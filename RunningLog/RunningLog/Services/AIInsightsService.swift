//
//  AIInsightsService.swift
//  RunningLog
//
//  Fetches and manages AI-generated insights from the ai_insights table.
//  Handles post-run analysis, injury early warning, and race readiness.
//

import Foundation
import os
import Supabase

// MARK: - Models

struct AIInsight: Identifiable, Codable {
    let id: UUID
    let userId: String
    let insightType: String
    let triggerSource: String?
    let status: String
    let title: String?
    let summary: String?
    let fullAnalysis: String?
    let referenceId: String?
    let priority: String?
    let expiresAt: Date?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case insightType = "insight_type"
        case triggerSource = "trigger_source"
        case status
        case title
        case summary
        case fullAnalysis = "full_analysis"
        case referenceId = "reference_id"
        case priority
        case expiresAt = "expires_at"
        case createdAt = "created_at"
    }

    var isPostRun: Bool { insightType == "post_run_analysis" }
    var isInjuryWarning: Bool { insightType == "injury_early_warning" }
    var isRaceReadiness: Bool { insightType == "race_readiness" }
    var isUnread: Bool { status == "unread" }

    var icon: String {
        switch insightType {
        case "post_run_analysis": return "figure.run"
        case "injury_early_warning": return "exclamationmark.triangle.fill"
        case "race_readiness": return "flag.checkered"
        default: return "sparkles"
        }
    }

    var accentColor: String {
        switch priority {
        case "high": return "struggling"
        case "medium": return "tired"
        default: return "positive"
        }
    }
}

// MARK: - Service

@Observable
final class AIInsightsService {
    var insights: [AIInsight] = []
    var isLoading = false
    var errorMessage: String?

    @MainActor
    func fetchRecent(limit: Int = 10) async {
        isLoading = true
        errorMessage = nil

        do {
            let userId = AuthManager.shared.userId
            let result: [AIInsight] = try await supabase
                .from("ai_insights")
                .select()
                .eq("user_id", value: userId)
                .order("created_at", ascending: false)
                .limit(limit)
                .execute()
                .value

            insights = result
        } catch {
            Log.coach.error("Failed to fetch AI insights: \(error)")
            errorMessage = "Could not load insights."
        }

        isLoading = false
    }

    @MainActor
    func markRead(_ insight: AIInsight) async {
        do {
            try await supabase
                .from("ai_insights")
                .update(["status": "read"])
                .eq("id", value: insight.id.uuidString)
                .execute()

            if insights.contains(where: { $0.id == insight.id }) {
                // Can't mutate the struct directly, refetch
                await fetchRecent()
            }
        } catch {
            Log.coach.error("Failed to mark insight read: \(error)")
        }
    }

    // MARK: - Trigger Functions

    @MainActor
    func triggerInjuryWarning() async -> Bool {
        do {
            let userId = AuthManager.shared.userId
            _ = try await callEdgeFunction(
                name: "injury-early-warning",
                body: ["user_id": userId]
            )
            await fetchRecent()
            return true
        } catch {
            Log.coach.error("Injury early warning failed: \(error)")
            errorMessage = "Could not run injury check."
            return false
        }
    }

    @MainActor
    func triggerRaceReadiness(raceDistance: String? = nil, raceDate: String? = nil) async -> Bool {
        do {
            let userId = AuthManager.shared.userId
            var body: [String: Any] = ["user_id": userId]
            if let dist = raceDistance { body["race_distance"] = dist }
            if let date = raceDate { body["race_date"] = date }

            _ = try await callEdgeFunction(
                name: "race-readiness",
                body: body
            )
            await fetchRecent()
            return true
        } catch {
            Log.coach.error("Race readiness check failed: \(error)")
            errorMessage = "Could not run race readiness check."
            return false
        }
    }

    @MainActor
    func triggerBlockReview(weeks: Int = 4) async -> Bool {
        do {
            let userId = AuthManager.shared.userId
            _ = try await callEdgeFunction(
                name: "block-review",
                body: ["user_id": userId, "weeks": weeks]
            )
            await fetchRecent()
            return true
        } catch {
            Log.coach.error("Block review failed: \(error)")
            errorMessage = "Could not generate block review."
            return false
        }
    }

    /// Writes to plan_adjustments — surface via PlanAdjustmentsView, not the AI insights feed.
    @MainActor
    func triggerAdaptiveWorkout() async -> Bool {
        do {
            let userId = AuthManager.shared.userId
            _ = try await callEdgeFunction(
                name: "adapt-plan",
                body: ["user_id": userId, "trigger": "manual"]
            )
            return true
        } catch {
            Log.coach.error("adapt-plan invoke failed: \(error)")
            errorMessage = "Could not run plan review."
            return false
        }
    }

    @MainActor
    func triggerInjuryAnalysis(injuryId: UUID) async -> Data? {
        do {
            let data = try await callEdgeFunction(
                name: "injury-analysis",
                body: ["injuryId": injuryId.uuidString]
            )
            return data
        } catch {
            Log.coach.error("Injury analysis failed: \(error)")
            errorMessage = "Could not analyze injury."
            return nil
        }
    }
}
