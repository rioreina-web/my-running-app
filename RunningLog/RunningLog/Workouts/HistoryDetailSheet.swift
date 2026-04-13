//
//  HistoryDetailSheet.swift
//  RunningLog
//
//  Detail sheet for viewing and editing a training log entry.
//

import HealthKit
import Supabase
import SwiftUI

// MARK: - HistoryDetailSheet

struct HistoryDetailSheet: View {
    let entry: TrainingLog
    let onUpdate: () -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var healthKitManager = HealthKitManager()
    @State private var vm: HistoryDetailViewModel
    @State private var isLoadingInsight = false
    @State private var showDeleteConfirmation = false
    @State private var showWorkoutPicker = false
    @State private var selectedWorkout: RunningWorkout?
    @State private var workoutNotesText: String = ""
    @State private var isEditingWorkoutNotes = false

    // Edit mode state
    @State private var isEditing = false
    @State private var editMood: String = ""
    @State private var editWorkoutType: String = ""
    @State private var editDistanceText: String = ""
    @State private var editDurationText: String = ""
    @State private var editNotesText: String = ""

    // Vital workout detail
    @State private var showVitalDetail = false

    init(entry: TrainingLog, onUpdate: @escaping () -> Void) {
        self.entry = entry
        self.onUpdate = onUpdate
        self._vm = State(initialValue: HistoryDetailViewModel(entry: entry))
        self._workoutNotesText = State(initialValue: entry.workoutNotes ?? "")
    }

