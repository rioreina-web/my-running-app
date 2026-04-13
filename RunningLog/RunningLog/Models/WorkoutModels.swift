//
//  WorkoutModels.swift
//  RunningLog
//
//  Core workout types: TrainingPhase, PlannedWorkoutCategory, SignatureType,
//  PlannedWorkoutStep, EditableWorkoutStep, PlannedWorkout, and related
//  generation/record types.
//

import Foundation
import SwiftUI

// MARK: - Training Phase

/// Four-phase periodization: Base (10%), Support (40%), Specific (40%), Taper (10%)
enum TrainingPhase: String, Codable, CaseIterable {
    case base = "base"
    case support = "support"
    case specific = "specific"
    case taper = "taper"

    var displayName: String {
        switch self {
        case .base: return "Base Phase"
        case .support: return "Support Phase"
        case .specific: return "Specific Phase"
        case .taper: return "Taper Phase"
        }
    }

    var description: String {
        switch self {
        case .base:
            return "Building aerobic foundation with easy volume and progression runs"
        case .support:
            return "Race-supportive work at 90% and 110% of race pace, building the ladder of support"
        case .specific:
            return "Race-specific workouts at 95-105% of race pace including tempo, intervals, and MP long runs"
        case .taper:
            return "Reducing volume while maintaining intensity for race readiness"
        }
    }

    var icon: String {
        switch self {
        case .base: return "figure.run"
        case .support: return "arrow.up.right"
        case .specific: return "chart.line.uptrend.xyaxis"
        case .taper: return "target"
        }
    }

    var color: Color {
        switch self {
        case .base: return Color.drip.positive
        case .support: return Color.drip.tired
        case .specific: return Color.drip.coral
        case .taper: return Color.drip.energized
        }
    }

    /// Determine phase based on week number and total weeks
    /// Distribution: Base 10%, Support 40%, Specific 40%, Taper 10%
    static func fromWeeksOut(_ weeksOut: Int, totalWeeks: Int) -> TrainingPhase {
        let taperWeeks = max(1, Int(Double(totalWeeks) * 0.10))
        let baseWeeks = max(1, Int(Double(totalWeeks) * 0.10))
        let supportWeeks = max(2, Int(Double(totalWeeks) * 0.40))

        if weeksOut < taperWeeks {
            return .taper
        } else if weeksOut >= totalWeeks - baseWeeks {
            return .base
        } else if weeksOut >= totalWeeks - baseWeeks - supportWeeks {
            return .support
        } else {
            return .specific
        }
    }

    /// Legacy method for compatibility - assumes 16 week plan
    static func fromWeeksOut(_ weeks: Int) -> TrainingPhase {
        return fromWeeksOut(weeks, totalWeeks: 16)
    }
}

// MARK: - Workout Category

/// planned workout categories
enum PlannedWorkoutCategory: String, Codable, CaseIterable {
    case regeneration = "regeneration"
    case fundamental = "fundamental"
    case special = "special"
    case specific = "specific"

    var displayName: String {
        switch self {
        case .regeneration: return "Regeneration"
        case .fundamental: return "Fundamental"
        case .special: return "Special"
        case .specific: return "Specific"
        }
    }

    var description: String {
        switch self {
        case .regeneration: return "Easy recovery running"
        case .fundamental: return "Aerobic building blocks"
        case .special: return "Extending endurance at moderate-fast paces"
        case .specific: return "Race-pace training"
        }
    }

    var color: Color {
        switch self {
        case .regeneration: return Color.drip.positive
        case .fundamental: return Color.drip.energized
        case .special: return Color.drip.coralLight
        case .specific: return Color.drip.coral
        }
    }

    var icon: String {
        switch self {
        case .regeneration: return "leaf.fill"
        case .fundamental: return "heart.fill"
        case .special: return "flame"
        case .specific: return "bolt.fill"
        }
    }
}

// MARK: - Signature Workout Types

