//
//  DayDetailSheet.swift
//  RunningLog
//
//  Detail sheet for viewing and editing a scheduled workout day.
//

import SwiftUI

// MARK: - DayDetailSheet

struct DayDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(VitalManager.self) private var vitalManager
    @Bindable var viewModel: TrainingPlanViewModel
    let scheduledWorkout: ScheduledWorkout
    let racePaceSeconds: Double

    @State private var showSwapPicker = false
    @State private var showAddWorkoutPicker = false
    @State private var showDeleteConfirmation = false
    @State private var isExporting = false
    @State private var showExportSheet = false
    @State private var exportedFileURL: URL?
    @State private var showExportError = false
    @State private var exportErrorMessage: String?

    // Edit mode state
    @State private var isEditing = false
    @State private var editableSteps: [EditableWorkoutStep] = []
    @State private var isSavingEdits = false
    @State private var showPaceSettings = false
    @State private var showZoneAdjustment = false
    @State private var showWorkoutChat = false
    @State private var showReschedule = false

    // Vital completed workout data
    @State private var completedVitalWorkouts: [RunningWorkout] = []
    @State private var showVitalDetail = false
    @State private var selectedVitalWorkout: RunningWorkout?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.drip.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Day Header
                        DayDetailHeader(workout: scheduledWorkout)
                            .padding(.horizontal, 20)

                        if scheduledWorkout.isRestDay {
                            // Rest day content
                            RestDayDetailContent(
                                workout: scheduledWorkout,
                                onAddWorkout: { showAddWorkoutPicker = true }
                            )
                            .padding(.horizontal, 20)
                        } else if let workout = scheduledWorkout.workout {
                            // Workout details - reuse existing components
                            if !isEditing {
                                WorkoutDetailHeader(
                                    workout: workout,
                                    racePaceSeconds: racePaceSeconds
                                )
                                .padding(.horizontal, 20)

                                // Pace settings row
                                HStack {
                                    Spacer()
                                    Button {
                                        showPaceSettings.toggle()
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "gearshape")
                                                .font(.system(size: 12))
                                            Text("Pace Labels")
                                                .font(.dripCaption(11))
                                        }
                                        .foregroundStyle(Color.drip.textTertiary)
                                    }
                                    .popover(isPresented: $showPaceSettings, arrowEdge: .top) {
                                        VStack(alignment: .leading, spacing: 12) {
                                            Text("PACE LABELS")
                                                .font(.dripCaption(10))
                                                .foregroundStyle(Color.drip.textSecondary)
                                                .tracking(1.0)

                                            Toggle(isOn: Binding(
                                                get: { !viewModel.paceConfig.disabledPaces.contains(.tenK) },
                                                set: { enabled in
                                                    var paces = viewModel.paceConfig.disabledPaces
                                                    if enabled { paces.remove(.tenK) } else { paces.insert(.tenK) }
                                                    viewModel.paceConfig.disabledPaces = paces
                                                }
                                            )) {
                                                HStack(spacing: 6) {
                                                    Circle()
                                                        .fill(NamedPace.tenK.color)
                                                        .frame(width: 8, height: 8)
                                                    Text("10K Pace")
                                                        .font(.dripBody(14))
                                                        .foregroundStyle(Color.drip.textPrimary)
                                                }
                                            }
                                            .tint(NamedPace.tenK.color)

                                            Toggle(isOn: Binding(
                                                get: { !viewModel.paceConfig.disabledPaces.contains(.fiveK) },
                                                set: { enabled in
                                                    var paces = viewModel.paceConfig.disabledPaces
                                                    if enabled { paces.remove(.fiveK) } else { paces.insert(.fiveK) }
                                                    viewModel.paceConfig.disabledPaces = paces
                                                }
                                            )) {
                                                HStack(spacing: 6) {
                                                    Circle()
                                                        .fill(NamedPace.fiveK.color)
                                                        .frame(width: 8, height: 8)
                                                    Text("5K Pace")
                                                        .font(.dripBody(14))
                                                        .foregroundStyle(Color.drip.textPrimary)
                                                }
                                            }
                                            .tint(NamedPace.fiveK.color)
                                        }
                                        .padding(16)
                                        .frame(width: 200)
                                        .presentationCompactAdaptation(.popover)
                                    }
                                }
                                .padding(.horizontal, 20)
                            }

                            // Workout Steps
                            VStack(alignment: .leading, spacing: 16) {
                                Text(isEditing ? "EDIT STEPS" : "WORKOUT STEPS")
                                    .font(.dripCaption(11))
                                    .foregroundStyle(Color.drip.textSecondary)
                                    .tracking(1.2)
                                    .padding(.horizontal, 20)

                                if isEditing {
                                    // Editable steps
                                    VStack(spacing: 12) {
                                        ForEach($editableSteps) { $step in
                                            EditableWorkoutStepRow(
                                                step: $step,
                                                equivalentPaces: viewModel.equivalentPaces ?? defaultEquivalentPaces,
                                                racePaceSeconds: racePaceSeconds,
                                                onDelete: {
                                                    withAnimation {
                                                        editableSteps.removeAll { $0.id == step.id }
                                                        reorderSteps()
                                                    }
                                                }
                                            )
                                        }

                                        // Add step button
                                        Button {
                                            addNewStep()
                                        } label: {
                                            HStack(spacing: 8) {
                                                Image(systemName: "plus.circle.fill")
                                                    .font(.system(size: 16))
                                                Text("Add Step")
                                                    .font(.dripLabel(14))
                                            }
                                            .foregroundStyle(Color.drip.coral)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 14)
                                            .background(Color.drip.coral.opacity(0.1))
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                        }
                                    }
                                    .padding(.horizontal, 20)
                                } else {
                                    // Read-only steps
                                    VStack(spacing: 0) {
                                        ForEach(Array(workout.steps.enumerated()), id: \.element.id) { index, step in
                                            WorkoutStepRow(
                                                step: step,
                                                stepNumber: index + 1,
                                                totalSteps: workout.steps.count,
                                                racePaceSeconds: racePaceSeconds,
                                                equivalentPaces: viewModel.equivalentPaces
                                            )
                                        }
                                    }
                                    .background(Color.drip.cardBackground)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                                    .padding(.horizontal, 20)
                                }
                            }

                            if !isEditing {
                                // Phase Info
                                PhaseInfoCard(phase: workout.trainingPhase)
                                    .padding(.horizontal, 20)

                                // Action Buttons
                                WorkoutActionButtons(
                                    workout: scheduledWorkout,
                                    isExporting: isExporting,
                                    onMarkComplete: { markComplete() },
                                    onMarkSkipped: { markSkipped() },
                                    onSwap: { showSwapPicker = true },
                                    onRestructure: { showWorkoutChat = true },
                                    onReschedule: { showReschedule = true },
                                    onDelete: { showDeleteConfirmation = true },
                                    onExport: { exportWorkout() }
                                )
                                .padding(.horizontal, 20)
                            }
                        }

                        // Completed Vital workout data
                        if !completedVitalWorkouts.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Color.drip.positive)
                                    Text("COMPLETED RUN")
                                        .font(.dripCaption(11))
                                        .foregroundStyle(Color.drip.textSecondary)
                                        .tracking(1.2)
                                }

                                ForEach(completedVitalWorkouts) { vitalWorkout in
                                    Button {
                                        selectedVitalWorkout = vitalWorkout
                                        showVitalDetail = true
                                    } label: {
                                        VStack(spacing: 12) {
                                            HStack(spacing: 0) {
                                                WorkoutStat(value: vitalWorkout.formattedDistance, label: "DISTANCE")
                                                Divider().frame(height: 32).background(Color.drip.divider)
                                                WorkoutStat(value: vitalWorkout.formattedDuration, label: "TIME")
                                                Divider().frame(height: 32).background(Color.drip.divider)
                                                WorkoutStat(value: vitalWorkout.formattedPace, label: "PACE")
                                            }

                                            HStack(spacing: 6) {
                                                Text("View details")
                                                    .font(.dripLabel(13))
                                                Image(systemName: "chevron.right")
                                                    .font(.system(size: 11, weight: .semibold))
                                            }
                                            .foregroundStyle(Color.drip.coral)
                                        }
                                        .padding(16)
                                        .background(Color.drip.cardBackground)
                                        .clipShape(RoundedRectangle(cornerRadius: 16))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16)
                                                .stroke(Color.drip.positive.opacity(0.3), lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 20)
                        }

                        Spacer()
                            .frame(height: 40)
                    }
                    .padding(.top, 20)
                }
            }
            .navigationTitle(scheduledWorkout.formattedFullDate)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !scheduledWorkout.isRestDay && scheduledWorkout.workout != nil {
                        Button(isEditing ? "Cancel" : "Edit") {
                            if isEditing {
                                withAnimation(.spring(response: 0.3)) {
                                    isEditing = false
                                }
                            } else {
                                enterEditMode()
                            }
                        }
                        .font(.dripBody(15))
                        .foregroundStyle(isEditing ? Color.drip.textSecondary : Color.drip.coral)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isEditing {
                        Button {
                            Task { await saveEdits() }
                        } label: {
                            if isSavingEdits {
                                ProgressView()
                                    .tint(Color.drip.coral)
                            } else {
                                Text("Save")
                                    .font(.dripLabel(15))
                                    .foregroundStyle(Color.drip.coral)
                            }
                        }
                        .disabled(isSavingEdits)
                    } else {
                        Button("Done") {
                            dismiss()
                        }
                        .font(.dripBody(15))
                        .foregroundStyle(Color.drip.coral)
                    }
                }
            }
            .toolbarBackground(Color.drip.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(isPresented: $showSwapPicker) {
                SwapWorkoutSheet(
                    viewModel: viewModel,
                    sourceWorkout: scheduledWorkout,
                    onSwap: { dismiss() }
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showAddWorkoutPicker) {
                AddWorkoutSheet(
                    viewModel: viewModel,
                    restDay: scheduledWorkout,
                    onAdd: { dismiss() }
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showExportSheet) {
                if let url = exportedFileURL {
                    ShareSheet(items: [url])
                }
            }
            .sheet(isPresented: $showWorkoutChat) {
                WorkoutChatSheet(
                    viewModel: viewModel,
                    scheduledWorkout: scheduledWorkout,
                    racePaceSeconds: racePaceSeconds,
                    onWorkoutUpdated: { dismiss() }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showReschedule) {
                RescheduleSheet(
                    viewModel: viewModel,
                    initialScope: .day,
                    targetDate: scheduledWorkout.date
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .alert("Delete Workout", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Convert to Rest Day", role: .destructive) {
                    convertToRestDay()
                }
            } message: {
                Text("This will convert this day to a rest day. This action cannot be undone.")
            }
            .alert("Export Failed", isPresented: $showExportError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(exportErrorMessage ?? "An error occurred while exporting")
            }
            .sheet(isPresented: $showVitalDetail) {
                if let vitalWorkout = selectedVitalWorkout,
                   let vitalId = vitalWorkout.vitalWorkoutId
                {
                    VitalWorkoutDetailView(workout: vitalWorkout, vitalWorkoutId: vitalId)
                        .presentationDetents([.large])
                        .presentationDragIndicator(.visible)
                }
            }
            .task {
                // Load completed Vital workouts for this day
                let workouts = await vitalManager.fetchRunningWorkouts(for: scheduledWorkout.date)
                await MainActor.run {
                    completedVitalWorkouts = workouts
                }
            }
        }
    }

    // MARK: - Actions

    private func markComplete() {
        Task {
            await viewModel.markWorkoutComplete(scheduledWorkout)
            dismiss()
        }
    }

    private func markSkipped() {
        Task {
            await viewModel.markWorkoutSkipped(scheduledWorkout)
            dismiss()
        }
    }

    private func convertToRestDay() {
        Task {
            await viewModel.convertToRestDay(scheduledWorkout)
            dismiss()
        }
    }

    private func exportWorkout() {
        guard let workout = scheduledWorkout.workout else { return }
        isExporting = true

        Task {
            do {
                let fitService = FITExportService()
                let url = try await fitService.exportWorkout(workout, racePaceSeconds: racePaceSeconds)

                await MainActor.run {
                    exportedFileURL = url
                    isExporting = false
                    showExportSheet = true
                }
            } catch {
                await MainActor.run {
                    isExporting = false
                    exportErrorMessage = error.localizedDescription
                    showExportError = true
                }
            }
        }
    }

    // MARK: - Edit Mode

    private var defaultEquivalentPaces: EquivalentPaces {
        EquivalentPaces(raceDistance: .marathon, goalTimeSeconds: 14400)
    }

    private func enterEditMode() {
        guard let workout = scheduledWorkout.workout else { return }
        editableSteps = workout.steps.map { step in
            EditableWorkoutStep(
                from: step,
                equivalentPaces: viewModel.equivalentPaces,
                racePaceSeconds: racePaceSeconds
            )
        }
        withAnimation(.spring(response: 0.3)) {
            isEditing = true
        }
    }

    private func addNewStep() {
        let newStep = EditableWorkoutStep(order: editableSteps.count)
        withAnimation {
            editableSteps.append(newStep)
        }
    }

    private func reorderSteps() {
        for i in editableSteps.indices {
            editableSteps[i].order = i
        }
    }

    private func saveEdits() async {
        guard let workout = scheduledWorkout.workout else { return }
        let equiv = viewModel.equivalentPaces ?? defaultEquivalentPaces

        isSavingEdits = true

        let updatedSteps = editableSteps.enumerated().map { index, editable in
            var step = editable
            step.order = index
            return step.toWorkoutStep(
                racePaceSeconds: racePaceSeconds,
                equivalentPaces: equiv
            )
        }

        // Calculate total distance from steps
        let totalMiles = updatedSteps.reduce(0.0) { total, step in
            switch step.durationType {
            case .distanceMiles:
                return total + step.durationValue
            case .distanceKm:
                return total + step.durationValue / 1.60934
            case .distanceMeters:
                return total + step.durationValue / 1609.34
            default:
                return total
            }
        }

        let updatedWorkout = PlannedWorkout(
            id: workout.id,
            name: workout.name,
            category: workout.category,
            trainingPhase: workout.trainingPhase,
            description: workout.description,
            steps: updatedSteps,
            totalDistanceMiles: totalMiles > 0 ? totalMiles : workout.totalDistanceMiles,
            estimatedDurationMinutes: workout.estimatedDurationMinutes,
            signatureType: workout.signatureType,
            createdAt: workout.createdAt
        )

        var updatedScheduled = scheduledWorkout
        updatedScheduled.workout = updatedWorkout
        updatedScheduled.status = .modified

        await viewModel.updateWorkout(updatedScheduled)

        isSavingEdits = false
        withAnimation(.spring(response: 0.3)) {
            isEditing = false
        }
    }
}

// MARK: - Day Detail Header

struct DayDetailHeader: View {
    let workout: ScheduledWorkout

    var body: some View {
        HStack(spacing: 14) {
            // Day and date
            VStack(alignment: .leading, spacing: 4) {
                Text(workout.dayName.uppercased())
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textSecondary)
                    .tracking(1.5)

                Text(workout.formattedShortDate)
                    .font(.dripStat(24))
                    .foregroundStyle(workout.isToday ? Color.drip.coral : Color.drip.textPrimary)
            }

            Spacer()

            // Workout type badge
            HStack(spacing: 6) {
                Image(systemName: workout.workoutType.icon)
                    .font(.system(size: 14))

                Text(workout.workoutType.displayName)
                    .font(.dripLabel(14))
            }
            .foregroundStyle(workout.workoutType.color)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(workout.workoutType.color.opacity(0.15))
            .clipShape(Capsule())
        }
        .padding(16)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    workout.isToday ? Color.drip.coral.opacity(0.3) : Color.drip.divider,
                    lineWidth: 1
                )
        )
    }
}

