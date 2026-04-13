//
//  FitnessAssessmentViewModel.swift
//  RunningLog
//
//  ViewModel for fitness assessment questionnaire and AI analysis.
//

import Foundation
import HealthKit
import os
import SwiftUI

// MARK: - FitnessAssessmentViewModel

@MainActor
@Observable
class FitnessAssessmentViewModel {
    // MARK: - Navigation State

    var currentStep: Int = 1
    let totalSteps = 5

    var isAnalyzing = false
    var analysisProgress: Double = 0
    var analysisStatus: String = ""
    var isComplete = false
    var finalAssessment: FitnessAssessment?

    // MARK: - Step 1: Running History

    var yearsRunning: YearsRunning = .twoToFive
    var currentWeeklyMileage: Double
    var peakWeeklyMileage: Double = 50

    init(currentWeeklyMileage: Double = 30) {
        self.currentWeeklyMileage = currentWeeklyMileage
        self.peakWeeklyMileage = max(50, currentWeeklyMileage * 1.5)
    }
    var runsPerWeek: Int = 5
    var consistencyLevel: ConsistencyLevel = .mostlyConsistent
    var recentInjury: Bool = false
    var injuryDetails: String = ""

    // MARK: - Step 2: Race History

    var hasRacedMarathon: Bool = false
    var marathonPRHours: Int = 4
    var marathonPRMinutes: Int = 0
    var marathonPRSeconds: Int = 0

    var hasRacedHalfMarathon: Bool = false
    var halfPRHours: Int = 1
    var halfPRMinutes: Int = 45
    var halfPRSeconds: Int = 0

    var hasRecent5k: Bool = false
    var hasRecent10k: Bool = false
    var recent5kMinutes: Int = 25
    var recent5kSeconds: Int = 0
    var recent10kMinutes: Int = 52
    var recent10kSeconds: Int = 0

    // MARK: - Step 3: Training Preferences

    var preferredLongRunDay: DayOfWeek = .sunday
    var canRunDoubles: Bool = false
    var hasAccessToTrack: Bool = true
    var preferredWorkoutTypes: [PreferredWorkoutType] = []
    var timeAvailablePerDay: TimeAvailability = .moderate
    var crossTrainingActivities: [CrossTrainingActivity] = []

    // MARK: - Step 4: Goal Assessment

    var goalTimeRealistic: GoalTimeAssessment = .challenging

    // MARK: - Private

    @ObservationIgnored private let analyzer = WorkoutHistoryAnalyzer()
    @ObservationIgnored private var workoutAnalysis: WorkoutHistoryAnalysis?

    // MARK: - Computed Properties

    var marathonPRTotalSeconds: Int? {
        guard hasRacedMarathon else { return nil }
        return marathonPRHours * 3600 + marathonPRMinutes * 60 + marathonPRSeconds
    }

    var halfMarathonPRTotalSeconds: Int? {
        guard hasRacedHalfMarathon else { return nil }
        return halfPRHours * 3600 + halfPRMinutes * 60 + halfPRSeconds
    }

    var recent5kTotalSeconds: Int? {
        guard hasRecent5k, recent5kMinutes > 0 else { return nil }
        return recent5kMinutes * 60 + recent5kSeconds
    }

    var recent10kTotalSeconds: Int? {
        guard hasRecent10k, recent10kMinutes > 0 else { return nil }
        return recent10kMinutes * 60 + recent10kSeconds
    }

    // MARK: - Build Questionnaire

    func buildQuestionnaire() -> FitnessQuestionnaire {
        FitnessQuestionnaire(
            yearsRunning: yearsRunning,
            currentWeeklyMileage: currentWeeklyMileage,
            peakWeeklyMileage: peakWeeklyMileage,
            runsPerWeek: runsPerWeek,
            consistencyLevel: consistencyLevel,
            recentInjury: recentInjury,
            injuryDetails: recentInjury ? injuryDetails : nil,
            hasRacedMarathon: hasRacedMarathon,
            marathonPR: marathonPRTotalSeconds,
            hasRacedHalfMarathon: hasRacedHalfMarathon,
            halfMarathonPR: halfMarathonPRTotalSeconds,
            has5kOr10kRecent: hasRecent5k || hasRecent10k,
            recent5kTime: recent5kTotalSeconds,
            recent10kTime: recent10kTotalSeconds,
            preferredLongRunDay: preferredLongRunDay,
            canRunDoubles: canRunDoubles,
            hasAccessToTrack: hasAccessToTrack,
            preferredWorkoutTypes: preferredWorkoutTypes,
            goalTimeRealistic: goalTimeRealistic,
            timeAvailablePerDay: timeAvailablePerDay,
            crossTrainingActivities: crossTrainingActivities
        )
    }

