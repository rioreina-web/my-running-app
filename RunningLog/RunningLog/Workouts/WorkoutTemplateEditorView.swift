//
//  WorkoutTemplateEditorView.swift
//  RunningLog
//
//  Create or edit a reusable workout template.
//  Uses the same step-editing paradigm as DayDetailSheet.
//

import SwiftUI

// MARK: - WorkoutTemplateEditorView

struct WorkoutTemplateEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CoachViewModel.self) private var viewModel

    let existingTemplate: WorkoutTemplate?
    /// When set, Save stores to plan inline instead of the template library
    var inlineSaveCallback: ((WorkoutTemplate) -> Void)? = nil

    // Form state
    @State private var name = ""
    @State private var workoutType: ScheduledWorkoutType = .intervals
    @State private var description = ""
    @State private var tagsText = ""   // comma-separated input
    @State private var isPublic = false

    // Steps
    @State private var steps: [EditableWorkoutStep] = []

    // Metrics (auto-calculated from steps or manually overridden)
    @State private var estimatedDistanceMiles: String = ""
    @State private var estimatedDurationMinutes: String = ""

    @State private var isSaving = false
    @State private var showRepeatSheet = false
    @State private var showDiscardAlert = false

    // Preview paces — read from pace chart's stored goal (same keys as PaceChartViewModel)
    @AppStorage("paceChart_selectedDistance") private var paceChartDistanceRaw: String = "marathon"
    @AppStorage("paceChart_goalTimeSeconds") private var paceChartGoalSeconds: Int = 14400

    private var previewRaceDistance: RaceDistance {
        switch paceChartDistanceRaw {
        case "marathon": return .marathon
        case "half": return .halfMarathon
        case "10K", "10mi": return .tenK
        case "5K", "3K": return .fiveK
        case "mile", "1500m": return .mile1500
        default: return .marathon
        }
    }

    private var previewPaces: EquivalentPaces {
        EquivalentPaces(raceDistance: previewRaceDistance, goalTimeSeconds: max(paceChartGoalSeconds, 60))
    }

    private var previewGoalLabel: String {
        let dist: String
        switch paceChartDistanceRaw {
        case "marathon": dist = "Marathon"
        case "half": dist = "Half Marathon"
        case "10K": dist = "10K"
        case "10mi": dist = "10 Mile"
        case "5K": dist = "5K"
        case "3K": dist = "3K"
        case "mile": dist = "Mile"
        case "1500m": dist = "1500m"
        default: dist = "Marathon"
        }
        return "\(dist) · \(PaceCalculator.formatSeconds(paceChartGoalSeconds))"
    }

    private var isEditing: Bool { existingTemplate != nil }

    private var hasUnsavedWork: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty || steps.count > 1 || !description.isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DripBackground().ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // Name + type
                        metaSection

                        // Preview pace reference
                        previewPaceSection

                        // Steps builder
                        stepsSection

                        // Metrics
                        metricsSection

                        // Description + tags
                        detailSection

                        // Visibility
                        visibilitySection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 60)
                }
            }
            .navigationTitle(isEditing ? "Edit Template" : "New Template")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Discard Changes?", isPresented: $showDiscardAlert) {
                Button("Keep Editing", role: .cancel) { }
                Button("Discard", role: .destructive) { dismiss() }
            } message: {
                Text("You have unsaved changes. Are you sure you want to discard this workout?")
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        if hasUnsavedWork {
                            showDiscardAlert = true
                        } else {
                            dismiss()
                        }
                    }
                    .font(.dripLabel(14))
                    .foregroundStyle(Color.drip.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Text("Save")
                                .font(.dripLabel(14))
                                .foregroundStyle(name.isEmpty ? Color.drip.textTertiary : Color.drip.coral)
                        }
                    }
                    .disabled(name.isEmpty || isSaving)
                }
            }
        }
        .onAppear { prefill() }
        .interactiveDismissDisabled(hasUnsavedWork)
        .sheet(isPresented: $showRepeatSheet) {
            RepeatBlockSheet(steps: steps) { expanded in
                steps = expanded
                for i in steps.indices { steps[i].order = i }
            }
        }
    }

    // MARK: - Meta Section

    private var metaSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("WORKOUT DETAILS")
                .font(.dripCaption(11))
                .foregroundStyle(Color.drip.textTertiary)

            VStack(spacing: 0) {
                // Name
                TextField("Name (e.g. 10 x 1K at 5K pace)", text: $name)
                    .font(.dripBody(15))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color.drip.cardBackground)

                Divider().background(Color.drip.divider)

                // Workout type picker
                HStack {
                    Text("Type")
                        .font(.dripBody(15))
                        .foregroundStyle(Color.drip.textPrimary)
                    Spacer()
                    Picker("Type", selection: $workoutType) {
                        ForEach(ScheduledWorkoutType.allCases.filter { $0 != .rest }, id: \.self) { type in
                            HStack {
                                Image(systemName: type.icon)
                                Text(type.displayName)
                            }
                            .tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(workoutType.color)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.drip.cardBackground)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.drip.divider, lineWidth: 1)
            )
        }
    }

    // MARK: - Preview Pace Section

    private var previewPaceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("PREVIEW PACES")
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textTertiary)
                Spacer()
                Text(previewGoalLabel)
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textSecondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(previewPaces.allPaces, id: \.0) { (named, pace) in
                        VStack(spacing: 2) {
                            Text(named.shortName)
                                .font(.dripCaption(9))
                                .foregroundStyle(named.color)
                            Text(EquivalentPaces.formatPace(pace))
                                .font(.dripStat(11))
                                .foregroundStyle(Color.drip.textPrimary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(named.color.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
    }

    // MARK: - Steps Section

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("WORKOUT STEPS")
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textTertiary)
                Spacer()
                if steps.count >= 2 {
                    Button {
                        showRepeatSheet = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "repeat")
                                .font(.system(size: 12))
                            Text("Repeat Block")
                                .font(.dripCaption(12))
                        }
                        .foregroundStyle(Color.drip.textSecondary)
                    }
                }
                Button {
                    let newStep = EditableWorkoutStep(order: steps.count)
                    steps.append(newStep)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 14))
                        Text("Add Step")
                            .font(.dripCaption(12))
                    }
                    .foregroundStyle(Color.drip.coral)
                }
            }
            Text("Paces preview based on 4:00 marathon. Each athlete sees their own goal paces.")
                .font(.dripCaption(11))
                .foregroundStyle(Color.drip.textTertiary)
                .italic()

            if steps.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 28))
                            .foregroundStyle(Color.drip.textTertiary)
                        Text("No steps yet — tap Add Step")
                            .font(.dripBody(14))
                            .foregroundStyle(Color.drip.textSecondary)
                    }
                    .padding(.vertical, 24)
                    Spacer()
                }
                .background(Color.drip.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.drip.divider, lineWidth: 1)
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { idx, step in
                        TemplateStepRow(
                            step: $steps[idx],
                            stepIndex: idx,
                            totalSteps: steps.count,
                            previewPaces: previewPaces,
                            onDelete: { steps.remove(at: idx) },
                            onMoveUp: idx > 0 ? { steps.swapAt(idx, idx - 1) } : nil,
                            onMoveDown: idx < steps.count - 1 ? { steps.swapAt(idx, idx + 1) } : nil
                        )

                        if idx < steps.count - 1 {
                            Divider()
                                .background(Color.drip.divider)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.drip.divider, lineWidth: 1)
                )

                // Add step button at bottom
                Button {
                    steps.append(EditableWorkoutStep(order: steps.count))
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 14))
                        Text("Add Step")
                            .font(.dripCaption(12))
                    }
                    .foregroundStyle(Color.drip.coral)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.drip.coral.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    // MARK: - Metrics Section

    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("METRICS (OPTIONAL)")
                .font(.dripCaption(11))
                .foregroundStyle(Color.drip.textTertiary)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Distance (mi)")
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.textTertiary)
                    TextField("e.g. 8.5", text: $estimatedDistanceMiles)
                        .font(.dripStat(16))
                        .keyboardType(.decimalPad)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.drip.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.drip.divider, lineWidth: 1)
                        )
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Duration (min)")
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.textTertiary)
                    TextField("e.g. 75", text: $estimatedDurationMinutes)
                        .font(.dripStat(16))
                        .keyboardType(.numberPad)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.drip.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.drip.divider, lineWidth: 1)
                        )
                }
            }
        }
    }

    // MARK: - Detail Section

    private var detailSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DESCRIPTION & TAGS")
                .font(.dripCaption(11))
                .foregroundStyle(Color.drip.textTertiary)

            VStack(spacing: 0) {
                TextField("Description (optional)", text: $description, axis: .vertical)
                    .font(.dripBody(15))
                    .lineLimit(3...6)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color.drip.cardBackground)

                Divider().background(Color.drip.divider)

                HStack(spacing: 8) {
                    Image(systemName: "tag")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.drip.textTertiary)
                    TextField("Tags (comma-separated: intervals, track, vo2max)", text: $tagsText)
                        .font(.dripBody(14))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color.drip.cardBackground)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.drip.divider, lineWidth: 1)
            )
        }
    }

    // MARK: - Visibility Section

    private var visibilitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("VISIBILITY")
                .font(.dripCaption(11))
                .foregroundStyle(Color.drip.textTertiary)

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Make public")
                        .font(.dripBody(15))
                        .foregroundStyle(Color.drip.textPrimary)
                    Text("Other coaches can browse and copy this template")
                        .font(.dripCaption(12))
                        .foregroundStyle(Color.drip.textSecondary)
                }
                Spacer()
                Toggle("", isOn: $isPublic)
                    .tint(Color.drip.coral)
                    .labelsHidden()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.drip.divider, lineWidth: 1)
            )
        }
    }

    // MARK: - Save

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        let tags = tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // Build a PlannedWorkout from steps using the user's actual goal pace
        let saveEquivPaces = previewPaces
        let saveRacePace = Double(paceChartGoalSeconds) / previewRaceDistance.distanceInMiles
        let plannedSteps = steps.enumerated().map { idx, editStep in
            editStep.toWorkoutStep(racePaceSeconds: saveRacePace, equivalentPaces: saveEquivPaces)
        }

        let distMiles = Double(estimatedDistanceMiles)
        let durationMins = Int(estimatedDurationMinutes)

        let workout = PlannedWorkout(
            id: existingTemplate?.workoutData.id ?? UUID(),
            name: name,
            category: categoryFor(workoutType),
            trainingPhase: .specific,
            description: description,
            steps: plannedSteps,
            totalDistanceMiles: distMiles,
            estimatedDurationMinutes: distMiles.map { _ in Double(durationMins ?? 0) } ?? Double(durationMins ?? 0),
            signatureType: nil,
            createdAt: existingTemplate?.workoutData.createdAt ?? Date()
        )

        let template = WorkoutTemplate(
            id: existingTemplate?.id ?? UUID(),
            coachId: existingTemplate?.coachId ?? viewModel.coachProfile?.id ?? UUID(),
            name: name,
            workoutType: workoutType,
            description: description.isEmpty ? nil : description,
            tags: tags,
            workoutData: workout,
            estimatedDistanceMiles: distMiles,
            estimatedDurationMinutes: durationMins,
            isPublic: isPublic,
            useCount: existingTemplate?.useCount ?? 0,
            createdAt: existingTemplate?.createdAt ?? Date(),
            updatedAt: Date()
        )

        if let callback = inlineSaveCallback {
            callback(template)
            dismiss()
            return
        }

        if existingTemplate != nil {
            await viewModel.updateWorkoutTemplate(template)
        } else {
            _ = await viewModel.saveWorkoutTemplate(template)
        }

        dismiss()
    }

    private func prefill() {
        guard let t = existingTemplate else {
            // Default: start with a single blank active step — user adds warmup if needed
            steps = [
                EditableWorkoutStep(order: 0),
            ]
            steps[0].stepType = .active
            steps[0].durationValue = 0
            steps[0].durationType = .distanceMiles
            return
        }
        name = t.name
        workoutType = t.workoutType
        description = t.description ?? ""
        tagsText = t.tags.joined(separator: ", ")
        isPublic = t.isPublic
        estimatedDistanceMiles = t.estimatedDistanceMiles.map { String(format: "%.1f", $0) } ?? ""
        estimatedDurationMinutes = t.estimatedDurationMinutes.map { String($0) } ?? ""

        let loadEquivPaces = previewPaces
        let loadRacePace = Double(paceChartGoalSeconds) / previewRaceDistance.distanceInMiles
        steps = t.workoutData.steps.map {
            EditableWorkoutStep(from: $0, equivalentPaces: loadEquivPaces, racePaceSeconds: loadRacePace)
        }
    }

    private func categoryFor(_ type: ScheduledWorkoutType) -> PlannedWorkoutCategory {
        switch type {
        case .easy, .recovery: return .regeneration
        case .longRun: return .fundamental
        case .tempo, .progression, .strides: return .special
        case .intervals, .race: return .specific
        default: return .regeneration
        }
    }
}

