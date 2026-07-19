import AVFoundation
import Foundation
import os
import Storage
import Supabase
import SwiftUI

/// Lightweight run row for the journal's per-week mileage subtotal — ALL runs
/// (not just authored entries), so the header reflects true weekly volume.
struct JournalMileageRow: Decodable {
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
struct JournalNiggle: Decodable, Identifiable {
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
        isUploading = true
        statusMessage = "Uploading..."

        do {
            let audioData = try Data(contentsOf: localURL)
            let userId = AuthManager.shared.userId

            // --- Step 1: Upload audio via the service-role edge function ---
            // Direct storage uploads have been rejected by the storage service
            // since 2026-06-02 (RLS "Unauthorized" on a valid JWT); the edge
            // function writes with the service role. See its docstring.
            let audioPublicURL = try await uploadVoiceMemoAudio(audioData)

            // --- Step 2: Attach to the run's existing row, or insert a new one ---
            // If this memo is for an already-imported run (Strava/HealthKit), the
            // GPS streams, splits, and parsed structure already live on THAT row.
            // Inserting a separate voice_log row creates a DUPLICATE: the journal
            // entry shows up empty ("no workout parsed") while the real workout
            // sits on the other row, and editing workout notes on one never
            // reaches the other. So when the selected run has a known source id,
            // UPDATE its row (attach the audio) instead of inserting — one row,
            // one set of notes, shown + editable in both the Log tab and the
            // workout detail sheet. Falls back to a fresh insert on any miss, so
            // a memo is never lost.
            var response: [TrainingLog] = []
            var didAttach = false
            if let vid = selectedWorkout?.vitalWorkoutId, !vid.isEmpty {
                struct IdRow: Decodable { let id: UUID }
                let existing: [IdRow]? = try? await supabase
                    .from("training_logs")
                    .select("id")
                    .eq("user_id", value: userId)
                    .eq("vital_workout_id", value: vid)
                    .limit(1)
                    .execute()
                    .value
                if let rowId = existing?.first?.id {
                    let attachData: [String: AnyJSON] = [
                        "audio_url": .string(audioPublicURL),
                        "processing_status": .string("pending"),
                    ]
                    response = (try? await supabase
                        .from("training_logs")
                        .update(attachData)
                        .eq("id", value: rowId.uuidString)
                        .select()
                        .execute()
                        .value) ?? []
                    didAttach = !response.isEmpty
                }
            }

            if response.isEmpty {
                // No existing run row matched — insert a new voice_log row.
                var insertData = TrainingLogInsert(audioUrl: audioPublicURL)
                insertData.userId = userId
                insertData.processingStatus = "pending"
                insertData.source = "voice_log"
                if let workout = selectedWorkout {
                    insertData.workoutDate = workout.startDate
                    insertData.workoutDistanceMiles = workout.distanceMiles
                    insertData.workoutDurationMinutes = workout.durationMinutes

                    // Remove auto_sync duplicate
                    let syncService = WorkoutSyncService()
                    await syncService.removeAutoSyncEntry(forWorkoutDate: workout.startDate, distance: workout.distanceMiles)
                }

                response = try await supabase
                    .from("training_logs")
                    .insert(insertData)
                    .select()
                    .execute()
                    .value
            }

            try? FileManager.default.removeItem(at: localURL)

            // Show success immediately — don't wait for AI processing
            isUploading = false
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                showSuccessAnimation = true
            }
            Task {
                try? await Task.sleep(for: .seconds(2.5))
                withAnimation { self.showSuccessAnimation = false }
            }

            await loadHistory()

