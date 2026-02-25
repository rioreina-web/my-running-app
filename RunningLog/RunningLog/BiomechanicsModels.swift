//
//  BiomechanicsModels.swift
//  RunningLog
//
//  Data models for biomechanics analysis — 3D pose estimation,
//  joint angles, foot strike patterns, and gait metrics.
//

import Foundation
import simd
import SwiftUI

// MARK: - BiomechanicsAnalysis

struct BiomechanicsAnalysis: Codable, Identifiable {
    let id: UUID
    let userId: String
    let videoStoragePath: String?
    let localVideoFilename: String?
    let recordedAt: Date
    let durationSeconds: Double?
    let frameCount: Int?
    let fps: Double?
    let viewAngle: ViewAngle
    var status: AnalysisStatus
    var jointAngles: JointAnglesSummary?
    var footStrike: FootStrikeAnalysis?
    var gaitMetrics: GaitMetrics?
    var aiAnalysis: BiomechanicsAIAnalysis?
    var aiAnalysisAt: Date?
    var linkedInjuryId: UUID?
    var notes: String?
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case videoStoragePath = "video_storage_path"
        case localVideoFilename = "local_video_filename"
        case recordedAt = "recorded_at"
        case durationSeconds = "duration_seconds"
        case frameCount = "frame_count"
        case fps
        case viewAngle = "view_angle"
        case status
        case jointAngles = "joint_angles"
        case footStrike = "foot_strike"
        case gaitMetrics = "gait_metrics"
        case aiAnalysis = "ai_analysis"
        case aiAnalysisAt = "ai_analysis_at"
        case linkedInjuryId = "linked_injury_id"
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

// MARK: - ViewAngle

enum ViewAngle: String, Codable, CaseIterable, Identifiable {
    case sagittalLeft = "sagittal_left"
    case sagittalRight = "sagittal_right"
    case frontal
    case posterior

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sagittalLeft: return "Left Side"
        case .sagittalRight: return "Right Side"
        case .frontal: return "Front"
        case .posterior: return "Back"
        }
    }

    var icon: String {
        switch self {
        case .sagittalLeft: return "arrow.left"
        case .sagittalRight: return "arrow.right"
        case .frontal: return "person.fill"
        case .posterior: return "person.fill.turn.right"
        }
    }

    var instruction: String {
        switch self {
        case .sagittalLeft: return "Film from the left side, full body visible"
        case .sagittalRight: return "Film from the right side, full body visible"
        case .frontal: return "Film from the front, facing the camera"
        case .posterior: return "Film from behind the runner"
        }
    }
}

// MARK: - AnalysisStatus

enum AnalysisStatus: String, Codable {
    case processing
    case completed
    case failed

    var displayName: String {
        switch self {
        case .processing: return "Processing"
        case .completed: return "Completed"
        case .failed: return "Failed"
        }
    }

    var icon: String {
        switch self {
        case .processing: return "clock.fill"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }
}

// MARK: - Joint Angles

struct JointAnglesSummary: Codable {
    let hipLeft: JointAngleData?
    let hipRight: JointAngleData?
    let kneeLeft: JointAngleData?
    let kneeRight: JointAngleData?
    let ankleLeft: JointAngleData?
    let ankleRight: JointAngleData?
    let shankLeft: ShankAngleData?
    let shankRight: ShankAngleData?
    let shoulderRotation: ShoulderRotationData?

    enum CodingKeys: String, CodingKey {
        case hipLeft = "hip_left"
        case hipRight = "hip_right"
        case kneeLeft = "knee_left"
        case kneeRight = "knee_right"
        case ankleLeft = "ankle_left"
        case ankleRight = "ankle_right"
        case shankLeft = "shank_left"
        case shankRight = "shank_right"
        case shoulderRotation = "shoulder_rotation"
    }
}

struct JointAngleData: Codable {
    let meanAngle: Double
    let maxAngle: Double
    let minAngle: Double
    let rangeOfMotion: Double
    let angleTimeSeries: [Double]?

    enum CodingKeys: String, CodingKey {
        case meanAngle = "mean_angle"
        case maxAngle = "max_angle"
        case minAngle = "min_angle"
        case rangeOfMotion = "range_of_motion"
        case angleTimeSeries = "angle_time_series"
    }

