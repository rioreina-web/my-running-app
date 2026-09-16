//
//  WorkoutStepComponents.swift
//  RunningLog
//
//  Workout step editing components used by DayDetailSheet.
//

import SwiftUI
import Foundation
import os

// MARK: - Editable Workout Step Row

struct EditableWorkoutStepRow: View {
    @Binding var step: EditableWorkoutStep
    let equivalentPaces: EquivalentPaces
    let racePaceSeconds: Double
    /// Which basis the surrounding editor is working in. Only the builder sets
    /// it; every other caller stays on the goal table, which is what they were
    /// doing before the switch existed.
    var paceBasis: WorkoutPaceBasis = .goal
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Row 1: Step type + Delete
            HStack {
                Menu {
                    ForEach(PlannedWorkoutStep.StepType.allCases, id: \.self) { type in
                        Button {
                            let oldType = step.stepType
                            step.stepType = type
                            // Auto-update pace when switching step types. In
                            // the fixed basis the default arrives as a number,
                            // not a zone — a fixed workout stays fixed.
                            if oldType.defaultPace != type.defaultPace {
                                let zoned = EditableWorkoutStep.PaceSelection.namedPace(type.defaultPace)
                                step.paceSelection = paceBasis == .fixed
                                    ? zoned.frozen(with: equivalentPaces, racePaceSeconds: racePaceSeconds)
                                    : zoned
                            }
                        } label: {
                            HStack {
                                Text(type.displayName)
                                if step.stepType == type {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(step.stepType.color)
                            .frame(width: 8, height: 8)
                        Text(step.stepType.displayName)
                            .font(.dripLabel(13))
                            .foregroundStyle(step.stepType.color)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.drip.textTertiary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(step.stepType.color.opacity(0.15))
                    .clipShape(Capsule())
                }

                Spacer()

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.drip.injured)
                        .padding(8)
                }
            }

            // Row 2: Duration
            HStack(spacing: 10) {
                if step.durationType == .timeSeconds {
                    TimeIntervalField(totalSeconds: $step.durationValue)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.drip.background)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    TextField("0", value: $step.durationValue, format: .number)
                        .font(.dripStat(16))
                        .foregroundStyle(Color.drip.textPrimary)
                        .keyboardType(.decimalPad)
                        .frame(width: 70)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.drip.background)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                Menu {
                    ForEach(PlannedWorkoutStep.DurationType.allCases, id: \.self) { type in
                        Button {
                            step.durationType = type
                        } label: {
                            HStack {
                                Text(type.displayLabel)
                                if step.durationType == type {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(step.durationType.displayLabel)
                            .font(.dripBody(13))
                            .foregroundStyle(Color.drip.textPrimary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.drip.textTertiary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.drip.background)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                Spacer()
            }

            // Row 3: Target intensity (Pace or Heart Rate)
            TargetIntensityPicker(
                step: $step,
                equivalentPaces: equivalentPaces,
                racePaceSeconds: racePaceSeconds,
                paceBasis: paceBasis
            )

            // Row 4: Interval reps + recovery (active steps only).
            // Shared with WorkoutTemplateEditorView's TemplateStepRow so
            // both surfaces stay in sync with the data model. Before this
            // section existed, opening a "7 × mile" workout in DayDetailSheet
            // displayed it as a single 1-mile step — same regression class
            // as the template editor's, in a different file.
            if step.stepType == .active {
                IntervalRepsSection(
                    step: $step,
                    equivalentPaces: equivalentPaces,
                    racePaceSeconds: racePaceSeconds,
                    paceBasis: paceBasis
                )
            }

            // Row 5: Notes
            TextField("Notes (optional)", text: $step.notes)
                .font(.dripBody(13))
                .foregroundStyle(Color.drip.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.drip.background)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(14)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.drip.coral.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Interval Reps + Recovery (shared)

/// Reps stepper + lazily-materialized recovery sub-row, scoped to one
/// active step. Used by both WorkoutTemplateEditorView's TemplateStepRow
/// and DayDetailSheet's EditableWorkoutStepRow so the two editor surfaces
/// render interval structure identically. Owns the "Make this an interval
/// set" entry affordance, the rep counter, the Remove control, and the
/// recovery editor.
///
/// The step's `repeats` field is the source of truth. When `repeats > 1`
/// the recovery sub-row appears; when `repeats == nil` only the "Make this
/// an interval set" link is shown.
struct IntervalRepsSection: View {
    @Binding var step: EditableWorkoutStep
    let equivalentPaces: EquivalentPaces
    let racePaceSeconds: Double
    var paceBasis: WorkoutPaceBasis = .goal

    /// The default recovery leg, expressed in whatever basis is active — a
    /// fixed workout gets a number here too, not a zone that would keep moving.
    private var defaultRecovery: EditableWorkoutStep.EditableRecovery {
        let jog = EditableWorkoutStep.PaceSelection.namedPace(.recovery)
        return EditableWorkoutStep.EditableRecovery(
            durationType: .timeSeconds,
            durationValue: 90,
            paceSelection: paceBasis == .fixed
                ? jog.frozen(with: equivalentPaces, racePaceSeconds: racePaceSeconds)
                : jog
        )
    }

    var body: some View {
        if let reps = step.repeats, reps > 1 {
            VStack(alignment: .leading, spacing: 8) {
                // Reps counter + remove
                HStack(spacing: 12) {
                    Text("Reps")
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.textTertiary)
                        .tracking(1.0)
                    Stepper("", value: Binding(
                        get: { step.repeats ?? 2 },
                        set: { step.repeats = max(2, $0) }
                    ), in: 2...30)
                    .labelsHidden()
                    Text("× \(reps)")
                        .font(.dripStat(15))
                        .foregroundStyle(Color.drip.coral)
                        .frame(minWidth: 36, alignment: .leading)
                    Spacer()
                    Button {
                        step.repeats = nil
                        step.recovery = nil
                    } label: {
                        Text("Remove")
                            .font(.dripCaption(11))
                            .foregroundStyle(Color.drip.textTertiary)
                    }
                }

                // Recovery sub-row. Lazy-initialized to (90s @ recovery)
                // when reps go above 1 so the coach never sees an empty
                // recovery slot.
                recoveryEditor
            }
            .padding(.top, 4)
            .padding(.leading, 8)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Color.drip.coral.opacity(0.25))
                    .frame(width: 2)
            }
        } else {
            Button {
                step.repeats = 4
                step.recovery = defaultRecovery
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "repeat")
                        .font(.system(size: 11))
                    Text("Make this an interval set")
                        .font(.dripCaption(12))
                }
                .foregroundStyle(Color.drip.textSecondary)
            }
            .padding(.top, 2)
        }
    }

    @ViewBuilder
    private var recoveryEditor: some View {
        if step.recovery != nil {
            let recoveryBinding = Binding<EditableWorkoutStep.EditableRecovery>(
                get: { step.recovery ?? defaultRecovery },
                set: { step.recovery = $0 }
            )

            VStack(alignment: .leading, spacing: 6) {
                Text("RECOVERY")
                    .font(.dripCaption(10))
                    .foregroundStyle(Color.drip.textTertiary)
                    .tracking(1.0)

                HStack(spacing: 8) {
                    if recoveryBinding.wrappedValue.durationType == .timeSeconds {
                        TimeIntervalField(totalSeconds: Binding(
                            get: { recoveryBinding.wrappedValue.durationValue },
                            set: { recoveryBinding.wrappedValue.durationValue = $0 }
                        ))
                    } else {
                        TextField("Value", value: Binding(
                            get: { recoveryBinding.wrappedValue.durationValue },
                            set: { recoveryBinding.wrappedValue.durationValue = $0 }
                        ), format: .number)
                            .font(.dripStat(13))
                            .keyboardType(.decimalPad)
                            .frame(width: 50)
                    }

                    Picker("", selection: Binding(
                        get: { recoveryBinding.wrappedValue.durationType },
                        set: { recoveryBinding.wrappedValue.durationType = $0 }
                    )) {
                        ForEach(PlannedWorkoutStep.DurationType.allCases, id: \.self) { dt in
                            Text(dt.displayLabel).tag(dt)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Color.drip.textSecondary)
                    .font(.dripCaption(12))
                }

                PaceSelectionPicker(
                    selection: Binding(
                        get: { recoveryBinding.wrappedValue.paceSelection },
                        set: { recoveryBinding.wrappedValue.paceSelection = $0 }
                    ),
                    equivalentPaces: equivalentPaces,
                    racePaceSeconds: racePaceSeconds,
                    paceBasis: paceBasis,
                    stepDurationType: recoveryBinding.wrappedValue.durationType,
                    stepDurationValue: recoveryBinding.wrappedValue.durationValue
                )
            }
            .padding(.leading, 6)
        }
    }
}

// MARK: - Fixed pace units

/// How an absolute pace is written down. All three are the same number stored
/// as seconds per mile — this only decides what the athlete types and reads.
///
/// It exists because a pace zone is unit-free ("10k" means the same thing on
/// any rep) and an absolute pace is not. "10 x K @ 10k" flipped to a number is
/// "3:30" to the coach who wrote it and "5:38/mi" to the storage layer, and if
/// the editor only speaks the second one then swapping a zone for a number
/// costs a mental conversion per rep — which is enough friction to make the
/// whole absolute-pace path not worth using.
enum FixedPaceUnit: CaseIterable {
    /// The time for one rep of this step. How track work is written.
    case perRep
    case perKm
    case perMile

    // MARK: Conversion

    /// Seconds per mile → the number shown in this unit.
    func display(fromSecPerMile secPerMile: Double, repMiles: Double?) -> Double {
        switch self {
        case .perMile: return secPerMile
        case .perKm:   return secPerMile / RaceDistanceConstants.kmPerMile
        case .perRep:  return secPerMile * (repMiles ?? 1)
        }
    }

    /// The typed number → seconds per mile.
    func secPerMile(fromDisplay value: Double, repMiles: Double?) -> Double {
        switch self {
        case .perMile: return value
        case .perKm:   return value * RaceDistanceConstants.kmPerMile
        case .perRep:
            guard let repMiles, repMiles > 0 else { return value }
            return value / repMiles
        }
    }

    /// The runnable band, expressed in this unit. Derived from one per-mile
    /// range so the three units can never disagree about what is plausible.
    func plausibleBounds(repMiles: Double?) -> ClosedRange<Double> {
        let low = display(fromSecPerMile: 180, repMiles: repMiles)
        let high = display(fromSecPerMile: 1200, repMiles: repMiles)
        return low...high
    }

    // MARK: Labels

    /// The trailing label beside the field: "per K", "per 800", "/mi".
    func inlineLabel(
        durationType: PlannedWorkoutStep.DurationType?,
        durationValue: Double
    ) -> String {
        switch self {
        case .perMile: return "/mi"
        case .perKm: return "/km"
        case .perRep:
            guard let durationType else { return "per rep" }
            return "per " + WorkoutLabelGrammar.repLabel(
                durationType: durationType, value: durationValue
            )
        }
    }

    func menuLabel(
        durationType: PlannedWorkoutStep.DurationType?,
        durationValue: Double
    ) -> String {
        switch self {
        case .perMile: return "per mile"
        case .perKm: return "per kilometre"
        case .perRep: return "rep time (\(inlineLabel(durationType: durationType, durationValue: durationValue).replacingOccurrences(of: "per ", with: "")))"
        }
    }
}

// MARK: - Pace Selection Picker

struct PaceSelectionPicker: View {
    @Binding var selection: EditableWorkoutStep.PaceSelection
    let equivalentPaces: EquivalentPaces
    let racePaceSeconds: Double
    /// In `.fixed` the zone chips are withheld: a zone would re-derive on the
    /// next goal change or fitness read, which is precisely what the athlete
    /// opted out of by pinning the workout to numbers.
    var paceBasis: WorkoutPaceBasis = .goal
    /// The step's own duration, so a fixed pace can be written in the terms the
    /// rep is written in. Optional because the recovery editor has no rep of
    /// its own to speak in.
    var stepDurationType: PlannedWorkoutStep.DurationType? = nil
    var stepDurationValue: Double = 0

    /// Which unit the fixed field is being typed in. Nil until the athlete
    /// picks one, at which point `defaultFixedUnit` stops applying.
    @State private var fixedUnitOverride: FixedPaceUnit? = nil

    /// One rep in miles, when the step is a distance. Nil for time-based and
    /// open steps, which have no rep to quote a time for.
    private var repMiles: Double? {
        guard let stepDurationType, stepDurationValue > 0 else { return nil }
        switch stepDurationType {
        case .distanceMiles: return stepDurationValue
        case .distanceKm: return stepDurationValue / RaceDistanceConstants.kmPerMile
        case .distanceMeters: return stepDurationValue / RaceDistanceConstants.meterPerMile
        case .timeSeconds, .open: return nil
        }
    }

    /// Metric reps are written as rep times ("K @ 3:30"), mile-based work as a
    /// pace ("4mi @ 6:00"). Start where the coach already is.
    private var defaultFixedUnit: FixedPaceUnit {
        guard let stepDurationType else { return .perMile }
        switch stepDurationType {
        case .distanceMeters, .distanceKm: return repMiles == nil ? .perKm : .perRep
        case .distanceMiles, .timeSeconds, .open: return .perMile
        }
    }

    private var fixedUnit: FixedPaceUnit {
        let unit = fixedUnitOverride ?? defaultFixedUnit
        // A rep time needs a rep. Fall back rather than divide by nothing.
        return (unit == .perRep && repMiles == nil) ? .perMile : unit
    }

    private var isFixedSelection: Bool {
        if case .fixed = selection { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TARGET PACE")
                .font(.dripCaption(10))
                .foregroundStyle(Color.drip.textTertiary)
                .tracking(1.0)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    // None option
                    PaceChip(
                        label: "None",
                        pace: nil,
                        isSelected: selection == .none,
                        color: Color.drip.textTertiary
                    ) {
                        selection = .none
                    }

                    // Named paces (filtered by disabled paces)
                    if paceBasis.isRelative {
                        ForEach(NamedPace.allCases.filter { !equivalentPaces.disabledPaces.contains($0) }, id: \.self) { named in
                            let resolvedPace = selection.resolvedPaceSeconds(equivalentPaces: equivalentPaces, racePaceSeconds: racePaceSeconds)
                            let chipLabel = chipLabelFor(named: named)
                            PaceChip(
                                label: chipLabel,
                                pace: selection.baseNamedPace == named ? resolvedPace : equivalentPaces.paceSeconds(for: named),
                                isSelected: selection.baseNamedPace == named,
                                color: named.color
                            ) {
                                selection = .namedPace(named)
                            }
                        }
                    }

                    // Fixed pace — a number, typed. Always offered: pinning one
                    // step of an otherwise goal-based workout is a normal thing
                    // to want ("the tempo at 6:30, everything else off MP").
                    PaceChip(
                        label: "Fixed",
                        pace: {
                            if case .fixed(let secs) = selection { return secs }
                            return nil
                        }(),
                        isSelected: isFixedSelection,
                        color: Color.drip.textPrimary
                    ) {
                        let seed = selection.resolvedPaceSeconds(
                            equivalentPaces: equivalentPaces,
                            racePaceSeconds: racePaceSeconds
                        ) ?? equivalentPaces.paceSeconds(for: .mp)
                        selection = .fixed(seed.rounded())
                    }

                    // Target time option (for track intervals)
                    PaceChip(
                        label: "Time",
                        pace: nil,
                        isSelected: {
                            if case .targetTime = selection { return true }
                            return false
                        }(),
                        color: Color.drip.energized
                    ) {
                        selection = .targetTime(300) // default 5:00
                    }

                    // Custom option
                    if paceBasis.isRelative {
                        PaceChip(
                            label: "Custom %",
                            pace: nil,
                            isSelected: {
                                if case .custom = selection { return true }
                                return false
                            }(),
                            color: Color.drip.coral
                        ) {
                            selection = .custom(100)
                        }
                    }
                }
            }

            // Fixed pace input, written in the rep's own terms.
            //
            // "10 x K @ 10k" flipped to a number should read "3:30", not
            // "5:38/mi" — a coach writing kilometre reps thinks in rep times,
            // and making them convert in their head is the difference between
            // this switch being usable and being a party trick. All three units
            // store the same `.fixed(secondsPerMile)`.
            if case .fixed(let secs) = selection {
                let unit = fixedUnit
                let miles = repMiles
                HStack(spacing: 8) {
                    FixedPaceField(
                        value: Binding(
                            get: { unit.display(fromSecPerMile: secs, repMiles: miles) },
                            set: { typed in
                                selection = .fixed(
                                    unit.secPerMile(fromDisplay: typed, repMiles: miles)
                                )
                            }
                        ),
                        bounds: unit.plausibleBounds(repMiles: miles)
                    )

                    fixedUnitMenu(current: unit)

                    Spacer(minLength: 0)

                    Text(fixedOrientation(secs, unit: unit))
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.textTertiary)
                        .lineLimit(1)
                }
            }

            // Adjustment control for named pace
            if let basePace = selection.baseNamedPace {
                PaceAdjustmentControl(
                    selection: $selection,
                    basePace: basePace,
                    equivalentPaces: equivalentPaces,
                    racePaceSeconds: racePaceSeconds
                )
            }

            // Custom percentage input
            if case .custom(let pct) = selection {
                HStack(spacing: 8) {
                    TextField("100", value: Binding(
                        get: { pct },
                        set: { selection = .custom($0) }
                    ), format: .number)
                    .font(.dripStat(14))
                    .foregroundStyle(Color.drip.textPrimary)
                    .keyboardType(.decimalPad)
                    .frame(width: 55)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.drip.background)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    Text("% of MP")
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.textSecondary)

                    Spacer()

                    let computedPace = racePaceSeconds / (pct / 100.0)
                    Text(EquivalentPaces.formatPace(computedPace) + "/mi")
                        .font(.dripLabel(13))
                        .foregroundStyle(Color.drip.coral)
                }
            }

