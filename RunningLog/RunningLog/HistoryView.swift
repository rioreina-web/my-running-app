import HealthKit
import os
import Supabase
import SwiftUI

// MARK: - HistoryLogEntry

struct HistoryLogEntry: Codable, Identifiable {
    let id: UUID
    let createdAt: Date
    let audioUrl: String?
    let notes: String?
    let cleanedNotes: String?
    let mood: String?
    let workoutDate: Date?
    let workoutDistanceMiles: Double?
    let workoutDurationMinutes: Double?
    let coachInsight: String?
    let workoutNotes: String?
    let workoutType: String?
    let workoutPacePerMile: String?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case audioUrl = "audio_url"
        case notes
        case cleanedNotes = "cleaned_notes"
        case mood
        case workoutDate = "workout_date"
        case workoutDistanceMiles = "workout_distance_miles"
        case workoutDurationMinutes = "workout_duration_minutes"
        case coachInsight = "coach_insight"
        case workoutNotes = "workout_notes"
        case workoutType = "workout_type"
        case workoutPacePerMile = "workout_pace_per_mile"
    }

    var hasLinkedWorkout: Bool {
        workoutDate != nil && workoutDistanceMiles != nil
    }

    /// The date to display - uses workout date (when run occurred) if available, otherwise created date
    var displayDate: Date {
        workoutDate ?? createdAt
    }

    var formattedWorkoutDistance: String? {
        guard let miles = workoutDistanceMiles else { return nil }
        return String(format: "%.2f mi", miles)
    }

    var formattedWorkoutDuration: String? {
        guard let minutes = workoutDurationMinutes else { return nil }
        let totalSeconds = Int((minutes * 60).rounded())
        let hours = totalSeconds / 3600
        let mins = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, mins, secs)
        }
        return String(format: "%d:%02d", mins, secs)
    }

    var formattedWorkoutPace: String? {
        guard let miles = workoutDistanceMiles, let minutes = workoutDurationMinutes, miles > 0 else { return nil }
        let totalSeconds = Int(((minutes / miles) * 60).rounded())
        let paceMinutes = totalSeconds / 60
        let paceSeconds = totalSeconds % 60
        return String(format: "%d:%02d /mi", paceMinutes, paceSeconds)
    }
}

// MARK: - HistoryView