    var romStatus: ROMStatus {
        // Generic ROM assessment — caller should use joint-specific thresholds
        return .normal
    }
}

// MARK: - Shank Angle (Tibial Inclination)

struct ShankAngleData: Codable {
    let atInitialContact: Double?
    let meanAngle: Double
    let maxAngle: Double
    let minAngle: Double

    enum CodingKeys: String, CodingKey {
        case atInitialContact = "at_initial_contact"
        case meanAngle = "mean_angle"
        case maxAngle = "max_angle"
        case minAngle = "min_angle"
    }

    /// Shank angle at initial contact indicates overstriding risk.
    /// Ideal: close to vertical (< 5° past vertical). Overstriding: > 10° past vertical.
    var overstridingRisk: ROMStatus {
        guard let angle = atInitialContact else { return .unknown }
        if angle < 5 { return .normal }
        if angle < 10 { return .borderline }
        return .atypical
    }
}

// MARK: - Shoulder Rotation (Transverse Plane)

struct ShoulderRotationData: Codable {
    /// Mean absolute rotation angle between shoulder line and hip line (degrees)
    let meanRotation: Double
    /// Peak rotation observed (degrees)
    let peakRotation: Double
    /// Range of rotation (max - min) through the gait cycle
    let rangeOfMotion: Double
    /// Time series of rotation angles (optional, for future charting)
    let anglTimeSeries: [Double]?

    enum CodingKeys: String, CodingKey {
        case meanRotation = "mean_rotation"
        case peakRotation = "peak_rotation"
        case rangeOfMotion = "range_of_motion"
        case anglTimeSeries = "angle_time_series"
    }

    /// Normal counter-rotation in running: 5-15° ROM.
    /// Excessive: > 20°, Insufficient: < 3°.
    var rotationStatus: ROMStatus {
        if rangeOfMotion >= 5 && rangeOfMotion <= 15 { return .normal }
        if rangeOfMotion > 3 && rangeOfMotion <= 20 { return .borderline }
        return .atypical
    }
}

// MARK: - Foot Strike Analysis

struct FootStrikeAnalysis: Codable {
    let pattern: FootStrikePattern
    let confidence: Double
    let ankleAngleAtContact: Double?
    let shankAngleAtContact: Double?
    /// Heel-to-forefoot Y difference at contact (negative = heel lower = rearfoot).
    /// Only available when MediaPipe provides heel + foot index landmarks.
    let heelVsForefoot: Double?
    let frameIndices: [Int]?
    let contactFrameDetail: FootStrikeContactFrame?

    enum CodingKeys: String, CodingKey {
        case pattern
        case confidence
        case ankleAngleAtContact = "ankle_angle_at_contact"
        case shankAngleAtContact = "shank_angle_at_contact"
        case heelVsForefoot = "heel_vs_forefoot"
        case frameIndices = "frame_indices"
        case contactFrameDetail = "contact_frame_detail"
    }
}

/// 2D image positions at a contact frame for overlay visualization.
struct FootStrikeContactFrame: Codable {
    let timestamp: Double
    let frameIndex: Int
    /// Normalized image coordinates (0-1, bottom-left origin)
    let hipImageX: Float
    let hipImageY: Float
    let kneeImageX: Float
    let kneeImageY: Float
    let ankleImageX: Float
    let ankleImageY: Float
    let heelImageX: Float?
    let heelImageY: Float?
    let footIndexImageX: Float?
    let footIndexImageY: Float?
    let shankAngle: Double?

    enum CodingKeys: String, CodingKey {
        case timestamp
        case frameIndex = "frame_index"
        case hipImageX = "hip_image_x"
        case hipImageY = "hip_image_y"
        case kneeImageX = "knee_image_x"
        case kneeImageY = "knee_image_y"
        case ankleImageX = "ankle_image_x"
        case ankleImageY = "ankle_image_y"
        case heelImageX = "heel_image_x"
        case heelImageY = "heel_image_y"
        case footIndexImageX = "foot_index_image_x"
        case footIndexImageY = "foot_index_image_y"
        case shankAngle = "shank_angle"
    }
}

enum FootStrikePattern: String, Codable, CaseIterable {
    case rearfoot = "rearfoot"
    case midfoot = "midfoot"
    case forefoot = "forefoot"