            // Target time input (mm:ss)
            if case .targetTime(let secs) = selection {
                HStack(spacing: 8) {
                    TimeIntervalField(totalSeconds: Binding(
                        get: { secs },
                        set: { selection = .targetTime($0) }
                    ))

                    Text("target")
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.textSecondary)
                }
            }
        }
    }

    /// Unit picker for the fixed pace. Same `Menu` idiom the step row already
    /// uses for its duration type, so it reads as part of the same control set.
    @ViewBuilder
    private func fixedUnitMenu(current: FixedPaceUnit) -> some View {
        Menu {
            ForEach(FixedPaceUnit.allCases, id: \.self) { candidate in
                if candidate != .perRep || repMiles != nil {
                    Button {
                        fixedUnitOverride = candidate
                    } label: {
                        HStack {
                            Text(candidate.menuLabel(
                                durationType: stepDurationType,
                                durationValue: stepDurationValue
                            ))
                            if candidate == current { Image(systemName: "checkmark") }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(current.inlineLabel(
                    durationType: stepDurationType,
                    durationValue: stepDurationValue
                ))
                .font(.dripCaption(11))
                .foregroundStyle(Color.drip.textSecondary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8))
                    .foregroundStyle(Color.drip.textTertiary)
            }
        }
    }

    /// M:SS entry for an absolute pace.
    ///
    /// Not `TimeIntervalField`: that one seeds its text once and only ever
    /// pushes text → model, so a value rewritten from outside leaves stale
    /// digits on screen. A fixed pace IS rewritten from outside — changing a
    /// step's type re-freezes it — and a stale number here would misstate what
    /// the save is about to write.
    private struct FixedPaceField: View {
        @Binding var value: Double
        /// What counts as a runnable number in the CURRENT unit. A rep time for
        /// a 4-mile rep is legitimately 24:00, which would fail a per-mile
        /// sanity check, so the caller scales the band to the unit.
        let bounds: ClosedRange<Double>
        @State private var text: String = ""

        var body: some View {
            TextField("6:30", text: $text)
                .font(.dripStat(15))
                .foregroundStyle(Color.drip.textPrimary)
                .keyboardType(.numbersAndPunctuation)
                .frame(width: 62)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.drip.background)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .onAppear { text = Self.format(value) }
                .onChange(of: value) { _, updated in
                    // Only redraw when the change came from elsewhere; matching
                    // on the parsed text keeps mid-typing digits from being
                    // reformatted out from under the cursor.
                    guard Self.parse(text, bounds: bounds) != updated else { return }
                    text = Self.format(updated)
                }
                .onChange(of: text) { _, typed in
                    if let parsed = Self.parse(typed, bounds: bounds) { value = parsed }
                }
        }

        private static func format(_ seconds: Double) -> String {
            let total = Int(seconds.rounded())
            return "\(total / 60):\(String(format: "%02d", total % 60))"
        }

        /// Accepts "6:30" and bare "630". Anything outside `bounds` is refused
        /// rather than written — a half-typed "6:" must not briefly set the
        /// step to six seconds.
        private static func parse(_ raw: String, bounds: ClosedRange<Double>) -> Double? {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            let minutes: Int
            let seconds: Int
            if trimmed.contains(":") {
                let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
                guard parts.count == 2,
                      let m = Int(parts[0]), let sec = Int(parts[1]), parts[1].count == 2
                else { return nil }
                minutes = m
                seconds = sec
            } else {
                guard trimmed.count >= 3, let all = Int(trimmed) else { return nil }
                minutes = all / 100
                seconds = all % 100
            }
            guard seconds < 60 else { return nil }
            let total = Double(minutes * 60 + seconds)
            return bounds.contains(total) ? total : nil
        }
    }

    /// Where the typed number actually sits: its per-mile value when the
    /// athlete is typing in some other unit, and the nearest zone on the active
    /// table. This is the line that answers "is 3:30 a K the same as my 10K
    /// pace?" — which is the whole reason the switch exists.
    ///
    /// "= LT" when it lands on a zone, "LT +6s" when it doesn't. Never claims
    /// the number IS the zone.
    private func fixedOrientation(_ secondsPerMile: Double, unit: FixedPaceUnit) -> String {
        var parts: [String] = []
        if unit != .perMile {
            parts.append(PaceCalculator.formatPace(secondsPerMile) + "/mi")
        }
        if let zone = equivalentPaces.nearestNamedPace(toPaceSeconds: secondsPerMile) {
            let delta = (secondsPerMile - equivalentPaces.paceSeconds(for: zone)).rounded()
            let name = zone.shortName
            if abs(delta) < 1 {
                parts.append("= \(name)")
            } else {
                parts.append(delta > 0 ? "\(name) +\(Int(delta))s" : "\(name) \(Int(delta))s")
            }
        }
        return parts.joined(separator: "  ·  ")
    }

    private func chipLabelFor(named: NamedPace) -> String {
        guard selection.baseNamedPace == named else { return named.shortName }
        switch selection {
        case .namedPaceOffset(_, let sec) where sec != 0:
            return sec > 0 ? "\(named.shortName)+\(formatSecOffset(sec))" : "\(named.shortName)\(formatSecOffset(sec))"
        case .namedPacePercentOffset(_, let pct) where pct != 0:
            return pct > 0 ? "\(named.shortName)+\(Int(pct))%" : "\(named.shortName)\(Int(pct))%"
        default:
            return named.shortName
        }
    }

    private func formatSecOffset(_ sec: Double) -> String {
        let absSec = Int(abs(sec))
        if absSec < 60 { return "\(absSec)s" }
        return "\(absSec / 60):\(String(format: "%02d", absSec % 60))"
    }
}

