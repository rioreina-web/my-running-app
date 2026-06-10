//
//  WorkoutDetailView.swift
//  RunningLog
//
//  Detailed view for a generated planned workout with step-by-step display and export.
//

// TODO(adaptive-plan-2.6): ADD a "Coach reconciliation" card to this view.
//   After the workout is logged, fetch the matching workout_reconciliations row
//   (scheduled_workout_id or training_log_id lookup) and render:
//     - target pace | actual pace | delta
//     - weather conditions (temp + dew point + HeatCategory badge)
//     - adjusted target pace (weather-adjusted)
//     - one-line verdict: "Nailed it" | "Faster than target" | "Slower than target"
//       | "Weather-adjusted — you crushed it" (beat adjusted target despite heat)
//   Use existing HeatCategory enum for colors/icons. If no reconciliation exists
//   (unplanned run, backfill still running), render nothing.
//   See: adaptive-plan-loop-prompts.md § Prompt 2.6
import os
import SwiftUI

// MARK: - WorkoutDetailView

struct WorkoutDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let workout: PlannedWorkout
    let racePaceSeconds: Double
    var equivalentPaces: EquivalentPaces?

    @State private var isExporting = false
    @State private var showExportSheet = false
    @State private var exportedFileURL: URL?
    @State private var showExportError = false
    @State private var exportErrorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.drip.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Workout Header
                        WorkoutDetailHeader(
                            workout: workout,
                            racePaceSeconds: racePaceSeconds
                        )
                        .padding(.horizontal, 20)

                        // Workout Steps
                        //
                        // Renders through `groupStepsIntoSections` so a
                        // "10' + 6 × 800m + cooldown" workout reads as 3
                        // sections instead of 14 flat rows. For interval
                        // blocks (`.reps`), the main step appears with a
                        // "× N" badge and the recovery sub-row underneath.
                        // Flat-format old workouts get detected + collapsed
                        // by the helper without needing a migration.
                        let sections = groupStepsIntoSections(workout.steps)
                        VStack(alignment: .leading, spacing: 16) {
                            Text("WORKOUT STEPS")
                                .font(.dripCaption(11))
                                .foregroundStyle(Color.drip.textSecondary)
                                .tracking(1.2)
                                .padding(.horizontal, 20)

                            VStack(spacing: 0) {
                                ForEach(Array(sections.warmup.enumerated()), id: \.element.id) { _, step in
                                    WorkoutStepRow(
                                        step: step,
                                        stepNumber: 0,
                                        totalSteps: 0,
                                        racePaceSeconds: racePaceSeconds,
                                        equivalentPaces: equivalentPaces
                                    )
                                }
                                ForEach(sections.blocks) { block in
                                    GroupedWorkoutBlockRow(
                                        block: block,
                                        racePaceSeconds: racePaceSeconds,
                                        equivalentPaces: equivalentPaces
                                    )
                                }
                                ForEach(Array(sections.cooldown.enumerated()), id: \.element.id) { _, step in
                                    WorkoutStepRow(
                                        step: step,
                                        stepNumber: 0,
                                        totalSteps: 0,
                                        racePaceSeconds: racePaceSeconds,
                                        equivalentPaces: equivalentPaces
                                    )
                                }
                            }
                            .background(Color.drip.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .padding(.horizontal, 20)
                        }

                        // Phase Info
                        PhaseInfoCard(phase: workout.trainingPhase)
                            .padding(.horizontal, 20)

                        // Export Button
                        VStack(spacing: 12) {
                            DripButton(
                                "Export to Garmin",
                                icon: "square.and.arrow.up",
                                style: .primary,
                                isLoading: isExporting
                            ) {
                                exportWorkout()
                            }

                            Text("Downloads as a .FIT file for Garmin Connect")
                                .font(.dripCaption(11))
                                .foregroundStyle(Color.drip.textTertiary)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                        Spacer()
                            .frame(height: 40)
                    }
                    .padding(.top, 20)
                }
            }
            .navigationTitle(workout.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.dripBody(15))
                    .foregroundStyle(Color.drip.coral)
                }
            }
            .toolbarBackground(Color.drip.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(isPresented: $showExportSheet) {
                if let url = exportedFileURL {
                    ShareSheet(items: [url])
                }
            }
            .alert("Export Failed", isPresented: $showExportError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(exportErrorMessage ?? "An error occurred while exporting")
            }
        }
    }

    private func exportWorkout() {
        isExporting = true

        Task {
            do {
                let fitService = FITExportService()
                let url = try await fitService.exportWorkout(workout, racePaceSeconds: racePaceSeconds)

                await MainActor.run {
                    exportedFileURL = url
                    isExporting = false
                    showExportSheet = true
                }
            } catch {
                Log.coach.error("Failed to export workout: \(error)")
                await MainActor.run {
                    isExporting = false
                    exportErrorMessage = error.localizedDescription
                    showExportError = true
                }
            }
        }
    }
}

// MARK: - WorkoutDetailHeader

struct WorkoutDetailHeader: View {
    let workout: PlannedWorkout
    let racePaceSeconds: Double
    /// Kept on the signature for back-compat with older call sites that
    /// still pass a forecast. Heat-adjustment UI moved to
    /// `HeatCalculatorCard` in DayDetailSheet — a unified card that
    /// combines the run-time picker, conditions readout, and per-pace
    /// impact table. The standalone banner that used to render here was
    /// removed because it left the time picker and the pace impact in
    /// two disconnected places.
    var weatherForecast: WorkoutForecast? = nil

