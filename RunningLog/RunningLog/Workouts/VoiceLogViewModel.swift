import AVFoundation
import Foundation
import os
import Storage
import Supabase
import SwiftUI

/// Lightweight run row for the journal's per-week mileage subtotal — ALL runs
/// (not just authored entries), so the header reflects true weekly volume.
// Codable: cached to disk with the journal snapshot for instant re-launch
// rendering (see JournalCachePayload / DiskCache).
struct JournalMileageRow: Codable {
    let workoutDate: Date?
    let createdAt: Date
    let miles: Double?
    let source: String?
    enum CodingKeys: String, CodingKey {
        case workoutDate = "workout_date"
        case createdAt = "created_at"
        case miles = "workout_distance_miles"
        case source
    }
}

/// A body-part mention linked to a training_log. Detection, not diagnosis: we
/// carry the athlete's area + their own words, never a severity number or an
/// interpretation. Backs the journal row's niggle chips.
// Codable: cached to disk with the journal snapshot (niggle chips render
// from the snapshot too — a chip that vanished for a beat on every launch
// would read as data loss).
struct JournalNiggle: Codable, Identifiable {
    let id: UUID
    let trainingLogId: UUID?
    let bodyArea: String
    let side: String?
    let verbatimQuote: String?
    enum CodingKeys: String, CodingKey {
        case id
        case trainingLogId = "training_log_id"
        case bodyArea = "body_area"
        case side
        case verbatimQuote = "verbatim_quote"
    }
    /// "left calf" / "achilles" — the athlete's own words, chip-ready.
    var label: String {
        let s = (side ?? "").trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? bodyArea : "\(s) \(bodyArea)"
    }
}

@Observable
final class VoiceLogViewModel {
    var historyLogs: [TrainingLog] = []
    /// Bumped on every journal load. `historyLogs.count` is NOT a load signal:
    /// the refresh that matters most — a memo's `processing_status` going
    /// pending → transcribed → completed — replaces the array with the SAME
    /// number of rows, so a count-keyed observer never fires and a cached feed
    /// keeps rendering the stale "Transcribing" row forever (2026-09-04).
    /// Views that snapshot the feed into `@State` must watch this instead.
    private(set) var historyRevision = 0
    /// Niggles keyed by training_log_id (uppercased UUID string) — chips per row.
    var niggleByLog: [String: [JournalNiggle]] = [:]
    /// Every run in the recent window (all sources) for the week-header mileage
    /// totals — the journal FEED is authored-only, but the totals are complete.
    var weeklyMileageRows: [JournalMileageRow] = []
    var isLoadingHistory = false
    /// True when the last history load errored or auth never resolved. Lets the
    /// view show a "couldn't load — retry" state instead of the "No entries
    /// yet" empty state, so a transient failure never masquerades as an empty
    /// journal (the recurring "my logs disappeared" report).
    var loadFailed = false
    var isUploading = false
    var statusMessage = ""
    var showSuccessAnimation = false

    // MARK: - Upload Audio