// MARK: - Pace Adjustment Control

private struct PaceAdjustmentControl: View {
    @Binding var selection: EditableWorkoutStep.PaceSelection
    let basePace: NamedPace
    let equivalentPaces: EquivalentPaces
    let racePaceSeconds: Double

    @State private var inPercentMode: Bool = false

    var body: some View {
        let isPercent = selection.isPercentMode
        let resolvedPace = selection.resolvedPaceSeconds(equivalentPaces: equivalentPaces, racePaceSeconds: racePaceSeconds) ?? equivalentPaces.paceSeconds(for: basePace)

        HStack(spacing: 8) {
            // Mode toggle
            Button {
                toggleMode()
            } label: {
                Text(isPercent ? "%" : "sec")
                    .font(.dripCaption(10))
                    .foregroundStyle(Color.drip.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.drip.background)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }

            Button {
                decrementOffset(isPercent: isPercent)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.drip.textTertiary)
            }

            Text(offsetLabel(isPercent: isPercent))
                .font(.dripStat(12))
                .foregroundStyle(offsetColor(isPercent: isPercent))
                .frame(minWidth: 72)
                .multilineTextAlignment(.center)

            Button {
                incrementOffset(isPercent: isPercent)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.drip.textTertiary)
            }

            Spacer()

            Text(EquivalentPaces.formatPace(resolvedPace))
                .font(.dripLabel(12))
                .foregroundStyle(basePace.color)
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }

    private func offsetLabel(isPercent: Bool) -> String {
        if isPercent {
            let pct = selection.offsetPercent
            if pct == 0 { return "±0%" }
            return pct > 0 ? "+\(String(format: "%.1f", pct))%" : "\(String(format: "%.1f", pct))%"
        } else {
            let sec = selection.offsetSeconds
            if sec == 0 { return "±0s" }
            let absSec = Int(abs(sec))
            let formatted = absSec < 60 ? "\(absSec)s" : "\(absSec / 60):\(String(format: "%02d", absSec % 60))"
            return sec > 0 ? "+\(formatted)" : "-\(formatted)"
        }
    }

    private func offsetColor(isPercent: Bool) -> Color {
        let val = isPercent ? selection.offsetPercent : selection.offsetSeconds
        if val == 0 { return Color.drip.textTertiary }
        return val > 0 ? Color.drip.injured : Color.drip.positive
    }

    private func toggleMode() {
        if selection.isPercentMode {
            // Switch to seconds mode — carry over approximate offset
            let pct = selection.offsetPercent
            let baseSec = equivalentPaces.paceSeconds(for: basePace)
            let approxSec = baseSec * pct / 100.0
            let rounded = (approxSec / 5).rounded() * 5
            selection = rounded == 0 ? .namedPace(basePace) : .namedPaceOffset(basePace, rounded)
        } else {
            // Switch to percent mode
            let sec = selection.offsetSeconds
            let baseSec = equivalentPaces.paceSeconds(for: basePace)
            let approxPct = baseSec > 0 ? (sec / baseSec * 100.0) : 0
            let rounded = (approxPct / 0.5).rounded() * 0.5
            selection = rounded == 0 ? .namedPacePercentOffset(basePace, 0) : .namedPacePercentOffset(basePace, rounded)
        }
    }

    private func decrementOffset(isPercent: Bool) {
        if isPercent {
            let newPct = selection.offsetPercent - 0.5
            selection = newPct == 0 ? .namedPacePercentOffset(basePace, 0) : .namedPacePercentOffset(basePace, newPct)
        } else {
            let newSec = selection.offsetSeconds - 1
            selection = newSec == 0 ? .namedPace(basePace) : .namedPaceOffset(basePace, newSec)
        }
    }

    private func incrementOffset(isPercent: Bool) {
        if isPercent {
            let newPct = selection.offsetPercent + 0.5
            selection = newPct == 0 ? .namedPacePercentOffset(basePace, 0) : .namedPacePercentOffset(basePace, newPct)
        } else {
            let newSec = selection.offsetSeconds + 1
            selection = newSec == 0 ? .namedPace(basePace) : .namedPaceOffset(basePace, newSec)
        }
    }
}