            // Processing is handled server-side by a DB trigger (pg_net calls
            // the edge function automatically on INSERT). iOS just polls for
            // completion so the UI auto-updates.
            if let insertedLog = response.first {
                let capturedRecordId = insertedLog.id.uuidString
                let capturedUserId = userId

                // On the attach path we UPDATEd an existing run row, so the
                // AFTER INSERT trigger that normally enqueues voice processing
                // never fired. Kick process-training-memo explicitly; the poll
                // below still picks up completion. (Insert path keeps relying on
                // the server-side enqueue, unchanged.)
                if didAttach {
                    Task { [weak self] in
                        _ = await self?.callProcessingFunction(
                            record: insertedLog,
                            checkInManager: checkInManager
                        )
                    }
                }

                Task { [weak self] in
                    // Poll every 3s for up to 60s
                    for _ in 0..<20 {
                        try? await Task.sleep(for: .seconds(3))
                        struct StatusRow: Decodable { let processing_status: String }
                        let result: [StatusRow]? = try? await supabase
                            .from("training_logs")
                            .select("processing_status")
                            .eq("id", value: capturedRecordId)
                            .execute()
                            .value
                        // Row gone: dedup merged this memo into the matching run
                        // and deleted the standalone row. That's a normal outcome,
                        // NOT "still pending" — stop polling immediately and
                        // refresh so the UI shows the merged entry instead of
                        // spinning until the 60s timeout. (An empty array means the
                        // row is gone; nil means a transient query error → retry.)
                        if let rows = result, rows.isEmpty {
                            await MainActor.run {
                                _ = Task { await self?.loadHistory() }
                            }
                            return
                        }
                        let status = result?.first?.processing_status ?? "pending"
                        if status == "completed" || status == "failed" {
                            await MainActor.run {
                                _ = Task { await self?.loadHistory() }
                            }
                            // Compute workout features after successful processing
                            if status == "completed" {
                                _ = try? await callEdgeFunction(
                                    name: "compute-workout-features",
                                    body: ["user_id": capturedUserId]
                                )
                            }
                            return
                        }
                    }
                    // Timed out — refresh anyway
                    await MainActor.run {
                        _ = Task { await self?.loadHistory() }
                    }
                }
            }
        } catch {
            Log.app.error("Failed to upload audio log: \(error)")
            // Data-loss guard: a voice memo is the core artifact of a
            // voice-first product. On failure (offline, 5xx, RLS), DO NOT lose
            // the recording. Hand it to the offline queue, which preserves the
            // file on disk and retries on reconnect. The view clears
            // recordingURL after this returns, so without enqueueing here the
            // m4a would orphan with no retry path.
            OfflineQueueManager.shared.enqueueVoiceLog(
                audioURL: localURL,
                notes: nil,
                mood: nil,
                workoutDate: selectedWorkout?.startDate
            )
            statusMessage = "Saved — will finish uploading in the background."
            isUploading = false
            ErrorReporter.shared.report(error, context: "upload audio log (queued for retry)")
            OfflineQueueManager.shared.drainQueue()
        }
    }

    // MARK: - Upload Check-In (not tied to a workout)

    @MainActor
    func uploadCheckIn(
        localURL: URL,
        checkInManager: CoachCheckInManager
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

            let response: [TrainingLog] = try await supabase
                .from("training_logs")
                .insert(insertData)
                .select()
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

            // Processing is handled server-side by a DB trigger (pg_net calls
            // process-check-in automatically on INSERT). iOS just polls for
            // completion so the UI auto-updates.
            let capturedId = recordId.uuidString
            Task { [weak self] in
                for _ in 0..<20 {
                    try? await Task.sleep(for: .seconds(3))
                    struct StatusRow: Decodable { let processing_status: String }
                    let result: [StatusRow]? = try? await supabase
                        .from("training_logs")
                        .select("processing_status")
                        .eq("id", value: capturedId)
                        .execute()
                        .value
                    let status = result?.first?.processing_status ?? "pending"
                    if status == "completed" || status == "failed" {
                        await MainActor.run {
                            _ = Task { await self?.loadHistory() }
                        }
                        return
                    }
                }
                await MainActor.run {
                    _ = Task { await self?.loadHistory() }
                }
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

    // MARK: - Save Manual Notes

    @MainActor
    func saveManualNotes(_ notes: String, selectedWorkout: RunningWorkout?) async -> Bool {
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
            // "pending" enqueues the note for the same analysis pass as voice
            // memos (mood + niggle/injury-mention extraction) via the outbox
            // trigger. The drain worker + process-training-memo take the text
            // branch (no audio). Was "not_required", which skipped all parsing.
            insertData.processingStatus = "pending"
            insertData.source = "voice_log"
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

            // Poll for the analysis pass (mood + niggle/injury-mention
            // extraction) to finish so the parsed result appears in place
            // without a manual refresh. Mirrors the audio path: every 3s for
            // up to 60s. The note is processed by the outbox drain, so this
            // just watches processing_status flip off "pending".
            let capturedRecordId = inserted.id.uuidString
            let capturedUserId = userId
            Task { [weak self] in
                for _ in 0..<20 {
                    try? await Task.sleep(for: .seconds(3))
                    struct StatusRow: Decodable { let processing_status: String }
                    let result: [StatusRow]? = try? await supabase
                        .from("training_logs")
                        .select("processing_status")
                        .eq("id", value: capturedRecordId)
                        .execute()
                        .value
                    // Row gone (dedup merged it into a run and deleted the
                    // standalone row): stop and refresh, don't spin to timeout.
                    if let rows = result, rows.isEmpty {
                        await MainActor.run { _ = Task { await self?.loadHistory() } }
                        return
                    }
                    let status = result?.first?.processing_status ?? "pending"
                    if status == "completed" || status == "failed" {
                        await MainActor.run { _ = Task { await self?.loadHistory() } }
                        // Recompute workout features so the ML pipeline stays current.
                        if status == "completed" {
                            _ = try? await callEdgeFunction(
                                name: "compute-workout-features",
                                body: ["user_id": capturedUserId]
                            )
                        }
                        return
                    }
                }
                // Timed out — refresh anyway.
                await MainActor.run { _ = Task { await self?.loadHistory() } }
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

    func loadHistory() async {
        isLoadingHistory = true

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
            loadFailed = true
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
                .select()
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

            await autoRetryStaleRecords(logs: logs)
        } catch {
            Log.app.error("Failed to load history: \(error)")
            loadFailed = true
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

    private func pollForCompletion(recordId: UUID, maxWait: Int) async -> Bool {
        let pollInterval: UInt64 = 2_000_000_000
        let maxAttempts = maxWait / 2

        for _ in 0 ..< maxAttempts {
            do {
                let logs: [TrainingLog] = try await supabase
                    .from("training_logs")
                    .select()
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

        guard let staleLog = logs.first(where: { log in
            log.isPending &&
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
