//
//  FitnessAssessmentView.swift
//  RunningLog
//
//  Multi-step fitness assessment questionnaire for training plan calibration.
//

import SwiftUI

// MARK: - FitnessAssessmentView

struct FitnessAssessmentView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: FitnessAssessmentViewModel

    let goalTimeSeconds: Int
    let raceDate: Date
    let onComplete: (FitnessAssessment) -> Void

    init(
        goalTimeSeconds: Int,
        raceDate: Date,
        onComplete: @escaping (FitnessAssessment) -> Void
    ) {
        self.goalTimeSeconds = goalTimeSeconds
        self.raceDate = raceDate
        self.onComplete = onComplete
        _viewModel = StateObject(wrappedValue: FitnessAssessmentViewModel())
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.drip.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Progress indicator
                    ProgressBar(currentStep: viewModel.currentStep, totalSteps: viewModel.totalSteps)
                        .padding(.horizontal, 20)
                        .padding(.top, 12)

                    // Content
                    TabView(selection: $viewModel.currentStep) {
                        RunningHistoryStep(viewModel: viewModel)
                            .tag(1)

                        RaceHistoryStep(viewModel: viewModel)
                            .tag(2)

                        TrainingPreferencesStep(viewModel: viewModel)
                            .tag(3)

                        GoalAssessmentStep(viewModel: viewModel, goalTimeSeconds: goalTimeSeconds)
                            .tag(4)

                        AnalyzingStep(viewModel: viewModel, goalTimeSeconds: goalTimeSeconds, raceDate: raceDate)
                            .tag(5)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .animation(.easeInOut, value: viewModel.currentStep)

                    // Navigation buttons
                    if viewModel.currentStep < 5 {
                        NavigationButtons(viewModel: viewModel, onSkip: { dismiss() })
                            .padding(.horizontal, 20)
                            .padding(.bottom, 30)
                    }
                }
            }
            .navigationTitle("Fitness Assessment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Skip") {
                        // Create minimal assessment and proceed
                        let assessment = viewModel.createBasicAssessment()
                        onComplete(assessment)
                    }
                    .font(.dripBody(15))
                    .foregroundStyle(Color.drip.textSecondary)
                }
            }
            .toolbarBackground(Color.drip.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .onChange(of: viewModel.isComplete) { _, isComplete in
                if isComplete, let assessment = viewModel.finalAssessment {
                    onComplete(assessment)
                }
            }
        }
    }
}

// MARK: - Progress Bar

struct ProgressBar: View {
    let currentStep: Int
    let totalSteps: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1 ... totalSteps, id: \.self) { step in
                RoundedRectangle(cornerRadius: 2)
                    .fill(step <= currentStep ? Color.drip.coral : Color.drip.divider)
                    .frame(height: 4)
            }
        }
    }
}

// MARK: - Navigation Buttons

