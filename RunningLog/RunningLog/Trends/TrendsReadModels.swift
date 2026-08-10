//
//  TrendsReadModels.swift
//  RunningLog · Trends
//
//  Pure. The Read — a templated headline, a templated story, and a month
//  grid — computed from the same `TrendsDay` substrate the Trends tab
//  already fetches. No view code, no formatting of colour, no LLM.
//
//  Why templated and not narrated (design-system/explorations,
//  `trends-headline-system-2026-08-06.html`): the old headline —
//  *"You're coming back up."* — was a verdict about the athlete with no
//  numeral in it, so nothing could check it and a calf flare the next day
//  read as a promise the app broke. Every string this builder emits names a
//  signal, states a direction, and carries a number that came from the
//  window in view. That makes the headline a unit test, not an eval.
//
//  The line the copy cannot cross, enforced by construction here:
//  • No second person. The Read describes data, never Maya.
//  • No trajectory words — "coming back", "turning a corner". Thirty days
//    of past does not license a forecast.
//  • No praise and no consolation. Observation over congratulation.
//  • No numeral that is not computed below.
//  • Niggles are surfaced, never interpreted — count, area and recency
//    only, never severity (CLAUDE.md, surface-not-diagnose).
//
//  A beat is emitted only when its condition holds. A quiet window
//  produces a short story rather than a padded one, and a window with
//  almost nothing in it produces the empty-state headline instead of a
//  verdict on four runs.
//

import Foundation

// MARK: - The Read

/// One window's read. Everything the Read surface draws, already computed.
struct TrendsRead {
    /// Templated. Sentence case, terminal period — the house display form
    /// ("Pace, narrated." / "Active aches.").
    let headline: String

    /// The mono fact line under the headline. Middle-dot separated, the
    /// canonical PRD separator. Empty when the window is too thin to state
    /// anything.
    let subline: String

    /// The story, in order. Rendered as one paragraph; each beat may carry
    /// a callout numeral that also lands on a day in `weeks`.
    let beats: [Beat]

    /// Calendar rows, Monday-first, with leading/trailing padding so the
    /// weekday columns line up without gap-filling on device.
    let weeks: [MonthWeek]

    /// Mood tallies for the key under the grid, most frequent first. Only
    /// words that actually occur — never a zero row.
    let moodCounts: [(mood: String, count: Int)]

    /// True when the window has too few runs to say anything. The view
    /// draws the empty state and no figure.
    let isThin: Bool

    // MARK: Lanes

    /// The recovery score for each day of the month, from the canonical
    /// `TrendsRecoveryLedger`. **Computed over the whole history and then
    /// sliced** — the score at any day reads a trailing window, so building
    /// it from one month alone would starve the first days of the month.
    let recovery: [LanePoint]

    /// Trailing-7-day mileage per day. This is *not* an acute:chronic
    /// ratio: `recovery-trend-v2-2026-07-27` §7.1 dismantled ACWR (coupling
    /// yields r = 0.52 from arithmetic alone; the only RCT was null), and
    /// `TrendsRecoveryLedger` states the replacement — load is measured
    /// against **the athlete's own 8-week average**. That average is
    /// `loadBaseline`, drawn as the reference line.
    let load: [LanePoint]

    /// Mean trailing-7-day mileage across the 8 weeks before this month
    /// ends. `nil` when there isn't 8 weeks of history to average.
    let loadBaseline: Double?

    /// Latest recovery score in the month, and its band word
    /// (`Flat` · `Worn` · `Steady` · `Clear`).
    let recoveryNow: Int?
    let recoveryBand: String?

    struct LanePoint: Identifiable {
        let id = UUID()
        let date: String
        let value: Double
    }

    // MARK: Beat

    /// One sentence of the story. `callout` ties it to a day in the grid.
    struct Beat {
        let text: String
        let callout: Int?
    }

    // MARK: Month grid

