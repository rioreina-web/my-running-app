//
//  SignalService.swift
//  RunningLog
//
//  Real data source for the Signal (pace-spectrum Trends) surface. Loads
//  the athlete's `training_logs`, buckets each run into pace zones using the
//  live `PaceZonesEngine`, and produces:
//    • `days`  — one continuous entry per calendar day (rest days empty),
//                each carrying miles-per-pace-zone (`comp`) and mood.
//    • `acwr`  — real 7-day-acute ÷ 28-day-chronic load, aligned to `days`.
//    • `dist`  — a pace-distribution histogram (miles per pace bucket),
//                over the athlete's real slow→fast pace bounds.
//
//  Zone assignment: when a run has `pace_segments` (per-mile / per-lap
//  splits from watch data) each segment is bucketed by its own pace, so a
//  workout reads as easy-shell + fast-work in one day's bar. Runs without
//  segments fall back to their whole-run average pace (single zone).
//
//  Reuses the existing `TrainingLog` / `PaceSegment` models and the shared
//  `supabase` client — no new table or edge function (respects the RLS +
//  migration hard rules). Niggles are not wired yet (0) — that's the next
//  step (from `body_mentions`).
//

import Foundation
import Observation
import os
import Supabase

/// One calendar day of running for the Signal chart.
struct SignalDay: Identifiable {
    let id = UUID()
    let date: Date
    /// (zone index into PaceSpectrum.stops, miles). Empty == rest day.
    let comp: [(zone: Int, mi: Double)]
    let mood: String?
    let niggles: Int
    /// e.g. "left calf" — the athlete's own body-area words, for the tap view.
    let niggleLabel: String?
    /// Miles per fine pace bucket (`SignalService.bucketCount` entries) for
    /// THIS day. Kept so the spectrum histogram can be summed over any range
    /// window without re-fetching. Empty == not computed (e.g. preview).
    var paceBuckets: [Double] = []
    var miles: Double { comp.reduce(0) { $0 + $1.mi } }
}

/// A body mention (niggle) as stored in `body_mentions`. Detection-not-
/// diagnosis: we carry the athlete's words and area, never interpret them.
private struct BodyMentionRow: Decodable {
    let body_area: String?
    let side: String?
    let mentioned_at: String?   // "yyyy-MM-dd"
}

@Observable
final class SignalService {
    static let shared = SignalService()

    private(set) var days: [SignalDay] = []
    private(set) var acwr: [Double] = []
    private(set) var dist: [Double] = Array(repeating: 0, count: SignalService.bucketCount)
    private(set) var distSlow: Double = 540
    private(set) var distFast: Double = 330
    private(set) var isLoading = false
    private(set) var loaded = false
    private(set) var lastError: String?

    static let bucketCount = 18
    private static let historyDays = 400   // enough to seed 28-day chronic for a year window

    private init() {}

    /// Preview / test seam.
    init(previewDays: [SignalDay], acwr: [Double], dist: [Double], slow: Double, fast: Double) {
        self.days = previewDays
        self.acwr = acwr
        self.dist = dist
        self.distSlow = slow
        self.distFast = fast
        self.loaded = true
    }

    // MARK: - Refresh

    @MainActor
    func refresh(zones: PaceZonesEngine?, force: Bool = false) async {
        if loaded && !force { return }
        guard let zones, let bounds = Self.paceBounds(zones) else {
            // No zones yet → nothing to classify against.
            days = []; acwr = []; loaded = false
            return
        }
        isLoading = true
        defer { isLoading = false }

        let anchors = Self.anchorTable(zones)   // (zone index, pace sec/mi), slow→fast
        guard anchors.count >= 2 else { days = []; loaded = false; return }

        do {
            let start = Calendar.current.date(byAdding: .day, value: -Self.historyDays, to: Date()) ?? Date()
            let rows: [TrainingLog] = try await supabase
                .from("training_logs")
                .select("id, created_at, mood, workout_date, workout_distance_miles, workout_duration_minutes, workout_pace_per_mile, workout_type, source, pace_segments")
                .gte("workout_date", value: ISO8601DateFormatter().string(from: start))
                .order("workout_date", ascending: true)
                .limit(2000)
                .execute()
                .value

            // Niggles (body_mentions). Non-fatal — if this fails the chart
            // still renders, just without the coral flags.
            let niggleByDay = await Self.loadNiggles(since: start)

            let result = Self.build(rows: rows, anchors: anchors, slow: bounds.slow, fast: bounds.fast, niggleByDay: niggleByDay)
            self.days = result.days
            self.acwr = result.acwr
            self.dist = result.dist
            self.distSlow = result.slow
            self.distFast = result.fast
            self.loaded = true
            self.lastError = nil
            Log.coach.info("Signal loaded (\(result.days.count) days, \(result.days.filter { !$0.comp.isEmpty }.count) run days)")
        } catch {
            self.lastError = error.localizedDescription
            Log.coach.error("Signal load failed: \(error.localizedDescription)")
        }
    }

