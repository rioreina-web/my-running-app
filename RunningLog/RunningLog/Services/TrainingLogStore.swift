//
//  TrainingLogStore.swift
//  RunningLog
//
//  ONE fetch of `training_logs` shared by every surface that reads the
//  training history (Log tab, Today home, Train analytics), instead of the
//  three separate 90/180/400-day fetches those screens used to fire
//  (PERF-AUDIT-2026-08-10.md, findings #5 and #9).
//
//  How it works:
//  - The store holds the 400-day window — a superset of every consumer's
//    window. Consumers ask for the slice they need via `cachedRows(days:)`
//    / `refresh(days:)`.
//  - Stale-while-revalidate: `cachedRows` returns the last-known rows
//    (from memory, else from `DiskCache`) synchronously, so a screen can
//    render instantly; `refresh` then revalidates over the network and
//    persists the fresh snapshot for next launch.
//  - Concurrent refreshes coalesce: if Log, Today and Train all ask at
//    launch, exactly one network request runs and all three await it.
//
//  The disk payload embeds the userId it was fetched for. `cachedRows`
//  returns nothing when the signed-in user is known and doesn't match, and
//  sign-out clears the cache entirely (see AuthManager.signOut) — cached
//  rows must never cross accounts.
//

import Foundation

@MainActor
@Observable
final class TrainingLogStore {
    static let shared = TrainingLogStore()

    /// The superset window. 400 days covers every consumer (Train's block
    /// analytics is the widest) — see TrainingAnalyticsViewModel.
    static let windowDays = 400

    private static let cacheName = "training_logs_400d"

    /// Last-known rows, newest first. Never partially populated: either
    /// empty or a full snapshot of the 400-day window.
    private(set) var rows: [TodayLogRow] = []

    /// When the current `rows` snapshot was fetched from the network.
    /// Nil while only disk/empty data has been seen this session.
    private(set) var lastRefreshed: Date?

    private var hasTriedDisk = false
    private var inFlight: Task<[TodayLogRow], Error>?

    private struct CachePayload: Codable {
        let userId: String
        let savedAt: Date
        let rows: [TodayLogRow]
    }

    private init() {}

    // MARK: - Reads

    /// Last-known rows for the given window, synchronously — memory first,
    /// then one disk read per session. Empty when nothing (valid) is cached.
    /// Renders may trust this immediately; callers should still `refresh`.
    func cachedRows(days: Int) -> [TodayLogRow] {
        loadDiskOnce()
        return window(rows, days: days)
    }

    /// Fetch the 400-day window from the network (coalescing with any
    /// refresh already in flight), publish + persist it, and return the
    /// requested slice.
    func refresh(days: Int) async throws -> [TodayLogRow] {
        let all = try await refreshAll()
        return window(all, days: days)
    }

    // MARK: - Internals

    private func refreshAll() async throws -> [TodayLogRow] {
        if let task = inFlight {
            return try await task.value
        }
        let task = Task {
            try await TodayLogRow.fetchRecentThrowing(days: Self.windowDays)
        }
        inFlight = task
        defer { inFlight = nil }

        let fetched = try await task.value
        rows = fetched
        lastRefreshed = Date()
        DiskCache.save(
            CachePayload(userId: AuthManager.shared.userId, savedAt: Date(), rows: fetched),
            name: Self.cacheName
        )
        return fetched
    }

    private func loadDiskOnce() {
        guard rows.isEmpty, !hasTriedDisk else { return }
        hasTriedDisk = true
        guard let payload = DiskCache.load(CachePayload.self, name: Self.cacheName) else { return }
        // Account guard: if we already know who's signed in and it isn't
        // the user this snapshot belongs to, ignore it. (An empty userId
        // means auth hasn't resolved yet — the launch-restore path — where
        // the only plausible owner is the device's one account; the network
        // pass replaces the snapshot moments later either way.)
        let current = AuthManager.shared.userId
        guard current.isEmpty || current == payload.userId else { return }
        rows = payload.rows
    }

    private func window(_ all: [TodayLogRow], days: Int) -> [TodayLogRow] {
        guard days < Self.windowDays else { return all }
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
        return all.filter { $0.date >= cutoff }
    }
}