struct HistoryView: View {
    @State private var entries: [HistoryLogEntry] = []
    @State private var isLoading = false
    @State private var selectedEntry: HistoryLogEntry?
    @State private var showExport = false
    @State private var showInjuries = false
    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        ZStack {
            DripBackground()

            ScrollView {
                VStack(spacing: 24) {
                    // Stats summary
                    if !entries.isEmpty {
                        HistoryStatsHeader(entries: entries)
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                    }

                    // Entries list
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeader("Training Logs", action: loadEntries, actionIcon: "arrow.clockwise")
                            .padding(.horizontal, 20)

                        if isLoading {
                            VStack(spacing: 12) {
                                ForEach(0 ..< 4, id: \.self) { _ in
                                    HistoryEntrySkeleton()
                                }
                            }
                            .padding(.horizontal, 20)
                        } else if entries.isEmpty {
                            EmptyHistoryView()
                                .padding(.horizontal, 20)
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(entries) { entry in
                                    HistoryEntryCard(entry: entry)
                                        .onTapGesture {
                                            selectedEntry = entry
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
                Text("HISTORY")
                    .font(.dripCaption(12))
                    .foregroundStyle(Color.drip.textSecondary)
                    .tracking(2)
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    Button {
                        showInjuries = true
                    } label: {
                        Image(systemName: "bandage.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color.drip.coral)
                    }

                    Button {
                        showExport = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color.drip.coral)
                    }
                }
            }
        }
        .toolbarBackground(Color.drip.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear {
            Task { await fetchEntries() }
        }
        .sheet(item: $selectedEntry) { entry in
            HistoryDetailSheet(entry: entry) {
                // Refresh entries after delete or update
                Task { await fetchEntries() }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showExport) {
            ExportView()
        }
        .fullScreenCover(isPresented: $showInjuries) {
            NavigationStack {
                InjuryListView()
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                showInjuries = false
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(Color.drip.textSecondary)
                            }
                        }
                    }
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
            Button("Retry") {
                Task { await fetchEntries() }
            }
        } message: {
            Text(errorMessage ?? "An error occurred")
        }
    }

    private func loadEntries() {
        Task { await fetchEntries() }
    }

    private func fetchEntries() async {
        await MainActor.run { isLoading = true }

        do {
            let response: [HistoryLogEntry] = try await supabase
                .from("training_logs")
                .select()
                .order("created_at", ascending: false)
                .limit(50)
                .execute()
                .value

            await MainActor.run {
                // Sort by displayDate (workout date when available, otherwise created date)
                entries = response.sorted { $0.displayDate > $1.displayDate }
                isLoading = false
            }
        } catch {
            Log.database.error("Failed to fetch entries: \(error)")
            await MainActor.run {
                isLoading = false
                errorMessage = "Could not load training logs. Pull down to try again."
                showError = true
            }
        }
    }
}

// MARK: - HistoryStatsHeader

struct HistoryStatsHeader: View {
    let entries: [HistoryLogEntry]

    var thisWeekEntries: [HistoryLogEntry] {
        let calendar = Calendar.current
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return entries.filter { $0.displayDate >= weekAgo }
    }

    var totalEntries: Int {
        entries.count
    }

    var thisWeekCount: Int {
        thisWeekEntries.count
    }

    var dominantMood: String {
        let moods = entries.compactMap(\.mood)
        guard !moods.isEmpty else { return "—" }

        let moodCounts = Dictionary(grouping: moods, by: { $0.lowercased() })
            .mapValues { $0.count }
        return moodCounts.max(by: { $0.value < $1.value })?.key.capitalized ?? "—"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("OVERVIEW")
                .font(.dripCaption(11))
                .foregroundStyle(Color.drip.textSecondary)
                .tracking(1.5)

            HStack(spacing: 12) {
                HistoryStatCard(
                    value: "\(totalEntries)",
                    label: "Total Logs",
                    icon: "doc.text.fill"
                )

                HistoryStatCard(
                    value: "\(thisWeekCount)",
                    label: "This Week",
                    icon: "calendar"
                )

                HistoryStatCard(
                    value: dominantMood,
                    label: "Top Mood",
                    icon: "face.smiling.fill"
                )
            }
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [Color.drip.coral.opacity(0.1), Color.drip.cardBackground],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.drip.coral.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - HistoryStatCard

struct HistoryStatCard: View {
    let value: String
    let label: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.drip.coral)

            Text(value)
                .font(.dripStat(20))
                .foregroundStyle(Color.drip.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(label)
                .font(.dripCaption(10))
                .foregroundStyle(Color.drip.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - HistoryEntryCard

struct HistoryEntryCard: View {
    let entry: HistoryLogEntry

    var displayText: String {
        if let cleaned = entry.cleanedNotes, !cleaned.isEmpty {
            return cleaned
        } else if let notes = entry.notes, !notes.isEmpty {
            return notes
        } else if entry.audioUrl != nil {
            return "Voice memo (processing...)"
        }
        return "No notes"
    }

    var entryType: EntryType {
        if entry.audioUrl != nil {
            return .voice
        }
        return .text
    }

    enum EntryType {
        case voice
        case text

        var icon: String {
            switch self {
            case .voice: "waveform"
            case .text: "doc.text"
            }
        }

        var label: String {
            switch self {
            case .voice: "Voice"
            case .text: "Text"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header - use workout date when available, otherwise created date
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.displayDate.dayOfWeekString)
                        .font(.dripLabel(15))
                        .foregroundStyle(Color.drip.textPrimary)

                    Text(entry.displayDate.shortDateString)
                        .font(.dripCaption(12))
                        .foregroundStyle(Color.drip.textSecondary)
                }

                Spacer()

                HStack(spacing: 8) {
                    if let workoutType = entry.workoutType {
                        WorkoutTypeBadge(type: workoutType)
                    }

                    if let mood = entry.mood, !mood.isEmpty {
                        MoodBadge(mood: mood)
                    }

                    EntryTypeBadge(type: entryType)
                }
            }

            // Linked workout info
            if entry.hasLinkedWorkout {
                LinkedWorkoutBanner(entry: entry)
            }

            // Content preview
            Text(displayText)
                .font(.dripBody(14))
                .foregroundStyle(Color.drip.textSecondary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)

            // Chevron hint
            HStack {
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.drip.textTertiary)
            }
        }
        .padding(16)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(entry.hasLinkedWorkout ? Color.drip.energized.opacity(0.4) : Color.drip.divider, lineWidth: 1)
        )
    }
}

// MARK: - LinkedWorkoutBanner

struct LinkedWorkoutBanner: View {
    let entry: HistoryLogEntry

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "figure.run.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(Color.drip.energized)

            HStack(spacing: 16) {
                if let distance = entry.formattedWorkoutDistance {
                    Label(distance, systemImage: "location.fill")
                }
                if let duration = entry.formattedWorkoutDuration {
                    Label(duration, systemImage: "timer")
                }
                if let pace = entry.formattedWorkoutPace {
                    Label(pace, systemImage: "speedometer")
                }
            }
            .font(.dripCaption(11))
            .foregroundStyle(Color.drip.textSecondary)

            Spacer()
        }
        .padding(10)
        .background(Color.drip.energized.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - EntryTypeBadge

struct EntryTypeBadge: View {
    let type: HistoryEntryCard.EntryType

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: type.icon)
                .font(.system(size: 10, weight: .medium))
            Text(type.label)
                .font(.dripCaption(10))
        }
        .foregroundStyle(Color.drip.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.drip.cardBackgroundElevated)
        .clipShape(Capsule())
        .fixedSize()
    }
}