// MARK: - Rest Day Detail Content

struct RestDayDetailContent: View {
    let workout: ScheduledWorkout
    let onAddWorkout: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            // Rest day illustration
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.drip.textTertiary.opacity(0.1))
                        .frame(width: 80, height: 80)

                    Image(systemName: "bed.double.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.drip.textTertiary)
                }

                VStack(spacing: 6) {
                    Text("Rest Day")
                        .font(.dripLabel(18))
                        .foregroundStyle(Color.drip.textPrimary)

                    Text("Recovery is when your body adapts and gets stronger. Use this time to stretch, hydrate, and prepare for your next session.")
                        .font(.dripBody(14))
                        .foregroundStyle(Color.drip.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(24)
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))

            // Recovery tips
            VStack(alignment: .leading, spacing: 12) {
                Text("RECOVERY TIPS")
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textSecondary)
                    .tracking(1.2)

                VStack(spacing: 10) {
                    RecoveryTipRow(icon: "drop.fill", text: "Stay hydrated - aim for 8+ glasses of water")
                    RecoveryTipRow(icon: "moon.stars.fill", text: "Get 7-9 hours of quality sleep")
                    RecoveryTipRow(icon: "figure.flexibility", text: "Light stretching or yoga can help recovery")
                    RecoveryTipRow(icon: "fork.knife", text: "Focus on protein and anti-inflammatory foods")
                }
                .padding(16)
                .background(Color.drip.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            // Add workout option
            Button(action: onAddWorkout) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16))

                    Text("Add Workout Instead")
                        .font(.dripLabel(14))
                }
                .foregroundStyle(Color.drip.coral)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.drip.coral.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

