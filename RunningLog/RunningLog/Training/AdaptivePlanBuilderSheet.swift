//
//  AdaptivePlanBuilderSheet.swift
//  RunningLog
//
//  Athlete-side adaptive plan builder. 3-step flow:
//    1. Goal — distance + race date + optional goal time
//    2. Schedule — quality day count, spacing pattern, anchor day
//    3. Preview + activate
//
//  Generates an inline plan template + subscribes the athlete to it.
//

import SwiftUI

// MARK: - Builder Sheet

struct AdaptivePlanBuilderSheet: View {
    @Environment(\.dismiss) private var dismiss
    let viewModel: TrainingPlanViewModel

    @State private var step: BuilderStep = .goal

    // Step 1
    @State private var raceDistance: PlanDistance = .tenK
    @State private var raceDate = Calendar.current.date(byAdding: .weekOfYear, value: 12, to: Date()) ?? Date()
    @State private var goalTimeText = ""

    // Step 2
    @State private var qualityCount: Int = 2
    @State private var anchorDay: Weekday = .tuesday  // first quality day
    @State private var qualityOffsets: [Int] = [0, 3] // days after anchor
    @State private var longRunOffset: Int = 5
    @State private var weeklyMileage: Int = 35

    // Step 3
    @State private var isActivating = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.drip.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        StepIndicator(current: step)
                            .padding(.horizontal, 20)
                            .padding(.top, 8)

                        switch step {
                        case .goal:
                            goalStep
                        case .schedule:
                            scheduleStep
                        case .preview:
                            previewStep
                        }

