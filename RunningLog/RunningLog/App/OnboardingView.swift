//
//  OnboardingView.swift
//  RunningLog
//
//  First-time user onboarding flow: welcome → connect watch → set goal → first memo.
//

import HealthKit
import Supabase
import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @EnvironmentObject private var healthKitManager: HealthKitManager
    @State private var currentStep = 0

    // Goal setup state
    @State private var selectedDistance: String = "half_marathon"
    @State private var goalHours = 1
    @State private var goalMinutes = 30
    @State private var goalSeconds = 0

    private let totalSteps = 4

    var body: some View {
        ZStack {
            Color.drip.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Progress dots
                HStack(spacing: 8) {
                    ForEach(0..<totalSteps, id: \.self) { step in
                        Circle()
                            .fill(step <= currentStep ? Color.drip.coral : Color.drip.divider)
                            .frame(width: 8, height: 8)
                    }
                }
                .padding(.top, 60)

                // Step content
                TabView(selection: $currentStep) {
                    welcomeStep.tag(0)
                    healthKitStep.tag(1)
                    goalStep.tag(2)
                    readyStep.tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.3), value: currentStep)
            }
        }
    }

    // MARK: - Step 1: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "waveform")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(Color.drip.coral)

                Text("Post Run Drip")
                    .font(.dripDisplay(36))
                    .foregroundStyle(Color.drip.textPrimary)

                Text("Your AI training companion")
                    .font(.dripBody(16))
                    .foregroundStyle(Color.drip.textSecondary)
            }

            VStack(alignment: .leading, spacing: 20) {
                FeatureRow(icon: "mic.fill", title: "Voice Memos", description: "Record how your run felt. AI transcribes and analyzes it.")
                FeatureRow(icon: "chart.bar.fill", title: "Smart Analysis", description: "Pace segments, HR zones, and coaching insights from your Garmin data.")
                FeatureRow(icon: "message.fill", title: "AI Coach", description: "Ask questions about your training. The coach knows your history.")
            }
            .padding(.horizontal, 32)

            Spacer()

            nextButton("Get Started")
        }
    }

    // MARK: - Step 2: Connect Watch

    private var healthKitStep: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "applewatch.and.arrow.forward")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(Color.drip.energized)

                Text("Connect Your Watch")
                    .font(.dripDisplay(28))
                    .foregroundStyle(Color.drip.textPrimary)

                Text("We'll pull your runs from Apple Health.\nGarmin and other watches sync through Health automatically.")
                    .font(.dripBody(14))
                    .foregroundStyle(Color.drip.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            if healthKitManager.isAuthorized {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.drip.energized)
                    Text("Connected")
                        .font(.dripLabel(14))
                        .foregroundStyle(Color.drip.energized)
                }
                .padding(.vertical, 12)
            } else {
                Button {
                    Task {
                        _ = await healthKitManager.requestAuthorization()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 14))
                        Text("Allow HealthKit Access")
                            .font(.dripLabel(14))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.drip.energized)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 40)
            }

            Spacer()

            VStack(spacing: 12) {
                nextButton("Continue")

                Button {
                    currentStep = 2
                } label: {
                    Text("Skip for now")
                        .font(.dripCaption(12))
                        .foregroundStyle(Color.drip.textTertiary)
                }
            }
        }
    }

    // MARK: - Step 3: Set Goal

    private var goalStep: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "flag.checkered")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(Color.drip.coral)

                Text("Set a Goal")
                    .font(.dripDisplay(28))
                    .foregroundStyle(Color.drip.textPrimary)

                Text("What are you training for?\nThis helps the AI personalize your coaching.")
                    .font(.dripBody(14))
                    .foregroundStyle(Color.drip.textSecondary)
                    .multilineTextAlignment(.center)
            }

            // Distance picker
            VStack(alignment: .leading, spacing: 8) {
                Text("DISTANCE")
                    .font(.dripCaption(10))
                    .foregroundStyle(Color.drip.textTertiary)
                    .tracking(1.5)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach([
                            ("5k", "5K"),
                            ("10k", "10K"),
                            ("half_marathon", "Half Marathon"),
                            ("marathon", "Marathon"),
                        ], id: \.0) { value, label in
                            Button {
                                selectedDistance = value
                            } label: {
                                Text(label)
                                    .font(.dripCaption(12))
                                    .foregroundStyle(selectedDistance == value ? .white : Color.drip.textSecondary)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(selectedDistance == value ? Color.drip.coral : Color.drip.cardBackground)
                                    .clipShape(Capsule())
                                    .overlay(
                                        Capsule().stroke(selectedDistance == value ? Color.clear : Color.drip.divider, lineWidth: 1)
                                    )
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 32)

            // Time picker
            VStack(alignment: .leading, spacing: 8) {
                Text("GOAL TIME (OPTIONAL)")
                    .font(.dripCaption(10))
                    .foregroundStyle(Color.drip.textTertiary)
                    .tracking(1.5)

                HStack(spacing: 4) {
                    Picker("Hours", selection: $goalHours) {
                        ForEach(0..<6, id: \.self) { Text("\($0)h").tag($0) }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 70, height: 100)
                    .clipped()

                    Text(":")
                        .font(.dripDisplay(20))

                    Picker("Minutes", selection: $goalMinutes) {
                        ForEach(0..<60, id: \.self) { Text(String(format: "%02dm", $0)).tag($0) }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 80, height: 100)
                    .clipped()

                    Text(":")
                        .font(.dripDisplay(20))

                    Picker("Seconds", selection: $goalSeconds) {
                        ForEach(0..<60, id: \.self) { Text(String(format: "%02ds", $0)).tag($0) }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 80, height: 100)
                    .clipped()
                }
            }
            .padding(.horizontal, 32)

            Spacer()

            VStack(spacing: 12) {
                nextButton("Continue")

                Button {
                    currentStep = 3
                } label: {
                    Text("Skip for now")
                        .font(.dripCaption(12))
                        .foregroundStyle(Color.drip.textTertiary)
                }
            }
        }
    }

    // MARK: - Step 4: Ready

    private var readyStep: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Color.drip.energized)

                Text("You're All Set")
                    .font(.dripDisplay(32))
                    .foregroundStyle(Color.drip.textPrimary)

                Text("After your next run, hit the record button and tell us how it went. The AI does the rest.")
                    .font(.dripBody(15))
                    .foregroundStyle(Color.drip.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            VStack(alignment: .leading, spacing: 16) {
                TipRow(number: "1", text: "Tap the mic and talk about your run")
                TipRow(number: "2", text: "AI transcribes, analyzes, and coaches")
                TipRow(number: "3", text: "Check the Training tab for insights")
            }
            .padding(.horizontal, 40)

            Spacer()

            Button {
                saveGoalIfNeeded()
                hasCompletedOnboarding = true
            } label: {
                HStack(spacing: 8) {
                    Text("Start Training")
                        .font(.dripLabel(16))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(Color.drip.coral)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Shared Components

    private func nextButton(_ title: String) -> some View {
        Button {
            withAnimation { currentStep += 1 }
        } label: {
            Text(title)
                .font(.dripLabel(15))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.drip.coral)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .padding(.horizontal, 40)
        .padding(.bottom, 40)
    }

    // MARK: - Save Goal

    private func saveGoalIfNeeded() {
        let totalSeconds = goalHours * 3600 + goalMinutes * 60 + goalSeconds
        guard totalSeconds > 0 else { return }

        Task {
            let userId = AuthManager.shared.userId
            guard !userId.isEmpty else { return }

            try? await supabase
                .from("user_goals")
                .insert([
                    "user_id": userId,
                    "goal_title": "\(selectedDistance.replacingOccurrences(of: "_", with: " ").capitalized) Goal",
                    "goal_type": selectedDistance,
                    "target_time": "\(goalHours):\(String(format: "%02d", goalMinutes)):\(String(format: "%02d", goalSeconds))",
                    "target_date": ISO8601DateFormatter().string(from: Date().addingTimeInterval(86400 * 120)),
                    "status": "active",
                ])
                .execute()
        }
    }
}

// MARK: - Supporting Views

private struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color.drip.coral)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.dripLabel(14))
                    .foregroundStyle(Color.drip.textPrimary)
                Text(description)
                    .font(.dripBody(12))
                    .foregroundStyle(Color.drip.textSecondary)
            }
        }
    }
}

private struct TipRow: View {
    let number: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.drip.coral.opacity(0.15))
                    .frame(width: 28, height: 28)
                Text(number)
                    .font(.dripLabel(13))
                    .foregroundStyle(Color.drip.coral)
            }

            Text(text)
                .font(.dripBody(14))
                .foregroundStyle(Color.drip.textSecondary)
        }
    }
}