// MARK: - Recovery Tip Row

struct RecoveryTipRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Color.drip.coral)
                .frame(width: 20)

            Text(text)
                .font(.dripBody(13))
                .foregroundStyle(Color.drip.textSecondary)

            Spacer()
        }
    }
}

// MARK: - Workout Action Buttons

struct WorkoutActionButtons: View {
    let workout: ScheduledWorkout
    let isExporting: Bool
    let onMarkComplete: () -> Void
    let onMarkSkipped: () -> Void
    let onSwap: () -> Void
    let onRestructure: () -> Void
    let onReschedule: () -> Void
    let onDelete: () -> Void
    let onExport: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            // Primary actions based on status
            if workout.status == .scheduled {
                HStack(spacing: 12) {
                    Button(action: onMarkComplete) {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16))
                            Text("Mark Complete")
                                .font(.dripLabel(14))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.drip.positive)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Button(action: onMarkSkipped) {
                        HStack(spacing: 8) {
                            Image(systemName: "xmark.circle")
                                .font(.system(size: 16))
                            Text("Skip")
                                .font(.dripLabel(14))
                        }
                        .foregroundStyle(Color.drip.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.drip.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.drip.divider, lineWidth: 1)
                        )
                    }
                }
            } else {
                // Status indicator
                HStack(spacing: 8) {
                    Image(systemName: workout.status == .completed ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 16))

                    Text(workout.status == .completed ? "Completed" : "Skipped")
                        .font(.dripLabel(14))
                }
                .foregroundStyle(workout.status == .completed ? Color.drip.positive : Color.drip.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    (workout.status == .completed ? Color.drip.positive : Color.drip.textTertiary)
                        .opacity(0.15)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            // Secondary actions
            HStack(spacing: 12) {
                ActionButton(
                    icon: "arrow.triangle.swap",
                    label: "Swap",
                    action: onSwap
                )

                ActionButton(
                    icon: "sparkles",
                    label: "AI Edit",
                    action: onRestructure
                )

                ActionButton(
                    icon: "calendar.badge.clock",
                    label: "Reschedule",
                    action: onReschedule
                )

                ActionButton(
                    icon: "square.and.arrow.up",
                    label: "Export",
                    isLoading: isExporting,
                    action: onExport
                )

                ActionButton(
                    icon: "trash",
                    label: "Delete",
                    isDestructive: true,
                    action: onDelete
                )
            }
        }
    }
}

// MARK: - Action Button

struct ActionButton: View {
    let icon: String
    let label: String
    var isLoading: Bool = false
    var isDestructive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                if isLoading {
                    ProgressView()
                        .tint(Color.drip.textSecondary)
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 16))
                }

                Text(label)
                    .font(.dripCaption(11))
            }
            .foregroundStyle(isDestructive ? Color.drip.injured : Color.drip.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.drip.divider, lineWidth: 1)
            )
        }
        .disabled(isLoading)
    }
}

// MARK: - Preview

#Preview {
    DayDetailSheet(
        viewModel: TrainingPlanViewModel(),
        scheduledWorkout: ScheduledWorkout.sample,
        racePaceSeconds: 480
    )
}
