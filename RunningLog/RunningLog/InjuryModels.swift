import Foundation
import SwiftUI

// MARK: - Injury

struct Injury: Codable, Identifiable {
    let id: UUID
    let userId: String
    let bodyArea: String
    let side: String
    var description: String?
    var severity: Int
    var status: InjuryStatus
    let firstReportedAt: Date
    var resolvedAt: Date?
    let source: InjurySource
    let sourceReferenceId: UUID?
    var aiAnalysis: InjuryAnalysis?
    var aiAnalysisAt: Date?
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case bodyArea = "body_area"
        case side
        case description
        case severity
        case status
        case firstReportedAt = "first_reported_at"
        case resolvedAt = "resolved_at"
        case source
        case sourceReferenceId = "source_reference_id"
        case aiAnalysis = "ai_analysis"
        case aiAnalysisAt = "ai_analysis_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var displayName: String {
        let sidePrefix = side != "unknown" ? "\(side.capitalized) " : ""
        return "\(sidePrefix)\(bodyArea.replacingOccurrences(of: "it band", with: "IT Band").capitalized)"
    }

    var daysSinceReported: Int {
        Calendar.current.dateComponents([.day], from: firstReportedAt, to: Date()).day ?? 0
    }

    var severityLabel: String {
        switch severity {
        case 1 ... 3: return "Mild"
        case 4 ... 6: return "Moderate"
        case 7 ... 8: return "Severe"
        case 9 ... 10: return "Critical"
        default: return "Unknown"
        }
    }

    var severityColor: Color {
        switch severity {
        case 1 ... 3: return Color.drip.positive
        case 4 ... 5: return Color.drip.tired
        case 6 ... 7: return .orange
        case 8 ... 10: return Color.drip.injured
        default: return Color.drip.textSecondary
        }
    }
}

// MARK: - InjuryStatus

enum InjuryStatus: String, Codable, CaseIterable {
    case active
    case monitoring
    case resolved

    var displayName: String {
        switch self {
        case .active: return "Active"
        case .monitoring: return "Monitoring"
        case .resolved: return "Resolved"
        }
    }

    var color: Color {
        switch self {
        case .active: return Color.drip.injured
        case .monitoring: return Color.drip.tired
        case .resolved: return Color.drip.positive
        }
    }

    var icon: String {
        switch self {
        case .active: return "exclamationmark.triangle.fill"
        case .monitoring: return "eye.fill"
        case .resolved: return "checkmark.circle.fill"
        }
    }
}

// MARK: - InjurySource

enum InjurySource: String, Codable {
    case voiceMemo = "voice_memo"
    case coachingChat = "coaching_chat"
    case manual

    var displayName: String {
        switch self {
        case .voiceMemo: return "Voice Memo"
        case .coachingChat: return "Coach Chat"
        case .manual: return "Manual Entry"
        }
    }

    var icon: String {
        switch self {
        case .voiceMemo: return "waveform"
        case .coachingChat: return "message.fill"
        case .manual: return "hand.tap.fill"
        }
    }
}

// MARK: - InjuryAnalysis (AI response)

struct InjuryAnalysis: Codable {
    let likelyCauses: [String]?
    let riskLevel: String?
    let recoveryTimelineDays: RecoveryTimeline?
    let recommendedActions: [RecommendedAction]?
    let trainingModifications: [TrainingModification]?
    let warningSigns: [String]?
    let returnToRunningCriteria: [String]?
    let isRecurring: Bool?
    let goalImpact: String?
    let summary: String?
    let disclaimer: String?

    enum CodingKeys: String, CodingKey {
        case likelyCauses = "likely_causes"
        case riskLevel = "risk_level"
        case recoveryTimelineDays = "recovery_timeline_days"
        case recommendedActions = "recommended_actions"
        case trainingModifications = "training_modifications"
        case warningSigns = "warning_signs"
        case returnToRunningCriteria = "return_to_running_criteria"
        case isRecurring = "is_recurring"
        case goalImpact = "goal_impact"
        case summary
        case disclaimer
    }

    var riskColor: Color {
        switch riskLevel?.lowercased() {
        case "low": return Color.drip.positive
        case "moderate": return Color.drip.tired
        case "high": return Color.drip.injured
        default: return Color.drip.textSecondary
        }
    }
}

struct RecoveryTimeline: Codable {
    let optimistic: Int?
    let typical: Int?
    let conservative: Int?
}

struct RecommendedAction: Codable, Identifiable {
    var id: String { action }
    let action: String
    let priority: String
    let detail: String

    var priorityColor: Color {
        switch priority {
        case "immediate": return Color.drip.injured
        case "short_term": return Color.drip.tired
        case "ongoing": return Color.drip.positive
        default: return Color.drip.textSecondary
        }
    }

    var priorityLabel: String {
        switch priority {
        case "immediate": return "Now"
        case "short_term": return "Soon"
        case "ongoing": return "Ongoing"
        default: return priority.capitalized
        }
    }
}

struct TrainingModification: Codable, Identifiable {
    var id: String { modification }
    let modification: String
    let duration: String
    let rationale: String
}

// MARK: - Body Area Options

enum BodyArea: String, CaseIterable {
    case calf
    case hamstring
    case quad
    case knee
    case ankle
    case achilles
    case shin
    case hip
    case itBand = "it band"
    case plantar
    case foot
    case back
    case glute

    var displayName: String {
        switch self {
        case .itBand: return "IT Band"
        case .plantar: return "Plantar"
        default: return rawValue.capitalized
        }
    }

    var icon: String {
        switch self {
        case .knee, .ankle, .shin, .calf, .foot, .plantar, .achilles:
            return "figure.walk"
        case .hip, .glute, .hamstring, .quad, .itBand:
            return "figure.run"
        case .back:
            return "figure.stand"
        }
    }
}

// MARK: - Medical Disclaimer

enum MedicalDisclaimer {
    static let short = "This is not medical advice. Consult a healthcare professional."
    static let full = "The information provided by this app is for educational and informational purposes only. It is not intended as a substitute for professional medical advice, diagnosis, or treatment. Always seek the advice of a qualified healthcare provider with any questions you may have regarding a medical condition or injury."
    static let aiAnalysis = "This AI-generated analysis is educational only and does not constitute a medical diagnosis. Individual injuries can vary significantly. Please consult a qualified healthcare professional such as a sports medicine doctor or physical therapist for proper evaluation and treatment of your injury."
}
