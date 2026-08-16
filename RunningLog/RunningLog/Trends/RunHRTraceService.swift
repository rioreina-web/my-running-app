//
//  RunHRTraceService.swift
//  RunningLog
//
//  Per-minute heart-rate traces for the runs on screen, from `run-hr-trace`.
//
//  WHY A SEPARATE SERVICE AND NOT PART OF THE TIMELINE. The source is the
//  per-second `external_streams` blob — the single largest thing in this
//  database and the one the 2026-08-10 performance audit says never to select.
//  `TrendsService` fetches 26 weeks; traces are only ever wanted for the 7 days
//  actually being looked at. Fetched here, on demand, for that week only.
//
//  CACHED BY LOG ID AND NEVER EVICTED WITHIN A SESSION. A trace is ~60 numbers
//  and a run's heart rate does not change after the fact, so paging back and
//  forth across a training block re-draws from memory rather than re-asking.
//  Twenty weeks of browsing is a few hundred small arrays.
//

import Foundation
import os

@Observable
final class RunHRTraceService {
    static let shared = RunHRTraceService()

    /// One run's trace: bpm per minute from the run's start, `nil` where the
    /// watch recorded nothing. The gaps are the point — see `Trace.segments`.
    struct Trace {
        let stepSec: Int
        let bpm: [Int?]

        /// Contiguous runs of readings, as (minuteIndex, bpm) pairs.
        ///
        /// The drawing code needs these rather than the raw array because a
        /// dropout has to BREAK the line. Joining across a gap would draw a
        /// heart rate through minutes nobody measured, which is the one thing
        /// an overlay whose whole value is that it was measured must not do.
        var segments: [[(minute: Int, bpm: Int)]] {
            var out: [[(minute: Int, bpm: Int)]] = []
            var current: [(minute: Int, bpm: Int)] = []
            for (i, v) in bpm.enumerated() {
                if let v { current.append((minute: i, bpm: v)) }
                else if !current.isEmpty { out.append(current); current = [] }
            }
            if !current.isEmpty { out.append(current) }
            return out
        }

        var range: (lo: Int, hi: Int)? {
            let vs = bpm.compactMap { $0 }
            guard let lo = vs.min(), let hi = vs.max() else { return nil }
            return (lo, hi)
        }
    }

    private(set) var traces: [UUID: Trace] = [:]
    private(set) var isLoading = false

    /// Ids already asked about — including ones that came back WITHOUT a trace.
    /// Without this, a week of runs that genuinely have no heart-rate stream
    /// would be re-requested on every appearance, forever.
    private var asked: Set<UUID> = []

    private init() {}

    /// Preview / test seam.
    init(preview: [UUID: Trace]) {
        self.traces = preview
        self.asked = Set(preview.keys)
    }

    @MainActor
    func load(_ ids: [UUID]) async {
        let missing = ids.filter { !asked.contains($0) }
        guard !missing.isEmpty else { return }
        asked.formUnion(missing)
        isLoading = true
        defer { isLoading = false }

        do {
            let data = try await withNetworkTimeout(seconds: 15) {
                try await callEdgeFunction(
                    name: "run-hr-trace",
                    body: ["log_ids": missing.map { $0.uuidString.lowercased() }]
                )
            }
            let payload = try JSONDecoder().decode(TracePayload.self, from: data)
            for (key, t) in payload.traces {
                guard let id = UUID(uuidString: key) else { continue }
                traces[id] = Trace(stepSec: t.step_sec, bpm: t.bpm)
            }
        } catch {
            // Additive: no trace is a drawable state, so a failure costs the
            // overlay and nothing else. The ids stay in `asked` on purpose —
            // retrying a failing endpoint once per redraw is how a chart turns
            // into a request storm.
            Log.coach.error("HR traces failed: \(error.localizedDescription)")
        }
    }

    private struct TracePayload: Decodable {
        struct Entry: Decodable {
            let step_sec: Int
            let bpm: [Int?]
        }
        let traces: [String: Entry]
    }
}
