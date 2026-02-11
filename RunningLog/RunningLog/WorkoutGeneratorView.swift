//
//  WorkoutGeneratorView.swift
//  RunningLog
//
//  Main view for the Canova-inspired AI workout generator.
//

import os
import SwiftUI

// MARK: - WorkoutGeneratorView

struct WorkoutGeneratorView: View {
    @State private var viewModel = WorkoutGeneratorViewModel()
    @State private var selectedWorkoutForDetail: CanovaWorkout?

    var body: some View {
        ZStack {
            DripBackground()

            ScrollView {
                VStack(spacing: 24) {
                    // Training Phase Banner
                    TrainingPhaseBanner(
                        phase: viewModel.currentPhase,
                        weeksOut: viewModel.weeksUntilRace,
                        goalName: viewModel.activeGoal?.goalTitle,
                        isLoading: viewModel.isLoadingGoal
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                    // Goal Pace Card
                    if let pacePace = viewModel.formattedRacePace,
                       let goalTime = viewModel.formattedGoalTime
                    {
                        GoalPaceCard(
                            goalTime: goalTime,
                            racePace: pacePace
                        )
                        .padding(.horizontal, 20)
                    }

                    // Signature Workouts Section
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeader("Signature Workouts")
                            .padding(.horizontal, 20)

                        SignatureWorkoutGrid(
                            isGenerating: viewModel.isGenerating,
                            onSelect: { type in
                                viewModel.generateQuickWorkout(signatureType: type)
                            }
                        )
                        .padding(.horizontal, 20)
                    }

                    // Quick Generate by Category
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeader("Generate by Category")
                            .padding(.horizontal, 20)

                        CategoryButtonRow(
                            isGenerating: viewModel.isGenerating,
                            onSelect: { category in
                                Task {
                                    await viewModel.generateWorkout(category: category)
                                }
                            }
                        )
                        .padding(.horizontal, 20)
                    }

                    // Generated Workouts List
                    if !viewModel.generatedWorkouts.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            SectionHeader("Generated Workouts")
                                .padding(.horizontal, 20)

                            LazyVStack(spacing: 12) {
                                ForEach(viewModel.generatedWorkouts) { workout in
                                    GeneratedWorkoutCard(
                                        workout: workout,
                                        racePaceSeconds: viewModel.racePaceSecondsPerMile ?? 480
                                    )
                                    .onTapGesture {
                                        selectedWorkoutForDetail = workout
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }

                    Spacer()
                        .frame(height: 40)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                SidebarMenuButton()
            }
            ToolbarItem(placement: .principal) {
                Text("GENERATE")
                    .font(.dripCaption(12))
                    .foregroundStyle(Color.drip.textSecondary)
                    .tracking(2)
            }
        }
        .toolbarBackground(Color.drip.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear {
            Task { await viewModel.loadActiveGoal() }
        }
        .sheet(item: $selectedWorkoutForDetail) { workout in
            WorkoutDetailView(
                workout: workout,
                racePaceSeconds: viewModel.racePaceSecondsPerMile ?? 480
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "An error occurred")
        }
    }
}

// MARK: - TrainingPhaseBanner

struct TrainingPhaseBanner: View {
    let phase: CanovaTrainingPhase
    let weeksOut: Int
    let goalName: String?
    let isLoading: Bool

    var body: some View {
        VStack(spacing: 16) {
            if isLoading {
                HStack(spacing: 12) {
                    ProgressView()
                        .tint(Color.drip.coral)
                    Text("Loading your training phase...")
                        .font(.dripBody(14))
                        .foregroundStyle(Color.drip.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(20)
                .background(Color.drip.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                VStack(spacing: 16) {
                    // Phase indicator
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(phase.color.opacity(0.2))
                                .frame(width: 44, height: 44)

                            Image(systemName: phase.icon)
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(phase.color)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(phase.displayName.uppercased())
                                .font(.dripCaption(11))
                                .foregroundStyle(phase.color)
                                .tracking(1.5)

                            if weeksOut > 0 {
                                Text("\(weeksOut) weeks to race")
                                    .font(.dripLabel(16))
                                    .foregroundStyle(Color.drip.textPrimary)
                            } else {
                                Text("Race week")
                                    .font(.dripLabel(16))
                                    .foregroundStyle(Color.drip.textPrimary)
                            }
                        }

                        Spacer()
                    }

                    // Goal name if available
                    if let goal = goalName {
                        HStack(spacing: 8) {
                            Image(systemName: "target")
                                .font(.system(size: 12))
                            Text(goal)
                                .font(.dripCaption(13))
                        }
                        .foregroundStyle(Color.drip.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Phase description
                    Text(phase.description)
                        .font(.dripBody(13))
                        .foregroundStyle(Color.drip.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Phase progress bar
                    PhaseProgressBar(currentPhase: phase)
                }
                .padding(20)
                .background(Color.drip.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(phase.color.opacity(0.3), lineWidth: 1)
                )
            }
        }
    }
}

// MARK: - PhaseProgressBar

struct PhaseProgressBar: View {
    let currentPhase: CanovaTrainingPhase

    private let phases = CanovaTrainingPhase.allCases

    var body: some View {
        HStack(spacing: 4) {
            ForEach(phases, id: \.self) { phase in
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(phase == currentPhase ? phase.color : Color.drip.divider)
                        .frame(height: 4)

                    Text(phase.rawValue.prefix(3).uppercased())
                        .font(.dripCaption(8))
                        .foregroundStyle(phase == currentPhase ? phase.color : Color.drip.textTertiary)
                }
            }
        }
    }
}

// MARK: - GoalPaceCard

struct GoalPaceCard: View {
    let goalTime: String
    let racePace: String

    var body: some View {
        HStack(spacing: 20) {
            VStack(spacing: 4) {
                Text("GOAL TIME")
                    .font(.dripCaption(10))
                    .foregroundStyle(Color.drip.textTertiary)
                    .tracking(1)

                Text(goalTime)
                    .font(.dripStat(24))
                    .foregroundStyle(Color.drip.coral)
            }

            Rectangle()
                .fill(Color.drip.divider)
                .frame(width: 1, height: 40)

            VStack(spacing: 4) {
                Text("RACE PACE")
                    .font(.dripCaption(10))
                    .foregroundStyle(Color.drip.textTertiary)
                    .tracking(1)

                Text(racePace)
                    .font(.dripStat(24))
                    .foregroundStyle(Color.drip.energized)
            }

            Spacer()
        }
        .padding(16)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.drip.divider, lineWidth: 1)
        )
    }
}

// MARK: - SignatureWorkoutGrid

struct SignatureWorkoutGrid: View {
    let isGenerating: Bool
    let onSelect: (CanovaSignatureType) -> Void

    private let signatureTypes: [CanovaSignatureType] = [
        .progressiveTempo,
        .descendingLadder,
        .racePaceRepeats,
        .longRunWithTempo,
    ]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(signatureTypes, id: \.self) { type in
                SignatureWorkoutButton(
                    type: type,
                    isLoading: isGenerating
                ) {
                    onSelect(type)
                }
            }
        }
    }
}

// MARK: - SignatureWorkoutButton

struct SignatureWorkoutButton: View {
    let type: CanovaSignatureType
    let isLoading: Bool
    let action: () -> Void

    var icon: String {
        switch type {
        case .progressiveTempo: return "arrow.up.right"
        case .descendingLadder: return "stairs"
        case .racePaceRepeats: return "repeat"
        case .specialBlock: return "square.2.layers.3d"
        case .longRunWithTempo: return "road.lanes"
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.drip.coral.opacity(0.15))
                        .frame(width: 40, height: 40)

                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.drip.coral)
                }

                Text(type.displayName)
                    .font(.dripLabel(13))
                    .foregroundStyle(Color.drip.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.drip.divider, lineWidth: 1)
            )
        }
        .disabled(isLoading)
        .opacity(isLoading ? 0.6 : 1)
    }
}

