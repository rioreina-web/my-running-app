//
//  AnalysisView.swift
//  RunningLog
//
//  Training analysis with monthly and yearly period views.
//

import os
import Supabase
import SwiftUI

// MARK: - AnalysisStats

struct AnalysisStats: Codable {
    let totalRuns: Int
    let totalMiles: Double
    let totalMinutes: Int
    let averagePace: String
    let averageDistance: Double
    let longestRun: Double
    let shortestRun: Double
    let runsByWeek: [WeeklyData]
    let moodDistribution: [String: Int]
    let daysWithRuns: Int
    let restDays: Int

    enum CodingKeys: String, CodingKey {
        case totalRuns
        case totalMiles
        case totalMinutes
        case averagePace
        case averageDistance
        case longestRun
        case shortestRun
        case runsByWeek
        case moodDistribution
        case daysWithRuns
        case restDays
    }
}

// MARK: - WeeklyData

struct WeeklyData: Codable {
    let week: Int
    let runs: Int
    let miles: Double
    let isComplete: Bool?
}

// MARK: - DateRange

struct DateRange: Codable {
    let start: String
    let end: String
}

// MARK: - PeriodProgress

struct PeriodProgress: Codable {
    let isComplete: Bool
    let percentComplete: Int
    let elapsedDays: Int
    let totalDays: Int
    let remainingDays: Int
    let currentWeek: Int
    let totalWeeks: Int
}

// MARK: - ProjectedStats

struct ProjectedStats: Codable {
    let projectedMiles: Double
    let projectedRuns: Int
    let milesPerDay: Double
    let runsPerWeek: Double
    let projectedWeeklyAverage: Double
}

// MARK: - QualitativeData

struct QualitativeData: Codable {
    let moodTrend: String
    let notableWorkouts: [String]
    let totalNotesRecorded: Int
}

// MARK: - PreviousPeriod

struct PreviousPeriod: Codable {
    let totalMiles: Double
    let totalRuns: Int
    let milesDiff: Double
}

// MARK: - AnalysisResponse

struct AnalysisResponse: Codable {
    let period: String
    let periodType: String
    let year: Int
    let month: Int?
    let dateRange: DateRange?
    let progress: PeriodProgress?
    let stats: AnalysisStats
    let projections: ProjectedStats?
    let qualitative: QualitativeData?
    let previousPeriod: PreviousPeriod?
    let analysis: String
    let processingTime: Int
}

// MARK: - AnalysisViewModel

@Observable
class AnalysisViewModel {
    var selectedPeriodType: PeriodType = .month
    var selectedYear: Int = Calendar.current.component(.year, from: Date())
    var selectedMonth: Int = Calendar.current.component(.month, from: Date())
    var selectedWeek: Int = Calendar.current.component(.weekOfYear, from: Date())

    var isLoading = false
    var analysisResponse: AnalysisResponse?
    var errorMessage: String?

    enum PeriodType: String, CaseIterable {
        case week = "Week"
        case month = "Month"
        case year = "Year"
    }

    var periodLabel: String {
        switch selectedPeriodType {
        case .week:
            if let weekDates = getWeekDates(week: selectedWeek, year: selectedYear) {
                let formatter = DateFormatter()
                formatter.dateFormat = "MMM d"
                let startStr = formatter.string(from: weekDates.start)
                let endStr = formatter.string(from: weekDates.end)
                return "Week: \(startStr) - \(endStr)"
            }
            return "Week \(selectedYear)"
        case .month:
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MMMM yyyy"
            let date = Calendar.current.date(from: DateComponents(year: selectedYear, month: selectedMonth)) ?? Date()
            return dateFormatter.string(from: date)
        case .year:
            return "\(selectedYear)"
        }
    }

    var availableYears: [Int] {
        let currentYear = Calendar.current.component(.year, from: Date())
        return Array((currentYear - 10) ... currentYear).reversed()
    }