    var body: some View {
        VStack(spacing: 16) {
            // Category badge removed — the four-bucket taxonomy
            // (Regeneration / Fundamental / Special / Specific) was too
            // academic and rarely matched how a runner thinks about a
            // workout. The signature badge stays — those labels (Progressive
            // Tempo, Descending Ladder, etc.) describe the workout's actual
            // shape and remain useful when present.
            if let signature = workout.signatureType {
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10))

                        Text(signature.displayName)
                            .font(.dripCaption(10))
                    }
                    .foregroundStyle(Color.drip.coral)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.drip.coral.opacity(0.15))
                    .clipShape(Capsule())

                    Spacer()
                }
            }

            // Description
            Text(workout.description)
                .font(.dripBody(14))
                .foregroundStyle(Color.drip.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Stats
            HStack(spacing: 0) {
                StatColumn(
                    icon: "figure.run",
                    label: "DISTANCE",
                    value: workout.formattedTotalDistance ?? "--"
                )

                Divider()
                    .frame(height: 40)
                    .background(Color.drip.divider)

                StatColumn(
                    icon: "clock",
                    label: "DURATION",
                    value: workout.formattedDuration ?? "--"
                )

                Divider()
                    .frame(height: 40)
                    .background(Color.drip.divider)

                StatColumn(
                    icon: "list.number",
                    label: "STEPS",
                    value: "\(workout.steps.count)"
                )
            }
            .padding(.vertical, 12)
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - StatColumn

struct StatColumn: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Color.drip.coral)

            Text(label)
                .font(.dripCaption(9))
                .foregroundStyle(Color.drip.textTertiary)
                .tracking(0.5)

            Text(value)
                .font(.dripLabel(14))
                .foregroundStyle(Color.drip.textPrimary)
        }
        .frame(maxWidth: .infinity)
    }
}

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

// MARK: - PhaseInfoCard

struct PhaseInfoCard: View {
    let phase: TrainingPhase

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(phase.color.opacity(0.2))
                    .frame(width: 36, height: 36)

                Image(systemName: phase.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(phase.color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Designed for \(phase.displayName)")
                    .font(.dripLabel(13))
                    .foregroundStyle(Color.drip.textPrimary)

                Text(phase.description)
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textSecondary)
            }

            Spacer()
        }
        .padding(14)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(phase.color.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - GroupedWorkoutBlockRow

/// Wraps a `WorkoutStepRow` with a "× N reps" badge and an optional
/// compact recovery sub-row. Renders single-step blocks as just the
/// underlying step. Pure presentation — the grouping itself is decided
/// upstream by `groupStepsIntoSections`.
struct GroupedWorkoutBlockRow: View {
    let block: WorkoutStepBlock
    let racePaceSeconds: Double
    var equivalentPaces: EquivalentPaces?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Reps badge — only on interval blocks. Positioned as a
            // small chip above the step row so the "× 6" is the first
            // thing the eye lands on for an interval workout.
            if case let .reps(count, _) = block.kind {
                HStack(spacing: 8) {
                    Text("× \(count) reps")
                        .font(.dripLabel(12))
                        .foregroundStyle(Color.drip.coral)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.drip.coral.opacity(0.12))
                        .clipShape(Capsule())
                    Spacer()
                }
                .padding(.leading, 56) // align with WorkoutStepRow's content column
                .padding(.bottom, 4)
            }

            WorkoutStepRow(
                step: block.step,
                stepNumber: 0,
                totalSteps: 0,
                racePaceSeconds: racePaceSeconds,
                equivalentPaces: equivalentPaces
            )

            // Recovery sub-row — compact, nested under the rep block
            // with a coral accent rule so it reads as belonging to the
            // set above. Only renders when the block has a recovery
            // (some interval sets are rep-only with no rest between).
            if case let .reps(_, recovery) = block.kind, let rec = recovery {
                HStack(alignment: .top, spacing: 8) {
                    Rectangle()
                        .fill(Color.drip.coral.opacity(0.3))
                        .frame(width: 2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("RECOVERY")
                            .font(.dripCaption(9))
                            .foregroundStyle(Color.drip.textTertiary)
                            .tracking(1.0)
                        HStack(spacing: 6) {
                            Text(formattedRecoveryDuration(rec))
                                .font(.dripStat(13))
                                .foregroundStyle(Color.drip.textPrimary)
                            if let zone = rec.paceZone {
                                Text("@ \(zone.shortName)")
                                    .font(.dripCaption(12))
                                    .foregroundStyle(zone.color)
                            }
                            if let adj = rec.paceAdjustment, adj.value != 0 {
                                Text(adj.displayString)
                                    .font(.dripCaption(11))
                                    .foregroundStyle(Color.drip.textTertiary)
                            }
                        }
                    }
                }
                .padding(.leading, 64)
                .padding(.trailing, 16)
                .padding(.vertical, 8)
            }
        }
    }

    private func formattedRecoveryDuration(_ rec: PlannedWorkoutRecovery) -> String {
        switch rec.durationType {
        case .timeSeconds:
            let secs = Int(rec.durationValue)
            let m = secs / 60
            let s = secs % 60
            if s == 0 { return "\(m) min" }
            return String(format: "%d:%02d", m, s)
        case .distanceMiles:
            return String(format: "%.2f mi", rec.durationValue)
        case .distanceKm:
            return String(format: "%.2f km", rec.durationValue)
        case .distanceMeters:
            return "\(Int(rec.durationValue)) m"
        case .open:
            return "Open"
        }
    }
}

// MARK: - Preview

#Preview {
    WorkoutDetailView(
        workout: PlannedWorkout.sample,
        racePaceSeconds: 480 // 8:00/mi pace
    )
}
