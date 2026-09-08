//
//  CheckInView.swift
//  RunningLog
//
//  Check in — how you're feeling, with no run attached.
//
//  WHY THIS FILE EXISTS. In the editorial skin, check-in is a mode on the
//  Log screen: a LOG RUN / CHECK IN segmented control above the headline.
//  The wild skin removes that control, which would otherwise leave the
//  mode unreachable. So check-in became its own surface, opened from the
//  app menu (☰ → Check in).
//
//  That is arguably where it belonged anyway. A check-in isn't a way of
//  logging a run — it's the opposite of one, and giving it a permanent
//  band at the top of the record screen charged every athlete, every day,
//  for something used occasionally.
//
//  It writes through `VoiceLogViewModel.uploadCheckIn`, the same call the
//  editorial mode uses, so entries land identically and appear in both
//  feeds with `source == "check_in"`.
//

import SwiftUI

struct CheckInView: View {
    @Environment(CoachCheckInManager.self) private var checkInManager
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel = VoiceLogViewModel()
    @State private var recorder = VoiceRecorder()
    @State private var pendingURL: URL?
    @State private var showMicDeniedAlert = false
    @State private var didUpload = false

    var body: some View {
        ZStack {
            Color.wild.paper.ignoresSafeArea()

            VStack(spacing: 0) {
                lede
                Spacer(minLength: 12)
                record
                Spacer(minLength: 12)
                footer
            }
            .padding(.horizontal, 22)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        // No Done button: the menu's fullScreenCover already supplies an ✕
        // in the leading slot, and two ways out of one screen is clutter.
        .toolbarBackground(Color.wild.paper, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear { recorder.prepare() }
        .overlay {
            if viewModel.showSuccessAnimation {
                SuccessOverlay().transition(.opacity.combined(with: .scale))
            }
        }
        .onChange(of: viewModel.showSuccessAnimation) { _, showing in
            // Close once the entry is safely away, so the athlete isn't
            // left staring at a screen whose job is done.
            guard didUpload, !showing else { return }
            dismiss()
        }
        .alert("Microphone access needed", isPresented: $showMicDeniedAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("Check-ins need the microphone. Enable it in Settings → PostRunDrip → Microphone.")
        }
    }

    private var lede: some View {
        VStack(spacing: 0) {
            if recorder.isRecording {
                Text(VoiceRecorder.clock(recorder.duration))
                    .font(.wildData(52, semibold: true))
                    .tracking(52 * -0.05)
                    .monospacedDigit()
                    .foregroundStyle(Color.wild.ink)
                    .contentTransition(.numericText())
                Text("Recording — tap the button to stop.")
                    .font(.wildDek(17))
                    .foregroundStyle(Color.wild.ink2)
                    .padding(.top, 12)
            } else {
                Text("How are you feeling?")
                    .font(.wildDisplay(44))
                    .tracking(44 * -0.05)
                    .foregroundStyle(Color.wild.ink)
                Text("A quick check-in. No run attached.")
                    .font(.wildDek(17))
                    .foregroundStyle(Color.wild.ink2)
                    .padding(.top, 12)
            }

            if !viewModel.statusMessage.isEmpty {
                Text(viewModel.statusMessage)
                    .font(.wildProse(16))
                    .foregroundStyle(viewModel.statusMessage.contains("Error")
                                     ? Color.wild.redText : Color.wild.ink2)
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
        .padding(.bottom, 30)
        .overlay(alignment: .bottom) { WildRule() }
        .animation(.spring(response: 0.3), value: recorder.duration)
    }

    private var record: some View {
        VStack(spacing: 12) {
            WildRecordButton(
                isRecording: recorder.isRecording,
                isDisabled: viewModel.isUploading
            ) {
                toggle()
            }
            WildLabel(recorder.isRecording ? "Tap to stop" : "Tap to record",
                      size: 11, tracking: 0.16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        WildLabel("Check-ins land in your journal", size: 9, tracking: 0.16)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 28)
    }

    private func toggle() {
        if recorder.isRecording {
            guard let take = recorder.stop() else {
                viewModel.statusMessage = "Error: No recording found"
                return
            }
            pendingURL = take.url
            upload()
        } else {
            viewModel.statusMessage = ""
            recorder.start(
                onDenied: { showMicDeniedAlert = true },
                onError: { viewModel.statusMessage = $0 }
            )
        }
    }

    /// No confirmation sheet here, deliberately. A check-in has nothing to
    /// confirm — no run to link, no distance to correct — so a sheet asking
    /// "keep this?" would be a step that exists only to have a step.
    private func upload() {
        guard let url = pendingURL else { return }
        didUpload = true
        Task {
            await viewModel.uploadCheckIn(localURL: url, checkInManager: checkInManager)
            pendingURL = nil
            recorder.release()
        }
    }
}
