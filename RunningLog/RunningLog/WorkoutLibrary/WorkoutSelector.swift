//
//  WorkoutSelector.swift
//  RunningLog
//
//  Intelligent workout selection algorithm.
//

import Foundation

// MARK: - Workout Selector

/// Selects appropriate workouts from the library based on context
final class WorkoutSelector {

    // MARK: - Singleton

    static let shared = WorkoutSelector()

    // MARK: - Dependencies

    private let library = WorkoutLibrary.shared

    // MARK: - Selection Result

    struct SelectionResult {
        let template: WorkoutTemplate
        let progression: Double
        let workout: CanovaWorkout
    }

    // MARK: - Main Selection Method

    /// Select and build a workout for the given context
    func selectWorkout(
        raceDistance: RaceDistance,
        phase: CanovaTrainingPhase,
        weekInPhase: Int,
        totalWeeksInPhase: Int,
        dayOfWeek: Int,  // 1 = Sunday, 7 = Saturday
        scheduledType: ScheduledWorkoutType,
        recentTemplateIDs: Set<String>,  // Templates used in last 2 weeks
        isRecoveryWeek: Bool,
        goalTimeSeconds: Int,
        weeklyMileage: Double
    ) -> SelectionResult? {
        // Calculate progression through phase (0.0 - 1.0)
        let progression = calculateProgression(
            weekInPhase: weekInPhase,
            totalWeeksInPhase: totalWeeksInPhase,
            isRecoveryWeek: isRecoveryWeek
        )

        // Get candidate templates
        var candidates = library.templates(
            for: raceDistance,
            phase: phase,
            type: scheduledType
        )

        // If no candidates for exact type, fall back to related types
        if candidates.isEmpty {
            candidates = getFallbackTemplates(
                raceDistance: raceDistance,
                phase: phase,
                type: scheduledType
            )
        }

        // Still no candidates? Return nil
        guard !candidates.isEmpty else {
            return nil
        }

        // Filter for recovery week if applicable
        if isRecoveryWeek {
            let recoveryFriendly = candidates.filter { template in
                template.progressionType == .static_ ||
                template.category == .regeneration ||
                template.category == .fundamental
            }
            if !recoveryFriendly.isEmpty {
                candidates = recoveryFriendly
            }
        }

        // Score and rank candidates
        let scored = candidates.map { template -> (WorkoutTemplate, Double) in
            let score = scoreTemplate(
                template,
                recentIDs: recentTemplateIDs,
                dayOfWeek: dayOfWeek,
                phase: phase,
                isRecoveryWeek: isRecoveryWeek
            )
            return (template, score)
        }.sorted { $0.1 > $1.1 }

        // Select from top candidates (with some randomness for variety)
        let selectedTemplate = selectFromTopCandidates(scored)

        // Build the workout
        let workout = selectedTemplate.buildWorkout(
            progression: progression,
            goalTimeSeconds: goalTimeSeconds,
            weeklyMileage: weeklyMileage,
            raceDistance: raceDistance,
            phase: phase
        )

        return SelectionResult(
            template: selectedTemplate,
            progression: progression,
            workout: workout
        )
    }

    // MARK: - Long Run Selection

