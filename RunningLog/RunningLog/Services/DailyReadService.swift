//
//  DailyReadService.swift
//  RunningLog
//
//  Singleton cache + fetcher for the daily Coach Read. Named to avoid
//  collision with the existing `CoachReadService` in
//  Training/CoachReadCard.swift, which is a different aggregator for
//  the Training Plan view (coaching_adjustments + ai_insights + heat
//  warnings). They share the colloquial name "Coach's Read" but cover
//  unrelated surfaces.
//
//  The Coach tab
//  observes `todayRead` (and the hydration caches) to render the
//  morning Read without any extra round-trips for chip rendering.
//
//  Phase 2.2 of coach-the-read-prompts.md.
//
//  Lifecycle:
//    - `refresh()` is called once at app launch from `RunningLogApp`
//      and again on every foreground transition.
//    - `refresh()` first SELECTs the completed `daily_coaching_reads`
//      row for today (cheap, RLS-scoped to the user via the Supabase
//      Swift client). On a miss it POSTs to `coaching-daily-read` with
//      `triggered_by = "manual"` to generate one.
//    - After the Read lands, the service issues two parallel
//      `IN (…)` queries to hydrate every cited workout and doc into
//      `workoutsById` / `docsById`, so the SwiftUI chip components
//      render without their own fetch.
//
//    - `ask(_:)` POSTs to `coaching-agent` with a new `format = "editorial"`
//      flag (the agent-side handling lands in Phase 4.2). Returns the
//      reply as a `CoachRead`-shaped value; does NOT mutate `todayRead`.
//      The reply view owns its own state in Phase 4.
//

import Foundation
import os
import Supabase

@Observable
final class DailyReadService {
    static let shared = DailyReadService()

    // MARK: - Observable state

    /// The most recently fetched Coach Read for today. Nil until the
    /// first successful refresh.
    var todayRead: CoachRead?

    /// True while a refresh is in flight. Views can render a skeleton
    /// state while this is true and `todayRead` is nil.
    var isLoading = false

    /// The last refresh error, if any. Cleared on success.
    var lastError: Error?

    /// Hydrated workouts keyed by id — every UUID in
    /// `todayRead?.sources.workouts` and every `.workout(workoutId:)`
    /// segment in `todayRead?.paragraph` is present after a successful
    /// refresh. The Read view reads from this cache to render `◆`
    /// workout chips without a second fetch.
    var workoutsById: [UUID: TrainingLog] = [:]

    /// Hydrated knowledge docs keyed by id — same contract as
    /// `workoutsById`, but for `§` doc chips.
    var docsById: [UUID: CoachingDocument] = [:]

    // MARK: - Init

    private init() {}

    // MARK: - Public API

    /// Fetch today's Read from the database; generate one via the edge
    /// function if no completed row exists for today. Then hydrate the
    /// referenced workouts and docs into the in-memory caches.
    ///
    /// Safe to call repeatedly — re-runs are cheap when a completed
    /// row exists for today (one SELECT, two `IN` queries).
    @MainActor
    func refresh() async throws {
        guard let userId = AuthManager.shared.currentUserId else {
            Log.coachRead.info("refresh() skipped — no signed-in user")
            return
        }
        isLoading = true
        defer { isLoading = false }

        do {
            let read = try await fetchOrGenerateTodayRead(userId: userId)
            todayRead = read
            try await hydrate(read: read)
            lastError = nil
            Log.coachRead.info(
                "Read refreshed (id=\(read.id.uuidString, privacy: .public), confidence=\(read.confidence.level.rawValue, privacy: .public))"
            )
        } catch {
            lastError = error
            Log.coachRead.error("refresh failed: \(error.localizedDescription)")
            throw error
        }
    }