// MARK: - Pace Chip

struct PaceChip: View {
    let label: String
    let pace: Double?
    let isSelected: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(label)
                    .font(.dripLabel(11))
                    .foregroundStyle(isSelected ? .white : color)

                if let pace {
                    let totalSecs = Int(pace.rounded())
                    let mins = totalSecs / 60
                    let secs = totalSecs % 60
                    Text("\(mins):\(String(format: "%02d", secs))")
                        .font(.dripCaption(9))
                        .foregroundStyle(isSelected ? .white.opacity(0.8) : Color.drip.textTertiary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? color : color.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

// MARK: - Target Intensity Picker (Pace OR Heart Rate)

/// Wraps PaceSelectionPicker + HRTargetPicker with a toggle between modes.
struct TargetIntensityPicker: View {
    @Binding var step: EditableWorkoutStep
    let equivalentPaces: EquivalentPaces
    let racePaceSeconds: Double
    var paceBasis: WorkoutPaceBasis = .goal

    private var isHRMode: Bool { step.hrTarget != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Mode toggle
            HStack(spacing: 0) {
                modeButton(label: "Pace", isActive: !isHRMode) {
                    step.hrTarget = nil
                    if step.paceSelection == .none {
                        let mp = EditableWorkoutStep.PaceSelection.namedPace(.mp)
                        step.paceSelection = paceBasis == .fixed
                            ? mp.frozen(with: equivalentPaces, racePaceSeconds: racePaceSeconds)
                            : mp
                    }
                }
                modeButton(label: "Heart Rate", isActive: isHRMode) {
                    step.hrTarget = HRTarget(mode: .zone, zone: 3)
                    step.paceSelection = .none
                }
            }
            .background(Color.drip.background)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.drip.divider, lineWidth: 1))

            if isHRMode {
                HRTargetPicker(hrTarget: Binding(
                    get: { step.hrTarget ?? HRTarget(mode: .zone, zone: 3) },
                    set: { step.hrTarget = $0 }
                ))
            } else {
                PaceSelectionPicker(
                    selection: $step.paceSelection,
                    equivalentPaces: equivalentPaces,
                    racePaceSeconds: racePaceSeconds,
                    paceBasis: paceBasis,
                    stepDurationType: step.durationType,
                    stepDurationValue: step.durationValue
                )
            }
        }
    }

