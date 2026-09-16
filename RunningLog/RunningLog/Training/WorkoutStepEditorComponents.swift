//
//  WorkoutStepEditorComponents.swift
//  RunningLog
//
//  Building blocks for WorkoutBuilderSheet: the pace-zone chip row (blue
//  depth ramp), the step card with reorder/duplicate controls, the label
//  grammar that turns steps into canonical workout names ("5K 5×1km",
//  "MP 7 mi"), the builder empty state, and the duplicate-to-day picker.
//
//  Design: Post Run Drip. Eyebrows are monospaced + tracked (the DD22
//  pattern), coral appears at most once per cluster, dividers are
//  hairlines, and empty states are eyebrow + plain-prose nudge + CTA —
//  never an em-dash (hard rule #8).
//

import SwiftUI

// MARK: - Label grammar

/// Workout labels ARE pace-zone labels (2026-05-28 taxonomy decision).
/// "Tempo" and "Threshold" are dead; the zone is the label. This enum turns
/// an edited step list into the same summary grammar the web uses:
///
///   interval sets   → "5K 5×1km", "3K 4×800", "10K 3×1mi"
///   continuous work → "MP 7 mi", "LT 6 mi", "Easy 5 mi"
///   time-based work → "Steady 40 min"
///
enum WorkoutLabelGrammar {

    /// The ten canonical zones, slow → fast, matching PaceSpectrum's stops.
    /// (NamedPace also carries recovery/longRun aliases; the builder's zone
    /// menu shows only the canonical ten.)
    static let canonicalZones: [NamedPace] = [
        .easy, .moderate, .steady, .mp, .hm, .threshold,
        .tenK, .fiveK, .threeK, .mile,
    ]

    /// Canonical grammar name for a zone. Differs from `NamedPace.shortName`
    /// in two places: `.hm` reads "HMP" and `.moderate` reads "Moderate" —
    /// matching the web's label vocabulary exactly.
    // Pure zone → label mapping, no actor state — `nonisolated` so it can be
    // passed to `.map(...)` from any context (the default MainActor isolation
    // otherwise rejects the bare function reference).
    nonisolated static func grammarName(_ zone: NamedPace) -> String {
        switch zone {
        case .recovery: return "Easy"
        case .easy: return "Easy"
        case .longRun: return "Long"
        case .moderate: return "Moderate"
        case .steady: return "Steady"
        case .mp: return "MP"
        case .hm: return "HMP"
        case .threshold: return "LT"
        case .tenK: return "10K"
        case .fiveK: return "5K"
        case .threeK: return "3K"
        case .mile: return "Mile"
        }
    }

    /// Rep-distance label for interval grammar. Meters print bare ("800"),
    /// kilometers with the unit ("1km"), miles with the unit ("1mi"), and
    /// time in minutes ("3min") — mirroring "5K 5×1km" / "3K 4×800".
    static func repLabel(durationType: PlannedWorkoutStep.DurationType, value: Double) -> String {
        switch durationType {
        case .distanceMeters:
            if value >= 1000, value.truncatingRemainder(dividingBy: 1000) == 0 {
                return "\(Int(value / 1000))km"
            }
            return "\(Int(value.rounded()))"
        case .distanceKm:
            return value == value.rounded()
                ? "\(Int(value))km"
                : String(format: "%.1fkm", value)
        case .distanceMiles:
            return value == value.rounded()
                ? "\(Int(value))mi"
                : String(format: "%.1fmi", value)
        case .timeSeconds:
            let total = Int(value.rounded())
            if total % 60 == 0 { return "\(total / 60)min" }
            return "\(total / 60):\(String(format: "%02d", total % 60))"
        case .open:
            return "open"
        }
    }

