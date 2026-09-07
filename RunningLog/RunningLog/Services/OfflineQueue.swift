import Foundation
import Storage
import Supabase
import SwiftData
import os

// MARK: - Pending Upload Model (SwiftData)

@Model
final class PendingUpload {
    var id: UUID
    var type: String // "voiceLog", "manualWorkout", "trainingLog"
    var payload: Data // JSON-encoded request body
    var localFilePath: String? // audio file path — don't delete until confirmed
    var createdAt: Date
    var retryCount: Int
    var status: String // "pending", "uploading", "failed"
    var lastError: String?
    // The account that created this item, stamped at enqueue. The queue drains
    // whenever the network returns — if we resolved the owner from "whoever is
    // signed in now," a memo recorded offline by user A could drain into user
    // B's account after a device hand-off (A signs out, B signs in). Optional
    // so pre-existing rows from before this field migrate cleanly.
    var ownerUserId: String?

    init(type: String, payload: Data, localFilePath: String? = nil, ownerUserId: String? = nil) {
        self.id = UUID()
        self.type = type
        self.payload = payload
        self.localFilePath = localFilePath
        self.createdAt = Date()
        self.retryCount = 0
        self.status = "pending"
        self.ownerUserId = ownerUserId
    }
}

// MARK: - Offline Queue Manager

@Observable
final class OfflineQueueManager {
    static let shared = OfflineQueueManager()

    var pendingCount: Int = 0
    var failedCount: Int = 0
    var isDraining = false

    private var container: ModelContainer?
    private let logger = Logger(subsystem: "com.postrundrip.app", category: "OfflineQueue")
    private var drainTask: Task<Void, Never>?

    private init() {
        do {
            container = try ModelContainer(for: PendingUpload.self)
            Task { refreshCount() }
        } catch {
            logger.error("Failed to create SwiftData container: \(error.localizedDescription)")
            Task { ErrorReporter.shared.report(error, context: "OfflineQueueManager.init: Failed to create SwiftData container") }
        }
    }

    // MARK: - Enqueue

    /// Queue a voice log upload for later. Preserves the audio file until upload succeeds.
    @MainActor
    func enqueueVoiceLog(audioURL: URL, notes: String?, mood: String?, workoutDate: Date?, source: String = "voice_log") {
        guard let container else { return }
        let context = container.mainContext

        var payloadDict: [String: String] = [:]
        payloadDict["audioPath"] = audioURL.path
        payloadDict["source"] = source
        if let notes { payloadDict["notes"] = notes }
        if let mood { payloadDict["mood"] = mood }
        if let date = workoutDate { payloadDict["workoutDate"] = ISO8601DateFormatter().string(from: date) }

        guard let payloadData = try? JSONEncoder().encode(payloadDict) else { return }

        let upload = PendingUpload(type: "voiceLog", payload: payloadData, localFilePath: audioURL.path, ownerUserId: AuthManager.shared.currentUserId)
        context.insert(upload)
        do {
            try context.save()
        } catch {
            Log.app.error("SwiftData save failed (enqueue voice log): \(error)")
            ErrorReporter.shared.report(error, context: "OfflineQueue: failed to persist voice log to queue")
        }
        refreshCountSync(context: context)
        logger.info("Queued voice log upload: \(upload.id)")
    }

    /// Queue a manual workout for later.
    @MainActor
    func enqueueManualWorkout(payload: [String: Any]) {
        guard let container else { return }
        let context = container.mainContext

        guard let payloadData = try? JSONSerialization.data(withJSONObject: payload) else { return }

        let upload = PendingUpload(type: "manualWorkout", payload: payloadData, ownerUserId: AuthManager.shared.currentUserId)
        context.insert(upload)
        do {
            try context.save()
        } catch {
            Log.app.error("SwiftData save failed (enqueue manual workout): \(error)")
            ErrorReporter.shared.report(error, context: "OfflineQueue: failed to persist manual workout to queue")
        }
        refreshCountSync(context: context)
        logger.info("Queued manual workout upload")
    }

