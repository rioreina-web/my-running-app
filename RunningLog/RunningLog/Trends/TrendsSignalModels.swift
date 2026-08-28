//
//  TrendsSignalModels.swift
//  RunningLog · Trends
//
//  The pure substrate behind Trends-v2: the time window, the day→bucket
//  rollup, the recovery ledger, and the computed read. No SwiftUI here —
//  every function is a pure map over `[TrendsDay]` + `[KeySession]` so the
//  numbers on the screen can be unit-tested without a view.
//
//  Three rules this file exists to enforce:
//
//  1. **One time control.** `TrendsWindow` is the only range on the surface.
//     Every section reads its slice from here; nothing carries a second,
//     independently-set range of its own.
//  2. **Ledes are functions, not strings.** `TrendsSignalRead` computes the
//     headline, the noise line and the findings from the same array the
//     chart draws, so prose cannot drift from the picture above it.
//  3. **No silent degradation.** When the window is wide enough to force
//     weekly buckets, `TrendsBucketSet.degradationNote` says which detail
//     was dropped and where to find it.
//
//  Date arithmetic goes through `TrendsWeekday` (UTC, calendar-field based).
//  Never add 86_400_000ms per day — that bug shipped once and blanked the
//  screen in America/Chicago while passing every test under UTC.
//

import Foundation

// MARK: - Window

/// The one time control on Trends. Raw value is the window in days; `custom`
/// carries its own bounds.
///
/// Replaces `TrendsRange` (4wk / 12wk / 6mo, defaulting to 12wk) on the v2
/// surface. The default is **30 days** — the window a self-coached runner
/// actually reasons in.
enum TrendsWindow: Equatable, Identifiable, Hashable {
    case thirtyDays
    case threeMonths
    case sixMonths
    case oneYear
    /// Inclusive bounds, UTC-midnight dates.
    case custom(from: Date, to: Date)

    static let presets: [TrendsWindow] = [.thirtyDays, .threeMonths, .sixMonths, .oneYear]

    var id: String {
        switch self {
        case .thirtyDays: "30d"
        case .threeMonths: "3mo"
        case .sixMonths: "6mo"
        case .oneYear: "1yr"
        case .custom: "custom"
        }
    }

    /// Pill label. Every preset reads in months or years — "30 D" sat in a row
    /// with "3 MO / 6 MO / 1 YR" as the only member using a different unit,
    /// which made the row read as four options and one oddity. The window is
    /// still 30 days; only the word changed.
    var label: String {
        switch self {
        case .thirtyDays: "1 MO"
        case .threeMonths: "3 MO"
        case .sixMonths: "6 MO"
        case .oneYear: "1 YR"
        case .custom: "CUSTOM"
        }
    }

    /// Nominal span in days. `custom` measures its own bounds.
    var days: Int {
        switch self {
        case .thirtyDays: 30
        case .threeMonths: 91
        case .sixMonths: 182
        case .oneYear: 365
        case .custom(let from, let to):
            max(1, Int(to.timeIntervalSince(from) / 86_400) + 1)
        }
    }

    /// Plate title for the header strip.
    var plateTitle: String {
        switch self {
        case .thirtyDays: "1-Month View"
        case .threeMonths: "3-Month View"
        case .sixMonths: "6-Month View"
        case .oneYear: "1-Year View"
        case .custom: "\(days)-Day View"
        }
    }

    var isCustom: Bool { if case .custom = self { return true }; return false }

    /// "2026-08-07" → a UTC-midnight `Date`, calendar-field based rather than
    /// by arithmetic on a time interval.
    ///
    /// The window's own date range is NOT computed from this — see
    /// `TrendsBucketSet.dateRangeLabel`, which reads the resolved slice. A
    /// preset is a trailing count of rows, not a span of calendar days, and an
    /// athlete with twelve days of timeline must not be told she is looking at
    /// a month.
    static func day(fromISO iso: String) -> Date? {
        let parts = iso.prefix(10).split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2])
        else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .current
        return cal.date(from: DateComponents(year: y, month: m, day: d))
    }
}

// MARK: - Session channel

