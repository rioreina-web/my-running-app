//
//  AnalysisView.swift
//  RunningLog
//
//  Training analysis with monthly and yearly period views.
//

import SwiftUI

// MARK: - AnalysisView

struct AnalysisView: View {
    @State private var viewModel = AnalysisViewModel()
    @State private var showPeriodPicker = false

    var body: some View {
        ZStack {
            Color.drip.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    headerSection

                    // Period Selector
                    periodSelector

                    // Content
                    if viewModel.isLoading {
                        loadingView
                    } else if let error = viewModel.errorMessage {
                        errorView(message: error)
                    } else if let response = viewModel.analysisResponse {
                        analysisContent(response: response)
                    } else {
                        emptyStateView
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 100)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Image("drip-logo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 28)
            }
        }
        .sheet(isPresented: $showPeriodPicker) {
            PeriodPickerSheet(viewModel: viewModel, isPresented: $showPeriodPicker)
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 12) {
            Text(viewModel.periodLabel)
                .font(.dripDisplay(34))
                .foregroundStyle(Color.drip.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            // Thin rule below masthead
            Rectangle()
                .fill(Color.drip.divider)
                .frame(height: 0.5)
        }
        .padding(.top, 8)
    }

    // MARK: - Period Selector

    private var periodSelector: some View {
        HStack(alignment: .center, spacing: 0) {
            // Period type tabs — editorial underline style
            HStack(spacing: 20) {
                ForEach(AnalysisViewModel.PeriodType.allCases, id: \.self) { type in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.selectedPeriodType = type
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Text(type.rawValue)
                                .font(.dripCaption(12))
                                .tracking(0.5)
                                .foregroundStyle(viewModel.selectedPeriodType == type ? Color.drip.textPrimary : Color.drip.textTertiary)

                            Rectangle()
                                .fill(viewModel.selectedPeriodType == type ? Color.drip.coral : Color.clear)
                                .frame(height: 1.5)
                        }
                    }
                }
            }

            Spacer()

            // Period picker — understated text link
            Button {
                showPeriodPicker = true
            } label: {
                Text("change")
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.coral)
                    .italic()
            }