struct NavigationButtons: View {
    @ObservedObject var viewModel: FitnessAssessmentViewModel
    let onSkip: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if viewModel.currentStep > 1 {
                Button {
                    withAnimation {
                        viewModel.currentStep -= 1
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .font(.dripLabel(15))
                    .foregroundStyle(Color.drip.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.drip.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }

            Button {
                withAnimation {
                    viewModel.currentStep += 1
                }
            } label: {
                HStack(spacing: 6) {
                    Text(viewModel.currentStep == 4 ? "Analyze" : "Continue")
                    Image(systemName: viewModel.currentStep == 4 ? "sparkles" : "chevron.right")
                }
                .font(.dripLabel(15))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.drip.coral)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

// MARK: - Step 1: Running History

struct RunningHistoryStep: View {
    @ObservedObject var viewModel: FitnessAssessmentViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                StepHeader(
                    title: "Running Background",
                    subtitle: "Tell us about your running history"
                )

                // Years running
                QuestionSection(title: "HOW LONG HAVE YOU BEEN RUNNING?") {
                    ForEach(YearsRunning.allCases, id: \.self) { option in
                        SelectableRow(
                            title: option.displayName,
                            isSelected: viewModel.yearsRunning == option
                        ) {
                            viewModel.yearsRunning = option
                        }
                    }
                }

                // Current weekly mileage
                QuestionSection(title: "CURRENT WEEKLY MILEAGE") {
                    MileageSlider(
                        value: $viewModel.currentWeeklyMileage,
                        range: 5 ... 100,
                        label: "miles/week"
                    )
                }

                // Peak mileage
                QuestionSection(title: "HIGHEST WEEKLY MILEAGE (EVER)") {
                    MileageSlider(
                        value: $viewModel.peakWeeklyMileage,
                        range: 10 ... 120,
                        label: "miles/week"
                    )
                }

                // Runs per week
                QuestionSection(title: "RUNS PER WEEK") {
                    HStack(spacing: 8) {
                        ForEach(3 ... 7, id: \.self) { num in
                            Button {
                                viewModel.runsPerWeek = num
                            } label: {
                                Text("\(num)")
                                    .font(.dripStat(20))
                                    .foregroundStyle(viewModel.runsPerWeek == num ? .white : Color.drip.textPrimary)
                                    .frame(width: 50, height: 50)
                                    .background(viewModel.runsPerWeek == num ? Color.drip.coral : Color.drip.cardBackground)
                                    .clipShape(Circle())
                            }
                        }
                    }
                }

                // Consistency
                QuestionSection(title: "TRAINING CONSISTENCY") {
                    ForEach(ConsistencyLevel.allCases, id: \.self) { level in
                        SelectableRow(
                            title: level.displayName,
                            isSelected: viewModel.consistencyLevel == level
                        ) {
                            viewModel.consistencyLevel = level
                        }
                    }
                }

                // Recent injury
                QuestionSection(title: "RECENT INJURY?") {
                    HStack(spacing: 12) {
                        SelectableChip(title: "No", isSelected: !viewModel.recentInjury) {
                            viewModel.recentInjury = false
                        }
                        SelectableChip(title: "Yes", isSelected: viewModel.recentInjury) {
                            viewModel.recentInjury = true
                        }
                    }

                    if viewModel.recentInjury {
                        TextField("Describe injury (optional)", text: $viewModel.injuryDetails)
                            .font(.dripBody(14))
                            .padding(12)
                            .background(Color.drip.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
        }
    }
}

// MARK: - Step 2: Race History

struct RaceHistoryStep: View {
    @ObservedObject var viewModel: FitnessAssessmentViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                StepHeader(
                    title: "Race History",
                    subtitle: "Your recent race performances help calibrate training"
                )

                // Marathon experience
                QuestionSection(title: "HAVE YOU RUN A MARATHON?") {
                    HStack(spacing: 12) {
                        SelectableChip(title: "No", isSelected: !viewModel.hasRacedMarathon) {
                            viewModel.hasRacedMarathon = false
                        }
                        SelectableChip(title: "Yes", isSelected: viewModel.hasRacedMarathon) {
                            viewModel.hasRacedMarathon = true
                        }
                    }

                    if viewModel.hasRacedMarathon {
                        TimeInputRow(
                            label: "Marathon PR",
                            hours: $viewModel.marathonPRHours,
                            minutes: $viewModel.marathonPRMinutes,
                            seconds: $viewModel.marathonPRSeconds
                        )
                    }
                }

                // Half marathon
                QuestionSection(title: "HAVE YOU RUN A HALF MARATHON?") {
                    HStack(spacing: 12) {
                        SelectableChip(title: "No", isSelected: !viewModel.hasRacedHalfMarathon) {
                            viewModel.hasRacedHalfMarathon = false
                        }
                        SelectableChip(title: "Yes", isSelected: viewModel.hasRacedHalfMarathon) {
                            viewModel.hasRacedHalfMarathon = true
                        }
                    }

                    if viewModel.hasRacedHalfMarathon {
                        TimeInputRow(
                            label: "Half Marathon PR",
                            hours: $viewModel.halfPRHours,
                            minutes: $viewModel.halfPRMinutes,
                            seconds: $viewModel.halfPRSeconds
                        )
                    }
                }

                // Recent 5K/10K
                QuestionSection(title: "RECENT 5K OR 10K TIME?") {
                    HStack(spacing: 12) {
                        SelectableChip(title: "No", isSelected: !viewModel.has5kOr10kRecent) {
                            viewModel.has5kOr10kRecent = false
                        }
                        SelectableChip(title: "Yes", isSelected: viewModel.has5kOr10kRecent) {
                            viewModel.has5kOr10kRecent = true
                        }
                    }

                    if viewModel.has5kOr10kRecent {
                        VStack(spacing: 12) {
                            TimeInputRow(
                                label: "5K Time",
                                hours: .constant(0),
                                minutes: $viewModel.recent5kMinutes,
                                seconds: $viewModel.recent5kSeconds,
                                showHours: false
                            )

                            TimeInputRow(
                                label: "10K Time",
                                hours: .constant(0),
                                minutes: $viewModel.recent10kMinutes,
                                seconds: $viewModel.recent10kSeconds,
                                showHours: false
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
        }
    }
}

// MARK: - Step 3: Training Preferences

struct TrainingPreferencesStep: View {
    @ObservedObject var viewModel: FitnessAssessmentViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                StepHeader(
                    title: "Training Preferences",
                    subtitle: "Help us customize your plan"
                )

                // Long run day
                QuestionSection(title: "PREFERRED LONG RUN DAY") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach([DayOfWeek.saturday, .sunday], id: \.self) { day in
                            SelectableChip(
                                title: day.displayName,
                                isSelected: viewModel.preferredLongRunDay == day
                            ) {
                                viewModel.preferredLongRunDay = day
                            }
                        }
                    }
                }

                // Can run doubles
                QuestionSection(title: "CAN YOU RUN TWICE A DAY?") {
                    HStack(spacing: 12) {
                        SelectableChip(title: "No", isSelected: !viewModel.canRunDoubles) {
                            viewModel.canRunDoubles = false
                        }
                        SelectableChip(title: "Yes", isSelected: viewModel.canRunDoubles) {
                            viewModel.canRunDoubles = true
                        }
                    }

                    Text("Doubles are used for high-mileage weeks (70+ mpw)")
                        .font(.dripCaption(12))
                        .foregroundStyle(Color.drip.textTertiary)
                }

                // Track access
                QuestionSection(title: "ACCESS TO A TRACK?") {
                    HStack(spacing: 12) {
                        SelectableChip(title: "No", isSelected: !viewModel.hasAccessToTrack) {
                            viewModel.hasAccessToTrack = false
                        }
                        SelectableChip(title: "Yes", isSelected: viewModel.hasAccessToTrack) {
                            viewModel.hasAccessToTrack = true
                        }
                    }
                }

                // Preferred workout types
                QuestionSection(title: "FAVORITE WORKOUT TYPES") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(PreferredWorkoutType.allCases, id: \.self) { type in
                            MultiSelectChip(
                                title: type.displayName,
                                isSelected: viewModel.preferredWorkoutTypes.contains(type)
                            ) {
                                if viewModel.preferredWorkoutTypes.contains(type) {
                                    viewModel.preferredWorkoutTypes.removeAll { $0 == type }
                                } else {
                                    viewModel.preferredWorkoutTypes.append(type)
                                }
                            }
                        }
                    }
                }

                // Time available
                QuestionSection(title: "TIME AVAILABLE FOR RUNNING") {
                    ForEach(TimeAvailability.allCases, id: \.self) { availability in
                        SelectableRow(
                            title: availability.displayName,
                            isSelected: viewModel.timeAvailablePerDay == availability
                        ) {
                            viewModel.timeAvailablePerDay = availability
                        }
                    }
                }

                // Cross training
                QuestionSection(title: "CROSS-TRAINING ACTIVITIES") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(CrossTrainingActivity.allCases.filter { $0 != .none }, id: \.self) { activity in
                            MultiSelectChip(
                                title: activity.displayName,
                                isSelected: viewModel.crossTrainingActivities.contains(activity)
                            ) {
                                if viewModel.crossTrainingActivities.contains(activity) {
                                    viewModel.crossTrainingActivities.removeAll { $0 == activity }
                                } else {
                                    viewModel.crossTrainingActivities.append(activity)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
        }
    }
}

// MARK: - Step 4: Goal Assessment

struct GoalAssessmentStep: View {
    @ObservedObject var viewModel: FitnessAssessmentViewModel
    let goalTimeSeconds: Int

    private var formattedGoalTime: String {
        let hours = goalTimeSeconds / 3600
        let minutes = (goalTimeSeconds % 3600) / 60
        let seconds = goalTimeSeconds % 60
        if seconds > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", hours, minutes)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                StepHeader(
                    title: "Goal Assessment",
                    subtitle: "One last question before we analyze"
                )

                // Goal time display
                VStack(spacing: 8) {
                    Text("YOUR GOAL TIME")
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.textSecondary)
                        .tracking(1.2)

                    Text(formattedGoalTime)
                        .font(.dripStat(48))
                        .foregroundStyle(Color.drip.coral)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(Color.drip.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16))

                // Goal realism
                QuestionSection(title: "HOW DO YOU FEEL ABOUT THIS GOAL?") {
                    ForEach(GoalTimeAssessment.allCases, id: \.self) { assessment in
                        SelectableRow(
                            title: assessment.displayName,
                            isSelected: viewModel.goalTimeRealistic == assessment
                        ) {
                            viewModel.goalTimeRealistic = assessment
                        }
                    }
                }

                // Info card
                InfoCard(
                    icon: "lightbulb.fill",
                    title: "Why we ask",
                    message: "Your self-assessment helps us calibrate workout intensities and provide appropriate coaching feedback."
                )
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
        }
    }
}

// MARK: - Step 5: Analyzing

struct AnalyzingStep: View {
    @ObservedObject var viewModel: FitnessAssessmentViewModel
    let goalTimeSeconds: Int
    let raceDate: Date

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            if viewModel.isAnalyzing {
                // Analyzing state
                VStack(spacing: 24) {
                    ZStack {
                        Circle()
                            .stroke(Color.drip.divider, lineWidth: 4)
                            .frame(width: 100, height: 100)

                        Circle()
                            .trim(from: 0, to: viewModel.analysisProgress)
                            .stroke(Color.drip.coral, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .frame(width: 100, height: 100)
                            .rotationEffect(.degrees(-90))
                            .animation(.easeInOut(duration: 0.3), value: viewModel.analysisProgress)

                        Image(systemName: "sparkles")
                            .font(.system(size: 32))
                            .foregroundStyle(Color.drip.coral)
                    }

                    Text("Analyzing your fitness...")
                        .font(.dripLabel(18))
                        .foregroundStyle(Color.drip.textPrimary)

                    Text(viewModel.analysisStatus)
                        .font(.dripBody(14))
                        .foregroundStyle(Color.drip.textSecondary)
                        .multilineTextAlignment(.center)
                }
            } else if let assessment = viewModel.finalAssessment {
                // Results state
                AssessmentResultsView(assessment: assessment)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .onAppear {
            viewModel.startAnalysis(goalTimeSeconds: goalTimeSeconds, raceDate: raceDate)
        }
    }
}

// MARK: - Assessment Results View

struct AssessmentResultsView: View {
    let assessment: FitnessAssessment

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Fitness level badge
                VStack(spacing: 12) {
                    Image(systemName: assessment.fitnessLevel.icon)
                        .font(.system(size: 40))
                        .foregroundStyle(assessment.fitnessLevel.color)

                    Text(assessment.fitnessLevel.displayName)
                        .font(.dripStat(28))
                        .foregroundStyle(Color.drip.textPrimary)

                    Text(assessment.fitnessLevel.description)
                        .font(.dripBody(14))
                        .foregroundStyle(Color.drip.textSecondary)
                }
                .padding(.vertical, 24)

