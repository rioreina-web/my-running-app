//
//  FitnessAssessmentViewModel.swift
//  RunningLog
//
//  ViewModel for fitness assessment questionnaire and AI analysis.
//

import Combine
import Foundation
import HealthKit
import os
import SwiftUI

// MARK: - FitnessAssessmentViewModel

@MainActor
class FitnessAssessmentViewModel: ObservableObject {
    // MARK: - Navigation State

    @Published var currentStep: Int = 1
    let totalSteps = 5

    @Published var isAnalyzing = false
    @Published var analysisProgress: Double = 0
    @Published var analysisStatus: String = ""
    @Published var isComplete = false
    @Published var finalAssessment: FitnessAssessment?

    // MARK: - Step 1: Running History

    @Published var yearsRunning: YearsRunning = .twoToFive
    @Published var currentWeeklyMileage: Double = 30
    @Published var peakWeeklyMileage: Double = 50
    @Published var runsPerWeek: Int = 5
    @Published var consistencyLevel: ConsistencyLevel = .mostlyConsistent
    @Published var recentInjury: Bool = false
    @Published var injuryDetails: String = ""

    // MARK: - Step 2: Race History

    @Published var hasRacedMarathon: Bool = false
    @Published var marathonPRHours: Int = 4
    @Published var marathonPRMinutes: Int = 0
    @Published var marathonPRSeconds: Int = 0

    @Published var hasRacedHalfMarathon: Bool = false
    @Published var halfPRHours: Int = 1
    @Published var halfPRMinutes: Int = 45
    @Published var halfPRSeconds: Int = 0

    @Published var has5kOr10kRecent: Bool = false
    @Published var recent5kMinutes: Int = 25
    @Published var recent5kSeconds: Int = 0
    @Published var recent10kMinutes: Int = 52
    @Published var recent10kSeconds: Int = 0

    // MARK: - Step 3: Training Preferences

    @Published var preferredLongRunDay: DayOfWeek = .sunday
    @Published var canRunDoubles: Bool = false
    @Published var hasAccessToTrack: Bool = true
    @Published var preferredWorkoutTypes: [PreferredWorkoutType] = []
    @Published var timeAvailablePerDay: TimeAvailability = .moderate
    @Published var crossTrainingActivities: [CrossTrainingActivity] = []

    // MARK: - Step 4: Goal Assessment

    @Published var goalTimeRealistic: GoalTimeAssessment = .challenging

    // MARK: - Private