            // Analyze — understated
            Button {
                Task {
                    await viewModel.fetchAnalysis()
                }
            } label: {
                Text("analyze")
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.coral)
                    .underline()
                    .padding(.leading, 12)
            }
            .disabled(viewModel.isLoading)
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(1.0)
                .tint(Color.drip.coral)

            Text("Reading the miles...")
                .font(.dripBody(15))
                .foregroundStyle(Color.drip.textSecondary)
                .italic()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }

    // MARK: - Error View

    private func errorView(message: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            AnalysisDivider()

            Text(message)
                .font(.dripBody(14))
                .foregroundStyle(Color.drip.textSecondary)

            Button {
                Task { await viewModel.fetchAnalysis() }
            } label: {
                Text("try again")
                    .font(.dripCaption(12))
                    .foregroundStyle(Color.drip.coral)
                    .underline()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 40)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 4) {
            Text("Pick a window of time,")
                .font(.dripBody(16))
                .foregroundStyle(Color.drip.textSecondary)

            HStack(spacing: 4) {
                Text("then tap")
                    .font(.dripBody(16))
                    .foregroundStyle(Color.drip.textSecondary)
                Text("analyze")
                    .font(.dripBody(16))
                    .foregroundStyle(Color.drip.coral)
                    .italic()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }

    // MARK: - Analysis Content

    private func analysisContent(response: AnalysisResponse) -> some View {
        VStack(spacing: 20) {
            // Progress indicator for incomplete periods
            if let progress = response.progress, !progress.isComplete {
                periodProgressSection(progress: progress, projections: response.projections)
            }

            // Stats Grid
            statsGridSection(stats: response.stats)

            // Projections for incomplete periods
            if let progress = response.progress, !progress.isComplete, let projections = response.projections {
                projectionsSection(projections: projections, currentMiles: response.stats.totalMiles, currentRuns: response.stats.totalRuns)
            }

            // Comparison (if available)
            if let previous = response.previousPeriod {
                comparisonSection(current: response.stats, previous: previous)
            }

            // Weekly Breakdown
            if !response.stats.runsByWeek.isEmpty {
                weeklyBreakdownSection(weeks: response.stats.runsByWeek)
            }

            // AI Analysis
            aiAnalysisSection(analysis: response.analysis)

            // Processing time
            AnalysisDivider()

            Text("generated in \(response.processingTime)ms")
                .font(.dripCaption(10))
                .foregroundStyle(Color.drip.textTertiary)
                .italic()
        }
    }

    // MARK: - Stats Narrative

    private func statsGridSection(stats: AnalysisStats) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // Narrative lede — prose with inline serif numbers
            narrativeLede(stats: stats)

            // Supporting detail
            Text("The longest effort covered \(formatMiles(stats.longestRun)) miles. You ran on \(stats.daysWithRuns) days and rested \(stats.restDays).")
                .font(.dripBody(14))
                .foregroundStyle(Color.drip.textSecondary)
                .lineSpacing(5)
        }
    }

    @ViewBuilder
    private func narrativeLede(stats: AnalysisStats) -> some View {
        let miles = formatMiles(stats.totalMiles)
        let avg = formatMiles(stats.averageDistance)

        // Magazine lede — built with AttributedString for mixed weights
        let lede = buildLede(miles: miles, runs: stats.totalRuns, avg: avg, pace: stats.averagePace)

        Text(lede)
            .lineSpacing(8)
    }

    private func buildLede(miles: String, runs: Int, avg: String, pace: String) -> AttributedString {
        var result = AttributedString()

        var milesAttr = AttributedString(miles)
        milesAttr.font = .dripDisplay(40)
        milesAttr.foregroundColor = Color.drip.textPrimary
        result.append(milesAttr)

        var across = AttributedString(" miles across ")
        across.font = .dripBody(16)
        across.foregroundColor = Color.drip.textSecondary
        result.append(across)

        var runsAttr = AttributedString("\(runs)")
        runsAttr.font = .dripDisplay(40)
        runsAttr.foregroundColor = Color.drip.textPrimary
        result.append(runsAttr)

        var runsLabel = AttributedString(" runs — averaging ")
        runsLabel.font = .dripBody(16)
        runsLabel.foregroundColor = Color.drip.textTertiary
        result.append(runsLabel)

        var avgAttr = AttributedString(avg)
        avgAttr.font = .dripDisplay(24)
        avgAttr.foregroundColor = Color.drip.coral
        result.append(avgAttr)

        var miAt = AttributedString(" mi at ")
        miAt.font = .dripBody(16)
        miAt.foregroundColor = Color.drip.textTertiary
        result.append(miAt)

        var paceAttr = AttributedString(pace)
        paceAttr.font = .dripDisplay(24)
        paceAttr.foregroundColor = Color.drip.coral
        result.append(paceAttr)

        var perMi = AttributedString("/mi.")
        perMi.font = .dripBody(16)
        perMi.foregroundColor = Color.drip.textTertiary
        result.append(perMi)

        return result
    }

    /// Drop trailing zeros: 4.0 → "4", 4.2 → "4.2"
    private func formatMiles(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)
    }

    // MARK: - Comparison Section

    private func comparisonSection(current: AnalysisStats, previous: PreviousPeriod) -> some View {
        let milesDiff = previous.milesDiff
        let runsDiff = current.totalRuns - previous.totalRuns
        let milesDir = milesDiff >= 0 ? "up" : "down"
        let runsDir = runsDiff >= 0 ? "more" : "fewer"

        let comparison = buildComparison(milesDiff: milesDiff, runsDiff: runsDiff, milesDir: milesDir, runsDir: runsDir)

        return Text(comparison)
            .lineSpacing(5)
    }

    private func buildComparison(milesDiff: Double, runsDiff: Int, milesDir: String, runsDir: String) -> AttributedString {
        var result = AttributedString()

        var thats = AttributedString("That's ")
        thats.font = .dripBody(14)
        thats.foregroundColor = Color.drip.textSecondary
        result.append(thats)

        let milesColor = milesDiff >= 0 ? Color.drip.energized : Color.drip.tired
        var milesText = AttributedString(String(format: "%.1f mi %@", abs(milesDiff), milesDir))
        milesText.font = .dripBody(14)
        milesText.foregroundColor = milesColor
        result.append(milesText)

        var andText = AttributedString(" and ")
        andText.font = .dripBody(14)
        andText.foregroundColor = Color.drip.textSecondary
        result.append(andText)

        let runsColor = runsDiff >= 0 ? Color.drip.energized : Color.drip.tired
        var runsText = AttributedString("\(abs(runsDiff)) \(runsDir) runs")
        runsText.font = .dripBody(14)
        runsText.foregroundColor = runsColor
        result.append(runsText)

        var than = AttributedString(" than last period.")
        than.font = .dripBody(14)
        than.foregroundColor = Color.drip.textSecondary
        result.append(than)

        return result
    }

    // MARK: - Weekly Breakdown

    private func weeklyBreakdownSection(weeks: [WeeklyData]) -> some View {
        VStack(spacing: 0) {
            AnalysisDivider()
                .padding(.bottom, 16)

            // Table header row
            HStack {
                Text("")
                    .frame(width: 32, alignment: .leading)
                Spacer()
                Text("mi")
                    .frame(width: 44, alignment: .trailing)
                Text("runs")
                    .frame(width: 36, alignment: .trailing)
            }
            .font(.dripCaption(9))
            .foregroundStyle(Color.drip.textTertiary)
            .tracking(1)
            .textCase(.uppercase)

            Rectangle()
                .fill(Color.drip.divider)
                .frame(height: 0.5)
                .padding(.top, 6)

            // Table rows
            ForEach(Array(weeks.enumerated()), id: \.element.week) { index, week in
                let isHighest = week.miles == weeks.map(\.miles).max()

                HStack {
                    Text("\(week.week)")
                        .font(.dripStat(13))
                        .foregroundStyle(isHighest ? Color.drip.coral : Color.drip.textTertiary)
                        .frame(width: 32, alignment: .leading)

                    // Subtle inline bar — typographic accent
                    GeometryReader { geo in
                        let maxMiles = weeks.map(\.miles).max() ?? 1
                        let barWidth = (week.miles / maxMiles) * geo.size.width

                        Rectangle()
                            .fill(Color.drip.coral.opacity(isHighest ? 0.25 : 0.10))
                            .frame(width: barWidth, height: 1)
                            .frame(maxHeight: .infinity, alignment: .center)
                    }

                    Text(formatMiles(week.miles))
                        .font(.dripStat(13))
                        .foregroundStyle(isHighest ? Color.drip.textPrimary : Color.drip.textSecondary)
                        .frame(width: 44, alignment: .trailing)

                    Text("\(week.runs)")
                        .font(.dripStat(13))
                        .foregroundStyle(Color.drip.textTertiary)
                        .frame(width: 36, alignment: .trailing)
                }
                .padding(.vertical, 8)

                if index < weeks.count - 1 {
                    Rectangle()
                        .fill(Color.drip.divider.opacity(0.5))
                        .frame(height: 0.5)
                }
            }
        }
    }

    // MARK: - AI Analysis

    private func aiAnalysisSection(analysis: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            AnalysisDivider()

            // Subtle editorial label
            HStack(spacing: 6) {
                Rectangle()
                    .fill(Color.drip.coral)
                    .frame(width: 16, height: 1.5)
                Text("COACH'S NOTES")
                    .font(.dripCaption(10))
                    .foregroundStyle(Color.drip.textTertiary)
                    .tracking(2)
            }

            Text(analysis)
                .font(.dripBody(15))
                .foregroundStyle(Color.drip.textPrimary.opacity(0.85))
                .lineSpacing(7)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Period Progress Section

    private func periodProgressSection(progress: PeriodProgress, projections: ProjectedStats?) -> some View {
        VStack(spacing: 12) {
            // Progress bar — thin, understated
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.drip.divider)
                        .frame(height: 2)

                    Rectangle()
                        .fill(Color.drip.coral.opacity(0.7))
                        .frame(width: geo.size.width * CGFloat(progress.percentComplete) / 100, height: 2)
                }
            }
            .frame(height: 2)

            // Progress text — single flowing line
            Text("Day \(progress.elapsedDays) of \(progress.totalDays)  ·  \(progress.percentComplete)% through  ·  \(progress.remainingDays) days left")
                .font(.dripCaption(11))
                .foregroundStyle(Color.drip.textTertiary)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Projections Section

    private func projectionsSection(projections: ProjectedStats, currentMiles: Double, currentRuns: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AnalysisDivider()
                .padding(.bottom, 8)

            Text(buildProjection(projections: projections))
                .lineSpacing(6)
        }
    }
    private func buildProjection(projections: ProjectedStats) -> AttributedString {
        var result = AttributedString()

        var intro = AttributedString("At this pace you're on track for roughly ")
        intro.font = .dripBody(14)
        intro.foregroundColor = Color.drip.textSecondary
        result.append(intro)

        var miles = AttributedString("\(String(format: "%.0f", projections.projectedMiles)) miles")
        miles.font = .dripDisplay(20)
        miles.foregroundColor = Color.drip.coral
        result.append(miles)

        var over = AttributedString(" over ")
        over.font = .dripBody(14)
        over.foregroundColor = Color.drip.textSecondary
        result.append(over)

        var runs = AttributedString("\(projections.projectedRuns) runs")
        runs.font = .dripDisplay(20)
        runs.foregroundColor = Color.drip.coral
        result.append(runs)

        var about = AttributedString(" — about \(formatMiles(projections.projectedWeeklyAverage)) mi/week.")
        about.font = .dripBody(14)
        about.foregroundColor = Color.drip.textTertiary
        result.append(about)

        return result
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        AnalysisView()
    }
}