// MARK: - CategoryButtonRow

struct CategoryButtonRow: View {
    let isGenerating: Bool
    let onSelect: (CanovaWorkoutCategory) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(CanovaWorkoutCategory.allCases, id: \.self) { category in
                    CategoryButton(
                        category: category,
                        isLoading: isGenerating
                    ) {
                        onSelect(category)
                    }
                }
            }
        }
    }
}

// MARK: - CategoryButton

struct CategoryButton: View {
    let category: CanovaWorkoutCategory
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: category.icon)
                    .font(.system(size: 14, weight: .semibold))

                Text(category.displayName)
                    .font(.dripLabel(13))
            }
            .foregroundStyle(category.color)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(category.color.opacity(0.15))
            .clipShape(Capsule())
        }
        .disabled(isLoading)
        .opacity(isLoading ? 0.6 : 1)
    }
}

// MARK: - GeneratedWorkoutCard

struct GeneratedWorkoutCard: View {
    let workout: CanovaWorkout
    let racePaceSeconds: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(workout.name)
                        .font(.dripLabel(16))
                        .foregroundStyle(Color.drip.textPrimary)

                    HStack(spacing: 8) {
                        CategoryBadge(category: workout.category)

                        if let signature = workout.signatureType {
                            Text(signature.displayName)
                                .font(.dripCaption(10))
                                .foregroundStyle(Color.drip.textTertiary)
                        }
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.drip.textTertiary)
            }

            // Description
            Text(workout.description)
                .font(.dripBody(13))
                .foregroundStyle(Color.drip.textSecondary)
                .lineLimit(2)

            // Stats row
            HStack(spacing: 16) {
                if let distance = workout.formattedTotalDistance {
                    StatPill(icon: "figure.run", value: distance)
                }

                if let duration = workout.formattedDuration {
                    StatPill(icon: "clock", value: duration)
                }

                StatPill(icon: "list.number", value: "\(workout.activeSteps.count) intervals")
            }

            // Preview of first few steps
            VStack(alignment: .leading, spacing: 6) {
                ForEach(workout.steps.prefix(3)) { step in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(step.stepType.color)
                            .frame(width: 6, height: 6)

                        Text(step.fullDescription(racePaceSeconds: racePaceSeconds))
                            .font(.dripCaption(11))
                            .foregroundStyle(Color.drip.textSecondary)
                    }
                }

                if workout.steps.count > 3 {
                    Text("+ \(workout.steps.count - 3) more steps...")
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.textTertiary)
                        .padding(.leading, 14)
                }
            }
            .padding(.top, 4)
        }
        .padding(16)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(workout.category.color.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - CategoryBadge

struct CategoryBadge: View {
    let category: CanovaWorkoutCategory

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: category.icon)
                .font(.system(size: 10))

            Text(category.displayName)
                .font(.dripCaption(10))
        }
        .foregroundStyle(category.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(category.color.opacity(0.15))
        .clipShape(Capsule())
    }
}

// MARK: - StatPill

struct StatPill: View {
    let icon: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))

            Text(value)
                .font(.dripCaption(11))
        }
        .foregroundStyle(Color.drip.textSecondary)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        WorkoutGeneratorView()
    }
}