/// signature workout types
enum SignatureType: String, Codable {
    case progressiveTempo = "progressive_tempo"
    case descendingLadder = "descending_ladder"
    case racePaceRepeats = "race_pace_repeats"
    case specialBlock = "special_block"
    case longRunWithTempo = "long_run_with_tempo"

    var displayName: String {
        switch self {
        case .progressiveTempo: return "Progressive Tempo"
        case .descendingLadder: return "Descending Ladder"
        case .racePaceRepeats: return "Race-Pace Repeats"
        case .specialBlock: return "Special Block"
        case .longRunWithTempo: return "Long Run with Tempo"
        }
    }

    var description: String {
        switch self {
        case .progressiveTempo:
            return "Continuous run with progressive speed increase through fractions"
        case .descendingLadder:
            return "6+5+4+3+2+1 km with float recovery between each"
        case .racePaceRepeats:
            return "Repeats at 100-102% of goal race pace"
        case .specialBlock:
            return "Two quality sessions on the same day (AM + PM)"
        case .longRunWithTempo:
            return "Long run finishing with tempo section"
        }
    }
}

// MARK: - Workout Step

// MARK: - Web-format compatibility types
//
// The web coach portal saves workouts using a structured "pace zone" model
// (NamedPace + optional adjustment) instead of iOS's percentage-of-race-pace
// model. The types below let iOS decode the web format without crashing.
// Phase 3a goal: decoding compatibility only — display still uses
// targetPaceIntensity if present, otherwise falls back to the zone label.

/// Optional fine-tuning of a base pace zone, e.g. "MP +2%" or "HM −10s/mi".
/// Mirrors the web `PaceAdjustment` type in workout-helpers.ts. Convention:
/// positive value = slower than base, negative = faster.
struct WorkoutPaceAdjustment: Codable, Equatable {
    enum AdjustmentType: String, Codable {
        case percent
        case secondsPerMile = "seconds_per_mile"
        case secondsPerKm   = "seconds_per_km"
    }

    let type: AdjustmentType
    let value: Double

    /// Human-readable suffix for display ("+2%", "−10s/mi", etc.).
    /// Uses Unicode minus sign (U+2212) for typographic correctness.
    var displayString: String {
        let sign = value >= 0 ? "+" : "−"
        let magnitude = abs(value)
        let formatted = magnitude.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(magnitude))"
            : String(format: "%g", magnitude)
        switch type {
        case .percent:        return "\(sign)\(formatted)%"
        case .secondsPerMile: return "\(sign)\(formatted)s/mi"
        case .secondsPerKm:   return "\(sign)\(formatted)s/km"
        }
    }
}

/// Recovery sub-block for an interval set, e.g. "90s @ Easy" between reps.
/// Mirrors the recovery sub-object on the web WorkoutStep type.
struct PlannedWorkoutRecovery: Codable, Equatable {
    let durationType: PlannedWorkoutStep.DurationType
    let durationValue: Double
    let paceZone: NamedPace?
    let paceAdjustment: WorkoutPaceAdjustment?
}

/// A single step within a workout
struct PlannedWorkoutStep: Identifiable, Codable, Equatable {
    let id: UUID
    let stepType: StepType
    let durationType: DurationType
    let durationValue: Double
    let targetPaceIntensity: PaceIntensity?
    var targetHR: HRTarget?
    let notes: String?
    let order: Int

    // ── Web-format compatibility (Phase 3a) ────────────────
    // These fields are populated when the workout was created on the web side
    // using the new pace-zone format. Phase 3b will populate the *SecPerMile
    // fields at subscribe time so iOS can show real per-athlete paces.
    let paceZone: NamedPace?
    let paceAdjustment: WorkoutPaceAdjustment?
    let repeats: Int?
    let recovery: PlannedWorkoutRecovery?
    let referenceSecPerMile: Double?
    let personalizedSecPerMile: Double?