    var body: some View {
        NavigationStack {
        ZStack {
            Color.drip.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    // Header - use workout date when available, otherwise created date
                    VStack(spacing: 8) {
                        Text(vm.currentEntry.displayDate.dayOfWeekString)
                            .font(.dripDisplay(28))
                            .foregroundStyle(Color.drip.textPrimary)

                        Text(vm.currentEntry.displayDate.fullDateString)
                            .font(.dripBody(14))
                            .foregroundStyle(Color.drip.textSecondary)

                        if isEditing {
                            // Editable mood picker
                            EditableMoodPicker(selectedMood: $editMood)
                                .padding(.top, 4)
                        } else if let mood = vm.currentEntry.mood, !mood.isEmpty {
                            MoodBadge(mood: mood)
                                .padding(.top, 4)
                        }
                    }
                    .padding(.top, 20)

                    // AI Summary
                    if let cleaned = vm.currentEntry.cleanedNotes, !cleaned.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.drip.coral)
                                Text("AI SUMMARY")
                                    .font(.dripCaption(11))
                                    .foregroundStyle(Color.drip.textSecondary)
                                    .tracking(1.2)
                            }

                            FormattedSummaryText(text: cleaned)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(Color.drip.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.drip.coral.opacity(0.3), lineWidth: 1)
                        )
                        .padding(.horizontal, 20)
                    }

                    // Coach Insight Section (hidden in edit mode)
                    if !isEditing {
                    CoachInsightSection(
                        entry: vm.currentEntry,
                        coachInsight: Binding(get: { vm.coachInsight }, set: { vm.coachInsight = $0 }),
                        isLoading: $isLoadingInsight,
                        onSave: { insight in
                            vm.saveCoachInsight(insight)
                        }
                    )
                    .padding(.horizontal, 20)
                    }

                    // Workout Type (edit mode) or badge display
                    if isEditing {
                        EditableWorkoutTypeSection(selectedType: $editWorkoutType)
                            .padding(.horizontal, 20)
                    }

                    // Original notes
                    if isEditing {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 6) {
                                Image(systemName: "text.alignleft")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.drip.textSecondary)
                                Text("NOTES")
                                    .font(.dripCaption(11))
                                    .foregroundStyle(Color.drip.textSecondary)
                                    .tracking(1.2)
                            }

                            TextEditor(text: $editNotesText)
                                .font(.dripBody(15))
                                .foregroundStyle(Color.drip.textPrimary)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 100)
                                .padding(12)
                                .background(Color.drip.cardBackgroundElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(Color.drip.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.drip.divider, lineWidth: 1)
                        )
                        .padding(.horizontal, 20)
                    } else if let notes = vm.currentEntry.notes, !notes.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 6) {
                                Image(systemName: "text.alignleft")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.drip.textSecondary)
                                Text("ORIGINAL NOTES")
                                    .font(.dripCaption(11))
                                    .foregroundStyle(Color.drip.textSecondary)
                                    .tracking(1.2)
                            }

                            Text(notes)
                                .font(.dripBody(15))
                                .foregroundStyle(Color.drip.textSecondary)
                                .lineSpacing(4)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(Color.drip.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.drip.divider, lineWidth: 1)
                        )
                        .padding(.horizontal, 20)
                    }

                    // Linked workout section OR link workout button
                    if isEditing {
                        // Editable workout stats
                        EditableWorkoutStatsSection(
                            distanceText: $editDistanceText,
                            durationText: $editDurationText
                        )
                        .padding(.horizontal, 20)
                    } else if vm.currentEntry.hasLinkedWorkout {
                        Button {
                            if vm.matchedVitalWorkout != nil {
                                showVitalDetail = true
                            }
                        } label: {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 6) {
                                Image(systemName: "figure.run.circle.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.drip.energized)
                                Text("LINKED WORKOUT")
                                    .font(.dripCaption(11))
                                    .foregroundStyle(Color.drip.textSecondary)
                                    .tracking(1.2)

                                Spacer()

                                if vm.matchedVitalWorkout != nil {
                                    HStack(spacing: 4) {
                                        Text("View Details")
                                            .font(.dripCaption(11))
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 10, weight: .semibold))
                                    }
                                    .foregroundStyle(Color.drip.coral)
                                }
                            }

                            HStack(spacing: 0) {
                                if let distance = vm.currentEntry.formattedWorkoutDistance {
                                    WorkoutStatItem(value: distance, label: "Distance")
                                }
                                if let duration = vm.currentEntry.formattedWorkoutDuration {
                                    WorkoutStatItem(value: duration, label: "Duration")
                                }
                                if let pace = vm.currentEntry.formattedWorkoutPace {
                                    WorkoutStatItem(value: pace, label: "Pace")
                                }
                            }

                            // Show when the log was recorded if different from workout date
                            if vm.currentEntry.workoutDate != nil {
                                Text("Logged \(vm.currentEntry.createdAt.shortDateString)")
                                    .font(.dripCaption(12))
                                    .foregroundStyle(Color.drip.textTertiary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(Color.drip.energized.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.drip.energized.opacity(0.3), lineWidth: 1)
                        )
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 20)
                    } else if !isEditing {
                        // Link workout button
                        Button {
                            showWorkoutPicker = true
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(Color.drip.energized.opacity(0.15))
                                        .frame(width: 44, height: 44)

                                    Image(systemName: "link.badge.plus")
                                        .font(.system(size: 18, weight: .medium))
                                        .foregroundStyle(Color.drip.energized)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Link a Workout")
                                        .font(.dripLabel(14))
                                        .foregroundStyle(Color.drip.textPrimary)
                                    Text("Connect this log to a run from HealthKit")
                                        .font(.dripCaption(12))
                                        .foregroundStyle(Color.drip.textSecondary)
                                }

                                Spacer()

                                if vm.isLinkingWorkout {
                                    ProgressView()
                                        .tint(Color.drip.energized)
                                } else {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Color.drip.textTertiary)
                                }
                            }
                            .padding(16)
                            .background(Color.drip.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.drip.divider, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(vm.isLinkingWorkout)
                        .padding(.horizontal, 20)
                    }

                    if !isEditing {
                    // Workout Notes section
                    WorkoutNotesSection(
                        workoutNotes: $workoutNotesText,
                        isEditing: $isEditingWorkoutNotes,
                        isSaving: Binding(get: { vm.isSavingWorkoutNotes }, set: { vm.isSavingWorkoutNotes = $0 }),
                        onSave: {
                            Task {
                                let saved = await vm.saveWorkoutNotes(workoutNotesText)
                                if saved { isEditingWorkoutNotes = false }
                            }
                        }
                    )
                    .padding(.horizontal, 20)

                    // Voice memo indicator
                    if vm.currentEntry.audioUrl != nil {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Color.drip.coral.opacity(0.15))
                                    .frame(width: 44, height: 44)

                                Image(systemName: "waveform")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(Color.drip.coral)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Voice Memo")
                                    .font(.dripLabel(14))
                                    .foregroundStyle(Color.drip.textPrimary)
                                Text("Recorded audio transcribed by AI")
                                    .font(.dripCaption(12))
                                    .foregroundStyle(Color.drip.textSecondary)
                            }

                            Spacer()
                        }
                        .padding(16)
                        .background(Color.drip.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.drip.divider, lineWidth: 1)
                        )
                        .padding(.horizontal, 20)
                    }

                    // Delete button
                    Button {
                        showDeleteConfirmation = true
                    } label: {
                        HStack(spacing: 8) {
                            if vm.isDeleting {
                                ProgressView()
                                    .tint(Color.drip.injured)
                            } else {
                                Image(systemName: "trash")
                                    .font(.system(size: 14, weight: .medium))
                            }
                            Text("Delete Log")
                                .font(.dripLabel(14))
                        }
                        .foregroundStyle(Color.drip.injured)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.drip.injured.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(vm.isDeleting)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    } // end !isEditing

                    Spacer()
                        .frame(height: 40)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if isEditing {
                    Button("Cancel") {
                        isEditing = false
                    }
                    .font(.dripBody(15))
                    .foregroundStyle(Color.drip.textSecondary)
                } else {
                    Button("Edit") {
                        enterEditMode()
                    }
                    .font(.dripBody(15))
                    .foregroundStyle(Color.drip.coral)
                }
            }

            ToolbarItem(placement: .principal) {
                Text(isEditing ? "EDIT LOG" : "LOG DETAILS")
                    .font(.dripCaption(12))
                    .foregroundStyle(Color.drip.textSecondary)
                    .tracking(2)
            }

            ToolbarItem(placement: .topBarTrailing) {
                if isEditing {
                    Button {
                        Task {
                            let saved = await vm.saveEdits(
                                mood: editMood,
                                workoutType: editWorkoutType,
                                distanceText: editDistanceText,
                                durationText: editDurationText,
                                notesText: editNotesText,
                                workoutNotesText: workoutNotesText
                            )
                            if saved {
                                isEditing = false
                                onUpdate()
                            }
                        }
                    } label: {
                        if vm.isSavingEdits {
                            ProgressView()
                                .tint(Color.drip.coral)
                        } else {
                            Text("Save")
                                .font(.dripLabel(15))
                                .foregroundStyle(Color.drip.coral)
                        }
                    }
                    .disabled(vm.isSavingEdits)
                } else {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.dripBody(15))
                    .foregroundStyle(Color.drip.textSecondary)
                }
            }
        }
        .toolbarBackground(Color.drip.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        } // end NavigationStack
        .onAppear {
            loadWorkouts()
        }
        .alert("Delete Log?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    let deleted = await vm.deleteEntry()
                    if deleted {
                        onUpdate()
                        dismiss()
                    }
                }
            }
        } message: {
            Text("This will permanently delete this training log entry. This action cannot be undone.")
        }
        .sheet(isPresented: $showWorkoutPicker) {
            HistoryWorkoutPickerSheet(
                workouts: healthKitManager.recentWorkouts,
                selectedWorkout: $selectedWorkout,
                isPresented: $showWorkoutPicker,
                onSelect: { workout in
                    Task {
                        let linked = await vm.linkWorkout(workout, workoutNotesText: workoutNotesText)
                        if linked { onUpdate() }
                    }
                }
            )
        }
        .sheet(isPresented: $showVitalDetail) {
            if let vitalWorkout = vm.matchedVitalWorkout,
               let vitalId = vitalWorkout.vitalWorkoutId {
                VitalWorkoutDetailView(workout: vitalWorkout, vitalWorkoutId: vitalId)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
        .task {
            await vm.matchVitalWorkout()
        }
    }

    private func loadWorkouts() {
        Task {
            _ = await healthKitManager.requestAuthorization()
            let workouts = await healthKitManager.fetchRecentRunningWorkouts(limit: 20)
            await MainActor.run {
                healthKitManager.recentWorkouts = workouts
            }
        }
    }

    private func enterEditMode() {
        editMood = vm.currentEntry.mood ?? ""
        editWorkoutType = vm.currentEntry.workoutType ?? ""
        editDistanceText = vm.currentEntry.workoutDistanceMiles.map { String(format: "%.2f", $0) } ?? ""
        editDurationText = vm.currentEntry.workoutDurationMinutes.map { vm.formatMinutesForEdit($0) } ?? ""
        editNotesText = vm.currentEntry.cleanedNotes ?? vm.currentEntry.notes ?? ""
        isEditing = true
    }
}

