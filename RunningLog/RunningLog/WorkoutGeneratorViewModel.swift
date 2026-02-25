//
//  WorkoutGeneratorViewModel.swift
//  RunningLog
//
//  View model for the Canova-inspired AI workout generator.
//

import Auth
import Foundation
import os
import Supabase
import SwiftUI

// MARK: - WorkoutGeneratorViewModel

@Observable
final class WorkoutGeneratorViewModel {
    // MARK: - State

    var activeGoal: UserGoal?
    var marathonGoalTime: Int? // Goal time in seconds
    var weeksUntilRace: Int = 0
    var currentPhase: CanovaTrainingPhase = .base

    var generatedWorkouts: [CanovaWorkout] = []
    var selectedWorkout: CanovaWorkout?

    var isLoadingGoal = false
    var isGenerating = false
    var errorMessage: String?
    var showError = false

    // MARK: - Computed Properties

    /// Race pace in seconds per mile (for display calculations)
    var racePaceSecondsPerMile: Double? {
        guard let goalTime = marathonGoalTime else { return nil }
        // Marathon = 26.2188 miles
        return Double(goalTime) / 26.2188
    }

    /// Formatted race pace string
    var formattedRacePace: String? {
        guard let pace = racePaceSecondsPerMile else { return nil }
        let totalSecs = Int(pace.rounded())
        let mins = totalSecs / 60
        let secs = totalSecs % 60
        return "\(mins):\(String(format: "%02d", secs))/mi"
    }

    /// Formatted goal time string
    var formattedGoalTime: String? {
        guard let time = marathonGoalTime else { return nil }
        let hours = time / 3600
        let mins = (time % 3600) / 60
        let secs = time % 60
        if secs > 0 {
            return String(format: "%d:%02d:%02d", hours, mins, secs)
        }
        return String(format: "%d:%02d", hours, mins)
    }

    // MARK: - Initialization

    init() {}

    // MARK: - Load Goal

    @MainActor
    func loadActiveGoal() async {
        isLoadingGoal = true
        errorMessage = nil

        do {
            // Fetch active goals ordered by target date
            let response: [UserGoal] = try await supabase
                .from("user_goals")
                .select()
                .eq("status", value: "active")
                .order("target_date", ascending: true)
                .execute()
                .value

            if let goal = response.first {
                activeGoal = goal
                calculatePhase(for: goal)
                parseGoalTime(from: goal.goalTitle)
            }

            isLoadingGoal = false
        } catch {
            Log.coach.error("Failed to load goal: \(error)")
            isLoadingGoal = false
            errorMessage = "Failed to load your goal"
            showError = true
        }
    }

    // MARK: - Phase Calculation

