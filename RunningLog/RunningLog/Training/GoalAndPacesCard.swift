//
//  GoalAndPacesCard.swift
//  RunningLog
//
//  Top-of-Training-tab card that surfaces the athlete's goal time and the
//  full pace ladder derived from it. Tapping the card (or the Edit chip)
//  opens EditGoalSheet.
//
//  Why this exists: every pace in the training plan flows from this number.
//  Until this card existed, the goal-time editor was buried in the toolbar
//  ⋯ menu and only reachable when a plan was already active. Athletes
//  couldn't set a goal before subscribing to a plan, and the AI Workout
//  Builder ended up calling the edge function with `goalTimeSeconds: nil`,
//  which collapsed interval workouts into single Active blocks.
//
//  This card makes the goal a first-class, always-visible artifact. Once
//  set, it propagates through:
//    - subscribe-to-plan (resolveAthletePaces)
//    - AI Workout Builder (Replace flow)
//    - All step-level pace rendering
//

import SwiftUI

struct GoalAndPacesCard: View {
    @Bindable var viewModel: TrainingPlanViewModel
    let onEditTapped: () -> Void

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
            populatedCard(goalSeconds: g, distance: distance)
        } else {
            emptyCard
        }
    }

    // MARK: - Populated state

    private func populatedCard(goalSeconds: Int, distance: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header row — label + goal time + edit chip
            HStack(alignment: .firstTextBaseline) {
                Text("YOUR GOAL")
                    .font(.dripCaption(11))
                    .tracking(1.4)
                    .foregroundStyle(Color.drip.textTertiary)
                Spacer()
                Button(action: onEditTapped) {
                    HStack(spacing: 4) {
                        Image(systemName: "pencil").font(.system(size: 10))
                        Text("Edit").font(.dripCaption(11))
                    }
                    .foregroundStyle(Color.drip.coral)
                }
            }

            // Goal time + race distance
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(formatHms(goalSeconds))
                    .font(.dripDisplay(28))
                    .foregroundStyle(Color.drip.textPrimary)
                Text(formatRaceDistance(distance))
                    .font(.dripBody(15))
                    .foregroundStyle(Color.drip.textSecondary)
            }

            // Race date + countdown (only when an active plan provides one)
            if let countdown = raceCountdownText {
                Text(countdown)
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textTertiary)
            }

            Divider().background(Color.drip.divider)

            // Pace ladder — derived on-device from the goal via PaceCalculator
            paceLadder(goalSeconds: goalSeconds, distance: distance)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Empty state

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Set your goal time")
                .font(.dripDisplay(18))
                .foregroundStyle(Color.drip.textPrimary)
            Text("Your target race anchors every pace in the plan.")
                .font(.dripBody(13))
                .foregroundStyle(Color.drip.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onEditTapped) {
                HStack(spacing: 6) {
                    Text("Set goal time")
                        .font(.dripLabel(14))
                    Image(systemName: "arrow.right").font(.system(size: 12))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.drip.coral)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
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
        VStack(alignment: .leading, spacing: 6) {
            ForEach(rows, id: \.0) { row in
                HStack {
                    Text(row.0)
                        .font(.dripCaption(12))
                        .foregroundStyle(Color.drip.textSecondary)
                        .frame(width: 70, alignment: .leading)
                    Spacer()
                    Text(row.1.map { PaceCalculator.formatPace($0) + "/mi" } ?? "—")
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
