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
    /// Seed for `linkWorkout`, which carries the description onto a newly
    /// linked run. No longer an editor: `workout_notes` is edited in exactly
    /// one place, `TheWorkoutBlock`. (2026-08-10)
    @State var workoutNotesText: String = ""
    /// "READ THE WORDS ↓" — reveals the verbatim transcript under the memo.
    /// Per-sheet, so paging to another entry starts collapsed again.
    @State var showTranscript = false
    /// "✦ READ THE INSIGHT" — reveals (or generates, then reveals) the coach's
    /// read. Starts false on every entry: the insight is opt-in per visit.
    @State var showInsight = false

    // Edit mode state
    @State var isEditing = false
    @State var editTitle: String = ""
    @State var editMood: String = ""
    @State var editWorkoutType: String = ""
    @State var editDistanceText: String = ""
    @State var editDurationText: String = ""
    @State var editNotesText: String = ""

    // ── Tap-to-edit state (title + mood) ─────────────────────────────────
    //
    // Deliberately separate from `isEditing` above. That is the sheet's
    // whole-entry mode: it swaps the page for a form and holds six fields
    // hostage behind one Save. Fixing a title should not cost that, so the
    // headline and the mood pill each edit themselves in place and save
    // themselves — one column per write (see `saveTitleInline` /
    // `saveMoodInline`).

    /// The headline is a text field right now.
    @State var isEditingTitleInline = false
    /// Draft title while the field is open. Committed on keyboard "done" and
    /// on focus loss, so tapping away saves rather than discards.
    @State var inlineTitleText: String = ""
    /// What the field was seeded with. A tap that changes nothing must not
    /// write: the seed is `resolvedTitle`, which falls back to the DERIVED
    /// workout label ("Intervals"), and writing that back would freeze a
    /// generated name into the athlete-authored `title` column — after which
    /// changing the workout type would no longer change the header, ever.
    @State var inlineTitleSeed: String = ""
    @FocusState var titleFieldFocused: Bool
    /// True once the field has actually held focus. SwiftUI can reset a focus
    /// value that no view has claimed yet, and without this the reset reads as
    /// "the athlete tapped away" and closes the editor before they've typed.
    @State var titleFieldDidFocus = false
    /// The mood pills are expanded under the headline.
    @State var isPickingMoodInline = false
    /// Mood shown optimistically while its save is in flight. The picker
    /// collapses on tap, so without this the old pill sits there for the
    /// length of the round trip and the tap looks ignored.
    @State var pendingMood: String?
    /// The last inline save failed. Surfaced under the headline: the field has
    /// already closed by then, so a silent failure looks exactly like an edit
    /// that evaporated.
    @State var inlineSaveFailed = false

    /// The voice memo player is revealed. Off by default: the recording sits
    /// behind the "▶ MEMO" corner affordance on the summary rather than
    /// printing a waveform in the middle of the athlete's own words.
    @State var showMemoPlayer = false

    // Vital workout detail
    @State var showVitalDetail = false

    // "The Effort, compared" — workout comparison sheet
    @State var showComparison = false

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
                                title: editTitle,
                                mood: editMood,
                                workoutType: editWorkoutType,
                                distanceText: editDistanceText,
                                durationText: editDurationText,
                                notesText: editNotesText
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
        .sheet(isPresented: $showComparison) {
            // "The Effort, compared" — deterministic diff vs. a similar past
            // session + the coach's read (compare-workouts edge function).
            // Same id rule as WorkoutRepDetailSheet above: the laps-bearing
            // training_logs row. Lowercased to match PostgREST's uuid text
            // representation (the manual picker excludes the current row by
            // string comparison).
            WorkoutComparisonSheet(workoutId: workoutDetailId.uuidString.lowercased())
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

    // Intentionally `internal` (not `private`) so the `editorialBody`
    // extension in HistoryDetailSheet+Editorial.swift can trigger edit mode
    // from the inline "EDIT" affordance on the VOICE SUMMARY section.
    func enterEditMode() {
        // COMMIT the inline field before closing it — don't just clear the
        // flag. Tapping a button doesn't resign first responder on its own, so
        // "type a title, then tap EDIT" arrives here with an uncommitted
        // draft; clearing first would drop it AND then seed `editTitle` from
        // the stale stored title, so Save would write the old name back over
        // the new one.
        // Flattened on capture: `saveEdits` trims but doesn't flatten, so a
        // draft carrying a line break would store one from the form path.
        let draft = isEditingTitleInline ? Self.normalizedTitle(inlineTitleText) : nil
        if isEditingTitleInline { commitInlineTitle() }
        isPickingMoodInline = false

        // Start editing from the current header — the athlete's own title if set,
        // otherwise the workout title — so a tap-to-edit refines the workout name
        // rather than opening a blank field. `commitInlineTitle` saves
        // asynchronously, so prefer the draft over `vm.currentEntry`, which
        // hasn't caught up yet.
        editTitle = draft ?? vm.currentEntry.resolvedTitle ?? ""
        editMood = vm.currentEntry.mood ?? ""
        editWorkoutType = vm.currentEntry.workoutType ?? ""
        editDistanceText = vm.currentEntry.workoutDistanceMiles.map { String(format: "%.2f", $0) } ?? ""
        editDurationText = vm.currentEntry.workoutDurationMinutes.map { vm.formatMinutesForEdit($0) } ?? ""
        editNotesText = vm.currentEntry.cleanedNotes ?? vm.currentEntry.notes ?? ""
        isEditing = true
    }

    // ────────────────────────────────────────────────────────────────────
    // MARK: - Tap-to-edit: title
    // ────────────────────────────────────────────────────────────────────

    /// Tap the headline → edit it where it sits.
    ///
    /// Seeded from `resolvedTitle` (the athlete's own title, else the workout
    /// name) so the tap refines what is printed rather than opening a blank
    /// field — same seed `enterEditMode` uses, so the two editors can't
    /// disagree about what the current title is.
    /// One definition of "the same title", shared by the tap-away guard here
    /// and `saveTitleInline`. Two spellings of this rule is how a stray space
    /// becomes a write.
    static func normalizedTitle(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func beginInlineTitleEdit() {
        guard !isEditing else { return }
        inlineTitleSeed = vm.currentEntry.resolvedTitle ?? ""
        inlineTitleText = inlineTitleSeed
        inlineSaveFailed = false
        titleFieldDidFocus = false
        isEditingTitleInline = true
        // Next runloop, not this one: `.focused($titleFieldFocused)` isn't in
        // the hierarchy until the field has been rendered, and a focus value
        // no view has claimed gets reset — which would open the editor with no
        // keyboard, or bounce it straight back shut.
        DispatchQueue.main.async { titleFieldFocused = true }
    }

    /// Save the inline title and close the field.
    ///
    /// Called from the keyboard's Done button AND from focus loss, so there is
    /// no gesture that types a title and loses it. Idempotent: the guard makes
    /// the second call (focus loss following an explicit commit) a no-op, and
    /// `saveTitleInline` itself skips the write when nothing changed.
    func commitInlineTitle() {
        guard isEditingTitleInline else { return }
        let text = inlineTitleText
        isEditingTitleInline = false
        titleFieldFocused = false

        // Untouched seed → close, write nothing. Without this, opening the
        // headline and tapping away would persist the derived workout label
        // as an athlete-authored title (see `inlineTitleSeed`).
        //
        // Compared through the same normalization the save applies, or a
        // stray space or Return — the field wraps, so Return is reachable —
        // reads as an edit and writes the derived label after all.
        guard Self.normalizedTitle(text) != Self.normalizedTitle(inlineTitleSeed) else { return }

        Task {
            switch await vm.saveTitleInline(text) {
            case .saved:
                inlineSaveFailed = false
                onUpdate()
            case .unchanged:
                inlineSaveFailed = false
            case .failed:
                inlineSaveFailed = true
            }
        }
    }

    // ────────────────────────────────────────────────────────────────────
    // MARK: - Tap-to-edit: mood
    // ────────────────────────────────────────────────────────────────────

    /// Tapping a mood pill IS the save. No Save button, no mode — the write is
    /// one column and reversible by tapping again, so confirmation would cost
    /// more than the mistake.
    func commitInlineMood(_ mood: String) {
        // Show it immediately; the round trip catches up. `pendingMood` is the
        // pill the athlete just tapped, so the badge changes under their
        // finger rather than after the network.
        pendingMood = mood
        inlineSaveFailed = false
        Task {
            let result = await vm.saveMoodInline(mood)
            // Only clear MY optimistic value. Two quick taps put two saves in
            // flight, and clearing unconditionally would flash the first
            // tap's mood back over the second one's.
            if pendingMood == mood { pendingMood = nil }
            switch result {
            case .saved: onUpdate()
            case .unchanged: break
            case .failed: inlineSaveFailed = true
            }
        }
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
    /// Body size. Defaults to the original 14pt; the journal's SUMMARY section
    /// passes 13.5 so the summary sits below the stat strip in the hierarchy.
    var size: CGFloat = 14
    /// Body color. Defaults to the original ink; the journal passes
    /// `textSecondary` for the same reason.
    var color: Color = Color.drip.textPrimary
    /// Leading between wrapped lines. 3 is tight enough for a supporting
    /// caption; the journal's SUMMARY passes 6 because at 16.5pt it is the
    /// entry's lead paragraph and wants magazine leading.
    var lineSpacing: CGFloat = 3

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
                            .font(.dripBody(size))
                            .foregroundStyle(Color.drip.textTertiary)
                        Text(content)
                            .font(.dripBody(size))
                            .foregroundStyle(color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                case let .paragraph(content):
                    Text(content)
                        .font(.dripBody(size))
                        .foregroundStyle(color)
                        .lineSpacing(lineSpacing)
                        .fixedSize(horizontal: false, vertical: true)
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
