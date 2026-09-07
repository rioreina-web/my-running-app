//
//  GoalAndPacesCard.swift
//  RunningLog
//
//  A sleek, single line — goal time + distance — that drops down and
//  expands into the full pace ladder on tap. Collapsed by default so it
//  reads as a fact, not a card competing with the rest of the tab; the
//  ladder is there when asked for. Tapping "Edit" (only visible once
//  expanded) opens EditGoalSheet.
//
//  Why this exists: every pace in the training plan flows from this number.
//  Until this component existed, the goal-time editor was buried in the
//  toolbar ⋯ menu and only reachable when a plan was already active.
//  Athletes couldn't set a goal before subscribing to a plan, and the AI
//  Workout Builder ended up calling the edge function with
//  `goalTimeSeconds: nil`, which collapsed interval workouts into single
//  Active blocks.
//
//  Once set, the goal propagates through:
//    - subscribe-to-plan (resolveAthletePaces)
//    - AI Workout Builder (Replace flow)
//    - All step-level pace rendering
//

import SwiftUI

struct GoalAndPacesCard: View {
    @Bindable var viewModel: TrainingPlanViewModel
    let onEditTapped: () -> Void

    /// Draw the top and bottom hairlines. On by default (the card as it was
    /// on Train). Trends passes `false` (2026-09-01, Rio: "around goal and
    /// such, make this a much smoother look"): there the line sits inside a
    /// masthead — readout above, segmenter below — and boxing it in two
    /// hairlines made five rules in 300pt. Without them it reads as the last
    /// line of the readout, which is what it is.
    var hairlines: Bool = true

    @State private var expanded = false

    var body: some View {
        // Source-of-truth precedence:
        //   1. Active plan's targetTimeSeconds — what update-plan-goal writes,
        //      and what every pace anchor in the plan derives from.
        //   2. viewModel.marathonGoalTime — legacy UserGoal title-parser
        //      fallback for athletes without an active plan yet.
        // Without (1) the card never repopulated after an Edit Goal save.
        let goalSeconds: Int? = viewModel.activePlan?.targetTimeSeconds
            ?? viewModel.marathonGoalTime
        if let g = goalSeconds, g > 0, let distance = effectiveRaceDistance {
            populatedLine(goalSeconds: g, distance: distance)
        } else {
            emptyLine
        }
    }

    // MARK: - Populated state

