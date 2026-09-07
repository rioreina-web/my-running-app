import PostgREST
import Supabase
import SwiftUI

// MARK: - ManualActivity

/// The three kinds of manually-entered workout. `rawValue` is the value sent
/// to the backend; cross_training / strength keep non-runs out of running-
/// fitness math (ACWR / volume / pace), per the training-context rules.
enum ManualActivity: String, CaseIterable, Identifiable {
    case run
    case crossTraining = "cross_training"
    case strength

    var id: String { rawValue }

    var label: String {
        switch self {
        case .run: return "Run"
        case .crossTraining: return "Cross-train"
        case .strength: return "Strength"
        }
    }

    /// Distance only makes sense for runs.
    var showsDistance: Bool { self == .run }
}

// MARK: - ManualWorkoutView

/// Manual workout entry. Two ways in:
///   1. Type a free-text description and tap "Parse with AI" — Gemini fills
///      the fields below, which the athlete then reviews and edits.
///   2. Fill the fields directly.
/// Nothing is saved until the athlete taps Save. Editing an existing manual
/// entry reuses this same screen (pass `existing`).
struct ManualWorkoutView: View {
    @Environment(\.dismiss) private var dismiss

    /// When set, the screen edits this manual entry instead of creating one.
    let existing: TrainingLog?
    /// Called after a successful save/update/delete so the parent can refresh.
    var onChange: (() -> Void)?

    init(existing: TrainingLog? = nil, onChange: (() -> Void)? = nil) {
        self.existing = existing
        self.onChange = onChange
    }

    // Free-text description (also stored as the workout's notes).
    @State private var description: String = ""
    @State private var isParsing = false
    @State private var parseError: String?

    // Structured, editable fields.
    @State private var activity: ManualActivity = .run
    @State private var runType: String = "easy"
    @State private var distanceMiles: String = ""
    @State private var hours: Int = 0
    @State private var minutes: Int = 0
    @State private var seconds: Int = 0
    @State private var workoutDate: Date = .init()
    @State private var selectedMood: String?

    @State private var isSaving = false
    @State private var saveError: String?
    @State private var showSuccess = false
    @State private var showDeleteConfirm = false

    // Canonical mood vocabulary (matches the rest of the product).
    private let moods: [(String, String, Color)] = [
        ("energized", "bolt.fill", Color.drip.energized),
        ("positive", "hand.thumbsup.fill", Color.drip.success),
        ("neutral", "equal", Color.drip.textSecondary),
        ("tired", "zzz", Color.drip.textSecondary),
        ("struggling", "exclamationmark.triangle.fill", Color.drip.injured),
        ("injured", "cross.case.fill", Color.drip.injured)
    ]

    // The options actually shown in the picker. Both the canonical list and the
    // preserve-a-legacy-value rule moved to `WorkoutLabel` on 2026-08-07 — this
    // view had the only correct copy of each, and the journal + receipt pickers
    // each had their own divergent one. See `WorkoutLabel.offered`.
    private var runTypeOptions: [(String, String)] {
        WorkoutLabel.options(including: runType)
    }

    private var isEditing: Bool { existing != nil }

    private var durationMinutes: Double {
        Double(hours * 60) + Double(minutes) + Double(seconds) / 60.0
    }

    private var distanceValue: Double? {
        Double(distanceMiles)
    }

    private var canSave: Bool {
        if !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if let d = distanceValue, d > 0 { return true }
        return durationMinutes > 0
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.drip.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        describeSection
                        activitySection
                        if activity == .run { runTypeSection }
                        if activity.showsDistance { distanceSection }
                        durationSection
                        dateSection
                        moodSection
                        if let saveError { errorBanner(saveError) }
                        saveButton
                        if isEditing { deleteButton }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                }
                .scrollDismissesKeyboard(.interactively)