/// What kind of day this was. Extends `TrendsDay.SessionChannel` with the
/// case the wire format can't express.
///
/// **Why `keyLong` exists.** `TrendsDay.SessionChannel` gives `long`
/// precedence over `key`, so a long run carrying real quality work — a
/// `Long wo` in the plan taxonomy — comes down the wire as plain `long` and
/// its key work vanishes from the day. That's a lossy classification: the
/// hardest session of some weeks is exactly this one.
///
/// We recover it client-side by cross-referencing the day against
/// `quality_sessions[]`: a `long` day that also carries a qualifying
/// non-long-run `KeySession` is a `keyLong`. No backend change needed.
///
/// The proper long-term fix is for `trends-timeline` to emit the two facts
/// separately (`is_long: Bool`, `key_sessions: Int`) rather than collapsing
/// them into one token — see the audit. Until then, this derivation is the
/// honest read of the data we already have.
enum TrendsSessionChannel: String, Hashable {
    case rest, easy, long, key, keyLong

    var isKey: Bool { self == .key || self == .keyLong }
    var isLong: Bool { self == .long || self == .keyLong }

    var readoutLabel: String {
        switch self {
        case .rest: "day off"
        case .easy: "easy"
        case .long: "long"
        case .key: "key"
        case .keyLong: "long + key"
        }
    }
}

// MARK: - Bucket

/// One column on the signal chart. A day at ≤120-day windows, a Monday-
/// anchored week above that.
struct TrendsBucket: Identifiable {
    let id = UUID()
    /// ISO date of the bucket's first day.
    let startISO: String
    let date: Date
    /// "Jul 5" — the axis and readout label.
    let label: String
    let miles: Double
    /// Key sessions in this bucket (0 or 1 for a day; 0…n for a week).
    let keyCount: Int
    let longCount: Int
    let channel: TrendsSessionChannel
    /// Summed quality load, for mark height at day grain.
    let qualityLoad: Double
    /// Closed vocabulary, or `nil` when nothing was logged.
    ///
    /// At day grain this is the mood of the day's hardest session — resolved
    /// server-side by `hardestSessionMood` in `trends-timeline/timeline.ts`,
    /// because only the server sees a day's individual logs. At week grain it
    /// is the most-logged day-label across the week.
    let mood: String?
    /// The body mentions that landed in this bucket, verbatim.
    let niggles: [TrendsDay.DayNiggle]
    /// Monday, at day grain — the chart rules a gridline here.
    let isWeekStart: Bool
    /// Days rolled into this bucket. 1 at day grain.
    let dayCount: Int

    var hasNiggle: Bool { !niggles.isEmpty }

    /// The bucket's loudest severity word, for the opacity ramp. The model
    /// never converts a word to a number — the view maps it to alpha and the
    /// readout quotes the athlete verbatim.
    var loudestSeverity: String? {
        niggles.compactMap(\.severity).max { TrendsSeverity.rank($0) < TrendsSeverity.rank($1) }
    }
}

// MARK: - Which log opens first

/// Ordering for a day that carries more than one log.
///
/// A workout day is often three rows — warm-up, workout, cool-down — and can
/// be a double. Opening the day should land on **the session that mattered**,
/// not on whichever row happens to sort first. The drill-down used to open
/// `entries[0]`, and since the fetch returns newest-first that was reliably
/// the cool-down: you tapped a hard Tuesday and got a 2-mile jog.
///
/// This deliberately mirrors `hardestSessionMood` in
/// `trends-timeline/timeline.ts` — the same day, asked the same question,
/// must not get two different answers depending on whether you're colouring
/// the mood lane or opening the log. The rank differs only in its first term,
/// because the client carries `quality_load` (the iOS-side approximation of
/// `intensity_score`) rather than the score itself:
///
///   1. Quality load — 0 for anything that isn't a qualifying key session.
///   2. Distance — a long run with no computed load still outranks a shakeout.
///   3. Most recent — a deterministic tiebreak, never a coin flip.
///
/// Only the *opening page* changes. The sibling run keeps its feed order, so
/// paging still reads oldest → newest and the athlete can cycle through every
/// log on the day. `HistoryDetailPager` mirrors that order itself and warns
/// against re-sorting, so this returns an index rather than a sorted array.
enum TrendsSessionOrder {

    /// One of a day's logs, reduced to just what decides the ordering. Keeps
    /// this file free of view-layer and database types so it stays testable.
    struct Candidate {
        let qualityLoad: Double
        let distanceMi: Double
        let at: Date