    private func calculatePhase(for goal: UserGoal) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let targetDate = calendar.startOfDay(for: goal.targetDate)
        let weeks = calendar.dateComponents([.weekOfYear], from: today, to: targetDate).weekOfYear ?? 0
        weeksUntilRace = max(0, weeks)
        currentPhase = CanovaTrainingPhase.fromWeeksOut(weeksUntilRace)
    }

    // MARK: - Parse Goal Time

    /// Attempts to parse a marathon goal time from the goal title
    /// Supports formats like "3:30", "3:30:00", "Boston Marathon 3:15"
    private func parseGoalTime(from title: String) {
        // Look for time pattern (H:MM or H:MM:SS)
        let patterns = [
            #"(\d{1,2}):(\d{2}):(\d{2})"#, // H:MM:SS
            #"(\d{1,2}):(\d{2})"# // H:MM
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title))
            {
                if pattern.contains(":SS") || match.numberOfRanges == 4 {
                    // H:MM:SS format
                    if let hoursRange = Range(match.range(at: 1), in: title),
                       let minsRange = Range(match.range(at: 2), in: title),
                       let secsRange = Range(match.range(at: 3), in: title),
                       let hours = Int(title[hoursRange]),
                       let mins = Int(title[minsRange]),
                       let secs = Int(title[secsRange])
                    {
                        marathonGoalTime = hours * 3600 + mins * 60 + secs
                        return
                    }
                } else {
                    // H:MM format
                    if let hoursRange = Range(match.range(at: 1), in: title),
                       let minsRange = Range(match.range(at: 2), in: title),
                       let hours = Int(title[hoursRange]),
                       let mins = Int(title[minsRange])
                    {
                        marathonGoalTime = hours * 3600 + mins * 60
                        return
                    }
                }
            }
        }

        // Default to 4:00 marathon if no time found
        marathonGoalTime = 4 * 3600
    }

    // MARK: - Generate Workout

    @MainActor
    func generateWorkout(category: CanovaWorkoutCategory) async {
        guard let goalTime = marathonGoalTime else {
            errorMessage = "Please set a goal time first"
            showError = true
            return
        }

        isGenerating = true
        errorMessage = nil

        // Build request
        let request = WorkoutGenerationRequest(
            userId: AuthManager.shared.currentUserId ?? "",
            goalRaceDistance: "marathon",
            goalTimeSeconds: goalTime,
            targetDate: activeGoal?.targetDate ?? Date().addingTimeInterval(86400 * 84), // 12 weeks default
            weeksUntilRace: weeksUntilRace,
            currentPhase: currentPhase.rawValue,
            currentWeeklyMileage: nil,
            preferredWorkoutType: category.rawValue,
            fitnessLevel: nil
        )

        do {
            guard let url = URL(string: "\(supabaseURL)/functions/v1/workout-generator") else {
                throw NSError(domain: "WorkoutGenerator", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
            }

            var urlRequest = URLRequest(url: url)
            urlRequest.httpMethod = "POST"
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let token = (try? await supabase.auth.session)?.accessToken ?? supabaseAnonKey
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            urlRequest.httpBody = try encoder.encode(request)

            let (data, response) = try await URLSession.shared.data(for: urlRequest)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw NSError(domain: "WorkoutGenerator", code: -2, userInfo: [NSLocalizedDescriptionKey: "Server error"])
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let workoutResponse = try decoder.decode(WorkoutGenerationResponse.self, from: data)

            if let error = workoutResponse.error {
                throw NSError(domain: "WorkoutGenerator", code: -3, userInfo: [NSLocalizedDescriptionKey: error])
            }

            if let workout = workoutResponse.workout {
                generatedWorkouts.insert(workout, at: 0)
                selectedWorkout = workout
                Log.coach.info("Generated workout: \(workout.name)")
            }

            isGenerating = false
        } catch {
            Log.coach.error("Failed to generate workout: \(error)")
            isGenerating = false
            errorMessage = "Failed to generate workout. Please try again."
            showError = true
        }
    }

    // MARK: - Generate Quick Workout (Local)

    /// Generates a sample workout locally without calling the backend
    /// Useful for testing or when backend is unavailable
    @MainActor
    func generateQuickWorkout(signatureType: CanovaSignatureType) {
        guard let goalTime = marathonGoalTime else {
            errorMessage = "Please set a goal time first"
            showError = true
            return
        }

        isGenerating = true

        // Simulate async delay
        Task {
            try? await Task.sleep(for: .milliseconds(500))

            let workout = createLocalWorkout(type: signatureType, goalTime: goalTime)
            generatedWorkouts.insert(workout, at: 0)
            selectedWorkout = workout
            isGenerating = false
        }
    }

    private func createLocalWorkout(type: CanovaSignatureType, goalTime: Int) -> CanovaWorkout {
        switch type {
        case .progressiveTempo:
            // 2mi warmup + 4mi + 4mi + 2mi cooldown = 12mi
            return CanovaWorkout(
                id: UUID(),
                name: "Progressive Tempo",
                category: .special,
                trainingPhase: currentPhase,
                description: "Build aerobic capacity with progressive intensity through fractions",
                steps: [
                    CanovaWorkoutStep(id: UUID(), stepType: .warmup, durationType: .distanceMiles, durationValue: 2.0, targetPaceIntensity: PaceIntensity(percentage: 70), notes: "Easy warm-up", order: 0),
                    CanovaWorkoutStep(id: UUID(), stepType: .active, durationType: .distanceMiles, durationValue: 4.0, targetPaceIntensity: PaceIntensity(percentage: 87), notes: "First fraction - comfortable aerobic", order: 1),
                    CanovaWorkoutStep(id: UUID(), stepType: .active, durationType: .distanceMiles, durationValue: 4.0, targetPaceIntensity: PaceIntensity(percentage: 95), notes: "Second fraction - moderate push", order: 2),
                    CanovaWorkoutStep(id: UUID(), stepType: .cooldown, durationType: .distanceMiles, durationValue: 2.0, targetPaceIntensity: PaceIntensity(percentage: 65), notes: "Easy cool-down", order: 3),
                ],
                totalDistanceMiles: 12.0,
                estimatedDurationMinutes: 90,
                signatureType: .progressiveTempo,
                createdAt: Date()
            )

        case .descendingLadder:
            // 2mi warmup + (4+3+2.5+2+1.5+1)mi + 2mi cooldown = 18mi
            return CanovaWorkout(
                id: UUID(),
                name: "Descending Ladder",
                category: .special,
                trainingPhase: currentPhase,
                description: "4+3+2.5+2+1.5+1 miles with 0.5mi float recovery between each",
                steps: [
                    CanovaWorkoutStep(id: UUID(), stepType: .warmup, durationType: .distanceMiles, durationValue: 2.0, targetPaceIntensity: PaceIntensity(percentage: 70), notes: "Easy warm-up", order: 0),
                    CanovaWorkoutStep(id: UUID(), stepType: .active, durationType: .distanceMiles, durationValue: 4.0, targetPaceIntensity: PaceIntensity(percentage: 92), notes: "4mi @ 92%", order: 1),
                    CanovaWorkoutStep(id: UUID(), stepType: .recovery, durationType: .distanceMiles, durationValue: 0.5, targetPaceIntensity: PaceIntensity(percentage: 75), notes: "Float recovery", order: 2),
                    CanovaWorkoutStep(id: UUID(), stepType: .active, durationType: .distanceMiles, durationValue: 3.0, targetPaceIntensity: PaceIntensity(percentage: 95), notes: "3mi @ 95%", order: 3),
                    CanovaWorkoutStep(id: UUID(), stepType: .recovery, durationType: .distanceMiles, durationValue: 0.5, targetPaceIntensity: PaceIntensity(percentage: 75), notes: "Float recovery", order: 4),
                    CanovaWorkoutStep(id: UUID(), stepType: .active, durationType: .distanceMiles, durationValue: 2.5, targetPaceIntensity: PaceIntensity(percentage: 98), notes: "2.5mi @ 98%", order: 5),
                    CanovaWorkoutStep(id: UUID(), stepType: .recovery, durationType: .distanceMiles, durationValue: 0.5, targetPaceIntensity: PaceIntensity(percentage: 75), notes: "Float recovery", order: 6),
                    CanovaWorkoutStep(id: UUID(), stepType: .active, durationType: .distanceMiles, durationValue: 2.0, targetPaceIntensity: PaceIntensity(percentage: 100), notes: "2mi @ race pace", order: 7),
                    CanovaWorkoutStep(id: UUID(), stepType: .recovery, durationType: .distanceMiles, durationValue: 0.5, targetPaceIntensity: PaceIntensity(percentage: 75), notes: "Float recovery", order: 8),
                    CanovaWorkoutStep(id: UUID(), stepType: .active, durationType: .distanceMiles, durationValue: 1.5, targetPaceIntensity: PaceIntensity(percentage: 102), notes: "1.5mi @ 102%", order: 9),
                    CanovaWorkoutStep(id: UUID(), stepType: .recovery, durationType: .distanceMiles, durationValue: 0.5, targetPaceIntensity: PaceIntensity(percentage: 75), notes: "Float recovery", order: 10),
                    CanovaWorkoutStep(id: UUID(), stepType: .active, durationType: .distanceMiles, durationValue: 1.0, targetPaceIntensity: PaceIntensity(percentage: 105), notes: "1mi fast finish", order: 11),
                    CanovaWorkoutStep(id: UUID(), stepType: .cooldown, durationType: .distanceMiles, durationValue: 2.0, targetPaceIntensity: PaceIntensity(percentage: 65), notes: "Easy cool-down", order: 12),
                ],
                totalDistanceMiles: 20.5,
                estimatedDurationMinutes: 120,
                signatureType: .descendingLadder,
                createdAt: Date()
            )

        case .racePaceRepeats:
            // 2mi warmup + 6x1mi @ MP w/0.5mi recovery + 2mi cooldown = 13mi
            return CanovaWorkout(
                id: UUID(),
                name: "Race-Pace Repeats",
                category: .specific,
                trainingPhase: currentPhase,
                description: "6x1mi @ MP with 0.5mi float recovery",
                steps: [
                    CanovaWorkoutStep(id: UUID(), stepType: .warmup, durationType: .distanceMiles, durationValue: 2.0, targetPaceIntensity: PaceIntensity(percentage: 70), notes: "Easy warm-up", order: 0),
                    CanovaWorkoutStep(id: UUID(), stepType: .active, durationType: .distanceMiles, durationValue: 1.0, targetPaceIntensity: PaceIntensity(percentage: 100), notes: "Rep 1 @ MP", order: 1),
                    CanovaWorkoutStep(id: UUID(), stepType: .recovery, durationType: .distanceMiles, durationValue: 0.5, targetPaceIntensity: PaceIntensity(percentage: 75), notes: "Float recovery", order: 2),
                    CanovaWorkoutStep(id: UUID(), stepType: .active, durationType: .distanceMiles, durationValue: 1.0, targetPaceIntensity: PaceIntensity(percentage: 100), notes: "Rep 2 @ MP", order: 3),
                    CanovaWorkoutStep(id: UUID(), stepType: .recovery, durationType: .distanceMiles, durationValue: 0.5, targetPaceIntensity: PaceIntensity(percentage: 75), notes: "Float recovery", order: 4),
                    CanovaWorkoutStep(id: UUID(), stepType: .active, durationType: .distanceMiles, durationValue: 1.0, targetPaceIntensity: PaceIntensity(percentage: 100), notes: "Rep 3 @ MP", order: 5),
                    CanovaWorkoutStep(id: UUID(), stepType: .recovery, durationType: .distanceMiles, durationValue: 0.5, targetPaceIntensity: PaceIntensity(percentage: 75), notes: "Float recovery", order: 6),
                    CanovaWorkoutStep(id: UUID(), stepType: .active, durationType: .distanceMiles, durationValue: 1.0, targetPaceIntensity: PaceIntensity(percentage: 100), notes: "Rep 4 @ MP", order: 7),
                    CanovaWorkoutStep(id: UUID(), stepType: .recovery, durationType: .distanceMiles, durationValue: 0.5, targetPaceIntensity: PaceIntensity(percentage: 75), notes: "Float recovery", order: 8),
                    CanovaWorkoutStep(id: UUID(), stepType: .active, durationType: .distanceMiles, durationValue: 1.0, targetPaceIntensity: PaceIntensity(percentage: 100), notes: "Rep 5 @ MP", order: 9),
                    CanovaWorkoutStep(id: UUID(), stepType: .recovery, durationType: .distanceMiles, durationValue: 0.5, targetPaceIntensity: PaceIntensity(percentage: 75), notes: "Float recovery", order: 10),
                    CanovaWorkoutStep(id: UUID(), stepType: .active, durationType: .distanceMiles, durationValue: 1.0, targetPaceIntensity: PaceIntensity(percentage: 102), notes: "Rep 6 - strong finish!", order: 11),
                    CanovaWorkoutStep(id: UUID(), stepType: .cooldown, durationType: .distanceMiles, durationValue: 2.0, targetPaceIntensity: PaceIntensity(percentage: 65), notes: "Easy cool-down", order: 12),
                ],
                totalDistanceMiles: 12.5,
                estimatedDurationMinutes: 90,
                signatureType: .racePaceRepeats,
                createdAt: Date()
            )

        case .specialBlock:
            // AM: 2mi warmup + 6mi tempo + 2mi cooldown = 10mi
            return CanovaWorkout(
                id: UUID(),
                name: "Special Block (AM Session)",
                category: .special,
                trainingPhase: currentPhase,
                description: "Morning tempo session - part of AM/PM double day",
                steps: [
                    CanovaWorkoutStep(id: UUID(), stepType: .warmup, durationType: .distanceMiles, durationValue: 2.0, targetPaceIntensity: PaceIntensity(percentage: 70), notes: "Easy warm-up", order: 0),
                    CanovaWorkoutStep(id: UUID(), stepType: .active, durationType: .distanceMiles, durationValue: 6.0, targetPaceIntensity: PaceIntensity(percentage: 88), notes: "Steady tempo @ 88%", order: 1),
                    CanovaWorkoutStep(id: UUID(), stepType: .cooldown, durationType: .distanceMiles, durationValue: 2.0, targetPaceIntensity: PaceIntensity(percentage: 65), notes: "Easy cool-down", order: 2),
                ],
                totalDistanceMiles: 10.0,
                estimatedDurationMinutes: 70,
                signatureType: .specialBlock,
                createdAt: Date()
            )

        case .longRunWithTempo:
            // 14mi easy + 4mi tempo + 2mi cooldown = 20mi
            return CanovaWorkout(
                id: UUID(),
                name: "Long Run with Tempo Finish",
                category: .fundamental,
                trainingPhase: currentPhase,
                description: "Endurance builder with progressive tempo in final miles",
                steps: [
                    CanovaWorkoutStep(id: UUID(), stepType: .active, durationType: .distanceMiles, durationValue: 14.0, targetPaceIntensity: PaceIntensity(percentage: 75), notes: "Easy long run pace", order: 0),
                    CanovaWorkoutStep(id: UUID(), stepType: .active, durationType: .distanceMiles, durationValue: 4.0, targetPaceIntensity: PaceIntensity(percentage: 88), notes: "Tempo finish @ 88%", order: 1),
                    CanovaWorkoutStep(id: UUID(), stepType: .cooldown, durationType: .distanceMiles, durationValue: 2.0, targetPaceIntensity: PaceIntensity(percentage: 65), notes: "Easy cool-down", order: 2),
                ],
                totalDistanceMiles: 20.0,
                estimatedDurationMinutes: 150,
                signatureType: .longRunWithTempo,
                createdAt: Date()
            )
        }
    }

    // MARK: - Clear Selection

    func clearSelection() {
        selectedWorkout = nil
    }

    // MARK: - Delete Workout

    func deleteWorkout(_ workout: CanovaWorkout) {
        generatedWorkouts.removeAll { $0.id == workout.id }
        if selectedWorkout?.id == workout.id {
            selectedWorkout = nil
        }
    }
}
