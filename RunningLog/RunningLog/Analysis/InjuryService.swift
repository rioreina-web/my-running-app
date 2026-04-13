import Foundation
import os
import Supabase

@Observable
final class InjuryService {
    var injuries: [Injury] = []
    var isLoading = false
    var isAnalyzing = false
    var errorMessage: String?

    // MARK: - Fetch All Injuries

    @MainActor
    func fetchInjuries() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        do {
            let response: [Injury] = try await supabase
                .from("injuries")
                .select()
                .order("status", ascending: true)
                .order("severity", ascending: false)
                .order("first_reported_at", ascending: false)
                .limit(100)
                .execute()
                .value

            injuries = response
        } catch {
            Log.database.error("Failed to fetch injuries: \(error)")
            ErrorReporter.shared.report(error, context: "InjuryService.fetchInjuries: Failed to fetch injuries")
            errorMessage = "Could not load injuries."
        }

        isLoading = false
    }

    // MARK: - Create Injury (Manual)

    @MainActor
    func createInjury(
        bodyArea: String,
        side: String,
        severity: Int,
        description: String?
    ) async -> Bool {
        do {
            let userId = AuthManager.shared.currentUserId ?? ""
            var newInjury: [String: AnyJSON] = [
                "user_id": .string(userId),
                "body_area": .string(bodyArea),
                "side": .string(side),
                "severity": .integer(severity),
                "status": .string("active"),
                "source": .string("manual"),
            ]

            if let description, !description.isEmpty {
                newInjury["description"] = .string(description)
            }

            try await supabase
                .from("injuries")
                .insert(newInjury)
                .execute()

            await fetchInjuries()
            return true
        } catch {
            Log.database.error("Failed to create injury: \(error)")
            ErrorReporter.shared.report(error, context: "InjuryService.createInjury: Failed to create injury")
            errorMessage = "Could not save injury."
            return false
        }
    }

    // MARK: - Update Injury

    @MainActor
    func updateInjury(
        id: UUID,
        severity: Int? = nil,
        status: InjuryStatus? = nil,
        description: String? = nil
    ) async -> Bool {
        var updateData: [String: AnyJSON] = [:]

        if let severity { updateData["severity"] = .integer(severity) }
        if let description { updateData["description"] = .string(description) }
        if let status {
            updateData["status"] = .string(status.rawValue)
            if status == .resolved {
                updateData["resolved_at"] = .string(ISO8601DateFormatter().string(from: Date()))
            }
        }

        guard !updateData.isEmpty else { return true }

        do {
            try await supabase
                .from("injuries")
                .update(updateData)
                .eq("id", value: id.uuidString)
                .execute()

            await fetchInjuries()
            return true
        } catch {
            Log.database.error("Failed to update injury: \(error)")
            ErrorReporter.shared.report(error, context: "InjuryService.updateInjury: Failed to update injury \(id)")
            errorMessage = "Could not update injury."
            return false
        }
    }

    // MARK: - Delete Injury

    @MainActor
    func deleteInjury(id: UUID) async -> Bool {
        do {
            try await supabase
                .from("injuries")
                .delete()
                .eq("id", value: id.uuidString)
                .execute()

            injuries.removeAll { $0.id == id }
            return true
        } catch {
            Log.database.error("Failed to delete injury: \(error)")
            ErrorReporter.shared.report(error, context: "InjuryService.deleteInjury: Failed to delete injury \(id)")
            errorMessage = "Could not delete injury."
            return false
        }
    }

    // MARK: - AI Analysis

    @MainActor
    func analyzeInjury(injuryId: UUID) async -> InjuryAnalysis? {
        isAnalyzing = true
        errorMessage = nil

        do {
            let data = try await callEdgeFunction(
                name: "injury-analysis",
                body: ["injuryId": injuryId.uuidString]
            )

            struct AnalysisResponse: Codable {
                let analysis: InjuryAnalysis?
            }

            let decoder = JSONDecoder()
            let response = try decoder.decode(AnalysisResponse.self, from: data)

            // Update local state
            if let analysis = response.analysis,
               let index = injuries.firstIndex(where: { $0.id == injuryId }) {
                injuries[index].aiAnalysis = analysis
                injuries[index].aiAnalysisAt = Date()
            }

            isAnalyzing = false
            return response.analysis
        } catch {
            Log.database.error("Failed to analyze injury: \(error)")
            ErrorReporter.shared.report(error, context: "InjuryService.analyzeInjury: AI analysis request failed for injury \(injuryId)")
            errorMessage = "Could not analyze injury. Please try again."
            isAnalyzing = false
            return nil
        }
    }

    // MARK: - Computed Properties

    var activeInjuries: [Injury] {
        injuries.filter { $0.status == .active || $0.status == .monitoring }
    }

    var resolvedInjuries: [Injury] {
        injuries.filter { $0.status == .resolved }
    }

    var hasActiveInjuries: Bool {
        !activeInjuries.isEmpty
    }
}