// MARK: - WorkoutTypeBadge

struct WorkoutTypeBadge: View {
    let type: String

    private var label: String {
        switch type {
        case "easy": return "Easy"
        case "tempo": return "Tempo"
        case "interval": return "Intervals"
        case "long_run": return "Long Run"
        case "recovery": return "Recovery"
        case "race": return "Race"
        default: return "Workout"
        }
    }

    var body: some View {
        Text(label)
            .font(.dripCaption(10))
            .foregroundStyle(Color.drip.coral)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.drip.coral.opacity(0.12))
            .clipShape(Capsule())
            .fixedSize()
    }
}

// MARK: - HistoryDetailSheet

struct HistoryDetailSheet: View {
    let entry: HistoryLogEntry
    let onUpdate: () -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var healthKitManager = HealthKitManager()
    @State private var coachInsight: String?
    @State private var isLoadingInsight = false
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var showWorkoutPicker = false
    @State private var selectedWorkout: RunningWorkout?
    @State private var isLinkingWorkout = false
    @State private var currentEntry: HistoryLogEntry
    @State private var workoutNotesText: String = ""
    @State private var isEditingWorkoutNotes = false
    @State private var isSavingWorkoutNotes = false

    // Edit mode state
    @State private var isEditing = false
    @State private var isSavingEdits = false
    @State private var editMood: String = ""
    @State private var editWorkoutType: String = ""
    @State private var editDistanceText: String = ""
    @State private var editDurationText: String = ""
    @State private var editNotesText: String = ""

    init(entry: HistoryLogEntry, onUpdate: @escaping () -> Void) {
        self.entry = entry
        self.onUpdate = onUpdate
        self._currentEntry = State(initialValue: entry)
        // Load saved coach insight from the entry
        self._coachInsight = State(initialValue: entry.coachInsight)
        // Load saved workout notes from the entry
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
                        Text(currentEntry.displayDate.dayOfWeekString)
                            .font(.dripDisplay(28))
                            .foregroundStyle(Color.drip.textPrimary)

                        Text(currentEntry.displayDate.fullDateString)
                            .font(.dripBody(14))
                            .foregroundStyle(Color.drip.textSecondary)

                        if isEditing {
                            // Editable mood picker
                            EditableMoodPicker(selectedMood: $editMood)
                                .padding(.top, 4)
                        } else if let mood = currentEntry.mood, !mood.isEmpty {
                            MoodBadge(mood: mood)
                                .padding(.top, 4)
                        }
                    }
                    .padding(.top, 20)

