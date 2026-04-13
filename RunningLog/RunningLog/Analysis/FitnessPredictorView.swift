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
    @EnvironmentObject private var healthKitManager: HealthKitManager
    @Environment(VitalManager.self) private var vitalManager
    @Bindable var trainingViewModel: TrainingPlanViewModel
    @State private var predictor = FitnessPredictorService()

    var body: some View {
        ZStack {
            DripBackground()

            ScrollView {
                VStack(spacing: 20) {
                    if let error = predictor.errorMessage {
                        PredictionErrorBanner(message: error)
                            .padding(.horizontal, 20)
                    }

                    if let predictions = predictor.predictions {
                        // Race predictions (with anchor inlined)
                        RacePredictionsCard(
                            predictions: predictions,
                            anchor: predictions.raceAnchor
                        )
                        .padding(.horizontal, 20)

                        // Training card (paces + stimulus combined)
                        if predictions.trainingPaces != nil || predictions.trainingStimulus != nil {
                            TrainingCard(
                                paces: predictions.trainingPaces,
                                stimulus: predictions.trainingStimulus
                            )
                            .padding(.horizontal, 20)
                        }

                        // Training volume by zone
                        TrainingEffortChart(
                            workouts: vitalManager.recentWorkouts,
                            equivalentPaces: EquivalentPaces(
                                raceDistance: .tenK,
                                goalTimeSeconds: Int(predictions.estimated10kPaceSeconds * 6.21371)
                            )
                        )
                        .padding(.horizontal, 20)

                        // Fitness trend (only with 2+ snapshots)
                        if predictor.snapshotHistory.count >= 2 {
                            FitnessTrendCard(
                                snapshots: predictor.snapshotHistory,
                                changeFromPrevious: predictor.tenKChangeFromPrevious,
                                previousDate: predictor.previousSnapshotDate
                            )
                            .padding(.horizontal, 20)
                        }

                        // Fitness summary
                        if let summary = predictions.fitnessSummary {
                            FitnessSummaryCard(summary: summary)
                                .padding(.horizontal, 20)
                        }

                        // Compact data sources footer
                        DataSourcesRow(sources: predictions.dataSources)
                            .padding(.horizontal, 20)

                    } else if predictor.isAnalyzing {
                        AnalyzingState()
                            .padding(.horizontal, 20)
                    } else {
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
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: predict) {
                    if predictor.isAnalyzing {
                        ProgressView()
                            .tint(Color.drip.coral)
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.drip.coral)
                    }
                }
                .disabled(predictor.isAnalyzing)
            }
        }
        .toolbarBackground(Color.drip.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task {
            async let historyTask: () = predictor.fetchHistory()
            async let predictTask: () = loadPredictions()
            _ = await (historyTask, predictTask)
        }
    }

    private func predict() {
        Task {
            await loadPredictions()
        }
    }

    private func loadPredictions() async {
        _ = await healthKitManager.requestAuthorization()
        await predictor.predictFitness(
            plan: trainingViewModel.activePlan
        )
    }
}

// MARK: - Analyzing State