    @MainActor
    func uploadAudioAndSaveLog(
        localURL: URL,
        selectedWorkout: RunningWorkout?,
        checkInManager: CoachCheckInManager
    ) async {
        // One save at a time. isUploading was set but never checked, so two
        // confirms in flight could insert two rows for one take.
        guard !isUploading else { return }
        // Insert-first (2026-08-31, latency Phase 2): the memo lands in the
        // journal BEFORE any audio bytes move. The old order — upload the
        // whole file through upload-voice-memo, then insert — held the UI
        // hostage to the athlete's post-run cell connection, which is exactly
        // when upload bandwidth is worst ("it never really uploads fast").
        // Now the row is inserted immediately at processing_status
        // "uploading" (renders as a normal pending entry), and the upload +
        // attach + processing all happen in a background task. The attach
        // UPDATE (audio_url + status -> "pending") is what arms the server
        // pipeline: the auto_process_voice_log_on_attach trigger enqueues the
        // outbox safety-net job, and we direct-invoke processing right after.
        isUploading = true
        statusMessage = "Saving..."

        let userId = AuthManager.shared.userId

        // --- Resolve the target row: an existing imported run, or a fresh insert ---
        // If this memo is for an already-imported run (Strava/HealthKit), the
        // GPS streams, splits, and parsed structure already live on THAT row.
        // Inserting a separate voice_log row creates a DUPLICATE: the journal
        // entry shows up empty ("no workout parsed") while the real workout
        // sits on the other row. So when the selected run has a known source
        // id, attach to its row instead of inserting.
        var targetRow: TrainingLog? = nil
        if let vid = selectedWorkout?.vitalWorkoutId, !vid.isEmpty {
            let existing: [TrainingLog]? = try? await supabase
                .from("training_logs")
                .select(TrainingLog.columns)
                .eq("user_id", value: userId)
                .eq("vital_workout_id", value: vid)
                .limit(1)
                .execute()
                .value
            targetRow = existing?.first
        }

        if targetRow == nil {
            // No existing run row matched — insert a fresh voice_log row NOW,
            // before the upload. audio_url intentionally NULL: it arrives via
            // the background attach. Status "uploading" (not "pending") so the
            // voice-processing trigger doesn't enqueue a job for a row with
            // nothing to process yet, and fn_enqueue_workout_insight doesn't
            // mistake an audio-less memo row for an insightable manual log.
            var insertData = TrainingLogInsert(audioUrl: nil)
            insertData.userId = userId
            insertData.processingStatus = "uploading"
            insertData.source = "voice_log"
            // ALWAYS stamp workout_date, even with no run selected. A NULL
            // here is not a harmless blank: four separate matchers key on
            // it — the sibling-GPS merge in process-training-memo, the
            // orphan lookup + pickBestOrphan in strava-sync, and the
            // journal's `order(workout_date, nullsFirst: false)` — so a
            // NULL-dated memo can never be reconciled with the run it
            // describes AND sinks to the bottom of the journal. That is
            // how 2026-08-24's memo silently detached from that morning's
            // Strava 10-miler. The recording time is the best available
            // proxy: a memo is recorded in the same session as the run,
            // which is exactly the ±4h window the matchers use.
            insertData.workoutDate = Date()
            if let workout = selectedWorkout {
                insertData.workoutDate = workout.startDate
                insertData.workoutDistanceMiles = workout.distanceMiles
                insertData.workoutDurationMinutes = workout.durationMinutes

                // Remove auto_sync duplicate
                let syncService = WorkoutSyncService()
                await syncService.removeAutoSyncEntry(forWorkoutDate: workout.startDate, distance: workout.distanceMiles)
            }

            do {
                let response: [TrainingLog] = try await supabase
                    .from("training_logs")
                    .insert(insertData)
                    .select(TrainingLog.columns)
                    .execute()
                    .value
                targetRow = response.first
            } catch {
                Log.app.error("Failed to insert voice log row: \(error)")
                // Data-loss guard: a voice memo is the core artifact of a
                // voice-first product. The row insert failed (offline, 5xx,
                // RLS) — hand the recording to the offline queue, whose
                // legacy path re-creates row + audio together on reconnect.
                OfflineQueueManager.shared.enqueueVoiceLog(
                    audioURL: localURL,
                    notes: nil,
                    mood: nil,
                    workoutDate: selectedWorkout?.startDate
                )
                statusMessage = "Saved — will finish uploading in the background."
                isUploading = false
                ErrorReporter.shared.report(error, context: "insert voice log row (queued for retry)")
                OfflineQueueManager.shared.drainQueue()
                return
            }
        }

        guard let row = targetRow else {
            // Neither attach target nor insert succeeded with a row back —
            // treat as insert failure (queued above only in the catch; this
            // guard is the decode-empty edge). Queue and bail.
            OfflineQueueManager.shared.enqueueVoiceLog(
                audioURL: localURL,
                notes: nil,
                mood: nil,
                workoutDate: selectedWorkout?.startDate
            )
            statusMessage = "Saved — will finish uploading in the background."
            isUploading = false
            OfflineQueueManager.shared.drainQueue()
            return
        }

        // --- The memo is in the journal. Show success NOW. ---
        isUploading = false
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            showSuccessAnimation = true
        }
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation { self.showSuccessAnimation = false }
        }
        await loadHistory()

        // --- Background: move the bytes, attach, process. ---
        //
        // Persist the attach intent HERE, synchronously, before the detached
        // task exists (2026-09-05). It used to be the first line inside
        // uploadAndAttach — which meant an app kill, or this view model being
        // torn down (the Log skin toggle swaps the whole view and its @State
        // VM), in the gap before that task ran left a row at "uploading" with
        // no audio_url, no intent, and no file reference: nothing on the
        // server or the client would ever retry it (autoRetryStaleRecords
        // skips audio-less rows). Now the intent is on disk the moment the
        // row exists, and the drain finishes the attach no matter what
        // happens to this process.
        let capturedRowId = row.id
        let ticket = OfflineQueueManager.shared.enqueueVoiceAttach(
            audioURL: localURL,
            recordId: capturedRowId.uuidString
        )
        Task { [weak self] in
            await self?.uploadAndAttach(
                localURL: localURL,
                rowId: capturedRowId,
                ticket: ticket,
                selectedWorkoutDate: selectedWorkout?.startDate,
                checkInManager: checkInManager
            )
        }
    }

    /// Background half of the insert-first flow: upload the audio, attach it
    /// to the already-visible row (audio_url + processing_status "pending" —
    /// which arms the server's attach trigger), then direct-invoke processing.
    /// Every failure path lands the recording in the offline queue; the m4a is
    /// only deleted after a successful attach.
    @MainActor
    private func uploadAndAttach(
        localURL: URL,
        rowId: UUID,
        ticket: UUID?,
        selectedWorkoutDate: Date?,
        checkInManager: CoachCheckInManager
    ) async {
        // The attach intent (`ticket`) was persisted by the caller before this
        // task was created — see uploadAudioAndSaveLog. The drain's attach is
        // idempotent (guarded on audio_url IS NULL), so the intent replaying
        // after our own success is a harmless no-op — but we clear it on
        // success anyway.
        do {
            let audioData = try Data(contentsOf: localURL)
            let audioPublicURL = try await uploadVoiceMemoAudio(audioData)

            let attachData: [String: AnyJSON] = [
                "audio_url": .string(audioPublicURL),
                "processing_status": .string("pending"),
            ]
            // Same idempotency guard as the drain: only attach if no audio is
            // on the row yet (a drain retry may have beaten us here).
            let updated: [TrainingLog] = try await supabase
                .from("training_logs")
                .update(attachData)
                .eq("id", value: rowId.uuidString)
                .is("audio_url", value: nil)
                .select(TrainingLog.columns)
                .execute()
                .value

            guard let attachedLog = updated.first else {
                // 0 rows: the row already has audio (a racing drain fulfilled
                // the intent — done), or it vanished (merged/superseded
                // mid-upload — requeue as a fresh insert so the audio is
                // never stranded; the server's sibling merge collapses it
                // onto the surviving run).
                struct ProbeRow: Decodable { let id: UUID; let audio_url: String? }
                let probe: [ProbeRow] = (try? await supabase
                    .from("training_logs")
                    .select("id, audio_url")
                    .eq("id", value: rowId.uuidString)
                    .limit(1)
                    .execute()
                    .value) ?? []
                if let row = probe.first, row.audio_url != nil {
                    if let ticket { OfflineQueueManager.shared.completeVoiceAttach(ticket: ticket) }
                    try? FileManager.default.removeItem(at: localURL)
                    return
                }
                Log.app.error("Voice attach hit a missing row \(rowId) — requeueing as fresh insert")
                if let ticket { OfflineQueueManager.shared.completeVoiceAttach(ticket: ticket) }
                OfflineQueueManager.shared.enqueueVoiceLog(
                    audioURL: localURL,
                    notes: nil,
                    mood: nil,
                    workoutDate: selectedWorkoutDate
                )
                OfflineQueueManager.shared.drainQueue()
                return
            }

            if let ticket { OfflineQueueManager.shared.completeVoiceAttach(ticket: ticket) }
            try? FileManager.default.removeItem(at: localURL)

            // Direct-invoke processing (2026-08-04, latency Phase 1): the
            // attach UPDATE only ENQUEUES the outbox job (90s grace); nothing
            // runs until the drain fires unless we kick the function now. The
            // outbox row stays behind as the retry net: if this call is lost
            // to a dropped connection, the drain picks the job up, and if both
            // run, the function's completed short-circuit + concurrency guard
            // make the second call a no-op.
            let capturedUserId = AuthManager.shared.userId
            Task { [weak self] in
                _ = await self?.callProcessingFunction(
                    record: attachedLog,
                    checkInManager: checkInManager
                )
            }

            Task { [weak self] in
                guard let self else { return }
                let status = await self.watchProcessing(recordId: rowId.uuidString)
                // Compute workout features after successful processing
                if status == "completed" {
                    _ = try? await callEdgeFunction(
                        name: "compute-workout-features",
                        body: ["user_id": capturedUserId]
                    )
                    // TrendsService caches its payload for the rest of the app
                    // session (`loaded` gate) — without this, a workout logged
                    // after Trends already loaded once never appears there
                    // until the athlete force-quits. This is the moment its
                    // parsed_structure.blocks actually exist to show.
                    await TrendsService.shared.refresh(force: true)
                }
            }
        } catch {
            Log.app.error("Failed to upload/attach voice memo audio: \(error)")
            // The attach intent was persisted before the upload started, so
            // the retry path is already armed — the drain replays the attach
            // against this row (idempotently) when the network returns. The
            // file survives on disk inside the queue item.
            statusMessage = "Saved — audio will finish uploading in the background."
            ErrorReporter.shared.report(error, context: "attach voice memo audio (intent queued)")
            OfflineQueueManager.shared.drainQueue()
        }
    }

    // MARK: - Upload Check-In (not tied to a workout)

    @MainActor
    func uploadCheckIn(
        localURL: URL,
        checkInManager: CoachCheckInManager,
        mood: String? = nil,
        repliedToReadId: UUID? = nil
    ) async {
        isUploading = true
        statusMessage = "Uploading check-in..."

        do {
            let audioData = try Data(contentsOf: localURL)
            let fileName = localURL.lastPathComponent
            let userId = AuthManager.shared.userId
            let storagePath = "\(userId)/\(fileName)"

            // Upload audio via Supabase SDK (handles auth + response parsing internally)
            try await supabase.storage
                .from("training-memos")
                .upload(storagePath, data: audioData, options: FileOptions(contentType: "audio/m4a", upsert: true))

            let publicURL = try supabase.storage
                .from("training-memos")
                .getPublicURL(path: storagePath)
            let audioPublicURL = publicURL.absoluteString

            // Insert check-in record via Supabase SDK
            var insertData = TrainingLogInsert(audioUrl: audioPublicURL)
            insertData.userId = userId
            insertData.processingStatus = "pending"
            insertData.source = "check_in"
            // Stamped for the same reason as the memo paths and
            // saveMoodCheckIn: the journal orders by workout_date with NULLS
            // LAST and takes 50, so over a few months of history a NULL-dated
            // row is not merely sorted low — it is EXCLUDED, and the athlete
            // sees the check-in they just recorded vanish. This path was the
            // last one still inserting undated (2026-08-31).
            insertData.workoutDate = Date()
            // The Read tab's check-in radio — athlete-declared, so it renders
            // in the journal immediately instead of waiting on extraction.
            insertData.mood = mood
            insertData.repliedToReadId = repliedToReadId

            let response: [TrainingLog] = try await supabase
                .from("training_logs")
                .insert(insertData)
                .select(TrainingLog.columns)
                .execute()
                .value

            guard let record = response.first else {
                throw URLError(.cannotParseResponse)
            }
            let recordId = record.id

            try? FileManager.default.removeItem(at: localURL)

            isUploading = false
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                showSuccessAnimation = true
            }
            Task {
                try? await Task.sleep(for: .seconds(2.5))
                withAnimation { self.showSuccessAnimation = false }
            }

            await loadHistory()

            // Processing is handled server-side by the outbox drain (which now
            // runs every 15s — check-ins go to process-check-in, which has no
            // client direct-invoke path). iOS just polls for completion so the
            // UI auto-updates.
            let capturedId = recordId.uuidString
            Task { [weak self] in
                guard let self else { return }
                _ = await self.watchProcessing(recordId: capturedId)
            }
        } catch {
            Log.app.error("Failed to upload check-in: \(error)")
            // Preserve the recording on failure (see uploadAudioAndSaveLog).
            OfflineQueueManager.shared.enqueueVoiceLog(
                audioURL: localURL,
                notes: nil,
                mood: nil,
                workoutDate: nil,
                source: "check_in"
            )
            statusMessage = "Saved — will finish uploading in the background."
            isUploading = false
            ErrorReporter.shared.report(error, context: "upload check-in (queued for retry)")
            OfflineQueueManager.shared.drainQueue()
        }
    }

    // MARK: - Mood-only check-in

    /// The Read tab's "rate how you are feeling" with no words attached.
    /// One `check_in` row, mood set, nothing to transcribe or parse —
    /// `processing_status` is "not_required" so the extraction pipeline never
    /// touches it and the athlete's rating is authoritative by construction.
    /// `workout_date` is stamped for the same reason as the memo paths: a
    /// NULL-dated row sinks in the journal.
    @MainActor
    func saveMoodCheckIn(_ mood: String, repliedToReadId: UUID? = nil) async -> Bool {
        let userId = AuthManager.shared.userId
        guard !userId.isEmpty else {
            statusMessage = "Not signed in yet — try again in a moment."
            return false
        }

        var insertData = TrainingLogInsert()
        insertData.userId = userId
        insertData.source = "check_in"
        insertData.processingStatus = "not_required"
        insertData.workoutDate = Date()
        insertData.mood = mood
        insertData.repliedToReadId = repliedToReadId

        do {
            try await supabase
                .from("training_logs")
                .insert(insertData)
                .execute()
            await loadHistory()
            return true
        } catch {
            Log.app.error("Failed to save mood check-in: \(error)")
            ErrorReporter.shared.report(error, context: "save mood check-in")
            return false
        }
    }

    // MARK: - Save Manual Notes

    @MainActor
    func saveManualNotes(
        _ notes: String,
        selectedWorkout: RunningWorkout?,
        mood: String? = nil,
        repliedToReadId: UUID? = nil
    ) async -> Bool {
        guard !notes.isEmpty else { return false }

        isUploading = true
        statusMessage = "Saving notes..."

        do {
            // user_id is REQUIRED: the training_logs INSERT policy is
            // WITH CHECK (user_id = auth.uid()::text), so an insert without it
            // is rejected by RLS — which is why manual notes silently failed to
            // save. Matches the audio path (uploadAudioAndSaveLog).
            let userId = AuthManager.shared.userId
            guard !userId.isEmpty else {
                statusMessage = "Not signed in yet — try again in a moment."
                isUploading = false
                return false
            }

            var insertData = TrainingLogInsert(notes: notes)
            insertData.userId = userId
            // Athlete-declared mood from the Read check-in radio, when one
            // accompanied the note. Declared mood wins — the extraction
            // UPDATE preserves a non-null row mood (see TrainingLogInsert.mood).
            insertData.mood = mood
            insertData.repliedToReadId = repliedToReadId
            // "pending" enqueues the note for the same analysis pass as voice
            // memos (mood + niggle/injury-mention extraction) via the outbox
            // trigger. The drain worker + process-training-memo take the text
            // branch (no audio). Was "not_required", which skipped all parsing.
            insertData.processingStatus = "pending"
            insertData.source = "voice_log"
            // Same reason as the audio path: never leave workout_date NULL, or
            // the note detaches from its run and sinks in the journal.
            insertData.workoutDate = Date()
            if let workout = selectedWorkout {
                insertData.workoutDate = workout.startDate
                insertData.workoutDistanceMiles = workout.distanceMiles
                insertData.workoutDurationMinutes = workout.durationMinutes
            }

            // Remove any auto_sync entry for this workout before inserting the manual note
            if let workout = selectedWorkout {
                let syncService = WorkoutSyncService()
                await syncService.removeAutoSyncEntry(forWorkoutDate: workout.startDate, distance: workout.distanceMiles)
            }

            struct InsertedRow: Decodable { let id: UUID }
            let inserted: InsertedRow = try await supabase
                .from("training_logs")
                .insert(insertData)
                .select("id")
                .single()
                .execute()
                .value

            statusMessage = "Notes saved!"
            isUploading = false

            Task {
                try? await Task.sleep(for: .seconds(2))
                if self.statusMessage == "Notes saved!" {
                    self.statusMessage = ""
                }
            }

            await loadHistory()

            let capturedRecordId = inserted.id.uuidString
            let capturedUserId = userId

            // Direct-invoke the analysis pass (2026-08-04, latency Phase 1):
            // the INSERT trigger enqueued a 'note' job, but waiting on the
            // drain cron cost up to a minute of dead time. Call
            // process-training-memo now (it takes the text branch — the note
            // IS the transcript); the outbox row stays as the retry net and
            // the drain no-ops once this completes.
            Task {
                let payload: [String: Any] = [
                    "type": "INSERT",
                    "table": "training_logs",
                    "schema": "public",
                    "record": ["id": capturedRecordId, "audio_url": ""],
                ]
                _ = try? await callEdgeFunction(name: "process-training-memo", body: payload)
            }

            // Watch for the analysis pass (mood + niggle/injury-mention
            // extraction) to finish so the parsed result appears in place
            // without a manual refresh.
            Task { [weak self] in
                guard let self else { return }
                let status = await self.watchProcessing(recordId: capturedRecordId)
                // Recompute workout features so the ML pipeline stays current.
                if status == "completed" {
                    _ = try? await callEdgeFunction(
                        name: "compute-workout-features",
                        body: ["user_id": capturedUserId]
                    )
                    // See the matching comment in uploadAndAttach — TrendsService
                    // is a load-once-per-session cache and won't pick up this
                    // workout's parsed_structure on its own.
                    await TrendsService.shared.refresh(force: true)
                }
            }

            return true
        } catch {
            Log.app.error("Failed to save manual notes: \(error)")
            statusMessage = "Error: \(error.localizedDescription)"
            isUploading = false
            ErrorReporter.shared.report(error, context: "save manual notes")
            return false
        }
    }

    // MARK: - History

    @MainActor
    /// All runs with a distance in the recent window (~27 weeks), any source —
    /// backs the journal's per-week mileage totals. Selects only the columns
    /// needed (never `*`, so the heavy external_streams JSONB isn't dragged).
    private func fetchJournalMileageRows(userId: String) async throws -> [JournalMileageRow] {
        let since = Calendar.current.date(byAdding: .day, value: -190, to: Date()) ?? Date()
        let sinceISO = ISO8601DateFormatter().string(from: since)
        return try await supabase
            .from("training_logs")
            .select("workout_date, created_at, workout_distance_miles, source")
            .eq("user_id", value: userId)
            .gte("workout_date", value: sinceISO)
            .gte("workout_distance_miles", value: 0.1)
            .limit(800)
            .execute()
            .value
    }

    /// Body-part mentions linked to a training_log, for the journal row chips.
    /// Text/uuid columns only (no DATE decode — `mentioned_at` is a query filter,
    /// not a decoded field), so it decodes cleanly via `.value`.
    private func fetchNiggles(userId: String) async throws -> [JournalNiggle] {
        let since = Calendar.current.date(byAdding: .day, value: -190, to: Date()) ?? Date()
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        return try await supabase
            .from("body_mentions")
            .select("id, training_log_id, body_area, side, verbatim_quote")
            .eq("user_id", value: userId.lowercased())
            .gte("mentioned_at", value: df.string(from: since))
            .limit(500)
            .execute()
            .value
    }

    /// Disk name for the journal snapshot (see JournalCachePayload below).
    private static let journalCacheName = "journal_feed"

    /// Snapshot of the journal surface — entries, weekly mileage, niggle
    /// chips — for instant re-launch rendering via DiskCache.
    private struct JournalCachePayload: Codable {
        let userId: String
        let savedAt: Date
        let logs: [TrainingLog]
        let mileage: [JournalMileageRow]
        let niggles: [JournalNiggle]
    }

    func loadHistory() async {
        isLoadingHistory = true

        // Stale-while-revalidate: publish the last-known journal from disk
        // BEFORE the auth wait below (which can spin for up to ~3s on a cold
        // launch). The athlete sees their entries the moment the tab draws;
        // the network pass replaces them seconds later. Account-guarded: a
        // known, different userId skips the snapshot (an empty userId means
        // auth hasn't resolved yet — launch-restore — and the network pass
        // overwrites moments later either way; sign-out clears the cache).
        if historyLogs.isEmpty,
           let cached = DiskCache.load(JournalCachePayload.self, name: Self.journalCacheName) {
            let current = AuthManager.shared.userId
            if current.isEmpty || current == cached.userId {
                historyLogs = cached.logs
                weeklyMileageRows = cached.mileage
                var byLog: [String: [JournalNiggle]] = [:]
                for n in cached.niggles {
                    guard let key = n.trainingLogId?.uuidString else { continue }
                    byLog[key, default: []].append(n)
                }
                niggleByLog = byLog
                isLoadingHistory = false
                historyRevision += 1
            }
        }

        // Auth may not have resolved yet on a cold launch. Querying with an
        // empty userId returns zero rows and would silently blank an existing
        // journal (the recurring "my logs disappeared" report), so wait briefly
        // for the session to resolve rather than clobbering historyLogs to [].
        var userId = AuthManager.shared.userId
        var authWaits = 0
        while userId.isEmpty && authWaits < 10 {
            try? await Task.sleep(for: .milliseconds(300))
            userId = AuthManager.shared.userId
            authWaits += 1
        }
        guard !userId.isEmpty else {
            // Same stale-beats-error rule as the catch below: if the disk
            // snapshot already rendered, don't slap an error over it.
            loadFailed = historyLogs.isEmpty
            isLoadingHistory = false
            return
        }

        do {
            // Voice Log view = only voice memos + manual entries. Auto-synced workouts
            // (strava, vital, healthkit) live elsewhere and show up as linkable workouts.
            // Decoded row-by-row (Failable) on purpose: a strict [TrainingLog]
            // decode is all-or-nothing, so one malformed row emptied the whole
            // journal and surfaced as "could not load history".
            let rows: [Failable<TrainingLog>] = try await supabase
                .from("training_logs")
                .select(TrainingLog.columns)
                .eq("user_id", value: userId)
                .or("audio_url.not.is.null,source.eq.voice_log,source.eq.manual,source.eq.check_in")
                .order("workout_date", ascending: false, nullsFirst: false)
                .limit(50)
                .execute()
                .value

            let logs = rows.compactMap(\.value)
            if logs.count < rows.count {
                Log.app.error("Skipped \(rows.count - logs.count) undecodable training_log row(s)")
            }

            historyLogs = logs.sorted { $0.displayDate > $1.displayDate }
            loadFailed = false
            // Publish the rows before the mileage/niggle fetches below, so the
            // two-stage reveal lands as soon as the transcript does.
            historyRevision += 1
            // All runs (any source) for the week-header mileage totals.
            weeklyMileageRows = (try? await fetchJournalMileageRows(userId: userId)) ?? []
            // Niggles linked to each log, for the row chips.
            let niggles = (try? await fetchNiggles(userId: userId)) ?? []
            var byLog: [String: [JournalNiggle]] = [:]
            for n in niggles {
                guard let key = n.trainingLogId?.uuidString else { continue }
                byLog[key, default: []].append(n)
            }
            niggleByLog = byLog
            isLoadingHistory = false
            historyRevision += 1

            // Persist the fresh snapshot for the next launch's fast path.
            DiskCache.save(
                JournalCachePayload(
                    userId: userId,
                    savedAt: Date(),
                    logs: historyLogs,
                    mileage: weeklyMileageRows,
                    niggles: niggles
                ),
                name: Self.journalCacheName
            )

            await autoRetryStaleRecords(logs: logs)
        } catch {
            Log.app.error("Failed to load history: \(error)")
            // Only surface the error state when there's nothing on screen —
            // if the disk snapshot rendered above, stale entries beat a
            // "couldn't load" banner over a journal the athlete can read.
            loadFailed = historyLogs.isEmpty
            isLoadingHistory = false
            ErrorReporter.shared.report(error, context: "load voice log history")
        }
    }


    // MARK: - Retry Processing

    @MainActor
    func retryProcessing(log: TrainingLog) async {
        guard log.audioUrl != nil else { return }

        statusMessage = "Retrying transcription..."

        let success = await callProcessingFunction(record: log, checkInManager: nil, maxRetries: 2)

        if success {
            statusMessage = "Transcription completed!"
        } else {
            statusMessage = "Retry failed. Try again later."
        }

        Task {
            try? await Task.sleep(for: .seconds(3))
            self.statusMessage = ""
        }

        await loadHistory()
    }

    // MARK: - Processing

    func callProcessingFunction(
        record: TrainingLog,
        checkInManager: CoachCheckInManager?,
        maxRetries: Int = 1
    ) async -> Bool {
        let payload: [String: Any] = [
            "type": "INSERT",
            "table": "training_logs",
            "schema": "public",
            "record": [
                "id": record.id.uuidString,
                "audio_url": record.audioUrl ?? "",
            ],
        ]

        for attempt in 1 ... maxRetries {
            do {
                Log.app.info("Processing attempt \(attempt) of \(maxRetries) for record \(record.id)")

                let result = try await withTimeout(seconds: 60) {
                    try await callEdgeFunction(name: "process-training-memo", body: payload)
                }

                if let json = try? JSONSerialization.jsonObject(with: result) as? [String: Any] {
                    if let success = json["success"] as? Bool, success {
                        Log.app.info("Processing completed successfully for record \(record.id)")

                        let mood = json["mood"] as? String
                        let cleanedNotes = json["cleaned_notes"] as? String
                        let coachInsight = json["coach_insight"] as? String
                        if let mood, let checkInManager,
                           CoachCheckInManager.triggerMoods.contains(mood)
                        {
                            await MainActor.run {
                                withAnimation(.spring(response: 0.4)) {
                                    checkInManager.trigger(
                                        logId: record.id,
                                        mood: mood,
                                        cleanedNotes: cleanedNotes,
                                        coachInsight: coachInsight
                                    )
                                }
                            }
                        }

                        await MainActor.run { AthletePaceProfileService.shared.scheduleRefresh() }
                        return true
                    }

                    if let status = json["status"] as? String, status == "processing" {
                        Log.app.info("Record \(record.id) already processing, polling for completion...")
                        if await pollForCompletion(recordId: record.id, maxWait: 60) {
                            return true
                        }
                        continue
                    }

                    if let errorMsg = json["error"] as? String {
                        Log.app.error("Processing returned error: \(errorMsg)")
                    }
                }

                if await pollForCompletion(recordId: record.id, maxWait: 30) {
                    return true
                }

            } catch {
                Log.app.error("Processing attempt \(attempt) failed: \(error)")

                // Not every failure of THIS call is a failure of the memo.
                //
                // The audio is already uploaded and the row is enqueued in
                // `voice_processing_jobs`, and the drain worker calls
                // process-training-memo with the SERVICE ROLE key — which
                // bypasses the per-user rate limit that rejected us here. So
                // for the two failures the outbox demonstrably recovers from,
                // the memo still lands; showing a red "Could not process voice
                // log. Please try again." banner would be a lie, and worse, it
                // invites a manual retry that spends more quota.
                //
                //   429 — daily/monthly voice_memo quota. Drain finishes it.
                //   409 — "already processing": the drain raced us and is
                //         mid-run. Routine since the 2026-08-04 direct-invoke
                //         change; never was a real error.
                //
                // Anything else (5xx, auth, transport) still surfaces — those
                // can strand the memo and the athlete should know.
                if Self.isOutboxRecoverable(error) {
                    Log.app.info("Direct invoke deferred to the drain worker for \(record.id); not surfacing to the athlete")
                    return await pollForCompletion(recordId: record.id, maxWait: 60)
                }

                ErrorReporter.shared.report(error, context: "process voice log")

                if attempt < maxRetries {
                    let delay = Double(1 << attempt)
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }

        Log.app.error("All processing attempts failed for record \(record.id)")
        return false
    }

    // MARK: - Helpers

    /// True for direct-invoke failures the `voice_processing_jobs` outbox will
    /// finish on its own, so the athlete should never see a banner for them.
    ///
    /// Both are server-side "come back later" signals, not data loss: the audio
    /// is uploaded and the job row exists, and the drain worker re-invokes with
    /// the service-role key (which skips the user-keyed rate limit entirely).
    static func isOutboxRecoverable(_ error: Error) -> Bool {
        guard let edgeError = error as? EdgeFunctionError else { return false }
        switch edgeError {
        case let .httpError(statusCode, _, _):
            return statusCode == 429 || statusCode == 409
        }
    }

    /// Watch a row's `processing_status` until it reaches a terminal state.
    ///
    /// Cadence: 1s ticks for the first 15s, then 3s, for up to 180s total. The
    /// transcript lands ~6s in and `completed` ~9s in (2026-09-05, thinking
    /// budget zeroed), so the tight early cadence is what makes those
    /// transitions feel instant; the 3s tail keeps the slow path cheap.
    ///
    /// Why 180s and not 60s: the direct invoke is not the only writer. When it
    /// is lost (429, dropped connection, app suspended), the outbox drain
    /// picks the job up at +90s and finishes ~100-110s after attach. A 60s
    /// watch quit before that could land, so a drain-recovered memo sat
    /// "Transcribing" until something else happened to reload the feed — and
    /// past 3 minutes would now read as stuck while already complete on the
    /// server. The window must outlast the safety net it depends on; 180s
    /// matches TrainingLog.isStalled so the two can never disagree.
    ///
    /// Refreshes the journal on EVERY status change — most importantly
    /// pending → `transcribed` (the two-stage reveal: the athlete's own words
    /// render immediately; mood, niggles, and structure fill in when the
    /// status flips to `completed`).
    ///
    /// Returns the terminal status ("completed" / "failed"), or nil when the
    /// row disappeared (dedup merged it — a normal outcome) or the watch
    /// timed out.
    private func watchProcessing(recordId: String) async -> String? {
        var lastStatus = "pending"
        var waited: Double = 0
        while waited < 180 {
            let interval: Double = waited < 15 ? 1 : 3
            try? await Task.sleep(for: .seconds(interval))
            waited += interval

            struct StatusRow: Decodable { let processing_status: String? }
            let result: [StatusRow]? = try? await supabase
                .from("training_logs")
                .select("processing_status")
                .eq("id", value: recordId)
                .execute()
                .value

            // Row gone: dedup merged this memo into the matching run and
            // deleted the standalone row. That's a normal outcome, NOT "still
            // pending" — stop watching and refresh so the UI shows the merged
            // entry. (An empty array means the row is gone; nil means a
            // transient query error → keep watching.)
            if let rows = result, rows.isEmpty {
                await MainActor.run { _ = Task { await self.loadHistory() } }
                return nil
            }

            let status = result?.first?.processing_status ?? "pending"
            if status != lastStatus {
                await MainActor.run { _ = Task { await self.loadHistory() } }
            }
            lastStatus = status
            if status == "completed" || status == "failed" {
                return status
            }
        }
        // Timed out — refresh anyway.
        await MainActor.run { _ = Task { await self.loadHistory() } }
        return nil
    }

    private func pollForCompletion(recordId: UUID, maxWait: Int) async -> Bool {
        let pollInterval: UInt64 = 2_000_000_000
        let maxAttempts = maxWait / 2

        for _ in 0 ..< maxAttempts {
            do {
                let logs: [TrainingLog] = try await supabase
                    .from("training_logs")
                    .select(TrainingLog.columns)
                    .eq("id", value: recordId.uuidString)
                    .limit(1)
                    .execute()
                    .value

                if let log = logs.first {
                    if log.isCompleted {
                        return true
                    } else if log.isFailed {
                        Log.app.error("Processing failed: \(log.processingError ?? "unknown")")
                        return false
                    }
                }

                try await Task.sleep(nanoseconds: pollInterval)
            } catch {
                Log.app.error("Poll error: \(error)")
                ErrorReporter.shared.report(error, context: "retry processing")
            }
        }
        return false
    }

    private func withTimeout<T>(seconds: Int, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
                throw URLError(.timedOut)
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    // MARK: - Vital Stream Enrichment

    /// After voice processing, find the matching Vital workout and compute pace segments from stream data.
    /// This gives voice logs the same rich splits/HR/pace data that auto_sync entries get.
    private func enrichWithVitalStream(logId: UUID, workoutDate: Date?, distanceMiles: Double?) async {
        guard let workoutDate else { return }

        // Find matching Vital workout by date + distance
        let vitalWorkouts = await VitalManager.shared.fetchRunningWorkouts(for: workoutDate)
        guard let match = vitalWorkouts.min(by: {
            guard let dist = distanceMiles else { return false }
            return abs($0.distanceMiles - dist) < abs($1.distanceMiles - dist)
        }), let vitalId = match.vitalWorkoutId else { return }

        // Fetch stream and compute pace segments
        guard let stream = await VitalManager.shared.fetchWorkoutStream(workoutId: vitalId) else { return }

        let paceSplits = VitalManager.shared.calculatePaceSplits(from: stream)
        guard !paceSplits.isEmpty else { return }

        // Classify pace splits into labeled segments (reuse WorkoutSyncService logic)
        let overallPace = match.pacePerMile
        let syncService = WorkoutSyncService()
        let segments = syncService.classifyPaceSplitsPublic(paceSplits, overallPace: overallPace)
        guard !segments.isEmpty else { return }

        // Derive workout pace from segments
        let hardSegments = segments.filter { ["interval", "threshold", "tempo", "race_pace", "moderate"].contains($0.effort) }
        let workoutPace = hardSegments.isEmpty ? nil : hardSegments.first?.pacePerMile

        // Save to database
        struct VitalEnrichment: Codable {
            let paceSegments: [PaceSegment]
            let vitalWorkoutId: String
            let workoutPacePerMile: String?

            enum CodingKeys: String, CodingKey {
                case paceSegments = "pace_segments"
                case vitalWorkoutId = "vital_workout_id"
                case workoutPacePerMile = "workout_pace_per_mile"
            }
        }

        do {
            try await supabase
                .from("training_logs")
                .update(VitalEnrichment(
                    paceSegments: segments,
                    vitalWorkoutId: vitalId,
                    workoutPacePerMile: workoutPace
                ))
                .eq("id", value: logId.uuidString)
                .execute()

            Log.app.info("Enriched voice log \(logId) with \(segments.count) pace segments from Vital")
        } catch {
            Log.app.error("Failed to enrich voice log with Vital data: \(error)")
        }
    }

    private func autoRetryStaleRecords(logs: [TrainingLog]) async {
        let fiveMinutesAgo = Date().addingTimeInterval(-5 * 60)

        // isInFlight (not isPending): a row stuck at `transcribed` — the
        // two-stage reveal wrote the transcript but the worker died before the
        // analysis — is just as stale, and the server-side "already processed"
        // guard is status-gated so retrying it re-runs the analysis correctly.
        // A stale row with NO audio is a memo whose attach never landed
        // (status "uploading"). Re-invoking the processor cannot help — there
        // is nothing on the server to process — but the attach intent is in
        // the offline queue, so drain it: the drain replays the attach
        // idempotently and the server pipeline takes over from there.
        if logs.contains(where: { $0.isInFlight && $0.audioUrl == nil && $0.createdAt < fiveMinutesAgo }) {
            Log.app.info("Stale audio-less memo row found — draining the offline queue to replay its attach")
            OfflineQueueManager.shared.drainQueue()
        }

        guard let staleLog = logs.first(where: { log in
            log.isInFlight &&
                log.audioUrl != nil &&
                log.createdAt < fiveMinutesAgo
        }) else { return }

        Log.app.info("Auto-retrying stale record \(staleLog.id)")
        let success = await callProcessingFunction(record: staleLog, checkInManager: nil, maxRetries: 1)

        if success {
            await loadHistory()
        }
    }
}
