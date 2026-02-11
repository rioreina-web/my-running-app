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
                            WorkoutDetailHeader(
                                workout: workout,
                                racePaceSeconds: racePaceSeconds
                            )
                            .padding(.horizontal, 20)

                            // Workout Steps
                            VStack(alignment: .leading, spacing: 16) {
                                Text("WORKOUT STEPS")
                                    .font(.dripCaption(11))
                                    .foregroundStyle(Color.drip.textSecondary)
                                    .tracking(1.2)
                                    .padding(.horizontal, 20)

                                VStack(spacing: 0) {
                                    ForEach(Array(workout.steps.enumerated()), id: \.element.id) { index, step in
                                        WorkoutStepRow(
                                            step: step,
                                            stepNumber: index + 1,
                                            totalSteps: workout.steps.count,
                                            racePaceSeconds: racePaceSeconds
                                        )
                                    }
                                }
                                .background(Color.drip.cardBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .padding(.horizontal, 20)
                            }

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
                                onDelete: { showDeleteConfirmation = true },
                                onExport: { exportWorkout() }
                            )
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.dripBody(15))
                    .foregroundStyle(Color.drip.coral)
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

// MARK: - Swap Workout Sheet

struct SwapWorkoutSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: TrainingPlanViewModel
    let sourceWorkout: ScheduledWorkout
    let onSwap: () -> Void

    @State private var selectedWorkout: ScheduledWorkout?

    private var availableWorkouts: [ScheduledWorkout] {
        viewModel.currentWeekWorkouts.filter { $0.id != sourceWorkout.id && !$0.isRestDay }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.drip.background.ignoresSafeArea()

                VStack(spacing: 20) {
                    Text("Select a workout to swap with")
                        .font(.dripBody(14))
                        .foregroundStyle(Color.drip.textSecondary)
                        .padding(.top, 8)

                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(availableWorkouts) { workout in
                                SwapWorkoutRow(
                                    workout: workout,
                                    isSelected: selectedWorkout?.id == workout.id
                                )
                                .onTapGesture {
                                    selectedWorkout = workout
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }

                    // Swap button
                    if let target = selectedWorkout {
                        Button {
                            Task {
                                await viewModel.swapWorkouts(sourceWorkout, with: target)
                                onSwap()
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.triangle.swap")
                                    .font(.system(size: 16))
                                Text("Swap Workouts")
                                    .font(.dripLabel(15))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.drip.coral)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                    }
                }
            }
            .navigationTitle("Swap Workout")
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
        }
    }
}

// MARK: - Swap Workout Row

struct SwapWorkoutRow: View {
    let workout: ScheduledWorkout
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Day
            VStack(spacing: 2) {
                Text(workout.shortDayName.uppercased())
                    .font(.dripCaption(9))
                    .foregroundStyle(Color.drip.textTertiary)

                Text("\(workout.dayNumber)")
                    .font(.dripStat(16))
                    .foregroundStyle(Color.drip.textPrimary)
            }
            .frame(width: 36)

            // Workout type icon
            ZStack {
                Circle()
                    .fill(workout.workoutType.color.opacity(0.15))
                    .frame(width: 32, height: 32)

                Image(systemName: workout.workoutType.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(workout.workoutType.color)
            }

            // Workout name
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.workout?.name ?? workout.workoutType.displayName)
                    .font(.dripLabel(14))
                    .foregroundStyle(Color.drip.textPrimary)

                if let w = workout.workout, let distance = w.formattedTotalDistance {
                    Text(distance)
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.textSecondary)
                }
            }

            Spacer()

            // Selection indicator
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22))
                .foregroundStyle(isSelected ? Color.drip.coral : Color.drip.textTertiary)
        }
        .padding(12)
        .background(
            isSelected
                ? Color.drip.coral.opacity(0.08)
                : Color.drip.cardBackground
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isSelected ? Color.drip.coral : Color.drip.divider,
                    lineWidth: 1
                )
        )
    }
}

// MARK: - Add Workout Sheet

struct AddWorkoutSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: TrainingPlanViewModel
    let restDay: ScheduledWorkout
    let onAdd: () -> Void

    @State private var selectedType: ScheduledWorkoutType = .easy

    private let availableTypes: [ScheduledWorkoutType] = [.easy, .tempo, .intervals, .longRun, .recovery]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.drip.background.ignoresSafeArea()

                VStack(spacing: 24) {
                    Text("Choose a workout type to add")
                        .font(.dripBody(14))
                        .foregroundStyle(Color.drip.textSecondary)
                        .padding(.top, 8)

                    // Workout type grid
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(availableTypes, id: \.self) { type in
                            AddWorkoutTypeCard(
                                type: type,
                                isSelected: selectedType == type
                            )
                            .onTapGesture {
                                selectedType = type
                            }
                        }
                    }
                    .padding(.horizontal, 20)

                    Spacer()

                    // Add button
                    Button {
                        Task {
                            await viewModel.addWorkoutToRestDay(restDay, workoutType: selectedType)
                            onAdd()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 16))
                            Text("Add \(selectedType.displayName)")
                                .font(.dripLabel(15))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(selectedType.color)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("Add Workout")
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
        }
    }
}

// MARK: - Add Workout Type Card

struct AddWorkoutTypeCard: View {
    let type: ScheduledWorkoutType
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(type.color.opacity(isSelected ? 0.3 : 0.15))
                    .frame(width: 48, height: 48)

                Image(systemName: type.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(type.color)
            }

            Text(type.displayName)
                .font(.dripLabel(14))
                .foregroundStyle(Color.drip.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(
            isSelected
                ? type.color.opacity(0.1)
                : Color.drip.cardBackground
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    isSelected ? type.color : Color.drip.divider,
                    lineWidth: isSelected ? 2 : 1
                )
        )
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
