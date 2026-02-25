//
//  PlanGeneratorSheet.swift
//  RunningLog
//
//  Sheet for generating a new training plan.
//

import SwiftUI

// MARK: - PlanGeneratorSheet

struct PlanGeneratorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: TrainingPlanViewModel
    let onGenerate: () -> Void

    @State private var planName: String = ""
    @State private var startDate: Date = Date()
    @State private var raceDate: Date = Date().addingTimeInterval(86400 * 112) // Default 16 weeks
    @State private var selectedRaceDistance: RaceDistance = .marathon
    @State private var goalTimeHours: Int = 3
    @State private var goalTimeMinutes: Int = 30
    @State private var goalTimeSeconds: Int = 0
    @State private var currentWeeklyMileage: Double = 20

    @State private var isGenerating = false
    @State private var showDateWarning = false
    @State private var showFitnessAssessment = false
    @State private var fitnessAssessment: FitnessAssessment?

    private var totalWeeks: Int {
        let calendar = Calendar.current
        let weeks = calendar.dateComponents([.weekOfYear], from: startDate, to: raceDate).weekOfYear ?? 0
        return max(1, weeks + 1)
    }

    private var goalTimeInSeconds: Int {
        goalTimeHours * 3600 + goalTimeMinutes * 60 + goalTimeSeconds
    }

    private var racePacePerMile: String {
        let totalSecs = Int(selectedRaceDistance.racePaceSecondsPerMile(goalTimeSeconds: goalTimeInSeconds).rounded())
        let mins = totalSecs / 60
        let secs = totalSecs % 60
        return "\(mins):\(String(format: "%02d", secs))/mi"
    }

    private var goalTimeLabel: String {
        "GOAL \(selectedRaceDistance.displayName.uppercased()) TIME"
    }

    private var defaultGoalTime: (hours: Int, minutes: Int, seconds: Int) {
        switch selectedRaceDistance {
        case .mile1500:
            return (0, 5, 0)  // 5:00 mile
        case .fiveK:
            return (0, 22, 0)  // 22:00 5K
        case .tenK:
            return (0, 45, 0)  // 45:00 10K
        case .halfMarathon:
            return (1, 40, 0)  // 1:40 HM
        case .marathon:
            return (3, 30, 0)  // 3:30 marathon
        }
    }

    private var hoursRange: ClosedRange<Int> {
        switch selectedRaceDistance {
        case .mile1500, .fiveK:
            return 0...0  // No hours for short events
        case .tenK:
            return 0...1
        case .halfMarathon:
            return 1...3
        case .marathon:
            return 2...6
        }
    }

    private var isValidPlan: Bool {
        !planName.isEmpty && totalWeeks >= 4 && totalWeeks <= 24
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.drip.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Plan name
                        VStack(alignment: .leading, spacing: 10) {
                            Text("PLAN NAME")
                                .font(.dripCaption(11))
                                .foregroundStyle(Color.drip.textSecondary)
                                .tracking(1.2)

                            TextField("e.g., Boston Marathon 2026", text: $planName)
                                .font(.dripBody(16))
                                .foregroundStyle(Color.drip.textPrimary)
                                .padding(16)
                                .background(Color.drip.cardBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.drip.divider, lineWidth: 1)
                                )
                        }
                        .padding(.horizontal, 20)

                        // Race distance section
                        VStack(alignment: .leading, spacing: 16) {
                            Text("RACE DISTANCE")
                                .font(.dripCaption(11))
                                .foregroundStyle(Color.drip.textSecondary)
                                .tracking(1.2)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(RaceDistance.allCases) { distance in
                                        RaceDistanceButton(
                                            distance: distance,
                                            isSelected: selectedRaceDistance == distance
                                        ) {
                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                selectedRaceDistance = distance
                                                // Update goal time to default for this distance
                                                let defaults = defaultGoalTime
                                                goalTimeHours = defaults.hours
                                                goalTimeMinutes = defaults.minutes
                                                goalTimeSeconds = defaults.seconds
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                            .padding(.horizontal, -20)
                        }
                        .padding(.horizontal, 20)

                        // Dates section
                        VStack(alignment: .leading, spacing: 16) {
                            Text("TRAINING PERIOD")
                                .font(.dripCaption(11))
                                .foregroundStyle(Color.drip.textSecondary)
                                .tracking(1.2)

                            VStack(spacing: 12) {
                                // Start date
                                DatePickerRow(
                                    label: "Start Date",
                                    icon: "calendar.badge.plus",
                                    date: $startDate
                                )

                                Divider()
                                    .background(Color.drip.divider)

                                // Race date
                                DatePickerRow(
                                    label: "Race Date",
                                    icon: "flag.checkered",
                                    date: $raceDate
                                )
                            }
                            .padding(16)
                            .background(Color.drip.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                            // Duration indicator
                            HStack {
                                Image(systemName: "clock")
                                    .font(.system(size: 12))

                                Text("\(totalWeeks) weeks of training")
                                    .font(.dripCaption(13))

                                if totalWeeks < 8 {
                                    Text("• Short buildup")
                                        .font(.dripCaption(11))
                                        .foregroundStyle(Color.drip.coralLight)
                                } else if totalWeeks > 20 {
                                    Text("• Extended plan")
                                        .font(.dripCaption(11))
                                        .foregroundStyle(Color.drip.energized)
                                }
                            }
                            .foregroundStyle(Color.drip.textSecondary)
                        }
                        .padding(.horizontal, 20)

                        // Goal time section
                        VStack(alignment: .leading, spacing: 16) {
                            Text(goalTimeLabel)
                                .font(.dripCaption(11))
                                .foregroundStyle(Color.drip.textSecondary)
                                .tracking(1.2)

                            VStack(spacing: 16) {
                                // Time pickers
                                HStack(spacing: 0) {
                                    // Only show hours for longer events
                                    if hoursRange.upperBound > 0 {
                                        TimePickerColumn(
                                            value: $goalTimeHours,
                                            range: hoursRange,
                                            label: "hrs"
                                        )

                                        Text(":")
                                            .font(.dripStat(28))
                                            .foregroundStyle(Color.drip.textSecondary)
                                            .padding(.horizontal, 4)
                                    }

                                    TimePickerColumn(
                                        value: $goalTimeMinutes,
                                        range: 0 ... 59,
                                        label: "min"
                                    )

                                    Text(":")
                                        .font(.dripStat(28))
                                        .foregroundStyle(Color.drip.textSecondary)
                                        .padding(.horizontal, 4)

                                    TimePickerColumn(
                                        value: $goalTimeSeconds,
                                        range: 0 ... 59,
                                        label: "sec"
                                    )
                                }
                                .frame(maxWidth: .infinity)

                                Divider()
                                    .background(Color.drip.divider)

                                // Pace indicator
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("RACE PACE")
                                            .font(.dripCaption(10))
                                            .foregroundStyle(Color.drip.textTertiary)
                                            .tracking(0.5)

                                        Text(racePacePerMile)
                                            .font(.dripStat(22))
                                            .foregroundStyle(Color.drip.energized)
                                    }

                                    Spacer()

                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text("GOAL TIME")
                                            .font(.dripCaption(10))
                                            .foregroundStyle(Color.drip.textTertiary)
                                            .tracking(0.5)

                                        Text(formattedGoalTime)
                                            .font(.dripStat(22))
                                            .foregroundStyle(Color.drip.coral)
                                    }
                                }
                            }
                            .padding(16)
                            .background(Color.drip.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .padding(.horizontal, 20)

                        // Current mileage section
                        VStack(alignment: .leading, spacing: 16) {
                            Text("CURRENT WEEKLY MILEAGE")
                                .font(.dripCaption(11))
                                .foregroundStyle(Color.drip.textSecondary)
                                .tracking(1.2)

                            VStack(spacing: 12) {
                                HStack {
                                    Text("\(Int(currentWeeklyMileage))")
                                        .font(.dripStat(32))
                                        .foregroundStyle(Color.drip.textPrimary)

                                    Text("miles/week")
                                        .font(.dripBody(14))
                                        .foregroundStyle(Color.drip.textSecondary)

                                    Spacer()
                                }

                                Slider(
                                    value: $currentWeeklyMileage,
                                    in: 5 ... 80,
                                    step: 5
                                )
                                .tint(Color.drip.coral)

                                HStack {
                                    Text("5 mi")
                                        .font(.dripCaption(10))
                                    Spacer()
                                    Text("80 mi")
                                        .font(.dripCaption(10))
                                }
                                .foregroundStyle(Color.drip.textTertiary)
                            }
                            .padding(16)
                            .background(Color.drip.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                            Text("This helps calibrate your starting volume for the plan.")
                                .font(.dripCaption(12))
                                .foregroundStyle(Color.drip.textTertiary)
                        }
                        .padding(.horizontal, 20)

                        // Training phases preview
                        TrainingPhasesPreview(totalWeeks: totalWeeks)
                            .padding(.horizontal, 20)

                        // Generate button
                        VStack(spacing: 12) {
                            Button {
                                showFitnessAssessment = true
                            } label: {
                                HStack(spacing: 10) {
                                    if isGenerating {
                                        ProgressView()
                                            .tint(.white)
                                    } else {
                                        Image(systemName: "sparkles")
                                            .font(.system(size: 16))
                                    }

                                    Text("Continue to Fitness Assessment")
                                        .font(.dripLabel(16))
                                }
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 18)
                                .background(
                                    isValidPlan
                                        ? Color.drip.coral
                                        : Color.drip.coral.opacity(0.4)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                            .disabled(!isValidPlan || isGenerating)

                            if !isValidPlan {
                                Text(validationMessage)
                                    .font(.dripCaption(12))
                                    .foregroundStyle(Color.drip.coralLight)
                            }

                            Text("We'll ask a few questions to personalize your plan")
                                .font(.dripCaption(12))
                                .foregroundStyle(Color.drip.textTertiary)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
                    }
                    .padding(.top, 20)
                }
            }
            .navigationTitle("Create Training Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.dripBody(15))
                    .foregroundStyle(Color.drip.coral)
                }
            }
            .toolbarBackground(Color.drip.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .onAppear {
                loadFromActiveGoal()
            }
            .sheet(isPresented: $showFitnessAssessment) {
                FitnessAssessmentView(
                    goalTimeSeconds: goalTimeInSeconds,
                    raceDate: raceDate
                ) { assessment in
                    fitnessAssessment = assessment
                    showFitnessAssessment = false
                    generatePlanWithAssessment(assessment)
                }
            }
        }
    }

    private var formattedGoalTime: String {
        if goalTimeSeconds > 0 {
            return String(format: "%d:%02d:%02d", goalTimeHours, goalTimeMinutes, goalTimeSeconds)
        }
        return String(format: "%d:%02d", goalTimeHours, goalTimeMinutes)
    }

    private var validationMessage: String {
        if planName.isEmpty {
            return "Please enter a plan name"
        }
        if totalWeeks < 4 {
            return "Training plan must be at least 4 weeks"
        }
        if totalWeeks > 24 {
            return "Training plan cannot exceed 24 weeks"
        }
        return ""
    }

    private func loadFromActiveGoal() {
        if let goal = viewModel.activeGoal {
            raceDate = goal.targetDate
            planName = goal.goalTitle.replacingOccurrences(of: "Run a ", with: "")
                .replacingOccurrences(of: " marathon", with: " Marathon")

            // Parse goal time if available
            if let goalTime = viewModel.marathonGoalTime {
                goalTimeHours = goalTime / 3600
                goalTimeMinutes = (goalTime % 3600) / 60
                goalTimeSeconds = goalTime % 60
            }
        }
    }

    private func generatePlan() {
        isGenerating = true

        Task {
            await viewModel.generatePlan(
                name: planName,
                startDate: startDate,
                targetDate: raceDate,
                targetTimeSeconds: goalTimeInSeconds,
                raceDistance: selectedRaceDistance,
                baseWeeklyMileage: currentWeeklyMileage
            )

            await MainActor.run {
                isGenerating = false
                onGenerate()
            }
        }
    }

    private func generatePlanWithAssessment(_ assessment: FitnessAssessment) {
        isGenerating = true

        Task {
            // Use assessment data to calibrate the plan
            let startingMileage = assessment.recommendedWeeklyMileage
            let peakMileage = assessment.recommendedPeakMileage
            let canRunDoubles = assessment.questionnaire.canRunDoubles
            let preferredLongRunDay = assessment.questionnaire.preferredLongRunDay

            await viewModel.generatePlan(
                name: planName,
                startDate: startDate,
                targetDate: raceDate,
                targetTimeSeconds: goalTimeInSeconds,
                raceDistance: selectedRaceDistance,
                baseWeeklyMileage: startingMileage,
                peakWeeklyMileage: peakMileage,
                canRunDoubles: canRunDoubles,
                preferredLongRunDay: preferredLongRunDay.rawValue,
                fitnessAssessment: assessment
            )

            await MainActor.run {
                isGenerating = false
                onGenerate()
            }
        }
    }
}