    private func populatedLine(goalSeconds: Int, distance: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                    expanded.toggle()
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("YOUR GOAL")
                        .font(.dripCaption(11))
                        .tracking(1.4)
                        .foregroundStyle(Color.drip.textTertiary)
                    Text(formatHms(goalSeconds))
                        .font(.dripDisplay(20))
                        .foregroundStyle(Color.drip.textPrimary)
                    Text(formatRaceDistance(distance))
                        .font(.dripBody(14))
                        .foregroundStyle(Color.drip.textSecondary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.drip.textTertiary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        // Race date + countdown (only when an active plan
                        // provides one)
                        if let countdown = raceCountdownText {
                            Text(countdown)
                                .font(.dripCaption(11))
                                .foregroundStyle(Color.drip.textTertiary)
                        }
                        Spacer()
                        Button(action: onEditTapped) {
                            HStack(spacing: 4) {
                                Image(systemName: "pencil").font(.system(size: 10))
                                Text("Edit").font(.dripCaption(11))
                            }
                            .foregroundStyle(Color.drip.coral)
                        }
                    }

                    Divider().background(Color.drip.divider)

                    // Pace ladder — derived on-device from the goal via PaceCalculator
                    paceLadder(goalSeconds: goalSeconds, distance: distance)
                }
                .padding(.top, 14)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.vertical, hairlines ? 14 : 0)
        .overlay(alignment: .top) { if hairlines { Rectangle().fill(Color.drip.divider).frame(height: 1) } }
        .overlay(alignment: .bottom) { if hairlines { Rectangle().fill(Color.drip.divider).frame(height: 1) } }
    }

    // MARK: - Empty state

    // No ladder to expand into yet, so this stays a single tappable line
    // straight into EditGoalSheet rather than a disclosure with nothing
    // under it.
    private var emptyLine: some View {
        Button(action: onEditTapped) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("YOUR GOAL")
                        .font(.dripCaption(11))
                        .tracking(1.4)
                        .foregroundStyle(Color.drip.textTertiary)
                    Text("Set a goal time to anchor every pace")
                        .font(.dripBody(14))
                        .foregroundStyle(Color.drip.textSecondary)
                }
                Spacer()
                Text("SET →")
                    .font(.dripCaption(11))
                    .tracking(1.2)
                    .foregroundStyle(Color.drip.coral)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, hairlines ? 14 : 0)
        .overlay(alignment: .top) { if hairlines { Rectangle().fill(Color.drip.divider).frame(height: 1) } }
        .overlay(alignment: .bottom) { if hairlines { Rectangle().fill(Color.drip.divider).frame(height: 1) } }
    }

    // MARK: - Pace ladder

    private func paceLadder(goalSeconds: Int, distance: String) -> some View {
        // Compute equivalent paces on-device using the same ratio table that
        // lives in supabase/functions/_shared/paces.ts. Both sides MUST stay
        // in lockstep — see PaceCalculator.swift's performanceRatios.
        let canonicalKey = canonicalDistanceKey(distance)
        let paces = PaceCalculator.calculateEquivalentPaces(
            fromDistance: canonicalKey,
            totalSeconds: goalSeconds
        )

        // Two-column layout. Order is intentional: race distances on the left
        // (mile through marathon), training paces on the right (recovery up
        // through steady). Athletes see "what I'm racing for" and "what I
        // train at" side by side.
        let leftRows: [(String, Double?)] = [
            ("Mile",     paces["mile"]),
            ("5K",       paces["5K"]),
            ("10K",      paces["10K"]),
            ("HM",       paces["half"]),
            ("MP",       paces["marathon"]),
        ]
        // Single-number anchors per zone using the canonical "% of MP" framework
        // (X% MP = MP × (2 - X/100)). Matches PaceModels MP ratios and PaceEngine.
        let rightRows: [(String, Double?)] = [
            ("Recovery", paces["marathon"].map { $0 * 1.35 }),  // 65% MP
            ("Easy",     paces["marathon"].map { $0 * 1.25 }),  // 75% MP
            ("Long",     paces["marathon"].map { $0 * 1.25 }),  // 75% MP
            ("Moderate", paces["marathon"].map { $0 * 1.15 }),  // 85% MP
            ("Steady",   paces["marathon"].map { $0 * 1.05 }),  // 95% MP
        ]

        return HStack(alignment: .top, spacing: 24) {
            paceColumn(rows: leftRows)
            paceColumn(rows: rightRows)
        }
    }

    private func paceColumn(rows: [(String, Double?)]) -> some View {
        // A zone with no derivable pace is omitted, not printed as an
        // em-dash placeholder — missing data renders as absent (hard rule
        // #8; the ios-design-review skill's swiftui-checks.md: "a Text("—")
        // is a bug with a rule number attached").
        let resolved: [(String, Double)] = rows.compactMap { label, pace in
            pace.map { (label, $0) }
        }
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(resolved, id: \.0) { row in
                HStack {
                    Text(row.0)
                        .font(.dripCaption(12))
                        .foregroundStyle(Color.drip.textSecondary)
                        .frame(width: 70, alignment: .leading)
                    Spacer()
                    Text(PaceCalculator.formatPace(row.1) + "/mi")
                        .font(.dripStat(13))
                        .foregroundStyle(Color.drip.textPrimary)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private var effectiveRaceDistance: String? {
        // Prefer the active plan's race distance (athlete-set when subscribing
        // or via Edit Goal). Falls back to "marathon" when nothing is set —
        // most common case for serious runners and matches the existing
        // EditGoalSheet default.
        viewModel.activePlan?.targetRaceDistance ?? "marathon"
    }

    private var raceCountdownText: String? {
        guard let plan = viewModel.activePlan else { return nil }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let race = calendar.startOfDay(for: plan.endDate)
        let weeks = (calendar.dateComponents([.day], from: today, to: race).day ?? 0) / 7
        if weeks <= 0 { return formatRaceDate(plan.endDate) }
        return "\(formatRaceDate(plan.endDate)) · \(weeks) weeks out"
    }

    private func formatRaceDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f.string(from: date)
    }

    /// "9000" → "2:30:00"; "3600" → "1:00:00"; "1800" → "30:00".
    /// Drops the hour digit when goal is under an hour (5K / mile).
    private func formatHms(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 {
            return "\(h):\(String(format: "%02d", m)):\(String(format: "%02d", s))"
        }
        return "\(m):\(String(format: "%02d", s))"
    }

    private func formatRaceDistance(_ raw: String) -> String {
        switch raw.lowercased() {
        case "marathon":            return "marathon"
        case "half_marathon":       return "half marathon"
        case "10k":                 return "10K"
        case "5k":                  return "5K"
        case "mile", "1mi":         return "mile"
        case "ultra":               return "ultra"
        case "general":             return "training block"
        default:                    return raw
        }
    }

    /// Maps stored race distance strings to PaceCalculator's canonical keys.
    /// PaceCalculator uses "marathon", "half", "10K", "5K", "mile" (note
    /// case + the absent "_marathon" suffix). Keep this list aligned with
    /// PaceCalculator.performanceRatios.
    private func canonicalDistanceKey(_ raw: String) -> String {
        switch raw.lowercased() {
        case "marathon":            return "marathon"
        case "half_marathon":       return "half"
        case "10k":                 return "10K"
        case "5k":                  return "5K"
        case "mile", "1mi":         return "mile"
        default:                    return "marathon"
        }
    }
}
