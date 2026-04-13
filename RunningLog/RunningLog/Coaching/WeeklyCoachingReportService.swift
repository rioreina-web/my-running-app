//
//  WeeklyCoachingReportService.swift
//  RunningLog
//
//  Service for fetching weekly coaching analysis reports.
//

import Foundation
import os

// MARK: - Weekly Coaching Report Models

struct WeeklyCoachingReport: Codable {
    let weekStart: String
    let weekEnd: String
    let coachingNarrative: String
    let alerts: [WeeklyAlert]
    let adjustments: [WeeklyAdjustment]
    let focusAreas: [String]
    let metrics: WeeklyMetrics?
    let planWeekNumber: Int?

    enum CodingKeys: String, CodingKey {
        case weekStart = "week_start"
        case weekEnd = "week_end"
        case coachingNarrative = "coaching_narrative"
        case alerts
        case adjustments
        case focusAreas = "focus_areas"
        case metrics
        case planWeekNumber = "plan_week_number"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        weekStart = try container.decode(String.self, forKey: .weekStart)
        weekEnd = try container.decode(String.self, forKey: .weekEnd)
        alerts = (try? container.decode([WeeklyAlert].self, forKey: .alerts)) ?? []
        adjustments = (try? container.decode([WeeklyAdjustment].self, forKey: .adjustments)) ?? []
        focusAreas = (try? container.decode([String].self, forKey: .focusAreas)) ?? []
        metrics = try? container.decode(WeeklyMetrics.self, forKey: .metrics)
        planWeekNumber = try? container.decode(Int.self, forKey: .planWeekNumber)

        // coaching_narrative can be a String or a JSON object {"narrative": "..."}
        if let str = try? container.decode(String.self, forKey: .coachingNarrative) {
            // If the string itself is JSON, try to extract the narrative field
            if str.hasPrefix("{"), let data = str.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let inner = obj["narrative"] as? String {
                coachingNarrative = inner
            } else {
                coachingNarrative = str
            }
        } else if let obj = try? container.decode([String: String].self, forKey: .coachingNarrative),
                  let inner = obj["narrative"] {
            coachingNarrative = inner
        } else {
            coachingNarrative = ""
        }
    }
}

struct WeeklyAlert: Codable, Identifiable {
    var id: String { title }
    let severity: String // green, yellow, orange, red
    let title: String
    let message: String
}

struct WeeklyAdjustment: Codable, Identifiable {
    var id: String { "\(targetWorkoutType)-\(action)-\(priority)" }
    let targetWorkoutType: String
    let targetDate: String?
    let action: String
    let originalValue: String?
    let recommendedValue: String?
    let rationale: String
    let priority: String // high, medium, low

    enum CodingKeys: String, CodingKey {
        case targetWorkoutType = "target_workout_type"
        case targetDate = "target_date"
        case action
        case originalValue = "original_value"
        case recommendedValue = "recommended_value"
        case rationale
        case priority
    }
}

struct WeeklyMetrics: Codable {
    let totalMiles: Double?
    let runCount: Int?
    let totalMinutes: Double?
    let avgPaceSeconds: Double?
    let acwr: Double?
    let complianceScore: Double?
    let moodScore: Double?
    let moodTrend: String?
    let longRunMiles: Double?
    let volumeChangePct: Double?
}

struct WeeklyReportResponse: Codable {
    let status: String
    let report: WeeklyCoachingReport?
    let processingTime: Int?
}

// MARK: - Service

@Observable
final class WeeklyCoachingReportService {
    var isLoading = false
    var error: String?

    @MainActor
    func fetchReport() async throws -> WeeklyCoachingReport? {
        isLoading = true
        error = nil
        defer { isLoading = false }

        let userId = AuthManager.shared.userId
        let body: [String: Any] = ["userId": userId]
        let data = try await callEdgeFunction(name: "weekly-coaching-report", body: body)

        // Check for error response
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let errorMsg = json["error"] as? String {
            self.error = errorMsg
            throw URLError(.badServerResponse)
        }

        let decoder = JSONDecoder()
        let response = try decoder.decode(WeeklyReportResponse.self, from: data)

        if response.status == "failed" {
            self.error = "Failed to generate report"
            return nil
        }

        return response.report
    }
}