// MARK: - TemplateStepRow

struct TemplateStepRow: View {
    @Binding var step: EditableWorkoutStep
    let stepIndex: Int
    let totalSteps: Int
    let previewPaces: EquivalentPaces
    let onDelete: () -> Void
    let onMoveUp: (() -> Void)?
    let onMoveDown: (() -> Void)?

    // Default 4:00 marathon for preview when no athlete goal available
    static let defaultPaces = EquivalentPaces(raceDistance: .marathon, goalTimeSeconds: 14400)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                // Step type color bar
                RoundedRectangle(cornerRadius: 3)
                    .fill(step.stepType.color)
                    .frame(width: 4)
                    .frame(minHeight: 44)

                VStack(alignment: .leading, spacing: 8) {
                    // Type + controls
                    HStack {
                        Picker("", selection: $step.stepType) {
                            ForEach(PlannedWorkoutStep.StepType.allCases, id: \.self) { type in
                                Text(type.displayName).tag(type)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(step.stepType.color)
                        .font(.dripCaption(12))
                        .onChange(of: step.stepType) { oldType, newType in
                            if oldType.defaultPace != newType.defaultPace {
                                step.paceSelection = .namedPace(newType.defaultPace)
                            }
                        }

                        Spacer()

                        HStack(spacing: 8) {
                            if let up = onMoveUp {
                                Button(action: up) {
                                    Image(systemName: "arrow.up")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color.drip.textTertiary)
                                }
                            }
                            if let down = onMoveDown {
                                Button(action: down) {
                                    Image(systemName: "arrow.down")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color.drip.textTertiary)
                                }
                            }
                            Button(action: onDelete) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(Color.drip.textTertiary)
                            }
                        }
                    }