    /// Live one-line summary for the builder header. Nil when there are no
    /// active steps yet (the empty state owns that moment).
    ///
    /// `equivalentPaces` is what lets a workout built in the fixed basis keep a
    /// real name — the steps carry numbers rather than zones, so the label has
    /// to ask the table which zone each number sits nearest.
    static func summaryLine(
        steps: [EditableWorkoutStep],
        equivalentPaces: EquivalentPaces? = nil
    ) -> String? {
        let actives = steps.filter { $0.stepType == .active }
        guard !actives.isEmpty else { return nil }

        // Interval grammar — a single active block carrying repeats.
        if actives.count == 1, let reps = actives[0].repeats, reps > 1 {
            let zoneLabel = actives[0].paceSelection.labelZone(in: equivalentPaces).map(grammarName) ?? "Workout"
            let rep = repLabel(durationType: actives[0].durationType, value: actives[0].durationValue)
            return "\(zoneLabel) \(reps)×\(rep)"
        }

        // Flat interval grammar — several identical active steps.
        if actives.count > 1 {
            let first = actives[0]
            let firstZone = first.paceSelection.labelZone(in: equivalentPaces)
            let identical = actives.allSatisfy {
                $0.durationType == first.durationType
                    && $0.durationValue == first.durationValue
                    && $0.paceSelection.labelZone(in: equivalentPaces) == firstZone
                    && ($0.repeats ?? 1) == 1
            }
            if identical, (first.repeats ?? 1) == 1 {
                let zoneLabel = firstZone.map(grammarName) ?? "Workout"
                let rep = repLabel(durationType: first.durationType, value: first.durationValue)
                return "\(zoneLabel) \(actives.count)×\(rep)"
            }
        }

        // Continuous grammar — dominant zone + total active volume.
        let zone = dominantZone(in: actives, equivalentPaces: equivalentPaces)
        let zoneLabel = zone.map(grammarName) ?? "Workout"
        let miles = totalMiles(of: actives)
        if miles > 0 {
            let dist = miles == miles.rounded()
                ? String(format: "%.0f", miles)
                : String(format: "%.1f", miles)
            return "\(zoneLabel) \(dist) mi"
        }
        let seconds = actives
            .filter { $0.durationType == .timeSeconds }
            .reduce(0.0) { $0 + $1.durationValue * Double($1.repeats ?? 1) }
        if seconds > 0 {
            return "\(zoneLabel) \(Int((seconds / 60).rounded())) min"
        }
        return zoneLabel
    }

    /// Active zone carrying the most distance — the workout's headline zone.
    static func dominantZone(
        in steps: [EditableWorkoutStep],
        equivalentPaces: EquivalentPaces? = nil
    ) -> NamedPace? {
        var byZone: [NamedPace: Double] = [:]
        for step in steps where step.stepType == .active {
            guard let zone = step.paceSelection.labelZone(in: equivalentPaces) else { continue }
            byZone[zone, default: 0] += max(milesOf(step), 0.01)
        }
        return byZone.max { $0.value < $1.value }?.key
    }

    /// Total distance in miles across the given steps (reps included).
    static func totalMiles(of steps: [EditableWorkoutStep]) -> Double {
        steps.reduce(0.0) { $0 + milesOf($1) }
    }

    private static func milesOf(_ step: EditableWorkoutStep) -> Double {
        let reps = Double(step.repeats ?? 1)
        let single: Double
        switch step.durationType {
        case .distanceMiles: single = step.durationValue
        case .distanceKm: single = step.durationValue / 1.60934
        case .distanceMeters: single = step.durationValue / 1609.34
        case .timeSeconds, .open: single = 0
        }
        var total = single * reps
        if let rec = step.recovery, reps > 1 {
            let recSingle: Double
            switch rec.durationType {
            case .distanceMiles: recSingle = rec.durationValue
            case .distanceKm: recSingle = rec.durationValue / 1.60934
            case .distanceMeters: recSingle = rec.durationValue / 1609.34
            case .timeSeconds, .open: recSingle = 0
            }
            total += recSingle * (reps - 1)
        }
        return total
    }
}

// MARK: - Pace basis row

