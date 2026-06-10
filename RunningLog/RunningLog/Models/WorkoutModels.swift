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

// MARK: - Structure grouping
//
// Normalize the flat steps[] array into a three-section shape (warmup
// prefix, middle blocks, cooldown suffix) where the middle blocks
// collapse interval reps into a single `reps` entry. Mirrors the web
// `groupStepsIntoSections` helper. Used by WorkoutDetailView and any
// other surface that wants to render "6 × 800m" instead of six flat
// "800m" rows.
//
// Handles two storage shapes:
//   1. New format — step has `repeats > 1` and a nested `recovery`.
//   2. Old flat format — coach or LLM stored "800m, 2min, 800m, 2min,
//      ..." as N separate steps. Adjacent identical Active steps with
//      a consistent gap between them collapse into one block.

enum WorkoutStepBlockKind: Equatable {
    case single
    case reps(count: Int, recovery: PlannedWorkoutRecovery?)
}

struct WorkoutStepBlock: Identifiable, Equatable {
    let id: UUID
    let kind: WorkoutStepBlockKind
    /// The primary step rendered (active body of the rep group, or the
    /// single step itself).
    let step: PlannedWorkoutStep
}

struct WorkoutSections: Equatable {
    let warmup: [PlannedWorkoutStep]
    let blocks: [WorkoutStepBlock]
    let cooldown: [PlannedWorkoutStep]
}

private func matchesAsRep(_ a: PlannedWorkoutStep, _ b: PlannedWorkoutStep) -> Bool {
    return a.stepType == b.stepType
        && a.durationType == b.durationType
        && a.durationValue == b.durationValue
        && a.paceZone == b.paceZone
        && a.paceAdjustment == b.paceAdjustment
}

private func matchesAsRecoveryShape(_ a: PlannedWorkoutStep, _ b: PlannedWorkoutStep) -> Bool {
    return a.durationType == b.durationType
        && a.durationValue == b.durationValue
        && a.paceZone == b.paceZone
        && a.paceAdjustment == b.paceAdjustment
}

