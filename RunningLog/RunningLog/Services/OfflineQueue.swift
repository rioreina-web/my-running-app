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

    init(type: String, payload: Data, localFilePath: String? = nil) {
        self.id = UUID()
        self.type = type
        self.payload = payload
        self.localFilePath = localFilePath
        self.createdAt = Date()
        self.retryCount = 0
        self.status = "pending"
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

        let upload = PendingUpload(type: "voiceLog", payload: payloadData, localFilePath: audioURL.path)
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

        let upload = PendingUpload(type: "manualWorkout", payload: payloadData)
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

        let upload = PendingUpload(type: "trainingLog", payload: payload)
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
        let descriptor = FetchDescriptor<PendingUpload>(
            predicate: #Predicate { $0.status != "uploading" },
            sortBy: [SortDescriptor(\.createdAt)]
        )

        guard let uploads = try? context.fetch(descriptor), !uploads.isEmpty else {
            return
        }

        logger.info("Draining offline queue: \(uploads.count) items")

        for upload in uploads {
            guard !Task.isCancelled else { break }

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
                    upload.status = "failed"
                    logger.error("Upload permanently failed after \(upload.retryCount) attempts: \(upload.id) (\(upload.type))")
                    ErrorReporter.shared.report(
                        .processing("A queued \(upload.type) upload failed after multiple retries and has been discarded."),
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
            let fileName = "\(userId)/\(UUID().uuidString).m4a"

            // Step 1: upload audio to storage with an EXPLICIT bearer token.
            // The SDK storage client wasn't attaching the user JWT — reads via
            // .from() carry it, but .storage.upload() went out unauthenticated,
            // so storage rejected it 400/403 "new row violates row-level
            // security policy". Send the token by hand (same approach as
            // callEdgeFunction, which works), and surface the real storage
            // error body if it still fails.
            let accessToken = try await supabase.auth.session.accessToken
            guard let uploadURL = URL(string: "\(supabaseURL)/storage/v1/object/training-memos/\(fileName)") else {
                throw URLError(.badURL)
            }
            var uploadReq = URLRequest(url: uploadURL)
            uploadReq.httpMethod = "POST"
            uploadReq.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            uploadReq.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
            uploadReq.setValue("audio/m4a", forHTTPHeaderField: "Content-Type")
            uploadReq.setValue("true", forHTTPHeaderField: "x-upsert")
            let (upRespData, upResp) = try await URLSession.shared.upload(for: uploadReq, from: audioData)
            if let http = upResp as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
                let body = String(data: upRespData, encoding: .utf8) ?? ""
                throw NSError(domain: "VoiceUpload", code: http.statusCode,
                              userInfo: [NSLocalizedDescriptionKey: "Storage upload \(http.statusCode): \(body)"])
            }

            guard let publicURL = URL(string: "\(supabaseURL)/storage/v1/object/public/training-memos/\(fileName)") else {
                throw URLError(.badURL)
            }

            // Step 2: insert the training_logs row exactly like the live path.
            // The DB trigger (pg_net → process-training-memo) picks it up from
            // there; we must NOT POST flat fields to the edge function (that
            // body shape is rejected and skips the row insert entirely).
            var insertData = TrainingLogInsert(audioUrl: publicURL.absoluteString)
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
