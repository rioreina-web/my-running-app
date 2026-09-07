//
//  GoalPaceGridDTO.swift
//  RunningLog · Trends
//
//  Wire format for `goal_pace_grid`, produced by
//  `trends-timeline/goalPaceGrid.ts`. REPLACES the one-percent-per-session
//  model in GoalPaceDTO.swift: that model averaged every workout into a
//  single number, which meant a 2mi warm-up + 16mi at MP + 2mi cool-down
//  reported as one mediocre ~92% instead of showing 16 miles of goal-pace
//  work. This surface never averages — every non-recovery BLOCK of every
//  candidate session is its own deposit, with its own miles and its own row.
//
//  ROW BUCKETING HAPPENS SERVER-SIDE ONLY. `pace_row` / `pace_row_heat_adj`
//  arrive pre-computed and this file never re-derives them from `pct_of_goal`.
//  The reason is concrete: the HTML prototype this feature grew from had a
//  backwards threshold search that collapsed every value from 75% to 115% of
//  goal pace into one row, and it survived two rounds of screenshot review
//  because nobody checked a boundary value. `goalPaceGrid.test.ts` on the
//  server pins every boundary explicitly; duplicating the bucketing logic
//  here would just create a second place for that exact bug to reappear.
//

import Foundation

// MARK: - View models

struct GoalPaceGridDeposit: Identifiable, Equatable {
    var id: String { "\(workoutId)-\(paceRow)-\(miles)" }
    let workoutId: String
    let date: Date
    let workoutType: String?
    let miles: Double
    let paceSec: Int
    let paceSecHeatAdj: Int
    let pctOfGoal: Double
    let pctOfGoalHeatAdj: Double
    /// Pre-computed server-side. Never re-derive from pct — see file header.
    let paceRow: Int
    let paceRowHeatAdj: Int
    let isKey: Bool
    let isLong: Bool
}

struct GoalPaceGridGoal: Equatable {
    let raceKey: String
    let timeSeconds: Int
    let paceSecPerMile: Double
    let source: String
    /// Nil when the goal resolved from a source with no date column
    /// (`athlete_state`'s flat columns). The grid still renders; it just has
    /// no right edge to size the runway against.
    let raceDate: Date?
}

struct GoalPaceGridSummary: Equatable {
    let totalMiles: Double
    let keyMiles: Double
    let longMiles: Double
    let nearGoalMiles: Double
    let nearGoalPct: Double
}

/// Which lens is filtering the grid. Mirrors the server's `is_key`/`is_long`
/// flags — `long_wo` deposits are true under both, so switching lenses can
/// only ever remove volume, never invent it.
enum GoalPaceGridFilter: String, CaseIterable, Identifiable {
    case all, key, long
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: return "All"
        case .key: return "Key sessions"
        case .long: return "Long runs"
        }
    }
}

struct GoalPaceGridData: Equatable {
    let goal: GoalPaceGridGoal
    let rowLabels: [String]
    let deposits: [GoalPaceGridDeposit]
    let summary: GoalPaceGridSummary

    var isEmpty: Bool { deposits.isEmpty }

    func deposits(for filter: GoalPaceGridFilter) -> [GoalPaceGridDeposit] {
        switch filter {
        case .all: return deposits
        case .key: return deposits.filter(\.isKey)
        case .long: return deposits.filter(\.isLong)
        }
    }

