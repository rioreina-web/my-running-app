//
//  BiomechanicsService.swift
//  RunningLog
//
//  Supabase CRUD for biomechanics analyses. Follows InjuryService pattern.
//

import Foundation
import os
import Supabase

@Observable
final class BiomechanicsService {
    var analyses: [BiomechanicsAnalysis] = []
    var isLoading = false
    var isAnalyzing = false
    var errorMessage: String?

    // MARK: - Fetch All Analyses

    @MainActor
    func fetchAnalyses() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        do {
            let response: [BiomechanicsAnalysis] = try await supabase
                .from("biomechanics_analyses")
                .select()
                .order("recorded_at", ascending: false)
                .limit(50)
                .execute()
                .value

            analyses = response
        } catch {
            Log.biomechanics.error("Failed to fetch analyses: \(error)")
            ErrorReporter.shared.report(error, context: "BiomechanicsService.fetchAnalyses: Failed to fetch biomechanics analyses")
            errorMessage = "Could not load analyses."
        }

        isLoading = false
    }

    // MARK: - Create Analysis

    @MainActor
    func createAnalysis(
        localVideoFilename: String,
        viewAngle: ViewAngle,
        durationSeconds: Double,
        frameCount: Int,
        fps: Double,
        jointAngles: JointAnglesSummary,
        footStrike: FootStrikeAnalysis?,
        gaitMetrics: GaitMetrics? = nil,
        linkedInjuryId: UUID? = nil,
        notes: String? = nil
    ) async -> UUID? {
        do {
            let userId = AuthManager.shared.currentUserId ?? ""
            let id = UUID()

            let insertRow = BiomechanicsInsertRow(
                id: id,
                userId: userId,
                localVideoFilename: localVideoFilename,
                viewAngle: viewAngle.rawValue,
                durationSeconds: durationSeconds,
                frameCount: frameCount,
                fps: fps,
                status: "completed",
                jointAngles: jointAngles,
                footStrike: footStrike,
                gaitMetrics: gaitMetrics,
                linkedInjuryId: linkedInjuryId,
                notes: notes
            )

            try await supabase
                .from("biomechanics_analyses")
                .insert(insertRow)
                .execute()

            await fetchAnalyses()
            Log.biomechanics.info("Created analysis \(id.uuidString)")
            return id
        } catch {
            Log.biomechanics.error("Failed to create analysis: \(error)")
            ErrorReporter.shared.report(error, context: "BiomechanicsService.createAnalysis: Failed to create biomechanics analysis")
            errorMessage = "Could not save analysis: \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: - Delete Analysis

    @MainActor
    func deleteAnalysis(id: UUID) async -> Bool {
        do {
            try await supabase
                .from("biomechanics_analyses")
                .delete()
                .eq("id", value: id.uuidString)
                .execute()

            analyses.removeAll { $0.id == id }

            // Clean up local video file
            deleteLocalVideo(for: id)

            return true
        } catch {
            Log.biomechanics.error("Failed to delete analysis: \(error)")
            ErrorReporter.shared.report(error, context: "BiomechanicsService.deleteAnalysis: Failed to delete biomechanics analysis \(id)")
            errorMessage = "Could not delete analysis."
            return false
        }
    }

    // MARK: - AI Analysis (Phase 3)

    @MainActor
    func requestAIAnalysis(analysisId: UUID) async -> BiomechanicsAIAnalysis? {
        isAnalyzing = true
        errorMessage = nil

        do {
            let data = try await callEdgeFunction(
                name: "biomechanics-analysis",
                body: ["analysisId": analysisId.uuidString]
            )

            let rawPreview = String(data: data.prefix(500), encoding: .utf8) ?? "n/a"
            Log.biomechanics.info("AI analysis response (\(data.count) bytes): \(rawPreview)")

            // Check for error responses from the edge function
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
                let analysis: BiomechanicsAIAnalysis?
            }

            let decoder = JSONDecoder()
            let response: AnalysisResponse
            do {
                response = try decoder.decode(AnalysisResponse.self, from: data)
            } catch {
                Log.biomechanics.error("Failed to decode AI response: \(error). Raw: \(rawPreview)")
                ErrorReporter.shared.report(error, context: "BiomechanicsService.requestAIAnalysis: Failed to decode AI response for analysis \(analysisId)")
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

            if let index = analyses.firstIndex(where: { $0.id == analysisId }) {
                analyses[index].aiAnalysis = aiAnalysis
                analyses[index].aiAnalysisAt = Date()
            }

            isAnalyzing = false
            return aiAnalysis
        } catch {
            Log.biomechanics.error("Failed AI analysis: \(error)")
            ErrorReporter.shared.report(error, context: "BiomechanicsService.requestAIAnalysis: AI analysis request failed for analysis \(analysisId)")
            errorMessage = "Could not analyze biomechanics. Please try again."
            isAnalyzing = false
            return nil
        }
    }

    // MARK: - Computed Properties

    var completedAnalyses: [BiomechanicsAnalysis] {
        analyses.filter { $0.status == .completed }
    }

    var latestAnalysis: BiomechanicsAnalysis? {
        completedAnalyses.first
    }

    // MARK: - Local Video Management

    static var videosDirectory: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let videosDir = documentsPath.appendingPathComponent("biomechanics_videos", isDirectory: true)
        try? FileManager.default.createDirectory(at: videosDir, withIntermediateDirectories: true)
        return videosDir
    }

    static func saveVideoLocally(from sourceURL: URL) throws -> String {
        let filename = "\(UUID().uuidString).mov"
        let destination = videosDirectory.appendingPathComponent(filename)
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        return filename
    }

    static func localVideoURL(for filename: String) -> URL {
        videosDirectory.appendingPathComponent(filename)
    }

    private func deleteLocalVideo(for analysisId: UUID) {
        guard let analysis = analyses.first(where: { $0.id == analysisId }),
              let filename = analysis.localVideoFilename
        else { return }
        let url = Self.localVideoURL(for: filename)
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - Insert Row (Encodable for Supabase insert)

private struct BiomechanicsInsertRow: Encodable {
    let id: UUID
    let userId: String
    let localVideoFilename: String
    let viewAngle: String
    let durationSeconds: Double
    let frameCount: Int
    let fps: Double
    let status: String
    let jointAngles: JointAnglesSummary
    let footStrike: FootStrikeAnalysis?
    let gaitMetrics: GaitMetrics?
    let linkedInjuryId: UUID?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case localVideoFilename = "local_video_filename"
        case viewAngle = "view_angle"
        case durationSeconds = "duration_seconds"
        case frameCount = "frame_count"
        case fps
        case status
        case jointAngles = "joint_angles"
        case footStrike = "foot_strike"
        case gaitMetrics = "gait_metrics"
        case linkedInjuryId = "linked_injury_id"
        case notes
    }
}
