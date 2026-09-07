//
//  TipEngine.swift
//  RunningLog · Analysis · Tips
//
//  The detectors. Each one is a pure function over completed training plus the
//  goal, returns a tip or nil, and fires only when its own threshold is met.
//
//  Every threshold below is a training judgement, not a measurement, and each
//  is named as a constant with the reasoning next to it so it can be argued
//  with. None of them are population norms dressed up as facts.
//
//  Reads `TrendsService` (already loaded by Trends and Week) and `user_goals`.
//  Never a plan — see TrainingTip.swift, constraint 1.
//

import Foundation
import SwiftUI
import Supabase

@Observable
final class TipEngine {
    static let shared = TipEngine()
    private init() {}

    private(set) var tips: [TrainingTip] = []
    private(set) var goal: TipGoal?
    private(set) var isLoading = false
    private(set) var loaded = false

    /// How many make it to the surface. Four is the most an athlete will read
    /// and act on; the catalogue is bigger so the list changes as they train.
    static let slots = 4

    @MainActor
    func refresh(force: Bool = false) async {
        if loaded && !force { return }
        if isLoading { return }
        isLoading = true
        defer { isLoading = false }

        let trends = TrendsService.shared
        await trends.refresh(force: force)
        goal = await Self.fetchGoal()

        tips = TipDetectors.all(days: trends.days,
                                weeks: trends.weeks,
                                paceBands: trends.paceBands,
                                goal: goal)
            .sorted { $0.priority > $1.priority }
        loaded = true
    }

    /// From `user_goals` — the athlete's own goal, which exists whether or not
    /// they ever built a plan. `training_plans` is deliberately not consulted.
    private static func fetchGoal() async -> TipGoal? {
        struct Row: Decodable {
            let goal_title: String?
            let target_race_distance: String?
            let target_time_seconds: Int?
            let target_date: String?
        }
        do {
            let rows: [Row] = try await supabase
                .from("user_goals")
                .select("goal_title, target_race_distance, target_time_seconds, target_date")
                .eq("user_id", value: AuthManager.shared.userId)
                .eq("status", value: "active")
                .order("created_at", ascending: false)
                .limit(1)
                .execute()
                .value
            guard let row = rows.first,
                  let distance = row.target_race_distance,
                  let seconds = row.target_time_seconds
            else { return nil }

            let date: Date? = row.target_date.flatMap {
                let f = ISO8601DateFormatter()
                f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                return f.date(from: $0) ?? ISO8601DateFormatter().date(from: $0)
            }
            return TipGoal(raceDistance: distance,
                           targetSeconds: seconds,
                           targetDate: date,
                           title: row.goal_title ?? "")
        } catch {
            return nil
        }
    }
}

// MARK: - Detectors

enum TipDetectors {

    // ---- thresholds, each with its reasoning ----

    /// Below this share of race-pace miles, the race pace is a stranger.
    /// 3% of a 60-mile week is under two miles — a low bar deliberately, so
    /// this only fires when race-pace work is genuinely near-absent.
    static let racePaceShareFloor = 3.0
    /// Outside this, a base block legitimately carries almost no race-pace
    /// work and flagging it would be noise. Inside it, the tip fires — but the
    /// copy changes with how close the race is, because "start introducing it"
    /// and "this is the priority" are different notes and a single threshold
    /// cannot say both. A marathon build runs 12–18 weeks; at the outer edge
    /// the honest advice is to begin, not to panic.
    static let racePaceWindowWeeks = 18
    /// Inside this, race-pace work stops being something to introduce and
    /// starts being the thing the block is for.
    static let racePaceSharpWeeks = 10
    /// Moderate running above this share is the classic grey zone: too hard to
    /// recover from, too easy to drive much adaptation.
    static let moderateShareCeiling = 25.0
    /// A long run this concentrated in one zone had no change of pace in it.
    static let monotonousLongRunShare = 0.80
    /// Above this share of running days being doubles, continuous time on feet
    /// is worth checking.
    static let doubleDayShareFloor = 0.40
    /// Week-over-week volume jumps above this are worth naming.
    static let volumeJumpCeiling = 12.0