    // Memberwise init — preserves backward-compat for all existing call sites
    // that build steps in code (PlanImportService, WorkoutGeneratorViewModel,
    // etc.) by giving the new fields safe defaults.
    init(
        id: UUID,
        stepType: StepType,
        durationType: DurationType,
        durationValue: Double,
        targetPaceIntensity: PaceIntensity? = nil,
        targetHR: HRTarget? = nil,
        notes: String? = nil,
        order: Int,
        paceZone: NamedPace? = nil,
        paceAdjustment: WorkoutPaceAdjustment? = nil,
        repeats: Int? = nil,
        recovery: PlannedWorkoutRecovery? = nil,
        referenceSecPerMile: Double? = nil,
        personalizedSecPerMile: Double? = nil
    ) {
        self.id = id
        self.stepType = stepType
        self.durationType = durationType
        self.durationValue = durationValue
        self.targetPaceIntensity = targetPaceIntensity
        self.targetHR = targetHR
        self.notes = notes
        self.order = order
        self.paceZone = paceZone
        self.paceAdjustment = paceAdjustment
        self.repeats = repeats
        self.recovery = recovery
        self.referenceSecPerMile = referenceSecPerMile
        self.personalizedSecPerMile = personalizedSecPerMile
    }

    // Custom decoder — handles BOTH old shape (targetPaceIntensity + order)
    // and new web shape (paceZone, no order). Missing fields get safe defaults
    // so neither shape causes a decode crash.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // id may be missing on synthetic web steps — generate one if so
        self.id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.stepType = try c.decode(StepType.self, forKey: .stepType)
        self.durationType = try c.decode(DurationType.self, forKey: .durationType)
        self.durationValue = try c.decode(Double.self, forKey: .durationValue)
        // Old fields — optional
        self.targetPaceIntensity = try c.decodeIfPresent(PaceIntensity.self, forKey: .targetPaceIntensity)
        self.targetHR = try c.decodeIfPresent(HRTarget.self, forKey: .targetHR)
        self.notes = try c.decodeIfPresent(String.self, forKey: .notes)
        // Order is required on iOS but missing from web JSON — default to 0
        self.order = try c.decodeIfPresent(Int.self, forKey: .order) ?? 0
        // New web-format fields — all optional
        self.paceZone = try c.decodeIfPresent(NamedPace.self, forKey: .paceZone)
        self.paceAdjustment = try c.decodeIfPresent(WorkoutPaceAdjustment.self, forKey: .paceAdjustment)
        self.repeats = try c.decodeIfPresent(Int.self, forKey: .repeats)
        self.recovery = try c.decodeIfPresent(PlannedWorkoutRecovery.self, forKey: .recovery)
        self.referenceSecPerMile = try c.decodeIfPresent(Double.self, forKey: .referenceSecPerMile)
        self.personalizedSecPerMile = try c.decodeIfPresent(Double.self, forKey: .personalizedSecPerMile)
    }

    private enum CodingKeys: String, CodingKey {
        case id, stepType, durationType, durationValue
        case targetPaceIntensity, targetHR, notes, order
        case paceZone, paceAdjustment, repeats, recovery
        case referenceSecPerMile, personalizedSecPerMile
    }

    enum StepType: String, Codable, CaseIterable {
        case warmup = "warmup"
        case active = "active"
        case rest = "rest"
        case recovery = "recovery"
        case cooldown = "cooldown"

        var displayName: String {
            switch self {
            case .warmup: return "Warm-up"
            case .active: return "Active"
            case .rest: return "Rest"
            case .recovery: return "Float Recovery"
            case .cooldown: return "Cool-down"
            }
        }

        var defaultPace: NamedPace {
            switch self {
            case .warmup, .cooldown, .recovery: return .easy
            case .active: return .mp
            case .rest: return .easy
            }
        }

        var color: Color {
            switch self {
            case .warmup: return Color.drip.positive
            case .active: return Color.drip.coral
            case .rest: return Color.drip.textSecondary
            case .recovery: return Color.drip.energized
            case .cooldown: return Color.drip.positive
            }
        }
    }

    enum DurationType: String, Codable, CaseIterable {
        case distanceKm = "distance_km"
        case distanceMiles = "distance_miles"
        case distanceMeters = "distance_meters"
        case timeSeconds = "time_seconds"
        case open = "open"

        var unit: String {
            switch self {
            case .distanceKm: return "km"
            case .distanceMiles: return "mi"
            case .distanceMeters: return "m"
            case .timeSeconds: return ""
            case .open: return ""
            }
        }

        var displayLabel: String {
            switch self {
            case .distanceKm: return "km"
            case .distanceMiles: return "miles"
            case .distanceMeters: return "meters"
            case .timeSeconds: return "time"
            case .open: return "open"
            }
        }
    }

    /// Format duration for display
    var formattedDuration: String {
        switch durationType {
        case .distanceKm:
            return String(format: "%.1f km", durationValue)
        case .distanceMiles:
            return String(format: "%.1f mi", durationValue)
        case .distanceMeters:
            return String(format: "%.0fm", durationValue)
        case .timeSeconds:
            let mins = Int(durationValue) / 60
            let secs = Int(durationValue) % 60
            if secs > 0 {
                return "\(mins):\(String(format: "%02d", secs))"
            }
            return "\(mins) min"
        case .open:
            return "Open"
        }
    }

    /// Full description including pace target — always shows pace per mile/km
    func fullDescription(racePaceSeconds: Double) -> String {
        var desc = formattedDuration
        if let intensity = targetPaceIntensity {
            desc += " @ \(intensity.formattedPace(forRacePace: racePaceSeconds))"
            desc += " (\(intensity.displayPercentage))"
        }
        return desc
    }

    /// Full description with named pace labels when available — always shows pace per mile/km
    func fullDescription(racePaceSeconds: Double, equivalentPaces: EquivalentPaces?) -> String {
        var desc = formattedDuration
        if let intensity = targetPaceIntensity {
            desc += " @ \(intensity.formattedPace(forRacePace: racePaceSeconds))"
            let label = intensity.displayLabel(forRacePace: racePaceSeconds, equivalentPaces: equivalentPaces)
            desc += " (\(label))"
        }
        return desc
    }
}

