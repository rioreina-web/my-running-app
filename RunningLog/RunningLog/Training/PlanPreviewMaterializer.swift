//
//  PlanPreviewMaterializer.swift
//  RunningLog
//
//  Pure-Swift port of the subscribe-to-plan edge function's adaptive
//  materializer, scoped to JUST week 1. Drives the live preview at the
//  bottom of JoinCoachPlanSheet — re-runs on every state change so the
//  athlete sees what their week will look like before they subscribe.
//
//  Mirrors `assignQualityDays`, `rampedMileage`, and the easy-fill
//  distribution from supabase/functions/subscribe-to-plan/index.ts.
//  Both sides MUST stay in sync; if a knob is added there, mirror it
//  here so the preview doesn't lie about what the athlete is signing
//  up for.
//
//  Intentional simplifications relative to the edge fn:
//    - No pre-quality strides cap (preview omits the strides finisher).
//    - No per-day weight redistribution (recovery-after-long etc.); we
//      split easy mileage evenly. Most athletes won't notice the sub-mile
//      delta, and it keeps this file readable.
//    - No quality_session_templates / scheduled_workout side effects —
//      preview is a one-shot read.
//

import Foundation

// MARK: - Output

enum PlanPreviewDayType: String, Equatable {
    case quality
    case easy
    case rest
    case longRun
}

struct PlanPreviewDay: Equatable, Identifiable {
    let dow: Int                // 0 = Mon … 6 = Sun
    let type: PlanPreviewDayType
    let miles: Double           // 0 for rest
    let paceLabel: String?      // nil when goal isn't set or zone has no anchor
    let label: String           // human-readable, e.g. "Tempo · 5 mi"

    var id: Int { dow }
}

// MARK: - Pace ladder

/// Per-zone seconds-per-mile, derived from a goal anchor. Mirrors the
/// server's `derivePaceTableFromGoal` (supabase/functions/_shared/paces.ts)
/// so the preview's numbers match what subscribe-to-plan will write.
struct PaceLadder: Equatable {
    let recovery: Double
    let easy: Double
    let longRun: Double
    let moderate: Double
    let steady: Double
    let mp: Double
    let hm: Double
    let threshold: Double
    let tenK: Double
    let fiveK: Double
    let threeK: Double
    let mile: Double

    func pace(for zone: NamedPace) -> Double {
        switch zone {
        case .recovery:  return recovery
        case .easy:      return easy
        case .longRun:   return longRun
        case .moderate:  return moderate
        case .steady:    return steady
        case .mp:        return mp
        case .hm:        return hm
        case .threshold: return threshold
        case .tenK:      return tenK
        case .fiveK:     return fiveK
        case .threeK:    return threeK
        case .mile:      return mile
        }
    }

    /// Build a ladder from an athlete-declared goal (race distance + total
    /// seconds). Returns nil when the goal can't be resolved (zero time,
    /// unsupported distance) — callers should treat that as "no pace
    /// labels yet" and render an em-dash.
    static func derive(distance: String, goalSeconds: Int) -> PaceLadder? {
        guard goalSeconds > 0 else { return nil }
        let key = canonicalDistanceKey(distance)
        let paces = PaceCalculator.calculateEquivalentPaces(
            fromDistance: key, totalSeconds: goalSeconds)
        guard let mp = paces["marathon"], mp > 0 else { return nil }
        // Single-number anchors per zone, using the canonical "% of MP" framework:
        // X% of MP = MP × (2 - X/100). See PaceModels for the band definitions.
        return PaceLadder(
            recovery:  mp * 1.35,  // 65% MP
            easy:      mp * 1.25,  // 75% MP — midpoint of easy band (70-80%)
            longRun:   mp * 1.25,  // 75% MP — same as easy by convention
            moderate:  mp * 1.15,  // 85% MP — midpoint of moderate band (80-90%)
            steady:    mp * 1.05,  // 95% MP — midpoint of steady band (90-100%)
            mp:        mp,
            hm:        paces["half"]     ?? mp,
            threshold: paces["half"]     ?? mp,   // LT ≈ HM (VDOT convention)
            tenK:      paces["10K"]      ?? mp,
            fiveK:     paces["5K"]       ?? mp,
            threeK:    paces["3K"]       ?? mp,
            mile:      paces["mile"]     ?? mp
        )
    }

    private static func canonicalDistanceKey(_ raw: String) -> String {
        switch raw.lowercased() {
        case "marathon":           return "marathon"
        case "half_marathon":      return "half"
        case "10k":                return "10K"
        case "5k":                 return "5K"
        case "mile", "1mi":        return "mile"
        default:                   return "marathon"
        }
    }
}