        init(qualityLoad: Double, distanceMi: Double, at: Date) {
            self.qualityLoad = qualityLoad
            self.distanceMi = distanceMi
            self.at = at
        }
    }

    /// Index of the hardest candidate, or `nil` for an empty list.
    static func hardestIndex(_ candidates: [Candidate]) -> Int? {
        guard !candidates.isEmpty else { return nil }
        return candidates.indices.max { a, b in
            let x = candidates[a], y = candidates[b]
            if x.qualityLoad != y.qualityLoad { return x.qualityLoad < y.qualityLoad }
            if x.distanceMi != y.distanceMi { return x.distanceMi < y.distanceMi }
            return x.at < y.at
        }
    }
}

/// Severity is the athlete's own word (`tight | sore | pain | sharp`), never a
/// score. `InjuryModels` keeps a 1–10 value for sorting only; it is never
/// displayed and never enters this file.
enum TrendsSeverity {
    private static let order = ["tight", "sore", "pain", "sharp"]

    static func rank(_ word: String?) -> Int {
        guard let w = word?.lowercased() else { return 0 }
        return (order.firstIndex(of: w) ?? 1) + 1
    }

    /// Opacity ramp for the niggle lane. Unknown words sit mid-ramp rather
    /// than loud or invisible.
    static func opacity(_ word: String?) -> Double {
        switch rank(word) {
        case 1: 0.32
        case 2: 0.55
        case 3: 0.78
        case 4: 1.0
        default: 0.5
        }
    }
}

// MARK: - Bucket set

/// The windowed, bucketed chart substrate plus everything derived from it.
struct TrendsBucketSet {
    enum Grain { case day, week }

    let grain: Grain
    let buckets: [TrendsBucket]
    /// The raw days in the window. Coverage is always counted in days, never
    /// buckets — a week with one check-in out of seven must not read "logged".
    let days: [TrendsDay]

    var isEmpty: Bool { buckets.isEmpty }

    /// Above 120 days the chart buckets weekly and loses day-level detail.
    /// It says so rather than truncating silently.
    var degradationNote: String {
        switch grain {
        case .day:
            // Mood went back to colour-only on 2026-08-06 — the height ramp
            // read as a bar chart of feelings. The clause is corrected rather
            // than dropped: the chart states its own encodings, and a false
            // one is worse than none.
            "\(buckets.count) daily columns · gridlines mark Mondays · mood is a colour, one swatch per logged day · niggle opacity is the athlete's own severity word"
        case .week:
            "\(buckets.count) weekly columns · mood shows the week's most-logged label and niggles show mentions per week — day-level detail needs the 1-month or 3-month view"
        }
    }

    // MARK: Window totals — every number on the screen is counted from here

    var totalMiles: Double { days.reduce(0) { $0 + $1.miles } }
    var keySessionCount: Int { buckets.reduce(0) { $0 + $1.keyCount } }
    var niggleMentionCount: Int { days.reduce(0) { $0 + $1.niggles.count } }
    var niggleAreas: Set<String> { Set(days.flatMap { $0.niggles.map { $0.area.lowercased() } }) }
    var moodLoggedDays: Int { days.filter { ($0.mood?.isEmpty == false) }.count }
    var restDays: Int { days.filter { $0.miles <= 0 }.count }
    /// Days that carried running. The time control's meta line counts these
    /// rather than `days.count`, so the range never claims a month of training
    /// when it holds a month of calendar and nine runs.
    var runDays: Int { days.filter { $0.miles > 0 }.count }

    /// "Jul 9 – Aug 7" — the days actually in the window.
    ///
    /// Read off the SLICE, never off the preset's nominal span. A preset is
    /// `days.suffix(n)`: it takes the last n rows that exist, so an athlete
    /// twelve days into her timeline on the 1-month view is looking at twelve
    /// days. A control that labelled that "Jul 9 – Aug 7" would be stating a
    /// range the chart beneath it is not drawing.
    ///
    /// Routed through `TrendsSignalBuilder.shortLabel` — the one table this
    /// surface names days from, so the meta line and the axis cannot start
    /// disagreeing about what to call July.
    var dateRangeLabel: String {
        guard let first = days.first?.date, let last = days.last?.date else { return "" }
        guard first != last else { return TrendsSignalBuilder.shortLabel(first) }
        return "\(TrendsSignalBuilder.shortLabel(first)) – \(TrendsSignalBuilder.shortLabel(last))"
    }

