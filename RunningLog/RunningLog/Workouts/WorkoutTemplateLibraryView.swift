//
//  WorkoutTemplateLibraryView.swift
//  RunningLog
//
//  Coach's saved workout template library.
//  Filterable by workout type. Tap to preview, swipe to delete, "+" to create new.
//

import SwiftUI

// MARK: - WorkoutTemplateLibraryView

struct WorkoutTemplateLibraryView: View {
    @Environment(CoachViewModel.self) private var viewModel
    @State private var searchText = ""
    @State private var selectedType: ScheduledWorkoutType? = nil
    @State private var showEditor = false
    @State private var editingTemplate: WorkoutTemplate? = nil
    @State private var selectedTemplate: WorkoutTemplate? = nil

    private var filtered: [WorkoutTemplate] {
        viewModel.workoutTemplates.filter { template in
            let matchesType = selectedType == nil || template.workoutType == selectedType
            let matchesSearch = searchText.isEmpty ||
                template.name.localizedCaseInsensitiveContains(searchText) ||
                template.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }
            return matchesType && matchesSearch
        }
    }

    var body: some View {
        ZStack {
            DripBackground().ignoresSafeArea()

            VStack(spacing: 0) {
                // Search bar
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.drip.textTertiary)
                    TextField("Search workouts or tags...", text: $searchText)
                        .font(.dripBody(15))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.drip.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.drip.divider, lineWidth: 1)
                )
                .padding(.horizontal, 20)
                .padding(.top, 12)

                // Type filter chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        TypeChip(label: "All", icon: nil, isSelected: selectedType == nil) {
                            selectedType = nil
                        }
                        ForEach(ScheduledWorkoutType.allCases.filter { $0 != .rest }, id: \.self) { type in
                            TypeChip(
                                label: type.shortName,
                                icon: type.icon,
                                color: type.color,
                                isSelected: selectedType == type
                            ) {
                                selectedType = selectedType == type ? nil : type
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }

                Divider()
                    .background(Color.drip.divider)

                if filtered.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(filtered) { template in
                                WorkoutTemplateRow(template: template)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedTemplate = template
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button(role: .destructive) {
                                            Task { await viewModel.deleteWorkoutTemplate(template) }
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                        Button {
                                            editingTemplate = template
                                            showEditor = true
                                        } label: {
                                            Label("Edit", systemImage: "pencil")
                                        }
                                        .tint(Color.drip.coralLight)
                                    }

                                Divider()
                                    .background(Color.drip.divider)
                                    .padding(.leading, 20)
                            }
                        }
                        .padding(.bottom, 100)
                    }
                }
            }
        }
        .navigationTitle("Workout Library")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editingTemplate = nil
                    showEditor = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Color.drip.coral)
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            WorkoutTemplateEditorView(existingTemplate: editingTemplate)
                .environment(viewModel)
        }
        .sheet(item: $selectedTemplate) { template in
            WorkoutTemplatePreviewSheet(template: template)
                .environment(viewModel)
        }
        .task {
            if viewModel.workoutTemplates.isEmpty {
                await viewModel.loadWorkoutTemplates()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "dumbbell.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color.drip.textTertiary)
            Text("No workout templates yet")
                .font(.dripLabel(17))
                .foregroundStyle(Color.drip.textPrimary)
            Text(searchText.isEmpty
                 ? "Tap + to create your first reusable workout"
                 : "No workouts match your search")
                .font(.dripBody(14))
                .foregroundStyle(Color.drip.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            if searchText.isEmpty {
                Button {
                    editingTemplate = nil
                    showEditor = true
                } label: {
                    Text("Create Template")
                        .font(.dripLabel(14))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.drip.coral)
                        .clipShape(Capsule())
                }
            }
            Spacer()
        }
    }
}

// MARK: - WorkoutTemplateRow

struct WorkoutTemplateRow: View {
    let template: WorkoutTemplate

    var body: some View {
        HStack(spacing: 14) {
            // Type icon badge
            ZStack {
                Circle()
                    .fill(template.workoutType.color.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: template.workoutType.icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(template.workoutType.color)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(template.name)
                    .font(.dripLabel(15))
                    .foregroundStyle(Color.drip.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(template.workoutType.displayName)
                        .font(.dripCaption(12))
                        .foregroundStyle(template.workoutType.color)

                    let effectiveDist = template.estimatedDistanceMiles ?? template.workoutData.effectiveDistanceMiles
                    let rowSummary: String = {
                        var parts: [String] = []
                        if let d = effectiveDist { parts.append(String(format: "%.1f mi", d)) }
                        if let m = template.estimatedDurationMinutes {
                            if m >= 60 {
                                let h = m / 60; let rem = m % 60
                                parts.append(rem > 0 ? "\(h)h \(rem)m" : "\(h)h")
                            } else { parts.append("\(m) min") }
                        }
                        return parts.joined(separator: " · ")
                    }()
                    if !rowSummary.isEmpty {
                        Text("·")
                            .font(.dripCaption(12))
                            .foregroundStyle(Color.drip.textTertiary)
                        Text(rowSummary)
                            .font(.dripCaption(12))
                            .foregroundStyle(Color.drip.textSecondary)
                    }
                }

                if !template.tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(template.tags.prefix(3), id: \.self) { tag in
                            Text(tag)
                                .font(.dripCaption(11))
                                .foregroundStyle(Color.drip.textTertiary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.drip.divider)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.top, 2)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.drip.textTertiary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color.drip.cardBackground)
    }
}

// MARK: - TypeChip

private struct TypeChip: View {
    let label: String
    let icon: String?
    var color: Color = Color.drip.textSecondary
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .medium))
                }
                Text(label)
                    .font(.dripCaption(12))
            }
            .foregroundStyle(isSelected ? .white : color)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isSelected ? color : Color.drip.cardBackground)
            .overlay(
                Capsule()
                    .stroke(isSelected ? color : Color.drip.divider, lineWidth: 1)
            )
            .clipShape(Capsule())
        }
    }
}

