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
//      and again on every foreground transition. Those calls are
//      SELECT-only (cheap): they hydrate an existing completed row and
//      NEVER trigger a paid LLM generation.
//    - `refresh(generateIfMissing: true)` additionally POSTs to
//      `coaching-daily-read` with `triggered_by = "manual"` when no
//      completed row exists. Only a mounted, user-visible Read surface
//      should pass this flag — generation is a real Gemini call.
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

    /// The athlete's replies to TODAY's read — check-in rows stamped with
    /// `replied_to_read_id` (migration 20260831170000). Rendered under the
    /// Read's check-in block so the question shows its own answers. Refreshed
    /// alongside the read, and by the view after each new reply lands.
    var todayReplies: [CoachReadReply] = []

    /// The week band under the masthead — every Read is an edition of a
    /// week and says so (Fig. 12). Label + "WK n · m MI", computed from the
    /// read's own week (Monday-start, same convention as the journal).
    var readWeek: ReadWeekBand?

    // MARK: - Init

    private init() {}

    // MARK: - Public API

    /// Fetch today's Read from the database. By default this is a cheap
    /// SELECT-only refresh; pass `generateIfMissing: true` to POST to the
    /// edge function (a paid LLM call) when no completed row exists.
    ///
    /// COST (2026-08-13): the default flipped from generate-always to
    /// SELECT-only. This method runs on every app launch and every
    /// foreground transition, and the Read surface (CoachReadView) is
    /// currently unmounted — so the old behavior generated a paid
    /// frontier-model Read on a dark surface, dozens of times a day
    /// during development ($7/day Gemini bills). Only a surface the user
    /// is actually looking at should pass `generateIfMissing: true`.
    @MainActor
    func refresh(generateIfMissing: Bool = false) async throws {
        guard let userId = AuthManager.shared.currentUserId else {
            Log.coachRead.info("refresh() skipped — no signed-in user")
            return
        }
        isLoading = true
        defer { isLoading = false }

        do {
            guard let read = try await fetchOrGenerateTodayRead(
                userId: userId,
                generateIfMissing: generateIfMissing
            ) else {
                // No completed Read for today and generation not requested.
                // Keep whatever we had; this is the normal launch path.
                lastError = nil
                return
            }
            todayRead = read
            try await hydrate(read: read)
            await reloadReplies()
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

    /// Fetch the replies stamped against today's read. Slim select — the
    /// reply line needs a timestamp, the declared mood, and the words; it
    /// never drags the full TrainingLog row (see TrainingLog.columns note).
    @MainActor
    func reloadReplies() async {
        guard let read = todayRead else {
            todayReplies = []
            return
        }
        do {
            let replies: [CoachReadReply] = try await supabase
                .from("training_logs")
                .select("id, created_at, mood, cleaned_notes, notes, audio_url, processing_status")
                .eq("replied_to_read_id", value: read.id.uuidString)
                .order("created_at", ascending: true)
                .execute()
                .value
            todayReplies = replies
        } catch {
            // Replies are an annotation on the read, never a gate on it —
            // keep whatever we had rather than blanking the list.
            Log.coachRead.error("reloadReplies failed: \(error.localizedDescription)")
        }
        await loadWeekBand(for: read)
    }

    /// Compute the masthead week band for the read's own Monday-start week:
    /// label ("THE WEEK OF AUG 24 – 30"), ISO week number, and the week's
    /// deduped mileage. Best-effort — a fetch miss drops the mileage from
    /// the band, never the band itself.
    @MainActor
    private func loadWeekBand(for read: CoachRead) async {
        // THE WEEK A READ COVERS = the seven days ENDING on its own date.
        // For the Sunday weekly edition that is exactly the Mon–Sun training
        // week (Aug 24–30); for a read published any other day it is still
        // the seven days it can actually speak about. Anchoring on the
        // calendar week *containing* read_date instead put a Monday read on a
        // fresh week that had barely happened yet.
        let cal = Calendar.current
        let end = cal.startOfDay(for: read.readDate)
        guard
            let start = cal.date(byAdding: .day, value: -6, to: end),
            let afterEnd = cal.date(byAdding: .day, value: 1, to: end)
        else { return }

        let startM = start.formatted(.dateTime.month(.abbreviated)).uppercased()
        let endM = end.formatted(.dateTime.month(.abbreviated)).uppercased()
        let startD = cal.component(.day, from: start)
        let endD = cal.component(.day, from: end)
        let range = startM == endM
            ? "\(startM) \(startD) – \(endD)"
            : "\(startM) \(startD) – \(endM) \(endD)"
        let wk = Calendar(identifier: .iso8601).component(.weekOfYear, from: start)

        var miles: Double?
        if let userId = AuthManager.shared.currentUserId {
            struct Row: Decodable {
                let workoutDate: Date?
                let miles: Double?
                let source: String?
                enum CodingKeys: String, CodingKey {
                    case workoutDate = "workout_date"
                    case miles = "workout_distance_miles"
                    case source
                }
            }
            let rows: [Row] = (try? await supabase
                .from("training_logs")
                .select("workout_date, workout_distance_miles, source")
                .eq("user_id", value: userId)
                .gte("workout_date", value: start.ISO8601Format())
                .lt("workout_date", value: afterEnd.ISO8601Format())
                .execute()
                .value) ?? []
            // Same-day voice/GPS dedupe, same rule as the journal's week totals.
            let runs = rows.filter { ($0.miles ?? 0) > 0 && $0.workoutDate != nil }
            var gpsByDay: [Date: [Double]] = [:]
            for r in runs where r.source != "voice_log" && r.source != "check_in" {
                gpsByDay[cal.startOfDay(for: r.workoutDate!), default: []].append(r.miles ?? 0)
            }
            var total = 0.0
            for r in runs {
                if r.source == "voice_log" || r.source == "check_in",
                   let sameDay = gpsByDay[cal.startOfDay(for: r.workoutDate!)],
                   sameDay.contains(where: { abs($0 - (r.miles ?? 0)) <= 0.3 }) {
                    continue
                }
                total += r.miles ?? 0
            }
            miles = total
        }

        readWeek = ReadWeekBand(
            label: "THE WEEK OF \(range)",
            detail: miles.map { "WK \(wk) · \(String(format: "%.1f", $0)) MI" } ?? "WK \(wk)"
        )
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
                } else if container.contains(AnyCodingKey("response")) {
                    // Chat-shaped fallback. coaching-agent returns its plain
                    // chat envelope ({ response, model, provider, ... }) instead
                    // of the editorial { read } when the request didn't reach
                    // the editorial branch (older deploy, or a build that didn't
                    // send format:"editorial"). Synthesize a CoachRead from the
                    // answer text so the ask surface renders instead of showing
                    // "Couldn't reach the coach" on a perfectly good 200.
                    let text = (try? container.decode(String.self, forKey: AnyCodingKey("response"))) ?? ""
                    self.read = CoachRead.fromPlainText(text)
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
    private func fetchOrGenerateTodayRead(
        userId: String,
        generateIfMissing: Bool
    ) async throws -> CoachRead? {
        let today = Self.deviceLocalDateString()

        // 1. Cheap path: SELECT the completed row for today via the
        //    typed Supabase Swift client. RLS scopes this to the
        //    signed-in user via the client's bearer token.
        //
        //    Decode the raw response with `JSONDecoder.coachRead()`, NOT
        //    the SDK's default `.value` decoder. `read_date` is a DATE
        //    column ("2026-05-19"), and the SDK decoder
        //    (`JSONDecoder.supabase()`) only parses ISO-8601 *timestamps*
        //    — it throws `dataCorrupted` on a date-only string, so the
        //    typed `.value` path failed on every load and silently fell
        //    through to the expensive generate path below. (TrainingLog's
        //    `workout_date` decodes fine via `.value` only because it's
        //    TIMESTAMPTZ, not DATE — they are not the same path.)
        do {
            // THE CURRENT EDITION, NOT STRICTLY TODAY'S ROW (2026-08-31).
            // The Read is weekly: one edition, published Sunday, that the
            // athlete converses with all week. Keying this to `read_date =
            // today` meant Monday morning showed an empty surface and — worse
            // — every reply stamped with `replied_to_read_id` pointed at an
            // edition the tab had already stopped displaying, so the answers
            // vanished the next day. Take the most recent completed read
            // within the last 8 days instead; the window is what keeps a
            // months-old read from resurfacing on a dormant account.
            let windowStart = Self.dateString(daysAgo: 8)
            let response = try await supabase
                .from("daily_coaching_reads")
                .select("*")
                .eq("user_id", value: userId)
                .gte("read_date", value: windowStart)
                .eq("status", value: "completed")
                .order("read_date", ascending: false)
                .limit(1)
                .execute()
            let rows = try JSONDecoder.coachRead().decode(
                [CoachRead].self,
                from: response.data
            )
            if let read = rows.first {
                return read
            }
        } catch {
            // SELECT failure: only fall through to the generate path when the
            // caller explicitly asked for generation. The old behavior
            // ("SELECT failed → generate") turned transient network/decoding
            // errors into paid LLM calls on every foreground.
            Log.coachRead.warning(
                "SELECT failed (\(error.localizedDescription))"
            )
        }

        guard generateIfMissing else { return nil }

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
        dateString(daysAgo: 0)
    }

    /// `yyyy-MM-dd`, N days back in device-local time. Backs the current-
    /// edition window in `fetchOrGenerateTodayRead`.
    private static func dateString(daysAgo: Int) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .iso8601)
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        return f.string(from: date)
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

// MARK: - CoachReadReply

/// One reply to a Read — the slim projection of a check-in row that the
/// Read surface lists under its own question. Kept separate from
/// `TrainingLog` so the reply fetch never widens into the full journal row.
struct CoachReadReply: Decodable, Identifiable {
    let id: UUID
    let createdAt: Date
    let mood: String?
    let cleanedNotes: String?
    let notes: String?
    let audioUrl: String?
    let processingStatus: String?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case mood
        case cleanedNotes = "cleaned_notes"
        case notes
        case audioUrl = "audio_url"
        case processingStatus = "processing_status"
    }

    /// The line the Read renders: declared mood first, then the words —
    /// or the honest in-between states while audio is still processing.
    var summaryLine: String {
        let words = (cleanedNotes ?? notes ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let moodPart = (mood ?? "").trimmingCharacters(in: .whitespaces)
        let pending = processingStatus == "pending"
            || processingStatus == "processing"
            || processingStatus == "uploading"
        if pending && words.isEmpty {
            return moodPart.isEmpty
                ? "Transcribing…"
                : "\(moodPart.capitalized) — transcribing…"
        }
        if words.isEmpty { return moodPart.capitalized }
        if moodPart.isEmpty { return "\u{201C}\(words)\u{201D}" }
        return "\(moodPart.capitalized) — \u{201C}\(words)\u{201D}"
    }
}

// MARK: - ReadWeekBand

/// The masthead week band — the line that makes a Read an edition of a
/// week ("THE WEEK OF AUG 24 – 30" · "WK 35 · 74.9 MI"). See Fig. 12.
struct ReadWeekBand: Equatable {
    let label: String
    let detail: String
}