// MARK: - Materializer

enum PlanPreviewMaterializer {
    /// Produce the 7-day preview for week 1 of `plan`, applying any
    /// athlete onboarding overrides. Pure function — safe to call on
    /// every state change in JoinCoachPlanSheet.
    static func materializeWeek1(
        plan: PlanTemplate,
        preferences: SubscriptionPreferences?,
        paceLadder: PaceLadder?
    ) -> [PlanPreviewDay] {
        let week1 = plan.weeks.first(where: { $0.weekNumber == 1 }) ?? plan.weeks.first
        guard let week1 else {
            return (0..<7).map {
                PlanPreviewDay(dow: $0, type: .easy, miles: 0, paceLabel: nil, label: "—")
            }
        }

        // 1. Quality workouts from the template (preserves coach order)
        let allQuality = (week1.workouts).filter { isQualityType($0.workoutType) }
        let longRun = allQuality.max(by: { workoutMiles($0) < workoutMiles($1) })
        let templateExplicitRestDows = Set(week1.workouts
            .filter { $0.workoutType == .rest }
            .map { $0.dayOfWeek })

        // 2. Athlete-driven quality placement
        let qualityByDow = assignQualityDays(
            allQuality: allQuality,
            longRun: longRun,
            preferredDows: preferences?.preferredQualityDows,
            longRunDow: preferences?.longRunDow
        )

        // 3. Rest days — athlete preference wins, else template explicit, else none
        let restDows: Set<Int>
        if let pref = preferences?.restDows {
            restDows = Set(pref)
        } else {
            restDows = templateExplicitRestDows
        }

        // 4. Target weekly mileage — apply volume_ramp at week 1
        let coachTarget = coachWeeklyMileage(week: week1)
        let targetMileage: Double
        if let ramp = preferences?.volumeRamp {
            targetMileage = rampedMileage(weekNumber: 1, coachTarget: coachTarget, ramp: ramp)
        } else {
            targetMileage = coachTarget
        }

        // 5. Distribute easy fill across non-quality, non-rest days
        let qualityMiles = qualityByDow.values.reduce(0.0) { $0 + workoutMiles($1) }
        let easyDows: [Int] = (0..<7).filter { dow in
            qualityByDow[dow] == nil && !restDows.contains(dow)
        }
        let easyMilesToDistribute = max(0, targetMileage - qualityMiles)
        let perEasyDay = easyDows.isEmpty ? 0 : easyMilesToDistribute / Double(easyDows.count)

        // 6. Build each day
        var days: [PlanPreviewDay] = []
        days.reserveCapacity(7)
        for dow in 0..<7 {
            if restDows.contains(dow) {
                days.append(PlanPreviewDay(dow: dow, type: .rest, miles: 0,
                                       paceLabel: nil, label: "Rest"))
            } else if let tw = qualityByDow[dow] {
                let isLongRun = tw.id == longRun?.id
                    || tw.workoutType == .longRun
                    || tw.workoutType == .race
                days.append(qualityPreview(
                    dow: dow,
                    tw: tw,
                    isLongRun: isLongRun,
                    paceLadder: paceLadder
                ))
            } else {
                let miles = max(1, (perEasyDay * 2).rounded() / 2)  // round to 0.5
                let paceLabel = paceLadder.map { PaceCalculator.formatPace($0.easy) + "/mi" }
                days.append(PlanPreviewDay(
                    dow: dow,
                    type: .easy,
                    miles: miles,
                    paceLabel: paceLabel,
                    label: "Easy · \(formatMiles(miles)) mi"
                ))
            }
        }
        return days
    }

    /// Total scheduled miles in the preview (used by the footer line).
    static func totalMiles(_ days: [PlanPreviewDay]) -> Double {
        days.reduce(0.0) { $0 + $1.miles }
    }
}

// MARK: - Internals

private func isQualityType(_ type: ScheduledWorkoutType?) -> Bool {
    switch type {
    case .tempo, .intervals, .longRun, .race, .progression: return true
    default: return false
    }
}

private func workoutMiles(_ tw: PlanTemplateWorkout) -> Double {
    tw.workoutData?.effectiveDistanceMiles ?? 0
}

private func coachWeeklyMileage(week: PlanTemplateWeek) -> Double {
    // PlanTemplateWeek doesn't carry targetMilesMin/Max in the iOS model; the
    // best on-device estimate is the sum of the week's planned distances.
    week.totalPlannedMiles
}