                    // Duration
                    HStack(spacing: 8) {
                        if step.durationType == .timeSeconds {
                            // MM:SS input for time-based durations
                            TimeIntervalField(totalSeconds: $step.durationValue)
                        } else {
                            TextField("Value", value: $step.durationValue, format: .number)
                                .font(.dripStat(15))
                                .keyboardType(.decimalPad)
                                .frame(width: 60)
                        }

                        Picker("", selection: $step.durationType) {
                            ForEach(PlannedWorkoutStep.DurationType.allCases, id: \.self) { dt in
                                Text(dt.displayLabel).tag(dt)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(Color.drip.textSecondary)
                        .font(.dripCaption(12))
                    }

                    // Target intensity (Pace or Heart Rate)
                    TargetIntensityPicker(
                        step: $step,
                        equivalentPaces: previewPaces,
                        racePaceSeconds: previewPaces.mpPace
                    )
                }
                .padding(.trailing, 4)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.drip.cardBackground)
        }
    }
}

// MARK: - RepeatBlockSheet

struct RepeatBlockSheet: View {
    @Environment(\.dismiss) private var dismiss

    let steps: [EditableWorkoutStep]
    let onConfirm: ([EditableWorkoutStep]) -> Void

    @State private var selectedIndices: Set<Int> = []
    @State private var repeatCount: Int = 5