    /// Monday-anchored weeks spanning the data through race day (or through
    /// today, when the goal carries no date). Always includes today's week
    /// even if it has no deposits yet, so the runway to the race is visible.
    func weeks(calendar: Calendar = .current, now: Date = Date()) -> [Date] {
        guard let first = deposits.map(\.date).min() else { return [] }
        let start = calendar.mondayOfWeek(containing: first)
        let end = calendar.mondayOfWeek(containing: max(goal.raceDate ?? now, now))
        var weeks: [Date] = []
        var cursor = start
        while cursor <= end {
            weeks.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 7, to: cursor) else { break }
            cursor = next
        }
        return weeks
    }

    /// One column per DAY across the same span (2026-09-01, Rio: "have it be
    /// day by day"). Week columns pooled up to seven sessions into a single
    /// cell, which both blurred the distribution and made a tapped cell
    /// ambiguous — it had to pick one arbitrary deposit out of a week's worth
    /// and could then label it with a date from a different day. A day column
    /// is one day, so the cell and its readout can't disagree.
    func days(calendar: Calendar = .current, now: Date = Date()) -> [Date] {
        guard let first = deposits.map(\.date).min() else { return [] }
        let start = calendar.startOfDay(for: first)
        let end = calendar.startOfDay(for: max(goal.raceDate ?? now, now))
        var days: [Date] = []
        var cursor = start
        while cursor <= end {
            days.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return days
    }

    /// Miles per (day, pace row). Same contract as the weekly `grid` — the
    /// pre-computed row is used as-is, never re-derived here.
    func dayGrid(
        filter: GoalPaceGridFilter,
        days: [Date],
        heatAdjusted: Bool,
        calendar: Calendar = .current
    ) -> [[Double]] {
        let rowCount = rowLabels.count
        var g = Array(repeating: Array(repeating: 0.0, count: days.count), count: rowCount)
        guard !days.isEmpty else { return g }
        let dayIndex: [Date: Int] = Dictionary(
            uniqueKeysWithValues: days.enumerated().map { ($1, $0) }
        )
        for d in deposits(for: filter) {
            let day = calendar.startOfDay(for: d.date)
            guard let di = dayIndex[day] else { continue }
            let row = heatAdjusted ? d.paceRowHeatAdj : d.paceRow
            guard row >= 0, row < rowCount else { continue }
            g[row][di] += d.miles
        }
        return g
    }

    /// Miles per (week, pace row) for a given filter and week list. `heatAdjusted`
    /// selects which pre-computed row/pct pair to bucket by — never a local
    /// recompute.
    func grid(
        filter: GoalPaceGridFilter,
        weeks: [Date],
        heatAdjusted: Bool,
        calendar: Calendar = .current
    ) -> [[Double]] {
        let rowCount = rowLabels.count
        var g = Array(repeating: Array(repeating: 0.0, count: weeks.count), count: rowCount)
        guard !weeks.isEmpty else { return g }
        let weekIndex: [Date: Int] = Dictionary(
            uniqueKeysWithValues: weeks.enumerated().map { ($1, $0) }
        )
        for d in deposits(for: filter) {
            let monday = calendar.mondayOfWeek(containing: d.date)
            guard let wi = weekIndex[monday] else { continue }
            let row = heatAdjusted ? d.paceRowHeatAdj : d.paceRow
            guard row >= 0, row < rowCount else { continue }
            g[row][wi] += d.miles
        }
        return g
    }

    /// Total miles in a lane, for the summary chips under the grid.
    func miles(filter: GoalPaceGridFilter) -> Double {
        deposits(for: filter).reduce(0) { $0 + $1.miles }
    }

    /// Every deposit from the same workout as `deposit`, ACROSS every filter —
    /// a day's blocks all share `is_key`/`is_long`, so the active lens can't
    /// change this.
    func sessionDeposits(matching deposit: GoalPaceGridDeposit) -> [GoalPaceGridDeposit] {
        deposits.filter { $0.workoutId == deposit.workoutId }
    }

    /// The most recent SESSION, aggregated — not a single block. This went
    /// through two wrong versions before landing here:
    ///   1. "most recent block by date" — four 3-mile reps from the same day
    ///      tie on date, so it could land on a rep instead of the day's total.
    ///   2. "largest block in the last 3 weeks" — this fixed the tie but then
    ///      jumped PAST the athlete's actual most recent run to an older,
    ///      bigger single-block long run, which is worse: the headline
    ///      stopped being "your last run" at all.
    /// The fix is to stop trying to pick a representative BLOCK and instead
    /// show what a session actually is: ALL its volume, summed, for the most
    /// recent day that has any. A 21-mile day with four 3-mile reps shows as
    /// "12 mi across 4 blocks" — the true captured total — not one slice of it.
    /// One aggregated row per actual training session, not one per block.
    /// The list this backs used to show a raw block per row, so an 8-rep
    /// interval workout was 8 nearly-identical rows for what the athlete
    /// thinks of as ONE session. Groups by calendar day — key sessions
    /// essentially never double up same-day, and merging is the same
    /// simplification `headlineSession()` already makes for the default
    /// readout, applied consistently to the whole list.
    func sessionSummaries(for filter: GoalPaceGridFilter) -> [SessionHeadline] {
        let byDay = Dictionary(grouping: deposits(for: filter), by: \.date)
        return byDay.compactMap { date, dayDeposits -> SessionHeadline? in
            guard !dayDeposits.isEmpty else { return nil }
            let byRow = Dictionary(grouping: dayDeposits, by: \.paceRow)
            let dominantRow = byRow.max { a, b in
                a.value.reduce(0) { $0 + $1.miles } < b.value.reduce(0) { $0 + $1.miles }
            }
            let dominant = dominantRow?.value.first ?? dayDeposits[0]
            return SessionHeadline(
                date: date,
                deposits: dayDeposits,
                totalMiles: dayDeposits.reduce(0) { $0 + $1.miles },
                dominant: dominant
            )
        }.sorted { $0.date > $1.date }
    }

    /// The most recent day, aggregated — same grouping `sessionSummaries`
    /// uses (unfiltered, since the default readout should answer "what was my
    /// last run" regardless of which lens is active), just the newest one.
    func headlineSession() -> SessionHeadline? {
        sessionSummaries(for: .all).first
    }
}

/// The most recent day's volume, aggregated across every block logged for it.
/// This is what a card shows BEFORE the athlete taps anything — the full
/// picture of the last session, not one pace segment of it.
struct SessionHeadline {
    let date: Date
    /// Every block logged for this day, across every filter.
    let deposits: [GoalPaceGridDeposit]
    /// The full captured total — ALL the volume, summed.
    let totalMiles: Double
    /// The single largest block, for a representative pace/percent to show
    /// alongside the total (e.g. "12 mi across 4 blocks, mostly at 87%").
    let dominant: GoalPaceGridDeposit
    var blockCount: Int { deposits.count }
}