    var availableMonths: [(Int, String)] {
        let dateFormatter = DateFormatter()
        return (1 ... 12).map { month in
            dateFormatter.dateFormat = "MMM" // Abbreviated: Jan, Feb, Mar, etc.
            let date = Calendar.current.date(from: DateComponents(year: 2024, month: month)) ?? Date()
            return (month, dateFormatter.string(from: date))
        }
    }

    var availableWeeks: [Int] {
        // Get the number of weeks in the selected year
        let calendar = Calendar.current
        guard let lastDay = calendar.date(from: DateComponents(year: selectedYear, month: 12, day: 31)) else {
            return Array(1 ... 52)
        }
        let weeksInYear = calendar.component(.weekOfYear, from: lastDay)
        // Handle edge case where Dec 31 might be week 1 of next year
        let maxWeek = weeksInYear == 1 ? 52 : weeksInYear
        return Array(1 ... maxWeek)
    }

    /// Get the start (Monday) and end (Sunday) dates for a given week number and year
    func getWeekDates(week: Int, year: Int) -> (start: Date, end: Date)? {
        var calendar = Calendar.current
        calendar.firstWeekday = 2 // Monday
        calendar.minimumDaysInFirstWeek = 4 // ISO week numbering

        var components = DateComponents()
        components.weekOfYear = week
        components.yearForWeekOfYear = year
        components.weekday = 2 // Monday

        guard let monday = calendar.date(from: components) else { return nil }
        guard let sunday = calendar.date(byAdding: .day, value: 6, to: monday) else { return nil }

        return (monday, sunday)
    }

    func fetchAnalysis() async {
        isLoading = true
        errorMessage = nil

        do {
            var requestBody: [String: Any]

            if selectedPeriodType == .week {
                // Use custom period type with week dates
                if let weekDates = getWeekDates(week: selectedWeek, year: selectedYear) {
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withFullDate]
                    requestBody = [
                        "periodType": "custom",
                        "year": selectedYear,
                        "startDate": formatter.string(from: weekDates.start),
                        "endDate": formatter.string(from: weekDates.end)
                    ]
                } else {
                    throw NSError(domain: "AnalysisError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid week selection"])
                }
            } else {
                requestBody = [
                    "periodType": selectedPeriodType.rawValue.lowercased(),
                    "year": selectedYear,
                    "month": selectedMonth
                ]
            }

            let jsonData = try JSONSerialization.data(withJSONObject: requestBody)

            let response: AnalysisResponse = try await supabase.functions.invoke(
                "training-analysis",
                options: FunctionInvokeOptions(body: jsonData)
            )