    static func all(days: [TrendsDay],
                    weeks: [TrendsWeek],
                    paceBands: PaceBands?,
                    goal: TipGoal?) -> [TrainingTip] {
        let recent = Array(days.suffix(28))
        return [
            racePaceExposure(days: recent, goal: goal),
            greyZone(days: recent),
            monotonousLongRuns(days: days, goal: goal),
            continuousTimeOnFeet(days: recent, goal: goal),
            volumeRamp(days: days),
            easyDayDiscipline(days: recent)
        ].compactMap { $0 }
    }

    // MARK: Pace · race-pace exposure

    /// The one tip that is fully goal-parameterised: a 5K athlete is measured
    /// on 5K-pace miles, a marathoner on marathon-pace miles.
    private static func racePaceExposure(days: [TrendsDay], goal: TipGoal?) -> TrainingTip? {
        guard let goal else { return nil }
        if let weeks = goal.weeksOut, weeks > racePaceWindowWeeks { return nil }

        var totals: [String: Double] = [:]
        for day in days {
            for (token, miles) in (day.zoneMiles ?? [:]) {
                totals[token, default: 0] += miles
            }
        }
        let grand = totals.values.reduce(0, +)
        guard grand > 20 else { return nil }

        let atRace = totals[goal.racePaceToken] ?? 0
        let share = atRace / grand * 100
        guard share < racePaceShareFloor else { return nil }

        let weeks = goal.weeksOut
        let isSharpEnd = (weeks ?? 0) <= racePaceSharpWeeks
        let weeksLine = weeks.map { "\($0) weeks out" } ?? "with the race on the calendar"
        let atRaceLabel = String(format: "%.1f", atRace)
        let grandLabel = String(format: "%.0f", grand)
        let shareLabel = String(format: "%.1f", share)

        var observation = "Over the last four weeks, \(atRaceLabel) of \(grandLabel) miles sat at "
        observation += "\(goal.raceLabel) pace — \(shareLabel)%. \(goal.timeLabel) is "
        observation += "\(goal.racePaceLabel) a mile, and \(weeksLine), "
        observation += isSharpEnd
            ? "that's the pace this block exists to rehearse."
            : "it's early enough that this is a note rather than an alarm — but it's the one pace the day itself is run at, and the legs learn it slowly."

        let action = isSharpEnd
            ? "Put continuous blocks at \(goal.racePaceLabel) inside a run you're already doing — 2 × 3 miles in the back half of your long run rather than a separate session. Continuous beats intervals here: the point is rehearsing the pace when you're already tired."
            : "Start small and inside existing runs: 2 × 2 miles at \(goal.racePaceLabel) in the back half of a long run, once a fortnight. It doesn't need its own day, and it doesn't need to be hard yet — it needs to stop being unfamiliar."

        return TrainingTip(
            id: "race-pace-exposure",
            category: .pace,
            headline: isSharpEnd
                ? "Your race pace is the pace you've run least."
                : "Your race pace is still a stranger.",
            observation: observation,
            action: action,
            evidence: [
                "\(goal.raceLabel.capitalized) pace · \(shareLabel)% of 4 weeks",
                "Goal pace · \(goal.racePaceLabel)/mi",
                "\(atRaceLabel) mi at race pace"
            ],
            priority: 100
        )
    }

    // MARK: Pace · the grey zone