    var displayName: String {
        switch self {
        case .rearfoot: return "Heel Strike"
        case .midfoot: return "Midfoot"
        case .forefoot: return "Forefoot"
        }
    }

    var description: String {
        switch self {
        case .rearfoot: return "Landing on the heel first — common in recreational runners"
        case .midfoot: return "Landing with the foot relatively flat — efficient for distance"
        case .forefoot: return "Landing on the ball of the foot — common in sprinters"
        }
    }

    var color: Color {
        switch self {
        case .rearfoot: return Color.drip.tired
        case .midfoot: return Color.drip.positive
        case .forefoot: return Color.drip.coral
        }
    }
}

// MARK: - ROM Status

enum ROMStatus {
    case normal
    case borderline
    case atypical
    case unknown

    var color: Color {
        switch self {
        case .normal: return Color.drip.positive
        case .borderline: return Color.drip.tired
        case .atypical: return Color.drip.injured
        case .unknown: return Color.drip.textSecondary
        }
    }

    var label: String {
        switch self {
        case .normal: return "Normal"
        case .borderline: return "Borderline"
        case .atypical: return "Atypical"
        case .unknown: return "—"
        }
    }
}

// MARK: - Processing Quality

enum ProcessingQuality: String, CaseIterable, Identifiable {
    case fast
    case enhanced

    var id: String { rawValue }

    var sampleRate: Double {
        switch self {
        case .fast: return 10.0
        case .enhanced: return 20.0
        }
    }

    var displayName: String {
        switch self {
        case .fast: return "Fast"
        case .enhanced: return "Enhanced"
        }
    }

    var subtitle: String {
        switch self {
        case .fast: return "~30 seconds"
        case .enhanced: return "~2 minutes"
        }
    }

    var description: String {
        switch self {
        case .fast: return "10 fps sampling — good for joint angles and foot strike"
        case .enhanced: return "20 fps sampling — better ground contact time and gait metrics"
        }
    }

    var icon: String {
        switch self {
        case .fast: return "hare.fill"
        case .enhanced: return "scope"
        }
    }
}

// MARK: - Video Clip (on-device only, for multi-video capture flow)

struct VideoClip: Identifiable {
    let id = UUID()
    let url: URL
    let viewAngle: ViewAngle
}

// MARK: - Pose Frame Data (on-device only, not persisted to Supabase)

struct PoseFrame: Codable {
    let frameIndex: Int
    let timestamp: Double
    let joints: [JointPosition3D]
    let bodyHeight: Float?

    enum CodingKeys: String, CodingKey {
        case frameIndex = "frame_index"
        case timestamp
        case joints
        case bodyHeight = "body_height"
    }

    func joint(named name: String) -> JointPosition3D? {
        joints.first { $0.name == name }
    }

    func jointPosition(named name: String) -> simd_float3? {
        guard let joint = joint(named: name) else { return nil }
        return simd_float3(joint.x, joint.y, joint.z)
    }

    /// Get the 2D image position for a named joint (normalized 0-1, bottom-left origin).
    func imagePosition(named name: String) -> CGPoint? {
        guard let joint = joint(named: name),
              let ix = joint.imageX, let iy = joint.imageY
        else { return nil }
        return CGPoint(x: CGFloat(ix), y: CGFloat(iy))
    }
}

struct JointPosition3D: Codable {
    let name: String
    let x: Float
    let y: Float
    let z: Float
    let confidence: Float
    /// Normalized image coordinate (0-1), Vision convention (bottom-left origin)
    let imageX: Float?
    let imageY: Float?

    enum CodingKeys: String, CodingKey {
        case name, x, y, z, confidence
        case imageX = "image_x"
        case imageY = "image_y"
    }
}

// MARK: - Gait Metrics (Phase 2)

struct GaitMetrics: Codable {
    let cadence: Double?
    let strideLength: Double?
    let groundContactTime: Double?
    let groundContactTimeLeft: Double?
    let groundContactTimeRight: Double?
    let groundContactBalance: Double?
    let flightTime: Double?
    let stancePhasePercent: Double?
    let swingPhasePercent: Double?
    let verticalOscillation: Double?
    let gaitCycleEvents: [GaitCycleEvent]?

