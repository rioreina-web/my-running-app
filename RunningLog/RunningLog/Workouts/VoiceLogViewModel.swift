import AVFoundation
import Foundation
import os
import Storage
import Supabase
import SwiftUI

@Observable
final class VoiceLogViewModel {
    var historyLogs: [TrainingLog] = []
    var isLoadingHistory = false
    var isUploading = false
    var statusMessage = ""
    var showSuccessAnimation = false

    /// Logs the app is actively watching for server-side completion. The
    /// journal card reads this to tell "we're still on it" apart from
    /// "we stopped looking — tap to check again."
    var watchingLogIds: Set<UUID> = []

    /// How long to keep watching a freshly uploaded memo before handing
    /// the athlete a manual "Check again". Covers p90 server latency
    /// (~5 min) with headroom.
    private static let watchWindow: TimeInterval = 10 * 60

    /// Processing states the server will not move off on its own.
    private static let terminalStatuses: Set<String> = ["completed", "failed", "not_required"]

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
            let fileName = localURL.lastPathComponent
            let userId = AuthManager.shared.userId
            let storagePath = "\(userId)/\(fileName)"

            // --- Step 1: Upload audio via Supabase SDK ---
            try await supabase.storage
                .from("training-memos")
                .upload(storagePath, data: audioData, options: FileOptions(contentType: "audio/m4a", upsert: true))

            let publicURL = try supabase.storage
                .from("training-memos")
                .getPublicURL(path: storagePath)
            let audioPublicURL = publicURL.absoluteString

            // --- Step 2: Insert record via Supabase SDK ---
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

            let response: [TrainingLog] = try await supabase
                .from("training_logs")
                .insert(insertData)
                .select()
                .execute()
                .value

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