private struct AnalyzingState: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(Color.drip.coral)
                .scaleEffect(1.2)
            Text("Analyzing your training...")
                .font(.dripBody(14))
                .foregroundStyle(Color.drip.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

// MARK: - Race Predictions Card (with anchor)

private struct RacePredictionsCard: View {
    let predictions: FitnessPrediction
    let anchor: RaceAnchorInfo?

    var body: some View {
        VStack(spacing: 0) {
            // Anchor strip at top (if present)
            if let anchor = anchor {
                HStack(spacing: 8) {
                    Image(systemName: "flag.checkered")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.drip.coral)

                    Text("\(anchor.raceType)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.drip.textPrimary)

                    Text(anchor.time)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.drip.textPrimary)

                    Text("·  \(anchor.date)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.drip.textTertiary)

                    Spacer()

                    Text("\(anchor.weeksAgo)w ago")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.drip.coral)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.drip.coral.opacity(0.1))
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.drip.background.opacity(0.5))
            }

            // Race tiles
            VStack(spacing: 12) {
                // Top row: Mile, 5K, 10K
                HStack(spacing: 10) {
                    ForEach(predictions.races.prefix(3)) { race in
                        RacePredictionTile(race: race, isCompact: true)
                    }
                }

                // Bottom row: Half, Marathon
                HStack(spacing: 10) {
                    ForEach(predictions.races.dropFirst(3)) { race in
                        RacePredictionTile(race: race, isCompact: false)
                    }
                }
            }
            .padding(16)
        }
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct RacePredictionTile: View {
    let race: RacePredictionItem
    var isCompact: Bool = false

    var body: some View {
        VStack(spacing: isCompact ? 3 : 5) {
            Text(race.distance)
                .font(.dripCaption(isCompact ? 9 : 10))
                .foregroundStyle(Color.drip.textTertiary)
                .tracking(1)

            Text(race.time)
                .font(.system(size: isCompact ? 17 : 20, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.drip.textPrimary)

            Text(race.pace)
                .font(.system(size: isCompact ? 10 : 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.drip.coral)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, isCompact ? 10 : 14)
        .background(Color.drip.background.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Combined Training Card (Paces + Stimulus)

private struct TrainingCard: View {
    let paces: TrainingPacesSummary?
    let stimulus: TrainingStimulusInfo?

    @State private var tab: TrainingTab = .paces

    enum TrainingTab: String, CaseIterable {
        case paces = "Paces"
        case stimulus = "Stimulus"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header with tab toggle
            HStack(spacing: 0) {
                Image(systemName: tab == .paces ? "speedometer" : "flame.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.drip.coral)
                    .frame(width: 20)
                    .padding(.trailing, 8)

                ForEach(TrainingTab.allCases, id: \.rawValue) { t in
                    let available = t == .paces ? paces != nil : stimulus != nil
                    if available {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { tab = t }
                        } label: {
                            Text(t.rawValue.uppercased())
                                .font(.dripCaption(10))
                                .tracking(1.2)
                                .foregroundStyle(tab == t ? Color.drip.textPrimary : Color.drip.textTertiary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(tab == t ? Color.drip.divider.opacity(0.5) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }

                Spacer()

                // Status pill (from stimulus)
                if let stimulus = stimulus {
                    let statusLabel = trainingStatus(stimulus)
                    let statusColor = trainingStatusColor(statusLabel)
                    Text(statusLabel)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(statusColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(statusColor.opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            // Content
            switch tab {
            case .paces:
                if let paces = paces {
                    PacesContent(paces: paces)
                }
            case .stimulus:
                if let stimulus = stimulus {
                    StimulusContent(stimulus: stimulus)
                }
            }
        }
        .padding(16)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onAppear {
            // Default to whichever tab has data
            if paces != nil {
                tab = .paces
            } else if stimulus != nil {
                tab = .stimulus
            }
        }
    }

    private func trainingStatus(_ s: TrainingStimulusInfo) -> String {
        if s.stimulusTrend > 1.2 && s.volumeTrend > 1.0 { return "Building" }
        if s.stimulusMinutes > 10 && s.volumeTrend >= 0.8 { return "Maintaining" }
        if s.stimulusMinutes > 0 || s.runsPerWeek >= 2 { return "Light" }
        return "Detraining"
    }

    private func trainingStatusColor(_ label: String) -> Color {
        switch label {
        case "Building": return Color.drip.positive
        case "Maintaining": return Color.drip.coral
        case "Light": return Color.drip.tired.opacity(0.7)
        default: return Color.drip.tired
        }
    }
}

// MARK: - Paces Content

private struct PacesContent: View {
    let paces: TrainingPacesSummary

    var body: some View {
        VStack(spacing: 6) {
            paceRow("Easy", paces.easyPace, Color.drip.positive)
            paceRow("Long Run", paces.longRunPace, Color.drip.positive.opacity(0.7))
            paceRow("Marathon", paces.marathonPace, Color.drip.coral.opacity(0.7))
            paceRow("Threshold", paces.thresholdPace, Color.drip.coral)
            paceRow("Interval", paces.intervalPace, Color.drip.tired)
        }
    }

    private func paceRow(_ label: String, _ pace: String, _ color: Color) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 3, height: 16)

            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.drip.textSecondary)

            Spacer()

            Text(pace)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.drip.textPrimary)
        }
    }
}

// MARK: - Stimulus Content

private struct StimulusContent: View {
    let stimulus: TrainingStimulusInfo

    private func trendIcon(_ trend: Double) -> String {
        if trend > 1.15 { return "arrow.up.right" }
        if trend < 0.85 { return "arrow.down.right" }
        return "arrow.right"
    }

    private func trendColor(_ trend: Double) -> Color {
        if trend > 1.15 { return Color.drip.positive }
        if trend < 0.85 { return Color.drip.tired }
        return Color.drip.textTertiary
    }

    var body: some View {
        HStack(spacing: 0) {
            stimulusStat(
                String(format: "%.0f", stimulus.weeklyMiles),
                "mi/week",
                trend: stimulus.volumeTrend
            )
            stimulusStat(
                String(format: "%.0f", stimulus.runsPerWeek),
                "runs/week",
                trend: nil
            )
            stimulusStat(
                String(format: "%.0f", stimulus.stimulusMinutes),
                "hard min",
                trend: stimulus.stimulusTrend
            )
            stimulusStat(
                "\(stimulus.structuredSessions)",
                "quality",
                trend: nil
            )
        }
    }

    private func stimulusStat(_ value: String, _ label: String, trend: Double?) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 2) {
                Text(value)
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.drip.textPrimary)
                if let trend = trend, trend != 0 {
                    Image(systemName: trendIcon(trend))
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(trendColor(trend))
                }
            }
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.drip.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Fitness Summary Card

private struct FitnessSummaryCard: View {
    let summary: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.drip.coral)

                Text("AI ANALYSIS")
                    .font(.dripCaption(10))
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

// MARK: - Compact Data Sources Row

private struct DataSourcesRow: View {
    let sources: DataSources

    var body: some View {
        HStack(spacing: 0) {
            dataItem("figure.run", "\(sources.workoutCount)", "workouts")
            dataItem("mic.fill", "\(sources.voiceLogCount)", "voice logs")
            dataItem("flame.fill", "\(sources.hardEffortCount)", "hard efforts")
            dataItem("chart.bar.fill", sources.confidence, "confidence")
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func dataItem(_ icon: String, _ value: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(Color.drip.coral)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.drip.textPrimary)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.drip.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Empty State

private struct EmptyPredictionState: View {
    let onPredict: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.drip.coral.opacity(0.12))
                    .frame(width: 64, height: 64)

                Image(systemName: "trophy.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(Color.drip.coral)
            }

            VStack(spacing: 6) {
                Text("Predict Your Race Times")
                    .font(.dripLabel(16))
                    .foregroundStyle(Color.drip.textPrimary)

                Text("Analyzes your workouts, voice logs, and GPS data.")
                    .font(.dripBody(13))
                    .foregroundStyle(Color.drip.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: onPredict) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14))
                    Text("Get Predictions")
                        .font(.dripLabel(15))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.drip.coral)
                .clipShape(Capsule())
            }
        }
        .padding(24)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Prediction Error Banner

private struct PredictionErrorBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.drip.tired)

            Text(message)
                .font(.dripBody(13))
                .foregroundStyle(Color.drip.textPrimary)

            Spacer()
        }
        .padding(14)
        .background(Color.drip.tired.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.drip.tired.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Fitness Trend Card

private struct FitnessTrendCard: View {
    let snapshots: [FitnessSnapshot]
    let changeFromPrevious: Int?
    let previousDate: Date?
    @State private var showAllDistances = false

    private var chronological: [FitnessSnapshot] {
        snapshots.reversed()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.drip.coral)

                    Text("FITNESS TREND")
                        .font(.dripCaption(10))
                        .foregroundStyle(Color.drip.textSecondary)
                        .tracking(1.2)
                }

                Spacer()

                if let change = changeFromPrevious, let date = previousDate {
                    ChangeIndicator(changeSeconds: change, comparedTo: date)
                }
            }

            TrendSparkline(
                snapshots: chronological,
                keyPath: \.predicted10kSeconds,
                label: "10K",
                height: 72
            )

            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showAllDistances.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Text(showAllDistances ? "Hide distances" : "All distances")
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.textTertiary)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.drip.textTertiary)
                        .rotationEffect(.degrees(showAllDistances ? 180 : 0))
                }
            }

            if showAllDistances {
                VStack(spacing: 10) {
                    TrendSparkline(snapshots: chronological, keyPath: \.predictedMileSeconds, label: "MILE", height: 44)
                    TrendSparkline(snapshots: chronological, keyPath: \.predicted5kSeconds, label: "5K", height: 44)
                    TrendSparkline(snapshots: chronological, keyPath: \.predictedHalfSeconds, label: "HALF", height: 44)
                    TrendSparkline(snapshots: chronological, keyPath: \.predictedMarathonSeconds, label: "MARATHON", height: 44)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Change Indicator

private struct ChangeIndicator: View {
    let changeSeconds: Int
    let comparedTo: Date

    private var isImproving: Bool { changeSeconds < 0 }
    private var absChange: Int { abs(changeSeconds) }

    private var changeText: String {
        let mins = absChange / 60
        let secs = absChange % 60
        if mins > 0 {
            return "\(isImproving ? "\u{2193}" : "\u{2191}") \(mins)m \(secs)s"
        }
        return "\(isImproving ? "\u{2193}" : "\u{2191}") \(secs)s"
    }

    private var relativeDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: comparedTo, relativeTo: Date())
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(changeText)
                .font(.dripCaption(11))
                .fontWeight(.semibold)

            Text("from \(relativeDate)")
                .font(.dripCaption(9))
                .foregroundStyle(isImproving ? Color.drip.success.opacity(0.7) : Color.drip.tired.opacity(0.7))
        }
        .foregroundStyle(isImproving ? Color.drip.success : Color.drip.tired)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            (isImproving ? Color.drip.success : Color.drip.tired).opacity(0.12)
        )
        .clipShape(Capsule())
    }
}

