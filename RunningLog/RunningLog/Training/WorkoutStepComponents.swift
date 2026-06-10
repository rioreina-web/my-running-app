//
//  WorkoutStepComponents.swift
//  RunningLog
//
//  Workout step editing components used by DayDetailSheet.
//

import SwiftUI
import Foundation

// MARK: - Editable Workout Step Row

struct EditableWorkoutStepRow: View {
    @Binding var step: EditableWorkoutStep
    let equivalentPaces: EquivalentPaces
    let racePaceSeconds: Double
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
                            // Auto-update pace when switching step types
                            if oldType.defaultPace != type.defaultPace {
                                step.paceSelection = .namedPace(type.defaultPace)
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
                racePaceSeconds: racePaceSeconds
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
                    racePaceSeconds: racePaceSeconds
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
                step.recovery = EditableWorkoutStep.EditableRecovery(
                    durationType: .timeSeconds,
                    durationValue: 90,
                    paceSelection: .namedPace(.recovery)
                )
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
                get: { step.recovery ?? EditableWorkoutStep.EditableRecovery(
                    durationType: .timeSeconds,
                    durationValue: 90,
                    paceSelection: .namedPace(.recovery)
                ) },
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
                    racePaceSeconds: racePaceSeconds
                )
            }
            .padding(.leading, 6)
        }
    }
}

// MARK: - Pace Selection Picker

struct PaceSelectionPicker: View {
    @Binding var selection: EditableWorkoutStep.PaceSelection
    let equivalentPaces: EquivalentPaces
    let racePaceSeconds: Double

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

    private var isHRMode: Bool { step.hrTarget != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Mode toggle
            HStack(spacing: 0) {
                modeButton(label: "Pace", isActive: !isHRMode) {
                    step.hrTarget = nil
                    if step.paceSelection == .none {
                        step.paceSelection = .namedPace(.mp)
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
                    racePaceSeconds: racePaceSeconds
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
