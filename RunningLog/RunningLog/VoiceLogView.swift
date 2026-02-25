import AVFoundation
import os
import PostgREST
import Storage
import Supabase
import SwiftUI

// MARK: - TrainingLog

struct TrainingLog: Codable {
    let id: UUID
    let createdAt: Date?
    let audioUrl: String?
    let notes: String?
    let cleanedNotes: String?
    let mood: String?
    let workoutDate: Date?
    let workoutDistanceMiles: Double?
    let workoutDurationMinutes: Double?
    let processingStatus: String?
    let processingError: String?
    let processingAttempts: Int?
    let transcriptUrl: String?
    let coachInsight: String?
    let workoutNotes: String?
    let workoutPacePerMile: String?
    let workoutType: String?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case audioUrl = "audio_url"
        case notes
        case cleanedNotes = "cleaned_notes"
        case mood
        case workoutDate = "workout_date"
        case workoutDistanceMiles = "workout_distance_miles"
        case workoutDurationMinutes = "workout_duration_minutes"
        case processingStatus = "processing_status"
        case processingError = "processing_error"
        case processingAttempts = "processing_attempts"
        case transcriptUrl = "transcript_url"
        case coachInsight = "coach_insight"
        case workoutNotes = "workout_notes"
        case workoutPacePerMile = "workout_pace_per_mile"
        case workoutType = "workout_type"
    }

    var isPending: Bool {
        processingStatus == "pending" || processingStatus == "processing"
    }

    var isFailed: Bool {
        processingStatus == "failed"
    }

    var isCompleted: Bool {
        processingStatus == "completed"
    }

    var workoutTypeLabel: String? {
        guard let type = workoutType else { return nil }
        switch type {
        case "easy": return "Easy"
        case "tempo": return "Tempo"
        case "interval": return "Intervals"
        case "long_run": return "Long Run"
        case "recovery": return "Recovery"
        case "race": return "Race"
        case "other": return "Workout"
        default: return nil
        }
    }
}

// MARK: - TrainingLogInsert

struct TrainingLogInsert: Codable {
    var userId: String?
    var audioUrl: String?
    var notes: String?
    var workoutDate: Date?
    var workoutDistanceMiles: Double?
    var workoutDurationMinutes: Double?
    var processingStatus: String?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case audioUrl = "audio_url"
        case notes
        case workoutDate = "workout_date"
        case workoutDistanceMiles = "workout_distance_miles"
        case workoutDurationMinutes = "workout_duration_minutes"
        case processingStatus = "processing_status"
    }
}

// MARK: - VoiceLogView

struct VoiceLogView: View {
    @StateObject private var healthKitManager = HealthKitManager()
    @State private var isRecording = false
    @State private var audioRecorder: AVAudioRecorder?
    @State private var recordingURL: URL?
    @State private var manualNotes = ""
    @State private var isUploading = false
    @State private var statusMessage = ""
    @State private var recordingDuration: TimeInterval = 0
    @State private var timer: Timer?
    @State private var selectedWorkout: RunningWorkout?
    @State private var showWorkoutPicker = false
    @State private var showConfirmation = false
    @State private var pendingRecordingDuration: TimeInterval = 0
    @State private var showSuccessAnimation = false
    @FocusState private var isTextEditorFocused: Bool

    // History state
    @State private var historyLogs: [TrainingLog] = []
    @State private var isLoadingHistory = false

    // Feed state
    @State private var selectedHistoryEntry: HistoryLogEntry?