                // AI Summary
                if let aiAssessment = assessment.aiAssessment {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("ASSESSMENT")
                            .font(.dripCaption(11))
                            .foregroundStyle(Color.drip.textSecondary)
                            .tracking(1.2)

                        Text(aiAssessment.summary)
                            .font(.dripBody(14))
                            .foregroundStyle(Color.drip.textPrimary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color.drip.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    // Recommendations
                    VStack(alignment: .leading, spacing: 12) {
                        Text("RECOMMENDED MILEAGE")
                            .font(.dripCaption(11))
                            .foregroundStyle(Color.drip.textSecondary)
                            .tracking(1.2)

                        HStack(spacing: 24) {
                            VStack(spacing: 4) {
                                Text("\(Int(aiAssessment.recommendedStartingMileage))")
                                    .font(.dripStat(32))
                                    .foregroundStyle(Color.drip.energized)
                                Text("Starting")
                                    .font(.dripCaption(12))
                                    .foregroundStyle(Color.drip.textSecondary)
                            }

                            Image(systemName: "arrow.right")
                                .foregroundStyle(Color.drip.textTertiary)

                            VStack(spacing: 4) {
                                Text("\(Int(aiAssessment.recommendedPeakMileage))")
                                    .font(.dripStat(32))
                                    .foregroundStyle(Color.drip.coral)
                                Text("Peak")
                                    .font(.dripCaption(12))
                                    .foregroundStyle(Color.drip.textSecondary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(16)
                    .background(Color.drip.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Text("Your plan will be calibrated based on this assessment")
                    .font(.dripCaption(13))
                    .foregroundStyle(Color.drip.textTertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 100)
        }
    }
}

// MARK: - Helper Views

struct StepHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.dripStat(24))
                .foregroundStyle(Color.drip.textPrimary)

            Text(subtitle)
                .font(.dripBody(14))
                .foregroundStyle(Color.drip.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 20)
    }
}

struct QuestionSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.dripCaption(11))
                .foregroundStyle(Color.drip.textSecondary)
                .tracking(1.2)