    @ViewBuilder
    private func modeButton(label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.dripCaption(11))
                .foregroundStyle(isActive ? .white : Color.drip.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(isActive ? Color.drip.coral : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .padding(2)
    }
}

// MARK: - HR Target Picker

struct HRTargetPicker: View {
    @Binding var hrTarget: HRTarget
    @AppStorage("userMaxHR") private var maxHR: Int = 180

    private let zoneNames = ["Z1", "Z2", "Z3", "Z4", "Z5"]
    private let zoneLabels = ["Recovery", "Aerobic", "Tempo", "Threshold", "VO2max"]
    private let zonePcts = ["50–60%", "60–70%", "70–80%", "80–90%", "90–100%"]
    private let zoneColors: [Color] = [.blue, .green, .yellow, .orange, .red]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Mode picker: Zone vs BPM
            HStack(spacing: 8) {
                Text("TARGET HR")
                    .font(.dripCaption(10))
                    .foregroundStyle(Color.drip.textTertiary)
                    .tracking(1.0)
                Spacer()
                Button {
                    hrTarget.mode = hrTarget.mode == .zone ? .bpmRange : .zone
                    if hrTarget.mode == .bpmRange && hrTarget.bpmLow == nil {
                        let zones = HRZones(maxHR: maxHR)
                        let range = zones.range(for: hrTarget.zone ?? 3) ?? (0...180)
                        hrTarget.bpmLow = range.lowerBound
                        hrTarget.bpmHigh = range.upperBound
                    }
                } label: {
                    Text(hrTarget.mode == .zone ? "Switch to BPM" : "Switch to Zone")
                        .font(.dripCaption(10))
                        .foregroundStyle(Color.drip.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.drip.background)
                        .clipShape(Capsule())
                }
            }

