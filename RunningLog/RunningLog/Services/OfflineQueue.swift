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
    func enqueueVoiceLog(audioURL: URL, notes: String?, mood: String?, workoutDate: Date?) {
        guard let container else { return }
        let context = container.mainContext

        var payloadDict: [String: String] = [:]
        payloadDict["audioPath"] = audioURL.path
        if let notes { payloadDict["notes"] = notes }
        if let mood { payloadDict["mood"] = mood }
        if let date = workoutDate { payloadDict["workoutDate"] = ISO8601DateFormatter().string(from: date) }

        guard let payloadData = try? JSONEncoder().encode(payloadDict) else { return }

        let upload = PendingUpload(type: "voiceLog", payload: payloadData, localFilePath: audioURL.path)
        context.insert(upload)
        try? context.save()
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
        try? context.save()
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
        try? context.save()
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
            try? context.save()

            let success = await processUpload(upload)

            if success {
                // Delete the local audio file now that it's uploaded
                if let filePath = upload.localFilePath {
                    try? FileManager.default.removeItem(atPath: filePath)
                }
                context.delete(upload)
                try? context.save()
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
                try? context.save()
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

        do {
            let audioData = try Data(contentsOf: audioURL)
            let userId = AuthManager.shared.currentUserId ?? ""
            let fileName = "\(userId)/\(Date().ISO8601Format())/\(UUID().uuidString).m4a"

            try await supabase.storage
                .from("training-memos")
                .upload(fileName, data: audioData, options: .init(contentType: "audio/m4a"))

            let publicURL = try supabase.storage
                .from("training-memos")
                .getPublicURL(path: fileName)

            let logData: [String: Any] = [
                "audio_url": publicURL.absoluteString,
                "notes": dict["notes"] ?? "",
                "mood": dict["mood"] ?? "neutral",
                "user_id": userId,
                "processing_status": "pending",
            ]

            _ = try await callEdgeFunction(name: "process-training-memo", body: logData)
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