                if showSuccess {
                    ManualWorkoutSuccessOverlay(isEditing: isEditing)
                        .transition(.opacity.combined(with: .scale))
                }
            }
            .navigationTitle(isEditing ? "Edit Workout" : "Log Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(.dripBody(15))
                        .foregroundStyle(Color.drip.textSecondary)
                }
            }
            .toolbarBackground(Color.drip.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .onAppear(perform: prefillIfEditing)
            .confirmationDialog("Delete this workout?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { Task { await deleteWorkout() } }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    // MARK: - Sections

    private var describeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Describe your workout")

            ZStack(alignment: .topLeading) {
                if description.isEmpty {
                    Text("e.g. \"ran 6 miles easy this morning, legs felt heavy, 52 minutes\"")
                        .font(.dripBody(15))
                        .foregroundStyle(Color.drip.textTertiary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                }
                TextEditor(text: $description)
                    .font(.dripBody(15))
                    .foregroundStyle(Color.drip.textPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            }
            .frame(minHeight: 96)
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.drip.divider, lineWidth: 1))

            DripButton(
                "Parse with AI",
                icon: "sparkles",
                isLoading: isParsing
            ) {
                Task { await parseDescription() }
            }
            .disabled(description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isParsing)
            .opacity(description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)

            if let parseError {
                Text(parseError)
                    .font(.dripCaption(12))
                    .foregroundStyle(Color.drip.struggling)
            } else {
                Text("AI fills in the fields below. Review and edit before saving.")
                    .font(.dripCaption(12))
                    .foregroundStyle(Color.drip.textTertiary)
            }
        }
    }

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Type")
            Picker("Activity", selection: $activity) {
                ForEach(ManualActivity.allCases) { a in
                    Text(a.label).tag(a)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var runTypeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Run type")
            Menu {
                ForEach(runTypeOptions, id: \.0) { value, label in
                    Button(label) { runType = value }
                }
            } label: {
                HStack {
                    Text(runTypeOptions.first { $0.0 == runType }?.1 ?? "Easy")
                        .font(.dripBody(16))
                        .foregroundStyle(Color.drip.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.drip.textSecondary)
                }
                .padding(16)
                .background(Color.drip.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.drip.divider, lineWidth: 1))
            }
        }
    }

    private var distanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Distance")
            HStack(spacing: 12) {
                TextField("0.00", text: $distanceMiles)
                    .font(.dripStat(40))
                    .foregroundStyle(Color.drip.textPrimary)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                Text("miles")
                    .font(.dripBody(18))
                    .foregroundStyle(Color.drip.textSecondary)
            }
            .padding(20)
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.drip.divider, lineWidth: 1))
        }
    }

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Duration")
            HStack(spacing: 8) {
                DurationPicker(value: $hours, label: "hr", range: 0 ... 23)
                Text(":").font(.dripStat(24)).foregroundStyle(Color.drip.textSecondary)
                DurationPicker(value: $minutes, label: "min", range: 0 ... 59)
                Text(":").font(.dripStat(24)).foregroundStyle(Color.drip.textSecondary)
                DurationPicker(value: $seconds, label: "sec", range: 0 ... 59)
            }
            .padding(16)
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.drip.divider, lineWidth: 1))

            // Calculated pace — only meaningful for runs with distance.
            if activity.showsDistance, let distance = distanceValue, distance > 0, durationMinutes > 0 {
                let totalSecs = Int(((durationMinutes / distance) * 60).rounded())
                HStack(spacing: 6) {
                    Image(systemName: "speedometer").font(.system(size: 12))
                    Text("Pace: \(totalSecs / 60):\(String(format: "%02d", totalSecs % 60)) /mi")
                        .font(.dripCaption(13))
                }
                .foregroundStyle(Color.drip.energized)
                .padding(.top, 4)
            }
        }
    }

    private var dateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Date")
            DatePicker("Workout Date", selection: $workoutDate, in: ...Date(), displayedComponents: [.date])
                .datePickerStyle(.graphical)
                .tint(Color.drip.coral)
                .colorScheme(.dark)
                .padding(16)
                .background(Color.drip.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.drip.divider, lineWidth: 1))
        }
    }

    private var moodSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("How did you feel?")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                ForEach(moods, id: \.0) { mood in
                    MoodButton(
                        name: mood.0,
                        icon: mood.1,
                        color: mood.2,
                        isSelected: selectedMood == mood.0
                    ) {
                        withAnimation(.spring(response: 0.3)) {
                            selectedMood = selectedMood == mood.0 ? nil : mood.0
                        }
                    }
                }
            }
        }
    }

    private func errorBanner(_ text: String) -> some View {
        Text(text)
            .font(.dripCaption(13))
            .foregroundStyle(Color.drip.struggling)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var saveButton: some View {
        DripButton(
            isEditing ? "Save Changes" : "Save Workout",
            icon: "checkmark.circle.fill",
            isLoading: isSaving
        ) {
            Task { await saveWorkout() }
        }
        .disabled(!canSave)
        .opacity(canSave ? 1 : 0.5)
        .padding(.top, 8)
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            showDeleteConfirm = true
        } label: {
            Text("Delete Workout")
                .font(.dripBody(15))
                .foregroundStyle(Color.drip.struggling)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
    }

    // MARK: - Backend

    /// The backend payload mirrors the ingest-manual-workout edge function.
    private struct WorkoutReq: Encodable {
        let mode: String
        let text: String?
        let activity: String
        let workout_type: String
        let distance_miles: Double?
        let duration_minutes: Double?
        let mood: String?
        let workout_date: String
        let training_log_id: String?
    }

    private struct WorkoutResp: Decodable {
        let success: Bool?
        let id: String?
        let error: String?
    }

    private struct Draft: Decodable {
        let activity: String?
        let workout_type: String?
        let distance_miles: Double?
        let duration_minutes: Double?
        let pace_per_mile: String?
        let mood: String?
        let cleaned_notes: String?
        let soreness: [String]?
    }

    private struct ParseReq: Encodable {
        let mode: String
        let text: String
    }

    private struct ParseResp: Decodable {
        let success: Bool?
        let draft: Draft?
        let error: String?
    }

    private var workoutTypeForSave: String {
        activity == .run ? runType : activity.rawValue
    }

    private var isoWorkoutDate: String {
        let fmt = ISO8601DateFormatter()
        return fmt.string(from: workoutDate)
    }

    @MainActor
    private func parseDescription() async {
        let text = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isParsing = true
        parseError = nil
        do {
            let resp: ParseResp = try await supabase.functions.invoke(
                "ingest-manual-workout",
                options: .init(body: ParseReq(mode: "parse", text: text))
            )
            if let draft = resp.draft {
                applyDraft(draft)
            } else {
                parseError = resp.error ?? "Couldn't read that. Fill the fields in below."
            }
        } catch {
            parseError = "Couldn't reach the parser. Fill the fields in below."
        }
        isParsing = false
    }

    private func applyDraft(_ d: Draft) {
        if let a = d.activity, let parsed = ManualActivity(rawValue: a) {
            activity = parsed
        }
        if activity == .run, let t = d.workout_type, !t.isEmpty {
            // Preserve whatever was stored (incl. legacy "tempo"); the
            // picker surfaces it via runTypeOptions so it isn't lost.
            runType = t
        }
        if let dist = d.distance_miles, dist > 0 {
            distanceMiles = String(format: dist == dist.rounded() ? "%.0f" : "%.2f", dist)
        }
        if let dur = d.duration_minutes, dur > 0 {
            let total = Int((dur * 60).rounded())
            hours = total / 3600
            minutes = (total % 3600) / 60
            seconds = total % 60
        }
        if let m = d.mood, moods.contains(where: { $0.0 == m }) {
            selectedMood = m
        }
    }

    @MainActor
    private func saveWorkout() async {
        isSaving = true
        saveError = nil
        let text = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let req = WorkoutReq(
            mode: isEditing ? "update" : "save",
            text: text.isEmpty ? nil : text,
            activity: activity.rawValue,
            workout_type: workoutTypeForSave,
            distance_miles: activity.showsDistance ? distanceValue : nil,
            duration_minutes: durationMinutes > 0 ? durationMinutes : nil,
            mood: selectedMood,
            workout_date: isoWorkoutDate,
            training_log_id: existing?.id.uuidString
        )
        do {
            let resp: WorkoutResp = try await supabase.functions.invoke(
                "ingest-manual-workout",
                options: .init(body: req)
            )
            if resp.success == true {
                onChange?()
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { showSuccess = true }
                try? await Task.sleep(for: .seconds(1.6))
                dismiss()
            } else {
                saveError = resp.error ?? "Couldn't save. Try again."
            }
        } catch {
            saveError = "Couldn't save. Check your connection and try again."
        }
        isSaving = false
    }

    @MainActor
    private func deleteWorkout() async {
        guard let id = existing?.id.uuidString else { return }
        isSaving = true
        saveError = nil
        struct DeleteReq: Encodable { let mode: String; let training_log_id: String }
        do {
            let resp: WorkoutResp = try await supabase.functions.invoke(
                "ingest-manual-workout",
                options: .init(body: DeleteReq(mode: "delete", training_log_id: id))
            )
            if resp.success == true {
                onChange?()
                dismiss()
            } else {
                saveError = resp.error ?? "Couldn't delete. Try again."
            }
        } catch {
            saveError = "Couldn't delete. Check your connection and try again."
        }
        isSaving = false
    }

    private func prefillIfEditing() {
        guard let log = existing else { return }
        description = log.notes ?? log.cleanedNotes ?? ""
        if let t = log.workoutType {
            if t == "cross_training" { activity = .crossTraining }
            else if t == "strength" { activity = .strength }
            else { activity = .run; runType = t }   // preserve legacy types (e.g. "tempo")
        }
        if let dist = log.workoutDistanceMiles, dist > 0 {
            distanceMiles = String(format: dist == dist.rounded() ? "%.0f" : "%.2f", dist)
        }
        if let dur = log.workoutDurationMinutes, dur > 0 {
            let total = Int((dur * 60).rounded())
            hours = total / 3600
            minutes = (total % 3600) / 60
            seconds = total % 60
        }
        if let d = log.workoutDate { workoutDate = d }
        if let m = log.mood, moods.contains(where: { $0.0 == m }) { selectedMood = m }
    }
}

