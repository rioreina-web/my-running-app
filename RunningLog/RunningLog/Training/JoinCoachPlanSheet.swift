//
//  JoinCoachPlanSheet.swift
//  RunningLog
//
//  Athlete enters a 6-char join code to subscribe to a coach's plan template.
//  On success, calls subscribe-to-plan edge function which generates
//  the athlete's real training_plans + scheduled_workouts records.
//

import SwiftUI

struct JoinCoachPlanSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var joinCode = ""
    @State private var startDate = Date()
    @State private var goalTimeSeconds: Int? = nil
    @State private var goalTimeText = ""
    @State private var isJoining = false
    @State private var errorMessage: String? = nil
    @State private var successMessage: String? = nil

    // Use a local CoachViewModel instance — we don't need the full coach profile here
    @State private var viewModel = CoachViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                DripBackground().ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Icon + heading
                        VStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(Color.drip.coral.opacity(0.12))
                                    .frame(width: 72, height: 72)
                                Image(systemName: "link.badge.plus")
                                    .font(.system(size: 30))
                                    .foregroundStyle(Color.drip.coral)
                            }
                            Text("Join a Coach Plan")
                                .font(.dripLabel(20))
                                .foregroundStyle(Color.drip.textPrimary)
                            Text("Enter the 6-character code your coach shared with you.")
                                .font(.dripBody(14))
                                .foregroundStyle(Color.drip.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                        }
                        .padding(.top, 12)

                        // Join code input
                        VStack(alignment: .leading, spacing: 8) {
                            Text("JOIN CODE")
                                .font(.dripCaption(11))
                                .foregroundStyle(Color.drip.textTertiary)
                            TextField("e.g. AB3X9Z", text: $joinCode)
                                .font(.dripStat(28))
                                .multilineTextAlignment(.center)
                                .textCase(.uppercase)
                                .autocorrectionDisabled()
                                .keyboardType(.asciiCapable)
                                .onChange(of: joinCode) { _, val in
                                    joinCode = String(val.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6))
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 16)
                                .background(Color.drip.cardBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(joinCode.count == 6 ? Color.drip.coral : Color.drip.divider, lineWidth: joinCode.count == 6 ? 2 : 1)
                                )
                        }

                        // Start date
                        VStack(alignment: .leading, spacing: 8) {
                            Text("PLAN START DATE")
                                .font(.dripCaption(11))
                                .foregroundStyle(Color.drip.textTertiary)
                            HStack {
                                Image(systemName: "calendar")
                                    .foregroundStyle(Color.drip.textSecondary)
                                DatePicker("", selection: $startDate, displayedComponents: .date)
                                    .datePickerStyle(.compact)
                                    .labelsHidden()
                                    .tint(Color.drip.coral)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Color.drip.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.drip.divider, lineWidth: 1)
                            )
                        }

                        // Optional: goal time
                        VStack(alignment: .leading, spacing: 8) {
                            Text("GOAL TIME (OPTIONAL)")
                                .font(.dripCaption(11))
                                .foregroundStyle(Color.drip.textTertiary)
                            TextField("e.g. 3:30:00 for a 3:30 marathon", text: $goalTimeText)
                                .font(.dripBody(15))
                                .keyboardType(.numbersAndPunctuation)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(Color.drip.cardBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.drip.divider, lineWidth: 1)
                                )
                            Text("Used to personalize pace targets in the plan")
                                .font(.dripCaption(11))
                                .foregroundStyle(Color.drip.textTertiary)
                        }

                        // Error / Success
                        if let err = errorMessage {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(Color.drip.injured)
                                Text(err)
                                    .font(.dripBody(14))
                                    .foregroundStyle(Color.drip.injured)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Color.drip.injured.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }

                        if let success = successMessage {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.drip.positive)
                                Text(success)
                                    .font(.dripBody(14))
                                    .foregroundStyle(Color.drip.positive)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Color.drip.positive.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }

                        // Join button
                        Button {
                            Task { await joinPlan() }
                        } label: {
                            HStack(spacing: 8) {
                                if isJoining {
                                    ProgressView().tint(.white).scaleEffect(0.85)
                                } else {
                                    Image(systemName: "person.badge.plus")
                                }
                                Text(isJoining ? "Joining..." : "Join Plan")
                                    .font(.dripLabel(16))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(joinCode.count < 6 ? Color.drip.textTertiary : Color.drip.coral)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .disabled(joinCode.count < 6 || isJoining)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Join Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .font(.dripLabel(14))
                        .foregroundStyle(Color.drip.textSecondary)
                }
            }
        }
    }

    private func joinPlan() async {
        errorMessage = nil
        successMessage = nil
        isJoining = true
        defer { isJoining = false }

        let goalSecs = parseGoalTime(goalTimeText)

        let success = await viewModel.joinPlanByCode(
            joinCode,
            startDate: startDate,
            goalTimeSeconds: goalSecs
        )

        if success {
            successMessage = "You've joined the plan! It will appear in your Training tab."
            Task {
                try? await Task.sleep(for: .seconds(2))
                dismiss()
            }
        } else {
            errorMessage = viewModel.error ?? "Failed to join plan. Check your code and try again."
        }
    }

    /// Parse "3:30:00" or "3:30" into seconds
    private func parseGoalTime(_ text: String) -> Int? {
        let parts = text.split(separator: ":").compactMap { Int($0) }
        switch parts.count {
        case 3: return parts[0] * 3600 + parts[1] * 60 + parts[2]
        case 2: return parts[0] * 3600 + parts[1] * 60
        default: return nil
        }
    }
}
