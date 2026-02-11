//
//  FitnessPredictorView.swift
//  RunningLog
//
//  AI-powered race time predictions based on training data.
//

import Supabase
import SwiftUI

// MARK: - FitnessPredictorView

struct FitnessPredictorView: View {
    @Bindable var trainingViewModel: TrainingPlanViewModel
    @State private var predictor = FitnessPredictorService()
    private let healthKitManager = HealthKitManager.shared

    var body: some View {
        ZStack {
            DripBackground()

            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    HeaderSection(
                        isAnalyzing: predictor.isAnalyzing,
                        lastUpdated: predictor.lastUpdated,
                        onPredict: predict
                    )
                    .padding(.horizontal, 20)

                    // Error
                    if let error = predictor.errorMessage {
                        PredictionErrorBanner(message: error)
                            .padding(.horizontal, 20)
                    }

                    // Race Predictions
                    if let predictions = predictor.predictions {
                        RacePredictionsCard(predictions: predictions)
                            .padding(.horizontal, 20)

                        // Fitness summary
                        if let summary = predictions.fitnessSummary {
                            FitnessSummaryCard(summary: summary)
                                .padding(.horizontal, 20)
                        }

                        // Data sources
                        DataSourcesCard(sources: predictions.dataSources)
                            .padding(.horizontal, 20)
                    } else if !predictor.isAnalyzing {
                        // Empty state
                        EmptyPredictionState(onPredict: predict)
                            .padding(.horizontal, 20)
                    }

                    Spacer()
                        .frame(height: 100)
                }
                .padding(.top, 8)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("FITNESS PREDICTOR")
                    .font(.dripCaption(12))
                    .foregroundStyle(Color.drip.textSecondary)
                    .tracking(2)
            }
        }
        .toolbarBackground(Color.drip.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task {
            // Auto-load predictions when view appears
            await loadPredictions()
        }
    }

    private func predict() {
        Task {
            await loadPredictions()
        }
    }

    private func loadPredictions() async {
        // Try to get HealthKit authorization (don't block if denied)
        _ = await healthKitManager.requestAuthorization()

        await predictor.predictFitness(
            plan: trainingViewModel.activePlan,
            healthKitManager: healthKitManager
        )
    }
}

// MARK: - Header Section

private struct HeaderSection: View {
    let isAnalyzing: Bool
    let lastUpdated: Date?
    let onPredict: () -> Void

    private var subtitle: String {
        if let date = lastUpdated {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            return "Updated \(formatter.localizedString(for: date, relativeTo: Date()))"
        }
        return "Predict your race times"
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Race Predictions")
                        .font(.dripLabel(20))
                        .foregroundStyle(Color.drip.textPrimary)

                    Text(subtitle)
                        .font(.dripCaption(12))
                        .foregroundStyle(Color.drip.textTertiary)
                }

                Spacer()

                Button(action: onPredict) {
                    HStack(spacing: 8) {
                        if isAnalyzing {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "sparkles")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        Text(isAnalyzing ? "Analyzing..." : "Predict")
                            .font(.dripLabel(14))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.drip.coral)
                    .clipShape(Capsule())
                }
                .disabled(isAnalyzing)
            }
        }
        .padding(16)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Race Predictions Card

private struct RacePredictionsCard: View {
    let predictions: FitnessPrediction

