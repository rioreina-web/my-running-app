//
//  KeySessionStore.swift
//  RunningLog · Training
//
//  The single source of truth for "was this day a key session?" — holding all
//  three inputs `KeySessionMark` resolves between, for every day at once:
//
//      overrideByDay    the athlete's word        (day_overrides)
//      planIntentByDay  what the plan intended    (scheduled_workouts)
//      loadByDay        the derived stimulus      (Σ workout_features.quality_load)
//
//  ONE shared store rather than state on a view model, because four unrelated
//  surfaces need the same answer at the same moment: the calendar, the journal
//  feed, the day sheet where the mark is set, and the Trends session grid.
//  When each computed its own answer they disagreed constantly — the same
//  17-mile long run starred in the journal and not in the calendar, and a
//  stray fast 400m starred in the calendar and not in the journal. Making it
//  physically impossible for them to differ is the point of this file.
//
//  WRITE CONTRACT — mirrors `SleepCheckInPrompt.select(_:)` beat for beat,
//  because that is the write-through pattern that already works in this app:
//      optimistic local update → network → roll back locally on failure.
//  The star moves the instant you tap. If the write fails it reverts and logs.
//  No spinner, no dialog: it is one tap.
//
//  THREE STATES, and the middle one is load-bearing. `nil` (no row) means
//  "nothing said" and falls through. `false` means "I am telling you this was
//  NOT a key session" and is a real, persisted answer. Clearing sends a DELETE
//  — we never write null into `value`, or those two collapse into one and
//  "back to auto" becomes unreachable.
//

import Foundation
import Observation
import os
import Supabase

@Observable
final class KeySessionStore {

    /// Shared instance. Every surface reads this one, so a tap in the day
    /// sheet moves the star in the calendar and the journal at once.
    static let shared = KeySessionStore()

    /// The column name in `day_overrides.field`.
    private static let overrideField = "is_key_session"

    private let log = Logger(subsystem: "com.runninglog", category: "keysession")

    // MARK: - State (all keyed by local "yyyy-MM-dd")

    /// The athlete's answer. Absent = nothing said. Present false = explicitly
    /// not key.
    private(set) var overrideByDay: [String: Bool] = [:]

    /// The plan's intent, from `scheduled_workouts.is_key_session`. Ingested by
    /// `TrainingPlanService` once it has loaded the plan — this store does not
    /// fetch it, because the plan is already loaded elsewhere and refetching it
    /// is how two versions of the truth start.
    private(set) var planIntentByDay: [String: Bool] = [:]

    /// Derived stimulus per day: the SUM of `quality_load` across the day's
    /// DEDUPED physical workouts.
    ///
    /// Sum, not max: a doubles day uploaded as warmup + main is one stimulus
    /// split across two rows. Deduped first, because summing raw rows
    /// double-counts a cross-source duplicate (the same run from Strava AND
    /// HealthKit) straight over the floor.
    private(set) var loadByDay: [String: Double] = [:]

    private(set) var hasLoaded = false

    /// True once `loadByDay` has been filled from somewhere — the Train tab's
    /// analytics load, or `hydrateLoadsIfNeeded()` below. A flag rather than
    /// `loadByDay.isEmpty`, because an athlete with no scored days is a real
    /// answer and must not re-fetch on every tab entry.
    private(set) var hasIngestedLoads = false

    private init() {}

    // MARK: - Day keys
    //
    // `day_overrides.date` is a LOCAL date, matching daily_checkins. Formatting
    // in the current calendar (not UTC) is the whole contract — a run at 9pm
    // Central keys to that day, not tomorrow.

    static func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    // MARK: - The question every surface asks

    /// Is this day a key session? The one answer.
    func isKey(on date: Date) -> Bool {
        let key = Self.dayKey(date)
        return KeySessionMark.isKey(override: overrideByDay[key],
                                planIntent: planIntentByDay[key],
                                derived: derived(key),
                                isFuture: Self.isFuture(date))
    }

    /// Same question, but with the derived rule supplied BY THE CALLER.
    ///
    /// Used while `quality_load` is not yet persisted: each surface passes the
    /// rule it already had, so adding the override changes which days you can
    /// CORRECT without changing which days are starred by default. Without
    /// this, every existing star would vanish until the backfill ran.
    ///
    /// Once `workout_features.quality_load` is populated, callers move to
    /// `isKey(on:)` above and their old heuristics are deleted. This overload
    /// is the seam between those two states — and the only reason it exists.
    func isKey(on date: Date, derived: Bool?) -> Bool {
        let key = Self.dayKey(date)
        return KeySessionMark.isKey(override: overrideByDay[key],
                                    planIntent: planIntentByDay[key],
                                    derived: derived,
                                    isFuture: Self.isFuture(date))
    }