    var body: some View {
        ZStack {
            DripBackground()

            ScrollView {
                VStack(spacing: 0) {
                    // Hero section with record button
                    VStack(spacing: 24) {
                        // Status pill
                        if !statusMessage.isEmpty {
                            StatusPill(message: statusMessage, isError: statusMessage.contains("Error"))
                                .transition(.asymmetric(
                                    insertion: .move(edge: .top).combined(with: .opacity),
                                    removal: .opacity
                                ))
                        }

                        Spacer()
                            .frame(height: 40)

                        // Recording duration
                        if isRecording {
                            Text(formatDuration(recordingDuration))
                                .font(.dripStat(48))
                                .foregroundStyle(Color.drip.textPrimary)
                                .contentTransition(.numericText())
                                .animation(.spring(response: 0.3), value: recordingDuration)
                        } else {
                            Text("Log Your Run")
                                .font(.dripDisplay(32))
                                .foregroundStyle(Color.drip.textPrimary)
                        }

                        Text(isRecording ? "Recording your thoughts..." : "Tap to start voice memo")
                            .font(.dripBody(15))
                            .foregroundStyle(Color.drip.textSecondary)

                        // Workout selector
                        WorkoutSelectorButton(
                            selectedWorkout: selectedWorkout,
                            onTap: { showWorkoutPicker = true }
                        )

                        Spacer()
                            .frame(height: 20)

                        // Record button
                        PulsingRecordButton(
                            isRecording: isRecording,
                            isDisabled: isUploading
                        ) {
                            toggleRecording()
                        }

                        Spacer()
                            .frame(height: 60)
                    }
                    .frame(minHeight: 420)
                    .padding(.horizontal, 24)

                    // Manual notes section
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeader("Or type your notes")

                        ZStack(alignment: .topLeading) {
                            if manualNotes.isEmpty {
                                Text("How did your run feel today?")
                                    .font(.dripBody(15))
                                    .foregroundStyle(Color.drip.textTertiary)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 14)
                            }

                            TextEditor(text: $manualNotes)
                                .font(.dripBody(15))
                                .foregroundStyle(Color.drip.textPrimary)
                                .scrollContentBackground(.hidden)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .focused($isTextEditorFocused)
                        }
                        .frame(minHeight: 120)
                        .background(Color.drip.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(isTextEditorFocused ? Color.drip.coral.opacity(0.5) : Color.drip.divider, lineWidth: 1)
                        )

                        DripButton("Save Notes", icon: "arrow.up.circle.fill", isLoading: isUploading && !manualNotes.isEmpty) {
                            saveManualNotes()
                        }
                        .disabled(manualNotes.isEmpty)
                        .opacity(manualNotes.isEmpty ? 0.5 : 1)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)

                    // Your Logs feed
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            SectionHeader("Your Logs")
                            Spacer()
                            Button {
                                Task { await loadHistory() }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(Color.drip.textSecondary)
                            }
                        }

                        if isLoadingHistory && historyLogs.isEmpty {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .tint(Color.drip.coral)
                                Spacer()
                            }
                            .padding(.vertical, 40)
                        } else if historyLogs.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "text.bubble")
                                    .font(.system(size: 32))
                                    .foregroundStyle(Color.drip.textTertiary)
                                Text("No logs yet")
                                    .font(.dripBody(14))
                                    .foregroundStyle(Color.drip.textSecondary)
                                Text("Record a voice memo or type notes to get started")
                                    .font(.dripCaption(12))
                                    .foregroundStyle(Color.drip.textTertiary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(historyLogs, id: \.id) { log in
                                    if log.isPending || log.isFailed {
                                        ProcessingLogCard(log: log) {
                                            Task { await retryProcessing(log: log) }
                                        }
                                    } else {
                                        HistoryEntryCard(entry: log.asHistoryEntry)
                                            .onTapGesture {
                                                selectedHistoryEntry = log.asHistoryEntry
                                            }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture {
                isTextEditorFocused = false
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                SidebarMenuButton()
            }
            ToolbarItem(placement: .principal) {
                Text("VOICE LOG")
                    .font(.dripCaption(12))
                    .foregroundStyle(Color.drip.textSecondary)
                    .tracking(2)
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    isTextEditorFocused = false
                }
                .font(.dripBody(15))
                .foregroundStyle(Color.drip.coral)
            }
        }
        .toolbarBackground(Color.drip.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear {
            setupAudioSession()
            Task {
                _ = await healthKitManager.requestAuthorization()
                let workouts = await healthKitManager.fetchRecentRunningWorkouts(limit: 20)
                await MainActor.run { healthKitManager.recentWorkouts = workouts }
                await loadHistory()
            }
        }
        .animation(.spring(response: 0.4), value: statusMessage)
        .sheet(isPresented: $showWorkoutPicker) {
            WorkoutPickerSheet(
                workouts: healthKitManager.recentWorkouts,
                selectedWorkout: $selectedWorkout,
                isPresented: $showWorkoutPicker
            )
        }
        .sheet(isPresented: $showConfirmation) {
            RecordingConfirmationSheet(
                duration: pendingRecordingDuration,
                selectedWorkout: $selectedWorkout,
                workouts: healthKitManager.recentWorkouts,
                onConfirm: confirmAndUpload,
                onDiscard: discardRecording
            )
            .interactiveDismissDisabled()
        }
        .overlay {
            if showSuccessAnimation {
                SuccessOverlay()
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .sheet(item: $selectedHistoryEntry) { entry in
            HistoryDetailSheet(entry: entry) {
                Task { await loadHistory() }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default)
            try session.setActive(true)
        } catch {
            statusMessage = "Error: Failed to setup audio"
        }
    }

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        let fileName = "training_memo_\(Date().timeIntervalSince1970).m4a"
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audioURL = documentsPath.appendingPathComponent(fileName)

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: audioURL, settings: settings)
            audioRecorder?.record()
            recordingURL = audioURL
            isRecording = true
            statusMessage = ""
            recordingDuration = 0

            // Start timer
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                recordingDuration += 1
            }
        } catch {
            statusMessage = "Error: Failed to start recording"
        }
    }

    private func stopRecording() {
        audioRecorder?.stop()
        timer?.invalidate()
        timer = nil
        isRecording = false
        pendingRecordingDuration = recordingDuration

        guard recordingURL != nil else {
            statusMessage = "Error: No recording found"
            return
        }

        // Show confirmation sheet instead of uploading directly
        showConfirmation = true
    }

    private func confirmAndUpload() {
        guard let url = recordingURL else { return }
        showConfirmation = false

        Task {
            await uploadAudioAndSaveLog(localURL: url)
        }
    }

    private func discardRecording() {
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordingURL = nil
        recordingDuration = 0
        pendingRecordingDuration = 0
        showConfirmation = false
        statusMessage = ""
    }

    private func uploadAudioAndSaveLog(localURL: URL) async {
        isUploading = true
        statusMessage = "Uploading..."

        do {
            let audioData = try Data(contentsOf: localURL)
            let fileName = localURL.lastPathComponent
            let userId = AuthManager.shared.currentUserId ?? ""
            let storagePath = "\(userId)/\(fileName)"

            try await supabase.storage
                .from("training-memos")
                .upload(storagePath, data: audioData, options: FileOptions(contentType: "audio/m4a"))

            let publicURL = try supabase.storage
                .from("training-memos")
                .getPublicURL(path: storagePath)

            // Build insert data with optional workout fields
            var insertData = TrainingLogInsert(audioUrl: publicURL.absoluteString)
            insertData.userId = userId
            insertData.processingStatus = "pending"
            if let workout = selectedWorkout {
                insertData.workoutDate = workout.startDate
                insertData.workoutDistanceMiles = workout.distanceMiles
                insertData.workoutDurationMinutes = workout.durationMinutes
            }

            let response: [TrainingLog] = try await supabase
                .from("training_logs")
                .insert(insertData)
                .select()
                .execute()
                .value

            try? FileManager.default.removeItem(at: localURL)

            await MainActor.run {
                statusMessage = "Processing with AI..."
            }

            var processingSuccess = false
            if let insertedLog = response.first {
                processingSuccess = await callProcessingFunction(record: insertedLog)
            }

            await MainActor.run {
                recordingURL = nil
                isUploading = false
                recordingDuration = 0
                pendingRecordingDuration = 0
                selectedWorkout = nil

                if processingSuccess {
                    statusMessage = ""
                    // Show success animation
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                        showSuccessAnimation = true
                    }

                    // Hide success animation after delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        withAnimation {
                            showSuccessAnimation = false
                        }
                    }
                } else {
                    // Show warning that processing is still pending
                    statusMessage = "Saved! Transcription will complete in background."
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                        if statusMessage.contains("background") {
                            statusMessage = ""
                        }
                    }
                }
            }

            // Reload history to show new entry
            await loadHistory()
        } catch {
            await MainActor.run {
                statusMessage = "Error: \(error.localizedDescription)"
                isUploading = false
            }
        }
    }

    private func callProcessingFunction(record: TrainingLog, maxRetries: Int = 3) async -> Bool {
        let payload: [String: Any] = [
            "type": "INSERT",
            "table": "training_logs",
            "schema": "public",
            "record": [
                "id": record.id.uuidString,
                "audio_url": record.audioUrl ?? ""
            ]
        ]

        for attempt in 1...maxRetries {
            do {
                Log.app.info("Processing attempt \(attempt) of \(maxRetries) for record \(record.id)")

                // Call edge function with timeout
                let result = try await withTimeout(seconds: 60) {
                    try await callEdgeFunction(name: "process-training-memo", body: payload)
                }

                // Parse response
                if let json = try? JSONSerialization.jsonObject(with: result) as? [String: Any] {
                    // Success
                    if let success = json["success"] as? Bool, success {
                        Log.app.info("Processing completed successfully for record \(record.id)")
                        return true
                    }

                    // 409 — already processing, skip to polling without consuming retry
                    if let status = json["status"] as? String, status == "processing" {
                        Log.app.info("Record \(record.id) already processing, polling for completion...")
                        if await pollForCompletion(recordId: record.id, maxWait: 60) {
                            return true
                        }
                        continue
                    }

                    // Error response
                    if let errorMsg = json["error"] as? String {
                        Log.app.error("Processing returned error: \(errorMsg)")
                    }
                }

                // Poll for completion status
                if await pollForCompletion(recordId: record.id, maxWait: 30) {
                    return true
                }

            } catch {
                Log.app.error("Processing attempt \(attempt) failed: \(error)")

                // Exponential backoff before retry
                if attempt < maxRetries {
                    let delay = Double(1 << attempt) // 2s, 4s, 8s
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }

        Log.app.error("All processing attempts failed for record \(record.id)")
        return false
    }

    private func pollForCompletion(recordId: UUID, maxWait: Int) async -> Bool {
        let pollInterval: UInt64 = 2_000_000_000 // 2 seconds
        let maxAttempts = maxWait / 2

        for _ in 0..<maxAttempts {
            do {
                let logs: [TrainingLog] = try await supabase
                    .from("training_logs")
                    .select()
                    .eq("id", value: recordId.uuidString)
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

    private func saveManualNotes() {
        guard !manualNotes.isEmpty else { return }

        isUploading = true
        statusMessage = "Saving notes..."

        Task {
            do {
                // Build insert data with optional workout fields
                var insertData = TrainingLogInsert(notes: manualNotes)
                insertData.processingStatus = "not_required" // Manual notes don't need AI processing
                if let workout = selectedWorkout {
                    insertData.workoutDate = workout.startDate
                    insertData.workoutDistanceMiles = workout.distanceMiles
                    insertData.workoutDurationMinutes = workout.durationMinutes
                }

                try await supabase
                    .from("training_logs")
                    .insert(insertData)
                    .execute()

                await MainActor.run {
                    statusMessage = "Notes saved!"
                    manualNotes = ""
                    isUploading = false
                    selectedWorkout = nil

                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        if statusMessage == "Notes saved!" {
                            statusMessage = ""
                        }
                    }
                }

                // Reload history
                await loadHistory()
            } catch {
                await MainActor.run {
                    statusMessage = "Error: \(error.localizedDescription)"
                    isUploading = false
                }
            }
        }
    }

    private func loadHistory() async {
        await MainActor.run {
            isLoadingHistory = true
        }

        do {
            let logs: [TrainingLog] = try await supabase
                .from("training_logs")
                .select()
                .order("created_at", ascending: false)
                .limit(50)
                .execute()
                .value

            await MainActor.run {
                historyLogs = logs
                isLoadingHistory = false
            }

            // Auto-retry stale pending/processing records (older than 5 minutes)
            await autoRetryStaleRecords(logs: logs)
        } catch {
            Log.app.error("Failed to load history: \(error)")
            await MainActor.run {
                isLoadingHistory = false
            }
        }
    }

    private func autoRetryStaleRecords(logs: [TrainingLog]) async {
        let fiveMinutesAgo = Date().addingTimeInterval(-5 * 60)

        // Find the first stale pending record with audio
        guard let staleLog = logs.first(where: { log in
            log.isPending &&
            log.audioUrl != nil &&
            (log.createdAt ?? Date()) < fiveMinutesAgo
        }) else { return }

        Log.app.info("Auto-retrying stale record \(staleLog.id)")
        let success = await callProcessingFunction(record: staleLog, maxRetries: 1)

        if success {
            await loadHistory()
        }
    }

    private func retryProcessing(log: TrainingLog) async {
        guard log.audioUrl != nil else { return }

        await MainActor.run {
            statusMessage = "Retrying transcription..."
        }

        let success = await callProcessingFunction(record: log, maxRetries: 2)

        await MainActor.run {
            if success {
                statusMessage = "Transcription completed!"
            } else {
                statusMessage = "Retry failed. Try again later."
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                statusMessage = ""
            }
        }

        await loadHistory()
    }
}

// MARK: - TrainingLog → HistoryLogEntry

extension TrainingLog {
    var asHistoryEntry: HistoryLogEntry {
        HistoryLogEntry(
            id: id,
            createdAt: createdAt ?? Date(),
            audioUrl: audioUrl,
            notes: notes,
            cleanedNotes: cleanedNotes,
            mood: mood,
            workoutDate: workoutDate,
            workoutDistanceMiles: workoutDistanceMiles,
            workoutDurationMinutes: workoutDurationMinutes,
            coachInsight: coachInsight,
            workoutNotes: workoutNotes,
            workoutType: workoutType,
            workoutPacePerMile: workoutPacePerMile
        )
    }
}

// MARK: - ProcessingLogCard

struct ProcessingLogCard: View {
    let log: TrainingLog
    let onRetry: () -> Void

    private var dateString: String {
        let date = log.workoutDate ?? log.createdAt
        if let date {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
        return "Unknown date"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: log.isFailed ? "exclamationmark.circle.fill" : "clock.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(log.isFailed ? Color.drip.tired : Color.drip.coral)

                Text(dateString)
                    .font(.dripCaption(12))
                    .foregroundStyle(Color.drip.textSecondary)

                Spacer()

                if log.audioUrl != nil {
                    HStack(spacing: 4) {
                        Image(systemName: "waveform")
                            .font(.system(size: 10, weight: .medium))
                        Text("Voice")
                            .font(.dripCaption(10))
                    }
                    .foregroundStyle(Color.drip.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.drip.cardBackgroundElevated)
                    .clipShape(Capsule())
                }
            }

            if log.isPending {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(Color.drip.coral)
                    Text("Processing with AI...")
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.coral)
                }
            } else if log.isFailed {
                Button(action: onRetry) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Retry transcription")
                            .font(.dripCaption(11))
                    }
                    .foregroundStyle(Color.drip.tired)
                }
            }
        }
        .padding(14)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.drip.divider, lineWidth: 1)
        )
    }
}