    /// Queue a generic training log update.
    @MainActor
    func enqueueTrainingLog(payload: Data) {
        guard let container else { return }
        let context = container.mainContext

        let upload = PendingUpload(type: "trainingLog", payload: payload, ownerUserId: AuthManager.shared.currentUserId)
        context.insert(upload)
        do {
            try context.save()
        } catch {
            Log.app.error("SwiftData save failed (enqueue training log): \(error)")
            ErrorReporter.shared.report(error, context: "OfflineQueue: failed to persist training log to queue")
        }
        refreshCountSync(context: context)
    }

    // MARK: - Drain Queue

    /// Attempt to upload all pending items. Call when network becomes available.
    func drainQueue() {
        guard !isDraining else { return }
        drainTask?.cancel()
        drainTask = Task {
            await performDrain()
        }
    }

    @MainActor
    private func performDrain() async {
        guard let container else { return }
        isDraining = true
        defer { isDraining = false }

        let context = container.mainContext

        // Purge unrecoverable items first: if the recording an item needs is no
        // longer on disk (Documents container reset on reinstall, or the file
        // was deleted), the upload can NEVER succeed. Retrying only burns the
        // attempt budget and fires a misleading "saved on this device, we'll
        // retry" banner. Drop these quietly — including ones already marked
        // "failed" — so a dead memo from a past install stops nagging.
        purgeUnrecoverable(context: context)

        // Exclude "failed" (retryCount maxed out) as well as in-flight items.
        // Without this, a permanently-failed row keeps matching the fetch, gets
        // re-processed on every drain, re-hits the retry cap, and re-fires its
        // error banner forever. "failed" rows stay on disk (recording preserved)
        // but are inert until something explicitly re-queues them.
        let descriptor = FetchDescriptor<PendingUpload>(
            predicate: #Predicate { $0.status != "uploading" && $0.status != "failed" },
            sortBy: [SortDescriptor(\.createdAt)]
        )

        guard let uploads = try? context.fetch(descriptor), !uploads.isEmpty else {
            return
        }

        logger.info("Draining offline queue: \(uploads.count) items")

        let currentUserId = AuthManager.shared.currentUserId

        for upload in uploads {
            guard !Task.isCancelled else { break }

            // Ownership guard: never upload an item into an account other than
            // the one that created it. If the signed-in user doesn't match the
            // item's stamped owner, leave it queued and skip — the sign-out
            // purge is what removes another account's items from this device.
            // (Items with a nil owner predate this field; allow them through
            // for backward compatibility.)
            if let owner = upload.ownerUserId, owner != currentUserId {
                logger.error("Skipping queued upload owned by a different account: \(upload.id) (\(upload.type))")
                continue
            }

            upload.status = "uploading"
            do { try context.save() } catch { Log.app.error("SwiftData save failed (mark uploading): \(error)") }

            let success = await processUpload(upload)

            if success {
                // Delete the local audio file now that it's uploaded
                if let filePath = upload.localFilePath {
                    try? FileManager.default.removeItem(atPath: filePath)
                }
                context.delete(upload)
                do { try context.save() } catch { Log.app.error("SwiftData save failed (delete after upload): \(error)") }
                logger.info("Upload succeeded: \(upload.id) (\(upload.type))")
            } else {
                upload.retryCount += 1
                if upload.retryCount >= 5 {
                    // Permanent failure: mark "failed" so the drain fetch (which
                    // now excludes "failed") stops re-attempting it — ending the
                    // retry-forever loop that re-fired this banner every drain.
                    // The recording stays on disk; we preserve, not purge.
                    upload.status = "failed"
                    logger.error("Upload permanently failed after \(upload.retryCount) attempts: \(upload.id) (\(upload.type))")
                    let noun: String
                    switch upload.type {
                    case "voiceLog": noun = "voice memo"
                    case "checkIn": noun = "check-in"
                    default: noun = "recording"
                    }
                    ErrorReporter.shared.report(
                        .processing("Your \(noun) couldn't upload after several tries. It's saved on this device and we'll retry next time you're online."),
                        retry: nil
                    )
                } else {
                    upload.status = "pending"
                    logger.warning("Upload failed (attempt \(upload.retryCount)): \(upload.id)")
                }
                do { try context.save() } catch { Log.app.error("SwiftData save failed (update retry status): \(error)") }
            }

            refreshCountSync(context: context)
        }
    }