    /// The window's most-logged mood.
    ///
    /// **Modal**, like the week rollup and unlike the day.
    ///
    /// The hardest-session rule applies only where several readings describe
    /// ONE training unit — a day's warm-up, workout and cool-down. There the
    /// workout carries the day, and that resolution happens server-side in
    /// `hardestSessionMood` (`trends-timeline/timeline.ts`), which is the only
    /// place a day's individual logs are visible.
    ///
    /// Rolling 30 separate days into one label is a different question: "what
    /// was the common register?" Ranking there would reduce a month to its
    /// single hardest session — a sample of one. The chip reads MOST DAYS so
    /// the two are never confused.
    var modalMood: String? {
        let logged = days.compactMap { (d: TrendsDay) -> String? in
            guard let m = d.mood, !m.isEmpty else { return nil }
            return m
        }
        return TrendsBucketSet.modal(logged)
    }


    static func modal(_ values: [String]) -> String? {
        guard !values.isEmpty else { return nil }
        var counts: [String: Int] = [:]
        for v in values { counts[v, default: 0] += 1 }
        return counts.max { a, b in a.value == b.value ? a.key > b.key : a.value < b.value }?.key
    }
}

// MARK: - Builder

enum TrendsSignalBuilder {

    /// Windows above this many days bucket weekly.
    static let dailyGrainLimit = 120

    /// Build the chart substrate for a window.
    ///
    /// - Parameters:
    ///   - days: `TrendsService.days`, dense and oldest → newest.
    ///   - keySessions: `TrendsService.keySessions`, used only to recover the
    ///     `keyLong` case the wire format collapses.
    static func build(
        days allDays: [TrendsDay],
        keySessions: [KeySession],
        window: TrendsWindow
    ) -> TrendsBucketSet {
        let windowed = slice(allDays, window: window)
        guard !windowed.isEmpty else {
            return TrendsBucketSet(grain: .day, buckets: [], days: [])
        }

        let qualityDates = qualitySessionDates(keySessions)
        let longRunDates = longRunSessionDates(keySessions)

        let grain: TrendsBucketSet.Grain = windowed.count <= dailyGrainLimit ? .day : .week
        let buckets: [TrendsBucket] = grain == .day
            ? windowed.map {
                dayBucket($0, quality: qualityDates, longRuns: longRunDates)
            }
            : weekBuckets(windowed, quality: qualityDates, longRuns: longRunDates)

        return TrendsBucketSet(grain: grain, buckets: buckets, days: windowed)
    }

    // MARK: Slicing

    private static func slice(_ days: [TrendsDay], window: TrendsWindow) -> [TrendsDay] {
        switch window {
        case .custom(let from, let to):
            days.filter { d in
                guard let date = TrendsWeekday.date(from: d.date) else { return false }
                return date >= from && date <= to
            }
        default:
            Array(days.suffix(window.days))
        }
    }

    // MARK: key + long sessions

    /// Dates carrying a qualifying **non-long-run** key session. A nil quality
    /// load never clears the floor, so an older payload degrades to "not key"
    /// rather than inventing one.
    private static func qualitySessionDates(_ sessions: [KeySession]) -> Set<String> {
        Set(
            sessions
                .filter { !$0.isLongRun && QualityLoad.qualifies($0.qualityLoad) }
                .map { String($0.date.prefix(10)) }
        )
    }

    private static func longRunSessionDates(_ sessions: [KeySession]) -> Set<String> {
        Set(sessions.filter(\.isLongRun).map { String($0.date.prefix(10)) })
    }

    /// Channel per ISO date, decided exactly as the chart's columns decide it.
    ///
    /// Exposed for surfaces that render days outside the bucket pipeline — the
    /// week drill-down lists seven days while the chart is bucketed weekly, and
    /// the two must not disagree about which of them was key work.
    static func channels(
        for days: [TrendsDay],
        keySessions: [KeySession]
    ) -> [String: TrendsSessionChannel] {
        let quality = qualitySessionDates(keySessions)
        let longRuns = longRunSessionDates(keySessions)
        return Dictionary(
            days.map { ($0.date, channel(for: $0, quality: quality, longRuns: longRuns)) },
            uniquingKeysWith: { a, _ in a }
        )
    }