                        Spacer().frame(height: 100)
                    }
                }
            }
            .navigationTitle(step.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                bottomBar
            }
        }
    }

    // MARK: - Step 1: Goal

    private var goalStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            Section(header: BuilderSectionHeader("RACE DISTANCE")) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], spacing: 8) {
                    ForEach(PlanDistance.allCases) { d in
                        DistancePill(distance: d, selected: raceDistance == d) {
                            raceDistance = d
                            // Sensible default mileage by distance
                            weeklyMileage = d.suggestedMileage
                        }
                    }
                }
            }

            Section(header: BuilderSectionHeader("RACE DATE")) {
                DatePicker(
                    "Race date",
                    selection: $raceDate,
                    in: Date()...,
                    displayedComponents: [.date]
                )
                .labelsHidden()
                .datePickerStyle(.graphical)
                .tint(Color.drip.coral)

                Text("\(weeksUntilRace) weeks of training")
                    .font(.dripCaption(12))
                    .foregroundStyle(Color.drip.textSecondary)
                    .padding(.top, 4)
            }

            Section(header: BuilderSectionHeader("GOAL TIME (OPTIONAL)")) {
                TextField(raceDistance.placeholderTime, text: $goalTimeText)
                    .keyboardType(.numbersAndPunctuation)
                    .padding(12)
                    .background(Color.drip.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                Text(raceDistance.formatHint)
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textTertiary)
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Step 2: Schedule

    private var scheduleStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            Section(header: BuilderSectionHeader("QUALITY DAYS PER WEEK")) {
                HStack(spacing: 8) {
                    ForEach(1...4, id: \.self) { n in
                        QualityCountButton(count: n, selected: qualityCount == n) {
                            qualityCount = n
                            qualityOffsets = Self.defaultOffsets(for: n)
                            longRunOffset = Self.defaultLongRunOffset(for: n, qualityOffsets: qualityOffsets)
                        }
                    }
                }
                Text("\(qualityCount) hard \(qualityCount == 1 ? "day" : "days")/week + long run")
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textTertiary)
            }

            Section(header: BuilderSectionHeader("ANCHOR DAY  •  YOUR FIRST QUALITY DAY")) {
                HStack(spacing: 6) {
                    ForEach(Weekday.allCases) { day in
                        DayPill(label: day.shortName, selected: anchorDay == day) {
                            anchorDay = day
                        }
                    }
                }
                Text("Quality days will rotate from this anchor.")
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textTertiary)
            }

            Section(header: BuilderSectionHeader("WEEKLY MILEAGE TARGET")) {
                HStack {
                    Slider(value: Binding(
                        get: { Double(weeklyMileage) },
                        set: { weeklyMileage = Int($0) }
                    ), in: 15...90, step: 5)
                    .tint(Color.drip.coral)
                    Text("\(weeklyMileage) mi")
                        .font(.dripLabel(14))
                        .foregroundStyle(Color.drip.textPrimary)
                        .frame(width: 60, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Step 3: Preview

    private var previewStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Preview week")
                .font(.dripCaption(11))
                .tracking(1.2)
                .foregroundStyle(Color.drip.textSecondary)
                .padding(.horizontal, 20)

            VStack(spacing: 0) {
                let week = previewWeek
                ForEach(Array(week.enumerated()), id: \.offset) { idx, day in
                    PreviewDayRow(day: day)
                    if idx < week.count - 1 {
                        Divider()
                    }
                }
            }
            .padding(16)
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 20)

            VStack(alignment: .leading, spacing: 6) {
                summaryRow(label: "Race", value: "\(raceDistance.displayName) on \(formatDate(raceDate))")
                summaryRow(label: "Training weeks", value: "\(weeksUntilRace)")
                summaryRow(label: "Quality days", value: "\(qualityCount) per week")
                summaryRow(label: "Weekly mileage", value: "\(weeklyMileage) mi")
                if !goalTimeText.isEmpty { summaryRow(label: "Goal time", value: goalTimeText) }
            }
            .padding(16)
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 20)

            if let err = errorMessage {
                Text(err)
                    .font(.dripCaption(11))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 20)
            }
        }
    }

    private func summaryRow(label: String, value: String) -> some View {
        HStack {
            Text(label.uppercased())
                .font(.dripCaption(10))
                .tracking(0.8)
                .foregroundStyle(Color.drip.textTertiary)
            Spacer()
            Text(value)
                .font(.dripLabel(13))
                .foregroundStyle(Color.drip.textPrimary)
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 12) {
            if step != .goal {
                Button {
                    withAnimation { step = step.previous() }
                } label: {
                    Text("Back")
                        .font(.dripLabel(15))
                        .foregroundStyle(Color.drip.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.drip.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            Button {
                if step == .preview {
                    Task { await activate() }
                } else {
                    withAnimation { step = step.next() }
                }
            } label: {
                HStack {
                    if isActivating { ProgressView().tint(.white) }
                    Text(step == .preview ? "Activate Plan" : "Next")
                        .font(.dripLabel(15))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.drip.coral)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(isActivating)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.drip.background.shadow(color: .black.opacity(0.2), radius: 8, y: -4))
    }

    // MARK: - Logic

    private var weeksUntilRace: Int {
        let days = Calendar.current.dateComponents([.day], from: Date(), to: raceDate).day ?? 0
        return max(1, days / 7)
    }

    /// Generate the preview week — rotates the qualityOffsets pattern to start
    /// at anchorDay. Long run is placed at longRunOffset days after anchor.
    private var previewWeek: [PreviewDay] {
        let anchorIdx = anchorDay.index  // 0=Mon..6=Sun
        var days: [PreviewDay] = []
        for i in 0..<7 {
            let weekday = Weekday.allCases[(anchorIdx + i) % 7]
            let kind: WorkoutKind
            if qualityOffsets.contains(i) {
                let qIdx = qualityOffsets.firstIndex(of: i)! + 1
                kind = .quality(label: "Quality \(qIdx)")
            } else if i == longRunOffset && !qualityOffsets.contains(longRunOffset) {
                kind = .longRun
            } else if i == longRunOffset && qualityOffsets.contains(longRunOffset) {
                kind = .qualityAndLong
            } else if i == lastQualityOffset() + 1 {
                kind = .recovery
            } else {
                kind = .easy
            }
            days.append(PreviewDay(weekday: weekday, kind: kind))
        }
        return days
    }

    private func lastQualityOffset() -> Int {
        qualityOffsets.max() ?? 0
    }

    private func activate() async {
        isActivating = true
        errorMessage = nil

        // 1. Parse goal time text into seconds (if provided)
        let goalTimeSeconds = parseGoalTime(goalTimeText, distance: raceDistance)

        // 2. Map PlanDistance to the edge function's race distance string
        let raceDistString: String = {
            switch raceDistance {
            case .fiveK: return "5k"
            case .tenK: return "10k"
            case .half: return "half_marathon"
            case .marathon: return "marathon"
            }
        }()

        // 3. Map anchor day to preferred long run day (0-indexed for Weekday lookup)
        let longRunDayIndex = (anchorDay.index + longRunOffset) % 7

        // 4. Build a structured message that provides all context for plan generation
        let startDate = Date()
        let qualityDayNames = qualityOffsets.map { offset in
            Weekday.allCases[(anchorDay.index + offset) % 7].fullName
        }.joined(separator: ", ")

        let message = """
        Generate a \(raceDistance.displayName) training plan. \
        Quality days: \(qualityCount) per week on \(qualityDayNames). \
        Long run day: \(Weekday.allCases[longRunDayIndex].fullName). \
        Weekly mileage target: \(weeklyMileage) miles. \
        Runs per week: \(qualityCount + 2). \
        \(goalTimeText.isEmpty ? "" : "Goal time: \(goalTimeText). ")\
        Preferred long run day: \(Weekday.allCases[longRunDayIndex].fullName).
        """

        let aiService = AITrainingPlanService()
        do {
            let response = try await aiService.sendMessage(
                message,
                conversationId: nil,
                startDate: startDate,
                raceDate: raceDate,
                goalTimeSeconds: goalTimeSeconds,
                currentWeeklyMileage: Double(weeklyMileage)
            )

            guard let planData = response.planData else {
                // AI returned a question instead of a plan — shouldn't happen with
                // all inputs pre-filled, but handle gracefully
                await MainActor.run {
                    isActivating = false
                    errorMessage = response.message
                }
                return
            }

            // 5. Convert AI response to the import format and persist
            let importedResponse = aiService.toImportedPlanResponse(planData)

            let planName = planData.plan.name.isEmpty
                ? "\(raceDistance.displayName) Plan"
                : planData.plan.name

            let defaultGoal: Int = {
                switch raceDistance {
                case .fiveK: return 1800
                case .tenK: return 3600
                case .half: return 7200
                case .marathon: return 14400
                }
            }()

            // applyImportedPlan reads from importService.importedPlanResponse
            viewModel.importService.importedPlanResponse = importedResponse

            let success = await viewModel.importService.applyImportedPlan(
                name: planName,
                startDate: startDate,
                raceDistance: raceDistString,
                goalTimeSeconds: goalTimeSeconds ?? defaultGoal
            )

            if !success {
                await MainActor.run {
                    isActivating = false
                    errorMessage = viewModel.errorMessage ?? "Failed to save the training plan"
                }
                return
            }

            await MainActor.run {
                isActivating = false
                dismiss()
            }
        } catch {
            await MainActor.run {
                isActivating = false
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Parse a goal time string like "3:30:00" or "22:00" into total seconds
    private func parseGoalTime(_ text: String, distance: PlanDistance) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        let parts = trimmed.split(separator: ":").compactMap { Int($0) }
        switch parts.count {
        case 3: return parts[0] * 3600 + parts[1] * 60 + parts[2]
        case 2:
            // For half/marathon, MM:SS doesn't make sense — treat as H:MM
            switch distance {
            case .half, .marathon: return parts[0] * 3600 + parts[1] * 60
            case .fiveK, .tenK: return parts[0] * 60 + parts[1]
            }
        default: return nil
        }
    }

    // MARK: - Defaults

    /// Recommended quality day spacing — biased toward 3-day gaps for 2-day,
    /// even spread for higher counts.
    static func defaultOffsets(for count: Int) -> [Int] {
        switch count {
        case 1: return [0]
        case 2: return [0, 3]            // T+F or W+Sat with 3-day gap
        case 3: return [0, 2, 4]         // M/W/F style
        case 4: return [0, 2, 4, 6]      // M/W/F/Sun
        default: return [0]
        }
    }

    static func defaultLongRunOffset(for count: Int, qualityOffsets: [Int]) -> Int {
        // Long run typically 5-6 days after anchor for 2-quality plans.
        // For 3-4 quality plans, long run often coincides with last quality.
        switch count {
        case 1: return 5
        case 2: return 5
        case 3, 4: return qualityOffsets.last ?? 6
        default: return 6
        }
    }
}

// MARK: - Step types

private enum BuilderStep {
    case goal, schedule, preview

    var title: String {
        switch self {
        case .goal: "Goal"
        case .schedule: "Schedule"
        case .preview: "Preview"
        }
    }

    func next() -> BuilderStep {
        switch self {
        case .goal: .schedule
        case .schedule: .preview
        case .preview: .preview
        }
    }
    func previous() -> BuilderStep {
        switch self {
        case .goal: .goal
        case .schedule: .goal
        case .preview: .schedule
        }
    }
}

private struct StepIndicator: View {
    let current: BuilderStep
    var body: some View {
        HStack(spacing: 6) {
            ForEach([BuilderStep.goal, .schedule, .preview], id: \.title) { step in
                Capsule()
                    .fill(step == current ? Color.drip.coral : Color.drip.textTertiary.opacity(0.25))
                    .frame(height: 4)
            }
        }
    }
}

private struct BuilderSectionHeader: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.dripCaption(11))
            .tracking(1.2)
            .foregroundStyle(Color.drip.textSecondary)
    }
}

// MARK: - Pickers

enum PlanDistance: String, CaseIterable, Identifiable {
    case fiveK = "5K"
    case tenK = "10K"
    case half = "Half"
    case marathon = "Marathon"
    var id: String { rawValue }
    var displayName: String { rawValue }
    var suggestedMileage: Int {
        switch self {
        case .fiveK: 25
        case .tenK: 35
        case .half: 45
        case .marathon: 55
        }
    }
    var placeholderTime: String {
        switch self {
        case .fiveK: "MM:SS  e.g. 22:00"
        case .tenK: "MM:SS  e.g. 45:00"
        case .half: "H:MM:SS  e.g. 1:40:00"
        case .marathon: "H:MM:SS  e.g. 3:30:00"
        }
    }
    var formatHint: String {
        switch self {
        case .fiveK, .tenK: "Use MM:SS format"
        case .half, .marathon: "Use H:MM:SS format"
        }
    }
}

private struct DistancePill: View {
    let distance: PlanDistance
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(distance.displayName)
                .font(.dripLabel(14))
                .foregroundStyle(selected ? .white : Color.drip.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(selected ? Color.drip.coral : Color.drip.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}

private struct QualityCountButton: View {
    let count: Int
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text("\(count)")
                .font(.dripDisplay(20))
                .foregroundStyle(selected ? .white : Color.drip.textPrimary)
                .frame(width: 56, height: 56)
                .background(selected ? Color.drip.coral : Color.drip.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

private struct DayPill: View {
    let label: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.dripLabel(13))
                .foregroundStyle(selected ? .white : Color.drip.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(selected ? Color.drip.coral : Color.drip.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

enum Weekday: Int, CaseIterable, Identifiable {
    case monday = 0, tuesday, wednesday, thursday, friday, saturday, sunday
    var id: Int { rawValue }
    var index: Int { rawValue }
    var shortName: String {
        switch self {
        case .monday: "M"
        case .tuesday: "T"
        case .wednesday: "W"
        case .thursday: "Th"
        case .friday: "F"
        case .saturday: "S"
        case .sunday: "Sun"
        }
    }
    var fullName: String {
        switch self {
        case .monday: "Monday"
        case .tuesday: "Tuesday"
        case .wednesday: "Wednesday"
        case .thursday: "Thursday"
        case .friday: "Friday"
        case .saturday: "Saturday"
        case .sunday: "Sunday"
        }
    }
}

// MARK: - Preview week model

private enum WorkoutKind {
    case easy, recovery, longRun, quality(label: String), qualityAndLong
    var label: String {
        switch self {
        case .easy: "Easy"
        case .recovery: "Recovery"
        case .longRun: "Long Run"
        case .quality(let l): l
        case .qualityAndLong: "Long Run + Quality"
        }
    }
    var icon: String {
        switch self {
        case .easy: "figure.run"
        case .recovery: "leaf.fill"
        case .longRun: "figure.walk.motion"
        case .quality, .qualityAndLong: "bolt.fill"
        }
    }
    var color: Color {
        switch self {
        case .easy: .green.opacity(0.7)
        case .recovery: .gray
        case .longRun: .blue
        case .quality, .qualityAndLong: Color.drip.coral
        }
    }
}

private struct PreviewDay {
    let weekday: Weekday
    let kind: WorkoutKind
}

private struct PreviewDayRow: View {
    let day: PreviewDay
    var body: some View {
        HStack(spacing: 12) {
            Text(day.weekday.shortName)
                .font(.dripLabel(13))
                .foregroundStyle(Color.drip.textSecondary)
                .frame(width: 32, alignment: .leading)
            Image(systemName: day.kind.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(day.kind.color)
                .frame(width: 20)
            Text(day.kind.label)
                .font(.dripBody(14))
                .foregroundStyle(Color.drip.textPrimary)
            Spacer()
        }
        .padding(.vertical, 10)
    }
}

private func formatDate(_ d: Date) -> String {
    let f = DateFormatter()
    f.dateFormat = "MMM d, yyyy"
    return f.string(from: d)
}