// MARK: - Editable Workout Step

/// Mutable version of PlannedWorkoutStep for editing
struct EditableWorkoutStep: Identifiable {
    let id: UUID
    var stepType: PlannedWorkoutStep.StepType
    var durationType: PlannedWorkoutStep.DurationType
    var durationValue: Double
    var paceSelection: PaceSelection
    var hrTarget: HRTarget? = nil
    var notes: String
    var order: Int

    /// How the pace target is specified
    enum PaceSelection: Equatable {
        case namedPace(NamedPace)
        /// Named pace ± offset in sec/mile. Positive = slower, negative = faster.
        case namedPaceOffset(NamedPace, Double)
        /// Named pace ± offset in percent. Positive = slower, negative = faster.
        case namedPacePercentOffset(NamedPace, Double)
        case custom(Double)
        /// Target time in seconds for the rep distance (e.g., 1600m in 305s = 5:05)
        case targetTime(Double)
        case none

        var baseNamedPace: NamedPace? {
            switch self {
            case .namedPace(let p): return p
            case .namedPaceOffset(let p, _): return p
            case .namedPacePercentOffset(let p, _): return p
            default: return nil
            }
        }

        var offsetSeconds: Double {
            if case .namedPaceOffset(_, let offset) = self { return offset }
            return 0
        }

        var offsetPercent: Double {
            if case .namedPacePercentOffset(_, let pct) = self { return pct }
            return 0
        }

        var isPercentMode: Bool {
            if case .namedPacePercentOffset = self { return true }
            return false
        }