    /// Select a long run template with rotation support
    func selectLongRun(
        raceDistance: RaceDistance,
        phase: CanovaTrainingPhase,
        weekInPhase: Int,
        totalWeeksInPhase: Int,
        recentTemplateIDs: Set<String>,
        isRecoveryWeek: Bool,
        goalTimeSeconds: Int,
        weeklyMileage: Double
    ) -> SelectionResult? {
        let progression = calculateProgression(
            weekInPhase: weekInPhase,
            totalWeeksInPhase: totalWeeksInPhase,
            isRecoveryWeek: isRecoveryWeek
        )

        var candidates = library.templates(
            for: raceDistance,
            phase: phase,
            type: .longRun
        )

        guard !candidates.isEmpty else { return nil }

        // Recovery week: prefer cutback or easy long
        if isRecoveryWeek {
            let easierOptions = candidates.filter {
                $0.id == "long_cutback" || $0.id == "long_easy"
            }
            if !easierOptions.isEmpty {
                candidates = easierOptions
            }
        }

        // In specific phase, prefer race-pace long runs more often
        if phase == .specific && !isRecoveryWeek {
            let racePaceOptions = candidates.filter {
                $0.id.contains("mp") || $0.id.contains("race") || $0.id.contains("fast")
            }
            // 60% chance to pick race-pace long run in specific phase
            if !racePaceOptions.isEmpty && Double.random(in: 0...1) < 0.6 {
                candidates = racePaceOptions
            }
        }

        // Prefer templates not used recently
        let freshCandidates = candidates.excluding(ids: recentTemplateIDs)
        if !freshCandidates.isEmpty {
            candidates = freshCandidates
        }

        // Random selection from remaining candidates
        guard let template = candidates.randomElement() else { return nil }

        let workout = template.buildWorkout(
            progression: progression,
            goalTimeSeconds: goalTimeSeconds,
            weeklyMileage: weeklyMileage,
            raceDistance: raceDistance,
            phase: phase
        )

        return SelectionResult(template: template, progression: progression, workout: workout)
    }

    // MARK: - Easy Run Selection

    /// Select an easy/recovery run template
    func selectEasyRun(
        raceDistance: RaceDistance,
        phase: CanovaTrainingPhase,
        weekInPhase: Int,
        totalWeeksInPhase: Int,
        includeStrides: Bool,
        isDoubleDay: Bool,
        isAM: Bool,
        goalTimeSeconds: Int,
        weeklyMileage: Double
    ) -> SelectionResult? {
        let progression = calculateProgression(
            weekInPhase: weekInPhase,
            totalWeeksInPhase: totalWeeksInPhase,
            isRecoveryWeek: false
        )

        var templateID: String

        if isDoubleDay {
            templateID = isAM ? "easy_am_double" : "easy_pm_double"
        } else if includeStrides {
            templateID = "easy_strides"
        } else {
            // Randomly pick between easy and aerobic runs
            templateID = Bool.random() ? "easy_run" : "easy_aerobic"
        }

        guard let template = library.template(withID: templateID) else {
            // Fallback to basic easy run
            guard let fallback = library.template(withID: "easy_run") else { return nil }
            let workout = fallback.buildWorkout(
                progression: progression,
                goalTimeSeconds: goalTimeSeconds,
                weeklyMileage: weeklyMileage,
                raceDistance: raceDistance,
                phase: phase
            )
            return SelectionResult(template: fallback, progression: progression, workout: workout)
        }

        let workout = template.buildWorkout(
            progression: progression,
            goalTimeSeconds: goalTimeSeconds,
            weeklyMileage: weeklyMileage,
            raceDistance: raceDistance,
            phase: phase
        )

        return SelectionResult(template: template, progression: progression, workout: workout)
    }

    // MARK: - Recovery Run Selection

    /// Select a recovery run template
    func selectRecoveryRun(
        raceDistance: RaceDistance,
        phase: CanovaTrainingPhase,
        weekInPhase: Int,
        totalWeeksInPhase: Int,
        goalTimeSeconds: Int,
        weeklyMileage: Double
    ) -> SelectionResult? {
        let progression = calculateProgression(
            weekInPhase: weekInPhase,
            totalWeeksInPhase: totalWeeksInPhase,
            isRecoveryWeek: false
        )

        let templateID = Bool.random() ? "easy_recovery" : "easy_recovery_strides"

        guard let template = library.template(withID: templateID) else { return nil }

        let workout = template.buildWorkout(
            progression: progression,
            goalTimeSeconds: goalTimeSeconds,
            weeklyMileage: weeklyMileage,
            raceDistance: raceDistance,
            phase: phase
        )

        return SelectionResult(template: template, progression: progression, workout: workout)
    }

    // MARK: - Helper Methods