/// The one control that answers "what do these numbers mean?" — Goal, Current,
/// or Fixed. Sits above the zone rail because it governs it: the zone chips
/// underneath read off whichever table this row selects, and in Fixed they
/// stand down entirely.
///
/// Design: mono eyebrow, three plain chips, one italic-serif line stating the
/// anchor in prose. Coral marks the selection and nothing else in the cluster.
/// When a basis has no data behind it the row says so in a sentence rather than
/// showing a dead chip with an em-dash under it (hard rule #8).
struct BuilderPaceBasisRow: View {
    @Binding var basis: WorkoutPaceBasis
    /// What the currently selected basis is anchored to, in prose.
    let caption: String
    /// Bases with nothing behind them. Tapping one does nothing; `note` says why.
    let unavailable: Set<WorkoutPaceBasis>
    /// One sentence naming what's missing, shown only while something is.
    let unavailableNote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PACE BASIS")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(Color.drip.textSecondary)

            HStack(spacing: 6) {
                ForEach(WorkoutPaceBasis.allCases, id: \.self) { candidate in
                    basisChip(candidate)
                }
                Spacer(minLength: 0)
            }

            Text(caption)
                .font(.system(size: 13, design: .serif).italic())
                .foregroundStyle(Color.drip.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let unavailableNote, !unavailable.isEmpty {
                Text(unavailableNote)
                    .font(.system(size: 12, design: .serif).italic())
                    .foregroundStyle(Color.drip.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func basisChip(_ candidate: WorkoutPaceBasis) -> some View {
        let isSelected = basis == candidate
        let isOff = unavailable.contains(candidate)

        Button {
            guard !isOff else { return }
            basis = candidate
        } label: {
            Text(candidate.displayName)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(chipForeground(isSelected: isSelected, isOff: isOff))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(isSelected ? Color.drip.coral : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.clear : Color.drip.divider, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(isOff)
    }

    private func chipForeground(isSelected: Bool, isOff: Bool) -> Color {
        if isSelected { return .white }
        return isOff ? Color.drip.textTertiary.opacity(0.5) : Color.drip.textPrimary
    }
}

// MARK: - Zone chip row

/// Horizontal menu of the ten canonical pace zones, each chip riding the
/// pace depth ramp (PaceSpectrum via NamedPace.color) with the athlete's
/// resolved pace underneath. Selecting a zone sets the builder's default —
/// new steps land at this zone, and the summary label leans on it.
struct BuilderZoneChipRow: View {
    @Binding var selectedZone: NamedPace
    let equivalentPaces: EquivalentPaces

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ZONE")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(Color.drip.textSecondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(WorkoutLabelGrammar.canonicalZones, id: \.self) { zone in
                        PaceChip(
                            label: WorkoutLabelGrammar.grammarName(zone),
                            pace: equivalentPaces.paceSeconds(for: zone),
                            isSelected: selectedZone == zone,
                            color: zone.color
                        ) {
                            selectedZone = zone
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Step card with reorder / duplicate controls

/// Wraps the shared EditableWorkoutStepRow with a quiet mono control line —
/// Up · Down · Duplicate — so the builder can reorder and clone steps
/// without new chrome. Delete stays inside the step row (its existing
/// affordance).
struct BuilderStepCard: View {
    @Binding var step: EditableWorkoutStep
    let equivalentPaces: EquivalentPaces
    let racePaceSeconds: Double
    let paceBasis: WorkoutPaceBasis
    let isFirst: Bool
    let isLast: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            EditableWorkoutStepRow(
                step: $step,
                equivalentPaces: equivalentPaces,
                racePaceSeconds: racePaceSeconds,
                paceBasis: paceBasis,
                onDelete: onDelete
            )

            HStack(spacing: 0) {
                controlLink("Up", disabled: isFirst, action: onMoveUp)
                middot()
                controlLink("Down", disabled: isLast, action: onMoveDown)
                middot()
                controlLink("Duplicate", disabled: false, action: onDuplicate)
                Spacer(minLength: 0)
            }
            .padding(.leading, 4)
        }
    }

    private func controlLink(_ label: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(disabled ? Color.drip.textTertiary.opacity(0.5) : Color.drip.textSecondary)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func middot() -> some View {
        Text("·")
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(Color.drip.textTertiary)
            .padding(.horizontal, 10)
    }
}

// MARK: - Empty state

/// Eyebrow + plain-prose nudge + CTA. States the absence, says what fills
/// it. Never an em-dash placeholder (hard rule #8).
struct BuilderEmptyState: View {
    let onAddStep: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("STRUCTURE")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(Color.drip.textSecondary)

            Text("No steps yet. Type the workout above, or start with a first step.")
                .font(.system(size: 14, design: .serif).italic())
                .foregroundStyle(Color.drip.textSecondary)

            Button(action: onAddStep) {
                HStack(spacing: 6) {
                    Text("Add a step")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color.drip.coral)
                    Text("\u{2197}")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.drip.coral)
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Quiet inline error

/// Italic annotation + optional mono retry link. Same register as the
/// heat card's quiet error — a sentence, not an alert block.
struct BuilderQuietError: View {
    let message: String
    var actionLabel: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(message)
                .font(.system(size: 13, design: .serif).italic())
                .foregroundStyle(Color.drip.textSecondary)
            if let actionLabel, let action {
                Button(action: action) {
                    Text(actionLabel)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.drip.coral)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Duplicate day picker

/// Compact picker for "Duplicate to another day" — the next three weeks of
/// future days as a plain editorial list. Days that already hold a workout
/// show its label in the trailing slot so the athlete knows they're
/// stacking a double.
struct DuplicateDayPickerSheet: View {
    let sourceWorkout: ScheduledWorkout
    let scheduled: [ScheduledWorkout]
    let onPick: (Date) -> Void
    @Environment(\.dismiss) private var dismiss

    private var candidateDays: [Date] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        return (1...21).compactMap { offset in
            cal.date(byAdding: .day, value: offset, to: start)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.drip.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("DUPLICATE  ·  PICK A DAY")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .tracking(1.4)
                                .foregroundStyle(Color.drip.coral)
                            if let summary = sourceSummary {
                                Text(summary)
                                    .font(.system(size: 14, design: .serif).italic())
                                    .foregroundStyle(Color.drip.textSecondary)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        .padding(.bottom, 16)

                        ForEach(candidateDays, id: \.self) { day in
                            dayRow(day)
                        }
                    }
                }
            }
            .navigationTitle("Duplicate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .font(.dripBody(15))
                        .foregroundStyle(Color.drip.textSecondary)
                }
            }
            .toolbarBackground(Color.drip.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var sourceSummary: String? {
        guard let workout = sourceWorkout.workout else { return nil }
        var line = workout.name
        if let miles = workout.totalDistanceMiles, miles > 0 {
            let dist = miles == miles.rounded()
                ? String(format: "%.0f", miles)
                : String(format: "%.1f", miles)
            line += "  ·  \(dist) mi"
        }
        return line
    }

    @ViewBuilder
    private func dayRow(_ day: Date) -> some View {
        let cal = Calendar.current
        let existing = scheduled.first {
            cal.isDate($0.date, inSameDayAs: day) && !$0.isRestDay
        }

        Button {
            onPick(day)
            dismiss()
        } label: {
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text(weekdayLabel(day))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .tracking(1.0)
                        .foregroundStyle(Color.drip.textSecondary)
                        .frame(width: 44, alignment: .leading)
                    Text(dateLabel(day))
                        .font(.dripBody(15))
                        .foregroundStyle(Color.drip.textPrimary)
                    Spacer()
                    if let existing {
                        Text(existingLabel(existing))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Color.drip.textTertiary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

                Rectangle()
                    .fill(Color.drip.divider)
                    .frame(height: 1)
                    .padding(.leading, 20)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func weekdayLabel(_ day: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f.string(from: day).uppercased()
    }

    private func dateLabel(_ day: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMMM d"
        return f.string(from: day)
    }

    private func existingLabel(_ workout: ScheduledWorkout) -> String {
        if let name = workout.workout?.name, !name.isEmpty {
            return name.uppercased()
        }
        return workout.workoutType.shortName.uppercased()
    }
}
