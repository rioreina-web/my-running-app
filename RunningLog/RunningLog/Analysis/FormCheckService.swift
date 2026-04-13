//
//  FormCheckService.swift
//  RunningLog
//
//  Supabase CRUD and AI analysis for qualitative form checks.
//  Follows BiomechanicsService pattern.
//

import Foundation
import os
import Supabase

@Observable
final class FormCheckService {
    var formChecks: [FormCheck] = []
    var isLoading = false
    var isAnalyzing = false
    var errorMessage: String?

    // MARK: - Fetch All

    @MainActor
    func fetchFormChecks() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        do {
            let response: [FormCheck] = try await supabase
                .from("form_checks")
                .select()
                .order("recorded_at", ascending: false)
                .limit(50)
                .execute()
                .value

            formChecks = response
        } catch {
            Log.biomechanics.error("Failed to fetch form checks: \(error)")
            ErrorReporter.shared.report(error, context: "FormCheckService.fetchFormChecks: Failed to fetch form checks")
            errorMessage = "Could not load form checks."
        }

        isLoading = false
    }

    // MARK: - Create

    @MainActor
    func createFormCheck(
        localVideoFilename: String,
        durationSeconds: Double,
        frameCount: Int,
        fps: Double,
        poseDataSummary: FormCheckPoseData,
        notes: String? = nil
    ) async -> UUID? {
        do {
            let userId = AuthManager.shared.currentUserId ?? ""
            let id = UUID()

            let insertRow = FormCheckInsertRow(
                id: id,
                userId: userId,
                localVideoFilename: localVideoFilename,
                durationSeconds: durationSeconds,
                frameCount: frameCount,
                fps: fps,
                status: "completed",
                poseDataSummary: poseDataSummary,
                notes: notes
            )

            try await supabase
                .from("form_checks")
                .insert(insertRow)
                .execute()

            await fetchFormChecks()
            Log.biomechanics.info("Created form check \(id.uuidString)")
            return id
        } catch {
            Log.biomechanics.error("Failed to create form check: \(error)")
            ErrorReporter.shared.report(error, context: "FormCheckService.createFormCheck: Failed to create form check")
            errorMessage = "Could not save form check: \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: - Delete

    @MainActor
    func deleteFormCheck(id: UUID) async -> Bool {
        // Find the check before deleting so we can clean up the local video
        let filename = formChecks.first(where: { $0.id == id })?.localVideoFilename

        do {
            try await supabase
                .from("form_checks")
                .delete()
                .eq("id", value: id.uuidString)
                .execute()

            formChecks.removeAll { $0.id == id }

            // Clean up local video file
            if let filename {
                let url = BiomechanicsService.localVideoURL(for: filename)
                try? FileManager.default.removeItem(at: url)
            }

            return true
        } catch {
            Log.biomechanics.error("Failed to delete form check: \(error)")
            ErrorReporter.shared.report(error, context: "FormCheckService.deleteFormCheck: Failed to delete form check \(id)")
            errorMessage = "Could not delete form check."
            return false
        }
    }

    // MARK: - AI Analysis

    @MainActor
    func requestAIAnalysis(formCheckId: UUID) async -> FormCheckAIAnalysis? {
        isAnalyzing = true
        errorMessage = nil

        do {
            let data = try await callEdgeFunction(
                name: "form-check-analysis",
                body: ["formCheckId": formCheckId.uuidString]
            )

            let rawPreview = String(data: data.prefix(500), encoding: .utf8) ?? "n/a"
            Log.biomechanics.info("Form check AI response (\(data.count) bytes): \(rawPreview)")

            // Check for error responses
            struct ErrorResponse: Codable {
                let error: String?
            }
            if let errorResp = try? JSONDecoder().decode(ErrorResponse.self, from: data),
               let errorMsg = errorResp.error
            {
                Log.biomechanics.error("Edge function error: \(errorMsg)")
                errorMessage = "AI analysis failed: \(errorMsg)"
                isAnalyzing = false
                return nil
            }

            struct AnalysisResponse: Codable {
                let analysis: FormCheckAIAnalysis?
            }

            let decoder = JSONDecoder()
            let response: AnalysisResponse
            do {
                response = try decoder.decode(AnalysisResponse.self, from: data)
            } catch {
                Log.biomechanics.error("Failed to decode form check AI response: \(error). Raw: \(rawPreview)")
                ErrorReporter.shared.report(error, context: "FormCheckService.requestAIAnalysis: Failed to decode AI response for form check \(formCheckId)")
                errorMessage = "AI analysis returned an unexpected format. Please try again."
                isAnalyzing = false
                return nil
            }

            guard let aiAnalysis = response.analysis else {
                Log.biomechanics.error("Edge function returned nil analysis. Raw: \(rawPreview)")
                errorMessage = "AI analysis returned no results. Please try again."
                isAnalyzing = false
                return nil
            }

            if let index = formChecks.firstIndex(where: { $0.id == formCheckId }) {
                formChecks[index].aiAnalysis = aiAnalysis
                formChecks[index].aiAnalysisAt = Date()
                if aiAnalysis.notRunning == true {
                    formChecks[index].status = .failed
                }
            }

            isAnalyzing = false
            return aiAnalysis
        } catch {
            Log.biomechanics.error("Failed form check AI analysis: \(error)")
            ErrorReporter.shared.report(error, context: "FormCheckService.requestAIAnalysis: AI analysis request failed for form check \(formCheckId)")
            errorMessage = "Could not analyze form. Please try again."
            isAnalyzing = false
            return nil
        }
    }

    // MARK: - Computed Properties

    var completedChecks: [FormCheck] {
        formChecks.filter { $0.status == .completed }
    }

    var latestCheck: FormCheck? {
        completedChecks.first
    }
}

// MARK: - Insert Row

private struct FormCheckInsertRow: Encodable {
    let id: UUID
    let userId: String
    let localVideoFilename: String
    let durationSeconds: Double
    let frameCount: Int
    let fps: Double
    let status: String
    let poseDataSummary: FormCheckPoseData
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case localVideoFilename = "local_video_filename"
        case durationSeconds = "duration_seconds"
        case frameCount = "frame_count"
        case fps
        case status
        case poseDataSummary = "pose_data_summary"
        case notes
    }
}