    var selectedBlock: [EditableWorkoutStep] {
        steps.indices
            .filter { selectedIndices.contains($0) }
            .map { steps[$0] }
    }

    var canApply: Bool { selectedIndices.count >= 1 }

    var body: some View {
        NavigationStack {
            ZStack {
                DripBackground().ignoresSafeArea()

                VStack(spacing: 20) {
                    // Step selector
                    VStack(alignment: .leading, spacing: 8) {
                        Text("SELECT STEPS TO REPEAT")
                            .font(.dripCaption(11))
                            .foregroundStyle(Color.drip.textTertiary)
                            .tracking(1.0)

                        VStack(spacing: 0) {
                            ForEach(Array(steps.enumerated()), id: \.offset) { idx, step in
                                Button {
                                    if selectedIndices.contains(idx) {
                                        selectedIndices.remove(idx)
                                    } else {
                                        selectedIndices.insert(idx)
                                    }
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: selectedIndices.contains(idx) ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(selectedIndices.contains(idx) ? Color.drip.coral : Color.drip.textTertiary)
                                            .font(.system(size: 20))

                                        Circle()
                                            .fill(step.stepType.color)
                                            .frame(width: 8, height: 8)

                                        Text(step.stepType.displayName)
                                            .font(.dripBody(14))
                                            .foregroundStyle(Color.drip.textPrimary)

                                        Text("·")
                                            .foregroundStyle(Color.drip.textTertiary)

                                        Text(step.durationType == .timeSeconds ? "\(formatMMSS(step.durationValue))" : "\(step.durationValue.formatted()) \(step.durationType.displayLabel)")
                                            .font(.dripBody(14))
                                            .foregroundStyle(Color.drip.textSecondary)

                                        if case .namedPace(let p) = step.paceSelection {
                                            Text("@ \(p.shortName)")
                                                .font(.dripCaption(12))
                                                .foregroundStyle(p.color)
                                        }

                                        Spacer()
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(selectedIndices.contains(idx) ? Color.drip.coral.opacity(0.08) : Color.drip.cardBackground)
                                }

                                if idx < steps.count - 1 {
                                    Divider().background(Color.drip.divider)
                                }
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.drip.divider, lineWidth: 1))
                    }

                    // Repeat count
                    HStack {
                        Text("Repeat times")
                            .font(.dripBody(15))
                            .foregroundStyle(Color.drip.textPrimary)
                        Spacer()
                        Stepper("", value: $repeatCount, in: 2...20)
                            .labelsHidden()
                        Text("\(repeatCount)×")
                            .font(.dripStat(16))
                            .foregroundStyle(Color.drip.coral)
                            .frame(width: 36)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color.drip.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.drip.divider, lineWidth: 1))

                    // Summary
                    if canApply {
                        let kept = steps.count - selectedIndices.count
                        let total = kept + selectedIndices.count * repeatCount
                        Text("\(selectedIndices.count) step\(selectedIndices.count == 1 ? "" : "s") × \(repeatCount) reps = \(total) steps total")
                            .font(.dripCaption(12))
                            .foregroundStyle(Color.drip.textSecondary)
                    }

                    // Confirm
                    Button {
                        let defaultPaces = TemplateStepRow.defaultPaces
                        var result: [EditableWorkoutStep] = []

                        // Keep non-selected steps in their original positions before the first selected index
                        let firstSelected = selectedIndices.min() ?? 0
                        result = steps.indices
                            .filter { !selectedIndices.contains($0) && $0 < firstSelected }
                            .map { steps[$0] }

                        // Append the selected block repeatCount times
                        for _ in 0..<repeatCount {
                            for s in selectedBlock {
                                let planned = s.toWorkoutStep(
                                    racePaceSeconds: defaultPaces.mpPace,
                                    equivalentPaces: defaultPaces
                                )
                                var copy = EditableWorkoutStep(
                                    from: PlannedWorkoutStep(
                                        id: UUID(),
                                        stepType: planned.stepType,
                                        durationType: planned.durationType,
                                        durationValue: planned.durationValue,
                                        targetPaceIntensity: planned.targetPaceIntensity,
                                        targetHR: planned.targetHR,
                                        notes: planned.notes,
                                        order: planned.order
                                    ),
                                    equivalentPaces: defaultPaces,
                                    racePaceSeconds: defaultPaces.mpPace
                                )
                                copy.paceSelection = s.paceSelection
                                copy.hrTarget = s.hrTarget
                                result.append(copy)
                            }
                        }

                        // Append any non-selected steps after the last selected index
                        let lastSelected = selectedIndices.max() ?? 0
                        let trailing = steps.indices
                            .filter { !selectedIndices.contains($0) && $0 > lastSelected }
                            .map { steps[$0] }
                        result.append(contentsOf: trailing)

                        onConfirm(result)
                        dismiss()
                    } label: {
                        Text("Apply Repeat")
                            .font(.dripLabel(16))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(canApply ? Color.drip.coral : Color.drip.textTertiary)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(!canApply)

                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle("Repeat Block")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(.dripLabel(14))
                        .foregroundStyle(Color.drip.textSecondary)
                }
            }
        }
    }
}

