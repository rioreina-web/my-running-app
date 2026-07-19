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
    @StateObject var healthKitManager = HealthKitManager()
    // `vm` and the @State vars below are intentionally `internal` (no
    // `private`) so the `editorialBody` extension in
    // `HistoryDetailSheet+Editorial.swift` can read them. Swift's
    // `private` is file-scoped and would hide them from the extension.
    @State var vm: HistoryDetailViewModel
    @State var showDeleteConfirmation = false
    @State var showWorkoutPicker = false
    @State var selectedWorkout: RunningWorkout?
    @State var workoutNotesText: String = ""
    @State var isEditingWorkoutNotes = false

    // Edit mode state
    @State var isEditing = false
    @State var editMood: String = ""
    @State var editWorkoutType: String = ""
    @State var editDistanceText: String = ""
    @State var editDurationText: String = ""
    @State var editNotesText: String = ""

    // Vital workout detail
    @State var showVitalDetail = false

    init(entry: TrainingLog, onUpdate: @escaping () -> Void) {
        self.entry = entry
        self.onUpdate = onUpdate
        self._vm = State(initialValue: HistoryDetailViewModel(entry: entry))
        self._workoutNotesText = State(initialValue: entry.workoutNotes ?? "")
    }

    /// The training_logs row id whose telemetry the "VIEW DETAIL" sheet and the
    /// inline WORKOUT section should chart. For a Strava-linked entry the GPS
    /// stream + laps live on the matched Strava row, not on this (voice/manual)
    /// entry — so open that row. When there is no linked Strava row, fall back to
    /// this entry's own id. Intentionally `internal` (not `private`) so the
    /// `editorialBody` extension in HistoryDetailSheet+Editorial.swift can read it.
    var workoutDetailId: UUID {
        vm.linkedStreamLogId ?? entry.id
    }

    var body: some View {
        NavigationStack {
        ZStack {
            Color.drip.background.ignoresSafeArea()

            editorialBody

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

            // Principal "LOG DETAILS" centerpiece removed — the
            // editorial plate strip now carries the title.

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
            // Canonical workout detail — the rep-by-rep chart (WorkoutRepChart)
            // reads the clean `running_workout_laps` table keyed on the
            // training_logs row id, plus the prescribed-workout notes. This
            // replaced the old per-source fork (legacy Vital view vs. the
            // broken stream-parser Analyst view).
            //
            // A Strava import lives in its OWN training_logs row (with the GPS
            // stream + laps), separate from this voice/manual entry. When the
            // entry is linked to such a row, open THAT row so the detail has
            // telemetry to chart — opening `entry.id` (this voice-log row, which
            // has no stream) is what showed the "Logged without GPS" state on a
            // run that was in fact recorded with GPS. HealthKit/Vital matches
            // keep `entry.id` because their id is not a training_logs row id.
            WorkoutRepDetailSheet(workoutId: workoutDetailId)
        }
        .task {
            await vm.matchVitalWorkout()
            // Poll notes and the coach insight concurrently — each waits up to
            // ~24s for its server-written value, so running them in series would
            // stall the insight behind the notes. The AI Insight section then
            // appears on its own the moment `coach_insight` lands.
            async let notes: Void = fillWorkoutNotesWhenReady()
            async let insight: Void = vm.refreshCoachInsightWhenReady()
            _ = await (notes, insight)
        }
    }

    /// The note is written server-side after the voice memo processes, so when
    /// the sheet first opened `entry.workoutNotes` was often empty. Poll a few
    /// times and fill the field once it lands — but never clobber text the user
    /// has started typing (guarded on `workoutNotesText.isEmpty`).
    private func fillWorkoutNotesWhenReady() async {
        for _ in 0..<8 {
            if !workoutNotesText.isEmpty { return }
            if let n = await vm.latestWorkoutNotes(), !n.isEmpty {
                await MainActor.run {
                    if workoutNotesText.isEmpty { workoutNotesText = n }
                }
                return
            }
            try? await Task.sleep(for: .seconds(3))
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