// MARK: - DurationPicker

struct DurationPicker: View {
    @Binding var value: Int
    let label: String
    let range: ClosedRange<Int>

    var body: some View {
        VStack(spacing: 4) {
            Picker(label, selection: $value) {
                ForEach(range, id: \.self) { num in
                    Text(String(format: "%02d", num))
                        .foregroundStyle(Color.drip.textPrimary)
                        .tag(num)
                }
            }
            .pickerStyle(.wheel)
            .colorScheme(.dark)
            .frame(width: 60, height: 100)
            .clipped()

            Text(label)
                .font(.dripCaption(11))
                .foregroundStyle(Color.drip.textTertiary)
        }
    }
}

// MARK: - MoodButton

struct MoodButton: View {
    let name: String
    let icon: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(isSelected ? color.opacity(0.2) : Color.drip.cardBackground)
                        .frame(width: 56, height: 56)
                    Image(systemName: icon)
                        .font(.system(size: 22))
                        .foregroundStyle(isSelected ? color : Color.drip.textSecondary)
                }
                .overlay(
                    Circle().stroke(isSelected ? color : Color.drip.divider, lineWidth: isSelected ? 2 : 1)
                )
                Text(name.capitalized)
                    .font(.dripCaption(11))
                    .foregroundStyle(isSelected ? color : Color.drip.textSecondary)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - ManualWorkoutSuccessOverlay

struct ManualWorkoutSuccessOverlay: View {
    var isEditing: Bool = false
    @State private var checkmarkScale: CGFloat = 0

    var body: some View {
        ZStack {
            Color.drip.background.opacity(0.95).ignoresSafeArea()
            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(Color.drip.energized)
                        .frame(width: 100, height: 100)
                        .shadow(color: Color.drip.energized.opacity(0.5), radius: 20, x: 0, y: 10)
                    Image(systemName: "checkmark")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(.black)
                        .scaleEffect(checkmarkScale)
                }
                VStack(spacing: 8) {
                    Text(isEditing ? "Changes Saved!" : "Workout Saved!")
                        .font(.dripDisplay(28))
                        .foregroundStyle(Color.drip.textPrimary)
                    Text(isEditing ? "Your workout has been updated" : "Your workout has been logged")
                        .font(.dripBody(15))
                        .foregroundStyle(Color.drip.textSecondary)
                }
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { checkmarkScale = 1 }
        }
    }
}

#Preview {
    ManualWorkoutView()
}