    struct MonthDay: Identifiable {
        let id = UUID()
        /// "yyyy-MM-dd", the same key `TrendsDay` carries.
        let date: String
        /// Day of month, the numeral drawn top-left.
        let dayOfMonth: Int
        /// Deduped miles. 0 on a rest day — the cell draws as a well.
        let miles: Double
        /// Closed-vocabulary mood, or nil when no feeling was logged. Never
        /// fabricated: a rest day with no check-in carries none.
        let mood: String?
        /// A key session landed here — drawn as the star.
        let isKey: Bool
        /// A body mention landed here — the date numeral goes coral.
        let hasNiggle: Bool
        /// Work-zone token (mile | 3k | 5k | 10k | hmp | mp) when a
        /// classified key session landed here, else nil.
        ///
        /// **Only key sessions carry a zone.** `TrendsDay.type` is a session
        /// channel, not a pace — an easy day has no classified pace anywhere
        /// in the payload, so the bar for it is drawn neutral rather than
        /// tinted with a pace we do not have.
        let zoneToken: String?
        /// Story callout that points at this day, if any.
        let callout: Int?
    }

    struct MonthWeek: Identifiable {
        let id = UUID()
        /// Seven slots, Monday-first. `nil` = outside the window.
        let days: [MonthDay?]
        /// Miles inside the window for this row — the margin tally.
        let miles: Double
    }
}

// MARK: - One month of the payload

/// A single calendar month, sliced out of the timeline.
///
/// The Read is a **month at a time**. The service hands back the whole
/// window it fetched — six months of `days` — and a read over all of it is
/// not a read: 180 bars land inside each other, the grid becomes an
/// endless scroll, and the headline sums a number ("1302 miles") no
/// athlete has a feel for. One month is the unit the athlete already
/// thinks in, it is what the grid draws, and it is what the deltas mean.
struct TrendsReadWindow: Identifiable {
    /// The window's end day key — unique, and sorts chronologically.
    let id: String
    /// "Jul 9 – Aug 7". En-dash for the range, per the house rules.
    let title: String
    /// Days in the window, oldest first.
    let days: [TrendsDay]
}

/// A calendar month of the payload.
///
/// Distinct from `TrendsReadWindow`'s rolling 30 days, and both are needed: a
/// rolling window is the honest unit for "the last month of training", but the
/// grid draws real weekday columns under a heading that says July, so what it
/// slices has to be July.
struct TrendsReadMonth: Identifiable {
    /// "2026-08" — sorts chronologically and keys the grid.
    let id: String
    /// "August 2026".
    let title: String
    /// Days in the month, oldest first.
    let days: [TrendsDay]
}

// MARK: - Builder

enum TrendsReadBuilder {

    // MARK: Dates

    /// UTC, ISO-8601 week rules (Monday first) — the same day key the
    /// timeline is built on, so a day can never land in the wrong column.
    private static var calendar: Calendar {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return c
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let shortFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d"
        return f
    }()

    private static let monthTitleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    static func date(_ key: String) -> Date? { dayFormatter.date(from: key) }

    // MARK: Months

    /// The payload split into calendar months, **newest month first**, each
    /// month's days oldest first.
    ///
    /// Every day lands in exactly one month and none are dropped, which is the
    /// property that matters: a read scoped to a month must sum that month and
    /// nothing else. Summing the payload instead was the six-month bug — 180
    /// days at 8 miles announcing "1440 mi" under a heading that said July.
    ///
    /// Keys are sliced off the day string rather than reconstructed through a
    /// `DateComponents` round-trip. The day key is already `yyyy-MM-dd` in UTC,
    /// so its first seven characters ARE the month key, and going via `Date`
    /// only adds a timezone that could move a day across a boundary.
    static func months(_ days: [TrendsDay]) -> [TrendsReadMonth] {
        let grouped = Dictionary(grouping: days) { String($0.date.prefix(7)) }
        return grouped.keys.sorted(by: >).map { key in
            TrendsReadMonth(
                id: key,
                title: date("\(key)-01").map { monthTitleFormatter.string(from: $0) } ?? key,
                days: (grouped[key] ?? []).sorted { $0.date < $1.date }
            )
        }
    }

