//
//  AnalysisModels.swift
//  RunningLog
//
//  Data models and view model for the training analysis feature.
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
            // Build request body
            var body: [String: Any]
            if selectedPeriodType == .week {
                guard let weekDates = getWeekDates(week: selectedWeek, year: selectedYear) else {
                    await MainActor.run {
                        self.errorMessage = "Invalid week selection"
                        self.isLoading = false
                    }
                    return
                }
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withFullDate]
                body = [
                    "periodType": "custom",
                    "year": selectedYear,
                    "startDate": formatter.string(from: weekDates.start),
                    "endDate": formatter.string(from: weekDates.end),
                ]
            } else {
                body = [
                    "periodType": selectedPeriodType.rawValue.lowercased(),
                    "year": selectedYear,
                    "month": selectedMonth,
                ]
            }

            body["userId"] = AuthManager.shared.userId

            // Direct request with anon key — bypasses callEdgeFunction auth token issues
            guard let url = URL(string: "\(supabaseURL)/functions/v1/training-analysis") else {
                await MainActor.run {
                    self.errorMessage = "Invalid URL"
                    self.isLoading = false
                }
                return
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 120
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
            request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                let msg = String(data: data.prefix(300), encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
                await MainActor.run {
                    self.errorMessage = "Server error: \(msg)"
                    self.isLoading = false
                }
                return
            }

            let decoded = try JSONDecoder().decode(AnalysisResponse.self, from: data)
            await MainActor.run {
                self.analysisResponse = decoded
                self.isLoading = false
            }
        } catch {
            Log.app.error("Analysis fetch error: \(error)")
            await MainActor.run {
                self.errorMessage = "Failed to generate analysis: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }
}