    /// The one place `keyLong` is decided.
    static func channel(
        for day: TrendsDay,
        quality: Set<String>,
        longRuns: Set<String>
    ) -> TrendsSessionChannel {
        let iso = String(day.date.prefix(10))
        let hasQuality = quality.contains(iso)
        let hasLong = longRuns.contains(iso) || day.type == .long

        switch day.type {
        case .rest:
            // A rest day with a logged session is a contradiction; trust miles.
            return day.miles > 0 ? .easy : .rest
        case .easy:
            return hasQuality ? (hasLong ? .keyLong : .key) : .easy
        case .long:
            // The lossy case: `long` won precedence on the wire. If the day
            // also carries qualifying key work, say so.
            return hasQuality ? .keyLong : .long
        case .key:
            return hasLong ? .keyLong : .key
        }
    }

    // MARK: Day grain

    private static func dayBucket(
        _ day: TrendsDay,
        quality: Set<String>,
        longRuns: Set<String>
    ) -> TrendsBucket {
        let ch = channel(for: day, quality: quality, longRuns: longRuns)
        let date = TrendsWeekday.date(from: day.date) ?? Date(timeIntervalSince1970: 0)
        return TrendsBucket(
            startISO: day.date,
            date: date,
            label: shortLabel(day.date),
            miles: day.miles,
            keyCount: ch.isKey ? 1 : 0,
            longCount: ch.isLong ? 1 : 0,
            channel: ch,
            qualityLoad: ch.isKey ? 1 : 0,
            mood: (day.mood?.isEmpty == false) ? day.mood : nil,
            niggles: day.niggles,
            isWeekStart: TrendsWeekday.index(from: day.date) == 0,
            dayCount: 1
        )
    }

    // MARK: Week grain

    private static func weekBuckets(
        _ days: [TrendsDay],
        quality: Set<String>,
        longRuns: Set<String>
    ) -> [TrendsBucket] {
        var groups: [(key: String, days: [TrendsDay])] = []
        for day in days {
            let ws = TrendsWeekday.weekStart(from: day.date) ?? day.date
            if groups.last?.key == ws {
                groups[groups.count - 1].days.append(day)
            } else {
                groups.append((key: ws, days: [day]))
            }
        }

        return groups.map { group in
            let ds = group.days
            let keyCount = ds.filter { channel(for: $0, quality: quality, longRuns: longRuns).isKey }.count
            let longCount = ds.filter { channel(for: $0, quality: quality, longRuns: longRuns).isLong }.count
            let miles = ds.reduce(0) { $0 + $1.miles }

            // The week's mood is the MODAL day-mood, not a load-ranked pick.
            //
            // The hardest-session rule is a DAY-level rule — it resolves
            // several readings of one training unit, and it now lives in
            // `trends-timeline`'s `hardestSessionMood`, which is where a day
            // actually gets collapsed. Rolling seven separate days into one
            // label asks a different question ("what was the common
            // register?"), and applying the rank here would reduce a whole
            // week to its single hardest session — a sample of one.
            let weekMood = TrendsBucketSet.modal(ds.compactMap { (d: TrendsDay) -> String? in
                guard let m = d.mood, !m.isEmpty else { return nil }
                return m
            })

            // At week grain the bar is a weekly total, not a session. Colouring
            // it by type would wash the lane — nearly every week contains a key
            // session — so the channel is carried by the KEY WORK lane instead.
            let ch: TrendsSessionChannel = miles > 0 ? .easy : .rest

            return TrendsBucket(
                startISO: group.key,
                date: TrendsWeekday.date(from: group.key) ?? Date(timeIntervalSince1970: 0),
                label: shortLabel(group.key),
                miles: (miles * 10).rounded() / 10,
                keyCount: keyCount,
                longCount: longCount,
                channel: ch,
                qualityLoad: Double(keyCount),
                mood: weekMood,
                niggles: ds.flatMap(\.niggles),
                isWeekStart: true,
                dayCount: ds.count
            )
        }
    }

    // MARK: Labels