    /// The expected recording path for items that carry an audio file
    /// (`voiceLog` / `checkIn`), or nil when the item needs no local file or
    /// the payload can't be read. Used to detect items whose recording is gone.
    private func recordingPath(for upload: PendingUpload) -> String? {
        guard upload.type == "voiceLog" || upload.type == "checkIn" else { return nil }
        guard let dict = try? JSONDecoder().decode([String: String].self, from: upload.payload) else { return nil }
        return dict["audioPath"]
    }

    /// Drops queue items whose local recording no longer exists — they can
    /// never upload, so keeping them only produces false "we'll retry" banners.
    private func purgeUnrecoverable(context: ModelContext) {
        guard let items = try? context.fetch(FetchDescriptor<PendingUpload>()) else { return }
        var purged = 0
        for item in items {
            guard let path = recordingPath(for: item),
                  !FileManager.default.fileExists(atPath: path) else { continue }
            logger.error("Purging unrecoverable upload — recording no longer on device: \(item.id) (\(item.type))")
            if let filePath = item.localFilePath {
                try? FileManager.default.removeItem(atPath: filePath)
            }
            context.delete(item)
            purged += 1
        }
        if purged > 0 {
            do { try context.save() } catch { Log.app.error("SwiftData save failed (purge unrecoverable): \(error)") }
            refreshCountSync(context: context)
            logger.info("Purged \(purged) unrecoverable upload(s) with missing recordings")
        }
    }

    private func processUpload(_ upload: PendingUpload) async -> Bool {
        switch upload.type {
        case "voiceLog":
            return await uploadVoiceLog(upload)
        case "manualWorkout":
            return await uploadManualWorkout(upload)
        case "trainingLog":
            return await uploadTrainingLog(upload)
        default:
            logger.error("Unknown upload type: \(upload.type)")
            return false
        }
    }

    private func uploadVoiceLog(_ upload: PendingUpload) async -> Bool {
        guard let dict = try? JSONDecoder().decode([String: String].self, from: upload.payload),
              let audioPath = dict["audioPath"] else { return false }

        let audioURL = URL(fileURLWithPath: audioPath)
        guard FileManager.default.fileExists(atPath: audioPath) else {
            logger.error("Audio file missing at: \(audioPath)")
            return false
        }

        // Must have a real authenticated user — otherwise the storage path
        // and RLS insert would both be wrong. Keep the item queued.
        guard let userId = AuthManager.shared.currentUserId, !userId.isEmpty else {
            logger.error("uploadVoiceLog: no authenticated user — keeping item queued")
            upload.lastError = "Not signed in"
            return false
        }

        // Hold a VALID session before writing. A missing/expired session makes
        // the upload go out unauthenticated, which storage rejects with 403
        // "new row violates row-level security policy" — stranding orphaned
        // audio with no training_logs row (the bug that broke voice memos).
        // `auth.session` auto-refreshes an expired token; if there's genuinely
        // no session, keep the item queued and bail quietly instead of firing
        // an anonymous upload that 403s and spams the error banner.
        do {
            _ = try await supabase.auth.session
        } catch {
            upload.lastError = "No valid session — sign in to upload"
            logger.error("uploadVoiceLog: no valid auth session, keeping item queued: \(error.localizedDescription)")
            return false
        }

        do {
            let audioData = try Data(contentsOf: audioURL)

            // Step 1: upload audio via the service-role edge function. Direct
            // storage uploads (SDK or explicit-bearer) are rejected by the
            // storage service since 2026-06-02 — RLS "Unauthorized" on a valid
            // JWT, even though the bucket policy is PUBLIC. upload-voice-memo
            // writes with the service role, bypassing that broken layer.
            let audioPublicURL = try await uploadVoiceMemoAudio(audioData)

            // Step 2: insert the training_logs row over PostgREST (which works).
            // The DB trigger (pg_net → process-training-memo) picks it up.
            var insertData = TrainingLogInsert(audioUrl: audioPublicURL)
            insertData.userId = userId
            insertData.processingStatus = "pending"
            insertData.source = dict["source"] ?? "voice_log"
            if let dateStr = dict["workoutDate"],
               let date = ISO8601DateFormatter().date(from: dateStr) {
                insertData.workoutDate = date
            }

            _ = try await supabase
                .from("training_logs")
                .insert(insertData)
                .execute()

            await MainActor.run { AthletePaceProfileService.shared.scheduleRefresh() }
            return true
        } catch {
            upload.lastError = error.localizedDescription
            logger.error("Voice log upload failed: \(error.localizedDescription)")
            ErrorReporter.shared.report(error, context: "OfflineQueueManager.uploadVoiceLog: Voice log upload failed for item \(upload.id)")
            return false
        }
    }