        /// Resolved pace in sec/mile given equivalent paces
        func resolvedPaceSeconds(equivalentPaces: EquivalentPaces, racePaceSeconds: Double) -> Double? {
            switch self {
            case .namedPace(let named):
                return equivalentPaces.paceSeconds(for: named)
            case .namedPaceOffset(let named, let offsetSec):
                return max(equivalentPaces.paceSeconds(for: named) + offsetSec, 1)
            case .namedPacePercentOffset(let named, let pct):
                let base = equivalentPaces.paceSeconds(for: named)
                return max(base * (1 + pct / 100.0), 1)
            case .custom(let pct):
                return max(racePaceSeconds / (pct / 100.0), 1)
            case .targetTime:
                return nil // Target time is absolute, not pace-based
            case .none:
                return nil
            }
        }

        /// Convert to PaceIntensity given equivalent paces and race pace
        func toPaceIntensity(
            racePaceSeconds: Double,
            equivalentPaces: EquivalentPaces
        ) -> PaceIntensity? {
            guard let target = resolvedPaceSeconds(equivalentPaces: equivalentPaces, racePaceSeconds: racePaceSeconds) else { return nil }
            let percentage = racePaceSeconds / target * 100.0
            return PaceIntensity(percentage: percentage)
        }
    }

    /// Initialize from an existing PlannedWorkoutStep
    init(from step: PlannedWorkoutStep, equivalentPaces: EquivalentPaces?, racePaceSeconds: Double) {
        self.id = step.id
        self.stepType = step.stepType
        self.durationType = step.durationType
        self.durationValue = step.durationValue
        self.order = step.order
        self.notes = step.notes ?? ""

        self.hrTarget = step.targetHR

        if step.targetHR != nil {
            // HR-targeted step — no pace selection
            self.paceSelection = .none
        } else if let intensity = step.targetPaceIntensity, let equiv = equivalentPaces {
            let actualPace = intensity.paceSeconds(forRacePace: racePaceSeconds)
            // Use tight tolerance (1s) so only exact named-pace matches snap — prevents
            // custom percentages near a named pace from losing their precise value
            if let named = equiv.closestNamedPace(forPaceSeconds: actualPace, tolerance: 1.0) {
                self.paceSelection = .namedPace(named)
            } else {
                self.paceSelection = .custom(intensity.percentage)
            }
        } else if let intensity = step.targetPaceIntensity {
            self.paceSelection = .custom(intensity.percentage)
        } else {
            self.paceSelection = .none
        }
    }

    /// Initialize a new empty step
    init(order: Int, stepType: PlannedWorkoutStep.StepType = .active) {
        self.id = UUID()
        self.stepType = stepType
        self.durationType = .distanceMiles
        self.durationValue = 1.0
        self.paceSelection = .namedPace(stepType.defaultPace)
        self.notes = ""
        self.order = order
    }

    /// Convert back to PlannedWorkoutStep
    func toWorkoutStep(racePaceSeconds: Double, equivalentPaces: EquivalentPaces) -> PlannedWorkoutStep {
        let pace: PaceIntensity? = hrTarget != nil ? nil : paceSelection.toPaceIntensity(
            racePaceSeconds: racePaceSeconds,
            equivalentPaces: equivalentPaces
        )
        return PlannedWorkoutStep(
            id: id,
            stepType: stepType,
            durationType: durationType,
            durationValue: durationValue,
            targetPaceIntensity: pace,
            targetHR: hrTarget,
            notes: notes.isEmpty ? nil : notes,
            order: order
        )
    }
}

// MARK: - Workout

/// Complete planned workout with all steps
struct PlannedWorkout: Identifiable, Codable {
    let id: UUID
    let name: String
    let category: PlannedWorkoutCategory
    let trainingPhase: TrainingPhase
    let description: String
    let steps: [PlannedWorkoutStep]
    var totalDistanceMiles: Double?
    var estimatedDurationMinutes: Double?
    let signatureType: SignatureType?
    let createdAt: Date

