import SwiftUI

// MARK: - HistoryView

struct HistoryView: View {
    @State private var viewModel = HistoryViewModel()
    @State private var selectedEntry: TrainingLog?
    @State private var showExport = false
    @State private var showInjuries = false

    var body: some View {
        ZStack {
            DripBackground()

            ScrollView {
                VStack(spacing: 24) {
                    // Stats summary
                    if !viewModel.entries.isEmpty {
                        HistoryStatsHeader(entries: viewModel.entries)
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                    }

                    // Entries list
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeader("Training Logs", action: { Task { await viewModel.fetchEntries() } }, actionIcon: "arrow.clockwise")
                            .padding(.horizontal, 20)

                        if viewModel.isLoading {
                            VStack(spacing: 12) {
                                ForEach(0 ..< 4, id: \.self) { _ in
                                    HistoryEntrySkeleton()
                                }
                            }
                            .padding(.horizontal, 20)
                        } else if let error = viewModel.errorMessage {
                            ErrorStateView(message: error) {
                                await viewModel.fetchEntries()
                            }
                            .padding(.horizontal, 20)
                        } else if viewModel.entries.isEmpty {
                            EmptyHistoryView()
                                .padding(.horizontal, 20)
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(viewModel.entries) { entry in
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
            Task { await viewModel.fetchEntries() }
        }
        .sheet(item: $selectedEntry) { entry in
            HistoryDetailSheet(entry: entry) {
                // Refresh entries after delete or update
                Task { await viewModel.fetchEntries() }
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
    }
}

// MARK: - HistoryStatsHeader

struct HistoryStatsHeader: View {
    let entries: [TrainingLog]

    var thisWeekEntries: [TrainingLog] {
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

// MARK: - Journal Entry Row

struct JournalEntryRow: View {
    let entry: TrainingLog

    private var moodColor: Color {
        switch (entry.mood ?? "").lowercased() {
        case "energized": Color.drip.energized
        case "positive": Color.drip.positive
        case "neutral": Color.drip.neutral
        case "tired": Color.drip.tired
        case "struggling": Color.drip.struggling
        case "injured": Color.drip.injured
        default: Color.drip.neutral
        }
    }

    private var moodLabel: String {
        (entry.mood ?? "neutral").lowercased().capitalized
    }

    private var displayText: String {
        entry.cleanedNotes ?? entry.notes ?? "Voice memo"
    }

    private var timeString: String {
        guard entry.hasLinkedWorkout else { return "Rest Day" }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: entry.displayDate)
    }

    private var workoutTypeLabel: String? {
        guard let type = entry.workoutType else { return nil }
        return type.replacingOccurrences(of: "_", with: " ").capitalized
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left margin: mood accent line
            VStack(spacing: 0) {
                Circle()
                    .fill(moodColor)
                    .frame(width: 6, height: 6)
                    .padding(.top, 8)

                Rectangle()
                    .fill(moodColor.opacity(0.2))
                    .frame(width: 1.5)
            }
            .frame(width: 20)

            // Main content
            VStack(alignment: .leading, spacing: 0) {
                // Date line
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(entry.displayDate.dayOfWeekString)
                        .font(.dripDisplay(22))
                        .foregroundStyle(Color.drip.textPrimary)

                    Text(", \(entry.displayDate.monthString) \(entry.displayDate.dayNumberString)")
                        .font(.dripBody(15))
                        .foregroundStyle(Color.drip.textSecondary)
                        .padding(.leading, 2)

                    Spacer()

                    // Voice memo indicator
                    if entry.audioUrl != nil {
                        Image(systemName: "waveform")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.drip.textTertiary)
                    }
                }

                // Time + mood
                HStack(spacing: 8) {
                    Text(timeString)
                        .font(.dripCaption(12))
                        .foregroundStyle(Color.drip.textTertiary)

                    Text("·")
                        .foregroundStyle(Color.drip.textTertiary)

                    Text(moodLabel)
                        .font(.dripCaption(12))
                        .foregroundStyle(moodColor)

                    if let type = workoutTypeLabel {
                        Text("·")
                            .foregroundStyle(Color.drip.textTertiary)

                        Text(type)
                            .font(.dripCaption(12))
                            .foregroundStyle(Color.drip.coral)
                    }
                }
                .padding(.top, 4)

                // Body text
                Text(displayText)
                    .font(.dripBody(15))
                    .foregroundStyle(Color.drip.textPrimary.opacity(0.85))
                    .lineSpacing(6)
                    .padding(.top, 12)
                    .padding(.bottom, 2)

                // Workout stats (single line, understated)
                if entry.formattedWorkoutDistance != nil {
                    Text(statLine)
                        .font(.dripCaption(12))
                        .foregroundStyle(Color.drip.textTertiary)
                        .padding(.top, 10)
                }
            }
        }
        .padding(.vertical, 20)
        .contentShape(Rectangle())
    }

    private var statLine: String {
        var parts: [String] = []
        if let d = entry.formattedWorkoutDistance { parts.append("\(d) mi") }
        if let t = entry.formattedWorkoutDuration { parts.append(t) }
        if let p = entry.formattedWorkoutPace { parts.append("\(p)/mi") }
        return parts.joined(separator: "  ·  ")
    }
}

// MARK: - Journal Month Header

struct JournalMonthHeader: View {
    let month: String
    let year: String

    var body: some View {
        HStack(spacing: 12) {
            thinRule
            VStack(spacing: 2) {
                Text(month.uppercased())
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textSecondary)
                    .tracking(3)
                Text(year)
                    .font(.dripCaption(10))
                    .foregroundStyle(Color.drip.textTertiary)
                    .tracking(1)
            }
            thinRule
        }
        .padding(.vertical, 16)
    }

    private var thinRule: some View {
        Rectangle()
            .fill(Color.drip.divider)
            .frame(height: 0.5)
    }
}

// MARK: - Journal Divider

struct JournalDivider: View {
    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(Color.drip.divider)
                .frame(height: 0.5)
            Circle()
                .fill(Color.drip.divider)
                .frame(width: 3, height: 3)
            Rectangle()
                .fill(Color.drip.divider)
                .frame(height: 0.5)
        }
        .padding(.leading, 20)
    }
}

// MARK: - HistoryEntryCard

struct HistoryEntryCard: View {
    let entry: TrainingLog

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
    let entry: TrainingLog

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

#Preview {
    NavigationStack {
        HistoryView()
    }
}