// MARK: - HistoryWorkoutPickerSheet

struct HistoryWorkoutPickerSheet: View {
    let workouts: [RunningWorkout]
    @Binding var selectedWorkout: RunningWorkout?
    @Binding var isPresented: Bool
    let onSelect: (RunningWorkout) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Color.drip.background.ignoresSafeArea()

                if workouts.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "figure.run")
                            .font(.system(size: 48))
                            .foregroundStyle(Color.drip.textTertiary)
                        Text("No recent runs found")
                            .font(.dripBody(16))
                            .foregroundStyle(Color.drip.textSecondary)
                        Text("Complete a run with your Apple Watch or running app to see it here.")
                            .font(.dripCaption(14))
                            .foregroundStyle(Color.drip.textTertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(workouts) { workout in
                                Button {
                                    selectedWorkout = workout
                                    isPresented = false
                                    onSelect(workout)
                                } label: {
                                    HistoryWorkoutPickerRow(workout: workout)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(20)
                    }
                }
            }
            .navigationTitle("Link Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .font(.dripBody(15))
                    .foregroundStyle(Color.drip.textSecondary)
                }
            }
            .toolbarBackground(Color.drip.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}

// MARK: - HistoryWorkoutPickerRow

struct HistoryWorkoutPickerRow: View {
    let workout: RunningWorkout

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.drip.energized.opacity(0.15))
                    .frame(width: 44, height: 44)

                Image(systemName: "figure.run")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.drip.energized)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(workout.dayOfWeek)
                    .font(.dripLabel(15))
                    .foregroundStyle(Color.drip.textPrimary)

                HStack(spacing: 12) {
                    Text(workout.formattedDistance)
                    Text(workout.formattedDuration)
                    Text(workout.formattedPace)
                }
                .font(.dripCaption(12))
                .foregroundStyle(Color.drip.textSecondary)
            }

            Spacer()

            Text(workout.shortDate)
                .font(.dripCaption(11))
                .foregroundStyle(Color.drip.textTertiary)
        }
        .padding(14)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.drip.divider, lineWidth: 1)
        )
    }
}