// MARK: - Race Distance Button

struct RaceDistanceButton: View {
    let distance: RaceDistance
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: distance.icon)
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? .white : distance.color)

                Text(distance.shortName)
                    .font(.dripLabel(12))
                    .foregroundStyle(isSelected ? .white : Color.drip.textPrimary)

                Text(String(format: "%.1f mi", distance.distanceInMiles))
                    .font(.dripCaption(9))
                    .foregroundStyle(isSelected ? .white.opacity(0.8) : Color.drip.textTertiary)
            }
            .frame(width: 65, height: 70)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? distance.color : Color.drip.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.clear : Color.drip.divider, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Date Picker Row

struct DatePickerRow: View {
    let label: String
    let icon: String
    @Binding var date: Date

    var body: some View {
        HStack {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.drip.coral)

                Text(label)
                    .font(.dripLabel(14))
                    .foregroundStyle(Color.drip.textPrimary)
            }

            Spacer()

            DatePicker(
                "",
                selection: $date,
                displayedComponents: .date
            )
            .labelsHidden()
            .tint(Color.drip.coral)
        }
    }
}

// MARK: - Time Picker Column

struct TimePickerColumn: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Picker("", selection: $value) {
                ForEach(range, id: \.self) { num in
                    Text(String(format: "%02d", num))
                        .font(.dripStat(28))
                        .foregroundStyle(Color.drip.textPrimary)
                        .tag(num)
                }
            }
            .pickerStyle(.wheel)
            .frame(width: 60, height: 100)
            .clipped()

            Text(label)
                .font(.dripCaption(10))
                .foregroundStyle(Color.drip.textTertiary)
        }
    }
}