    /// Ask the coach a follow-up question. Returns a `CoachRead`-shaped
    /// reply; does NOT mutate `todayRead`. The Phase 4 reply view owns
    /// its own state.
    ///
    /// Backend support for `format = "editorial"` lands in Phase 4.2;
    /// shipping the service flag now lets the iOS view code be wired
    /// up against a stable signature.
    @MainActor
    func ask(_ question: String) async throws -> CoachRead {
        guard let userId = AuthManager.shared.currentUserId else {
            throw URLError(.userAuthenticationRequired)
        }
        Log.coachRead.info("ask() — \(question.count) chars")
        let data = try await callEdgeFunction(
            name: "coaching-agent",
            body: [
                "user_id": userId,
                "message": question,
                "format": "editorial",
            ]
        )
        // The Phase 4.2 response shape wraps the Read alongside `you`
        // and `related_ask` siblings; for now we only need the Read
        // itself. Extra fields are silently ignored by Codable.
        struct AskEnvelope: Decodable {
            let read: CoachRead?
            // Some endpoints may inline the read fields at the top
            // level rather than nesting under `read`. Try both.
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: AnyCodingKey.self)
                if container.contains(AnyCodingKey("read")) {
                    self.read = try container.decode(
                        CoachRead.self,
                        forKey: AnyCodingKey("read")
                    )
                } else {
                    self.read = try CoachRead(from: decoder)
                }
            }
        }
        let envelope = try JSONDecoder.coachRead().decode(AskEnvelope.self, from: data)
        guard let read = envelope.read else {
            throw URLError(.cannotParseResponse)
        }
        return read
    }

    // MARK: - Fetch / generate

    @MainActor
    private func fetchOrGenerateTodayRead(userId: String) async throws -> CoachRead {
        let today = Self.deviceLocalDateString()

        // 1. Cheap path: SELECT the completed row for today via the
        //    typed Supabase Swift client. RLS scopes this to the
        //    signed-in user via the client's bearer token. The SDK's
        //    default decoder handles both the date-only `read_date`
        //    and the ISO-8601 `generated_at` (the same path TrainingLog
        //    relies on for its DATE-column `workout_date` field).
        do {
            let rows: [CoachRead] = try await supabase
                .from("daily_coaching_reads")
                .select("*")
                .eq("user_id", value: userId)
                .eq("read_date", value: today)
                .eq("status", value: "completed")
                .limit(1)
                .execute()
                .value
            if let read = rows.first {
                return read
            }
        } catch {
            // Don't bail on a SELECT failure — fall through to the
            // generate path. The edge function call is the canonical
            // recovery: it'll write the row server-side and return it.
            Log.coachRead.warning(
                "SELECT failed (\(error.localizedDescription)) — falling back to generate"
            )
        }

        // 2. Generate path: POST to the edge function. It short-
        //    circuits on completed rows internally — so even if our
        //    device-local "today" disagrees with the server's
        //    profile-tz-resolved "today" (e.g. during travel), we
        //    still get whichever Read the server considers current.
        let data = try await callEdgeFunction(
            name: "coaching-daily-read",
            body: ["user_id": userId, "triggered_by": "manual"]
        )
        struct GenerateResponse: Decodable { let read: CoachRead }
        let response = try JSONDecoder.coachRead().decode(
            GenerateResponse.self,
            from: data
        )
        return response.read
    }

    // MARK: - Hydration

    @MainActor
    private func hydrate(read: CoachRead) async throws {
        // Collect every workout/doc id the Read references — both from
        // `sources` AND from inline paragraph segments, in case the
        // model populated one but not the other.
        var workoutIds = Set(read.sources.workouts)
        var docIds = Set(read.sources.docs)
        for seg in read.paragraph {
            switch seg {
            case .workout(let id): workoutIds.insert(id)
            case .doc(let id): docIds.insert(id)
            case .text: break
            }
        }

        // Freeze to immutable arrays before crossing the async boundary —
        // Swift 6 strict concurrency rejects capturing `var` by reference
        // inside the implicit concurrent task that `async let` spawns.
        let workoutIdList = Array(workoutIds)
        let docIdList = Array(docIds)
        async let workouts: [TrainingLog] = fetchWorkouts(ids: workoutIdList)
        async let docs: [CoachingDocument] = fetchDocs(ids: docIdList)
        let (resolvedWorkouts, resolvedDocs) = try await (workouts, docs)

        var nextWorkouts: [UUID: TrainingLog] = [:]
        for w in resolvedWorkouts { nextWorkouts[w.id] = w }
        workoutsById = nextWorkouts

        var nextDocs: [UUID: CoachingDocument] = [:]
        for d in resolvedDocs { nextDocs[d.id] = d }
        docsById = nextDocs
    }

    private func fetchWorkouts(ids: [UUID]) async throws -> [TrainingLog] {
        guard !ids.isEmpty else { return [] }
        let rows: [TrainingLog] = try await supabase
            .from("training_logs")
            .select("*")
            .in("id", values: ids.map { $0.uuidString })
            .execute()
            .value
        return rows
    }

    private func fetchDocs(ids: [UUID]) async throws -> [CoachingDocument] {
        guard !ids.isEmpty else { return [] }
        let rows: [CoachingDocument] = try await supabase
            .from("coaching_documents")
            .select("id, title, category, content")
            .in("id", values: ids.map { $0.uuidString })
            .execute()
            .value
        return rows
    }

    // MARK: - Helpers

    /// "yyyy-MM-dd" in the device's current timezone. If the user's
    /// `user_profiles.timezone` matches their device (the typical
    /// case), this is also the server-side `read_date`. When they
    /// disagree (travel without profile update), the SELECT misses
    /// and we fall through to the generate-path POST, which uses the
    /// profile-tz date and is therefore authoritative.
    private static func deviceLocalDateString() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .iso8601)
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}

// MARK: - AnyCodingKey

/// Lightweight `CodingKey` used by `ask()`'s envelope decoder when it
/// needs to peek at a field name at runtime.
private struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }

    init(_ s: String) { self.stringValue = s }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}
