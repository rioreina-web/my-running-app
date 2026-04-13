//
//  PlanTemplateBuilderView.swift
//  RunningLog
//
//  The main plan builder: week selector + 7-day grid.
//  Coach picks a week, taps any day cell to assign a workout from their library.
//

import SwiftUI

// MARK: - PlanTemplateBuilderView

struct PlanTemplateBuilderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CoachViewModel.self) private var viewModel

    /// Pass nil to create a new plan template
    let existingPlan: PlanTemplate?

    // Plan metadata
    @State private var planName = ""
    @State private var targetDistance = "marathon"
    @State private var durationWeeks = 16

    // Week data
    @State private var weeks: [PlanTemplateWeek] = []
    @State private var selectedWeekIndex = 0

    // UI state
    @State private var showWorkoutPicker = false
    @State private var pickerDayOfWeek = 0
    @State private var pickerSlot = 0  // 0 = primary, 1 = double
    @State private var showHeaderEditor = false
    @State private var isSaving = false
    @State private var showPublishSuccess = false
    @State private var generatedJoinCode = ""
    @State private var showInlineEditor = false
    @State private var inlineEditTemplate: WorkoutTemplate? = nil
    @State private var inlineEditDay = 0
    @State private var inlineEditSlot = 0

    private var isEditing: Bool { existingPlan != nil }
    private var selectedWeek: PlanTemplateWeek { weeks[safe: selectedWeekIndex] ?? emptyWeek(1) }

    var body: some View {
        NavigationStack {
            ZStack {
                DripBackground().ignoresSafeArea()

                VStack(spacing: 0) {
                    // Plan header
                    planHeaderSection

                    Divider().background(Color.drip.divider)

                    // Week chip scroller
                    weekSelector

                    Divider().background(Color.drip.divider)

                    // Week theme / notes
                    if !weeks.isEmpty {
                        weekHeaderRow
                    }

                    // Day grid
                    if weeks.isEmpty {
                        loadingState
                    } else {
                        dayGrid
                    }

                    Spacer()
                }
            }
            .navigationTitle(isEditing ? "Edit Plan" : "New Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(.dripLabel(14))
                        .foregroundStyle(Color.drip.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            Task { await saveDraft() }
                        } label: {
                            Label("Save Draft", systemImage: "square.and.arrow.down")
                        }
                        Button {
                            Task { await saveAndPublish() }
                        } label: {
                            Label("Save & Publish", systemImage: "checkmark.seal.fill")
                        }
                    } label: {
                        if isSaving {
                            ProgressView().scaleEffect(0.85)
                        } else {
                            Text("Save")
                                .font(.dripLabel(14))
                                .foregroundStyle(planName.isEmpty ? Color.drip.textTertiary : Color.drip.coral)
                        }
                    }
                    .disabled(planName.isEmpty || isSaving)
                }
            }
            .sheet(isPresented: $showWorkoutPicker) {
                let workout = workoutFor(day: pickerDayOfWeek, slot: pickerSlot)
                CoachWorkoutPickerSheet(
                    dayOfWeek: pickerDayOfWeek,
                    weekNumber: selectedWeek.weekNumber,
                    existingWorkout: workout
                ) { assigned in
                    setWorkout(assigned, forDay: pickerDayOfWeek, slot: pickerSlot)
                }
                .environment(viewModel)
            }
            .sheet(isPresented: $showInlineEditor) {
                if let tmpl = inlineEditTemplate {
                    WorkoutTemplateEditorView(existingTemplate: tmpl) { saved in
                        // Store the edited workout back into the plan day inline
                        let updated = PlanTemplateWorkout(
                            dayOfWeek: inlineEditDay,
                            workoutTemplateId: saved.id,
                            workoutType: saved.workoutType,
                            workoutData: saved.workoutData,
                            notes: ""
                        )
                        setWorkout(updated, forDay: inlineEditDay, slot: inlineEditSlot)
                    }
                    .environment(viewModel)
                }
            }
            .alert("Plan Published!", isPresented: $showPublishSuccess) {
                Button("Copy Join Code") {
                    UIPasteboard.general.string = generatedJoinCode
                }
                Button("Done", role: .cancel) { dismiss() }
            } message: {
                Text("Share this code with athletes to subscribe:\n\n\(generatedJoinCode)")
            }
        }
        .onAppear { setup() }
    }

    // MARK: - Plan Header

    private var planHeaderSection: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    if planName.isEmpty {
                        Text("Untitled Plan")
                            .font(.dripLabel(17))
                            .foregroundStyle(Color.drip.textTertiary)
                    } else {
                        Text(planName)
                            .font(.dripLabel(17))
                            .foregroundStyle(Color.drip.textPrimary)
                            .lineLimit(1)
                    }
                    HStack(spacing: 6) {
                        Text(displayDistance)
                            .font(.dripCaption(12))
                            .foregroundStyle(Color.drip.coral)
                        Text("·")
                            .font(.dripCaption(12))
                            .foregroundStyle(Color.drip.textTertiary)
                        Text("\(durationWeeks) weeks")
                            .font(.dripCaption(12))
                            .foregroundStyle(Color.drip.textSecondary)
                        let totalMiles = weeks.reduce(0.0) { $0 + $1.totalPlannedMiles }
                        if totalMiles > 0 {
                            Text("·")
                                .font(.dripCaption(12))
                                .foregroundStyle(Color.drip.textTertiary)
                            Text(String(format: "%.0f mi total", totalMiles))
                                .font(.dripCaption(12))
                                .foregroundStyle(Color.drip.textSecondary)
                        }
                    }
                }
                Spacer()
                Button {
                    showHeaderEditor = true
                } label: {
                    Image(systemName: "pencil.circle")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.drip.coral)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(Color.drip.cardBackground)
        .sheet(isPresented: $showHeaderEditor) {
            PlanHeaderEditorSheet(
                name: $planName,
                targetDistance: $targetDistance,
                durationWeeks: $durationWeeks,
                onSave: { rebuildWeeksIfNeeded() }
            )
        }
    }

    private var displayDistance: String {
        switch targetDistance {
        case "marathon": return "Marathon"
        case "half_marathon": return "Half Marathon"
        case "10k": return "10K"
        case "5k": return "5K"
        case "mile": return "Mile"
        case "custom": return "Custom"
        default: return targetDistance.capitalized
        }
    }

    // MARK: - Week Selector

    private var weekSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(weeks.indices, id: \.self) { idx in
                    let week = weeks[idx]
                    let hasWorkouts = week.workouts.filter { !$0.isRest }.count > 0
                    Button {
                        selectedWeekIndex = idx
                    } label: {
                        VStack(spacing: 2) {
                            Text("W\(week.weekNumber)")
                                .font(.dripLabel(12))
                                .foregroundStyle(selectedWeekIndex == idx ? .white : Color.drip.textPrimary)
                            if hasWorkouts {
                                Circle()
                                    .fill(selectedWeekIndex == idx ? .white.opacity(0.7) : Color.drip.coral)
                                    .frame(width: 4, height: 4)
                            }
                        }
                        .frame(width: 38, height: 38)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedWeekIndex == idx ? Color.drip.coral : Color.drip.cardBackground)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(selectedWeekIndex == idx ? Color.drip.coral : Color.drip.divider, lineWidth: 1)
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Color.drip.background)
    }

    // MARK: - Week Header Row

    private var weekHeaderRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                if !selectedWeek.theme.isEmpty {
                    Text(selectedWeek.theme)
                        .font(.dripLabel(14))
                        .foregroundStyle(Color.drip.textPrimary)
                }
                let workoutCount = selectedWeek.workouts.filter { !$0.isRest }.count
                Text("\(workoutCount) workout\(workoutCount == 1 ? "" : "s") · \(selectedWeek.totalPlannedMiles > 0 ? String(format: "%.0f mi planned", selectedWeek.totalPlannedMiles) : "no distance set")")
                    .font(.dripCaption(12))
                    .foregroundStyle(Color.drip.textSecondary)
            }
            Spacer()
            Button {
                copyWeekFromPrevious()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12))
                    Text("Copy prev")
                        .font(.dripCaption(12))
                }
                .foregroundStyle(Color.drip.textSecondary)
            }
            .disabled(selectedWeekIndex == 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color.drip.cardBackground.opacity(0.6))
    }

    // MARK: - Day Grid

    private var dayGrid: some View {
        ScrollView {
            VStack(spacing: 8) {
                let dayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
                ForEach(0..<7, id: \.self) { dayIdx in
                    let primary = workoutFor(day: dayIdx, slot: 0)
                    let secondary = doubleWorkoutFor(day: dayIdx)
                    DayCell(
                        dayName: dayNames[dayIdx],
                        primary: primary,
                        secondary: secondary,
                        onAddPrimary: {
                            pickerDayOfWeek = dayIdx; pickerSlot = 0; showWorkoutPicker = true
                        },
                        onEditPrimary: {
                            openInlineEditor(for: primary, day: dayIdx, slot: 0)
                        },
                        onRemovePrimary: {
                            setWorkout(PlanTemplateWorkout(dayOfWeek: dayIdx, workoutType: .rest), forDay: dayIdx, slot: 0)
                            removeDouble(forDay: dayIdx)
                        },
                        onAddDouble: {
                            pickerDayOfWeek = dayIdx; pickerSlot = 1; showWorkoutPicker = true
                        },
                        onEditDouble: secondary != nil ? { self.openInlineEditor(for: secondary!, day: dayIdx, slot: 1) } : nil,
                        onRemoveDouble: {
                            removeDouble(forDay: dayIdx)
                        }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .padding(.bottom, 60)
        }
    }

    private var loadingState: some View {
        VStack {
            Spacer()
            ProgressView()
            Spacer()
        }
    }

    // MARK: - Helpers

    /// Returns primary workout for a day (always non-nil, defaults to rest)
    private func workoutFor(day: Int, slot: Int) -> PlanTemplateWorkout {
        let matches = weeks[safe: selectedWeekIndex]?.workouts.filter { $0.dayOfWeek == day } ?? []
        return matches[safe: slot] ?? PlanTemplateWorkout(dayOfWeek: day, workoutType: .rest)
    }

    /// Returns the double (slot 1) workout only if one actually exists
    private func doubleWorkoutFor(day: Int) -> PlanTemplateWorkout? {
        let matches = weeks[safe: selectedWeekIndex]?.workouts.filter { $0.dayOfWeek == day } ?? []
        return matches.count > 1 ? matches[1] : nil
    }

    private func setWorkout(_ workout: PlanTemplateWorkout, forDay day: Int, slot: Int) {
        guard weeks.indices.contains(selectedWeekIndex) else { return }
        var dayWorkouts = weeks[selectedWeekIndex].workouts.filter { $0.dayOfWeek == day }
        let others = weeks[selectedWeekIndex].workouts.filter { $0.dayOfWeek != day }
        if slot < dayWorkouts.count {
            dayWorkouts[slot] = workout
        } else {
            dayWorkouts.append(workout)
        }
        weeks[selectedWeekIndex].workouts = others + dayWorkouts
    }

    private func removeDouble(forDay day: Int) {
        guard weeks.indices.contains(selectedWeekIndex) else { return }
        var dayWorkouts = weeks[selectedWeekIndex].workouts.filter { $0.dayOfWeek == day }
        if dayWorkouts.count > 1 { dayWorkouts.removeLast() }
        let others = weeks[selectedWeekIndex].workouts.filter { $0.dayOfWeek != day }
        weeks[selectedWeekIndex].workouts = others + dayWorkouts
    }

    private func openInlineEditor(for workout: PlanTemplateWorkout, day: Int, slot: Int) {
        inlineEditDay = day
        inlineEditSlot = slot
        // Prefer fetching the saved template for editing; fall back to inline data
        if let tmplId = workout.workoutTemplateId,
           let saved = viewModel.workoutTemplates.first(where: { $0.id == tmplId }) {
            inlineEditTemplate = saved
        } else if let data = workout.workoutData {
            inlineEditTemplate = WorkoutTemplate(
                id: workout.workoutTemplateId ?? UUID(),
                coachId: viewModel.coachProfile?.id ?? UUID(),
                name: data.name,
                workoutType: workout.workoutType ?? .easy,
                description: data.description,
                tags: [],
                workoutData: data,
                estimatedDistanceMiles: data.totalDistanceMiles,
                estimatedDurationMinutes: data.estimatedDurationMinutes.map { Int($0) },
                isPublic: false,
                useCount: 0,
                createdAt: data.createdAt,
                updatedAt: Date()
            )
        } else { return }
        showInlineEditor = true
    }

    private func copyWeekFromPrevious() {
        guard selectedWeekIndex > 0 else { return }
        weeks[selectedWeekIndex].workouts = weeks[selectedWeekIndex - 1].workouts.map { w in
            PlanTemplateWorkout(
                dayOfWeek: w.dayOfWeek,
                workoutTemplateId: w.workoutTemplateId,
                workoutType: w.workoutType,
                workoutData: w.workoutData,
                notes: w.notes
            )
        }
    }

    private func setup() {
        if let plan = existingPlan {
            planName = plan.name
            targetDistance = plan.targetDistance
            durationWeeks = plan.durationWeeks
            weeks = plan.weeks
        } else {
            let distance = RaceDistance.from(legacyString: targetDistance) ?? .marathon
            durationWeeks = distance.typicalPlanWeeks.upperBound
            weeks = buildBlankWeeks(count: durationWeeks)
        }
    }

    private func rebuildWeeksIfNeeded() {
        let current = weeks.count
        if durationWeeks > current {
            let extra = (current + 1...durationWeeks).map { emptyWeek($0) }
            weeks.append(contentsOf: extra)
        } else if durationWeeks < current {
            weeks = Array(weeks.prefix(durationWeeks))
        }
    }

    private func buildBlankWeeks(count: Int) -> [PlanTemplateWeek] {
        (1...count).map { emptyWeek($0) }
    }

    private func emptyWeek(_ num: Int) -> PlanTemplateWeek {
        PlanTemplateWeek(
            weekNumber: num,
            theme: num == durationWeeks ? "Race Week" : "Week \(num)",
            notes: "",
            workouts: (0..<7).map { PlanTemplateWorkout(dayOfWeek: $0, workoutType: .rest) }
        )
    }

    // MARK: - Save

    private func saveDraft() async {
        isSaving = true
        defer { isSaving = false }
        let draft = buildPlanTemplate(publish: false)
        if existingPlan != nil {
            await viewModel.updatePlanTemplate(draft)
        } else {
            _ = await viewModel.savePlanTemplate(draft)
        }
        dismiss()
    }

    private func saveAndPublish() async {
        isSaving = true
        defer { isSaving = false }
        let draft = buildPlanTemplate(publish: false)

        if existingPlan != nil {
            await viewModel.updatePlanTemplate(draft)
            if let code = await viewModel.publishPlanTemplate(draft) {
                generatedJoinCode = code
                showPublishSuccess = true
            } else {
                dismiss()
            }
        } else {
            if let saved = await viewModel.savePlanTemplate(draft) {
                if let code = await viewModel.publishPlanTemplate(saved) {
                    generatedJoinCode = code
                    showPublishSuccess = true
                } else {
                    dismiss()
                }
            }
        }
    }

    private func buildPlanTemplate(publish: Bool) -> PlanTemplate {
        PlanTemplate(
            id: existingPlan?.id ?? UUID(),
            coachId: existingPlan?.coachId ?? viewModel.coachProfile?.id ?? UUID(),
            name: planName.isEmpty ? "Untitled Plan" : planName,
            description: existingPlan?.description,
            targetDistance: targetDistance,
            durationWeeks: durationWeeks,
            planType: existingPlan?.planType ?? "fixed",
            weeks: weeks,
            dayStructure: existingPlan?.dayStructure,
            phaseConfig: existingPlan?.phaseConfig,
            weeklyMileageTargets: existingPlan?.weeklyMileageTargets,
            raceDate: existingPlan?.raceDate,
            joinCode: existingPlan?.joinCode,
            isPublished: existingPlan?.isPublished ?? false,
            subscriberCount: existingPlan?.subscriberCount ?? 0,
            createdAt: existingPlan?.createdAt ?? Date(),
            updatedAt: Date()
        )
    }
}

// MARK: - DayCell

struct DayCell: View {
    let dayName: String
    let primary: PlanTemplateWorkout
    let secondary: PlanTemplateWorkout?
    let onAddPrimary: () -> Void
    let onEditPrimary: () -> Void
    let onRemovePrimary: () -> Void
    let onAddDouble: () -> Void
    let onEditDouble: (() -> Void)?
    let onRemoveDouble: () -> Void

    @State private var isExpanded = false

    var body: some View {
        HStack(spacing: 14) {
            Text(dayName)
                .font(.dripCaption(12))
                .foregroundStyle(Color.drip.textTertiary)
                .frame(width: 30, alignment: .leading)

            VStack(spacing: 6) {
                workoutRow(workout: primary, label: secondary != nil ? "AM" : nil,
                           onEdit: onEditPrimary, onRemove: onRemovePrimary, onAdd: onAddPrimary)

                if let sec = secondary {
                    workoutRow(workout: sec, label: "PM",
                               onEdit: onEditDouble ?? {}, onRemove: onRemoveDouble, onAdd: nil)
                } else if !primary.isRest {
                    // Add double button
                    Button(action: onAddDouble) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 12))
                            Text("Add PM workout")
                                .font(.dripCaption(12))
                        }
                        .foregroundStyle(Color.drip.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.drip.cardBackground.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.drip.divider.opacity(0.5), lineWidth: 1))
                    }
                }

                // Steps preview
                if !primary.isRest, let steps = primary.workoutData?.steps, !steps.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
                    } label: {
                        HStack(spacing: 4) {
                            Text(isExpanded ? "Hide steps" : "\(steps.count) steps")
                                .font(.dripCaption(11))
                                .foregroundStyle(Color.drip.textTertiary)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9))
                                .foregroundStyle(Color.drip.textTertiary)
                                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 2)
                    }

                    if isExpanded {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(steps.prefix(10)) { step in
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(step.stepType.color)
                                        .frame(width: 6, height: 6)
                                    Text(step.stepType.displayName)
                                        .font(.dripCaption(12))
                                        .foregroundStyle(Color.drip.textPrimary)
                                    Text("·")
                                        .foregroundStyle(Color.drip.textTertiary)
                                        .font(.dripCaption(12))
                                    Text(stepSummary(step))
                                        .font(.dripCaption(12))
                                        .foregroundStyle(Color.drip.textSecondary)
                                    Spacer()
                                }
                            }
                            if steps.count > 10 {
                                Text("+\(steps.count - 10) more steps")
                                    .font(.dripCaption(11))
                                    .foregroundStyle(Color.drip.textTertiary)
                            }
                            if let miles = primary.workoutData?.effectiveDistanceMiles, miles > 0 {
                                Divider().padding(.vertical, 2)
                                HStack {
                                    Text("Total")
                                        .font(.dripCaption(12))
                                        .foregroundStyle(Color.drip.textSecondary)
                                    Spacer()
                                    Text(String(format: "%.1f mi", miles))
                                        .font(.dripLabel(12))
                                        .foregroundStyle(Color.drip.coral)
                                }
                            }
                        }
                        .padding(10)
                        .background(Color.drip.background)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func workoutRow(workout: PlanTemplateWorkout, label: String?, onEdit: @escaping () -> Void, onRemove: @escaping () -> Void, onAdd: (() -> Void)?) -> some View {
        if workout.isRest {
            Button(action: onAdd ?? {}) {
                HStack {
                    if let l = label {
                        Text(l).font(.dripCaption(10)).foregroundStyle(Color.drip.textTertiary).frame(width: 22)
                    }
                    Image(systemName: "bed.double.fill").font(.system(size: 13)).foregroundStyle(Color.drip.textTertiary)
                    Text("Rest").font(.dripBody(14)).foregroundStyle(Color.drip.textTertiary)
                    Spacer()
                    Image(systemName: "plus").font(.system(size: 12, weight: .medium)).foregroundStyle(Color.drip.textTertiary)
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(Color.drip.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.drip.divider, lineWidth: 1))
            }
        } else {
            let type = workout.workoutType ?? .easy
            Button(action: onEdit) {
                HStack(spacing: 10) {
                    if let l = label {
                        Text(l).font(.dripCaption(10)).foregroundStyle(Color.drip.textTertiary).frame(width: 22)
                    }
                    Image(systemName: type.icon).font(.system(size: 15)).foregroundStyle(type.color).frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(workout.workoutData?.name ?? type.displayName)
                            .font(.dripLabel(14)).foregroundStyle(Color.drip.textPrimary).lineLimit(1)
                        if let miles = workout.workoutData?.effectiveDistanceMiles, miles > 0 {
                            Text(String(format: "%.1f mi", miles))
                                .font(.dripCaption(12)).foregroundStyle(Color.drip.coral)
                        } else if let steps = workout.workoutData?.steps, !steps.isEmpty {
                            Text("\(steps.count) steps")
                                .font(.dripCaption(12)).foregroundStyle(Color.drip.textSecondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "pencil").font(.system(size: 13)).foregroundStyle(Color.drip.textTertiary)
                    // Remove button — isolated so it doesn't trigger edit
                    Button(action: onRemove) {
                        Image(systemName: "xmark.circle").font(.system(size: 18)).foregroundStyle(Color.drip.textTertiary)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(type.color.opacity(0.4), lineWidth: 1))
        }
    }

    private func stepSummary(_ step: PlannedWorkoutStep) -> String {
        switch step.durationType {
        case .distanceMiles:
            return String(format: "%.1f mi", step.durationValue)
        case .distanceKm:
            return String(format: "%.1f km", step.durationValue)
        case .distanceMeters:
            return String(format: "%.0f m", step.durationValue)
        case .timeSeconds:
            let secs = Int(step.durationValue)
            return "\(secs / 60):\(String(format: "%02d", secs % 60))"
        case .open:
            return "open"
        }
    }
}

// MARK: - PlanHeaderEditorSheet

struct PlanHeaderEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var name: String
    @Binding var targetDistance: String
    @Binding var durationWeeks: Int
    let onSave: () -> Void

    let races: [(String, String)] = [
        ("Marathon", "marathon"),
        ("Half Marathon", "half_marathon"),
        ("10K", "10k"),
        ("5K", "5k"),
        ("Mile", "mile"),
        ("Custom", "custom"),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                DripBackground().ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("PLAN NAME")
                                .font(.dripCaption(11))
                                .foregroundStyle(Color.drip.textTertiary)
                            TextField("e.g. 16-Week Marathon Plan", text: $name)
                                .font(.dripBody(16))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(Color.drip.cardBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.drip.divider, lineWidth: 1))
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            Text("TARGET RACE")
                                .font(.dripCaption(11))
                                .foregroundStyle(Color.drip.textTertiary)
                            VStack(spacing: 0) {
                                ForEach(races, id: \.1) { label, value in
                                    Button {
                                        targetDistance = value
                                    } label: {
                                        HStack {
                                            Text(label)
                                                .font(.dripBody(15))
                                                .foregroundStyle(Color.drip.textPrimary)
                                            Spacer()
                                            if targetDistance == value {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 14, weight: .semibold))
                                                    .foregroundStyle(Color.drip.coral)
                                            }
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 13)
                                    }
                                    if value != "custom" {
                                        Divider().background(Color.drip.divider)
                                    }
                                }
                            }
                            .background(Color.drip.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.drip.divider, lineWidth: 1))
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            Text("DURATION")
                                .font(.dripCaption(11))
                                .foregroundStyle(Color.drip.textTertiary)
                            HStack {
                                Text("\(durationWeeks) weeks")
                                    .font(.dripBody(15))
                                    .foregroundStyle(Color.drip.textPrimary)
                                Spacer()
                                Stepper("", value: $durationWeeks, in: 1...52)
                                    .labelsHidden()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(Color.drip.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.drip.divider, lineWidth: 1))
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }
            }
            .navigationTitle("Plan Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        onSave()
                        dismiss()
                    }
                    .font(.dripLabel(14))
                    .foregroundStyle(Color.drip.coral)
                }
            }
        }
        .presentationDetents([.large])
    }
}

// MARK: - Safe subscript (fileprivate to avoid conflict)

fileprivate extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