            if hrTarget.mode == .zone {
                // Zone chips
                HStack(spacing: 6) {
                    ForEach(1...5, id: \.self) { zone in
                        let color = zoneColors[zone - 1]
                        let isSelected = hrTarget.zone == zone
                        let zones = HRZones(maxHR: maxHR)
                        let range = zones.range(for: zone)
                        Button {
                            hrTarget.zone = zone
                        } label: {
                            VStack(spacing: 2) {
                                Text(zoneNames[zone - 1])
                                    .font(.dripLabel(12))
                                    .foregroundStyle(isSelected ? .white : color)
                                Text(zoneLabels[zone - 1])
                                    .font(.dripCaption(9))
                                    .foregroundStyle(isSelected ? .white.opacity(0.85) : Color.drip.textTertiary)
                                if let r = range {
                                    Text("\(r.lowerBound)–\(r.upperBound)")
                                        .font(.dripCaption(9))
                                        .foregroundStyle(isSelected ? .white.opacity(0.7) : Color.drip.textTertiary)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(isSelected ? color : color.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                Text("Based on \(maxHR) bpm max HR · adjust in Settings")
                    .font(.dripCaption(10))
                    .foregroundStyle(Color.drip.textTertiary)
                    .italic()
            } else {
                // Custom BPM range
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("LOW")
                            .font(.dripCaption(9))
                            .foregroundStyle(Color.drip.textTertiary)
                        TextField("140", value: Binding(
                            get: { hrTarget.bpmLow ?? 140 },
                            set: { hrTarget.bpmLow = $0 }
                        ), format: .number)
                        .font(.dripStat(16))
                        .keyboardType(.numberPad)
                        .frame(width: 60)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color.drip.background)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    Text("–")
                        .font(.dripBody(15))
                        .foregroundStyle(Color.drip.textTertiary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("HIGH")
                            .font(.dripCaption(9))
                            .foregroundStyle(Color.drip.textTertiary)
                        TextField("155", value: Binding(
                            get: { hrTarget.bpmHigh ?? 155 },
                            set: { hrTarget.bpmHigh = $0 }
                        ), format: .number)
                        .font(.dripStat(16))
                        .keyboardType(.numberPad)
                        .frame(width: 60)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color.drip.background)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    Text("bpm")
                        .font(.dripBody(14))
                        .foregroundStyle(Color.drip.textSecondary)
                    Spacer()
                }
            }
        }
    }
}

// MARK: - Read-only step display (moved from WorkoutDetailView.swift, 2026-07-03)
// WorkoutStepRow renders a planned workout step in DayDetailSheet;
// WorkoutStepDetailSheet is the tap-through detail it presents.

// MARK: - WorkoutStepRow

struct WorkoutStepRow: View {
    let step: PlannedWorkoutStep
    let stepNumber: Int
    let totalSteps: Int
    let racePaceSeconds: Double
    var equivalentPaces: EquivalentPaces?
    /// Forecast for the day this step's workout is scheduled. When present
    /// and `isMeaningful`, the step shows a weather-adjusted pace alongside
    /// the original target. The original is never overwritten — see
    /// feedback_ai_advises_never_acts.md.
    var weatherForecast: WorkoutForecast?

    @State private var showDetail = false

    var isLast: Bool {
        stepNumber == totalSteps
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Step indicator
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(step.stepType.color.opacity(0.2))
                        .frame(width: 32, height: 32)

                    Image(systemName: stepIcon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(step.stepType.color)
                }

                if !isLast {
                    Rectangle()
                        .fill(Color.drip.divider)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }

            // Step details
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(step.stepType.displayName)
                        .font(.dripLabel(14))
                        .foregroundStyle(step.stepType.color)

                    Spacer()

                    // Duration line — prefix "N × " when this step is an
                    // interval set so the athlete sees "10 × 1 km" instead of
                    // a misleading single "1 km". The compact `repeats` field
                    // is preserved end-to-end (subscribe-to-plan no longer
                    // flattens), so we render the structure the coach wrote.
                    Text(durationDisplay)
                        .font(.dripStat(16))
                        .foregroundStyle(Color.drip.textPrimary)
                }

                // Pace target
                if let intensity = step.targetPaceIntensity {
                    // Pace display — zone-tolerance-based range with short
                    // name inline, effort description on a second line, and
                    // baseline+modifier on a third line when the coach adjusted
                    // off-baseline. Replaces the old decorative chip.
                    //
                    //   6:10–6:26/mi · HM
                    //   1-hour race effort
                    //   your HM 6:18 · +3% today      (only with a modifier)
                    //
                    // Decision captured in the pace-labels design conversation
                    // (2026-04-23). Tolerance table lives on NamedPace.
                    HStack(alignment: .top, spacing: 8) {
                        Text("Target:")
                            .font(.dripCaption(12))
                            .foregroundStyle(Color.drip.textTertiary)
                            .padding(.top, 1)

                        VStack(alignment: .leading, spacing: 2) {
                            let hasRacePace = racePaceSeconds > 0

                            // Prescribed pace (seconds/mile) — the number the
                            // coach wants the athlete to run today. Adjustment,
                            // if any, is already baked in upstream.
                            let prescribedSeconds: Double? = {
                                if let secPerKm = intensity.paceSecondsPerKm {
                                    return secPerKm * 1.609344
                                }
                                if hasRacePace {
                                    let sec = intensity.paceSeconds(forRacePace: racePaceSeconds)
                                    if sec > 180 && sec < 1200 { return sec }
                                }
                                return nil
                            }()

                            // Heat-adjusted pace. When the forecast is present
                            // and meaningful (≥5 sec/mi shift), this becomes
                            // the value the athlete should actually run today —
                            // not a side suggestion. Coach's original number
                            // is shown as the "from coach's X" subtitle below
                            // so it's never lost.
                            let heatAdjustedSeconds: Double? = {
                                guard let prescribed = prescribedSeconds,
                                      let forecast = weatherForecast,
                                      forecast.isMeaningful(referencePaceSecondsPerMile: prescribed)
                                else { return nil }
                                return forecast.adjust(paceSecondsPerMile: prescribed)
                            }()

                            // What the athlete sees as the headline target.
                            // Heat-adjusted when applicable, else coach's value.
                            let effectiveSeconds: Double? = heatAdjustedSeconds ?? prescribedSeconds
                            let isHeatAdjusted: Bool = heatAdjustedSeconds != nil

                            // Zone: prefer coach intent; fall back to nearest
                            // match against the athlete's pace table.
                            let badgePace: NamedPace? = step.paceZone ?? {
                                guard let sec = prescribedSeconds,
                                      let equiv = equivalentPaces else { return nil }
                                return equiv.closestNamedPace(forPaceSeconds: sec)
                            }()

                            // Pace display — range if computable, else single pace.
                            // For slow aerobic zones (easy/longRun/moderate/steady/recovery)
                            // the range is MP-derived and ignores the prescribed
                            // pace entirely; that matches how real coaches
                            // prescribe aerobic work (as a range, not a point).
                            //
                            // When heat-adjusted, every range/single value is
                            // shifted by the same dew-point factor so the displayed
                            // bounds line up with the calculator card's impact table.
                            let heatPct: Double = {
                                guard let prescribed = prescribedSeconds,
                                      let adj = heatAdjustedSeconds,
                                      prescribed > 0 else { return 0 }
                                return (adj - prescribed) / prescribed
                            }()
                            let bumpForHeat: (Double) -> Double = { x in
                                isHeatAdjusted ? x * (1.0 + heatPct) : x
                            }
                            let paceDisplay: String? = {
                                // 1. Coach-provided explicit range (paceSecondsPerKm + High)
                                if let secPerKm = intensity.paceSecondsPerKm,
                                   let secPerKmHigh = intensity.paceSecondsPerKmHigh {
                                    return formatPaceRange(
                                        low: bumpForHeat(secPerKm * 1.609344),
                                        high: bumpForHeat(secPerKmHigh * 1.609344)
                                    )
                                }
                                // 2. Zone-driven range via displayPaceRange.
                                //    Fast zones use ±tolerance around the prescribed pace;
                                //    slow zones use the MP-derived percentage range.
                                if let zone = badgePace,
                                   let r = zone.displayPaceRange(
                                       base: effectiveSeconds,
                                       marathonPace: equivalentPaces.map { bumpForHeat($0.mpPace) }
                                   ) {
                                    return formatPaceRange(low: r.low, high: r.high)
                                }
                                // 3. Race-pace-derived range from percentageHigh
                                //    (legacy path — coach-provided percentage range)
                                if hasRacePace, let hi = intensity.percentageHigh {
                                    let sec = bumpForHeat(intensity.paceSeconds(forRacePace: racePaceSeconds))
                                    let secHi = bumpForHeat(racePaceSeconds / (hi / 100.0))
                                    if sec > 180, secHi > 180, abs(secHi - sec) > 5 {
                                        return formatPaceRange(
                                            low: min(sec, secHi),
                                            high: max(sec, secHi)
                                        )
                                    }
                                }
                                // 4. Single pace, no zone → just the number
                                if let base = effectiveSeconds {
                                    return "\(PaceCalculator.formatPace(base))/mi"
                                }
                                return nil
                            }()

                            // LINE 1 — pace range · zone short name. Heat-
                            // adjusted values render in coral so the athlete
                            // can see at a glance that the displayed target
                            // is shifted from coach's prescription.
                            HStack(spacing: 6) {
                                if let display = paceDisplay {
                                    Text(display)
                                        .font(.dripLabel(13))
                                        .foregroundStyle(isHeatAdjusted ? Color.drip.coral : Color.drip.energized)
                                } else if badgePace == nil {
                                    // Last-resort: no pace AND no zone match.
                                    // Never display a percentage — show em-dash
                                    // and log (per adaptive-plan rules).
                                    Text("—")
                                        .font(.dripLabel(13))
                                        .foregroundStyle(Color.drip.textTertiary)
                                        .onAppear {
                                            Log.paceProfile.error("WorkoutDetailView step missing both paceDisplay and namedPace — no pace to display")
                                        }
                                }
                                if let zone = badgePace {
                                    Text("·")
                                        .font(.dripCaption(12))
                                        .foregroundStyle(Color.drip.textTertiary)
                                    Text(zone.shortName)
                                        .font(.dripLabel(13))
                                        .foregroundStyle(zone.color)
                                }
                            }

                            // LINE 2 — effort description (only when we have a zone)
                            if let zone = badgePace {
                                Text(zone.effortDescription)
                                    .font(.dripCaption(11))
                                    .foregroundStyle(Color.drip.textSecondary)
                            }

                            // LINE 3 — baseline + modifier. Only appears when the
                            // coach adjusted off-baseline (e.g. "+3% for heat").
                            // Closes the gap the old chip silently hid: the
                            // displayed pace intentionally differs from the chart.
                            if let zone = badgePace,
                               let adj = step.paceAdjustment,
                               adj.value != 0,
                               let prescribed = prescribedSeconds {
                                let baseline: Double = {
                                    switch adj.type {
                                    case .percent:
                                        return prescribed / (1.0 + adj.value / 100.0)
                                    case .secondsPerMile:
                                        return prescribed - adj.value
                                    case .secondsPerKm:
                                        return prescribed - (adj.value * 1.609344)
                                    }
                                }()
                                if baseline > 180 && baseline < 1200 {
                                    Text("your \(zone.shortName) \(PaceCalculator.formatPace(baseline)) · \(adj.displayString) today")
                                        .font(.dripCaption(11))
                                        .foregroundStyle(Color.drip.textTertiary)
                                }
                            }
                        }

                        Spacer()
                    }

                    // Heat-adjusted footnote — only when the LINE 1 target
                    // above was actually shifted by heat. Shows the coach's
                    // original pace and the size of the bump so the athlete
                    // knows what changed and why. The displayed target above
                    // is the heat-adjusted value, not a side suggestion.
                    if let forecast = weatherForecast,
                       let secPerKm = step.targetPaceIntensity?.paceSecondsPerKm,
                       forecast.isMeaningful(referencePaceSecondsPerMile: secPerKm * 1.609344) {
                        let prescribed = secPerKm * 1.609344
                        let adjustedSecPerMile = forecast.adjust(paceSecondsPerMile: prescribed)
                        let delta = Int((adjustedSecPerMile - prescribed).rounded())
                        HStack(spacing: 6) {
                            Image(systemName: forecast.conditionIcon)
                                .font(.system(size: 10))
                                .foregroundStyle(Color.drip.coral)
                            Text("Heat-adjusted from coach's \(PaceCalculator.formatPace(prescribed))/mi · +\(delta)s for \(forecast.summaryShort)")
                                .font(.dripCaption(11))
                                .foregroundStyle(Color.drip.textSecondary)
                        }
                    }
                }

                // Recovery sub-row — only shown when this step is an
                // interval set (repeats > 1) AND has between-rep recovery.
                // Renders as a single subtle line under the main pace block:
                //   "↻ After each rep · 90s @ Recovery"
                // Coach-authored structure stays visible without expanding
                // into a long flat list.
                if hasRepeats, let recovery = step.recovery {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.drip.textTertiary)
                        Text("After each rep · \(recoveryDurationText(recovery))")
                            .font(.dripCaption(11))
                            .foregroundStyle(Color.drip.textTertiary)
                        if let zone = recovery.paceZone {
                            Text("·")
                                .font(.dripCaption(11))
                                .foregroundStyle(Color.drip.textTertiary)
                            Text(zone.shortName)
                                .font(.dripCaption(11))
                                .foregroundStyle(zone.color)
                        }
                    }
                }