// MARK: - Training Phases Preview

struct TrainingPhasesPreview: View {
    let totalWeeks: Int

    private var phases: [(name: String, weeks: Int, color: Color)] {
        // Distribute weeks: Base 10%, Support 40%, Specific 40%, Taper 10%
        let taperWeeks = max(1, Int(Double(totalWeeks) * 0.10))
        let baseWeeks = max(1, Int(Double(totalWeeks) * 0.10))
        let supportWeeks = max(2, Int(Double(totalWeeks) * 0.40))
        let specificWeeks = totalWeeks - baseWeeks - supportWeeks - taperWeeks

        return [
            ("Base", baseWeeks, CanovaTrainingPhase.base.color),
            ("Support", supportWeeks, CanovaTrainingPhase.support.color),
            ("Specific", specificWeeks, CanovaTrainingPhase.specific.color),
            ("Taper", taperWeeks, CanovaTrainingPhase.taper.color),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TRAINING PHASES")
                .font(.dripCaption(11))
                .foregroundStyle(Color.drip.textSecondary)
                .tracking(1.2)

            VStack(spacing: 0) {
                // Phase bars
                HStack(spacing: 2) {
                    ForEach(phases, id: \.name) { phase in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(phase.color)
                            .frame(height: 8)
                            .frame(maxWidth: max(1, CGFloat(phase.weeks) * 20))
                    }
                }

                // Phase labels
                HStack(spacing: 0) {
                    ForEach(phases, id: \.name) { phase in
                        VStack(spacing: 2) {
                            Text(phase.name)
                                .font(.dripCaption(9))
                                .foregroundStyle(phase.color)

                            Text("\(phase.weeks)w")
                                .font(.dripCaption(8))
                                .foregroundStyle(Color.drip.textTertiary)
                        }
                        .frame(maxWidth: max(1, CGFloat(phase.weeks) * 20))
                    }
                }
                .padding(.top, 8)
            }
            .padding(16)
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - Preview

#Preview {
    PlanGeneratorSheet(
        viewModel: TrainingPlanViewModel(),
        onGenerate: {}
    )
}
