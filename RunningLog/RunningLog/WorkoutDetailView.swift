//
//  WorkoutDetailView.swift
//  RunningLog
//
//  Detailed view for a generated Canova workout with step-by-step display and export.
//

import os
import SwiftUI

// MARK: - WorkoutDetailView

struct WorkoutDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let workout: CanovaWorkout
    let racePaceSeconds: Double

    @State private var isExporting = false
    @State private var showExportSheet = false
    @State private var exportedFileURL: URL?
    @State private var showExportError = false
    @State private var exportErrorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.drip.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Workout Header
                        WorkoutDetailHeader(
                            workout: workout,
                            racePaceSeconds: racePaceSeconds
                        )
                        .padding(.horizontal, 20)

                        // Workout Steps
                        VStack(alignment: .leading, spacing: 16) {
                            Text("WORKOUT STEPS")
                                .font(.dripCaption(11))
                                .foregroundStyle(Color.drip.textSecondary)
                                .tracking(1.2)
                                .padding(.horizontal, 20)

                            VStack(spacing: 0) {
                                ForEach(Array(workout.steps.enumerated()), id: \.element.id) { index, step in
                                    WorkoutStepRow(
                                        step: step,
                                        stepNumber: index + 1,
                                        totalSteps: workout.steps.count,
                                        racePaceSeconds: racePaceSeconds
                                    )
                                }
                            }
                            .background(Color.drip.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .padding(.horizontal, 20)
                        }

                        // Phase Info
                        PhaseInfoCard(phase: workout.trainingPhase)
                            .padding(.horizontal, 20)

                        // Export Button
                        VStack(spacing: 12) {
                            DripButton(
                                "Export to Garmin",
                                icon: "square.and.arrow.up",
                                style: .primary,
                                isLoading: isExporting
                            ) {
                                exportWorkout()
                            }

                            Text("Downloads as a .FIT file for Garmin Connect")
                                .font(.dripCaption(11))
                                .foregroundStyle(Color.drip.textTertiary)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                        Spacer()
                            .frame(height: 40)
                    }
                    .padding(.top, 20)
                }
            }
            .navigationTitle(workout.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.dripBody(15))
                    .foregroundStyle(Color.drip.coral)
                }
            }
            .toolbarBackground(Color.drip.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(isPresented: $showExportSheet) {
                if let url = exportedFileURL {
                    ShareSheet(items: [url])
                }
            }
            .alert("Export Failed", isPresented: $showExportError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(exportErrorMessage ?? "An error occurred while exporting")
            }
        }
    }

    private func exportWorkout() {
        isExporting = true

        Task {
            do {
                let fitService = FITExportService()
                let url = try await fitService.exportWorkout(workout, racePaceSeconds: racePaceSeconds)

                await MainActor.run {
                    exportedFileURL = url
                    isExporting = false
                    showExportSheet = true
                }
            } catch {
                Log.coach.error("Failed to export workout: \(error)")
                await MainActor.run {
                    isExporting = false
                    exportErrorMessage = error.localizedDescription
                    showExportError = true
                }
            }
        }
    }
}

// MARK: - WorkoutDetailHeader

struct WorkoutDetailHeader: View {
    let workout: CanovaWorkout
    let racePaceSeconds: Double

    var body: some View {
        VStack(spacing: 16) {
            // Category and signature badges
            HStack(spacing: 8) {
                CategoryBadge(category: workout.category)

                if let signature = workout.signatureType {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10))

                        Text(signature.displayName)
                            .font(.dripCaption(10))
                    }
                    .foregroundStyle(Color.drip.coral)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.drip.coral.opacity(0.15))
                    .clipShape(Capsule())
                }

                Spacer()
            }

            // Description
            Text(workout.description)
                .font(.dripBody(14))
                .foregroundStyle(Color.drip.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Stats
            HStack(spacing: 0) {
                StatColumn(
                    icon: "figure.run",
                    label: "DISTANCE",
                    value: workout.formattedTotalDistance ?? "--"
                )

                Divider()
                    .frame(height: 40)
                    .background(Color.drip.divider)

                StatColumn(
                    icon: "clock",
                    label: "DURATION",
                    value: workout.formattedDuration ?? "--"
                )

                Divider()
                    .frame(height: 40)
                    .background(Color.drip.divider)

                StatColumn(
                    icon: "list.number",
                    label: "STEPS",
                    value: "\(workout.steps.count)"
                )
            }
            .padding(.vertical, 12)
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - StatColumn

struct StatColumn: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Color.drip.coral)

            Text(label)
                .font(.dripCaption(9))
                .foregroundStyle(Color.drip.textTertiary)
                .tracking(0.5)

            Text(value)
                .font(.dripLabel(14))
                .foregroundStyle(Color.drip.textPrimary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - WorkoutStepRow

struct WorkoutStepRow: View {
    let step: CanovaWorkoutStep
    let stepNumber: Int
    let totalSteps: Int
    let racePaceSeconds: Double

    var isLast: Bool {
        stepNumber == totalSteps
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Step indicator
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(step.stepType.color.opacity(0.2))
                        .frame(width: 32, height: 32)

                    Image(systemName: stepIcon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(step.stepType.color)
                }

                if !isLast {
                    Rectangle()
                        .fill(Color.drip.divider)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }

            // Step details
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(step.stepType.displayName)
                        .font(.dripLabel(14))
                        .foregroundStyle(step.stepType.color)

                    Spacer()

                    Text(step.formattedDuration)
                        .font(.dripStat(16))
                        .foregroundStyle(Color.drip.textPrimary)
                }

                // Pace target
                if let intensity = step.targetPaceIntensity {
                    HStack(spacing: 8) {
                        Text("Target:")
                            .font(.dripCaption(12))
                            .foregroundStyle(Color.drip.textTertiary)

                        Text(intensity.formattedPace(forRacePace: racePaceSeconds))
                            .font(.dripLabel(13))
                            .foregroundStyle(Color.drip.energized)

                        Text("(\(intensity.displayPercentage) MP)")
                            .font(.dripCaption(11))
                            .foregroundStyle(Color.drip.textSecondary)
                    }
                }

                // Notes
                if let notes = step.notes {
                    Text(notes)
                        .font(.dripBody(12))
                        .foregroundStyle(Color.drip.textSecondary)
                }
            }
            .padding(.bottom, isLast ? 0 : 20)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, isLast ? 16 : 12)

        if !isLast {
            Divider()
                .background(Color.drip.divider)
                .padding(.leading, 64)
        }
    }

    private var stepIcon: String {
        switch step.stepType {
        case .warmup: return "sun.max"
        case .active: return "bolt.fill"
        case .rest: return "pause.fill"
        case .recovery: return "wind"
        case .cooldown: return "moon.fill"
        }
    }
}

// MARK: - PhaseInfoCard

struct PhaseInfoCard: View {
    let phase: CanovaTrainingPhase

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(phase.color.opacity(0.2))
                    .frame(width: 36, height: 36)

                Image(systemName: phase.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(phase.color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Designed for \(phase.displayName)")
                    .font(.dripLabel(13))
                    .foregroundStyle(Color.drip.textPrimary)

                Text(phase.description)
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textSecondary)
            }

            Spacer()
        }
        .padding(14)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(phase.color.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Preview

#Preview {
    WorkoutDetailView(
        workout: CanovaWorkout.sample,
        racePaceSeconds: 480 // 8:00/mi pace
    )
}