    enum CodingKeys: String, CodingKey {
        case cadence
        case strideLength = "stride_length"
        case groundContactTime = "ground_contact_time"
        case groundContactTimeLeft = "ground_contact_time_left"
        case groundContactTimeRight = "ground_contact_time_right"
        case groundContactBalance = "ground_contact_balance"
        case flightTime = "flight_time"
        case stancePhasePercent = "stance_phase_percent"
        case swingPhasePercent = "swing_phase_percent"
        case verticalOscillation = "vertical_oscillation"
        case gaitCycleEvents = "gait_cycle_events"
    }

    /// Balance status: how close to 50/50
    var balanceStatus: ROMStatus {
        guard let balance = groundContactBalance else { return .unknown }
        let deviation = abs(balance - 50)
        if deviation < 2 { return .normal }
        if deviation < 5 { return .borderline }
        return .atypical
    }
}

struct GaitCycleEvent: Codable {
    let type: GaitEventType
    let timestamp: Double
    let frameIndex: Int
    let side: String

    enum CodingKeys: String, CodingKey {
        case type
        case timestamp
        case frameIndex = "frame_index"
        case side
    }
}

enum GaitEventType: String, Codable {
    case heelStrike = "heel_strike"
    case toeOff = "toe_off"
}

// MARK: - AI Analysis (Phase 3)

struct BiomechanicsAIAnalysis: Codable {
    let overallScore: Int?
    let formAssessment: String?
    let findings: [BiomechanicsFindings]?
    let injuryRiskFactors: [String]?
    let improvementPriorities: [ImprovementPriority]?
    let comparisonNotes: String?
    let disclaimer: String?

    enum CodingKeys: String, CodingKey {
        case overallScore = "overall_score"
        case formAssessment = "form_assessment"
        case findings
        case injuryRiskFactors = "injury_risk_factors"
        case improvementPriorities = "improvement_priorities"
        case comparisonNotes = "comparison_notes"
        case disclaimer
    }
}

struct BiomechanicsFindings: Codable, Identifiable {
    var id: String { area }
    let area: String
    let observation: String
    let severity: String
    let recommendation: String

    var severityColor: Color {
        switch severity.lowercased() {
        case "normal": return Color.drip.positive
        case "minor": return Color.drip.tired
        case "moderate": return .orange
        case "significant": return Color.drip.injured
        default: return Color.drip.textSecondary
        }
    }
}

struct ImprovementPriority: Codable, Identifiable {
    var id: Int { priority }
    let priority: Int
    let area: String
    let drill: String
    let explanation: String
}

// MARK: - Reference Ranges

enum BiomechanicsReferenceRanges {
    struct JointRange {
        let normalMin: Double
        let normalMax: Double
        let label: String
    }

    static let hipFlexion = JointRange(normalMin: 40, normalMax: 55, label: "Hip Flexion")
    static let hipExtension = JointRange(normalMin: 10, normalMax: 15, label: "Hip Extension")
    static let kneeFlexionSwing = JointRange(normalMin: 90, normalMax: 120, label: "Knee Flexion (Swing)")
    static let kneeAtContact = JointRange(normalMin: 5, normalMax: 10, label: "Knee at Contact")
    static let shankAtContact = JointRange(normalMin: -5, normalMax: 5, label: "Shank at Contact")
    static let shoulderRotation = JointRange(normalMin: 5, normalMax: 15, label: "Shoulder Rotation ROM")
    static func status(value: Double, range: JointRange) -> ROMStatus {
        if value >= range.normalMin && value <= range.normalMax {
            return .normal
        }
        let margin = (range.normalMax - range.normalMin) * 0.3
        if value >= (range.normalMin - margin) && value <= (range.normalMax + margin) {
            return .borderline
        }
        return .atypical
    }
}

// MARK: - Biomechanics Disclaimer

enum BiomechanicsDisclaimer {
    static let analysis = "This biomechanics analysis uses smartphone-based pose estimation with typical accuracy of 4-7° compared to lab-based motion capture. Results are for educational purposes only and should not replace professional gait analysis. Consult a qualified biomechanist or physical therapist for clinical assessment."
}