    // Legacy support for Supabase data stored in km
    private enum CodingKeys: String, CodingKey {
        case id, name, category, trainingPhase, description, steps
        case totalDistanceMiles = "total_distance_km" // Keep same DB column, convert on read
        case estimatedDurationMinutes = "estimated_duration_minutes"
        case signatureType = "signature_type"
        case createdAt = "created_at"
    }

    // Memberwise init — preserves backward-compat for existing call sites
    // (PlanImportService, ImportedDayWorkout.toPlannedWorkout, etc.) that
    // construct workouts in code with all fields specified.
    init(
        id: UUID,
        name: String,
        category: PlannedWorkoutCategory,
        trainingPhase: TrainingPhase,
        description: String,
        steps: [PlannedWorkoutStep],
        totalDistanceMiles: Double? = nil,
        estimatedDurationMinutes: Double? = nil,
        signatureType: SignatureType? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.trainingPhase = trainingPhase
        self.description = description
        self.steps = steps
        self.totalDistanceMiles = totalDistanceMiles
        self.estimatedDurationMinutes = estimatedDurationMinutes
        self.signatureType = signatureType
        self.createdAt = createdAt
    }

    // Custom decoder — handles BOTH old shape (full schema with id, category,
    // trainingPhase, description, createdAt) and new web shape (only name +
    // steps + total_distance_km present). Missing fields get safe defaults so
    // workouts created via the web coach portal don't fail to decode and
    // silently disappear from the athlete calendar.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Workout"
        self.category = try c.decodeIfPresent(PlannedWorkoutCategory.self, forKey: .category) ?? .regeneration
        self.trainingPhase = try c.decodeIfPresent(TrainingPhase.self, forKey: .trainingPhase) ?? .base
        self.description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        self.steps = try c.decodeIfPresent([PlannedWorkoutStep].self, forKey: .steps) ?? []
        self.totalDistanceMiles = try c.decodeIfPresent(Double.self, forKey: .totalDistanceMiles)
        self.estimatedDurationMinutes = try c.decodeIfPresent(Double.self, forKey: .estimatedDurationMinutes)
        self.signatureType = try c.decodeIfPresent(SignatureType.self, forKey: .signatureType)
        self.createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }

    var formattedTotalDistance: String? {
        guard let miles = totalDistanceMiles else { return nil }
        return String(format: "%.1f mi", miles)
    }

    var formattedDuration: String? {
        guard let mins = estimatedDurationMinutes else { return nil }
        if mins >= 60 {
            let hours = Int(mins) / 60
            let remaining = Int(mins) % 60
            if remaining > 0 {
                return "\(hours)h \(remaining)m"
            }
            return "\(hours)h"
        }
        return "\(Int(mins)) min"
    }

    var activeSteps: [PlannedWorkoutStep] {
        steps.filter { $0.stepType == .active }
    }

    /// Calculate total active distance in miles (active steps only)
    var totalActiveDistanceMiles: Double {
        steps.filter { $0.stepType == .active }.reduce(0) { total, step in
            switch step.durationType {
            case .distanceKm: return total + step.durationValue / 1.60934
            case .distanceMiles: return total + step.durationValue
            case .distanceMeters: return total + step.durationValue / 1609.34
            default: return total
            }
        }
    }

    /// Total distance across ALL steps (warmup, active, recovery, cooldown, etc.)
    var totalAllStepsDistanceMiles: Double {
        steps.reduce(0) { total, step in
            switch step.durationType {
            case .distanceKm: return total + step.durationValue / 1.60934
            case .distanceMiles: return total + step.durationValue
            case .distanceMeters: return total + step.durationValue / 1609.34
            case .timeSeconds:
                // Only estimate distance for pace-targeted running steps
                // Skip HR-only (cross training) and no-target (strength) steps
                guard step.targetHR == nil, step.targetPaceIntensity != nil else { return total }
                let paceSecPerMile: Double = switch step.stepType {
                case .warmup, .cooldown: 540    // ~9:00/mi
                case .recovery: 570             // ~9:30/mi
                case .active: 420               // ~7:00/mi
                case .rest: 0
                }
                let miles = paceSecPerMile > 0 ? step.durationValue / paceSecPerMile : 0
                return total + miles
            case .open: return total
            }
        }
    }

    /// Best available distance: explicit totalDistanceMiles, then computed from steps
    var effectiveDistanceMiles: Double? {
        if let d = totalDistanceMiles, d > 0 { return d }
        let computed = totalAllStepsDistanceMiles
        return computed > 0 ? computed : nil
    }

    /// Backward compatibility: total distance in km
    var totalDistanceKm: Double? {
        guard let miles = totalDistanceMiles else { return nil }
        return miles * 1.60934
    }
}

