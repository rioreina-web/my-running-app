//
//  WorkoutPickerSheet.swift
//  RunningLog
//
//  Bottom sheet for assigning a workout to a day cell in the plan builder.
//  Shows the coach's template library plus a quick-add option.
//

import SwiftUI

// MARK: - WorkoutPickerSheet

struct CoachWorkoutPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CoachViewModel.self) private var viewModel

    let dayOfWeek: Int
    let weekNumber: Int
    let existingWorkout: PlanTemplateWorkout
    let onAssign: (PlanTemplateWorkout) -> Void

    @State private var tab: Tab = .templates
    @State private var searchText = ""
    @State private var quickType: ScheduledWorkoutType = .easy
    @State private var quickDistanceMiles: String = ""

    enum Tab: String, CaseIterable {
        case templates = "My Templates"
        case quickAdd = "Quick Add"
        case rest = "Rest Day"
    }

    private var dayName: String {
        ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"][dayOfWeek]
    }

    private var filteredTemplates: [WorkoutTemplate] {
        guard !searchText.isEmpty else { return viewModel.workoutTemplates }
        return viewModel.workoutTemplates.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.tags.contains { $0.localizedCaseInsensitiveContains(searchText) } ||
            $0.workoutType.displayName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DripBackground().ignoresSafeArea()

                VStack(spacing: 0) {
                    // Subheader
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Week \(weekNumber), \(dayName)")
                                .font(.dripLabel(15))
                                .foregroundStyle(Color.drip.textPrimary)
                            Text("Assign a workout")
                                .font(.dripCaption(12))
                                .foregroundStyle(Color.drip.textSecondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)

                    // Tab picker
                    HStack(spacing: 0) {
                        ForEach(Tab.allCases, id: \.self) { t in
                            Button {
                                tab = t
                            } label: {
                                Text(t.rawValue)
                                    .font(.dripLabel(13))
                                    .foregroundStyle(tab == t ? Color.drip.coral : Color.drip.textSecondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .overlay(
                                        Rectangle()
                                            .frame(height: 2)
                                            .foregroundStyle(tab == t ? Color.drip.coral : .clear)
                                            .offset(y: 1),
                                        alignment: .bottom
                                    )
                            }
                        }
                    }
                    .background(Color.drip.cardBackground)

                    Divider().background(Color.drip.divider)

                    // Content
                    switch tab {
                    case .templates:
                        templatesTab
                    case .quickAdd:
                        quickAddTab
                    case .rest:
                        restTab
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("ASSIGN WORKOUT")
                        .font(.dripCaption(13))
                        .foregroundStyle(Color.drip.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .font(.dripLabel(14))
                        .foregroundStyle(Color.drip.textSecondary)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Templates Tab

    private var templatesTab: some View {
        VStack(spacing: 0) {
            // Search
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.drip.textTertiary)
                TextField("Search templates...", text: $searchText)
                    .font(.dripBody(14))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.drip.divider, lineWidth: 1)
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            if filteredTemplates.isEmpty {
                Spacer()
                Text(searchText.isEmpty ? "No templates saved yet" : "No results")
                    .font(.dripBody(14))
                    .foregroundStyle(Color.drip.textTertiary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredTemplates) { template in
                            Button {
                                assignTemplate(template)
                            } label: {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle()
                                            .fill(template.workoutType.color.opacity(0.12))
                                            .frame(width: 38, height: 38)
                                        Image(systemName: template.workoutType.icon)
                                            .font(.system(size: 15))
                                            .foregroundStyle(template.workoutType.color)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(template.name)
                                            .font(.dripLabel(14))
                                            .foregroundStyle(Color.drip.textPrimary)
                                            .lineLimit(1)
                                        if !template.summaryText.isEmpty {
                                            Text(template.summaryText)
                                                .font(.dripCaption(12))
                                                .foregroundStyle(Color.drip.textSecondary)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "plus.circle")
                                        .font(.system(size: 18))
                                        .foregroundStyle(Color.drip.coral)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(Color.drip.cardBackground)
                            }

                            Divider()
                                .background(Color.drip.divider)
                                .padding(.leading, 16)
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
        }
    }

    // MARK: Quick Add Tab

    private var quickAddTab: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Workout type
                VStack(alignment: .leading, spacing: 8) {
                    Text("TYPE")
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.textTertiary)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(ScheduledWorkoutType.allCases.filter { $0 != .rest }, id: \.self) { type in
                            Button {
                                quickType = type
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: type.icon)
                                        .font(.system(size: 18))
                                        .foregroundStyle(quickType == type ? .white : type.color)
                                    Text(type.shortName)
                                        .font(.dripCaption(11))
                                        .foregroundStyle(quickType == type ? .white : Color.drip.textPrimary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(quickType == type ? type.color : Color.drip.cardBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(quickType == type ? type.color : Color.drip.divider, lineWidth: 1)
                                )
                            }
                        }
                    }
                }

                // Distance input
                VStack(alignment: .leading, spacing: 8) {
                    Text("DISTANCE (OPTIONAL)")
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.textTertiary)
                    HStack {
                        TextField("e.g. 8", text: $quickDistanceMiles)
                            .font(.dripStat(20))
                            .keyboardType(.decimalPad)
                        Text("miles")
                            .font(.dripBody(15))
                            .foregroundStyle(Color.drip.textSecondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.drip.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.drip.divider, lineWidth: 1)
                    )
                }

                // Assign button
                Button {
                    assignQuick()
                } label: {
                    Text("Assign \(quickType.displayName)")
                        .font(.dripLabel(15))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(quickType.color)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }

    // MARK: Rest Tab

    private var restTab: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "bed.double.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.drip.textTertiary)
            Text("Set as Rest Day")
                .font(.dripLabel(18))
                .foregroundStyle(Color.drip.textPrimary)
            Text("No workout will be scheduled on this day")
                .font(.dripBody(14))
                .foregroundStyle(Color.drip.textSecondary)
                .multilineTextAlignment(.center)
            Button {
                let workout = PlanTemplateWorkout(
                    dayOfWeek: dayOfWeek,
                    workoutType: .rest,
                    workoutData: nil,
                    notes: ""
                )
                onAssign(workout)
                dismiss()
            } label: {
                Text("Mark as Rest Day")
                    .font(.dripLabel(15))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.drip.textTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 40)
            Spacer()
        }
    }

    // MARK: Actions

    private func assignTemplate(_ template: WorkoutTemplate) {
        var workoutData = template.workoutData
        // Propagate template's estimated distance if the PlannedWorkout doesn't have one
        if (workoutData.totalDistanceMiles ?? 0) <= 0 && workoutData.totalAllStepsDistanceMiles <= 0 {
            workoutData.totalDistanceMiles = template.estimatedDistanceMiles
        }
        let workout = PlanTemplateWorkout(
            dayOfWeek: dayOfWeek,
            workoutTemplateId: template.id,
            workoutType: template.workoutType,
            workoutData: workoutData,
            notes: ""
        )
        onAssign(workout)
        dismiss()
    }

    private func assignQuick() {
        let distMiles = Double(quickDistanceMiles)
        let workout = PlanTemplateWorkout(
            dayOfWeek: dayOfWeek,
            workoutType: quickType,
            workoutData: PlannedWorkout(
                id: UUID(),
                name: quickType.displayName,
                category: .regeneration,
                trainingPhase: .base,
                description: "",
                steps: [],
                totalDistanceMiles: distMiles,
                estimatedDurationMinutes: nil,
                signatureType: nil,
                createdAt: Date()
            ),
            notes: ""
        )
        onAssign(workout)
        dismiss()
    }
}
