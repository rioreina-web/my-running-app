//
//  OnboardingView.swift
//  RunningLog
//
//  Editorial onboarding flow per
//  `design-system/ui_kits/ios_app/OnboardingScreen.jsx`. Four steps:
//  (1) Welcome  (2) Connect data  (3) Set a goal  (4) Ready.
//
//  Replaces the prior SF-Symbol-and-rounded-pill style with hairline-
//  bound editorial vocabulary — monospaced labels, Crimson Pro display,
//  coral progress strip, no SF Symbols. The working wiring carries
//  over unchanged: HealthKit authorization, goal save to `user_goals`,
//  and the `hasCompletedOnboarding` AppStorage flag.
//

import HealthKit
import Supabase
import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @EnvironmentObject private var healthKitManager: HealthKitManager
    @State private var currentStep = 0

    // Connect-data state. Strava + manual are display-only here; the
    // production wiring lives elsewhere. HealthKit reads from
    // `healthKitManager.isAuthorized`.
    @State private var stravaConnected = false

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
                plateStripHeader

                progressStrip
                    .padding(.horizontal, 56)
                    .padding(.top, 18)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        switch currentStep {
                        case 0: welcomeStep
                        case 1: connectStep
                        case 2: goalStep
                        case 3: readyStep
                        default: EmptyView()
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 28)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                footer
            }
        }
        .animation(.easeInOut(duration: 0.25), value: currentStep)
    }

    // MARK: - Plate strip header

    private var plateStripHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("RUNNING LOG")
                    .font(.dripCaption(10)).tracking(1.4)
                    .foregroundStyle(Color.drip.textPrimary)
                Text("— FIRST-RUN · v1 ONBOARDING")
                    .font(.dripCaption(10)).tracking(1.4)
                    .foregroundStyle(Color.drip.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("STEP \(currentStep + 1) / \(totalSteps)")
                    .font(.dripCaption(10)).tracking(1.4)
                    .foregroundStyle(Color.drip.textPrimary)
                Button {
                    hasCompletedOnboarding = true
                } label: {
                    Text("SKIP ↗")
                        .font(.dripCaption(10)).tracking(1.4)
                        .foregroundStyle(Color.drip.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 32)
        .padding(.bottom, 12)
    }

    // MARK: - Progress strip

    private var progressStrip: some View {
        HStack(spacing: 6) {
            ForEach(0..<totalSteps, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i <= currentStep ? Color.drip.coral : Color.drip.divider)
                    .frame(height: 2)
            }
        }
    }

    // MARK: - Step 0: Welcome

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrow("WELCOME")
            displayTitle("A quieter log\nfor serious runners.")
            italicSub("— half diary, half cockpit. Talk to it after a run; the coach reads the week. —")

            VStack(spacing: 0) {
                featureRow(num: "01", title: "Voice memos.",
                           desc: "Tap the coral button. Talk for two minutes. It transcribes, extracts a mood, and saves it to your journal.",
                           topHairline: true, bottomHairline: false)
                featureRow(num: "02", title: "Glass-box analysis.",
                           desc: "Pace, HR zones, splits — and the rationale behind every coaching note. No black boxes.",
                           topHairline: true, bottomHairline: false)
                featureRow(num: "03", title: "A coach in the room.",
                           desc: "Reads your log every Sunday night. Ask follow-ups any time. Reasons in plain language.",
                           topHairline: true, bottomHairline: true)
            }
            .padding(.top, 22)
        }
    }

    // MARK: - Step 1: Connect data

    private var connectStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrow("DATA · SOURCES")
            displayTitle("Where do your\nruns come from?")
            italicSub("— Apple Health pulls everything: Garmin, Coros, Strava, the watch on your wrist. Pick what you have. —")

            VStack(spacing: 0) {
                sourceRow(label: "Apple Health",
                          hint: "Pulls runs, HR, and sleep automatically.",
                          actionText: healthKitManager.isAuthorized ? "CONNECTED ✓" : "ALLOW ↗",
                          actionColor: healthKitManager.isAuthorized ? Color.drip.energized : Color.drip.coral,
                          topHairline: true, bottomHairline: false) {
                    Task { _ = await healthKitManager.requestAuthorization() }
                }
                sourceRow(label: "Strava",
                          hint: "Optional — only if Health misses runs.",
                          actionText: stravaConnected ? "CONNECTED ✓" : "CONNECT ↗",
                          actionColor: stravaConnected ? Color.drip.energized : Color.drip.coral,
                          topHairline: true, bottomHairline: false) {
                    stravaConnected.toggle()
                }
                sourceRow(label: "Manual entry",
                          hint: "Always available — no permissions needed.",
                          actionText: "READY",
                          actionColor: Color.drip.textTertiary,
                          topHairline: true, bottomHairline: true,
                          action: nil)
            }
            .padding(.top, 22)

            Text("— you can change any of this later. Nothing is collected unless you say so. —")
                .font(.system(size: 12, design: .serif).italic())
                .foregroundStyle(Color.drip.textTertiary)
                .padding(.top, 18)
                .lineSpacing(2)
        }
    }

    // MARK: - Step 2: Goal

    private var goalStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrow("A GOAL")
            displayTitle("What are you\ntraining for?")
            italicSub("— this anchors the coaching. You can change it any week. —")

            // Distance chips
            VStack(alignment: .leading, spacing: 0) {
                eyebrow("DISTANCE", color: Color.drip.textTertiary)
                    .padding(.top, 22)
                distanceChipRow
                    .padding(.top, 14)
            }

            // Time picker
            VStack(alignment: .leading, spacing: 0) {
                eyebrow("GOAL TIME · OPTIONAL", color: Color.drip.textTertiary)
                    .padding(.top, 22)
                goalTimePicker
                    .padding(.top, 14)
            }
        }
    }

    private var distanceChipRow: some View {
        // Wrapping flex layout — three rows of two when needed.
        // SwiftUI doesn't have a native flow layout pre-iOS 16; the
        // chips wrap by being placed in an HStack with .fixedSize and
        // grouping. Two HStacks keep it simple.
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                distanceChip(value: "5k", label: "5K")
                distanceChip(value: "10k", label: "10K")
                distanceChip(value: "half_marathon", label: "HALF")
            }
            HStack(spacing: 8) {
                distanceChip(value: "marathon", label: "MARATHON")
                distanceChip(value: "ultra", label: "ULTRA")
            }
            HStack(spacing: 8) {
                distanceChip(value: "general", label: "GENERAL FITNESS")
            }
        }
    }

    private func distanceChip(value: String, label: String) -> some View {
        let isActive = selectedDistance == value
        return Button {
            selectedDistance = value
        } label: {
            Text(label)
                .font(.dripCaption(11)).tracking(1.3)
                .foregroundStyle(isActive ? Color.drip.coral : Color.drip.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.clear)
                .overlay(
                    Capsule().stroke(isActive ? Color.drip.coral : Color.drip.divider, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var goalTimePicker: some View {
        HStack(spacing: 6) {
            timeColumn(label: "HRS", selection: $goalHours, range: 0..<6, format: "%d")
            colonSeparator
            timeColumn(label: "MIN", selection: $goalMinutes, range: 0..<60, format: "%02d")
            colonSeparator
            timeColumn(label: "SEC", selection: $goalSeconds, range: 0..<60, format: "%02d")
        }
    }

    private func timeColumn(label: String, selection: Binding<Int>, range: Range<Int>, format: String) -> some View {
        VStack(spacing: 4) {
            Picker(label, selection: selection) {
                ForEach(range, id: \.self) { v in
                    Text(String(format: format, v))
                        .font(.system(size: 22, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                        .tag(v)
                }
            }
            .pickerStyle(.wheel)
            .frame(width: 60, height: 72)
            .clipped()
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(Color.drip.textTertiary)
        }
    }

    private var colonSeparator: some View {
        Text(":")
            .font(.dripDisplay(22))
            .foregroundStyle(Color.drip.textTertiary)
            .frame(width: 12)
    }

    // MARK: - Step 3: Ready

    private var readyStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrow("YOU'RE IN")
            displayTitle("Three habits.\nThat's the whole product.")
            italicSub("— keep these going for a couple of weeks and the coaching gets sharp. —")

            VStack(spacing: 0) {
                tipRow(num: "01", text: "After a run, tap the coral button on the LOG tab and talk for a minute.",
                       topHairline: true, bottomHairline: false)
                tipRow(num: "02", text: "Check the TRAIN tab in the morning. Read the day's prescription out loud if it helps.",
                       topHairline: true, bottomHairline: false)
                tipRow(num: "03", text: "Sunday night, your coach posts a note. Read it. Reply if something is off.",
                       topHairline: true, bottomHairline: true)
            }
            .padding(.top, 22)

            Text("— that's it. Nothing else to learn. —")
                .font(.system(size: 12, design: .serif).italic())
                .foregroundStyle(Color.drip.textTertiary)
                .padding(.top, 18)
                .lineSpacing(2)
        }
    }

    // MARK: - Editorial primitives (local — small enough to inline)

    @ViewBuilder
    private func eyebrow(_ text: String, color: Color = Color.drip.coral) -> some View {
        Text(text)
            .font(.dripCaption(10)).tracking(1.4)
            .foregroundStyle(color)
    }

    @ViewBuilder
    private func displayTitle(_ text: String) -> some View {
        Text(text)
            .font(.dripDisplay(38))
            .foregroundStyle(Color.drip.textPrimary)
            .padding(.top, 6)
            .lineSpacing(2)
    }

    @ViewBuilder
    private func italicSub(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, design: .serif).italic())
            .foregroundStyle(Color.drip.textSecondary)
            .padding(.top, 12)
            .lineSpacing(3)
    }

    private func featureRow(num: String, title: String, desc: String,
                            topHairline: Bool, bottomHairline: Bool) -> some View {
        VStack(spacing: 0) {
            if topHairline { DripHairline() }
            HStack(alignment: .top, spacing: 14) {
                Text(num)
                    .font(.dripCaption(10)).tracking(1.0)
                    .foregroundStyle(Color.drip.coral)
                    .frame(width: 28, alignment: .leading)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.dripDisplay(16))
                        .foregroundStyle(Color.drip.textPrimary)
                    Text(desc)
                        .font(.dripBody(13))
                        .foregroundStyle(Color.drip.textSecondary)
                        .lineSpacing(2)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 18)
            if bottomHairline { DripHairline() }
        }
    }

    private func sourceRow(label: String, hint: String, actionText: String,
                           actionColor: Color, topHairline: Bool, bottomHairline: Bool,
                           action: (() -> Void)? = nil) -> some View {
        VStack(spacing: 0) {
            if topHairline { DripHairline() }
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.dripDisplay(15))
                        .foregroundStyle(Color.drip.textPrimary)
                    Text(hint)
                        .font(.system(size: 12, design: .serif).italic())
                        .foregroundStyle(Color.drip.textTertiary)
                }
                Spacer(minLength: 12)
                if let action {
                    Button(action: action) {
                        Text(actionText)
                            .font(.dripCaption(11)).tracking(1.3)
                            .foregroundStyle(actionColor)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(actionText)
                        .font(.dripCaption(11)).tracking(1.3)
                        .foregroundStyle(actionColor)
                }
            }
            .padding(.vertical, 14)
            if bottomHairline { DripHairline() }
        }
    }

    private func tipRow(num: String, text: String,
                        topHairline: Bool, bottomHairline: Bool) -> some View {
        VStack(spacing: 0) {
            if topHairline { DripHairline() }
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(num)
                    .font(.dripCaption(10)).tracking(1.0)
                    .foregroundStyle(Color.drip.coral)
                    .frame(width: 28, alignment: .leading)
                Text(text)
                    .font(.dripBody(14))
                    .foregroundStyle(Color.drip.textPrimary)
                    .lineSpacing(2)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 14)
            if bottomHairline { DripHairline() }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 12) {
            Button {
                advance()
            } label: {
                Text(currentStep < totalSteps - 1 ? "Continue" : "Start training ↗")
                    .font(.dripLabel(15))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.drip.coral)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            if currentStep > 0 {
                Button {
                    withAnimation { currentStep -= 1 }
                } label: {
                    Text("← BACK")
                        .font(.dripCaption(11)).tracking(1.4)
                        .foregroundStyle(Color.drip.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 18)
        .padding(.bottom, 28)
    }

    // MARK: - Navigation + persistence

    private func advance() {
        if currentStep < totalSteps - 1 {
            withAnimation { currentStep += 1 }
        } else {
            saveGoalIfNeeded()
            hasCompletedOnboarding = true
        }
    }

    private func saveGoalIfNeeded() {
        let totalSeconds = goalHours * 3600 + goalMinutes * 60 + goalSeconds
        guard totalSeconds > 0 else { return }

        Task {
            let userId = AuthManager.shared.userId
            guard !userId.isEmpty else { return }

            _ = try? await supabase
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
