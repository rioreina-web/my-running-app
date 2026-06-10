//
//  AthletePaceProfileService.swift
//  RunningLog
//
//  Singleton cache of the current user's AthletePaceProfile. Everything that
//  needs a "real" reference pace (easy, marathon, half, 10K, 5K, mile) reads
//  from here rather than re-deriving locally or — worse — falling back to a
//  hardcoded percentage string.
//
//  Lifecycle:
//    - refresh() is called once at app launch from RunningLogApp.
//    - scheduleRefresh() coalesces bursts of training_logs inserts behind a
//      30-second debounce so we don't hammer the edge function.
//    - The profile is NOT persisted to SwiftData. The edge function owns the
//      truth; we keep it in memory.
//

import Foundation
import os

@Observable
final class AthletePaceProfileService {
    static let shared = AthletePaceProfileService()

    /// Latest pace profile for the signed-in user. Nil until first refresh
    /// succeeds, or if no fitness_snapshot exists yet.
    var profile: AthletePaceProfile?

    /// True while a refresh is in flight. Views can surface a subtle spinner.
    var isRefreshing = false

    /// Human-readable reason the last refresh failed, if any. Cleared on success.
    var lastErrorMessage: String?

    private var refreshDebounceTask: Task<Void, Never>?
    private static let debounceSeconds: UInt64 = 30

    private init() {}

    /// Fetch the latest profile from the build-pace-profile edge function and
    /// replace the in-memory cache. Throws on network / decode errors; a 404
    /// (no fitness data) is treated as "clear the profile and return quietly."
    @MainActor
    func refresh() async throws {
        guard let userId = AuthManager.shared.currentUserId else {
            Log.paceProfile.info("refresh() skipped — no signed-in user")
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let data = try await callEdgeFunction(
                name: "build-pace-profile",
                body: ["user_id": userId]
            )
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decoded = try decoder.decode(AthletePaceProfile.self, from: data)
            profile = decoded
            lastErrorMessage = nil
            Log.paceProfile.info(
                "Pace profile refreshed (easy=\(decoded.easy?.secondsPerMile ?? 0, privacy: .public)s/mi)"
            )
        } catch let EdgeFunctionError.httpError(status, _, message) where status == 404 {
            // User has no fitness_snapshot yet — not an error, just empty.
            profile = nil
            lastErrorMessage = nil
            Log.paceProfile.info("No fitness data for user — profile cleared (404: \(message))")
        } catch {
            lastErrorMessage = error.localizedDescription
            Log.paceProfile.error("Pace profile refresh failed: \(error.localizedDescription)")
            throw error
        }
    }

    /// Debounced refresh. Call this after any training_logs insert; bursts
    /// within 30s coalesce into a single trailing refresh.
    @MainActor
    func scheduleRefresh() {
        refreshDebounceTask?.cancel()
        refreshDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.debounceSeconds * 1_000_000_000)
            if Task.isCancelled { return }
            try? await self?.refresh()
        }
    }

    /// Returns the cached reference pace in seconds/mile, or nil if the profile
    /// or that specific pace is unavailable.
    ///
    /// Accepts: "easy", "mile", "5K", "10K", "half", "marathon". Case-insensitive.
    func paceSeconds(for referenceDistance: String) -> Double? {
        profile?.pace(for: referenceDistance)?.secondsPerMile
    }
}
