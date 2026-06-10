//
//  PaceZonesService.swift
//  RunningLog
//
//  Singleton cache of the current user's pace zones, fetched from the
//  `get-pace-zones` edge function. THE single iOS-side source of truth for
//  what paces to display — no view, view-model, or service should compute
//  paces locally. If you need a pace, read it from `zones`.
//
//  Lifecycle:
//    - `refresh()` is called once at app launch from RunningLogApp.
//    - `scheduleRefresh()` coalesces bursts of training_logs inserts behind
//      a 30-second debounce so we don't hammer the endpoint.
//    - The result is NOT persisted to SwiftData. The edge function owns the
//      truth; we keep the latest snapshot in memory.
//
//  Design parallel: mirrors AthletePaceProfileService. Both fetch from edge
//  functions, both are @Observable singletons, both debounce refreshes.
//  The difference: AthletePaceProfileService surfaces the raw stored pace
//  anchors; PaceZonesService surfaces the engine-computed zones used by UI.
//

import Foundation
import os

@Observable
final class PaceZonesService {
    static let shared = PaceZonesService()

    /// Latest pace zones for the signed-in user. Nil until first refresh
    /// succeeds, or when no source data exists yet.
    var zones: PaceZonesEngine?

    /// True while a refresh is in flight.
    var isRefreshing = false

    /// Human-readable reason the last refresh failed, if any. Cleared on success.
    var lastErrorMessage: String?

    private var refreshDebounceTask: Task<Void, Never>?
    private static let debounceSeconds: UInt64 = 30

    private init() {}

    /// Fetch the latest pace zones from the get-pace-zones edge function and
    /// replace the in-memory cache. Throws on network / decode errors; a 404
    /// (no source data yet) is treated as "clear the zones and return quietly."
    @MainActor
    func refresh() async throws {
        guard AuthManager.shared.currentUserId != nil else {
            Log.paceProfile.info("PaceZonesService.refresh() skipped — no signed-in user")
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            // The JWT identifies the user; the empty body keeps service-role
            // cross-call semantics open without spoofing risk.
            let data = try await callEdgeFunction(name: "get-pace-zones", body: [:])
            let decoded = try JSONDecoder().decode(PaceZonesEngine.self, from: data)
            zones = decoded
            lastErrorMessage = nil
            let observedSessions = decoded.observedEasy?.sessionCount ?? 0
            Log.paceProfile.info(
                "Pace zones refreshed (source=\(decoded.primarySource, privacy: .public), MP=\(decoded.marathon?.pace ?? 0, privacy: .public)s/mi, observedEasySessions=\(observedSessions, privacy: .public))"
            )
        } catch let EdgeFunctionError.httpError(status, _, message) where status == 404 {
            zones = nil
            lastErrorMessage = nil
            Log.paceProfile.info("No source data for pace zones — cleared (404: \(message))")
        } catch {
            lastErrorMessage = error.localizedDescription
            Log.paceProfile.error("Pace zones refresh failed: \(error.localizedDescription)")
            throw error
        }
    }

    /// Debounced refresh. Call after any training_logs insert; bursts within
    /// 30s coalesce into one trailing refresh.
    @MainActor
    func scheduleRefresh() {
        refreshDebounceTask?.cancel()
        refreshDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.debounceSeconds * 1_000_000_000)
            if Task.isCancelled { return }
            try? await self?.refresh()
        }
    }
}