    private static func greyZone(days: [TrendsDay]) -> TrainingTip? {
        var totals: [String: Double] = [:]
        for day in days {
            for (token, miles) in (day.zoneMiles ?? [:]) {
                totals[token, default: 0] += miles
            }
        }
        let grand = totals.values.reduce(0, +)
        guard grand > 20 else { return nil }

        let moderate = totals["moderate"] ?? 0
        let easy = (totals["easy"] ?? 0) + (totals["recovery"] ?? 0)
        let moderateShare = moderate / grand * 100
        let easyShare = easy / grand * 100
        guard moderateShare > moderateShareCeiling else { return nil }

        return TrainingTip(
            id: "grey-zone",
            category: .pace,
            headline: "A third of your running is in the middle.",
            observation: "\(String(format: "%.0f", moderateShare))% of the last four weeks sat at moderate pace, against \(String(format: "%.0f", easyShare))% easy. Moderate is the pace that costs almost as much to recover from as real work while driving much less adaptation — it fills the week without moving much.",
            action: "Take the moderate miles to one side or the other. Most days drop to genuinely easy; one or two days a week take the work up to threshold or race pace. The weekly mileage doesn't need to change at all.",
            evidence: [
                "Moderate · \(String(format: "%.0f", moderateShare))% of miles",
                "Easy · \(String(format: "%.0f", easyShare))% of miles"
            ],
            priority: 80
        )
    }

    // MARK: Pace · long runs with no change of pace

    private static func monotonousLongRuns(days: [TrendsDay], goal: TipGoal?) -> TrainingTip? {
        let longRuns = days.filter { $0.type == .long }.suffix(4)
        guard longRuns.count >= 3 else { return nil }

        var monotonous: [String] = []
        for day in longRuns {
            guard let zones = day.zoneMiles, !zones.isEmpty else { continue }
            let total = zones.values.reduce(0, +)
            guard total > 0, let top = zones.values.max() else { continue }
            if top / total >= monotonousLongRunShare {
                monotonous.append(String(format: "%.1f mi", day.miles))
            }
        }
        guard monotonous.count >= 3 else { return nil }

        let paceLine = goal.map { "\($0.racePaceLabel) a mile" } ?? "race pace"

        return TrainingTip(
            id: "monotonous-long-runs",
            category: .pace,
            headline: "Your long runs run themselves.",
            observation: "\(monotonous.count) of your last \(longRuns.count) long runs sat almost entirely in a single pace zone from start to finish. The distance is there — what's missing is anything inside them that asks a different question of the legs.",
            action: "Keep the distance and change the shape. A progression — last 4 miles quicker than the first 4 — or a block at \(paceLine) in the back half. Same run, one instruction.",
            evidence: monotonous.map { "Single-zone long run · \($0)" },
            priority: 75
        )
    }

    // MARK: Load · continuous time on feet

    private static func continuousTimeOnFeet(days: [TrendsDay], goal: TipGoal?) -> TrainingTip? {
        let runDays = days.filter { $0.miles > 0 }
        guard runDays.count >= 8 else { return nil }

        let doubleDays = runDays.filter { $0.runs.count > 1 }
        let share = Double(doubleDays.count) / Double(runDays.count)
        guard share >= doubleDayShareFloor else { return nil }

        let longestSingle = runDays.flatMap { $0.runs }.map(\.miles).max() ?? 0
        let longestDay = runDays.map(\.miles).max() ?? 0
        // Only worth saying when splitting is actually costing continuous
        // duration somewhere other than the long run.
        guard longestDay > 0 else { return nil }

        let splitExample = doubleDays
            .sorted { $0.miles > $1.miles }
            .first
            .map { day in
                day.runs.map { String(format: "%.1f", $0.miles) }.joined(separator: " + ")
            }

        let raceLine = goal?.raceLabel ?? "the race"

        // Built in steps rather than one concatenated expression — a long
        // chain of `+` with an optional in the middle is a reliable way to
        // trip "unable to type-check this expression in reasonable time".
        var observation = "\(doubleDays.count) of your last \(runDays.count) running days were doubles"
        if let splitExample {
            observation += " — your biggest was \(splitExample)"
        }
        observation += ". Doubles are an efficient way to carry volume, but "
        observation += "\(raceLine) is one continuous effort, and the adaptations that matter most "
        observation += "for it track time on feet in a single run rather than miles in a day."

        return TrainingTip(
            id: "continuous-time-on-feet",
            category: .load,
            headline: "The mileage is there. The continuous running isn't.",
            observation: observation,
            action: "Once a week, run one of the doubles as a single continuous run instead. Same total, one session — the second-longest run of your week is usually the one to consolidate.",
            evidence: [
                "\(doubleDays.count) of \(runDays.count) days were doubles",
                String(format: "Longest single run · %.1f mi", longestSingle),
                String(format: "Longest day · %.1f mi", longestDay)
            ],
            priority: 85
        )
    }