// MARK: - Workout Generation Request

/// Request payload for generating a planned workout
struct WorkoutGenerationRequest: Codable {
    let userId: String
    let goalRaceDistance: String
    let goalTimeSeconds: Int
    let targetDate: Date
    let weeksUntilRace: Int
    let currentPhase: String
    let currentWeeklyMileage: Double?
    let preferredWorkoutType: String?
    let fitnessLevel: String?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case goalRaceDistance = "goal_race_distance"
        case goalTimeSeconds = "goal_time_seconds"
        case targetDate = "target_date"
        case weeksUntilRace = "weeks_until_race"
        case currentPhase = "current_phase"
        case currentWeeklyMileage = "current_weekly_mileage"
        case preferredWorkoutType = "preferred_workout_type"
        case fitnessLevel = "fitness_level"
    }
}

// MARK: - Workout Generation Response

/// Response from workout generator edge function
struct WorkoutGenerationResponse: Codable {
    let workout: PlannedWorkout?
    let error: String?
}

// MARK: - Generated Workout Record

/// Database record for stored workouts
struct GeneratedWorkoutRecord: Codable, Identifiable {
    let id: UUID
    let workoutData: PlannedWorkout
    let goalRaceDistance: String?
    let goalTimeSeconds: Int?
    let trainingPhase: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case workoutData = "workout_data"
        case goalRaceDistance = "goal_race_distance"
        case goalTimeSeconds = "goal_time_seconds"
        case trainingPhase = "training_phase"
        case createdAt = "created_at"
    }
}

// MARK: - Helper Extensions

extension PlannedWorkout {
    /// Create a sample workout for previews
    static var sample: PlannedWorkout {
        PlannedWorkout(
            id: UUID(),
            name: "Progressive Tempo Run",
            category: .special,
            trainingPhase: .specific,
            description: "Build aerobic capacity with progressive intensity",
            steps: [
                PlannedWorkoutStep(
                    id: UUID(),
                    stepType: .warmup,
                    durationType: .distanceMiles,
                    durationValue: 2.0,
                    targetPaceIntensity: PaceIntensity(percentage: 70),
                    notes: "Easy warm-up",
                    order: 0
                ),
                PlannedWorkoutStep(
                    id: UUID(),
                    stepType: .active,
                    durationType: .distanceMiles,
                    durationValue: 4.0,
                    targetPaceIntensity: PaceIntensity(percentage: 87),
                    notes: "First fraction - comfortable",
                    order: 1
                ),
                PlannedWorkoutStep(
                    id: UUID(),
                    stepType: .active,
                    durationType: .distanceMiles,
                    durationValue: 4.0,
                    targetPaceIntensity: PaceIntensity(percentage: 95),
                    notes: "Second fraction - push",
                    order: 2
                ),
                PlannedWorkoutStep(
                    id: UUID(),
                    stepType: .cooldown,
                    durationType: .distanceMiles,
                    durationValue: 2.0,
                    targetPaceIntensity: PaceIntensity(percentage: 65),
                    notes: "Easy cool-down",
                    order: 3
                )
            ],
            totalDistanceMiles: 12.0,
            estimatedDurationMinutes: 90,
            signatureType: .progressiveTempo,
            createdAt: Date()
        )
    }
}