    /// Rolling **30-day** windows, newest first, each one stepped back a
    /// month from the last.
    ///
    /// Not calendar months. A calendar month means the current one is
    /// always partial — on the 7th the surface would draw 7 bars, two grid
    /// rows and a one-sentence story, which reads as a broken screen rather
    /// than an early month. The window is always the same length, so the
    /// figure, the grid and the deltas are always comparable; stepping back
    /// moves it a month at a time, which is the interval the athlete asked
    /// to travel in.
    static func windows(_ days: [TrendsDay], length: Int = 30) -> [TrendsReadWindow] {
        let sorted = days.sorted { $0.date < $1.date }
        guard let firstKey = sorted.first?.date,
              let lastKey = sorted.last?.date,
              let firstDay = date(firstKey),
              var end = date(lastKey)
        else { return [] }

        let cal = calendar
        var out: [TrendsReadWindow] = []

        while end >= firstDay {
            guard let start = cal.date(byAdding: .day, value: -(length - 1), to: end)
            else { break }

            let startKey = dayFormatter.string(from: start)
            let endKey = dayFormatter.string(from: end)
            let slice = sorted.filter { $0.date >= startKey && $0.date <= endKey }

            // A window with nothing in it means we've walked off the back of
            // the payload — stop rather than emitting empty pages.
            if slice.isEmpty { break }

            out.append(
                TrendsReadWindow(
                    id: endKey,
                    title: "\(label(startKey)) – \(label(endKey))",
                    days: slice
                )
            )

            guard let stepped = cal.date(byAdding: .month, value: -1, to: end) else { break }
            end = stepped
        }
        return out
    }

    /// "Jul 15" — the label the story and the axis both use.
    static func label(_ key: String) -> String {
        guard let d = date(key) else { return key }
        return shortFormatter.string(from: d)
    }

    // MARK: Entry point

    /// Build the Read for `days`, in window order (oldest first).
    ///
    /// `keySessions` supplies the only classified pace in the payload; days
    /// without one are drawn neutral. Passing an empty array is valid and
    /// simply means no bar is tinted.
    static func build(days: [TrendsDay], keySessions: [KeySession] = []) -> TrendsRead {
        build(month: days, history: days, keySessions: keySessions)
    }

    /// Build the Read for `month`, using `history` for anything that needs a
    /// trailing window (the recovery ledger, the 8-week load baseline).
    ///
    /// Keeping the two separate is not tidiness: recovery at a given day
    /// reads backwards, so handing the ledger a single month would give the
    /// 1st of the month no history and quietly bias the first week low.
    static func build(
        month: [TrendsDay], history: [TrendsDay], keySessions: [KeySession] = []
    ) -> TrendsRead {
        let past = history.sorted { $0.date < $1.date }
        let monthDates = Set(month.map(\.date))

        // Recovery — canonical ledger, over the full history, then sliced.
        let ledgers = TrendsRecoveryLedger.series(days: past)
        // `uniquingKeysWith`, not `uniqueKeysWithValues`: the timeline is
        // meant to be one row per day, but a duplicate key would *trap* on
        // the strict initialiser and take the tab down. First value wins.
        let scoreByDate = Dictionary(
            zip(past, ledgers).map { ($0.date, $1.total) },
            uniquingKeysWith: { first, _ in first }
        )
        let recovery = past
            .filter { monthDates.contains($0.date) }
            .compactMap { day in
                scoreByDate[day.date].map { LanePointBox(date: day.date, value: Double($0)) }
            }

        // Load — trailing 7-day mileage, and the athlete's own 8-week mean.
        let rolling = trailingSeven(past)
        let load = past
            .filter { monthDates.contains($0.date) }
            .compactMap { day in
                rolling[day.date].map { LanePointBox(date: day.date, value: $0) }
            }
        let baseline = eightWeekBaseline(past, rolling: rolling, upTo: month.map(\.date).max())

        return assemble(
            month: month,
            keySessions: keySessions,
            recovery: recovery.map { TrendsRead.LanePoint(date: $0.date, value: $0.value) },
            load: load.map { TrendsRead.LanePoint(date: $0.date, value: $0.value) },
            loadBaseline: baseline,
            recoveryNow: recovery.last.map { Int($0.value) },
            recoveryBand: recovery.last.map {
                TrendsRecoveryLedger.Band.of(Int($0.value)).rawValue
            }
        )
    }

