//
//  FormCheckModels.swift
//  RunningLog
//
//  Data models for the qualitative Form Check feature — AI-first
//  running form analysis focused on imbalances, posture, and foot strike.
//

import Foundation
import SwiftUI

// MARK: - FormCheck (Supabase entity)

struct FormCheck: Codable, Identifiable {
    let id: UUID
    let userId: String
    let localVideoFilename: String?
    let recordedAt: Date
    let durationSeconds: Double?
    let frameCount: Int?
    let fps: Double?
    var status: AnalysisStatus
    var poseDataSummary: FormCheckPoseData?
    var aiAnalysis: FormCheckAIAnalysis?
    var aiAnalysisAt: Date?
    var notes: String?
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case localVideoFilename = "local_video_filename"
        case recordedAt = "recorded_at"
        case durationSeconds = "duration_seconds"
        case frameCount = "frame_count"
        case fps
        case status
        case poseDataSummary = "pose_data_summary"
        case aiAnalysis = "ai_analysis"
        case aiAnalysisAt = "ai_analysis_at"
        case notes
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var displayDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: recordedAt)
    }

    var statusColor: Color {
        switch status {
        case .processing: return Color.drip.tired
        case .completed: return Color.drip.positive
        case .failed: return Color.drip.injured
        }
    }
}

// MARK: - FormCheckPoseData (computed on-device, sent to AI)

struct FormCheckPoseData: Codable {
    // L/R asymmetry indicators
    let hipROMLeft: Double?
    let hipROMRight: Double?
    let kneeROMLeft: Double?
    let kneeROMRight: Double?
    let ankleROMLeft: Double?
    let ankleROMRight: Double?
    let shoulderRotationROM: Double?

    // Foot strike
    let footStrikePattern: String?
    let footStrikeConfidence: Double?
    let heelVsForefoot: Double?         // meters: negative = heel lower (rearfoot), positive = forefoot lower
    let shankAngleAtContact: Double?    // degrees: shin angle at initial contact (higher = more overstriding)
    let contactCount: Int?              // number of ground contacts detected

    // Ground contact balance
    let gctLeft: Double?
    let gctRight: Double?
    let gctBalance: Double?

    // Posture indicators
    let avgTrunkLean: Double?
    let headForwardOffset: Double?
    let armSwingSymmetry: Double?

    // Shank / overstriding
    let shankAtContactLeft: Double?
    let shankAtContactRight: Double?

    // Cadence
    let cadence: Double?                    // steps per minute

    // Fatigue indicators (early vs late form comparison)
    let trunkLeanEarly: Double?             // trunk lean in first half (degrees)
    let trunkLeanLate: Double?              // trunk lean in second half (degrees)
    let cadenceEarly: Double?               // cadence in first half (spm)
    let cadenceLate: Double?                // cadence in second half (spm)

    enum CodingKeys: String, CodingKey {
        case hipROMLeft = "hip_rom_left"
        case hipROMRight = "hip_rom_right"
        case kneeROMLeft = "knee_rom_left"
        case kneeROMRight = "knee_rom_right"
        case ankleROMLeft = "ankle_rom_left"
        case ankleROMRight = "ankle_rom_right"
        case shoulderRotationROM = "shoulder_rotation_rom"
        case footStrikePattern = "foot_strike_pattern"
        case footStrikeConfidence = "foot_strike_confidence"
        case heelVsForefoot = "heel_vs_forefoot"
        case shankAngleAtContact = "shank_angle_at_contact"
        case contactCount = "contact_count"
        case gctLeft = "gct_left"
        case gctRight = "gct_right"
        case gctBalance = "gct_balance"
        case avgTrunkLean = "avg_trunk_lean"
        case headForwardOffset = "head_forward_offset"
        case armSwingSymmetry = "arm_swing_symmetry"
        case shankAtContactLeft = "shank_at_contact_left"
        case shankAtContactRight = "shank_at_contact_right"
        case cadence
        case trunkLeanEarly = "trunk_lean_early"
        case trunkLeanLate = "trunk_lean_late"
        case cadenceEarly = "cadence_early"
        case cadenceLate = "cadence_late"
    }
}

// MARK: - FormCheckAIAnalysis (returned by edge function)

struct FormCheckAIAnalysis: Codable {
    let overallAssessment: String?
    let findings: [FormCheckFinding]?
    let compensationPatterns: [CompensationPattern]?
    let drills: [FormDrill]?
    let summary: String?
    let disclaimer: String?
    let notRunning: Bool?

    enum CodingKeys: String, CodingKey {
        case overallAssessment = "overall_assessment"
        case findings
        case compensationPatterns = "compensation_patterns"
        case drills
        case summary
        case disclaimer
        case notRunning = "not_running"
    }
}

// MARK: - FormCheckFinding

struct FormCheckFinding: Codable, Identifiable {
    var id: String { area }
    let area: String
    let observation: String
    let severity: String
    let detail: String

    var severityColor: Color {
        switch severity.lowercased() {
        case "good": return Color.drip.positive
        case "watch": return Color.drip.tired
        case "concern": return Color.drip.injured
        default: return Color.drip.textSecondary
        }
    }

    var severityIcon: String {
        switch severity.lowercased() {
        case "good": return "checkmark.circle.fill"
        case "watch": return "eye.fill"
        case "concern": return "exclamationmark.triangle.fill"
        default: return "circle.fill"
        }
    }

    var severityLabel: String {
        switch severity.lowercased() {
        case "good": return "Good"
        case "watch": return "Watch"
        case "concern": return "Concern"
        default: return severity.capitalized
        }
    }
}

// MARK: - CompensationPattern

struct CompensationPattern: Codable, Identifiable {
    var id: String { pattern }
    let pattern: String
    let likelyCause: String
    let affectedAreas: [String]

    enum CodingKeys: String, CodingKey {
        case pattern
        case likelyCause = "likely_cause"
        case affectedAreas = "affected_areas"
    }
}

// MARK: - FormDrill

struct FormDrill: Codable, Identifiable {
    var id: String { name }
    let name: String
    let target: String
    let description: String
    let frequency: String
}

// MARK: - FormCheckDisclaimer

enum FormCheckDisclaimer {
    static let analysis = "This form check uses smartphone-based pose estimation for qualitative assessment only. It is not a clinical gait analysis. Consult a qualified professional for medical or biomechanical concerns."
}