    // MARK: - Create Basic Assessment (for Skip)

    func createBasicAssessment() -> FitnessAssessment {
        let questionnaire = buildQuestionnaire()
        return FitnessAssessment(
            id: UUID(),
            createdAt: Date(),
            questionnaire: questionnaire,
            workoutAnalysis: nil,
            aiAssessment: nil
        )
    }

    // MARK: - Start Analysis

    func startAnalysis(goalTimeSeconds: Int, raceDate: Date) {
        guard !isAnalyzing else { return }

        isAnalyzing = true
        analysisProgress = 0
        analysisStatus = "Gathering your responses..."

        Task {
            await runAnalysis(goalTimeSeconds: goalTimeSeconds, raceDate: raceDate)
        }
    }

    private func runAnalysis(goalTimeSeconds: Int, raceDate: Date) async {
        // Step 1: Build questionnaire
        await updateProgress(0.1, status: "Processing questionnaire...")
        let questionnaire = buildQuestionnaire()

        // Step 2: Analyze HealthKit workout history
        await updateProgress(0.2, status: "Analyzing workout history...")
        let workoutAnalysis = await analyzer.analyzeWorkoutHistory()

        // Step 3: Calculate weeks until race
        let weeksUntilRace = Calendar.current.dateComponents([.weekOfYear], from: Date(), to: raceDate).weekOfYear ?? 16

        // Step 4: Call AI for assessment
        await updateProgress(0.4, status: "AI analyzing your fitness...")
        let aiAssessment = await getAIAssessment(
            questionnaire: questionnaire,
            workoutAnalysis: workoutAnalysis,
            goalTimeSeconds: goalTimeSeconds,
            weeksUntilRace: weeksUntilRace
        )

        await updateProgress(0.9, status: "Finalizing assessment...")

        // Build final assessment
        let assessment = FitnessAssessment(
            id: UUID(),
            createdAt: Date(),
            questionnaire: questionnaire,
            workoutAnalysis: workoutAnalysis,
            aiAssessment: aiAssessment
        )

        await updateProgress(1.0, status: "Complete!")

        try? await Task.sleep(for: .seconds(0.5))

        finalAssessment = assessment
        isAnalyzing = false
        isComplete = true
    }

    private func updateProgress(_ progress: Double, status: String) async {
        withAnimation {
            analysisProgress = progress
            analysisStatus = status
        }
        try? await Task.sleep(for: .seconds(0.3))
    }

    // MARK: - AI Assessment

    private func getAIAssessment(
        questionnaire: FitnessQuestionnaire,
        workoutAnalysis: WorkoutHistoryAnalysis?,
        goalTimeSeconds: Int,
        weeksUntilRace: Int
    ) async -> AIFitnessAssessment {
        do {
            let request = FitnessAssessmentRequest(
                questionnaire: questionnaire,
                workoutHistory: workoutAnalysis,
                goalRaceDistance: "marathon",
                goalTimeSeconds: goalTimeSeconds,
                weeksUntilRace: weeksUntilRace
            )

            let requestBody: [String: Any] = [
                "assessment_request": try JSONSerialization.jsonObject(
                    with: JSONEncoder().encode(request)
                )
            ]

            let data = try await callEdgeFunction(name: "assess-fitness", body: requestBody)
            let response = try JSONDecoder().decode(AIFitnessAssessment.self, from: data)
            return response
        } catch {
            Log.coach.warning("AI assessment failed, using local analysis: \(error)")
            return analyzer.generateLocalAssessment(
                questionnaire: questionnaire,
                workoutAnalysis: workoutAnalysis,
                goalTimeSeconds: goalTimeSeconds,
                weeksUntilRace: weeksUntilRace
            )
        }
    }
}