// MARK: - Time Interval Field (MM:SS)

private func formatMMSS(_ totalSeconds: Double) -> String {
    let secs = Int(totalSeconds)
    let m = secs / 60
    let s = secs % 60
    return String(format: "%d:%02d", m, s)
}

struct TimeIntervalField: View {
    @Binding var totalSeconds: Double

    @State private var minText: String
    @State private var secText: String

    init(totalSeconds: Binding<Double>) {
        self._totalSeconds = totalSeconds
        let total = Int(totalSeconds.wrappedValue)
        if total > 0 {
            self._minText = State(initialValue: "\(total / 60)")
            self._secText = State(initialValue: String(format: "%02d", total % 60))
        } else {
            self._minText = State(initialValue: "")
            self._secText = State(initialValue: "")
        }
    }

    var body: some View {
        HStack(spacing: 2) {
            TextField("0", text: $minText)
                .font(.dripStat(15))
                .keyboardType(.numberPad)
                .frame(width: 28)
                .multilineTextAlignment(.trailing)
                .onChange(of: minText) { sync() }

            Text(":")
                .font(.dripStat(15))
                .foregroundStyle(Color.drip.textSecondary)

            TextField("00", text: $secText)
                .font(.dripStat(15))
                .keyboardType(.numberPad)
                .frame(width: 28)
                .onChange(of: secText) { sync() }
        }
    }

    private func sync() {
        let m = Int(minText) ?? 0
        let s = min(59, Int(secText) ?? 0)
        totalSeconds = Double(max(0, m) * 60 + max(0, s))
    }
}