    /// Fetch body_mentions and collapse to a per-day (count, label) map.
    @MainActor
    private static func loadNiggles(since start: Date) async -> [Date: (count: Int, label: String?)] {
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        let cal = Calendar.current
        var map: [Date: (count: Int, label: String?)] = [:]
        do {
            let rows: [BodyMentionRow] = try await supabase
                .from("body_mentions")
                .select("body_area, side, mentioned_at")
                .gte("mentioned_at", value: df.string(from: start))
                .order("mentioned_at", ascending: true)
                .limit(2000)
                .execute()
                .value
            for m in rows {
                guard let ds = m.mentioned_at, let parsed = df.date(from: ds) else { continue }
                let day = cal.startOfDay(for: parsed)
                var entry = map[day] ?? (0, nil)
                entry.count += 1
                if entry.label == nil {
                    let side = (m.side ?? "").trimmingCharacters(in: .whitespaces)
                    let area = m.body_area ?? "niggle"
                    entry.label = side.isEmpty ? area : "\(side) \(area)"
                }
                map[day] = entry
            }
        } catch {
            Log.coach.error("Signal niggles load failed: \(error.localizedDescription)")
        }
        return map
    }

    // MARK: - Build (pure, testable)

    private static func build(rows: [TrainingLog], anchors: [(zone: Int, pace: Double)], slow fallbackSlow: Double, fast fallbackFast: Double,
                              niggleByDay: [Date: (count: Int, label: String?)])
        -> (days: [SignalDay], acwr: [Double], dist: [Double], slow: Double, fast: Double) {

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var dayComp: [Date: [Int: Double]] = [:]
        var dayMood: [Date: String] = [:]
        // Raw (pace, miles) samples per day + overall. We bucket in a SECOND
        // pass, after fitting the histogram bounds to the paces actually run —
        // so the bars fill the width instead of wasting the empty slow/fast
        // ends. Zone assignment (`comp`) is anchor-based and bound-independent,
        // so it stays in this first pass.
        var daySamples: [Date: [(pace: Double, mi: Double)]] = [:]
        var allSamples: [(pace: Double, mi: Double)] = []

        for log in rows {
            guard let dist = log.workoutDistanceMiles, dist > 0.5,
                  let durMin = log.workoutDurationMinutes, durMin > 0 else { continue }
            // Running only — cross-training / strength don't belong on the pace spectrum.
            if let t = log.workoutType?.lowercased(),
               t.contains("strength") || t.contains("cross") || t.contains("rest") || t.contains("swim") || t.contains("bike") || t.contains("cycle") {
                continue
            }
            let day = cal.startOfDay(for: log.workoutDate ?? log.createdAt)

            // `isRest` splits what a segment counts toward. Standing/walking
            // recoveries between reps still count as VOLUME — they are miles
            // the athlete covered, and `comp` feeds daily miles and ACWR — but
            // they are not a PACE, so they stay out of the spectrum histogram.
            //
            // Since 2026-08-20 `pace_segments` comes from the watch's laps
            // rather than per-mile splits, so those recoveries now arrive as
            // their own rows tagged "recovery" instead of being averaged into
            // a mile. Over a real 4-week window that is 3.3 mi across 41 laps
            // at 17:00–75:00/mi. Bucketed, all of it clamps into the leftmost
            // bar and reads as easy running that never happened — and, worse,
            // it sits just under the 2% tail that `fittedBounds` trims, so one
            // extra interval week would drag the slow end of the axis out to
            // walking pace and squash every real bar into the left third.
            func add(_ zone: Int, _ mi: Double, _ paceSec: Double, isRest: Bool) {
                guard mi > 0, paceSec > 0 else { return }
                dayComp[day, default: [:]][zone, default: 0] += mi
                guard !isRest else { return }
                daySamples[day, default: []].append((paceSec, mi))
                allSamples.append((paceSec, mi))
            }

            if let segs = log.paceSegments, !segs.isEmpty,
               segs.reduce(0, { $0 + $1.distanceMiles }) > 0.3 {
                for s in segs {
                    let sd = s.distanceMiles
                    guard sd > 0 else { continue }
                    let paceSec = s.durationSeconds > 0 ? (s.durationSeconds / sd) : (paceSecFromString(s.pacePerMile) ?? 0)
                    guard paceSec > 0 else { continue }
                    add(classify(paceSec, anchors), sd, paceSec, isRest: isRestSegment(s))
                }
            } else {
                // No segments: the whole run at its average pace. Never a rest —
                // a logged run is running.
                let paceSec = (durMin * 60) / dist
                add(classify(paceSec, anchors), dist, paceSec, isRest: false)
            }

            if dayMood[day] == nil, let m = log.mood, !m.isEmpty { dayMood[day] = m }
        }

        // Fit the histogram bounds to the real paces, then bucket everything.
        let (slow, fast) = fittedBounds(allSamples, fallbackSlow: fallbackSlow, fallbackFast: fallbackFast)
        var buckets = Array(repeating: 0.0, count: bucketCount)
        var dayBuckets: [Date: [Double]] = [:]
        for (day, samples) in daySamples {
            var db = Array(repeating: 0.0, count: bucketCount)
            for s in samples where s.mi > 0 {
                if let b = bucket(s.pace, slow: slow, fast: fast) { db[b] += s.mi; buckets[b] += s.mi }
            }
            dayBuckets[day] = db
        }

        // Continuous daily array, oldest → newest.
        var out: [SignalDay] = []
        for k in 0..<historyDays {
            let d = cal.date(byAdding: .day, value: k - (historyDays - 1), to: today) ?? today
            let nig = niggleByDay[d]
            let dayBk = dayBuckets[d] ?? Array(repeating: 0.0, count: bucketCount)
            if let zmap = dayComp[d] {
                let comp = zmap.map { (zone: $0.key, mi: ($0.value * 10).rounded() / 10) }
                    .sorted { $0.zone < $1.zone }
                out.append(SignalDay(date: d, comp: comp, mood: dayMood[d], niggles: nig?.count ?? 0, niggleLabel: nig?.label, paceBuckets: dayBk))
            } else {
                out.append(SignalDay(date: d, comp: [], mood: nil, niggles: nig?.count ?? 0, niggleLabel: nig?.label, paceBuckets: dayBk))
            }
        }

        // Real ACWR from daily miles.
        let dailyMiles = out.map { $0.miles }
        let acwr: [Double] = dailyMiles.indices.map { j in
            let acute = dailyMiles[max(0, j - 6)...j].reduce(0, +)
            let chronicSlice = dailyMiles[max(0, j - 27)...j]
            let weeksSpan = Double(chronicSlice.count) / 7.0
            let chronic = weeksSpan > 0 ? chronicSlice.reduce(0, +) / weeksSpan : 0
            return chronic > 0 ? acute / chronic : 0
        }

        return (out, acwr, buckets, slow, fast)
    }