    private static let monthAbbr = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun",
        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    ]

    /// "2026-07-05" → "Jul 5". Falls back to the raw string.
    static func shortLabel(_ iso: String) -> String {
        let parts = iso.prefix(10).split(separator: "-")
        guard parts.count == 3, let m = Int(parts[1]), (1...12).contains(m), let d = Int(parts[2])
        else { return iso }
        return "\(monthAbbr[m - 1]) \(d)"
    }

    /// "Jul 5 ’25" — used only when the window straddles a year boundary.
    static func labelWithYear(_ iso: String) -> String {
        let parts = iso.prefix(10).split(separator: "-")
        guard parts.count == 3, let y = Int(parts[0]) else { return shortLabel(iso) }
        return "\(shortLabel(iso)) ’\(String(format: "%02d", y % 100))"
    }
}

// MARK: - The read

/// The computed lede. Every string here is a function of the same buckets the
/// chart draws — three hand-written headlines had to be thrown away once
/// because they contradicted the charts beneath them, and prose written once
/// and rendered forever drifts silently.
struct TrendsSignalRead {

    /// Mileage moves smaller than this (percent, front half to back) are
    /// noise, and the screen says so. This is the most important threshold on
    /// the surface: it's the difference between a tool that observes and one
    /// that manufactures signal.
    ///
    /// It used to threshold the recovery delta. The recovery score was cut on
    /// 2026-08-24 — a lede that keyed off it was asserting a direction the
    /// number could not support.
    static let noiseThreshold = 8.0

    let headline: String
    /// The coral-emphasised tail of the headline, if any.
    let headlineAccent: String
    let note: String
    let dateRange: String
    let findings: [Finding]

    struct Finding: Identifiable {
        let id = UUID()
        let text: String
        let meta: String
        let tone: Tone

        enum Tone { case niggle, mood, neutral }
    }

    static func compute(_ set: TrendsBucketSet) -> TrendsSignalRead {
        guard !set.buckets.isEmpty, let firstDay = set.days.first, let lastDay = set.days.last else {
            return TrendsSignalRead(
                headline: "Not enough logged yet.",
                headlineAccent: "",
                note: "The signal chart needs a few days of runs or voice logs before it can say anything.",
                dateRange: "",
                findings: []
            )
        }

        // Date range — years only when the window straddles one.
        let spansYear = String(firstDay.date.prefix(4)) != String(lastDay.date.prefix(4))
        let range = spansYear
            ? "\(TrendsSignalBuilder.labelWithYear(firstDay.date)) – \(TrendsSignalBuilder.labelWithYear(lastDay.date))"
            : "\(TrendsSignalBuilder.shortLabel(firstDay.date)) – \(TrendsSignalBuilder.shortLabel(lastDay.date))"

        // Back half vs front half.
        let half = set.buckets.count / 2
        let front = Array(set.buckets.prefix(half))
        let back = Array(set.buckets.suffix(set.buckets.count - half))
        let milesFront = mean(front.map(\.miles))
        let milesBack = mean(back.map(\.miles))
        let dMiles = milesFront > 0 ? (milesBack - milesFront) / milesFront * 100 : 0

        let headline: String
        let accent: String
        let note: String

        // Load only. What the load COST is a question for the nightly signals,
        // read one at a time against their own baselines — not for a lede.
        if abs(dMiles) < noiseThreshold {
            headline = "Steady"
            accent = "through the window."
            note = "Mileage moved \(signed(dMiles))% front half to back — inside the noise on this measure. Nothing is proven here."
        } else if dMiles > 0 {
            headline = "Load's climbing."
            accent = "\(Int(dMiles.rounded()))% in the back half."
            note = "The back half of this window carries \(Int(dMiles.rounded()))% more mileage than the front."
        } else {
            headline = "Load eased off."
            accent = "\(Int(abs(dMiles).rounded()))% down."
            note = "The back half of this window carries \(Int(abs(dMiles).rounded()))% less mileage than the front."
        }

        return TrendsSignalRead(
            headline: headline,
            headlineAccent: accent,
            note: note,
            dateRange: range,
            findings: findings(set)
        )
    }

    // MARK: Findings — small n gets named, never inflated