                    // AI Summary
                    if let cleaned = currentEntry.cleanedNotes, !cleaned.isEmpty {
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
                        entry: currentEntry,
                        coachInsight: $coachInsight,
                        isLoading: $isLoadingInsight,
                        onSave: { insight in
                            saveCoachInsight(insight)
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
                    } else if let notes = currentEntry.notes, !notes.isEmpty {
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
                    } else if currentEntry.hasLinkedWorkout {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 6) {
                                Image(systemName: "figure.run.circle.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.drip.energized)
                                Text("LINKED WORKOUT")
                                    .font(.dripCaption(11))
                                    .foregroundStyle(Color.drip.textSecondary)
                                    .tracking(1.2)
                            }

                            HStack(spacing: 0) {
                                if let distance = currentEntry.formattedWorkoutDistance {
                                    WorkoutStatItem(value: distance, label: "Distance")
                                }
                                if let duration = currentEntry.formattedWorkoutDuration {
                                    WorkoutStatItem(value: duration, label: "Duration")
                                }
                                if let pace = currentEntry.formattedWorkoutPace {
                                    WorkoutStatItem(value: pace, label: "Pace")
                                }
                            }

                            // Show when the log was recorded if different from workout date
                            if currentEntry.workoutDate != nil {
                                Text("Logged \(currentEntry.createdAt.shortDateString)")
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

                                if isLinkingWorkout {
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
                        .disabled(isLinkingWorkout)
                        .padding(.horizontal, 20)
                    }

                    if !isEditing {
                    // Workout Notes section
                    WorkoutNotesSection(
                        workoutNotes: $workoutNotesText,
                        isEditing: $isEditingWorkoutNotes,
                        isSaving: $isSavingWorkoutNotes,
                        onSave: saveWorkoutNotes
                    )
                    .padding(.horizontal, 20)

                    // Voice memo indicator
                    if currentEntry.audioUrl != nil {
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
                            if isDeleting {
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
                    .disabled(isDeleting)
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
                deleteEntry()
            }
        } message: {
            Text("This will permanently delete this training log entry. This action cannot be undone.")
        }
        .sheet(isPresented: $showWorkoutPicker) {
            HistoryWorkoutPickerSheet(
                workouts: healthKitManager.recentWorkouts,
                selectedWorkout: $selectedWorkout,
                isPresented: $showWorkoutPicker,
                onSelect: linkWorkout
            )
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

    private func deleteEntry() {
        isDeleting = true

        Task {
            do {
                try await supabase
                    .from("training_logs")
                    .delete()
                    .eq("id", value: entry.id.uuidString)
                    .execute()

                await MainActor.run {
                    onUpdate()
                    dismiss()
                }
            } catch {
                Log.database.error("Failed to delete entry: \(error)")
                await MainActor.run {
                    isDeleting = false
                }
            }
        }
    }

    private func linkWorkout(_ workout: RunningWorkout) {
        isLinkingWorkout = true

        Task {
            do {
                let updateData: [String: AnyJSON] = [
                    "workout_date": .string(ISO8601DateFormatter().string(from: workout.startDate)),
                    "workout_distance_miles": .double(workout.distanceMiles),
                    "workout_duration_minutes": .double(workout.durationMinutes)
                ]

                try await supabase
                    .from("training_logs")
                    .update(updateData)
                    .eq("id", value: entry.id.uuidString)
                    .execute()

                await MainActor.run {
                    // Update the local entry to reflect the change
                    currentEntry = HistoryLogEntry(
                        id: entry.id,
                        createdAt: entry.createdAt,
                        audioUrl: entry.audioUrl,
                        notes: entry.notes,
                        cleanedNotes: entry.cleanedNotes,
                        mood: entry.mood,
                        workoutDate: workout.startDate,
                        workoutDistanceMiles: workout.distanceMiles,
                        workoutDurationMinutes: workout.durationMinutes,
                        coachInsight: coachInsight,
                        workoutNotes: workoutNotesText.isEmpty ? nil : workoutNotesText,
                        workoutType: entry.workoutType,
                        workoutPacePerMile: entry.workoutPacePerMile
                    )
                    isLinkingWorkout = false
                    onUpdate()
                }
            } catch {
                Log.database.error("Failed to link workout: \(error)")
                await MainActor.run {
                    isLinkingWorkout = false
                }
            }
        }
    }

    private func saveCoachInsight(_ insight: String) {
        Task {
            do {
                let updateData: [String: AnyJSON] = [
                    "coach_insight": .string(insight)
                ]

                try await supabase
                    .from("training_logs")
                    .update(updateData)
                    .eq("id", value: entry.id.uuidString)
                    .execute()

                Log.database.info("Coach insight saved to database")
            } catch {
                Log.database.error("Failed to save coach insight: \(error)")
            }
        }
    }

    private func enterEditMode() {
        editMood = currentEntry.mood ?? ""
        editWorkoutType = currentEntry.workoutType ?? ""
        editDistanceText = currentEntry.workoutDistanceMiles.map { String(format: "%.2f", $0) } ?? ""
        editDurationText = currentEntry.workoutDurationMinutes.map { formatMinutesForEdit($0) } ?? ""
        editNotesText = currentEntry.cleanedNotes ?? currentEntry.notes ?? ""
        isEditing = true
    }

    private func formatMinutesForEdit(_ minutes: Double) -> String {
        let totalSeconds = Int(minutes * 60)
        let hrs = totalSeconds / 3600
        let mins = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        if hrs > 0 {
            return String(format: "%d:%02d:%02d", hrs, mins, secs)
        }
        return String(format: "%d:%02d", mins, secs)
    }

    private func parseDurationToMinutes(_ text: String) -> Double? {
        let parts = text.split(separator: ":").compactMap { Double($0) }
        switch parts.count {
        case 3: // h:mm:ss
            return parts[0] * 60 + parts[1] + parts[2] / 60.0
        case 2: // mm:ss
            return parts[0] + parts[1] / 60.0
        case 1: // just minutes
            return parts[0]
        default:
            return nil
        }
    }

    private func saveEdits() async {
        isSavingEdits = true

        var updateData: [String: AnyJSON] = [:]

        // Mood
        let newMood = editMood.isEmpty ? nil : editMood
        if newMood != currentEntry.mood {
            updateData["mood"] = newMood.map { .string($0) } ?? .null
        }

        // Workout type
        let newType = editWorkoutType.isEmpty ? nil : editWorkoutType
        if newType != currentEntry.workoutType {
            updateData["workout_type"] = newType.map { .string($0) } ?? .null
        }

        // Distance
        let newDistance = Double(editDistanceText)
        if newDistance != currentEntry.workoutDistanceMiles {
            updateData["workout_distance_miles"] = newDistance.map { .double($0) } ?? .null
        }

        // Duration
        let newDuration = parseDurationToMinutes(editDurationText)
        if newDuration != currentEntry.workoutDurationMinutes {
            updateData["workout_duration_minutes"] = newDuration.map { .double($0) } ?? .null
        }

        // Notes (update cleaned_notes since that's the primary display)
        let newNotes = editNotesText.isEmpty ? nil : editNotesText
        if newNotes != (currentEntry.cleanedNotes ?? currentEntry.notes) {
            updateData["cleaned_notes"] = newNotes.map { .string($0) } ?? .null
        }

        guard !updateData.isEmpty else {
            await MainActor.run {
                isEditing = false
                isSavingEdits = false
            }
            return
        }

        do {
            try await supabase
                .from("training_logs")
                .update(updateData)
                .eq("id", value: entry.id.uuidString)
                .execute()

            await MainActor.run {
                // Update local entry to reflect changes
                currentEntry = HistoryLogEntry(
                    id: entry.id,
                    createdAt: entry.createdAt,
                    audioUrl: currentEntry.audioUrl,
                    notes: currentEntry.notes,
                    cleanedNotes: editNotesText.isEmpty ? currentEntry.cleanedNotes : editNotesText,
                    mood: editMood.isEmpty ? nil : editMood,
                    workoutDate: currentEntry.workoutDate,
                    workoutDistanceMiles: Double(editDistanceText) ?? currentEntry.workoutDistanceMiles,
                    workoutDurationMinutes: parseDurationToMinutes(editDurationText) ?? currentEntry.workoutDurationMinutes,
                    coachInsight: coachInsight,
                    workoutNotes: workoutNotesText.isEmpty ? nil : workoutNotesText,
                    workoutType: editWorkoutType.isEmpty ? nil : editWorkoutType,
                    workoutPacePerMile: currentEntry.workoutPacePerMile
                )
                isEditing = false
                isSavingEdits = false
                onUpdate()
            }
        } catch {
            Log.database.error("Failed to save edits: \(error)")
            await MainActor.run {
                isSavingEdits = false
            }
        }
    }

    private func saveWorkoutNotes() {
        guard !workoutNotesText.isEmpty else { return }
        isSavingWorkoutNotes = true

        Task {
            do {
                let updateData: [String: AnyJSON] = [
                    "workout_notes": .string(workoutNotesText)
                ]

                try await supabase
                    .from("training_logs")
                    .update(updateData)
                    .eq("id", value: entry.id.uuidString)
                    .execute()

                await MainActor.run {
                    isSavingWorkoutNotes = false
                    isEditingWorkoutNotes = false
                    onUpdate()
                }
                Log.database.info("Workout notes saved to database")
            } catch {
                Log.database.error("Failed to save workout notes: \(error)")
                await MainActor.run {
                    isSavingWorkoutNotes = false
                }
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
    @State private var isAnimating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.drip.cardBackgroundElevated)
                        .frame(width: 80, height: 14)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.drip.cardBackgroundElevated)
                        .frame(width: 100, height: 10)
                }
                Spacer()
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.drip.cardBackgroundElevated)
                    .frame(width: 70, height: 24)
            }

            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.drip.cardBackgroundElevated)
                    .frame(height: 12)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.drip.cardBackgroundElevated)
                    .frame(width: 200, height: 12)
            }
        }
        .padding(16)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .opacity(isAnimating ? 0.5 : 1)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}

