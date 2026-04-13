import AVFoundation
import os
import PostgREST
import Storage
import Supabase
import SwiftUI

// MARK: - VoiceLogView

struct VoiceLogView: View {
    @Environment(CoachCheckInManager.self) private var checkInManager
    @Environment(\.selectedTab) private var selectedTab
    @StateObject private var healthKitManager = HealthKitManager()
    @State private var viewModel = VoiceLogViewModel()
    @State private var isRecording = false
    @State private var audioRecorder: AVAudioRecorder?
    @State private var recordingURL: URL?
    @State private var manualNotes = ""
    @State private var recordingDuration: TimeInterval = 0
    @State private var timer: Timer?
    @State private var selectedWorkout: RunningWorkout?
    @State private var showWorkoutPicker = false
    @State private var showConfirmation = false
    @State private var pendingRecordingDuration: TimeInterval = 0
    @FocusState private var isTextEditorFocused: Bool

    // Mode toggle
    @State private var isCheckInMode = false

    // Feed state
    @State private var selectedHistoryEntry: TrainingLog?

    var body: some View {
        ZStack {
            DripBackground()

            ScrollView {
                VStack(spacing: 0) {
                    // Hero section with record button
                    VStack(spacing: 24) {
                        // Status pill
                        if !viewModel.statusMessage.isEmpty {
                            StatusPill(message: viewModel.statusMessage, isError: viewModel.statusMessage.contains("Error"))
                                .transition(.asymmetric(
                                    insertion: .move(edge: .top).combined(with: .opacity),
                                    removal: .opacity
                                ))
                        }

                        // Coach check-in card
                        if checkInManager.showBanner, let context = checkInManager.pendingCheckIn {
                            CoachCheckInCard(
                                context: context,
                                onTalkToCoach: {
                                    selectedTab.wrappedValue = 2
                                },
                                onDismiss: {
                                    withAnimation(.spring(response: 0.3)) {
                                        checkInManager.dismiss()
                                    }
                                }
                            )
                            .transition(.asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .opacity
                            ))
                            .padding(.horizontal, 16)
                        }

                        Spacer()
                            .frame(height: 40)

                        // Mode toggle: Log Run vs Check In
                        if !isRecording {
                            HStack(spacing: 0) {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) { isCheckInMode = false }
                                } label: {
                                    Text("Log Run")
                                        .font(.dripLabel(13))
                                        .foregroundStyle(isCheckInMode ? Color.drip.textTertiary : .white)
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 8)
                                        .background(isCheckInMode ? Color.clear : Color.drip.coral)
                                        .clipShape(Capsule())
                                }

                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) { isCheckInMode = true; selectedWorkout = nil }
                                } label: {
                                    Text("Check In")
                                        .font(.dripLabel(13))
                                        .foregroundStyle(isCheckInMode ? .white : Color.drip.textTertiary)
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 8)
                                        .background(isCheckInMode ? Color.drip.energized : Color.clear)
                                        .clipShape(Capsule())
                                }
                            }
                            .padding(3)
                            .background(Color.drip.cardBackground)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.drip.divider, lineWidth: 1))
                        }

                        // Recording duration or title
                        if isRecording {
                            Text(formatDuration(recordingDuration))
                                .font(.dripStat(48))
                                .foregroundStyle(Color.drip.textPrimary)
                                .contentTransition(.numericText())
                                .animation(.spring(response: 0.3), value: recordingDuration)
                        } else {
                            Text(isCheckInMode ? "How Are You Feeling?" : "Log Your Run")
                                .font(.dripDisplay(32))
                                .foregroundStyle(Color.drip.textPrimary)
                        }

                        Text(isRecording
                            ? (isCheckInMode ? "Tell us how you're feeling..." : "Recording your thoughts...")
                            : (isCheckInMode ? "Record a quick update on your body and mind" : "Tap to start voice memo"))
                            .font(.dripBody(15))
                            .foregroundStyle(Color.drip.textSecondary)
                            .multilineTextAlignment(.center)

                        // Workout selector — only in run mode
                        if !isCheckInMode {
                            WorkoutSelectorButton(
                                selectedWorkout: selectedWorkout,
                                onTap: { showWorkoutPicker = true }
                            )
                        }

                        Spacer()
                            .frame(height: 20)

                        // Record button
                        PulsingRecordButton(
                            isRecording: isRecording,
                            isDisabled: viewModel.isUploading
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

                        DripButton("Save Notes", icon: "arrow.up.circle.fill", isLoading: viewModel.isUploading && !manualNotes.isEmpty) {
                            Task {
                                let saved = await viewModel.saveManualNotes(manualNotes, selectedWorkout: selectedWorkout)
                                if saved {
                                    manualNotes = ""
                                    selectedWorkout = nil
                                }
                            }
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
                                Task { await viewModel.loadHistory() }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(Color.drip.textSecondary)
                            }
                        }

                        if viewModel.isLoadingHistory && viewModel.historyLogs.isEmpty {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .tint(Color.drip.coral)
                                Spacer()
                            }
                            .padding(.vertical, 40)
                        } else if viewModel.historyLogs.isEmpty {
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
                                ForEach(viewModel.historyLogs, id: \.id) { log in
                                    if log.isPending || log.isFailed {
                                        ProcessingLogCard(log: log) {
                                            Task { await viewModel.retryProcessing(log: log) }
                                        }
                                    } else {
                                        HistoryEntryCard(entry: log)
                                            .onTapGesture {
                                                selectedHistoryEntry = log
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
                await viewModel.loadHistory()
            }
        }
        .animation(.spring(response: 0.4), value: viewModel.statusMessage)
        .sheet(isPresented: $showWorkoutPicker) {
            WorkoutPickerSheet(
                healthKitManager: healthKitManager,
                selectedWorkout: $selectedWorkout,
                isPresented: $showWorkoutPicker
            )
        }
        .sheet(isPresented: $showConfirmation) {
            RecordingConfirmationSheet(
                duration: pendingRecordingDuration,
                selectedWorkout: $selectedWorkout,
                healthKitManager: healthKitManager,
                onConfirm: confirmAndUpload,
                onDiscard: discardRecording
            )
            .interactiveDismissDisabled()
        }
        .overlay {
            if viewModel.showSuccessAnimation {
                SuccessOverlay()
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .sheet(item: $selectedHistoryEntry) { entry in
            HistoryDetailSheet(entry: entry) {
                Task { await viewModel.loadHistory() }
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
            viewModel.statusMessage = "Error: Failed to setup audio"
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
            viewModel.statusMessage = ""
            recordingDuration = 0

            // Start timer
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                recordingDuration += 1
            }
        } catch {
            viewModel.statusMessage = "Error: Failed to start recording"
        }
    }

    private func stopRecording() {
        audioRecorder?.stop()
        timer?.invalidate()
        timer = nil
        isRecording = false
        pendingRecordingDuration = recordingDuration

        guard recordingURL != nil else {
            viewModel.statusMessage = "Error: No recording found"
            return
        }

        // Show confirmation sheet instead of uploading directly
        showConfirmation = true
    }

    private func confirmAndUpload() {
        guard let url = recordingURL else { return }
        showConfirmation = false

        Task {
            if isCheckInMode {
                await viewModel.uploadCheckIn(
                    localURL: url,
                    checkInManager: checkInManager
                )
            } else {
                await viewModel.uploadAudioAndSaveLog(
                    localURL: url,
                    selectedWorkout: selectedWorkout,
                    checkInManager: checkInManager
                )
            }
            recordingURL = nil
            recordingDuration = 0
            pendingRecordingDuration = 0
            selectedWorkout = nil
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
        viewModel.statusMessage = ""
    }

}

// MARK: - ProcessingLogCard

struct ProcessingLogCard: View {
    let log: TrainingLog
    let onRetry: () -> Void

    private var dateString: String {
        let date = log.workoutDate ?? log.createdAt
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
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

// MARK: - CoachCheckInCard

struct CoachCheckInCard: View {
    let context: CheckInContext
    let onTalkToCoach: () -> Void
    let onDismiss: () -> Void

    private var teaserText: String {
        if let insight = context.coachInsight, !insight.isEmpty {
            return insight.count > 80 ? String(insight.prefix(77)) + "..." : insight
        }
        switch context.mood {
        case "injured":
            return "Sounds like something's bothering you. Let's figure out the right next step."
        case "struggling":
            return "Tough one today. Want to talk through what's going on?"
        case "tired":
            return "You sound worn down. Might be time for a recovery check."
        default:
            return "How are you feeling? Want to check in?"
        }
    }

    private var moodColor: Color {
        switch context.mood {
        case "injured": return Color.drip.injured
        case "struggling": return Color.drip.struggling
        case "tired": return Color.drip.tired
        default: return Color.drip.textSecondary
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(moodColor.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: "figure.run")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(moodColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Coach wants to check in")
                        .font(.dripLabel(14))
                        .foregroundStyle(Color.drip.textPrimary)

                    Text(teaserText)
                        .font(.dripBody(13))
                        .foregroundStyle(Color.drip.textSecondary)
                        .lineLimit(2)
                }

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.drip.textTertiary)
                        .padding(6)
                }
            }

            Button(action: onTalkToCoach) {
                HStack(spacing: 8) {
                    Image(systemName: "message.fill")
                        .font(.system(size: 13))
                    Text("Talk to Coach")
                        .font(.dripLabel(14))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(moodColor)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(16)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(moodColor.opacity(0.3), lineWidth: 1)
        )
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
    @ObservedObject var healthKitManager: HealthKitManager
    @Binding var selectedWorkout: RunningWorkout?
    @Binding var isPresented: Bool
    @State private var isRefreshing = false
    @State private var mergedWorkouts: [RunningWorkout] = []

    private var workouts: [RunningWorkout] {
        mergedWorkouts
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.drip.background.ignoresSafeArea()

                if workouts.isEmpty && !isRefreshing {
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

                        Button {
                            Task { await refreshWorkouts() }
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                                .font(.dripBody(14))
                                .foregroundStyle(Color.drip.energized)
                        }
                        .padding(.top, 8)
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

                            if isRefreshing {
                                ProgressView()
                                    .tint(Color.drip.energized)
                                    .padding(.vertical, 20)
                            }

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
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task { await refreshWorkouts() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.drip.energized)
                            .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                            .animation(isRefreshing ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: isRefreshing)
                    }
                    .disabled(isRefreshing)
                }
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
            .task {
                await refreshWorkouts()
            }
        }
    }

    private func refreshWorkouts() async {
        isRefreshing = true

        // Fetch from both HealthKit and Vital in parallel
        async let hkWorkouts = healthKitManager.fetchRecentRunningWorkouts(limit: 20)
        async let vitalWorkouts = VitalManager.shared.fetchRecentRunningWorkouts(limit: 30)

        let hk = await hkWorkouts
        let vital = await vitalWorkouts

        // Merge: start with Vital workouts, then add HealthKit workouts that aren't duplicates
        // Garmin syncs to both Vital and HealthKit (via Garmin Connect) with slightly different
        // timestamps, so we match on start time within 5 min AND similar duration (within 2 min).
        // This still preserves individual reps (e.g. 5x1mi) since each has a different start time.
        var merged = vital
        for hkW in hk {
            let isDuplicate = merged.contains { existing in
                abs(existing.startDate.timeIntervalSince(hkW.startDate)) < 300
                    && abs(existing.durationMinutes - hkW.durationMinutes) < 2.0
            }
            if !isDuplicate {
                merged.append(hkW)
            }
        }

        // Sort by date, most recent first
        merged.sort { $0.startDate > $1.startDate }

        await MainActor.run {
            healthKitManager.recentWorkouts = hk
            mergedWorkouts = merged
            isRefreshing = false
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
    @ObservedObject var healthKitManager: HealthKitManager
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
                    healthKitManager: healthKitManager,
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