    private static func findings(_ set: TrendsBucketSet) -> [Finding] {
        var out: [Finding] = []
        let dayCount = set.days.count

        // 1 · Do body mentions track the hard days?
        //
        // Computed off `buckets`, not `days`, because the bucket carries the
        // derived `TrendsSessionChannel` — the raw `TrendsDay.type` gives
        // `long` precedence over `key`, so counting off it would silently miss
        // every long run that carried quality work. Those are among the hardest
        // sessions in a block and exactly the ones a niggle is likely to follow.
        let mentionCount = set.niggleMentionCount
        if mentionCount == 0 {
            out.append(Finding(
                text: "No body mentions in this window. Absence is a real finding, not an empty state.",
                meta: "0 of \(dayCount) days",
                tone: .neutral
            ))
        } else if set.grain == .week {
            // At weekly buckets, "the day after a key session" isn't resolvable.
            // Say what we can count, and name where the detail lives.
            let weeksWith = set.buckets.filter(\.hasNiggle).count
            out.append(Finding(
                text: "\(mentionCount) body mention\(mentionCount == 1 ? "" : "s") across \(set.buckets.count) weeks, in \(weeksWith) of them. Whether they land on your key sessions needs day-level detail — that's the 1-month or 3-month view.",
                meta: "\(set.niggleAreas.count) area\(set.niggleAreas.count == 1 ? "" : "s") · weekly buckets",
                tone: .niggle
            ))
        } else {
            let mentionBuckets = set.buckets.filter(\.hasNiggle)
            if mentionBuckets.count <= 3 {
                // Small n — name them in full rather than reporting a
                // percentage off three data points.
                let named = mentionBuckets.map { b -> String in
                    switch b.channel {
                    case .keyLong: "\(b.label) (a long run with key work)"
                    case .key: "\(b.label) (a key session)"
                    case .long: "\(b.label) (a long run)"
                    default: b.label
                    }
                }.joined(separator: ", ")
                out.append(Finding(
                    text: "Body mentions: \(mentionBuckets.count) of \(dayCount) days — \(named). "
                        + (mentionBuckets.count == 1 ? "One isn't a pattern." : "Too few to call a pattern."),
                    meta: "Small n · named in full",
                    tone: .niggle
                ))
            } else {
                // A mention counts as session-linked if its own day carried key
                // work, or the previous day did.
                var linked = 0
                for (idx, b) in set.buckets.enumerated() where b.hasNiggle {
                    let ownIsKey = b.channel.isKey
                    let prevIsKey = idx > 0 && set.buckets[idx - 1].channel.isKey
                    if ownIsKey || prevIsKey { linked += 1 }
                }
                let pct = Int((Double(linked) / Double(mentionBuckets.count) * 100).rounded())
                out.append(Finding(
                    text: pct >= 60
                        ? "\(pct)% of body mentions land on a key session day or the day after. That's where they cluster."
                        : "Body mentions don't track your key sessions — only \(pct)% fall on one or the day after. Your niggles aren't following the hard days.",
                    meta: "\(linked) of \(mentionBuckets.count) days · session-linked",
                    tone: .niggle
                ))
            }
        }

        // 2 · Mood, with a coverage guard first.
        let logged = set.moodLoggedDays
        if logged < dayCount / 2 {
            out.append(Finding(
                text: "Mood is logged on \(logged) of \(dayCount) days. Under half the window carries a check-in, so read the mood lane as a sample, not the month.",
                meta: "Coverage \(Int((Double(logged) / Double(max(1, dayCount)) * 100).rounded()))%",
                tone: .neutral
            ))
        } else {
            let low = set.days.filter {
                guard let m = $0.mood?.lowercased() else { return false }
                return m == "tired" || m == "struggling" || m == "injured"
            }.count
            let pct = logged > 0 ? Int((Double(low) / Double(logged) * 100).rounded()) : 0
            out.append(Finding(
                text: pct >= 45
                    ? "\(pct)% of logged days read tired or harder. In your own words, that's most of the window."
                    : "\(pct)% of logged days read tired or harder — the rest sit neutral or better.",
                meta: "\(logged) of \(dayCount) days logged",
                tone: .mood
            ))
        }

        // 3 · Days off — counted, never judged.
        let rest = set.restDays
        out.append(Finding(
            text: rest == 0
                ? "No full day off in this window."
                : "\(rest) full days off across \(dayCount) days — one every \(String(format: "%.1f", Double(dayCount) / Double(rest))) days on average.",
            meta: "Days off · counted, not judged",
            tone: .neutral
        ))

        return out
    }

    private static func mean(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }

    private static func signed(_ v: Double) -> String {
        (v >= 0 ? "+" : "−") + String(format: "%.1f", abs(v))
    }
}