            await MainActor.run {
                self.analysisResponse = response
                self.isLoading = false
            }
        } catch {
            Log.app.error("Analysis fetch error: \(error)")
            await MainActor.run {
                self.errorMessage = "Failed to generate analysis. Please try again."
                self.isLoading = false
            }
        }
    }
}

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
                .padding(.horizontal, 20)
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
        VStack(spacing: 8) {
            Text("TRAINING ANALYSIS")
                .font(.dripCaption(11))
                .foregroundStyle(Color.drip.textSecondary)
                .tracking(1.5)

            Text(viewModel.periodLabel)
                .font(.dripDisplay(32))
                .foregroundStyle(Color.drip.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.top, 8)
    }

    // MARK: - Period Selector

    private var periodSelector: some View {
        HStack(spacing: 6) {
            // Period type toggle
            HStack(spacing: 0) {
                ForEach(AnalysisViewModel.PeriodType.allCases, id: \.self) { type in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.selectedPeriodType = type
                        }
                    } label: {
                        Text(type.rawValue)
                            .font(.dripLabel(11))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .foregroundStyle(viewModel.selectedPeriodType == type ? Color.drip.textPrimary : Color.drip.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(viewModel.selectedPeriodType == type ? Color.drip.cardBackgroundElevated : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(3)
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Spacer(minLength: 4)

            // Period picker button
            Button {
                showPeriodPicker = true
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "calendar")
                        .font(.system(size: 10))
                    Text("Select")
                        .font(.dripLabel(10))
                }
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(Color.drip.coral)
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .background(Color.drip.coral.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // Generate button
            Button {
                Task {
                    await viewModel.fetchAnalysis()
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10))
                    Text("Analyze")
                        .font(.dripLabel(10))
                }
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .background(Color.drip.coral)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .disabled(viewModel.isLoading)
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(Color.drip.coral)

            Text("Analyzing your training...")
                .font(.dripBody(14))
                .foregroundStyle(Color.drip.textSecondary)

            Text("This may take a moment for larger periods")
                .font(.dripCaption(12))
                .foregroundStyle(Color.drip.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Error View

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(Color.drip.tired)

            Text(message)
                .font(.dripBody(14))
                .foregroundStyle(Color.drip.textSecondary)
                .multilineTextAlignment(.center)

            DripButton("Try Again", icon: "arrow.clockwise", style: .secondary) {
                Task {
                    await viewModel.fetchAnalysis()
                }
            }
            .frame(width: 160)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 48))
                .foregroundStyle(Color.drip.textTertiary)

            Text("Select a period and tap Analyze")
                .font(.dripBody(15))
                .foregroundStyle(Color.drip.textSecondary)

            Text("Get AI-powered insights on your training patterns, volume trends, and recommendations.")
                .font(.dripCaption(12))
                .foregroundStyle(Color.drip.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Analysis Content

    private func analysisContent(response: AnalysisResponse) -> some View {
        VStack(spacing: 24) {
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
            Text("Generated in \(response.processingTime)ms")
                .font(.dripCaption(10))
                .foregroundStyle(Color.drip.textTertiary)
                .padding(.top, 8)
        }
    }

    // MARK: - Stats Grid

    private func statsGridSection(stats: AnalysisStats) -> some View {
        VStack(spacing: 12) {
            SectionHeader("Overview")

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                StatCard(value: String(format: "%.1f", stats.totalMiles), label: "Total Miles", icon: "figure.run", accentColor: Color.drip.coral)
                StatCard(value: "\(stats.totalRuns)", label: "Total Runs", icon: "flame.fill", accentColor: Color.drip.energized)
                StatCard(value: stats.averagePace, label: "Avg Pace", icon: "speedometer", accentColor: Color.drip.coralLight)
                StatCard(value: String(format: "%.1f", stats.averageDistance), label: "Avg Distance", icon: "ruler", accentColor: Color.drip.positive)
            }

            HStack(spacing: 12) {
                miniStat(value: String(format: "%.1f mi", stats.longestRun), label: "Longest")
                miniStat(value: "\(stats.daysWithRuns) days", label: "Run Days")
                miniStat(value: "\(stats.restDays) days", label: "Rest Days")
            }
        }
    }

    private func miniStat(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.dripStat(16))
                .foregroundStyle(Color.drip.textPrimary)
            Text(label)
                .font(.dripCaption(10))
                .foregroundStyle(Color.drip.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Comparison Section

    private func comparisonSection(current: AnalysisStats, previous: PreviousPeriod) -> some View {
        VStack(spacing: 12) {
            SectionHeader("vs Previous Period")

            HStack(spacing: 16) {
                comparisonItem(
                    current: String(format: "%.1f", current.totalMiles),
                    diff: previous.milesDiff,
                    label: "Miles",
                    unit: "mi"
                )

                comparisonItem(
                    current: "\(current.totalRuns)",
                    diff: Double(current.totalRuns - previous.totalRuns),
                    label: "Runs",
                    unit: ""
                )
            }
        }
    }

    private func comparisonItem(current: String, diff: Double, label: String, unit: String) -> some View {
        VStack(spacing: 8) {
            Text(current)
                .font(.dripStat(24))
                .foregroundStyle(Color.drip.textPrimary)

            HStack(spacing: 4) {
                Image(systemName: diff >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 11, weight: .bold))
                Text(String(format: "%+.1f%@", diff, unit))
                    .font(.dripCaption(11))
            }
            .foregroundStyle(diff >= 0 ? Color.drip.energized : Color.drip.tired)

            Text(label)
                .font(.dripCaption(10))
                .foregroundStyle(Color.drip.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Weekly Breakdown

    private func weeklyBreakdownSection(weeks: [WeeklyData]) -> some View {
        VStack(spacing: 12) {
            SectionHeader("Weekly Breakdown")

            VStack(spacing: 8) {
                ForEach(weeks, id: \.week) { week in
                    HStack {
                        Text("Week \(week.week)")
                            .font(.dripCaption(12))
                            .foregroundStyle(Color.drip.textSecondary)
                            .frame(width: 60, alignment: .leading)

                        // Bar chart with distance text
                        GeometryReader { geo in
                            let maxMiles = weeks.map(\.miles).max() ?? 1
                            let textWidth: CGFloat = 55 // Reserve space for distance text
                            let availableWidth = geo.size.width - textWidth - 8 // 8 for spacing
                            let barWidth = (week.miles / maxMiles) * availableWidth

                            HStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.drip.coral)
                                    .frame(width: max(barWidth, 4), height: 24)

                                Spacer(minLength: 0)

                                Text(String(format: "%.1f mi", week.miles))
                                    .font(.dripCaption(11))
                                    .foregroundStyle(Color.drip.textPrimary)
                                    .frame(width: textWidth, alignment: .trailing)
                            }
                        }
                        .frame(height: 24)

                        Text("\(week.runs) runs")
                            .font(.dripCaption(11))
                            .foregroundStyle(Color.drip.textTertiary)
                            .frame(width: 50, alignment: .trailing)
                    }
                }
            }
            .padding(16)
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: - AI Analysis

    private func aiAnalysisSection(analysis: String) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.drip.coral)
                Text("AI ANALYSIS")
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textSecondary)
                    .tracking(1.2)
                Spacer()
            }

            Text(analysis)
                .font(.dripBody(14))
                .foregroundStyle(Color.drip.textPrimary)
                .lineSpacing(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background(Color.drip.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.drip.coral.opacity(0.3), lineWidth: 1)
                )
        }
    }

    // MARK: - Period Progress Section

    private func periodProgressSection(progress: PeriodProgress, projections: ProjectedStats?) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "clock.badge.checkmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.drip.energized)
                Text("PERIOD IN PROGRESS")
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textSecondary)
                    .tracking(1.2)
                Spacer()

                Text("\(progress.percentComplete)%")
                    .font(.dripLabel(14))
                    .foregroundStyle(Color.drip.energized)
            }

            VStack(spacing: 12) {
                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.drip.cardBackgroundElevated)
                            .frame(height: 8)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.drip.energized)
                            .frame(width: geo.size.width * CGFloat(progress.percentComplete) / 100, height: 8)
                    }
                }
                .frame(height: 8)

                // Progress stats
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(progress.elapsedDays) days elapsed")
                            .font(.dripCaption(12))
                            .foregroundStyle(Color.drip.textPrimary)
                        Text("\(progress.remainingDays) days remaining")
                            .font(.dripCaption(11))
                            .foregroundStyle(Color.drip.textSecondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Week \(progress.currentWeek) of \(progress.totalWeeks)")
                            .font(.dripCaption(12))
                            .foregroundStyle(Color.drip.textPrimary)
                        Text("\(progress.totalDays) days total")
                            .font(.dripCaption(11))
                            .foregroundStyle(Color.drip.textSecondary)
                    }
                }
            }
            .padding(16)
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Projections Section

    private func projectionsSection(projections: ProjectedStats, currentMiles: Double, currentRuns: Int) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.drip.coralLight)
                Text("PROJECTIONS")
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textSecondary)
                    .tracking(1.2)
                Spacer()

                Text("at current pace")
                    .font(.dripCaption(10))
                    .foregroundStyle(Color.drip.textTertiary)
            }

            VStack(spacing: 16) {
                // Main projection cards
                HStack(spacing: 12) {
                    projectionCard(
                        current: String(format: "%.1f", currentMiles),
                        projected: String(format: "%.0f", projections.projectedMiles),
                        label: "Miles",
                        icon: "figure.run"
                    )

                    projectionCard(
                        current: "\(currentRuns)",
                        projected: "\(projections.projectedRuns)",
                        label: "Runs",
                        icon: "flame.fill"
                    )
                }

                // Pace indicators
                HStack(spacing: 12) {
                    miniProjectionStat(
                        value: String(format: "%.1f", projections.milesPerDay),
                        label: "mi/day"
                    )
                    miniProjectionStat(
                        value: String(format: "%.1f", projections.runsPerWeek),
                        label: "runs/week"
                    )
                    miniProjectionStat(
                        value: String(format: "%.1f", projections.projectedWeeklyAverage),
                        label: "mi/week avg"
                    )
                }
            }
            .padding(16)
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func projectionCard(current: String, projected: String, label: String, icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Color.drip.coralLight)

            VStack(spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(current)
                        .font(.dripStat(20))
                        .foregroundStyle(Color.drip.textPrimary)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.drip.textTertiary)
                    Text("~\(projected)")
                        .font(.dripStat(20))
                        .foregroundStyle(Color.drip.coralLight)
                }

                Text(label)
                    .font(.dripCaption(10))
                    .foregroundStyle(Color.drip.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.drip.cardBackgroundElevated)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func miniProjectionStat(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.dripLabel(14))
                .foregroundStyle(Color.drip.textPrimary)
            Text(label)
                .font(.dripCaption(9))
                .foregroundStyle(Color.drip.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - PeriodPickerSheet

struct PeriodPickerSheet: View {
    @Bindable var viewModel: AnalysisViewModel
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Color.drip.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Year Picker
                        VStack(alignment: .leading, spacing: 12) {
                            Text("YEAR")
                                .font(.dripCaption(11))
                                .foregroundStyle(Color.drip.textSecondary)
                                .tracking(1.2)

                            Picker("Year", selection: $viewModel.selectedYear) {
                                ForEach(viewModel.availableYears, id: \.self) { year in
                                    Text(String(year))
                                        .foregroundStyle(Color.white)
                                        .tag(year)
                                }
                            }
                            .pickerStyle(.wheel)
                            .frame(height: 120)
                            .background(Color.drip.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .tint(Color.drip.coral)
                        }

                        // Week Picker (only for week period type)
                        if viewModel.selectedPeriodType == .week {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("WEEK")
                                    .font(.dripCaption(11))
                                    .foregroundStyle(Color.drip.textSecondary)
                                    .tracking(1.2)

                                Picker("Week", selection: $viewModel.selectedWeek) {
                                    ForEach(viewModel.availableWeeks, id: \.self) { week in
                                        weekLabel(week: week)
                                            .tag(week)
                                    }
                                }
                                .pickerStyle(.wheel)
                                .frame(height: 120)
                                .background(Color.drip.cardBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .tint(Color.drip.coral)
                            }
                        }

                        // Month Picker (only for month period type)
                        if viewModel.selectedPeriodType == .month {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("MONTH")
                                    .font(.dripCaption(11))
                                    .foregroundStyle(Color.drip.textSecondary)
                                    .tracking(1.2)

                                Picker("Month", selection: $viewModel.selectedMonth) {
                                    ForEach(viewModel.availableMonths, id: \.0) { month, name in
                                        Text(name)
                                            .foregroundStyle(Color.white)
                                            .tag(month)
                                    }
                                }
                                .pickerStyle(.wheel)
                                .frame(height: 120)
                                .background(Color.drip.cardBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .tint(Color.drip.coral)
                            }
                        }

                        Spacer()
                            .frame(height: 20)

                        DripButton("Done", style: .primary) {
                            isPresented = false
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Select Period")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .foregroundStyle(Color.drip.coral)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }

    private func weekLabel(week: Int) -> some View {
        if let dates = viewModel.getWeekDates(week: week, year: viewModel.selectedYear) {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            let startStr = formatter.string(from: dates.start)
            let endStr = formatter.string(from: dates.end)
            return Text("\(startStr) - \(endStr)")
                .foregroundStyle(Color.white)
        } else {
            return Text("Week \(week)")
                .foregroundStyle(Color.white)
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        AnalysisView()
    }
}