                // Notes
                if let notes = step.notes {
                    Text(notes)
                        .font(.dripBody(12))
                        .foregroundStyle(Color.drip.textSecondary)
                }
            }
            .padding(.bottom, isLast ? 0 : 20)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, isLast ? 16 : 12)
        .contentShape(Rectangle())
        .onTapGesture { showDetail = true }
        .sheet(isPresented: $showDetail) {
            WorkoutStepDetailSheet(step: step, racePaceSeconds: racePaceSeconds)
        }

        if !isLast {
            Divider()
                .background(Color.drip.divider)
                .padding(.leading, 64)
        }
    }

    // True when this step is an interval set (10 × 1km, 6 × 800m, etc.).
    private var hasRepeats: Bool {
        (step.repeats ?? 1) > 1
    }

    // Duration line for the row header. Prefixes "N × " when this step is
    // an interval set so the structure is visible — e.g., "10 × 1.0 km"
    // instead of just "1.0 km".
    private var durationDisplay: String {
        if hasRepeats, let reps = step.repeats {
            return "\(reps) × \(step.formattedDuration)"
        }
        return step.formattedDuration
    }

    // Format a recovery segment's duration for the sub-row. Mirrors how
    // the main step's `formattedDuration` reads, scoped to recovery.
    private func recoveryDurationText(_ r: PlannedWorkoutRecovery) -> String {
        switch r.durationType {
        case .timeSeconds:
            let total = Int(r.durationValue.rounded())
            if total < 60 { return "\(total)s" }
            let m = total / 60
            let s = total % 60
            return s == 0 ? "\(m) min" : "\(m):\(String(format: "%02d", s))"
        case .distanceMiles:
            return "\(formatRecoveryDistance(r.durationValue)) mi"
        case .distanceKm:
            return "\(formatRecoveryDistance(r.durationValue)) km"
        case .distanceMeters:
            return "\(Int(r.durationValue.rounded())) m"
        case .open:
            return "open"
        }
    }

    private func formatRecoveryDistance(_ value: Double) -> String {
        if abs(value - value.rounded()) < 0.05 {
            return String(Int(value.rounded()))
        }
        return String(format: "%.2g", value)
    }

    private var stepIcon: String {
        switch step.stepType {
        case .warmup: return "sun.max"
        case .active: return "bolt.fill"
        case .rest: return "pause.fill"
        case .recovery: return "wind"
        case .cooldown: return "moon.fill"
        }
    }
}