            // Processing is handled server-side by the voice-processing
            // outbox (a DB trigger enqueues; a once-a-minute cron drains).
            // iOS watches for completion so the UI auto-updates.
            if let insertedLog = response.first {
                let capturedUserId = userId
                watchProcessing(recordId: insertedLog.id) { status in
                    // Compute workout features after successful processing
                    if status == "completed" {
                        _ = try? await callEdgeFunction(
                            name: "compute-workout-features",
                            body: ["user_id": capturedUserId]
                        )
                    }
                }
            }
        } catch {
            Log.app.error("Failed to upload audio log: \(error)")
            statusMessage = "Error: \(error.localizedDescription)"
            isUploading = false
            ErrorReporter.shared.report(error, context: "upload audio log")
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

            // Processing is handled server-side by the voice-processing
            // outbox (a DB trigger enqueues; a once-a-minute cron drains).
            // iOS watches for completion so the UI auto-updates.
            watchProcessing(recordId: recordId)
        } catch {
            Log.app.error("Failed to upload check-in: \(error)")
            statusMessage = "Error: \(error.localizedDescription)"
            isUploading = false
            ErrorReporter.shared.report(error, context: "upload check-in")
        }
    }

    // MARK: - Save Manual Notes

    @MainActor
    func saveManualNotes(_ notes: String, selectedWorkout: RunningWorkout?) async -> Bool {
        guard !notes.isEmpty else { return false }

        isUploading = true
        statusMessage = "Saving notes..."

        do {
            var insertData = TrainingLogInsert(notes: notes)
            insertData.processingStatus = "not_required"
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

            try await supabase
                .from("training_logs")
                .insert(insertData)
                .execute()

            statusMessage = "Notes saved!"
            isUploading = false

            Task {
                try? await Task.sleep(for: .seconds(2))
                if self.statusMessage == "Notes saved!" {
                    self.statusMessage = ""
                }
            }

            await loadHistory()

            // Recompute workout features so ML pipeline stays current
            let userId = AuthManager.shared.userId
            Task.detached {
                try? await callEdgeFunction(
                    name: "compute-workout-features",
                    body: ["user_id": userId]
                )
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
    func loadHistory() async {
        isLoadingHistory = true

        do {
            let userId = AuthManager.shared.userId
            // Voice Log view = only voice memos + manual entries. Auto-synced workouts
            // (strava, vital, healthkit) live elsewhere and show up as linkable workouts.
            let logs: [TrainingLog] = try await supabase
                .from("training_logs")
                .select()
                .eq("user_id", value: userId)
                .or("audio_url.not.is.null,source.eq.voice_log,source.eq.manual,source.eq.check_in")
                .order("workout_date", ascending: false, nullsFirst: false)
                .limit(50)
                .execute()
                .value

            historyLogs = logs.sorted { $0.displayDate > $1.displayDate }
            isLoadingHistory = false

            await autoRetryStaleRecords(logs: logs)
        } catch {
            Log.app.error("Failed to load history: \(error)")
            isLoadingHistory = false
            ErrorReporter.shared.report(error, context: "load voice log history")
        }
    }


    // MARK: - Watch Processing

    /// Poll a just-uploaded log until the server marks it done, then
    /// refresh the journal so the card flips on its own.
    ///
    /// Sizing matters here. Processing runs through the voice-processing
    /// outbox: a DB trigger enqueues the job, a once-a-minute cron drains
    /// it, and only then does transcription + the LLM pass run. Measured
    /// end-to-end latency is ~2 min at the median and ~5 min at p90. The
    /// previous 60s cutoff expired before most memos finished — and
    /// because nothing re-fetched afterwards, a memo that had completed
    /// server-side kept showing "Processing with AI..." until the athlete
    /// found the small refresh button. That is the "stuck memo" bug.
    ///
    /// Cadence backs off so a fast memo still updates near-instantly
    /// without the long tail hammering the API: every 3s for the first
    /// 30s, every 5s out to 2 min, every 15s to the deadline.
    @MainActor
    func watchProcessing(
        recordId: UUID,
        then onCompleted: ((String) async -> Void)? = nil
    ) {
        guard !watchingLogIds.contains(recordId) else { return }
        watchingLogIds.insert(recordId)

        Task { [weak self] in
            let startedAt = Date()
            var status = "pending"

            while Date().timeIntervalSince(startedAt) < Self.watchWindow {
                let elapsed = Date().timeIntervalSince(startedAt)
                let interval: Duration =
                    elapsed < 30 ? .seconds(3)
                    : elapsed < 120 ? .seconds(5)
                    : .seconds(15)

                try? await Task.sleep(for: interval)
                if Task.isCancelled { break }

                if let fetched = await Self.fetchProcessingStatus(recordId: recordId) {
                    status = fetched
                }
                if Self.terminalStatuses.contains(status) { break }
            }

            await self?.stopWatching(recordId: recordId)
            await onCompleted?(status)
        }
    }

    /// Re-check a single log on demand — backs the "Check again" action on
    /// a memo whose watch window already closed.
    @MainActor
    func checkAgain(log: TrainingLog) async {
        statusMessage = "Checking..."
        let status = await Self.fetchProcessingStatus(recordId: log.id)
        await loadHistory()

        if let status, Self.terminalStatuses.contains(status) {
            statusMessage = ""
        } else {
            statusMessage = "Still processing. This can take a few minutes."
            watchProcessing(recordId: log.id)
            Task {
                try? await Task.sleep(for: .seconds(4))
                if self.statusMessage.hasPrefix("Still processing") {
                    self.statusMessage = ""
                }
            }
        }
    }

    @MainActor
    private func stopWatching(recordId: UUID) async {
        watchingLogIds.remove(recordId)
        await loadHistory()
    }

    private static func fetchProcessingStatus(recordId: UUID) async -> String? {
        struct StatusRow: Decodable { let processing_status: String? }
        let rows: [StatusRow]? = try? await supabase
            .from("training_logs")
            .select("processing_status")
            .eq("id", value: recordId.uuidString)
            .limit(1)
            .execute()
            .value
        return rows?.first?.processing_status
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
                await ErrorReporter.shared.report(error, context: "process voice log")

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
                await ErrorReporter.shared.report(error, context: "retry processing")
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