    /// Same question, for a surface that already holds a `"yyyy-MM-dd"` key
    /// rather than a `Date` (the Trends payload dates arrive as strings).
    ///
    /// ⚠️  Trends dates are the UTC day; `day_overrides` and the calendar use
    /// the LOCAL day. For this athlete's data they coincide, but a run logged
    /// late evening in a positive-UTC-offset zone would key differently on the
    /// two surfaces. Real, narrow, and worth fixing when the app goes wide —
    /// the fix is for trends-timeline to emit the local day.
    func isKey(onDayKey key: String) -> Bool {
        KeySessionMark.isKey(override: overrideByDay[key],
                             planIntent: planIntentByDay[key],
                             derived: derived(key),
                             isFuture: key > Self.dayKey(Date()))
    }

    /// Who decided — drives how the star is drawn.
    func provenance(on date: Date) -> KeySessionMark.Provenance {
        let key = Self.dayKey(date)
        return KeySessionMark.provenance(override: overrideByDay[key],
                                     planIntent: planIntentByDay[key])
    }

    /// The athlete's stored answer, or nil if they've said nothing.
    func override(on date: Date) -> Bool? { overrideByDay[Self.dayKey(date)] }

    /// Summed stimulus for the day, or nil if nothing was scored.
    func load(on date: Date) -> Double? { loadByDay[Self.dayKey(date)] }

    /// The derived rule, and the ONLY derived rule: does the day's summed
    /// stimulus clear `QualityLoad.floor` (25 weighted minutes)?
    ///
    /// Returns nil — not false — when the day has no score at all, so callers
    /// can tell "not enough work" from "not scored yet".
    ///
    /// If `quality_load` isn't available (pre-migration, or a session that
    /// never got features computed) this shows NO star rather than falling back
    /// to the old `split.threshold > 0` heuristic. A missing star is honest; a
    /// wrong star is the bug being fixed.
    private func derived(_ key: String) -> Bool? {
        guard let load = loadByDay[key] else { return nil }
        return QualityLoad.qualifies(load)
    }

    private static func isFuture(_ date: Date) -> Bool {
        Calendar.current.startOfDay(for: date) > Calendar.current.startOfDay(for: Date())
    }

    // MARK: - Read

    private struct OverrideRow: Decodable {
        let date: String
        let value: Bool      // JSONB true/false decodes straight to Bool
    }

    private struct FeatureLoadRow: Decodable {
        let training_log_id: UUID
        let quality_load: Double?
        let quality_kind: String?
    }

    /// Load the athlete's overrides. Called at launch and after auth settles.
    ///
    /// Degrades to an empty map on ANY failure, including the table not
    /// existing yet (pre-migration) — matching `RPERow.fetchRecent`. An empty
    /// override map just means nothing has been declared; it must never block
    /// the calendar from rendering.
    @MainActor
    func loadOverrides() async {
        guard let userId = AuthManager.shared.currentUserId else {
            overrideByDay = [:]
            hasLoaded = false
            return
        }
        do {
            let rows: [OverrideRow] = try await supabase
                .from("day_overrides")
                .select("date,value")
                .eq("user_id", value: userId)
                .eq("field", value: Self.overrideField)
                .execute()
                .value
            overrideByDay = Dictionary(rows.map { ($0.date, $0.value) },
                                       uniquingKeysWith: { a, _ in a })
            hasLoaded = true
        } catch {
            log.error("day_overrides load failed: \(error.localizedDescription)")
            overrideByDay = [:]
            hasLoaded = false
        }
    }

    /// Fold a set of ALREADY-DEDUPED logs and their persisted stimulus scores
    /// into `loadByDay`.
    ///
    /// The caller passes deduped logs because `LogDedup` is the canonical
    /// picker and reimplementing it here is how two answers start.
    /// `TrainingAnalyticsViewModel` dedupes before it calls in.
    ///
    /// Leaves `loadByDay` untouched on failure rather than zeroing it: a
    /// stale-but-real map beats an empty one.
    @MainActor
    func ingestLoads(forDedupedLogs logs: [TodayLogRow]) async {
        guard !logs.isEmpty else { return }
        let ids = logs.map(\.id.uuidString)
        let dateByLogId = Dictionary(logs.map { ($0.id, Self.dayKey($0.date)) },
                                     uniquingKeysWith: { a, _ in a })
        do {
            var out: [String: Double] = [:]
            // Chunked: `.in()` builds a URL query string, and 400 days of logs
            // would blow past the server's URL length limit in one request.
            var start = 0
            while start < ids.count {
                let chunk = Array(ids[start..<min(start + 200, ids.count)])
                let rows: [FeatureLoadRow] = try await supabase
                    .from("workout_features")
                    .select("training_log_id,quality_load,quality_kind")
                    .in("training_log_id", values: chunk)
                    .execute()
                    .value
                for row in rows {
                    guard let load = row.quality_load, load > 0,
                          let key = dateByLogId[row.training_log_id] else { continue }
                    out[key, default: 0] += load     // sum, not max — see loadByDay
                }
                start += 200
            }
            loadByDay = out
            hasIngestedLoads = true
        } catch {
            // Pre-migration, or features not computed yet. No derived stars,
            // which is the honest outcome.
            log.error("quality_load fetch failed: \(error.localizedDescription)")
        }
    }

