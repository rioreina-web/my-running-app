//
//  WorkoutLibrary.swift
//  RunningLog
//
//  Central singleton containing all workout templates.
//

import Foundation

// MARK: - Workout Library

/// Central repository of all workout templates
final class WorkoutLibrary {

    // MARK: - Singleton

    static let shared = WorkoutLibrary()

    // MARK: - All Templates

    /// All templates in the library
    let allTemplates: [WorkoutTemplate]

    /// Templates indexed by ID for fast lookup
    private let templatesByID: [String: WorkoutTemplate]

    /// Templates indexed by workout type
    private let templatesByType: [ScheduledWorkoutType: [WorkoutTemplate]]

    /// Templates indexed by category
    private let templatesByCategory: [CanovaWorkoutCategory: [WorkoutTemplate]]

    // MARK: - Initialization

    private init() {
        // Combine all templates
        let templates: [WorkoutTemplate] =
            TempoTemplates.all +
            IntervalTemplates.all +
            LongRunTemplates.all +
            EasyRecoveryTemplates.all +
            SpecialTemplates.all +
            SpeedTemplates.all

        self.allTemplates = templates

        // Build indexes
        var byID: [String: WorkoutTemplate] = [:]
        var byType: [ScheduledWorkoutType: [WorkoutTemplate]] = [:]
        var byCategory: [CanovaWorkoutCategory: [WorkoutTemplate]] = [:]

        for template in templates {
            byID[template.id] = template

            var typeList = byType[template.workoutType, default: []]
            typeList.append(template)
            byType[template.workoutType] = typeList

            var categoryList = byCategory[template.category, default: []]
            categoryList.append(template)
            byCategory[template.category] = categoryList
        }

        self.templatesByID = byID
        self.templatesByType = byType
        self.templatesByCategory = byCategory
    }

    // MARK: - Lookup Methods

    /// Get a template by ID
    func template(withID id: String) -> WorkoutTemplate? {
        templatesByID[id]
    }

    /// Get all templates for a workout type
    func templates(forType type: ScheduledWorkoutType) -> [WorkoutTemplate] {
        templatesByType[type] ?? []
    }

    /// Get all templates for a category
    func templates(forCategory category: CanovaWorkoutCategory) -> [WorkoutTemplate] {
        templatesByCategory[category] ?? []
    }

    /// Get all templates valid for a specific race distance and phase
    func templates(
        for raceDistance: RaceDistance,
        phase: CanovaTrainingPhase
    ) -> [WorkoutTemplate] {
        allTemplates.filter { $0.isValid(for: raceDistance, phase: phase) }
    }

    /// Get all templates valid for a specific race distance, phase, and workout type
    func templates(
        for raceDistance: RaceDistance,
        phase: CanovaTrainingPhase,
        type: ScheduledWorkoutType
    ) -> [WorkoutTemplate] {
        templates(forType: type).filter { $0.isValid(for: raceDistance, phase: phase) }
    }

    // MARK: - Template Counts

    /// Total number of templates
    var totalTemplateCount: Int {
        allTemplates.count
    }

    /// Count of templates by workout type
    var templateCountsByType: [ScheduledWorkoutType: Int] {
        templatesByType.mapValues { $0.count }
    }

    /// Count of templates by category
    var templateCountsByCategory: [CanovaWorkoutCategory: Int] {
        templatesByCategory.mapValues { $0.count }
    }

    // MARK: - Debug/Summary

    /// Print a summary of the library contents
    func printSummary() {
        print("=== Workout Library Summary ===")
        print("Total templates: \(totalTemplateCount)")
        print()
        print("By Workout Type:")
        for (type, templates) in templatesByType.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            print("  \(type.displayName): \(templates.count)")
        }
        print()
        print("By Category:")
        for (category, templates) in templatesByCategory.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            print("  \(category.displayName): \(templates.count)")
        }
        print()
        print("By Race Distance Compatibility:")
        for distance in RaceDistance.allCases {
            let count = allTemplates.filter { $0.raceDistances.contains(distance) }.count
            print("  \(distance.displayName): \(count)")
        }
    }
}

// MARK: - Template Filtering Extensions

extension Array where Element == WorkoutTemplate {
    /// Filter templates by race distance
    func forRaceDistance(_ distance: RaceDistance) -> [WorkoutTemplate] {
        filter { $0.raceDistances.contains(distance) }
    }

    /// Filter templates by phase
    func forPhase(_ phase: CanovaTrainingPhase) -> [WorkoutTemplate] {
        filter { $0.phases.contains(phase) }
    }

    /// Filter templates by workout type
    func forWorkoutType(_ type: ScheduledWorkoutType) -> [WorkoutTemplate] {
        filter { $0.workoutType == type }
    }

    /// Filter templates by category
    func forCategory(_ category: CanovaWorkoutCategory) -> [WorkoutTemplate] {
        filter { $0.category == category }
    }

    /// Exclude specific template IDs (for variety)
    func excluding(ids: Set<String>) -> [WorkoutTemplate] {
        filter { !ids.contains($0.id) }
    }
}