    /// Fit the spectrum's slow/fast bounds to the paces the athlete actually
    /// ran, so the 18 bars fill the width instead of leaving empty bars at the
    /// slow end and crushing every race zone into the fast tail.
    ///
    /// Uses miles-weighted 2nd/98th percentiles (so a single fast stride or a
    /// slow warm-up jog can't stretch the axis), pads the ends slightly, and
    /// clamps INSIDE the zone bounds so the range never claims paces the
    /// athlete's fitness doesn't support. Falls back to the zone bounds when
    /// there isn't enough data to fit.
    static func fittedBounds(_ samples: [(pace: Double, mi: Double)],
                             fallbackSlow: Double, fallbackFast: Double) -> (slow: Double, fast: Double) {
        let totalMi = samples.reduce(0) { $0 + $1.mi }
        guard samples.count >= 5, totalMi > 3 else { return (fallbackSlow, fallbackFast) }

        let sorted = samples.sorted { $0.pace < $1.pace }   // fastest (small sec) → slowest
        func weightedPercentile(_ p: Double) -> Double {
            let target = totalMi * p
            var cum = 0.0
            for s in sorted { cum += s.mi; if cum >= target { return s.pace } }
            return sorted.last?.pace ?? fallbackSlow
        }
        let pFast = weightedPercentile(0.02)   // near-fastest pace with real volume
        let pSlow = weightedPercentile(0.98)   // near-slowest

        let span = max(pSlow - pFast, 1)
        let pad = span * 0.04
        var slow = pSlow + pad
        var fast = pFast - pad

        // Never wider than the athlete's zone range (keeps anchors honest).
        slow = min(slow, fallbackSlow)
        fast = max(fast, fallbackFast)

        // Degenerate span (e.g. every run at one pace) → use zone bounds.
        guard slow - fast >= 30 else { return (fallbackSlow, fallbackFast) }
        return (slow, fast)
    }

