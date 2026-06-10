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

    // Today sheet — Today doesn't have a tab anymore (voice is the front
    // door), so it lives behind this opener. Edit the IA in MainTabView
    // and outputs/design-parity-audit-2026-05-20.md if this changes.
    @State private var showToday = false

    var body: some View {
        ZStack {
            DripBackground()

            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 0) {
                        // ── Editorial plate strip header ────────────────
                        // Replaces the iOS toolbar centerpiece. Mirrors
                        // `<PlateStrip surface="LOG · v1 VOICE LOG"
                        // fig="FIG. 09" />` in `LogScreen.jsx`.
                        DripPlateStrip(
                            leadingBottom: "LOG · v1 VOICE LOG",
                            trailingTop: "FIG. 09",
                            trailingBottom: ""
                        )

                        // ── HERO — fills the visible viewport ───────────
                        // Mode toggle, title, linked workout, and record
                        // button live in a single block sized to the
                        // viewport so the recording action takes the full
                        // screen on first open. Type-notes and the
                        // journal feed sit below the fold.
                        VStack(spacing: 0) {
                            // Quiet status annotation
                            if !viewModel.statusMessage.isEmpty {
                                nsStatusLine
                            }

                            // Coach check-in eyebrow line
                            if checkInManager.showBanner, checkInManager.pendingCheckIn != nil {
                                nsCoachCheckInLine
                            }

                            // Mode toggle (only when idle)
                            if !isRecording {
                                nsModeToggle
                            }

                            // Title + directive subtitle (centered)
                            nsTitleBlock

                            // Linked workout — only in Log Run mode
                            if !isCheckInMode {
                                nsLinkedWorkoutSection
                            }

                            // Push the record button toward the lower
                            // half of the hero, the way the original
                            // layout did. Spacer fills remaining space.
                            Spacer(minLength: 20)

                            // Record button — the one loud accent
                            nsRecordButtonSection

                            Spacer(minLength: 30)
                        }
                        .frame(minHeight: max(geometry.size.height - 60, 600))

                        // ── BELOW THE FOLD ─────────────────────────────
                        // Type-notes section
                        nsTypeNotesSection

                        // Your Logs feed (journal entries)
                        nsYourLogsSection
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .onTapGesture {
                    isTextEditorFocused = false
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                SidebarMenuButton()
            }
            // The "VOICE LOG" toolbar centerpiece moved into the inline
            // `DripPlateStrip` at the top of the scroll view, per the
            // editorial pattern from LogScreen.jsx. Leaving the principal
            // slot empty keeps the iOS nav bar quiet, in line with the
            // plate-strip-as-header treatment.
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showToday = true
                } label: {
                    HStack(spacing: 4) {
                        Text("TODAY")
                            .font(.dripEyebrow(11))
                            .tracking(1.3)  // 0.12em label tracking at 11pt
                        Text("↗")
                            .font(.dripEyebrow(11))
                    }
                    .foregroundStyle(Color.drip.coral)
                }
                .buttonStyle(.plain)
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
        .sheet(isPresented: $showToday) {
            NavigationStack {
                TodayHomeView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                showToday = false
                            } label: {
                                Text("Done")
                                    .font(.dripLabel(15))
                                    .foregroundStyle(Color.drip.coral)
                            }
                        }
                    }
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

    // MARK: - Negative Splits sections

    /// Quiet status annotation (replaces the floating coral StatusPill).
    @ViewBuilder
    private var nsStatusLine: some View {
        let isError = viewModel.statusMessage.contains("Error")
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(isError ? "——" : "·")
                .foregroundStyle(Color.drip.textTertiary)
            Text(viewModel.statusMessage)
                .font(.system(size: 14, design: .serif).italic())
                .foregroundStyle(isError ? Color.drip.coral : Color.drip.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .transition(.opacity)
    }

    /// Coach check-in surfaced as a quiet single-line eyebrow.
    @ViewBuilder
    private var nsCoachCheckInLine: some View {
        Button {
            // Coach moved to tab 3 when Trends was inserted at slot 2.
            selectedTab.wrappedValue = 3
        } label: {
            HStack(spacing: 8) {
                Text("COACH HAS A CHECK-IN WAITING")
                    .font(.dripCaption(11))
                    .tracking(1.2)
                    .foregroundStyle(Color.drip.coral)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.drip.coral)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        checkInManager.dismiss()
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.drip.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    /// Text segmented mode toggle with amber underline on the active mode.
    /// Replaces the filled coral/green capsule pills.
    @ViewBuilder
    private var nsModeToggle: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.drip.divider).frame(height: 1)
            HStack(spacing: 0) {
                nsModeButton(label: "LOG RUN", active: !isCheckInMode) {
                    withAnimation(.easeInOut(duration: 0.2)) { isCheckInMode = false }
                }
                nsModeButton(label: "CHECK IN", active: isCheckInMode) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isCheckInMode = true
                        selectedWorkout = nil
                    }
                }
            }
            Rectangle().fill(Color.drip.divider).frame(height: 1)
        }
    }

    @ViewBuilder
    private func nsModeButton(label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(active ? Color.drip.coral : Color.drip.textSecondary)
                    .padding(.top, 14)
                Rectangle()
                    .fill(active ? Color.drip.coral : Color.clear)
                    .frame(height: 2)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    /// Big serif title (or m:ss timer when recording) + directive subtitle.
    /// Centered so the eye reads top → middle → button as one obvious flow,
    /// the way the original design's "Log Your Run / Tap to start voice
    /// memo" stack did. Subtitle is instructional, not poetic.
    @ViewBuilder
    private var nsTitleBlock: some View {
        VStack(spacing: 14) {
            if isRecording {
                // Recording timer — mono + tabular numerals so the
                // digits don't dance as seconds tick over. The JSX
                // calls out `font-mono` + `font-variant-numeric:
                // tabular-nums` for this; the serif display token
                // (`dripDisplay`) used elsewhere is wrong here.
                Text(formatDuration(recordingDuration))
                    .font(.system(size: 56, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .tracking(-1.0)  // -0.02em at 56pt ≈ -1.1pt
                    .foregroundStyle(Color.drip.textPrimary)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.3), value: recordingDuration)
            } else {
                Text(isCheckInMode ? "How are you feeling?" : "Log your run.")
                    .font(.dripDisplay(38))
                    .foregroundStyle(Color.drip.textPrimary)
                    .multilineTextAlignment(.center)
            }
            Text(isRecording
                 ? (isCheckInMode ? "Speak your status — tap the button to stop." : "Recording — tap the button to stop.")
                 : (isCheckInMode ? "Tap the button to record a quick check-in." : "Tap the button to start your voice memo."))
                .font(.system(size: 15, design: .serif).italic())
                .foregroundStyle(Color.drip.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 32)
        .padding(.bottom, 24)
    }

    /// Hairline-bound section showing the linked workout (or a quiet
    /// invitation to link one). Tapping anywhere opens the picker.
    @ViewBuilder
    private var nsLinkedWorkoutSection: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.drip.divider).frame(height: 1)
            Button {
                showWorkoutPicker = true
            } label: {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("LINKED TO")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .tracking(1.0)
                            .foregroundStyle(Color.drip.textSecondary)
                        Spacer()
                        HStack(spacing: 4) {
                            Text(selectedWorkout == nil ? "LINK A RUN" : "CHANGE")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .tracking(1.0)
                                .foregroundStyle(Color.drip.textSecondary)
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Color.drip.textSecondary)
                        }
                    }
                    if let w = selectedWorkout {
                        Text(linkedWorkoutLine(w))
                            .font(.dripDisplay(20))
                            .foregroundStyle(Color.drip.textPrimary)
                        Text(linkedWorkoutMeta(w))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Color.drip.textTertiary)
                    } else {
                        Text("Optional — attach to a recent run.")
                            .font(.system(size: 14, design: .serif).italic())
                            .foregroundStyle(Color.drip.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
            Rectangle().fill(Color.drip.divider).frame(height: 1)
        }
    }

    private func linkedWorkoutLine(_ w: RunningWorkout) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        let date = f.string(from: w.startDate)
        return "\(date)  ·  \(String(format: "%.2f", w.distanceMiles)) mi  ·  \(w.formattedDuration)"
    }

    private func linkedWorkoutMeta(_ w: RunningWorkout) -> String {
        let pace = w.pacePerMile > 0
            ? PaceCalculator.formatPaceFromMinutes(w.pacePerMile) + " / MI"
            : "—"
        return "\(pace)   ·   \(w.sourceApp.uppercased())"
    }

    /// The record button — kept loud. The one place the design system's
    /// restraint deliberately breaks.
    @ViewBuilder
    private var nsRecordButtonSection: some View {
        VStack(spacing: 14) {
            Spacer().frame(height: 36)
            PulsingRecordButton(
                isRecording: isRecording,
                isDisabled: viewModel.isUploading
            ) {
                toggleRecording()
            }
            Text(isRecording ? "TAP TO STOP" : "TAP TO RECORD")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(Color.drip.textSecondary)
            Spacer().frame(height: 36)
        }
        .frame(maxWidth: .infinity)
    }

    /// "OR · TYPE NOTES" text input — quiet hairline-bound section, no
    /// bordered card, italic placeholder.
    @ViewBuilder
    private var nsTypeNotesSection: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.drip.divider).frame(height: 1)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("OR  ·  TYPE NOTES")
                        .font(.dripCaption(11))
                        .tracking(1.2)
                        .foregroundStyle(Color.drip.textSecondary)
                    Spacer()
                    nsSaveNotesAction
                }

                ZStack(alignment: .topLeading) {
                    if manualNotes.isEmpty {
                        Text("How did your run feel today?")
                            .font(.system(size: 15, design: .serif).italic())
                            .foregroundStyle(Color.drip.textTertiary)
                            .padding(.top, 8)
                            .padding(.leading, 4)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $manualNotes)
                        .font(.system(size: 15, design: .serif))
                        .foregroundStyle(Color.drip.textPrimary)
                        .scrollContentBackground(.hidden)
                        .focused($isTextEditorFocused)
                        .frame(minHeight: 84)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            Rectangle().fill(Color.drip.divider).frame(height: 1)
        }
    }

    @ViewBuilder
    private var nsSaveNotesAction: some View {
        if manualNotes.isEmpty {
            Text("SAVE")
                .font(.dripCaption(11))
                .tracking(1.2)
                .foregroundStyle(Color.drip.textTertiary)
        } else if viewModel.isUploading {
            ProgressView().tint(Color.drip.coral).scaleEffect(0.7)
        } else {
            Button {
                Task {
                    let saved = await viewModel.saveManualNotes(manualNotes, selectedWorkout: selectedWorkout)
                    if saved {
                        manualNotes = ""
                        selectedWorkout = nil
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text("SAVE")
                        .font(.dripCaption(11))
                        .tracking(1.2)
                        .foregroundStyle(Color.drip.coral)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.drip.coral)
                }
            }
            .buttonStyle(.plain)
        }
    }

    /// The journal feed — eyebrow ("JOURNAL · RECENT"), hairline, then
    /// `JournalLogRow` entries. Each row is taller than the dashboard's
    /// preview row: vertical mood-color rule on the left, day-of-week as
    /// serif headline, fuller body text (3 lines), mood footer.
    /// Pending/failed logs still use `ProcessingLogCard`.
    @ViewBuilder
    private var nsYourLogsSection: some View {
        VStack(spacing: 0) {
            HStack {
                Text("JOURNAL  \(journalCountLabel)")
                    .font(.dripCaption(11))
                    .tracking(1.2)
                    .foregroundStyle(Color.drip.textSecondary)
                Spacer()
                Button {
                    Task { await viewModel.loadHistory() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.drip.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)

            Rectangle().fill(Color.drip.divider).frame(height: 1)

            nsYourLogsContent
        }
        .padding(.bottom, 40)
    }

    private var journalCountLabel: String {
        let n = viewModel.historyLogs.count
        guard n > 0 else { return "·  RECENT" }
        return "·  \(n) \(n == 1 ? "ENTRY" : "ENTRIES")"
    }

    @ViewBuilder
    private var nsYourLogsContent: some View {
        if viewModel.isLoadingHistory && viewModel.historyLogs.isEmpty {
            HStack {
                Spacer()
                ProgressView().tint(Color.drip.coral)
                Spacer()
            }
            .padding(.vertical, 32)
        } else if viewModel.historyLogs.isEmpty {
            Text("No entries yet — record or type to start your journal.")
                .font(.system(size: 14, design: .serif).italic())
                .foregroundStyle(Color.drip.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.vertical, 24)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(Array(viewModel.historyLogs.enumerated()), id: \.element.id) { idx, log in
                    if log.isPending || log.isFailed {
                        ProcessingLogCard(log: log) {
                            Task { await viewModel.retryProcessing(log: log) }
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 8)
                    } else {
                        Button {
                            selectedHistoryEntry = log
                        } label: {
                            JournalLogRow(entry: log)
                                .padding(.horizontal, 24)
                        }
                        .buttonStyle(.plain)
                    }
                    if idx < viewModel.historyLogs.count - 1 {
                        Rectangle()
                            .fill(Color.drip.divider)
                            .frame(height: 1)
                            .padding(.horizontal, 24)
                    }
                }
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Configure the audio session category eagerly on appear, but defer
    /// `setActive(true)` to record-time. Activating on appear surfaces a
    /// spurious "Failed to setup audio" banner whenever the simulator has
    /// no audio device, another app holds the route, or backgrounding has
    /// temporarily interrupted us. The actual recording path activates +
    /// surfaces an error only if the user has tried to record and we
    /// genuinely can't.
    private func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default)
        } catch {
            print("[VoiceLog] setCategory failed (will retry at record time): \(error)")
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
            // Activate the session right before recording — deferred from
            // onAppear so we don't show a spurious error banner when the
            // sim or another app is holding the route. If activation fails
            // here, the user has actually pressed record, so surfacing
            // "Failed to start recording" is honest.
            try AVAudioSession.sharedInstance().setActive(true)
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
            print("[VoiceLog] startRecording failed: \(error)")
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

        // Fetch from HealthKit, Vital (stubbed), and Strava-imported training_logs in parallel.
        async let hkWorkouts = healthKitManager.fetchRecentRunningWorkouts(limit: 20)
        async let vitalWorkouts = VitalManager.shared.fetchRecentRunningWorkouts(limit: 30)
        async let stravaWorkouts = Self.fetchStravaRunningWorkouts(limit: 30)

        let hk = await hkWorkouts
        let vital = await vitalWorkouts
        let strava = await stravaWorkouts

        // Merge, dedup across sources (Garmin often syncs to multiple places).
        // Match on start time within 5 min AND similar duration (within 2 min).
        var merged: [RunningWorkout] = []
        let appendIfUnique: (RunningWorkout) -> Void = { w in
            let isDuplicate = merged.contains { existing in
                abs(existing.startDate.timeIntervalSince(w.startDate)) < 300
                    && abs(existing.durationMinutes - w.durationMinutes) < 2.0
            }
            if !isDuplicate { merged.append(w) }
        }
        for w in vital { appendIfUnique(w) }
        for w in strava { appendIfUnique(w) }
        for w in hk { appendIfUnique(w) }

        merged.sort { $0.startDate > $1.startDate }

        await MainActor.run {
            healthKitManager.recentWorkouts = hk
            mergedWorkouts = merged
            isRefreshing = false
        }
    }

    /// Fetch Strava-sourced training_logs and map them to RunningWorkout so they
    /// appear in the workout link picker.
    private static func fetchStravaRunningWorkouts(limit: Int) async -> [RunningWorkout] {
        struct Row: Decodable {
            let id: String
            let workout_date: Date?
            let workout_distance_miles: Double?
            let workout_duration_minutes: Double?
            let vital_workout_id: String?
            let cleaned_notes: String?
        }
        do {
            let userId = AuthManager.shared.userId
            let rows: [Row] = try await supabase
                .from("training_logs")
                .select("id, workout_date, workout_distance_miles, workout_duration_minutes, vital_workout_id, cleaned_notes")
                .eq("user_id", value: userId)
                .eq("source", value: "strava")
                .order("workout_date", ascending: false, nullsFirst: false)
                .limit(limit)
                .execute()
                .value

            return rows.compactMap { r -> RunningWorkout? in
                guard let start = r.workout_date,
                      let dist = r.workout_distance_miles, dist > 0,
                      let dur = r.workout_duration_minutes, dur > 0,
                      let uuid = UUID(uuidString: r.id) else { return nil }
                return RunningWorkout(
                    id: uuid,
                    startDate: start,
                    endDate: start.addingTimeInterval(dur * 60),
                    distanceMiles: dist,
                    durationMinutes: dur,
                    pacePerMile: dur / dist,
                    calories: 0,
                    sourceApp: "Strava",
                    vitalWorkoutId: r.vital_workout_id
                )
            }
        } catch {
            Log.app.error("Strava workout fetch failed: \(error)")
            return []
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