    /// Fill `loadByDay` for a surface that needs the derived rule but does not
    /// own a log fetch of its own.
    ///
    /// WHY THIS EXISTS. `ingestLoads` was called from exactly one place —
    /// `TrainingAnalyticsViewModel`, i.e. the Train tab — so `loadByDay` was
    /// empty for anyone who opened Trends without visiting Train first. With no
    /// load, `derived(_:)` returns nil, `isKey` falls through to false, and the
    /// session grid drew every mark as an open "below floor" ring: a grid of
    /// hollow circles on an athlete with a block full of quality work. The
    /// store is shared; its hydration was not. (Rio, 2026-08-11.)
    ///
    /// It fetches nothing new in the common case: `TrainingLogStore` holds one
    /// 400-day window for the whole app, serves it from memory or disk, and
    /// coalesces concurrent refreshes — so on a launch where Log or Today has
    /// already asked, this is a cache read plus one `workout_features` query.
    ///
    /// Dedupe goes through `dedupedByPhysicalWorkout()`, the canonical picker,
    /// for the same reason the analytics VM uses it: raw rows double-count a
    /// run that arrived from both Strava and HealthKit, and a doubled day sails
    /// straight over the floor.
    @MainActor
    func hydrateLoadsIfNeeded() async {
        guard !hasIngestedLoads else { return }
        let store = TrainingLogStore.shared
        var rows = store.cachedRows(days: TrainingLogStore.windowDays)
        if rows.isEmpty {
            rows = (try? await store.refresh(days: TrainingLogStore.windowDays)) ?? []
        }
        guard !rows.isEmpty else { return }   // nothing logged yet; try again next visit
        await ingestLoads(forDedupedLogs: rows.dedupedByPhysicalWorkout())
    }

    /// Fold the plan's intent in. Called by `TrainingPlanService` once the
    /// plan's scheduled workouts are loaded.
    ///
    /// A day is intended-key if ANY session that day says so; intended-NOT-key
    /// only if a session says false and none says true. That asymmetry is
    /// deliberate — on a doubles day, one key session makes the day a key day.
    @MainActor
    func ingestPlanIntent(_ intents: [(date: Date, isKey: Bool?)]) {
        var out: [String: Bool] = [:]
        for intent in intents {
            guard let value = intent.isKey else { continue }
            let key = Self.dayKey(intent.date)
            out[key] = (out[key] ?? false) || value
        }
        planIntentByDay = out
    }

    // MARK: - Write

    private struct OverrideWrite: Encodable {
        let user_id: String
        let date: String
        let field: String
        let value: Bool
        let updated_at: String
    }

    /// Declare a day key (`true`) or explicitly not key (`false`).
    /// Optimistic; rolls back on failure.
    @MainActor
    func set(_ isKey: Bool, on date: Date) async {
        let key = Self.dayKey(date)
        let previous = overrideByDay[key]
        overrideByDay[key] = isKey               // optimistic; it's one tap

        guard let userId = AuthManager.shared.currentUserId else {
            overrideByDay[key] = previous
            return
        }
        let row = OverrideWrite(
            user_id: userId,
            date: key,
            field: Self.overrideField,
            value: isKey,
            updated_at: ISO8601DateFormatter().string(from: Date())
        )
        do {
            try await supabase
                .from("day_overrides")
                .upsert(row, onConflict: "user_id,date,field")
                .execute()
        } catch {
            log.error("day_overrides set failed: \(error.localizedDescription)")
            overrideByDay[key] = previous        // roll back the optimistic tap
        }
    }

    /// Back to auto — the athlete withdraws their answer and the derived rule
    /// takes over again.
    ///
    /// This DELETES the row. Writing `value = null` instead would make "back to
    /// auto" indistinguishable from "explicitly not key", which is the one
    /// ambiguity the schema exists to prevent. It is also why the migration
    /// ships a FOR DELETE policy: without it RLS drops the delete silently, the
    /// call reports success, zero rows change, and the override looks stuck on.
    @MainActor
    func clear(on date: Date) async {
        let key = Self.dayKey(date)
        let previous = overrideByDay[key]
        overrideByDay[key] = nil                 // optimistic

        guard let userId = AuthManager.shared.currentUserId else {
            overrideByDay[key] = previous
            return
        }
        do {
            try await supabase
                .from("day_overrides")
                .delete()
                .eq("user_id", value: userId)
                .eq("date", value: key)
                .eq("field", value: Self.overrideField)
                .execute()
        } catch {
            log.error("day_overrides clear failed: \(error.localizedDescription)")
            overrideByDay[key] = previous
        }
    }

    /// The tap cycle used by the day sheet: nothing said → key → not key →
    /// nothing said. Three taps returns you exactly where you started, which is
    /// the property that makes it safe to poke at.
    @MainActor
    func cycle(on date: Date) async {
        switch override(on: date) {
        case nil:          await set(true, on: date)
        case .some(true):  await set(false, on: date)
        case .some(false): await clear(on: date)
        }
    }
}