/// Not private: `todayIndex`/`raceIndex`/tap-lookup in GoalPaceGridCard must
/// bucket dates through this SAME function, not `Calendar`'s own
/// `.weekOfYear` granularity comparison against a differently-configured
/// calendar. Those two disagreeing is exactly the bug that made the grid
/// default-scroll to the race week instead of today: `Calendar.current`'s
/// locale default first-weekday (often Sunday) doesn't line up with the
/// Monday-anchored weeks this file builds, so a granularity match silently
/// failed and fell back to `weeks.count - 1` — the last column, i.e. race week.
extension Calendar {
    /// Monday of the week containing `date`, at midnight.
    func mondayOfWeek(containing date: Date) -> Date {
        var cal = self
        cal.firstWeekday = 2 // Monday
        let start = cal.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        return cal.startOfDay(for: start)
    }
}

// MARK: - Wire format

struct GoalPaceGridDTO: Decodable {
    let goal: GoalDTO
    let rowLabels: [String]
    let deposits: [DepositDTO]
    let summary: SummaryDTO

    private enum CodingKeys: String, CodingKey {
        case goal
        case rowLabels = "row_labels"
        case deposits
        case summary
    }

    struct GoalDTO: Decodable {
        let raceKey: String
        let timeSeconds: Int
        let paceSecPerMile: Double
        let source: String
        let raceDate: String?
        private enum CodingKeys: String, CodingKey {
            case raceKey = "race_key"
            case timeSeconds = "time_seconds"
            case paceSecPerMile = "pace_sec_per_mile"
            case source
            case raceDate = "race_date"
        }
    }

    struct DepositDTO: Decodable {
        let workoutId: String
        let date: String
        let workoutType: String?
        let miles: Double
        let paceSec: Int
        let paceSecHeatAdj: Int
        let pctOfGoal: Double
        let pctOfGoalHeatAdj: Double
        let paceRow: Int
        let paceRowHeatAdj: Int
        let isKey: Bool
        let isLong: Bool
        private enum CodingKeys: String, CodingKey {
            case workoutId = "workout_id"
            case date
            case workoutType = "workout_type"
            case miles
            case paceSec = "pace_sec"
            case paceSecHeatAdj = "pace_sec_heat_adj"
            case pctOfGoal = "pct_of_goal"
            case pctOfGoalHeatAdj = "pct_of_goal_heat_adj"
            case paceRow = "pace_row"
            case paceRowHeatAdj = "pace_row_heat_adj"
            case isKey = "is_key"
            case isLong = "is_long"
        }
    }

    struct SummaryDTO: Decodable {
        let totalMiles: Double
        let keyMiles: Double
        let longMiles: Double
        let nearGoalMiles: Double
        let nearGoalPct: Double
        private enum CodingKeys: String, CodingKey {
            case totalMiles = "total_miles"
            case keyMiles = "key_miles"
            case longMiles = "long_miles"
            case nearGoalMiles = "near_goal_miles"
            case nearGoalPct = "near_goal_pct"
        }
    }

    /// `date` arrives as a DATE column, which the SDK's default decoder
    /// throws on — see `feedback_supabase_swift_date_decoder`. Parsed by hand.
    private static func parseDate(_ s: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }
        let plain = DateFormatter()
        plain.calendar = Calendar(identifier: .iso8601)
        plain.timeZone = TimeZone(identifier: "UTC")
        plain.dateFormat = "yyyy-MM-dd"
        return plain.date(from: String(s.prefix(10)))
    }

    func toData() -> GoalPaceGridData? {
        let parsed: [GoalPaceGridDeposit] = deposits.compactMap { d in
            guard let date = Self.parseDate(d.date) else { return nil }
            return GoalPaceGridDeposit(
                workoutId: d.workoutId,
                date: date,
                workoutType: d.workoutType,
                miles: d.miles,
                paceSec: d.paceSec,
                paceSecHeatAdj: d.paceSecHeatAdj,
                pctOfGoal: d.pctOfGoal,
                pctOfGoalHeatAdj: d.pctOfGoalHeatAdj,
                paceRow: d.paceRow,
                paceRowHeatAdj: d.paceRowHeatAdj,
                isKey: d.isKey,
                isLong: d.isLong
            )
        }
        guard !parsed.isEmpty else { return nil }
        return GoalPaceGridData(
            goal: GoalPaceGridGoal(
                raceKey: goal.raceKey,
                timeSeconds: goal.timeSeconds,
                paceSecPerMile: goal.paceSecPerMile,
                source: goal.source,
                raceDate: goal.raceDate.flatMap(Self.parseDate)
            ),
            rowLabels: rowLabels,
            deposits: parsed,
            summary: GoalPaceGridSummary(
                totalMiles: summary.totalMiles,
                keyMiles: summary.keyMiles,
                longMiles: summary.longMiles,
                nearGoalMiles: summary.nearGoalMiles,
                nearGoalPct: summary.nearGoalPct
            )
        )
    }
}