// MARK: - EmptyHistoryView

struct EmptyHistoryView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Color.drip.textTertiary)

            VStack(spacing: 4) {
                Text("No logs yet")
                    .font(.dripLabel(16))
                    .foregroundStyle(Color.drip.textSecondary)

                Text("Your training logs will appear here")
                    .font(.dripBody(14))
                    .foregroundStyle(Color.drip.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

// MARK: - CoachInsightSection

struct CoachInsightSection: View {
    let entry: HistoryLogEntry
    @Binding var coachInsight: String?
    @Binding var isLoading: Bool
    var onSave: ((String) -> Void)?
    @State private var hasError = false
    @State private var errorMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "figure.run.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.drip.coral)
                Text("COACH INSIGHT")
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textSecondary)
                    .tracking(1.2)
            }

            if let insight = coachInsight {
                // Check if it's an error message
                if insight.starts(with: "Error:") || insight.starts(with: "Couldn't get") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(insight)
                            .font(.dripBody(14))
                            .foregroundStyle(Color.drip.injured)
                            .lineSpacing(4)

                        Button {
                            coachInsight = nil
                            getCoachInsight()
                        } label: {
                            Text("Try Again")
                                .font(.dripLabel(13))
                                .foregroundStyle(Color.drip.coral)
                        }
                    }
                } else {
                    Text(insight)
                        .font(.dripBody(15))
                        .foregroundStyle(Color.drip.textPrimary)
                        .lineSpacing(4)
                }
            } else if isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(Color.drip.coral)
                        .scaleEffect(0.8)
                    Text("Getting coach feedback...")
                        .font(.dripBody(14))
                        .foregroundStyle(Color.drip.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            } else {
                Button {
                    getCoachInsight()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 14, weight: .medium))
                        Text("Get Coach Feedback")
                            .font(.dripLabel(14))
                    }
                    .foregroundStyle(Color.drip.coral)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.drip.coral.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    coachInsight.map { !$0.starts(with: "Error:") && !$0.starts(with: "Couldn't get") } == true ? Color.drip.coral
                        .opacity(0.3) : Color.drip.divider,
                    lineWidth: 1
                )
        )
        .alert("Coach Error", isPresented: $hasError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private func getCoachInsight() {
        Log.coach.debug("getCoachInsight() called")
        isLoading = true

        // Build structured workout context
        var workoutDetails = ""
        if entry.hasLinkedWorkout {
            var parts: [String] = []
            if let distance = entry.formattedWorkoutDistance {
                parts.append(distance)
            }
            if let duration = entry.formattedWorkoutDuration {
                parts.append(duration)
            }
            if let pace = entry.formattedWorkoutPace {
                parts.append("\(pace)/mi")
            }
            workoutDetails = "Workout: " + parts.joined(separator: " | ")
        }

        var notesContext = ""
        if let cleaned = entry.cleanedNotes, !cleaned.isEmpty {
            notesContext = "Notes: \(cleaned)"
        } else if let notes = entry.notes, !notes.isEmpty {
            notesContext = "Notes: \(notes)"
        }

        var moodContext = ""
        if let mood = entry.mood, !mood.isEmpty {
            moodContext = "Mood: \(mood)"
        }

        // Check if this is a harder effort (tempo, interval, long run, speed work)
        let allNotes = (entry.cleanedNotes ?? "") + (entry.notes ?? "")
        let isHarderEffort = isQualityWorkout(notes: allNotes, distanceMiles: entry.workoutDistanceMiles)

        // Detect specific focus areas from the notes
        let hasRecoveryConcern = allNotes.lowercased().containsAny(["sore", "tight", "pain", "ache", "hurt", "tired", "fatigue", "heavy"])
        let hasMoodData = entry.mood.map { !$0.isEmpty } ?? false

        // Build the focused prompt
        let contextParts = [workoutDetails, notesContext, moodContext].filter { !$0.isEmpty }
        let context = contextParts.joined(separator: "\n")

        // Build dynamic focus suggestions
        var focusHints: [String] = []
        if hasRecoveryConcern {
            focusHints.append("note any recovery/fatigue signals")
        }
        if hasMoodData {
            focusHints.append("connect effort to how they felt")
        }
        if isHarderEffort {
            focusHints.append("training stimulus and adaptation")
        }

        let goalsInstruction = isHarderEffort
            ? "[GOALS] Reflect on how this workout connects to their upcoming goal race. Vary phrasing naturally (e.g., 'This type of effort builds the strength you'll need for...', 'Sessions like this are what prepare you for race day...', 'This is the work that'll pay off when...')."
            : ""

        let message = """
        [COACH INSIGHT REQUEST]

        \(context.isEmpty ? "Training log from \(entry.displayDate.shortDateString)" : context)

        Give thoughtful coaching feedback (4-5 sentences). Be conversational and supportive.
        Observations to consider: \(focusHints.isEmpty ? "effort, execution, pacing" : focusHints.joined(separator: ", "))
        \(goalsInstruction)
        """

        Log.coach.debug("Coach insight request message: \(message)")

        Task {
            await callCoachingAgent(message: message)
        }
    }

    /// Detect if workout is a quality/harder effort based on notes and distance
    private func isQualityWorkout(notes: String, distanceMiles: Double?) -> Bool {
        let lowercased = notes.lowercased()

        // Check for quality workout keywords
        let qualityKeywords = [
            "tempo", "interval", "speed", "fast", "hard",
            "long run", "longrun", "race", "threshold",
            "fartlek", "repeat", "workout", "track",
            "progressive", "negative split", "pr", "pb"
        ]

        if qualityKeywords.contains(where: { lowercased.contains($0) }) {
            return true
        }

        // Long runs (8+ miles) are quality efforts
        if let miles = distanceMiles, miles >= 8.0 {
            return true
        }

        return false
    }

    private func callCoachingAgent(message: String) async {
        Log.coach.debug("callCoachingAgent() starting...")

        guard let url = URL(string: "\(supabaseURL)/functions/v1/coaching-agent") else {
            Log.coach.error("Invalid URL")
            await MainActor.run {
                isLoading = false
                coachInsight = "Error: Invalid URL configuration"
            }
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30 // 30 second timeout

        let payload: [String: Any] = ["message": message]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            Log.coach.debug("Making API request to coaching-agent...")

            let (data, response) = try await URLSession.shared.data(for: request)

            Log.coach.debug("Received response from API")

            if let httpResponse = response as? HTTPURLResponse {
                Log.coach.debug("HTTP status code: \(httpResponse.statusCode)")
                if httpResponse.statusCode != 200 {
                    let errorBody = String(data: data, encoding: .utf8) ?? "No body"
                    Log.coach.error("Response body: \(errorBody)")
                    throw NSError(
                        domain: "CoachError",
                        code: httpResponse.statusCode,
                        userInfo: [NSLocalizedDescriptionKey: "Server error (\(httpResponse.statusCode)): \(errorBody)"]
                    )
                }
            }

            // Log raw response for debugging
            if let rawResponse = String(data: data, encoding: .utf8) {
                Log.coach.debug("Raw API response: \(rawResponse.prefix(500))...")
            }

            struct CoachResponse: Codable {
                let response: String?
                let conversationId: String?
                let sources: [DocumentSource]?
                let error: String?
                let details: String?
                let model: String?
                let provider: String?
                let cached: Bool?
                let remaining: Int?

                struct DocumentSource: Codable {
                    let title: String
                    let category: String
                }
            }

            let coachResponse = try JSONDecoder().decode(CoachResponse.self, from: data)
            Log.coach.info("Successfully decoded response, model: \(coachResponse.model ?? "unknown")")

            await MainActor.run {
                if let error = coachResponse.error {
                    coachInsight = "Error: \(error)"
                    if let details = coachResponse.details {
                        Log.coach.error("Error details: \(details)")
                    }
                } else if let response = coachResponse.response {
                    coachInsight = response
                    // Save to database for persistence
                    onSave?(response)
                } else {
                    coachInsight = "No response received from coach."
                }
                isLoading = false
            }

        } catch let urlError as URLError {
            Log.coach.error("URLError: \(urlError.localizedDescription), code: \(urlError.code.rawValue)")
            await MainActor.run {
                if urlError.code == .timedOut {
                    coachInsight = "Error: Request timed out. Please try again."
                } else if urlError.code == .notConnectedToInternet {
                    coachInsight = "Error: No internet connection."
                } else {
                    coachInsight = "Error: Network error - \(urlError.localizedDescription)"
                }
                isLoading = false
            }
        } catch {
            Log.coach.error("General error: \(error)")
            await MainActor.run {
                coachInsight = "Couldn't get coach feedback: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }
}

// MARK: - WorkoutNotesSection

struct WorkoutNotesSection: View {
    @Binding var workoutNotes: String
    @Binding var isEditing: Bool
    @Binding var isSaving: Bool
    var onSave: () -> Void
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "list.bullet.clipboard.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.drip.coral)
                Text("WORKOUT NOTES")
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textSecondary)
                    .tracking(1.2)

                Spacer()

                if !workoutNotes.isEmpty, !isEditing {
                    Button {
                        isEditing = true
                        isTextFieldFocused = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.drip.textSecondary)
                    }
                }
            }

            if isEditing || workoutNotes.isEmpty {
                // Editing mode
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Add splits, paces, intervals...", text: $workoutNotes, axis: .vertical)
                        .font(.dripBody(14))
                        .foregroundStyle(Color.drip.textPrimary)
                        .lineLimit(1 ... 8)
                        .focused($isTextFieldFocused)
                        .padding(12)
                        .background(Color.drip.cardBackgroundElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    HStack(spacing: 12) {
                        if isEditing, !workoutNotes.isEmpty {
                            Button {
                                isEditing = false
                                isTextFieldFocused = false
                            } label: {
                                Text("Cancel")
                                    .font(.dripLabel(13))
                                    .foregroundStyle(Color.drip.textSecondary)
                            }
                        }

                        Spacer()

                        Button {
                            isTextFieldFocused = false
                            onSave()
                        } label: {
                            HStack(spacing: 6) {
                                if isSaving {
                                    ProgressView()
                                        .tint(.white)
                                        .scaleEffect(0.7)
                                } else {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                Text(isSaving ? "Saving..." : "Save Notes")
                                    .font(.dripLabel(13))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(workoutNotes.isEmpty ? Color.drip.textTertiary : Color.drip.coral)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .disabled(workoutNotes.isEmpty || isSaving)
                    }
                }
            } else {
                // Display mode
                Text(workoutNotes)
                    .font(.dripBody(14))
                    .foregroundStyle(Color.drip.textPrimary)
                    .lineSpacing(4)
            }

            // Helper text
            if workoutNotes.isEmpty, !isEditing {
                Text("Record splits, interval times, pace notes, or any workout details")
                    .font(.dripCaption(12))
                    .foregroundStyle(Color.drip.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(!workoutNotes.isEmpty ? Color.drip.coral.opacity(0.3) : Color.drip.divider, lineWidth: 1)
        )
        .onTapGesture {
            if workoutNotes.isEmpty {
                isEditing = true
                isTextFieldFocused = true
            }
        }
    }
}

// MARK: - EditableMoodPicker

struct EditableMoodPicker: View {
    @Binding var selectedMood: String

    private let moods = ["energized", "positive", "neutral", "tired", "struggling", "injured"]

    private func moodColor(_ mood: String) -> Color {
        switch mood {
        case "energized": return Color.drip.energized
        case "positive": return Color.drip.positive
        case "neutral": return Color.drip.neutral
        case "tired": return Color.drip.tired
        case "struggling": return Color.drip.struggling
        case "injured": return Color.drip.injured
        default: return Color.drip.neutral
        }
    }

    private func moodIcon(_ mood: String) -> String {
        switch mood {
        case "energized": return "bolt.fill"
        case "positive": return "face.smiling.fill"
        case "neutral": return "minus.circle.fill"
        case "tired": return "moon.fill"
        case "struggling": return "exclamationmark.triangle.fill"
        case "injured": return "bandage.fill"
        default: return "circle.fill"
        }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(moods, id: \.self) { mood in
                    Button {
                        selectedMood = selectedMood == mood ? "" : mood
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: moodIcon(mood))
                                .font(.system(size: 10, weight: .bold))
                            Text(mood.capitalized)
                                .font(.dripCaption(11))
                                .fontWeight(.semibold)
                        }
                        .foregroundStyle(selectedMood == mood ? .white : moodColor(mood))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(selectedMood == mood ? moodColor(mood) : moodColor(mood).opacity(0.15))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - EditableWorkoutTypeSection

struct EditableWorkoutTypeSection: View {
    @Binding var selectedType: String

    private let workoutTypes = [
        ("easy", "Easy"),
        ("tempo", "Tempo"),
        ("interval", "Intervals"),
        ("long_run", "Long Run"),
        ("recovery", "Recovery"),
        ("race", "Race"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "figure.run")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.drip.coral)
                Text("WORKOUT TYPE")
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textSecondary)
                    .tracking(1.2)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(workoutTypes, id: \.0) { type, label in
                        Button {
                            selectedType = selectedType == type ? "" : type
                        } label: {
                            Text(label)
                                .font(.dripCaption(12))
                                .fontWeight(.medium)
                                .foregroundStyle(selectedType == type ? .white : Color.drip.coral)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(selectedType == type ? Color.drip.coral : Color.drip.coral.opacity(0.12))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.drip.divider, lineWidth: 1)
        )
    }
}

// MARK: - EditableWorkoutStatsSection

struct EditableWorkoutStatsSection: View {
    @Binding var distanceText: String
    @Binding var durationText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "figure.run.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.drip.energized)
                Text("WORKOUT STATS")
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textSecondary)
                    .tracking(1.2)
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Distance (mi)")
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.textTertiary)
                    TextField("0.00", text: $distanceText)
                        .font(.dripStat(18))
                        .foregroundStyle(Color.drip.textPrimary)
                        .keyboardType(.decimalPad)
                        .padding(10)
                        .background(Color.drip.cardBackgroundElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Duration (m:ss)")
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.textTertiary)
                    TextField("0:00", text: $durationText)
                        .font(.dripStat(18))
                        .foregroundStyle(Color.drip.textPrimary)
                        .keyboardType(.numbersAndPunctuation)
                        .padding(10)
                        .background(Color.drip.cardBackgroundElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .frame(maxWidth: .infinity)
            }

            // Computed pace display
            if let distance = Double(distanceText),
               let duration = parseDurationToMinutes(durationText),
               distance > 0 {
                let totalSecs = Int(((duration / distance) * 60).rounded())
                let paceMinutes = totalSecs / 60
                let paceSeconds = totalSecs % 60
                Text("Pace: \(String(format: "%d:%02d", paceMinutes, paceSeconds)) /mi")
                    .font(.dripCaption(12))
                    .foregroundStyle(Color.drip.textSecondary)
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

    private func parseDurationToMinutes(_ text: String) -> Double? {
        let parts = text.split(separator: ":").compactMap { Double($0) }
        switch parts.count {
        case 3: return parts[0] * 60 + parts[1] + parts[2] / 60.0
        case 2: return parts[0] + parts[1] / 60.0
        case 1: return parts[0]
        default: return nil
        }
    }
}

// MARK: - Date Extensions

extension Date {
    var dayOfWeekString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: self)
    }

    var shortDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: self)
    }

    var fullDateString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }
}

// MARK: - String Extensions

extension String {
    func containsAny(_ substrings: [String]) -> Bool {
        substrings.contains { self.contains($0) }
    }
}

#Preview {
    NavigationStack {
        HistoryView()
    }
}