func groupStepsIntoSections(_ steps: [PlannedWorkoutStep]) -> WorkoutSections {
    // 1. Warmup prefix
    var warmupEnd = 0
    while warmupEnd < steps.count && steps[warmupEnd].stepType == .warmup {
        warmupEnd += 1
    }
    // 2. Cooldown suffix
    var cooldownStart = steps.count
    while cooldownStart > warmupEnd && steps[cooldownStart - 1].stepType == .cooldown {
        cooldownStart -= 1
    }

    let warmup = Array(steps[..<warmupEnd])
    let cooldown = Array(steps[cooldownStart...])
    let middle = Array(steps[warmupEnd..<cooldownStart])

    var blocks: [WorkoutStepBlock] = []
    var i = 0
    while i < middle.count {
        let step = middle[i]

        // Pass-through: step already encodes repeats.
        if let reps = step.repeats, reps > 1 {
            blocks.append(WorkoutStepBlock(
                id: UUID(),
                kind: .reps(count: reps, recovery: step.recovery),
                step: step,
            ))
            i += 1
            continue
        }

        // Flat-format collapse — only attempt on active steps.
        if step.stepType == .active {
            var mainCount = 1
            var recoveryRow: PlannedWorkoutStep?
            var j = i + 1
            while j < middle.count {
                // Adjacent matching main, no gap.
                if matchesAsRep(middle[j], step) {
                    mainCount += 1
                    j += 1
                    continue
                }
                // Gap candidate — verify next is matching main.
                if j + 1 >= middle.count { break }
                if !matchesAsRep(middle[j + 1], step) { break }
                let candidate = middle[j]
                if let recovery = recoveryRow, !matchesAsRecoveryShape(recovery, candidate) {
                    break
                }
                if recoveryRow == nil { recoveryRow = candidate }
                mainCount += 1
                j += 2
            }
            if mainCount >= 2 {
                let recovery: PlannedWorkoutRecovery? = recoveryRow.map { r in
                    PlannedWorkoutRecovery(
                        durationType: r.durationType,
                        durationValue: r.durationValue,
                        paceZone: r.paceZone,
                        paceAdjustment: r.paceAdjustment,
                    )
                }
                blocks.append(WorkoutStepBlock(
                    id: UUID(),
                    kind: .reps(count: mainCount, recovery: recovery),
                    step: step,
                ))
                i = j
                continue
            }
        }

        // Default: single step.
        blocks.append(WorkoutStepBlock(id: UUID(), kind: .single, step: step))
        i += 1
    }

    return WorkoutSections(warmup: warmup, blocks: blocks, cooldown: cooldown)
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

    // Custom decoder — handles FOUR shapes:
    //   1. Legacy iOS: nested `targetPaceIntensity` object.
    //   2. Web/AI: `paceZone` named reference + `referenceSecPerMile`.
    //   3. Adaptive-plan-v1 (Phase 1): flat `target_pace_seconds_per_mile` +
    //      optional `target_pace_seconds_high` + optional `pace_reference`.
    //   4. Coach-authored (coach portal, or legacy plans from the now-
    //      removed custom-plan-builder): `target_pace` as "M:SS" string
    //      (already resolved, usually goal-anchored). Paired with optional
    //      `paceZone` + `paceAdjustment` for display/audit.
    // Missing fields get safe defaults so none of the shapes crash decode.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.stepType = try c.decode(StepType.self, forKey: .stepType)
        self.durationType = try c.decode(DurationType.self, forKey: .durationType)
        self.durationValue = try c.decode(Double.self, forKey: .durationValue)
        // Priority order (most trustworthy first):
        //   1. Coach-authored `target_pace: "M:SS"` string — literal prescription.
        //   2. Phase-1 flat `target_pace_seconds_per_mile` — resolver output.
        //   3. Nested `targetPaceIntensity` with concrete seconds.
        //   4. Nested `targetPaceIntensity` with only a percentage — last resort.
        //      Any legacy percentage gets discarded when a higher-priority
        //      concrete pace is present; mixing them produced workouts
        //      rendered at the wrong pace (e.g., HM step showing as 3K pace).
        let targetPaceStr = try c.decodeIfPresent(String.self, forKey: .targetPace)
        let flatSecPerMile = try c.decodeIfPresent(Double.self, forKey: .targetPaceSecondsPerMile)
        let flatSecPerMileHigh = try c.decodeIfPresent(Double.self, forKey: .targetPaceSecondsHigh)
        let nestedIntensity = try c.decodeIfPresent(PaceIntensity.self, forKey: .targetPaceIntensity)

        var resolvedIntensity: PaceIntensity? = nil
        if let paceStr = targetPaceStr, let secPerMile = Self.parsePaceString(paceStr) {
            resolvedIntensity = PaceIntensity(
                percentage: 0,
                paceSecondsPerKm: secPerMile / 1.609344,
                paceSecondsPerKmHigh: nil
            )
        } else if let secPerMile = flatSecPerMile, secPerMile > 0 {
            resolvedIntensity = PaceIntensity(
                percentage: 0,
                paceSecondsPerKm: secPerMile / 1.609344,
                paceSecondsPerKmHigh: flatSecPerMileHigh.map { $0 / 1.609344 }
            )
        } else if let nested = nestedIntensity, nested.paceSecondsPerKm != nil {
            resolvedIntensity = nested
        } else if let nested = nestedIntensity {
            // Percentage-only fallback. Kept for very old workouts but warned
            // about — render path will derive pace via racePaceSeconds, which
            // is unreliable when the plan was authored against a different
            // reference (e.g., goal 5K vs current fitness).
            resolvedIntensity = nested
        }
        self.targetPaceIntensity = resolvedIntensity
        self.targetHR = try c.decodeIfPresent(HRTarget.self, forKey: .targetHR)
        self.notes = try c.decodeIfPresent(String.self, forKey: .notes)
        self.order = try c.decodeIfPresent(Int.self, forKey: .order) ?? 0
        self.paceZone = try c.decodeIfPresent(NamedPace.self, forKey: .paceZone)
        self.paceAdjustment = try c.decodeIfPresent(WorkoutPaceAdjustment.self, forKey: .paceAdjustment)
        self.repeats = try c.decodeIfPresent(Int.self, forKey: .repeats)
        self.recovery = try c.decodeIfPresent(PlannedWorkoutRecovery.self, forKey: .recovery)
        self.referenceSecPerMile = try c.decodeIfPresent(Double.self, forKey: .referenceSecPerMile)
            ?? flatSecPerMile // new flat field doubles as reference when the old one is absent
        self.personalizedSecPerMile = try c.decodeIfPresent(Double.self, forKey: .personalizedSecPerMile)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(stepType, forKey: .stepType)
        try c.encode(durationType, forKey: .durationType)
        try c.encode(durationValue, forKey: .durationValue)
        try c.encodeIfPresent(targetPaceIntensity, forKey: .targetPaceIntensity)
        try c.encodeIfPresent(targetHR, forKey: .targetHR)
        try c.encodeIfPresent(notes, forKey: .notes)
        try c.encode(order, forKey: .order)
        try c.encodeIfPresent(paceZone, forKey: .paceZone)
        try c.encodeIfPresent(paceAdjustment, forKey: .paceAdjustment)
        try c.encodeIfPresent(repeats, forKey: .repeats)
        try c.encodeIfPresent(recovery, forKey: .recovery)
        try c.encodeIfPresent(referenceSecPerMile, forKey: .referenceSecPerMile)
        try c.encodeIfPresent(personalizedSecPerMile, forKey: .personalizedSecPerMile)
    }

    private enum CodingKeys: String, CodingKey {
        case id, stepType, durationType, durationValue
        case targetPaceIntensity, targetHR, notes, order
        case paceZone, paceAdjustment, repeats, recovery
        case referenceSecPerMile, personalizedSecPerMile
        case targetPaceSecondsPerMile = "target_pace_seconds_per_mile"
        case targetPaceSecondsHigh = "target_pace_seconds_high"
        case targetPace = "target_pace"
    }

    /// Parse a coach-written pace string in "M:SS" form (e.g. "5:34" or "7:27")
    /// into seconds per mile. Returns nil for malformed or out-of-range values.
    static func parsePaceStringExternal(_ s: String) -> Double? { parsePaceString(s) }
    private static func parsePaceString(_ s: String) -> Double? {
        let parts = s.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        let total = Double(parts[0] * 60 + parts[1])
        return (total >= 180 && total <= 900) ? total : nil
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
    /// Interval set count. When >1, this step is rendered as "N × {duration}"
    /// with `recovery` underneath. Mirrors PlannedWorkoutStep.repeats so the
    /// editor round-trips workouts authored on the web / by the LLM without
    /// flattening or dropping interval structure. nil means "single rep".
    var repeats: Int? = nil
    /// Between-rep recovery. Only meaningful when `repeats > 1`. Editable
    /// mirror of PlannedWorkoutRecovery — keeps the editor and persisted
    /// model symmetric.
    var recovery: EditableRecovery? = nil

    /// Editable mirror of PlannedWorkoutRecovery. Uses the same `PaceSelection`
    /// enum as the parent step so the recovery's pace target can be
    /// rendered/edited with the same UI components.
    struct EditableRecovery: Equatable {
        var durationType: PlannedWorkoutStep.DurationType
        var durationValue: Double
        var paceSelection: PaceSelection
    }

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

        // Carry over interval structure verbatim. Before this fix, repeats
        // and recovery were silently dropped here — a workout authored on
        // the web with "7 × 1mi + 90s recovery" loaded as a single 1mi step,
        // and any save from the iOS editor wiped the structure permanently.
        // See WorkoutTemplateEditorView screenshot regression, May 2026.
        self.repeats = step.repeats
        self.recovery = step.recovery.map { rec in
            EditableRecovery(
                durationType: rec.durationType,
                durationValue: rec.durationValue,
                paceSelection: EditableWorkoutStep.paceSelection(
                    from: rec.paceZone,
                    adjustment: rec.paceAdjustment
                )
            )
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
        // Encode interval structure. Only emit `repeats` when > 1 — a stored
        // `repeats: 1` is meaningless and clutters the JSON. Recovery is
        // mirrored back from the editable struct using the same paceZone +
        // adjustment shape the planned model expects.
        let emittedRepeats: Int? = (repeats ?? 1) > 1 ? repeats : nil
        let plannedRecovery: PlannedWorkoutRecovery? = emittedRepeats == nil ? nil : recovery.map { rec in
            let (zone, adjustment) = EditableWorkoutStep.zoneAndAdjustment(from: rec.paceSelection)
            return PlannedWorkoutRecovery(
                durationType: rec.durationType,
                durationValue: rec.durationValue,
                paceZone: zone,
                paceAdjustment: adjustment
            )
        }
        // Round-trip the parent step's structural paceZone + paceAdjustment
        // too — when the source step was authored on the web (zone-based,
        // not seconds-based) we keep that representation intact so the next
        // surface to read it doesn't have to reverse-engineer it from
        // targetPaceIntensity.
        let (parentZone, parentAdjustment) = EditableWorkoutStep.zoneAndAdjustment(from: paceSelection)
        return PlannedWorkoutStep(
            id: id,
            stepType: stepType,
            durationType: durationType,
            durationValue: durationValue,
            targetPaceIntensity: pace,
            targetHR: hrTarget,
            notes: notes.isEmpty ? nil : notes,
            order: order,
            paceZone: parentZone,
            paceAdjustment: parentAdjustment,
            repeats: emittedRepeats,
            recovery: plannedRecovery
        )
    }

    // MARK: - PaceSelection ↔ paceZone + adjustment

    /// Lift a stored (NamedPace, WorkoutPaceAdjustment?) pair into the
    /// editor's PaceSelection enum. Maps adjustment.type → the matching
    /// enum case; seconds_per_km is converted to seconds_per_mile so the
    /// editor only has to handle two flavors of offset.
    static func paceSelection(
        from zone: NamedPace?,
        adjustment: WorkoutPaceAdjustment?
    ) -> PaceSelection {
        guard let zone else { return .none }
        guard let adj = adjustment, adj.value != 0 else {
            return .namedPace(zone)
        }
        switch adj.type {
        case .percent:
            return .namedPacePercentOffset(zone, adj.value)
        case .secondsPerMile:
            return .namedPaceOffset(zone, adj.value)
        case .secondsPerKm:
            // Convert the per-km offset into per-mile to keep the editor's
            // offset units consistent. `× 1.609344` is the same conversion
            // adjustedPaceSecPerMile applies on the web side.
            return .namedPaceOffset(zone, adj.value * 1.609344)
        }
    }

    /// Lower a PaceSelection back to (NamedPace?, WorkoutPaceAdjustment?).
    /// `.custom`, `.targetTime`, `.none` collapse to (nil, nil) — those
    /// modes don't have a paceZone representation; the targetPaceIntensity
    /// already carries the resolved pace for those cases.
    static func zoneAndAdjustment(
        from selection: PaceSelection
    ) -> (NamedPace?, WorkoutPaceAdjustment?) {
        switch selection {
        case .namedPace(let p):
            return (p, nil)
        case .namedPaceOffset(let p, let sec):
            return (p, WorkoutPaceAdjustment(type: .secondsPerMile, value: sec))
        case .namedPacePercentOffset(let p, let pct):
            return (p, WorkoutPaceAdjustment(type: .percent, value: pct))
        case .custom, .targetTime, .none:
            return (nil, nil)
        }
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
        case targetPace = "target_pace" // top-level pace on unstructured easy workouts
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
        let decodedName = try c.decodeIfPresent(String.self, forKey: .name) ?? "Workout"
        self.name = decodedName
        // Category is rarely present in workout_data JSON written by
        // subscribe-to-plan and the web coach editor, so a missing-field
        // fallback of .regeneration was causing every tempo, threshold, and
        // interval workout to display the green "Regeneration" leaf badge.
        // Infer from the name when the field isn't there. (We can't infer
        // from steps yet — they're decoded a few lines down.)
        if let explicit = try c.decodeIfPresent(PlannedWorkoutCategory.self, forKey: .category) {
            self.category = explicit
        } else {
            self.category = Self.inferCategoryFromName(decodedName)
        }
        self.trainingPhase = try c.decodeIfPresent(TrainingPhase.self, forKey: .trainingPhase) ?? .base
        self.description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        var decodedSteps = try c.decodeIfPresent([PlannedWorkoutStep].self, forKey: .steps) ?? []
        // Restore the natural workout flow: warmup first, cooldown last,
        // everything else in the middle preserved as-authored. Some authoring
        // paths (LLM, web coach) emit the JSON array in the wrong order
        // (active before warmup) and ship without `order` values, so we'd
        // otherwise render Active → Warm-up → Cool-down.
        //
        // Stable sort by stepType priority preserves interval rep ordering
        // (warmup, active, rest, active, rest, …, cooldown stays correct
        // because all the middle steps have priority 1).
        decodedSteps = Self.reorderStepsForDisplay(decodedSteps)
        // DB column is `total_distance_km` (kilometers). Convert to miles here
        // so the property name matches its actual value downstream.
        let decodedMiles: Double?
        if let km = try c.decodeIfPresent(Double.self, forKey: .totalDistanceMiles) {
            decodedMiles = km / RaceDistanceConstants.kmPerMile
        } else {
            decodedMiles = nil
        }
        self.totalDistanceMiles = decodedMiles
        // Unstructured easy workouts arrive as `{name, target_pace, total_distance_km}`
        // with no steps array. Synthesize a single active step so the workout
        // card can render a pace instead of rendering a bare name.
        if decodedSteps.isEmpty,
           let paceStr = try c.decodeIfPresent(String.self, forKey: .targetPace),
           let miles = decodedMiles, miles > 0,
           let secPerMile = PlannedWorkoutStep.parsePaceStringExternal(paceStr) {
            decodedSteps = [PlannedWorkoutStep(
                id: UUID(),
                stepType: .active,
                durationType: .distanceMiles,
                durationValue: miles,
                targetPaceIntensity: PaceIntensity(
                    percentage: 0,
                    paceSecondsPerKm: secPerMile / 1.609344,
                    paceSecondsPerKmHigh: nil
                ),
                notes: nil,
                order: 0
            )]
        }
        self.steps = decodedSteps
        self.estimatedDurationMinutes = try c.decodeIfPresent(Double.self, forKey: .estimatedDurationMinutes)
        self.signatureType = try c.decodeIfPresent(SignatureType.self, forKey: .signatureType)
        self.createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }

    // Custom encoder — mirror of the decoder. Convert miles → km for the DB
    // column `total_distance_km`.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(category, forKey: .category)
        try c.encode(trainingPhase, forKey: .trainingPhase)
        try c.encode(description, forKey: .description)
        try c.encode(steps, forKey: .steps)
        if let miles = totalDistanceMiles {
            try c.encode(miles * RaceDistanceConstants.kmPerMile, forKey: .totalDistanceMiles)
        }
        try c.encodeIfPresent(estimatedDurationMinutes, forKey: .estimatedDurationMinutes)
        try c.encodeIfPresent(signatureType, forKey: .signatureType)
        try c.encode(createdAt, forKey: .createdAt)
    }

    var formattedTotalDistance: String? {
        guard let miles = totalDistanceMiles else { return nil }
        return String(format: "%.1f mi", miles)
    }

    /// Heuristic to recover a sensible category when the JSON payload
    /// doesn't carry one. The web coach editor and subscribe-to-plan write
    /// rich workout_data without the `category` key, so the previous
    /// decoder default of `.regeneration` was painting every tempo,
    /// threshold, and interval workout with a green "Regeneration" leaf
    /// badge. Match keywords in priority order — most specific first —
    /// so that "5K intervals" classifies as .specific and not .regeneration
    /// just because "K" doesn't trigger a tempo match.
    fileprivate static func inferCategoryFromName(_ name: String) -> PlannedWorkoutCategory {
        let lower = name.lowercased()

        // Specific = race-pace intervals, VO2, sprint repeats
        let specificKeywords = ["interval", "repeat", "vo2", "5k pace", "5k @", "8x", "10x", "12x", "16x", "200m", "400m", "800m", "1k repeat", "1mi rep"]
        if specificKeywords.contains(where: lower.contains) { return .specific }
        // "N x ..." pattern (e.g., "8 x 400") — common in interval workouts
        if lower.range(of: #"\b\d+\s*x\s*"#, options: .regularExpression) != nil { return .specific }

        // Special = tempo, threshold, MP work, race pace, progression
        let specialKeywords = ["tempo", "threshold", "lactate", "marathon pace", "race pace",
                                "progression", "fartlek", "steady state", "mp ", "mp-", "mp+",
                                "lt ", "lt-", "lt+", "@mp", "@ mp"]
        if specialKeywords.contains(where: lower.contains) { return .special }

        // Fundamental = long run / endurance focus
        let fundamentalKeywords = ["long run", "long-run", "endurance", "miles long"]
        if fundamentalKeywords.contains(where: lower.contains) { return .fundamental }

        // Recovery / easy default
        return .regeneration
    }

    /// Stable-sort steps so warmup is first and cooldown is last, leaving
    /// every other step in array order. If the steps already carry distinct
    /// `order` values (e.g., LLM-authored intervals with order 0..15), trust
    /// those. Otherwise fall back to stepType priority.
    fileprivate static func reorderStepsForDisplay(_ steps: [PlannedWorkoutStep]) -> [PlannedWorkoutStep] {
        guard !steps.isEmpty else { return steps }

        // If `order` is meaningfully set (any two steps differ), trust it.
        let distinctOrders = Set(steps.map { $0.order })
        if distinctOrders.count > 1 {
            return steps.sorted { $0.order < $1.order }
        }

        // Otherwise sort by stepType priority. Ties preserve original
        // index, so interval reps that arrive interleaved stay interleaved.
        let priority: (PlannedWorkoutStep.StepType) -> Int = { type in
            switch type {
            case .warmup:                return 0
            case .active, .recovery, .rest: return 1
            case .cooldown:              return 2
            }
        }
        return steps.enumerated()
            .sorted { lhs, rhs in
                let lp = priority(lhs.element.stepType)
                let rp = priority(rhs.element.stepType)
                if lp != rp { return lp < rp }
                return lhs.offset < rhs.offset
            }
            .map { $0.element }
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

    /// Convert a step or recovery segment's distance duration to miles. Returns
    /// 0 for time- or open-based segments — the time→distance heuristic lives
    /// in the callers that have access to the step context (pace target, step
    /// type) needed to apply it.
    private func durationToMiles(_ type: PlannedWorkoutStep.DurationType, _ value: Double) -> Double {
        switch type {
        case .distanceMiles: return value
        case .distanceKm: return value / RaceDistanceConstants.kmPerMile
        case .distanceMeters: return value / RaceDistanceConstants.meterPerMile
        case .timeSeconds, .open: return 0
        }
    }

    /// Calculate total active distance in miles (active steps only). Honors
    /// interval repeats and between-rep recovery so `6 × 800m + 400m recovery`
    /// reports the full 4.225 mi instead of a single rep.
    var totalActiveDistanceMiles: Double {
        steps.filter { $0.stepType == .active }.reduce(0) { total, step in
            let reps = max(step.repeats ?? 1, 1)
            let activeMiles = durationToMiles(step.durationType, step.durationValue) * Double(reps)
            let recoveryMiles = step.recovery.map {
                durationToMiles($0.durationType, $0.durationValue) * Double(reps - 1)
            } ?? 0
            return total + activeMiles + recoveryMiles
        }
    }

    /// Total distance across ALL steps (warmup, active, recovery, cooldown, etc.),
    /// honoring interval repeats and between-rep recovery. Uses the reference
    /// runner for time→distance conversion — call `computedDistanceMiles(paces:)`
    /// directly when an athlete pace table is available.
    var totalAllStepsDistanceMiles: Double {
        computedDistanceMiles(paces: nil)
    }

    /// Total distance in miles, personalized when `paces` is provided. Identical
    /// to `totalAllStepsDistanceMiles` for distance-only workouts; differs for
    /// timeSeconds segments where the time→distance conversion uses the
    /// athlete's own pace for the step's zone (or intensity) instead of the
    /// reference runner.
    func computedDistanceMiles(paces: EquivalentPaces?) -> Double {
        steps.reduce(0) { total, step in
            let reps = max(step.repeats ?? 1, 1)

            let activeMiles: Double = {
                let direct = durationToMiles(step.durationType, step.durationValue)
                if direct > 0 { return direct * Double(reps) }
                guard step.durationType == .timeSeconds,
                      step.targetHR == nil,
                      (step.paceZone != nil || step.targetPaceIntensity != nil) else { return 0 }
                let pace = Self.secondsPerMile(for: step, paces: paces)
                guard pace > 0 else { return 0 }
                return (step.durationValue / pace) * Double(reps)
            }()

            let recoveryMiles: Double = {
                guard let recovery = step.recovery else { return 0 }
                let direct = durationToMiles(recovery.durationType, recovery.durationValue)
                if direct > 0 { return direct * Double(reps - 1) }
                guard recovery.durationType == .timeSeconds else { return 0 }
                let pace = Self.secondsPerMile(for: recovery, paces: paces)
                guard pace > 0 else { return 0 }
                return (recovery.durationValue / pace) * Double(reps - 1)
            }()

            return total + activeMiles + recoveryMiles
        }
    }

    /// Total estimated duration in minutes — personalized when `paces` is
    /// provided, or a reference-runner estimate when nil. UI should label the
    /// nil-paces case as `PlannedWorkout.referenceRunnerLabel`.
    func computedDurationMinutes(paces: EquivalentPaces?) -> Double {
        steps.reduce(0) { total, step in
            let reps = max(step.repeats ?? 1, 1)
            let activeSec = segmentDurationSeconds(step: step, paces: paces) * Double(reps)
            let recoverySec: Double = step.recovery.map {
                segmentDurationSeconds(recovery: $0, paces: paces) * Double(reps - 1)
            } ?? 0
            return total + (activeSec + recoverySec) / 60
        }
    }

    private func segmentDurationSeconds(step: PlannedWorkoutStep, paces: EquivalentPaces?) -> Double {
        if step.durationType == .timeSeconds { return step.durationValue }
        let miles = durationToMiles(step.durationType, step.durationValue)
        guard miles > 0 else { return 0 }
        return miles * Self.secondsPerMile(for: step, paces: paces)
    }

    private func segmentDurationSeconds(recovery: PlannedWorkoutRecovery, paces: EquivalentPaces?) -> Double {
        if recovery.durationType == .timeSeconds { return recovery.durationValue }
        let miles = durationToMiles(recovery.durationType, recovery.durationValue)
        guard miles > 0 else { return 0 }
        return miles * Self.secondsPerMile(for: recovery, paces: paces)
    }

    /// Reference runner pace (sec/mi) per named zone — used only when the
    /// athlete pace table isn't available. Mirrors the web side's
    /// REFERENCE_PACE_SEC_PER_MILE so coach-portal estimates agree with iOS.
    fileprivate static let referenceSecPerMile: [NamedPace: Double] = [
        .recovery:  10 * 60 + 30,
        .easy:       9 * 60,
        .longRun:    8 * 60 + 30,
        .moderate:   8 * 60,
        .steady:     7 * 60 + 30,
        .mp:         7 * 60,
        .hm:         6 * 60 + 45,
        .threshold:  6 * 60 + 30,
        .tenK:       6 * 60 + 15,
        .fiveK:      6 * 60,
        .threeK:     5 * 60 + 45,
        .mile:       5 * 60 + 30,
    ]

    /// Label for UI when duration was computed from the reference runner and
    /// still needs to be personalized on the athlete side.
    static let referenceRunnerLabel = "est. for reference runner — personalized on save"

    /// Apply a pace adjustment (percent / s-per-mi / s-per-km) on top of a base
    /// sec/mi pace. Mirrors web `adjustedPaceSecPerMile`.
    fileprivate static func applyAdjustment(_ adjustment: WorkoutPaceAdjustment?, to base: Double) -> Double {
        guard let adj = adjustment, adj.value != 0 else { return base }
        switch adj.type {
        case .percent:        return base * (1 + adj.value / 100)
        case .secondsPerMile: return base + adj.value
        case .secondsPerKm:   return base + adj.value * RaceDistanceConstants.kmPerMile
        }
    }

    /// Resolve sec/mi for an active step. Priority:
    ///   1. Named zone + athlete paces (web-format workouts)
    ///   2. PaceIntensity (% of race pace) + athlete paces (iOS-format workouts)
    ///   3. Named zone + reference table
    ///   4. Step-type fallback (matches the previous hardcoded heuristic)
    fileprivate static func secondsPerMile(for step: PlannedWorkoutStep, paces: EquivalentPaces?) -> Double {
        if let zone = step.paceZone, let paces = paces {
            return applyAdjustment(step.paceAdjustment, to: paces.paceSeconds(for: zone))
        }
        if let intensity = step.targetPaceIntensity, let paces = paces {
            let racePace = Double(paces.goalTimeSeconds) / paces.goalRaceDistance.distanceInMiles
            return intensity.paceSeconds(forRacePace: racePace)
        }
        if let zone = step.paceZone, let ref = referenceSecPerMile[zone] {
            return applyAdjustment(step.paceAdjustment, to: ref)
        }
        switch step.stepType {
        case .warmup, .cooldown: return 9 * 60        // 9:00/mi
        case .recovery:          return 9 * 60 + 30   // 9:30/mi
        case .active:            return 7 * 60        // 7:00/mi
        case .rest:              return 0
        }
    }

    /// Resolve sec/mi for a recovery sub-block.
    fileprivate static func secondsPerMile(for recovery: PlannedWorkoutRecovery, paces: EquivalentPaces?) -> Double {
        if let zone = recovery.paceZone, let paces = paces {
            return applyAdjustment(recovery.paceAdjustment, to: paces.paceSeconds(for: zone))
        }
        if let zone = recovery.paceZone, let ref = referenceSecPerMile[zone] {
            return applyAdjustment(recovery.paceAdjustment, to: ref)
        }
        return 9 * 60 + 30   // 9:30/mi recovery-jog fallback
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
        return miles * RaceDistanceConstants.kmPerMile
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
            steps: {
                let p = AthletePaceProfileService.shared.profile
                return [
                    PlannedWorkoutStep(
                        id: UUID(),
                        stepType: .warmup,
                        durationType: .distanceMiles,
                        durationValue: 2.0,
                        targetPaceIntensity: PaceIntensity.fromLegacyPercentage(70, profile: p),
                        notes: "Easy warm-up",
                        order: 0
                    ),
                    PlannedWorkoutStep(
                        id: UUID(),
                        stepType: .active,
                        durationType: .distanceMiles,
                        durationValue: 4.0,
                        targetPaceIntensity: PaceIntensity.fromLegacyPercentage(87, profile: p),
                        notes: "First fraction - comfortable",
                        order: 1
                    ),
                    PlannedWorkoutStep(
                        id: UUID(),
                        stepType: .active,
                        durationType: .distanceMiles,
                        durationValue: 4.0,
                        targetPaceIntensity: PaceIntensity.fromLegacyPercentage(95, profile: p),
                        notes: "Second fraction - push",
                        order: 2
                    ),
                    PlannedWorkoutStep(
                        id: UUID(),
                        stepType: .cooldown,
                        durationType: .distanceMiles,
                        durationValue: 2.0,
                        targetPaceIntensity: PaceIntensity.fromLegacyPercentage(65, profile: p),
                        notes: "Easy cool-down",
                        order: 3
                    )
                ]
            }(),
            totalDistanceMiles: 12.0,
            estimatedDurationMinutes: 90,
            signatureType: .progressiveTempo,
            createdAt: Date()
        )
    }
}