    /// Internal carrier so the lane maths doesn't allocate `LanePoint`
    /// (which owns a `UUID`) twice per day.
    private struct LanePointBox {
        let date: String
        let value: Double
    }

    /// Trailing-7-day mileage, keyed by day. A day with fewer than 7 days of
    /// history behind it is omitted rather than averaged over a short
    /// window — a half-filled trailing sum is not the same measurement.
    private static func trailingSeven(_ days: [TrendsDay]) -> [String: Double] {
        var out: [String: Double] = [:]
        guard days.count >= 7 else { return out }
        for i in 6 ..< days.count {
            out[days[i].date] = days[(i - 6) ... i].reduce(0) { $0 + $1.miles }
        }
        return out
    }

    /// Mean trailing-7 across the 56 days ending at `end`. `nil` when the
    /// history is too short to be an 8-week average — the reference line is
    /// then simply not drawn, rather than drawn from four weeks and called
    /// eight.
    private static func eightWeekBaseline(
        _ days: [TrendsDay], rolling: [String: Double], upTo end: String?
    ) -> Double? {
        guard let end else { return nil }
        let window = days.filter { $0.date <= end }.suffix(56)
        guard window.count == 56 else { return nil }
        let values = window.compactMap { rolling[$0.date] }
        guard values.count >= 28 else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func assemble(
        month days: [TrendsDay],
        keySessions: [KeySession],
        recovery: [TrendsRead.LanePoint],
        load: [TrendsRead.LanePoint],
        loadBaseline: Double?,
        recoveryNow: Int?,
        recoveryBand: String?
    ) -> TrendsRead {
        let ordered = days.sorted { $0.date < $1.date }
        let runDays = ordered.filter { $0.miles > 0 }

        // Too thin to read. Five running days is the floor: below it a
        // 30-day delta is one workout's worth of noise, and the honest
        // thing is to say so rather than rank signals.
        guard runDays.count >= 5 else {
            return TrendsRead(
                headline: "Not enough logged yet.",
                subline: "",
                beats: [TrendsRead.Beat(
                    text: "Five runs in the window turns this on. "
                        + "Right now there are \(runDays.count).",
                    callout: nil
                )],
                weeks: monthWeeks(ordered, callouts: [:], zones: [:]),
                moodCounts: [],
                isThin: true,
                recovery: recovery,
                load: load,
                loadBaseline: loadBaseline,
                recoveryNow: recoveryNow,
                recoveryBand: recoveryBand
            )
        }

        let zones = zoneByDate(keySessions)
        let totalMiles = ordered.reduce(0) { $0 + $1.miles }
        let keyCount = ordered.filter { $0.type == .key }.count
        let moodCounts = tally(ordered)

        // ---- callouts, in the order the story tells them -----------------
        var callouts: [String: Int] = [:]
        var beats: [TrendsRead.Beat] = []
        var next = 1

        // 1 · a rough opening — two or more low logs inside the first five days
        let opening = ordered.prefix(5).filter { isLow($0.mood) }
        if opening.count >= 2, let first = opening.first {
            callouts[first.date] = next
            beats.append(.init(
                text: "The window opened rough — \(opening.count) "
                    + "\(opening.count == 1 ? "log" : "logs") in the first five days.",
                callout: next
            ))
            next += 1
        }

        // 2 · niggles — count, area, recency. Never severity.
        let niggleDays = ordered.filter { !$0.niggles.isEmpty }
        if let firstNiggle = niggleDays.first {
            let top = dominantArea(niggleDays)
            let area = top?.label ?? "a niggle"
            let mentions = top?.count ?? niggleDays.reduce(0) { $0 + $1.niggles.count }
            callouts[firstNiggle.date] = next
            let quiet = daysSince(niggleDays.last?.date, in: ordered)
            beats.append(.init(
                text: quiet >= 7
                    ? "\(area.capitalizedFirst) came up \(mentions) "
                        + "\(mentions == 1 ? "time" : "times"), last on "
                        + "\(label(niggleDays.last?.date ?? firstNiggle.date))."
                    : "\(area.capitalizedFirst) came up \(mentions) "
                        + "\(mentions == 1 ? "time" : "times"), most recently "
                        + "\(label(niggleDays.last?.date ?? firstNiggle.date)).",
                callout: next
            ))
            next += 1
        }

        // 3 · the work underneath — always true, always numbers
        beats.append(.init(
            text: "Underneath it the work held: \(miles(totalMiles)) miles, "
                + "\(keyCount) key \(keyCount == 1 ? "session" : "sessions").",
            callout: nil
        ))

        // 4 · the last low log, when the tail is genuinely clear
        if let lastLow = ordered.last(where: { isLow($0.mood) }),
           daysSince(lastLow.date, in: ordered) >= 7 {
            callouts[lastLow.date] = next
            beats.append(.init(
                text: "\(label(lastLow.date)) was the last low log.",
                callout: next
            ))
            next += 1
        }

        return TrendsRead(
            headline: headline(ordered, niggleDays: niggleDays, totalMiles: totalMiles),
            subline: subline(totalMiles: totalMiles, keyCount: keyCount,
                             moodLogged: ordered.filter { $0.mood != nil }.count,
                             windowDays: ordered.count),
            beats: beats,
            weeks: monthWeeks(ordered, callouts: callouts, zones: zones),
            moodCounts: moodCounts,
            isThin: false,
            recovery: recovery,
            load: load,
            loadBaseline: loadBaseline,
            recoveryNow: recoveryNow,
            recoveryBand: recoveryBand
        )
    }

    // MARK: Headline

    /// Priority order: a live niggle outranks any good news above it, then
    /// the signal that moved most, then a flat window.
    private static func headline(
        _ days: [TrendsDay], niggleDays: [TrendsDay], totalMiles: Double
    ) -> String {
        // Alert first.
        if let last = niggleDays.last, daysSince(last.date, in: days) < 7 {
            let top = dominantArea(niggleDays)
            let area = top?.label ?? "Niggle"
            let mentions = top?.count ?? niggleDays.reduce(0) { $0 + $1.niggles.count }
            return "\(area.capitalizedFirst), \(mentions) "
                + "\(mentions == 1 ? "mention" : "mentions")."
        }

        // Volume, back half against front half.
        let half = days.count / 2
        let front = days.prefix(half).reduce(0) { $0 + $1.miles }
        let back = days.suffix(days.count - half).reduce(0) { $0 + $1.miles }
        if front > 0 {
            let pct = Int(((back - front) / front * 100).rounded())
            if abs(pct) >= 10 {
                return "Volume, \(pct > 0 ? "up" : "down") \(abs(pct))%."
            }
        }
        return "A flat \(days.count) days."
    }

    private static func subline(
        totalMiles: Double, keyCount: Int, moodLogged: Int, windowDays: Int
    ) -> String {
        "\(miles(totalMiles)) mi · \(keyCount) key · \(moodLogged)/\(windowDays) logged"
    }

    // MARK: Month grid

    private static func monthWeeks(
        _ days: [TrendsDay], callouts: [String: Int], zones: [String: String]
    ) -> [TrendsRead.MonthWeek] {
        let cal = calendar
        guard let first = days.first.flatMap({ date($0.date) }),
              let last = days.last.flatMap({ date($0.date) })
        else { return [] }

        // Monday on or before the first day; Sunday on or after the last.
        let startOfWeek = cal.dateInterval(of: .weekOfYear, for: first)?.start ?? first
        let endOfWeek = cal.dateInterval(of: .weekOfYear, for: last)?.end ?? last

        let byDate = Dictionary(uniqueKeysWithValues: days.map { ($0.date, $0) })

        var weeks: [TrendsRead.MonthWeek] = []
        var cursor = startOfWeek

        while cursor < endOfWeek {
            var slots: [TrendsRead.MonthDay?] = []
            var rowMiles = 0.0

            for offset in 0 ..< 7 {
                guard let slotDate = cal.date(byAdding: .day, value: offset, to: cursor)
                else { slots.append(nil); continue }
                let key = dayFormatter.string(from: slotDate)

                guard let day = byDate[key] else { slots.append(nil); continue }

                rowMiles += day.miles
                slots.append(
                    TrendsRead.MonthDay(
                        date: key,
                        dayOfMonth: cal.component(.day, from: slotDate),
                        miles: day.miles,
                        mood: day.mood,
                        isKey: day.type == .key,
                        hasNiggle: !day.niggles.isEmpty,
                        zoneToken: zones[key],
                        callout: callouts[key]
                    )
                )
            }

            weeks.append(.init(days: slots, miles: rowMiles))
            guard let nextWeek = cal.date(byAdding: .day, value: 7, to: cursor) else { break }
            cursor = nextWeek
        }
        return weeks
    }

    // MARK: Helpers

    /// The two words the closed mood vocabulary treats as low. `injured`
    /// is deliberately not folded in — it is an alert, not a mood beat, and
    /// it belongs to the niggle line.
    private static func isLow(_ mood: String?) -> Bool {
        guard let m = mood?.lowercased() else { return false }
        return m == "struggling" || m == "tired"
    }

    /// Whole miles. The Read never shows a decimal — a tenth of a mile is
    /// below the resolution of any claim on this surface.
    private static func miles(_ v: Double) -> String { String(Int(v.rounded())) }

    /// Days between `key` and the end of the window.
    private static func daysSince(_ key: String?, in days: [TrendsDay]) -> Int {
        guard let key, let from = date(key),
              let lastKey = days.last?.date, let to = date(lastKey)
        else { return .max }
        return calendar.dateComponents([.day], from: from, to: to).day ?? .max
    }

    /// Most-mentioned body area **and its own mention count**.
    ///
    /// The count travels with the label deliberately. Both callers used to name
    /// this area and then quote `niggleDays.reduce(0) { $0 + $1.niggles.count }`
    /// beside it — every mention in the window, whatever the body part. One calf
    /// mention and one knee mention rendered as "Left calf, 2 mentions", which
    /// is not a rounding difference but a false statement about the calf. The
    /// niggle rules are explicit that the surface reports what was said and
    /// where; a count that silently spans other body parts reports neither.
    private static func dominantArea(_ days: [TrendsDay]) -> (label: String, count: Int)? {
        var counts: [String: Int] = [:]
        var order: [String] = []
        for day in days {
            for niggle in day.niggles {
                let area = [niggle.side, niggle.area]
                    .compactMap { $0?.isEmpty == false ? $0 : nil }
                    .joined(separator: " ")
                let label = area.isEmpty ? niggle.area : area
                if counts[label] == nil { order.append(label) }
                counts[label, default: 0] += 1
            }
        }
        // Most mentions wins; a tie goes to whichever appeared first, so the
        // same window always names the same area.
        let winner = order.max { a, b in
            let countA = counts[a] ?? 0
            let countB = counts[b] ?? 0
            if countA != countB { return countA < countB }
            let firstA = order.firstIndex(of: a) ?? 0
            let firstB = order.firstIndex(of: b) ?? 0
            return firstA > firstB
        }
        return winner.map { ($0, counts[$0] ?? 0) }
    }

    private static func tally(_ days: [TrendsDay]) -> [(mood: String, count: Int)] {
        var counts: [String: Int] = [:]
        for day in days {
            guard let m = day.mood?.lowercased() else { continue }
            counts[m, default: 0] += 1
        }
        return TrendsMoodColor.ordered
            .compactMap { m in counts[m].map { (mood: m, count: $0) } }
            .sorted { $0.count > $1.count }
    }

    /// date → work-zone token, for the days that carry a classified session.
    private static func zoneByDate(_ sessions: [KeySession]) -> [String: String] {
        var out: [String: String] = [:]
        for s in sessions where !s.isLongRun {
            out[s.date] = s.zone.lowercased()
        }
        return out
    }
}

// MARK: - Small string helper

private extension String {
    /// Sentence case for a verbatim body area at the head of a sentence.
    /// Only the first character is touched — the athlete's own words are
    /// never re-cased beyond that.
    var capitalizedFirst: String {
        guard let f = first else { return self }
        return String(f).uppercased() + dropFirst()
    }
}