            content
        }
    }
}

struct SelectableRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.dripBody(14))
                    .foregroundStyle(Color.drip.textPrimary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.drip.coral)
                } else {
                    Circle()
                        .stroke(Color.drip.divider, lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                }
            }
            .padding(14)
            .background(isSelected ? Color.drip.coral.opacity(0.1) : Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.drip.coral : Color.clear, lineWidth: 1)
            )
        }
    }
}

struct SelectableChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.dripLabel(14))
                .foregroundStyle(isSelected ? .white : Color.drip.textPrimary)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(isSelected ? Color.drip.coral : Color.drip.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

struct MultiSelectChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                }
                Text(title)
                    .font(.dripLabel(13))
            }
            .foregroundStyle(isSelected ? .white : Color.drip.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isSelected ? Color.drip.coral : Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

struct MileageSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let label: String

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("\(Int(value))")
                    .font(.dripStat(32))
                    .foregroundStyle(Color.drip.textPrimary)

                Text(label)
                    .font(.dripBody(14))
                    .foregroundStyle(Color.drip.textSecondary)

                Spacer()
            }

            Slider(value: $value, in: range, step: 5)
                .tint(Color.drip.coral)

            HStack {
                Text("\(Int(range.lowerBound))")
                    .font(.dripCaption(10))
                Spacer()
                Text("\(Int(range.upperBound))")
                    .font(.dripCaption(10))
            }
            .foregroundStyle(Color.drip.textTertiary)
        }
        .padding(16)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct TimeInputRow: View {
    let label: String
    @Binding var hours: Int
    @Binding var minutes: Int
    @Binding var seconds: Int
    var showHours: Bool = true

    var body: some View {
        HStack {
            Text(label)
                .font(.dripBody(14))
                .foregroundStyle(Color.drip.textPrimary)

            Spacer()

            HStack(spacing: 4) {
                if showHours {
                    TimeField(value: $hours, range: 0 ... 6)
                    Text(":")
                        .foregroundStyle(Color.drip.textSecondary)
                }
                TimeField(value: $minutes, range: 0 ... 59)
                Text(":")
                    .foregroundStyle(Color.drip.textSecondary)
                TimeField(value: $seconds, range: 0 ... 59)
            }
            .font(.dripStat(18))
        }
        .padding(12)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct TimeField: View {
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        TextField("", value: $value, format: .number)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .frame(width: 36)
            .onChange(of: value) { _, newValue in
                value = min(max(newValue, range.lowerBound), range.upperBound)
            }
    }
}

struct InfoCard: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Color.drip.energized)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.dripLabel(13))
                    .foregroundStyle(Color.drip.textPrimary)

                Text(message)
                    .font(.dripCaption(12))
                    .foregroundStyle(Color.drip.textSecondary)
            }
        }
        .padding(14)
        .background(Color.drip.energized.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Preview

#Preview {
    FitnessAssessmentView(
        goalTimeSeconds: 12600, // 3:30:00
        raceDate: Date().addingTimeInterval(86400 * 112),
        onComplete: { _ in }
    )
}