// MARK: - WorkoutStatItem

struct WorkoutStatItem: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.dripStat(18))
                .foregroundStyle(Color.drip.textPrimary)
            Text(label)
                .font(.dripCaption(10))
                .foregroundStyle(Color.drip.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - FormattedSummaryText

struct FormattedSummaryText: View {
    let text: String

    private var parsedElements: [SummaryElement] {
        parseText(text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(parsedElements.enumerated()), id: \.offset) { _, element in
                switch element {
                case let .header(content):
                    Text(content.uppercased())
                        .font(.dripCaption(10))
                        .foregroundStyle(Color.drip.coral)
                        .tracking(1)
                        .padding(.top, 4)
                case let .bullet(content):
                    HStack(alignment: .top, spacing: 8) {
                        Text("–")
                            .font(.dripBody(14))
                            .foregroundStyle(Color.drip.textTertiary)
                        Text(content)
                            .font(.dripBody(14))
                            .foregroundStyle(Color.drip.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                case let .paragraph(content):
                    Text(content)
                        .font(.dripBody(14))
                        .foregroundStyle(Color.drip.textPrimary)
                        .lineSpacing(3)
                }
            }
        }
    }

    private enum SummaryElement {
        case header(String)
        case bullet(String)
        case paragraph(String)
    }

    private func parseText(_ text: String) -> [SummaryElement] {
        var elements: [SummaryElement] = []
        let lines = text.components(separatedBy: .newlines)
        var currentParagraph = ""

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                if !currentParagraph.isEmpty {
                    elements.append(.paragraph(currentParagraph.trimmingCharacters(in: .whitespaces)))
                    currentParagraph = ""
                }
                continue
            }

            // Check for bullet points
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("• ") || trimmed.hasPrefix("* ") {
                if !currentParagraph.isEmpty {
                    elements.append(.paragraph(currentParagraph.trimmingCharacters(in: .whitespaces)))
                    currentParagraph = ""
                }
                let bulletContent = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                elements.append(.bullet(bulletContent))
            }
            // Check for headers (ends with colon, short, or ALL CAPS)
            else if (trimmed.hasSuffix(":") && trimmed.count < 30) ||
                (trimmed == trimmed.uppercased() && trimmed.count < 25 && trimmed.contains(" ") == false) {
                if !currentParagraph.isEmpty {
                    elements.append(.paragraph(currentParagraph.trimmingCharacters(in: .whitespaces)))
                    currentParagraph = ""
                }
                let headerContent = trimmed.hasSuffix(":") ? String(trimmed.dropLast()) : trimmed
                elements.append(.header(headerContent))
            }
            // Regular text - accumulate into paragraph
            else {
                if !currentParagraph.isEmpty {
                    currentParagraph += " "
                }
                currentParagraph += trimmed
            }
        }

        // Add remaining paragraph
        if !currentParagraph.isEmpty {
            elements.append(.paragraph(currentParagraph.trimmingCharacters(in: .whitespaces)))
        }

        return elements
    }
}

// MARK: - HistoryEntrySkeleton

struct HistoryEntrySkeleton: View {
    var body: some View {
        SkeletonPulse {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        SkeletonBar(width: 80, height: 14)
                        SkeletonBar(width: 100, height: 10)
                    }
                    Spacer()
                    SkeletonBar(width: 70, height: 24)
                }

                VStack(alignment: .leading, spacing: 6) {
                    SkeletonBar(height: 12)
                    SkeletonBar(width: 200, height: 12)
                }
            }
            .padding(16)
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
}

// MARK: - EmptyHistoryView

struct EmptyHistoryView: View {
    var body: some View {
        EmptyStateView(
            icon: "clock.arrow.circlepath",
            title: "No logs yet",
            subtitle: "Your training logs will appear here"
        )
    }
}
