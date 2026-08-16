import Foundation

//  The mood read: a count over a fortnight, not a score.
//
//  WHY NOT A SCORE. This shipped briefly as a 0–100 mean and it could not
//  answer the only question worth asking. A mean is not reversible — 56 cannot
//  be turned back into days — and it cannot see clustering: fourteen neutral
//  days and a fortnight of half energized, half injured average the same. It
//  also needed a paragraph under it explaining that it wasn't a grade, which is
//  a design telling on itself.
//
//  WHAT REPLACED IT. "Seven of the last fourteen days came back struggling."
//  A fraction of a concrete window: definitive without being arbitrary,
//  reversible because you can point at the seven in the chart, and a trend
//  because the fortnight before it is printed underneath. (Rio, 2026-08-15.)
//
//  THE BLOCK IS THE WINDOW. The chart draws exactly the fourteen days the
//  headline counts — no fortnight-inside-a-month, no second timescale to hold
//  in your head. Stepping back moves a whole fortnight.
enum TrendsMoodRead {

    /// The block. Fourteen days is long enough that one hard Tuesday doesn't
    /// move it and short enough to still be about now — and short enough that
    /// a day is a real target on a phone rather than a 6pt sliver.
    static let windowDays = 14

    /// Half the block. Below this many logged days the header says how many it
    /// actually heard from: "2 of 14" understates badly when only three were
    /// logged, and the fix is to say so, not to change the denominator.
    static let thinLogFloor = windowDays / 2

    /// The closed vocabulary, best to worst. Duplicated from
    /// `TrendsMoodColor.ordered` so this file stays free of SwiftUI; a test
    /// pins the two together.
    nonisolated static let vocabulary = [
        "energized", "positive", "neutral", "tired", "struggling", "injured",
    ]

    /// What counts as a low day.
    ///
    /// `tired` is deliberately NOT in here. A tired day after a hard session is
    /// training working, not a bad day, and counting it would put the headline
    /// in the red through every honest build. It still shows in the day cells
    /// and the counted list — it just isn't evidence on its own.
    nonisolated static let lowLabels: Set<String> = ["struggling", "injured"]

    // `nonisolated` on these four: the module is main-actor-by-default, and
    // both predicates get passed as function REFERENCES to `filter` below —
    // a synchronous nonisolated context. Pure functions over immutable
    // Sendable constants, so there is nothing for the actor to protect.
    // Warnings today; hard errors under Swift 6.
    nonisolated static func isLogged(_ mood: String?) -> Bool {
        guard let raw = mood?.lowercased(), !raw.isEmpty else { return false }
        return vocabulary.contains(raw)
    }

    nonisolated static func isLow(_ mood: String?) -> Bool {
        guard let raw = mood?.lowercased() else { return false }
        return lowLabels.contains(raw)
    }

    static func lowCount(_ moods: [String?]) -> Int { moods.filter(isLow).count }
    static func loggedCount(_ moods: [String?]) -> Int { moods.filter(isLogged).count }

    /// Count per label. Unrecognised labels are dropped rather than bucketed —
    /// a vocabulary drift must show as a missing day, never as a wrong one.
    static func counts(_ moods: [String?]) -> [String: Int] {
        var out: [String: Int] = [:]
        for mood in moods {
            guard let raw = mood?.lowercased(), vocabulary.contains(raw) else { continue }
            out[raw, default: 0] += 1
        }
        return out
    }

    /// The longest unbroken run of low days.
    ///
    /// Any day that is not low breaks the run, INCLUDING a day with no log — an
    /// unlogged day is not evidence of a bad one. This under-claims on purpose.
    static func longestLowRun(_ moods: [String?]) -> Int {
        var best = 0, current = 0
        for mood in moods {
            if isLow(mood) { current += 1; best = max(best, current) } else { current = 0 }
        }
        return best
    }

    /// Which way a count moved. Two days of slack either side, so the header
    /// doesn't announce a direction every time one day changes.
    enum Move {
        case worse, better, flat

        static func of(now: Int, then: Int) -> Move {
            let delta = now - then
            if delta >= 2 { return .worse }
            if delta <= -2 { return .better }
            return .flat
        }
    }
}

// MARK: - The block

/// One fortnight, resolved through the same bucket pipeline the rest of Trends
/// uses so this surface cannot disagree with the others about what a day was.
struct TrendsMoodBlock {

    let set: TrendsBucketSet
    /// 0 = the most recent full fortnight. 1 = the fourteen days before that.
    let blocksBack: Int
    let from: Date
    let to: Date