// MARK: - StatusPill

struct StatusPill: View {
    let message: String
    let isError: Bool

    var body: some View {
        HStack(spacing: 8) {
            if message.contains("Processing") {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(0.7)
            } else {
                Image(systemName: isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
            }

            Text(message)
                .font(.dripCaption(13))
                .fontWeight(.medium)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isError ? Color.drip.injured : Color.drip.success)
        .clipShape(Capsule())
    }
}

// MARK: - WorkoutSelectorButton

struct WorkoutSelectorButton: View {
    let selectedWorkout: RunningWorkout?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: selectedWorkout != nil ? "figure.run.circle.fill" : "figure.run.circle")
                    .font(.system(size: 24))
                    .foregroundStyle(selectedWorkout != nil ? Color.drip.energized : Color.drip.textSecondary)

                VStack(alignment: .leading, spacing: 2) {
                    if let workout = selectedWorkout {
                        Text(workout.formattedDate)
                            .font(.dripBody(14))
                            .foregroundStyle(Color.drip.textPrimary)
                        Text("\(workout.formattedDistance) · \(workout.formattedDuration)")
                            .font(.dripCaption(12))
                            .foregroundStyle(Color.drip.textSecondary)
                    } else {
                        Text("Link a workout")
                            .font(.dripBody(14))
                            .foregroundStyle(Color.drip.textPrimary)
                        Text("Optional: attach to a recent run")
                            .font(.dripCaption(12))
                            .foregroundStyle(Color.drip.textTertiary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.drip.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selectedWorkout != nil ? Color.drip.energized.opacity(0.5) : Color.drip.divider, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - WorkoutPickerSheet

struct WorkoutPickerSheet: View {
    let workouts: [RunningWorkout]
    @Binding var selectedWorkout: RunningWorkout?
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Color.drip.background.ignoresSafeArea()

                if workouts.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "figure.run")
                            .font(.system(size: 48))
                            .foregroundStyle(Color.drip.textTertiary)
                        Text("No recent runs found")
                            .font(.dripBody(16))
                            .foregroundStyle(Color.drip.textSecondary)
                        Text("Complete a run with your Apple Watch or running app to see it here.")
                            .font(.dripCaption(14))
                            .foregroundStyle(Color.drip.textTertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            // Option to not link any workout
                            Button {
                                selectedWorkout = nil
                                isPresented = false
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: selectedWorkout == nil ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 22))
                                        .foregroundStyle(selectedWorkout == nil ? Color.drip.energized : Color.drip.textTertiary)

                                    Text("No workout linked")
                                        .font(.dripBody(15))
                                        .foregroundStyle(Color.drip.textPrimary)

                                    Spacer()
                                }
                                .padding(16)
                                .background(Color.drip.cardBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)

                            ForEach(workouts) { workout in
                                Button {
                                    selectedWorkout = workout
                                    isPresented = false
                                } label: {
                                    WorkoutPickerRow(
                                        workout: workout,
                                        isSelected: selectedWorkout?.id == workout.id
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(20)
                    }
                }
            }
            .navigationTitle("Select Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        isPresented = false
                    }
                    .font(.dripBody(15))
                    .foregroundStyle(Color.drip.energized)
                }
            }
            .toolbarBackground(Color.drip.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}

// MARK: - WorkoutPickerRow

struct WorkoutPickerRow: View {
    let workout: RunningWorkout
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22))
                .foregroundStyle(isSelected ? Color.drip.energized : Color.drip.textTertiary)

            VStack(alignment: .leading, spacing: 4) {
                Text(workout.formattedDate)
                    .font(.dripBody(15))
                    .foregroundStyle(Color.drip.textPrimary)

                HStack(spacing: 16) {
                    Label(workout.formattedDistance, systemImage: "location.fill")
                    Label(workout.formattedDuration, systemImage: "timer")
                    Label(workout.formattedPace, systemImage: "speedometer")
                }
                .font(.dripCaption(12))
                .foregroundStyle(Color.drip.textSecondary)
            }

            Spacer()

            Text(workout.sourceApp)
                .font(.dripCaption(11))
                .foregroundStyle(Color.drip.textTertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.drip.divider)
                .clipShape(Capsule())
        }
        .padding(16)
        .background(isSelected ? Color.drip.energized.opacity(0.1) : Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.drip.energized : Color.drip.divider, lineWidth: 1)
        )
    }
}