// MARK: - Trend Sparkline

private struct TrendSparkline: View {
    let snapshots: [FitnessSnapshot]
    let keyPath: KeyPath<FitnessSnapshot, Int>
    let label: String
    var height: CGFloat = 80

    private var latestValue: Int {
        snapshots.last.map { $0[keyPath: keyPath] } ?? 0
    }

    private var formattedTime: String {
        let totalSecs = latestValue
        let hours = totalSecs / 3600
        let mins = (totalSecs % 3600) / 60
        let secs = totalSecs % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, mins, secs)
        }
        return String(format: "%d:%02d", mins, secs)
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.dripCaption(10))
                    .foregroundStyle(Color.drip.textTertiary)
                    .tracking(1)

                Text(formattedTime)
                    .font(.system(size: height > 60 ? 16 : 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.drip.textPrimary)
            }
            .frame(width: 70, alignment: .leading)

            GeometryReader { geo in
                let values = snapshots.map { Double($0[keyPath: keyPath]) }
                let minVal = (values.min() ?? 0) * 0.995
                let maxVal = (values.max() ?? 1) * 1.005
                let range = max(maxVal - minVal, 1)

                ZStack {
                    Path { path in
                        guard values.count >= 2 else { return }
                        let stepX = geo.size.width / CGFloat(values.count - 1)

                        path.move(to: CGPoint(x: 0, y: geo.size.height))
                        for (i, val) in values.enumerated() {
                            let y = (val - minVal) / range * Double(geo.size.height)
                            path.addLine(to: CGPoint(x: CGFloat(i) * stepX, y: y))
                        }
                        path.addLine(to: CGPoint(x: CGFloat(values.count - 1) * stepX, y: geo.size.height))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [Color.drip.coral.opacity(0.25), Color.drip.coral.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    Path { path in
                        guard values.count >= 2 else { return }
                        let stepX = geo.size.width / CGFloat(values.count - 1)

                        for (i, val) in values.enumerated() {
                            let y = (val - minVal) / range * Double(geo.size.height)
                            if i == 0 {
                                path.move(to: CGPoint(x: 0, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: CGFloat(i) * stepX, y: y))
                            }
                        }
                    }
                    .stroke(Color.drip.coral, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                    if let lastVal = values.last {
                        let x = geo.size.width
                        let y = (lastVal - minVal) / range * Double(geo.size.height)
                        Circle()
                            .fill(Color.drip.coral)
                            .frame(width: 6, height: 6)
                            .position(x: x, y: y)
                    }
                }
            }
            .frame(height: height)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        FitnessPredictorView(trainingViewModel: TrainingPlanViewModel())
    }
}