    private func uploadManualWorkout(_ upload: PendingUpload) async -> Bool {
        do {
            let body = try JSONSerialization.jsonObject(with: upload.payload) as? [String: Any] ?? [:]
            _ = try await callEdgeFunction(name: "log-manual-workout", body: body)
            await MainActor.run { AthletePaceProfileService.shared.scheduleRefresh() }
            return true
        } catch {
            upload.lastError = error.localizedDescription
            ErrorReporter.shared.report(error, context: "OfflineQueueManager.uploadManualWorkout: Manual workout upload failed for item \(upload.id)")
            return false
        }
    }

    private func uploadTrainingLog(_ upload: PendingUpload) async -> Bool {
        do {
            let body = try JSONSerialization.jsonObject(with: upload.payload) as? [String: Any] ?? [:]
            _ = try await callEdgeFunction(name: "log-training", body: body)
            await MainActor.run { AthletePaceProfileService.shared.scheduleRefresh() }
            return true
        } catch {
            upload.lastError = error.localizedDescription
            ErrorReporter.shared.report(error, context: "OfflineQueueManager.uploadTrainingLog: Training log upload failed for item \(upload.id)")
            return false
        }
    }

    // MARK: - Sign-out purge

    /// Clears every queued item and its on-disk audio. Called on sign-out so a
    /// departing account leaves nothing behind for the next person to sign in
    /// on the same device — the cross-account voice-memo leak fix. Any pending
    /// upload cancels; a queued memo that never made it up is lost by design
    /// (correct-account integrity beats retrying it into the wrong account).
    @MainActor
    func purgeAllForSignOut() {
        drainTask?.cancel()
        guard let container else { return }
        let context = container.mainContext
        guard let items = try? context.fetch(FetchDescriptor<PendingUpload>()) else { return }
        var purged = 0
        for item in items {
            if let filePath = item.localFilePath {
                try? FileManager.default.removeItem(atPath: filePath)
            }
            context.delete(item)
            purged += 1
        }
        if purged > 0 {
            do { try context.save() } catch { Log.app.error("SwiftData save failed (purge on sign-out): \(error)") }
            logger.info("Purged \(purged) queued upload(s) on sign-out")
        }
        refreshCountSync(context: context)
    }

    // MARK: - Count

    @MainActor
    private func refreshCountSync(context: ModelContext) {
        let pendingDescriptor = FetchDescriptor<PendingUpload>(
            predicate: #Predicate { $0.status != "failed" }
        )
        pendingCount = (try? context.fetchCount(pendingDescriptor)) ?? 0

        let failedDescriptor = FetchDescriptor<PendingUpload>(
            predicate: #Predicate { $0.status == "failed" }
        )
        failedCount = (try? context.fetchCount(failedDescriptor)) ?? 0
    }

    @MainActor
    func refreshCount() {
        guard let container else { return }
        refreshCountSync(context: container.mainContext)
    }
}