    // `self.` is load-bearing: as the first token inside a computed-property
    // body, a bare `set` parses as the start of a setter clause.
    var buckets: [TrendsBucket] { self.set.buckets }
    var days: [TrendsDay] { self.set.days }
    var moods: [String?] { buckets.map(\.mood) }
    var dayCount: Int { buckets.count }

    var lowDays: Int { TrendsMoodRead.lowCount(moods) }
    var loggedDays: Int { TrendsMoodRead.loggedCount(moods) }
    var longestLowRun: Int { TrendsMoodRead.longestLowRun(moods) }
    var niggleDays: Int { buckets.filter(\.hasNiggle).count }
    var keySessionCount: Int { buckets.reduce(0) { $0 + $1.keyCount } }
    var miles: Double { buckets.reduce(0) { $0 + $1.miles } }
    var counts: [String: Int] { TrendsMoodRead.counts(moods) }

    /// True when the fortnight barely heard from her. The count isn't wrong,
    /// but it is a weaker claim, and the header says so.
    var isThin: Bool { loggedDays < TrendsMoodRead.thinLogFloor }

    /// "17 Jul – 30 Jul", from the columns actually in the window.
    var rangeLabel: String {
        guard let first = buckets.first?.label, let last = buckets.last?.label else { return "" }
        return "\(first) – \(last)"
    }

    /// Daily training load. `zoneLoad` is already weighted minutes — TLS as the
    /// app defines it. `stressLoad` covers days the zone backfill hasn't
    /// reached; a day with neither contributes 0 rather than a guess.
    var load: [Double] {
        days.map { day in
            if let zones = day.zoneLoad, !zones.isEmpty { return zones.values.reduce(0, +) }
            return day.stressLoad ?? 0
        }
    }

    /// The body part mentioned on the most days.
    var topNiggleArea: String? {
        var tally: [String: Int] = [:]
        for bucket in buckets {
            for area in Set(bucket.niggles.map { $0.area.lowercased() }) {
                tally[area, default: 0] += 1
            }
        }
        return tally.max { a, b in a.value == b.value ? a.key > b.key : a.value < b.value }?.key
    }

    /// Calendar weeks inside the window. The two at the edges are usually
    /// clipped — `partial` marks them so a short bar is not read as a down week.
    struct WeekRun {
        let first: Int
        let last: Int
        let miles: Double
        var dayCount: Int { last - first + 1 }
        var partial: Bool { dayCount < 7 }
    }

    var weekRuns: [WeekRun] {
        var runs: [WeekRun] = []
        for (i, bucket) in buckets.enumerated() {
            if i == 0 || bucket.isWeekStart {
                runs.append(WeekRun(first: i, last: i, miles: bucket.miles))
            } else if let open = runs.popLast() {
                runs.append(WeekRun(first: open.first, last: i, miles: open.miles + bucket.miles))
            }
        }
        return runs
    }
}

// MARK: - Building blocks

/// Slices the dense day timeline into whole fortnights.
///
/// Index-based rather than date arithmetic: `TrendsService.days` is dense — one
/// row per day through today, rest days included — so counting rows is counting
/// days, and a block is exactly fourteen columns wide whatever month it lands in.
enum TrendsMoodBlocks {

    /// How far back a whole block still exists. Stepping stops there rather
    /// than showing a short block, which would quietly change the denominator
    /// while still calling itself fourteen days.
    static func maxBlocksBack(dayCount: Int) -> Int {
        max(0, dayCount / TrendsMoodRead.windowDays - 1)
    }

    static func block(
        days: [TrendsDay],
        keySessions: [KeySession],
        blocksBack: Int
    ) -> TrendsMoodBlock? {
        let width = TrendsMoodRead.windowDays
        let end = days.count - blocksBack * width
        guard blocksBack >= 0, end >= width else { return nil }

        let slice = Array(days[(end - width)..<end])
        guard let first = slice.first, let last = slice.last,
              let from = TrendsWindow.day(fromISO: first.date),
              let to = TrendsWindow.day(fromISO: last.date)
        else { return nil }

        // The builder is handed the FULL history, not the slice: recovery needs
        // an 8-week baseline and a 14-day niggle lookback that both sit behind
        // the window's first column. `.custom` filters to the span.
        let set = TrendsSignalBuilder.build(
            days: days,
            keySessions: keySessions,
            window: .custom(from: from, to: to)
        )
        return TrendsMoodBlock(set: set, blocksBack: blocksBack, from: from, to: to)
    }
}