// MARK: - RecordingConfirmationSheet

struct RecordingConfirmationSheet: View {
    let duration: TimeInterval
    @Binding var selectedWorkout: RunningWorkout?
    let workouts: [RunningWorkout]
    let onConfirm: () -> Void
    let onDiscard: () -> Void

    @State private var showWorkoutPicker = false

    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.drip.background.ignoresSafeArea()

                VStack(spacing: 32) {
                    Spacer()

                    // Recording preview
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(Color.drip.coral.opacity(0.15))
                                .frame(width: 100, height: 100)

                            Circle()
                                .fill(Color.drip.coral.opacity(0.3))
                                .frame(width: 70, height: 70)

                            Image(systemName: "waveform")
                                .font(.system(size: 32, weight: .medium))
                                .foregroundStyle(Color.drip.coral)
                        }

                        Text(formattedDuration)
                            .font(.dripStat(40))
                            .foregroundStyle(Color.drip.textPrimary)

                        Text("Voice memo recorded")
                            .font(.dripBody(16))
                            .foregroundStyle(Color.drip.textSecondary)
                    }

                    // Link workout option
                    VStack(alignment: .leading, spacing: 12) {
                        Text("LINK TO WORKOUT")
                            .font(.dripCaption(11))
                            .foregroundStyle(Color.drip.textSecondary)
                            .tracking(1.2)
                            .padding(.horizontal, 4)

                        Button {
                            showWorkoutPicker = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selectedWorkout != nil ? "figure.run.circle.fill" : "figure.run.circle")
                                    .font(.system(size: 24))
                                    .foregroundStyle(selectedWorkout != nil ? Color.drip.energized : Color.drip.textSecondary)

                                VStack(alignment: .leading, spacing: 2) {
                                    if let workout = selectedWorkout {
                                        Text(workout.formattedDate)
                                            .font(.dripBody(14))
                                            .foregroundStyle(Color.drip.textPrimary)
                                        Text("\(workout.formattedDistance) · \(workout.formattedDuration)")
                                            .font(.dripCaption(12))
                                            .foregroundStyle(Color.drip.textSecondary)
                                    } else {
                                        Text("Link a workout")
                                            .font(.dripBody(14))
                                            .foregroundStyle(Color.drip.textPrimary)
                                        Text("Optional")
                                            .font(.dripCaption(12))
                                            .foregroundStyle(Color.drip.textTertiary)
                                    }
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color.drip.textTertiary)
                            }
                            .padding(16)
                            .background(Color.drip.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(selectedWorkout != nil ? Color.drip.energized.opacity(0.5) : Color.drip.divider, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 24)

                    Spacer()

                    // Action buttons
                    VStack(spacing: 12) {
                        DripButton("Save Voice Log", icon: "checkmark.circle.fill") {
                            onConfirm()
                        }

                        Button {
                            onDiscard()
                        } label: {
                            Text("Discard")
                                .font(.dripBody(15))
                                .foregroundStyle(Color.drip.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("Confirm Recording")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.drip.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(isPresented: $showWorkoutPicker) {
                WorkoutPickerSheet(
                    workouts: workouts,
                    selectedWorkout: $selectedWorkout,
                    isPresented: $showWorkoutPicker
                )
            }
        }
    }
}

// MARK: - SuccessOverlay

struct SuccessOverlay: View {
    @State private var checkmarkScale: CGFloat = 0
    @State private var ringScale: CGFloat = 0.8
    @State private var ringOpacity: Double = 0

    var body: some View {
        ZStack {
            Color.drip.background.opacity(0.95)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                ZStack {
                    // Animated rings
                    ForEach(0 ..< 3) { i in
                        Circle()
                            .stroke(Color.drip.energized.opacity(0.3 - Double(i) * 0.1), lineWidth: 2)
                            .frame(width: 120 + CGFloat(i) * 40, height: 120 + CGFloat(i) * 40)
                            .scaleEffect(ringScale)
                            .opacity(ringOpacity)
                    }

                    // Success circle
                    Circle()
                        .fill(Color.drip.energized)
                        .frame(width: 100, height: 100)
                        .shadow(color: Color.drip.energized.opacity(0.5), radius: 20, x: 0, y: 10)

                    // Checkmark
                    Image(systemName: "checkmark")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(.black)
                        .scaleEffect(checkmarkScale)
                }

                VStack(spacing: 8) {
                    Text("Saved!")
                        .font(.dripDisplay(28))
                        .foregroundStyle(Color.drip.textPrimary)

                    Text("Your voice log is being processed")
                        .font(.dripBody(15))
                        .foregroundStyle(Color.drip.textSecondary)
                }
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                checkmarkScale = 1
            }
            withAnimation(.easeOut(duration: 0.8)) {
                ringScale = 1.2
                ringOpacity = 1
            }
            withAnimation(.easeOut(duration: 1.5).delay(0.3)) {
                ringOpacity = 0
            }
        }
    }
}

#Preview {
    NavigationStack {
        VoiceLogView()
    }
}