    // MARK: Load · volume ramp

    private static func volumeRamp(days: [TrendsDay]) -> TrainingTip? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt

        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.locale = Locale(identifier: "en_US_POSIX")

        var buckets: [Date: Double] = [:]
        for day in days {
            guard let date = f.date(from: day.date),
                  let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start
            else { continue }
            buckets[start, default: 0] += day.miles
        }
        // Drop the current (partial) week — a Tuesday is not a down week.
        let ordered = buckets.keys.sorted().dropLast().suffix(5)
        let series = ordered.map { buckets[$0] ?? 0 }
        guard series.count >= 3 else { return nil }

        var worst: (from: Double, to: Double, pct: Double)?
        for i in 1..<series.count {
            let prev = series[i - 1], next = series[i]
            guard prev > 5 else { continue }
            let pct = (next / prev - 1) * 100
            if pct > volumeJumpCeiling, pct > (worst?.pct ?? 0) {
                worst = (prev, next, pct)
            }
        }
        guard let jump = worst else { return nil }

        let seriesLine = series.map { String(format: "%.0f", $0) }.joined(separator: " · ")
        let fromLabel = String(format: "%.0f", jump.from)
        let toLabel = String(format: "%.0f", jump.to)
        let pctLabel = String(format: "%.0f", jump.pct)

        var observation = "Your last few weeks ran \(seriesLine) miles. "
        observation += "The step from \(fromLabel) to \(toLabel) is \(pctLabel)% in one week — "
        observation += "the single-week jump is the part of a build that tends to be felt two or "
        observation += "three weeks later rather than at the time."

        return TrainingTip(
            id: "volume-ramp",
            category: .load,
            headline: "One week jumped harder than the others.",
            observation: observation,
            action: "Keep the climb nearer 10% a week and let the extra volume arrive in the week after instead. If a big week is deliberate, follow it with one that's genuinely lower rather than level.",
            evidence: series.map { String(format: "%.0f mi", $0) },
            priority: 70
        )
    }

    // MARK: Load · easy-day discipline

    private static func easyDayDiscipline(days: [TrendsDay]) -> TrainingTip? {
        let runDays = days.filter { $0.miles > 0 }
        guard runDays.count >= 10 else { return nil }

        // Days with no work at all that still weren't easy — the recovery days
        // that aren't recovering.
        let notEasyRecovery = runDays.filter { day in
            guard let zones = day.zoneMiles, !zones.isEmpty else { return false }
            let total = zones.values.reduce(0, +)
            guard total > 0 else { return false }
            let work = ["steady", "mp", "hmp", "lt", "10k", "5k", "3k", "mile"]
                .reduce(0.0) { $0 + (zones[$1] ?? 0) }
            let moderate = zones["moderate"] ?? 0
            // No real work in the day, but mostly moderate rather than easy.
            return work / total < 0.05 && moderate / total > 0.5
        }
        guard notEasyRecovery.count >= 4 else { return nil }

        return TrainingTip(
            id: "easy-day-discipline",
            category: .load,
            headline: "Your easy days aren't easy.",
            observation: "\(notEasyRecovery.count) days in the last four weeks had no real work in them and still ran mostly at moderate pace. Those days carry the cost of training without the benefit — they're the reason a hard day can feel flat.",
            action: "On the days between sessions, run by feel and let the pace be slower than feels natural. The test is whether you could hold a conversation the whole way.",
            evidence: [
                "\(notEasyRecovery.count) moderate-paced days with no work",
                "\(runDays.count) running days in the window"
            ],
            priority: 60
        )
    }
}