/// Linear ramp from `start_mileage` at week 1 toward the coach target across
/// `ramp_weeks`. After ramp_weeks → coach target as written.
/// `ramp_to_coach_target == false` → flat at start_mileage forever.
/// Mirrors `rampedMileage` in subscribe-to-plan/index.ts.
private func rampedMileage(weekNumber: Int, coachTarget: Double, ramp: VolumeRamp) -> Double {
    if weekNumber > ramp.rampWeeks { return coachTarget }
    if !ramp.rampToCoachTarget { return ramp.startMileage }
    if ramp.rampWeeks <= 1 { return coachTarget }
    let progress = Double(weekNumber - 1) / Double(ramp.rampWeeks - 1)
    return ramp.startMileage + progress * (coachTarget - ramp.startMileage)
}

/// Place coach's quality workouts onto either their template dows (default)
/// or the athlete's preferred quality dows. Long run override forces the
/// largest-by-distance workout onto `longRunDow`. Mirrors
/// `assignQualityDays` in subscribe-to-plan/index.ts.
private func assignQualityDays(
    allQuality: [PlanTemplateWorkout],
    longRun: PlanTemplateWorkout?,
    preferredDows: [Int]?,
    longRunDow: Int?
) -> [Int: PlanTemplateWorkout] {
    var result: [Int: PlanTemplateWorkout] = [:]

    // No athlete override → keep coach's exact placement; apply long_run_dow
    // swap when set.
    guard let preferredDows else {
        for tw in allQuality { result[tw.dayOfWeek] = tw }
        if let longRun, let target = longRunDow, target != longRun.dayOfWeek {
            let occupant = result[target]
            result[longRun.dayOfWeek] = nil
            result[target] = longRun
            if let occupant { result[longRun.dayOfWeek] = occupant }
        }
        return result
    }

    let sortedDows = Array(Set(preferredDows)).sorted()
    let longRunId = longRun?.id
    let others = allQuality.filter { $0.id != longRunId }

    var longRunSlot: Int?
    if let longRun {
        if let target = longRunDow {
            longRunSlot = target
        } else if let last = sortedDows.last {
            longRunSlot = last
        }
        if let slot = longRunSlot { result[slot] = longRun }
    }

    var i = 0
    for dow in sortedDows {
        if dow == longRunSlot { continue }
        if i >= others.count { break }
        result[dow] = others[i]
        i += 1
    }
    return result
}

private func qualityPreview(
    dow: Int,
    tw: PlanTemplateWorkout,
    isLongRun: Bool,
    paceLadder: PaceLadder?
) -> PlanPreviewDay {
    let miles = workoutMiles(tw)
    let mileText = miles > 0 ? "\(formatMiles(miles)) mi" : ""
    let typeName = (tw.workoutType ?? .easy).displayName
    let label: String
    if isLongRun {
        label = mileText.isEmpty ? "Long run" : "Long run · \(mileText)"
    } else {
        label = mileText.isEmpty ? typeName : "\(typeName) · \(mileText)"
    }
    let paceLabel = qualityPaceLabel(tw: tw, isLongRun: isLongRun, paceLadder: paceLadder)
    return PlanPreviewDay(
        dow: dow,
        type: isLongRun ? .longRun : .quality,
        miles: miles,
        paceLabel: paceLabel,
        label: label
    )
}

/// Best-effort pace label for a quality workout. Walks the workout's steps
/// looking for the first active step with a paceZone (the canonical anchor
/// the coach picked). Falls back to:
///   - long run → ladder.longRun
///   - other quality → ladder.threshold (a sane mid-quality default)
private func qualityPaceLabel(
    tw: PlanTemplateWorkout,
    isLongRun: Bool,
    paceLadder: PaceLadder?
) -> String? {
    guard let ladder = paceLadder else { return nil }
    if let zone = primaryActiveZone(tw) {
        return PaceCalculator.formatPace(ladder.pace(for: zone)) + "/mi"
    }
    if isLongRun {
        return PaceCalculator.formatPace(ladder.longRun) + "/mi"
    }
    return PaceCalculator.formatPace(ladder.threshold) + "/mi"
}

private func primaryActiveZone(_ tw: PlanTemplateWorkout) -> NamedPace? {
    guard let workout = tw.workoutData else { return nil }
    if let activeStep = workout.steps.first(where: { $0.stepType == .active && $0.paceZone != nil }) {
        return activeStep.paceZone
    }
    if let anyZoned = workout.steps.first(where: { $0.paceZone != nil }) {
        return anyZoned.paceZone
    }
    return nil
}

private func formatMiles(_ miles: Double) -> String {
    let rounded = (miles * 10).rounded() / 10
    if rounded == rounded.rounded() {
        return String(format: "%.0f", rounded)
    }
    return String(format: "%.1f", rounded)
}