    private let healthKitManager = HealthKitManager.shared
    private var workoutAnalysis: WorkoutHistoryAnalysis?

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
        guard has5kOr10kRecent, recent5kMinutes > 0 else { return nil }
        return recent5kMinutes * 60 + recent5kSeconds
    }

    var recent10kTotalSeconds: Int? {
        guard has5kOr10kRecent, recent10kMinutes > 0 else { return nil }
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
            has5kOr10kRecent: has5kOr10kRecent,
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
        let workoutAnalysis = await analyzeWorkoutHistory()

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

        try? await Task.sleep(nanoseconds: 500_000_000) // Brief pause to show completion

        await MainActor.run {
            self.finalAssessment = assessment
            self.isAnalyzing = false
            self.isComplete = true
        }
    }

    @MainActor
    private func updateProgress(_ progress: Double, status: String) async {
        withAnimation {
            analysisProgress = progress
            analysisStatus = status
        }
        try? await Task.sleep(nanoseconds: 300_000_000) // Small delay for visual feedback
    }

    // MARK: - Analyze Workout History

    private func analyzeWorkoutHistory() async -> WorkoutHistoryAnalysis? {
        // Fetch workouts from HealthKit (last 90 days)
        let endDate = Date()
        guard let startDate = Calendar.current.date(byAdding: .day, value: -90, to: endDate) else {
            return nil
        }

        let workouts = await fetchHealthKitWorkouts(from: startDate, to: endDate)

        guard !workouts.isEmpty else {
            Log.coach.info("No HealthKit workouts found for analysis")
            return nil
        }

        Log.coach.info("Analyzing \(workouts.count) workouts from HealthKit")

        // Calculate weekly mileage stats
        let weeklyMileageStats = calculateWeeklyMileageStats(workouts: workouts)

        // Calculate pace progression
        let paceProgression = calculatePaceProgression(workouts: workouts)

        // Workout type breakdown
        let typeBreakdown = calculateWorkoutTypeBreakdown(workouts: workouts)

        // Consistency score
        let consistencyScore = calculateConsistencyScore(workouts: workouts, dayCount: 90)

        // Longest run
        let longestRun = findLongestRun(workouts: workouts)

        // Recent trend
        let recentTrend = weeklyMileageStats.trend

        return WorkoutHistoryAnalysis(
            analyzedWorkouts: workouts.count,
            dateRange: WorkoutHistoryAnalysis.DateRange(start: startDate, end: endDate),
            weeklyMileageStats: weeklyMileageStats,
            paceProgression: paceProgression,
            workoutTypeBreakdown: typeBreakdown,
            consistencyScore: consistencyScore,
            longestRun: longestRun,
            recentTrend: recentTrend
        )
    }

    private func fetchHealthKitWorkouts(from startDate: Date, to endDate: Date) async -> [RunningWorkout] {
        await healthKitManager.fetchRecentRunningWorkouts(limit: 200)
            .filter { $0.startDate >= startDate && $0.startDate <= endDate }
    }

    private func calculateWeeklyMileageStats(workouts: [RunningWorkout]) -> WorkoutHistoryAnalysis.WeeklyMileageStats {
        // Group workouts by week
        var weeklyTotals: [Date: Double] = [:]
        let calendar = Calendar.current

        for workout in workouts {
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: workout.startDate)?.start ?? workout.startDate
            weeklyTotals[weekStart, default: 0] += workout.distanceMiles
        }

        let totals = Array(weeklyTotals.values)
        let average = totals.isEmpty ? 0 : totals.reduce(0, +) / Double(totals.count)
        let peak = totals.max() ?? 0

        // Recent 4 week average
        let fourWeeksAgo = calendar.date(byAdding: .weekOfYear, value: -4, to: Date()) ?? Date()
        let recentWeeks = weeklyTotals.filter { $0.key >= fourWeeksAgo }
        let recentAverage = recentWeeks.isEmpty ? average : recentWeeks.values.reduce(0, +) / Double(recentWeeks.count)

        // Trend (compare last 2 weeks to previous 2 weeks)
        let twoWeeksAgo = calendar.date(byAdding: .weekOfYear, value: -2, to: Date()) ?? Date()
        let lastTwoWeeks = weeklyTotals.filter { $0.key >= twoWeeksAgo }.values.reduce(0, +)
        let previousTwoWeeks = weeklyTotals.filter { $0.key >= fourWeeksAgo && $0.key < twoWeeksAgo }.values.reduce(0, +)

        let trend: TrendDirection
        if lastTwoWeeks > previousTwoWeeks * 1.1 {
            trend = .up
        } else if lastTwoWeeks < previousTwoWeeks * 0.9 {
            trend = .down
        } else {
            trend = .stable
        }

        return WorkoutHistoryAnalysis.WeeklyMileageStats(
            average: average,
            peak: peak,
            recent4WeekAverage: recentAverage,
            trend: trend
        )
    }

    private func calculatePaceProgression(workouts: [RunningWorkout]) -> WorkoutHistoryAnalysis.PaceProgression {
        // Separate easy runs from quality workouts by pace
        let validWorkouts = workouts.filter { $0.pacePerMile > 0 && $0.pacePerMile < 900 } // < 15 min/mile

        guard !validWorkouts.isEmpty else {
            return WorkoutHistoryAnalysis.PaceProgression(
                averageEasyPace: 540, // 9:00/mi default
                averageWorkoutPace: 480, // 8:00/mi default
                estimatedMarathonPace: 510,
                vdotEstimate: 40
            )
        }

        let sortedByPace = validWorkouts.sorted { $0.pacePerMile < $1.pacePerMile }

        // Top 25% fastest = workout pace
        let fastCount = max(1, sortedByPace.count / 4)
        let fastestWorkouts = Array(sortedByPace.prefix(fastCount))
        let avgWorkoutPace = fastestWorkouts.map(\.pacePerMile).reduce(0, +) / Double(fastCount)

        // Bottom 50% = easy pace
        let easyCount = max(1, sortedByPace.count / 2)
        let easiestWorkouts = Array(sortedByPace.suffix(easyCount))
        let avgEasyPace = easiestWorkouts.map(\.pacePerMile).reduce(0, +) / Double(easyCount)

        // Estimate marathon pace (typically between easy and workout pace)
        let estimatedMP = avgEasyPace * 0.85 + avgWorkoutPace * 0.15

        // Rough VDOT estimate based on pace
        let vdot = estimateVDOT(paceSecondsPerMile: avgWorkoutPace)

        return WorkoutHistoryAnalysis.PaceProgression(
            averageEasyPace: avgEasyPace,
            averageWorkoutPace: avgWorkoutPace,
            estimatedMarathonPace: estimatedMP,
            vdotEstimate: vdot
        )
    }

    private func estimateVDOT(paceSecondsPerMile: Double) -> Double {
        // Rough VDOT estimation from pace
        // This is a simplified formula; real VDOT requires race performance
        let paceMinPerMile = paceSecondsPerMile / 60.0
        return max(25, min(85, 85 - (paceMinPerMile - 5) * 8))
    }

    private func calculateWorkoutTypeBreakdown(workouts: [RunningWorkout]) -> [WorkoutHistoryAnalysis.WorkoutTypeCount] {
        var breakdown: [String: (count: Int, miles: Double)] = [:]

        for workout in workouts {
            // Classify workout type based on distance and pace
            let type: String
            if workout.distanceMiles >= 12 {
                type = "Long Run"
            } else if workout.pacePerMile < 420 { // faster than 7:00/mi
                type = "Quality/Tempo"
            } else if workout.distanceMiles < 5 {
                type = "Recovery"
            } else {
                type = "Easy Run"
            }

            var current = breakdown[type] ?? (0, 0)
            current.count += 1
            current.miles += workout.distanceMiles
            breakdown[type] = current
        }

        return breakdown.map { key, value in
            WorkoutHistoryAnalysis.WorkoutTypeCount(type: key, count: value.count, totalMiles: value.miles)
        }.sorted { $0.count > $1.count }
    }

    private func calculateConsistencyScore(workouts: [RunningWorkout], dayCount: Int) -> Double {
        // Count days with at least one run
        let calendar = Calendar.current
        var daysWithRuns: Set<Date> = []

        for workout in workouts {
            let day = calendar.startOfDay(for: workout.startDate)
            daysWithRuns.insert(day)
        }

        // Score based on runs per week
        let expectedRunsPerWeek = 5.0
        let weeks = Double(dayCount) / 7.0
        let expectedRuns = expectedRunsPerWeek * weeks
        let actualRuns = Double(daysWithRuns.count)

        let score = min(100, (actualRuns / expectedRuns) * 100)
        return score
    }

    private func findLongestRun(workouts: [RunningWorkout]) -> WorkoutHistoryAnalysis.LongestRunInfo? {
        guard let longest = workouts.max(by: { $0.distanceMiles < $1.distanceMiles }) else {
            return nil
        }

        return WorkoutHistoryAnalysis.LongestRunInfo(
            distanceMiles: longest.distanceMiles,
            date: longest.startDate,
            pace: longest.pacePerMile * 60 // Convert to seconds
        )
    }

    // MARK: - AI Assessment

    private func getAIAssessment(
        questionnaire: FitnessQuestionnaire,
        workoutAnalysis: WorkoutHistoryAnalysis?,
        goalTimeSeconds: Int,
        weeksUntilRace: Int
    ) async -> AIFitnessAssessment {
        // Try to call edge function for AI assessment
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
            return generateLocalAssessment(
                questionnaire: questionnaire,
                workoutAnalysis: workoutAnalysis,
                goalTimeSeconds: goalTimeSeconds,
                weeksUntilRace: weeksUntilRace
            )
        }
    }

    private func generateLocalAssessment(
        questionnaire: FitnessQuestionnaire,
        workoutAnalysis: WorkoutHistoryAnalysis?,
        goalTimeSeconds: Int,
        weeksUntilRace: Int
    ) -> AIFitnessAssessment {
        // Determine fitness level based on questionnaire and workout analysis
        let fitnessLevel = determineFitnessLevel(questionnaire: questionnaire, workoutAnalysis: workoutAnalysis)

        // Build summary
        let summary = buildAssessmentSummary(
            fitnessLevel: fitnessLevel,
            questionnaire: questionnaire,
            workoutAnalysis: workoutAnalysis
        )

        // Identify strengths
        let strengths = identifyStrengths(questionnaire: questionnaire, workoutAnalysis: workoutAnalysis)

        // Identify areas to improve
        let areasToImprove = identifyAreasToImprove(questionnaire: questionnaire, workoutAnalysis: workoutAnalysis)

        // Calculate recommended mileage
        let (startingMileage, peakMileage) = calculateRecommendedMileage(
            questionnaire: questionnaire,
            workoutAnalysis: workoutAnalysis,
            weeksUntilRace: weeksUntilRace
        )

        // Identify risk factors
        let riskFactors = identifyRiskFactors(questionnaire: questionnaire, workoutAnalysis: workoutAnalysis)

        // Assess goal
        let goalAssessment = assessGoal(
            questionnaire: questionnaire,
            workoutAnalysis: workoutAnalysis,
            goalTimeSeconds: goalTimeSeconds
        )

        // Build recommendations
        let recommendations = buildRecommendations(
            questionnaire: questionnaire,
            workoutAnalysis: workoutAnalysis,
            fitnessLevel: fitnessLevel
        )

        return AIFitnessAssessment(
            fitnessLevel: fitnessLevel,
            summary: summary,
            strengths: strengths,
            areasToImprove: areasToImprove,
            recommendedStartingMileage: startingMileage,
            recommendedPeakMileage: peakMileage,
            riskFactors: riskFactors,
            goalAssessment: goalAssessment,
            trainingRecommendations: recommendations
        )
    }

    private func determineFitnessLevel(
        questionnaire: FitnessQuestionnaire,
        workoutAnalysis: WorkoutHistoryAnalysis?
    ) -> FitnessLevel {
        var score = 0

        // Years running (0-2 points)
        switch questionnaire.yearsRunning {
        case .lessThanOne: score += 0
        case .oneToTwo: score += 1
        case .twoToFive: score += 1
        case .fiveToTen: score += 2
        case .moreThanTen: score += 2
        }

        // Current mileage (0-3 points)
        if questionnaire.currentWeeklyMileage >= 60 {
            score += 3
        } else if questionnaire.currentWeeklyMileage >= 40 {
            score += 2
        } else if questionnaire.currentWeeklyMileage >= 25 {
            score += 1
        }

        // Marathon PR (0-3 points)
        if let pr = questionnaire.marathonPR {
            if pr < 10800 { // sub-3:00
                score += 3
            } else if pr < 12600 { // sub-3:30
                score += 2
            } else if pr < 16200 { // sub-4:30
                score += 1
            }
        }

        // Half marathon PR (0-2 points)
        if let pr = questionnaire.halfMarathonPR {
            if pr < 5400 { // sub-1:30
                score += 2
            } else if pr < 6300 { // sub-1:45
                score += 1
            }
        }

        // Consistency (0-1 point)
        if questionnaire.consistencyLevel == .veryConsistent {
            score += 1
        }

        // Workout analysis boost
        if let analysis = workoutAnalysis {
            if analysis.weeklyMileageStats.average >= 50 {
                score += 1
            }
            if analysis.consistencyScore >= 80 {
                score += 1
            }
        }

        // Map score to level
        switch score {
        case 0 ... 2: return .beginner
        case 3 ... 4: return .novice
        case 5 ... 7: return .intermediate
        case 8 ... 10: return .advanced
        default: return .elite
        }
    }

    private func buildAssessmentSummary(
        fitnessLevel: FitnessLevel,
        questionnaire: FitnessQuestionnaire,
        workoutAnalysis: WorkoutHistoryAnalysis?
    ) -> String {
        var parts: [String] = []

        parts.append("Based on your responses, you're at an \(fitnessLevel.displayName.lowercased()) fitness level.")

        if let analysis = workoutAnalysis {
            parts.append("Your recent training shows an average of \(Int(analysis.weeklyMileageStats.average)) miles per week with \(Int(analysis.consistencyScore))% consistency.")
        } else {
            parts.append("You're currently running about \(Int(questionnaire.currentWeeklyMileage)) miles per week.")
        }

        if questionnaire.hasRacedMarathon {
            parts.append("Your marathon experience will be valuable for this training cycle.")
        } else if questionnaire.hasRacedHalfMarathon {
            parts.append("Your half marathon experience provides a good foundation to build from.")
        }

        return parts.joined(separator: " ")
    }

    private func identifyStrengths(
        questionnaire: FitnessQuestionnaire,
        workoutAnalysis: WorkoutHistoryAnalysis?
    ) -> [String] {
        var strengths: [String] = []

        if questionnaire.consistencyLevel == .veryConsistent || questionnaire.consistencyLevel == .mostlyConsistent {
            strengths.append("Consistent training habits")
        }

        if questionnaire.currentWeeklyMileage >= 40 {
            strengths.append("Strong mileage base (\(Int(questionnaire.currentWeeklyMileage)) mpw)")
        }

        if questionnaire.hasRacedMarathon {
            strengths.append("Marathon racing experience")
        }

        if questionnaire.yearsRunning == .fiveToTen || questionnaire.yearsRunning == .moreThanTen {
            strengths.append("Years of running experience")
        }

        if let analysis = workoutAnalysis {
            if analysis.consistencyScore >= 80 {
                strengths.append("High workout consistency (\(Int(analysis.consistencyScore))%)")
            }

            if let longestRun = analysis.longestRun, longestRun.distanceMiles >= 16 {
                strengths.append("Long run experience up to \(Int(longestRun.distanceMiles)) miles")
            }
        }

        if !questionnaire.crossTrainingActivities.isEmpty && !questionnaire.crossTrainingActivities.contains(.none) {
            strengths.append("Active cross-training routine")
        }

        return Array(strengths.prefix(4))
    }

    private func identifyAreasToImprove(
        questionnaire: FitnessQuestionnaire,
        workoutAnalysis: WorkoutHistoryAnalysis?
    ) -> [String] {
        var areas: [String] = []

        if questionnaire.currentWeeklyMileage < 30 {
            areas.append("Build weekly mileage gradually")
        }

        if questionnaire.consistencyLevel == .inconsistent || questionnaire.consistencyLevel == .returning {
            areas.append("Improve training consistency")
        }

        if !questionnaire.hasRacedMarathon && !questionnaire.hasRacedHalfMarathon {
            areas.append("Gain race experience at shorter distances")
        }

        if questionnaire.recentInjury {
            areas.append("Continue injury recovery and prevention")
        }

        if questionnaire.timeAvailablePerDay == .limited {
            areas.append("Maximize efficiency of limited training time")
        }

        if let analysis = workoutAnalysis {
            if analysis.weeklyMileageStats.trend == .down {
                areas.append("Stabilize declining mileage trend")
            }

            if analysis.consistencyScore < 70 {
                areas.append("Improve workout completion rate")
            }
        }

        return Array(areas.prefix(4))
    }

    private func calculateRecommendedMileage(
        questionnaire: FitnessQuestionnaire,
        workoutAnalysis: WorkoutHistoryAnalysis?,
        weeksUntilRace: Int
    ) -> (starting: Double, peak: Double) {
        // Base starting mileage on current mileage
        var starting = questionnaire.currentWeeklyMileage

        // If we have workout analysis, use the recent average
        if let analysis = workoutAnalysis {
            starting = max(starting, analysis.weeklyMileageStats.recent4WeekAverage)
        }

        // Adjust for consistency
        if questionnaire.consistencyLevel == .inconsistent || questionnaire.consistencyLevel == .returning {
            starting *= 0.85 // Start lower if inconsistent
        }

        // Adjust for injury
        if questionnaire.recentInjury {
            starting *= 0.8
        }

        // Floor and ceiling
        starting = max(20, min(starting, 60))

        // Calculate peak based on time available and experience
        var peakMultiplier: Double = 1.5

        switch questionnaire.timeAvailablePerDay {
        case .limited: peakMultiplier = 1.3
        case .moderate: peakMultiplier = 1.5
        case .flexible: peakMultiplier = 1.7
        case .abundant: peakMultiplier = 1.8
        }

        // Adjust for experience
        if questionnaire.yearsRunning == .lessThanOne || questionnaire.yearsRunning == .oneToTwo {
            peakMultiplier *= 0.9
        }

        // Adjust for weeks available
        if weeksUntilRace < 12 {
            peakMultiplier *= 0.9 // Less aggressive if short timeline
        }

        let peak = min(starting * peakMultiplier, questionnaire.peakWeeklyMileage * 1.1)

        return (round(starting), round(min(peak, 90)))
    }

    private func identifyRiskFactors(
        questionnaire: FitnessQuestionnaire,
        workoutAnalysis: WorkoutHistoryAnalysis?
    ) -> [RiskFactor] {
        var risks: [RiskFactor] = []

        if questionnaire.recentInjury {
            risks.append(RiskFactor(
                factor: "Recent injury history",
                severity: .moderate,
                mitigation: "Include extra recovery days and listen to your body. Consider working with a physical therapist."
            ))
        }

        if questionnaire.consistencyLevel == .inconsistent {
            risks.append(RiskFactor(
                factor: "Inconsistent training background",
                severity: .moderate,
                mitigation: "Focus on completing workouts rather than hitting exact paces. Build habits first."
            ))
        }

        if questionnaire.currentWeeklyMileage < 25 {
            risks.append(RiskFactor(
                factor: "Low base mileage",
                severity: .moderate,
                mitigation: "Take extra time in base phase before adding quality work. Don't increase mileage more than 10% per week."
            ))
        }

        if !questionnaire.hasRacedMarathon && !questionnaire.hasRacedHalfMarathon {
            risks.append(RiskFactor(
                factor: "No race experience",
                severity: .low,
                mitigation: "Consider a tune-up half marathon 4-6 weeks before your goal race."
            ))
        }

        if let analysis = workoutAnalysis, analysis.weeklyMileageStats.trend == .down {
            risks.append(RiskFactor(
                factor: "Declining mileage trend",
                severity: .low,
                mitigation: "Focus on rebuilding consistency before increasing intensity."
            ))
        }

        return risks
    }

    private func assessGoal(
        questionnaire: FitnessQuestionnaire,
        workoutAnalysis: WorkoutHistoryAnalysis?,
        goalTimeSeconds: Int
    ) -> GoalAssessmentResult {
        // Estimate realistic goal time from PRs
        var estimatedTime: Int?
        var confidence: Double = 50

        if let marathonPR = questionnaire.marathonPR {
            // Previous marathon is best predictor
            estimatedTime = marathonPR
            confidence = 80
        } else if let halfPR = questionnaire.halfMarathonPR {
            // Half marathon to full: multiply by ~2.1
            estimatedTime = Int(Double(halfPR) * 2.1)
            confidence = 65
        } else if let tenKPR = questionnaire.recent10kTime {
            // 10K to marathon: multiply by ~4.8
            estimatedTime = Int(Double(tenKPR) * 4.8)
            confidence = 50
        } else if let fiveKPR = questionnaire.recent5kTime {
            // 5K to marathon: multiply by ~10
            estimatedTime = Int(Double(fiveKPR) * 10)
            confidence = 40
        }

        // Compare goal to estimated
        let isRealistic: Bool
        var reasoning: String

        if let estimated = estimatedTime {
            let difference = Double(goalTimeSeconds - estimated)
            let percentDiff = difference / Double(estimated) * 100

            if percentDiff >= -5 && percentDiff <= 10 {
                isRealistic = true
                reasoning = "Your goal is well-aligned with your current fitness level."
            } else if percentDiff < -5 && percentDiff >= -15 {
                isRealistic = true
                reasoning = "This is an ambitious but achievable goal with proper training."
                confidence *= 0.8
            } else if percentDiff < -15 {
                isRealistic = false
                reasoning = "This goal may be too aggressive based on your current fitness. Consider a more conservative target."
                confidence *= 0.5
            } else {
                isRealistic = true
                reasoning = "This is a conservative goal - you may be capable of more!"
            }
        } else {
            // No PR data to compare
            isRealistic = questionnaire.goalTimeRealistic != .ambitious
            reasoning = "Without race history data, we recommend starting conservatively and adjusting based on training."
            confidence = 30
        }

        return GoalAssessmentResult(
            isRealistic: isRealistic,
            confidenceLevel: confidence,
            suggestedGoalTime: estimatedTime != nil && !isRealistic ? estimatedTime : nil,
            reasoning: reasoning
        )
    }

    private func buildRecommendations(
        questionnaire: FitnessQuestionnaire,
        workoutAnalysis: WorkoutHistoryAnalysis?,
        fitnessLevel: FitnessLevel
    ) -> [TrainingRecommendation] {
        var recommendations: [TrainingRecommendation] = []

        // Mileage recommendation
        if questionnaire.currentWeeklyMileage < 40 {
            recommendations.append(TrainingRecommendation(
                title: "Build Your Base",
                description: "Gradually increase weekly mileage to at least 40 miles before adding quality workouts",
                priority: .high
            ))
        }

        // Consistency recommendation
        if questionnaire.consistencyLevel == .inconsistent || questionnaire.consistencyLevel == .returning {
            recommendations.append(TrainingRecommendation(
                title: "Prioritize Consistency",
                description: "Focus on completing 5+ runs per week for 4 weeks before worrying about pace or intensity",
                priority: .high
            ))
        }

        // Long run recommendation
        recommendations.append(TrainingRecommendation(
            title: "Long Run Progression",
            description: "Build your long run gradually to 20+ miles. Add 1-2 miles every 2-3 weeks with cutback weeks.",
            priority: .medium
        ))

        // Cross-training recommendation
        if questionnaire.crossTrainingActivities.isEmpty || questionnaire.crossTrainingActivities.contains(.none) {
            recommendations.append(TrainingRecommendation(
                title: "Add Cross-Training",
                description: "Consider adding yoga or strength training 1-2x per week for injury prevention",
                priority: .low
            ))
        }

        // Race experience recommendation
        if !questionnaire.hasRacedMarathon {
            recommendations.append(TrainingRecommendation(
                title: "Get Race Experience",
                description: "Run a half marathon 4-6 weeks before your goal race as a tune-up and pacing practice",
                priority: .medium
            ))
        }

        return Array(recommendations.prefix(4))
    }

}
