//
//  DayDetailSheets.swift
//  RunningLog
//
//  Modal/sheet views used by DayDetailSheet.
//

import SwiftUI

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