// MARK: - WorkoutTemplatePreviewSheet

struct WorkoutTemplatePreviewSheet: View {
    let template: WorkoutTemplate
    @Environment(\.dismiss) private var dismiss
    @Environment(CoachViewModel.self) private var viewModel
    @State private var showEditor = false

    var body: some View {
        NavigationStack {
            ZStack {
                DripBackground().ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Header
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(template.workoutType.color.opacity(0.12))
                                    .frame(width: 52, height: 52)
                                Image(systemName: template.workoutType.icon)
                                    .font(.system(size: 22, weight: .medium))
                                    .foregroundStyle(template.workoutType.color)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(template.name)
                                    .font(.dripLabel(18))
                                    .foregroundStyle(Color.drip.textPrimary)
                                Text(template.workoutType.displayName)
                                    .font(.dripCaption(13))
                                    .foregroundStyle(template.workoutType.color)
                            }
                            Spacer()
                        }

                        let displayDist = template.estimatedDistanceMiles ?? template.workoutData.effectiveDistanceMiles
                        if displayDist != nil || template.estimatedDurationMinutes != nil {
                            HStack(spacing: 16) {
                                if let dist = displayDist {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(String(format: "%.1f mi", dist))
                                            .font(.dripStat(20))
                                            .foregroundStyle(Color.drip.textPrimary)
                                        Text("Distance")
                                            .font(.dripCaption(11))
                                            .foregroundStyle(Color.drip.textTertiary)
                                    }
                                }
                                if let mins = template.estimatedDurationMinutes {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(mins) min")
                                            .font(.dripStat(20))
                                            .foregroundStyle(Color.drip.textPrimary)
                                        Text("Duration")
                                            .font(.dripCaption(11))
                                            .foregroundStyle(Color.drip.textTertiary)
                                    }
                                }
                            }
                        }

                        if let desc = template.description, !desc.isEmpty {
                            Text(desc)
                                .font(.dripBody(15))
                                .foregroundStyle(Color.drip.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        // Steps
                        if !template.workoutData.steps.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                Text("WORKOUT STEPS")
                                    .font(.dripCaption(11))
                                    .foregroundStyle(Color.drip.textTertiary)
                                    .padding(.bottom, 8)

                                VStack(spacing: 0) {
                                    ForEach(Array(template.workoutData.steps.enumerated()), id: \.element.id) { idx, step in
                                        HStack(spacing: 12) {
                                            // Step type indicator
                                            RoundedRectangle(cornerRadius: 3)
                                                .fill(step.stepType.color)
                                                .frame(width: 4, height: 36)

                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(step.stepType.displayName)
                                                    .font(.dripCaption(11))
                                                    .foregroundStyle(Color.drip.textTertiary)
                                                Text(step.formattedDuration)
                                                    .font(.dripLabel(14))
                                                    .foregroundStyle(Color.drip.textPrimary)
                                            }

                                            Spacer()

                                            if step.targetPaceIntensity != nil {
                                                Text(step.targetPaceIntensity!.displayPercentage + " MP")
                                                    .font(.dripStat(13))
                                                    .foregroundStyle(Color.drip.textSecondary)
                                            }
                                        }
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 12)
                                        .background(Color.drip.cardBackground)

                                        if idx < template.workoutData.steps.count - 1 {
                                            Divider()
                                                .background(Color.drip.divider)
                                                .padding(.leading, 28)
                                        }
                                    }
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.drip.divider, lineWidth: 1)
                                )
                            }
                        }

                        // Tags
                        if !template.tags.isEmpty {
                            FlowLayout(spacing: 6) {
                                ForEach(template.tags, id: \.self) { tag in
                                    Text(tag)
                                        .font(.dripCaption(12))
                                        .foregroundStyle(Color.drip.textSecondary)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Color.drip.divider)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                    .padding(20)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Workout Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .font(.dripLabel(14))
                        .foregroundStyle(Color.drip.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { showEditor = true }
                        .font(.dripLabel(14))
                        .foregroundStyle(Color.drip.coral)
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            WorkoutTemplateEditorView(existingTemplate: template)
                .environment(viewModel)
        }
    }
}

// FlowLayout is defined in WeeklyCoachingReportSheet.swift