    // MARK: - Pace helpers

    /// Recovery between reps, as tagged by the sync (`_shared/paceSegments.ts`,
    /// which mirrors `running_workout_laps.is_rest`). Matched on the effort tag
    /// rather than re-deriving a distance/speed threshold here: one rest rule,
    /// defined once, at the point the segment is written.
    static func isRestSegment(_ s: PaceSegment) -> Bool {
        s.effort.lowercased() == "recovery"
    }


    static func paceBounds(_ z: PaceZonesEngine) -> (slow: Double, fast: Double)? {
        guard let easyMid = z.easyMidpoint else { return nil }
        let fast = z.mile?.pace ?? z.fiveK?.pace ?? z.threeK?.pace ?? z.tenK?.pace
        guard let fastPace = fast else { return nil }
        let slow = z.easy?.paceSlow ?? (easyMid + 25)
        return (slow, fastPace)
    }

    /// (zone index, pace sec/mi) for every zone the engine can supply,
    /// slowest → fastest.
    static func anchorTable(_ z: PaceZonesEngine) -> [(zone: Int, pace: Double)] {
        var a: [(zone: Int, pace: Double)] = []
        if let e = z.easyMidpoint      { a.append((0, e)) }
        if let m = z.moderateMidpoint  { a.append((1, m)) }
        if let s = z.steadyMidpoint    { a.append((2, s)) }
        if let mp = z.marathon?.pace   { a.append((3, mp)) }
        if let hm = z.halfMarathon?.pace { a.append((4, hm)) }
        if let lt = z.thresholdPace    { a.append((5, lt)) }
        if let tk = z.tenK?.pace       { a.append((6, tk)) }
        if let fk = z.fiveK?.pace      { a.append((7, fk)) }
        if let threeK = z.threeK?.pace { a.append((8, threeK)) }
        if let mi = z.mile?.pace       { a.append((9, mi)) }
        return a.sorted { $0.pace > $1.pace }   // slow (big sec) → fast
    }

    /// Nearest-anchor zone for a pace.
    private static func classify(_ paceSec: Double, _ anchors: [(zone: Int, pace: Double)]) -> Int {
        guard var best = anchors.first else { return 0 }
        var bestD = abs(paceSec - best.pace)
        for a in anchors {
            let d = abs(paceSec - a.pace)
            if d < bestD { bestD = d; best = a }
        }
        return best.zone
    }

    private static func bucket(_ paceSec: Double, slow: Double, fast: Double) -> Int? {
        guard slow > fast else { return nil }
        let f = (slow - paceSec) / (slow - fast)
        let b = Int(f * Double(bucketCount))
        return min(max(b, 0), bucketCount - 1)
    }

    private static func paceSecFromString(_ s: String) -> Double? {
        let parts = s.split(separator: ":")
        guard parts.count == 2, let m = Double(parts[0]), let sec = Double(parts[1]) else { return nil }
        return m * 60 + sec
    }
}