// MARK: - WorkoutStepDetailSheet

struct WorkoutStepDetailSheet: View {
    let step: PlannedWorkoutStep
    let racePaceSeconds: Double
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    paceSection
                    if step.durationType == .distanceMiles || step.durationType == .distanceKm {
                        targetTimeSection
                        splitsSection
                    }
                    effortSection
                    if let notes = step.notes, !notes.isEmpty {
                        notesSection(notes)
                    }
                }
                .padding(20)
            }
            .navigationTitle(step.stepType.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var header: some View {
        HStack {
            Text(step.formattedDuration)
                .font(.dripStat(28))
                .foregroundStyle(Color.drip.textPrimary)
            Spacer()
        }
    }

    @ViewBuilder
    private var paceSection: some View {
        if let intensity = step.targetPaceIntensity, let paceText = paceDisplay(intensity) {
            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("Target pace")
                Text(paceText)
                    .font(.dripStat(22))
                    .foregroundStyle(Color.drip.energized)
                if let source = paceSourceLabel {
                    Text(source)
                        .font(.dripCaption(12))
                        .foregroundStyle(Color.drip.textSecondary)
                }
            }
        }
    }

    /// Human-readable explanation of where the target pace came from.
    /// Combines the named zone (`Easy`, `HM Pace`) with any coach-authored
    /// adjustment (`+3%`, `-10s/mi`). Returns nil when the step carries a
    /// raw pace with no named reference.
    private var paceSourceLabel: String? {
        let zoneName = step.paceZone?.displayName
        let adjustment = step.paceAdjustment?.displayString
        switch (zoneName, adjustment) {
        case let (name?, adj?): return "Derived from \(name) \(adj)"
        case let (name?, nil):  return "Derived from \(name)"
        default:                return nil
        }
    }

    @ViewBuilder
    private var targetTimeSection: some View {
        if let intensity = step.targetPaceIntensity,
           let targetTime = intensity.formattedTargetTime(
               forDistance: step.durationValue, durationType: step.durationType) {
            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("Target total time")
                Text(targetTime.replacingOccurrences(of: "in ", with: ""))
                    .font(.dripStat(18))
                    .foregroundStyle(Color.drip.textPrimary)
            }
        }
    }

    @ViewBuilder
    private var splitsSection: some View {
        if let intensity = step.targetPaceIntensity, let secPerKm = intensity.paceSecondsPerKm {
            let secPerMile = secPerKm * 1.609344
            let splits = PaceCalculator.calculateSplits(paceSecondsPerMile: secPerMile)
            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("Splits at target pace")
                HStack(spacing: 16) {
                    splitCell("400m", PaceCalculator.formatSplit(splits.fourHundred))
                    splitCell("1K", PaceCalculator.formatSplit(splits.oneK))
                    splitCell("Mile", PaceCalculator.formatSplit(splits.mile))
                }
            }
        }
    }

    private var effortSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Effort")
            Text(effortDescription)
                .font(.dripBody(14))
                .foregroundStyle(Color.drip.textSecondary)
        }
    }

    private func notesSection(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Coach notes")
            Text(notes)
                .font(.dripBody(14))
                .foregroundStyle(Color.drip.textPrimary)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.dripCaption(10))
            .tracking(0.6)
            .foregroundStyle(Color.drip.textTertiary)
    }

    private func splitCell(_ label: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.dripCaption(10))
                .foregroundStyle(Color.drip.textTertiary)
            Text(value)
                .font(.dripStat(16))
                .foregroundStyle(Color.drip.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.drip.divider.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func paceDisplay(_ intensity: PaceIntensity) -> String? {
        if let secPerKm = intensity.paceSecondsPerKm {
            let secPerMile = secPerKm * 1.609344
            let low = PaceCalculator.formatPace(secPerMile)
            if let secPerKmHigh = intensity.paceSecondsPerKmHigh {
                let high = PaceCalculator.formatPace(secPerKmHigh * 1.609344)
                return "\(low)–\(high)/mi"
            }
            return "\(low)/mi"
        }
        if racePaceSeconds > 0 {
            let sec = intensity.paceSeconds(forRacePace: racePaceSeconds)
            if sec > 180 && sec < 1200 {
                return "\(PaceCalculator.formatPace(sec))/mi"
            }
        }
        return nil
    }

    private var effortDescription: String {
        switch step.stepType {
        case .warmup:   return "Loosen up and gradually raise heart rate. Conversational — should feel like you're just starting to open the legs."
        case .active:   return "The focus of the workout. Stay on target; if it feels like too much, back off rather than bail."
        case .recovery: return "Between-reps float. Keep moving, drop the effort — the goal is to return to the next rep ready to hit pace."
        case .rest:     return "Full stop or walk. Let the heart rate settle before the next block."
        case .cooldown: return "Bring the effort down gradually. Easy legs, easy breath — signals to the body that the hard work is done."
        }
    }
}