    var body: some View {
        VStack(spacing: 16) {
            // Top row: Mile, 5K, 10K
            HStack(spacing: 12) {
                ForEach(predictions.races.prefix(3)) { race in
                    RacePredictionTile(race: race, isCompact: true)
                }
            }

            // Bottom row: Half, Marathon
            HStack(spacing: 12) {
                ForEach(predictions.races.dropFirst(3)) { race in
                    RacePredictionTile(race: race, isCompact: false)
                }
            }
        }
        .padding(20)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

private struct RacePredictionTile: View {
    let race: RacePredictionItem
    var isCompact: Bool = false

    var body: some View {
        VStack(spacing: isCompact ? 6 : 8) {
            // Distance label
            Text(race.distance)
                .font(.dripCaption(isCompact ? 10 : 11))
                .foregroundStyle(Color.drip.textSecondary)
                .tracking(1)

            // Time
            Text(race.time)
                .font(.dripStat(isCompact ? 22 : 28))
                .foregroundStyle(Color.drip.textPrimary)

            // Pace
            Text(race.pace)
                .font(.dripCaption(isCompact ? 10 : 12))
                .foregroundStyle(Color.drip.coral)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, isCompact ? 12 : 16)
        .background(Color.drip.background.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Fitness Summary Card

private struct FitnessSummaryCard: View {
    let summary: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.drip.coral)

                Text("AI ANALYSIS")
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textSecondary)
                    .tracking(1.2)
            }

            Text(summary)
                .font(.dripBody(14))
                .foregroundStyle(Color.drip.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Data Sources Card

private struct DataSourcesCard: View {
    let sources: DataSources

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DATA ANALYZED")
                .font(.dripCaption(11))
                .foregroundStyle(Color.drip.textSecondary)
                .tracking(1.2)

            HStack(spacing: 16) {
                DataSourceItem(
                    icon: "figure.run",
                    value: "\(sources.workoutCount)",
                    label: "Workouts"
                )

                DataSourceItem(
                    icon: "mic.fill",
                    value: "\(sources.voiceLogCount)",
                    label: "Voice Logs"
                )

                DataSourceItem(
                    icon: "flame.fill",
                    value: "\(sources.hardEffortCount)",
                    label: "Hard Efforts"
                )

                DataSourceItem(
                    icon: "chart.bar.fill",
                    value: sources.confidence,
                    label: "Confidence"
                )
            }
        }
        .padding(16)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct DataSourceItem: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Color.drip.coral)

            Text(value)
                .font(.dripStat(16))
                .foregroundStyle(Color.drip.textPrimary)

            Text(label)
                .font(.dripCaption(9))
                .foregroundStyle(Color.drip.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Empty State

private struct EmptyPredictionState: View {
    let onPredict: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.drip.coral.opacity(0.15))
                    .frame(width: 80, height: 80)

                Image(systemName: "trophy.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.drip.coral)
            }

            VStack(spacing: 8) {
                Text("Predict Your Race Times")
                    .font(.dripLabel(18))
                    .foregroundStyle(Color.drip.textPrimary)

                Text("We'll analyze your workouts, voice logs, and training notes to estimate what you can run.")
                    .font(.dripBody(14))
                    .foregroundStyle(Color.drip.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: onPredict) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16))

                    Text("Get My Predictions")
                        .font(.dripLabel(16))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(Color.drip.coral)
                .clipShape(Capsule())
            }

            // What's analyzed
            VStack(alignment: .leading, spacing: 10) {
                Text("WHAT WE ANALYZE")
                    .font(.dripCaption(10))
                    .foregroundStyle(Color.drip.textTertiary)
                    .tracking(1)

                AnalysisItem(icon: "figure.run", text: "HealthKit workouts (30 days)")
                AnalysisItem(icon: "mic.fill", text: "Voice training logs & notes")
                AnalysisItem(icon: "speedometer", text: "Paces from hard efforts")
                AnalysisItem(icon: "brain.head.profile", text: "AI fitness estimation")
            }
            .padding(.top, 12)
        }
        .padding(24)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

private struct AnalysisItem: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(Color.drip.coral)
                .frame(width: 20)

            Text(text)
                .font(.dripCaption(12))
                .foregroundStyle(Color.drip.textSecondary)
        }
    }
}

// MARK: - Prediction Error Banner

private struct PredictionErrorBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.drip.tired)

            Text(message)
                .font(.dripBody(14))
                .foregroundStyle(Color.drip.textPrimary)

            Spacer()
        }
        .padding(16)
        .background(Color.drip.tired.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.drip.tired.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        FitnessPredictorView(trainingViewModel: TrainingPlanViewModel())
    }
}