    private func calculateProgression(
        weekInPhase: Int,
        totalWeeksInPhase: Int,
        isRecoveryWeek: Bool
    ) -> Double {
        if isRecoveryWeek {
            // Recovery weeks use lower progression
            return max(0, Double(weekInPhase - 1) / Double(max(1, totalWeeksInPhase - 1))) * 0.7
        }

        // Normal linear progression through phase
        return min(1.0, Double(weekInPhase) / Double(max(1, totalWeeksInPhase)))
    }

    private func getFallbackTemplates(
        raceDistance: RaceDistance,
        phase: CanovaTrainingPhase,
        type: ScheduledWorkoutType
    ) -> [WorkoutTemplate] {
        // Map workout types to related categories
        switch type {
        case .tempo:
            return library.templates(forCategory: .special)
                .forRaceDistance(raceDistance)
                .forPhase(phase)
        case .intervals:
            return library.templates(forCategory: .specific)
                .forRaceDistance(raceDistance)
                .forPhase(phase)
        case .progression:
            return library.templates(forType: .tempo)
                .forRaceDistance(raceDistance)
                .forPhase(phase)
        default:
            return []
        }
    }

    private func scoreTemplate(
        _ template: WorkoutTemplate,
        recentIDs: Set<String>,
        dayOfWeek: Int,
        phase: CanovaTrainingPhase,
        isRecoveryWeek: Bool
    ) -> Double {
        var score = 1.0

        // Penalty for recently used templates
        if recentIDs.contains(template.id) {
            score *= 0.3
        }

        // Bonus for phase-appropriate intensity
        if phase == .specific && template.category == .specific {
            score *= 1.3
        } else if phase == .support && template.category == .special {
            score *= 1.25
        } else if phase == .base && template.category == .fundamental {
            score *= 1.2
        } else if phase == .taper && template.progressionType == .static_ {
            score *= 1.3
        }

        // Recovery week preferences
        if isRecoveryWeek {
            if template.progressionType == .static_ {
                score *= 1.4
            }
            if template.category == .regeneration {
                score *= 1.3
            }
        }

        // Small random factor for variety
        score *= Double.random(in: 0.9...1.1)

        return score
    }

    private func selectFromTopCandidates(_ scored: [(WorkoutTemplate, Double)]) -> WorkoutTemplate {
        // Take top 3 candidates (or all if fewer)
        let topCount = min(3, scored.count)
        let topCandidates = Array(scored.prefix(topCount))

        // Weighted random selection based on scores
        let totalScore = topCandidates.reduce(0) { $0 + $1.1 }
        let random = Double.random(in: 0..<totalScore)

        var cumulative = 0.0
        for (template, score) in topCandidates {
            cumulative += score
            if random < cumulative {
                return template
            }
        }

        // Fallback to first (highest scored)
        return topCandidates.first!.0
    }
}

// MARK: - Workout Type Mapping

extension WorkoutSelector {
    /// Map day of week and context to preferred workout type
    static func preferredWorkoutType(
        forDay dayOfWeek: Int,
        phase: CanovaTrainingPhase,
        raceDistance: RaceDistance,
        isRecoveryWeek: Bool
    ) -> ScheduledWorkoutType {
        // 1 = Sunday, 2 = Monday, ..., 7 = Saturday

        if isRecoveryWeek {
            // Recovery week: easier schedule
            switch dayOfWeek {
            case 1: return .longRun  // Sunday - shorter long run
            case 2: return .rest
            case 3: return .easy
            case 4: return .recovery
            case 5: return .easy
            case 6: return .recovery
            case 7: return .strides
            default: return .easy
            }
        }

        switch dayOfWeek {
        case 1:  // Sunday - Long run day
            return .longRun
        case 2:  // Monday - Recovery after long run
            return .recovery
        case 3:  // Tuesday - Quality day 1
            return phase == .specific ? .intervals : .tempo
        case 4:  // Wednesday - Easy or recovery
            return .easy
        case 5:  // Thursday - Quality day 2
            return phase == .specific ? .tempo : .strides
        case 6:  // Friday - Recovery/easy before long run
            return .recovery
        case 7:  // Saturday - Pre-long run easy
            return .strides
        default:
            return .easy
        }
    }
}
