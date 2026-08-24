//
//  NiggleTimeline.swift
//  RunningLog
//
//  The niggle mention-timeline — derivation only, no UI, no interpretation.
//
//  Ported from the web prototype at `web/src/app/design/niggles/niggles-data.ts`
//  (see `outputs/niggles-v2-dashboard-2026-08-23.md` for the contract). The
//  prototype ran on mock rows; this runs on the real `body_mentions` and
//  `niggle_resolutions` that `InjuryService` already loads.
//
//  Everything here is a MECHANICAL derivation from dates and mileage. Per the
//  Niggles rules in CLAUDE.md the system reports what was said and when, never
//  what it means. "Quiet" is deliberately not "healed" — we do not know that.
//
//  Two deliberate departures from the prototype, both noted in the handoff:
//
//   1. Volume bands are athlete-referenced (terciles of this athlete's own
//      non-empty weeks), not the prototype's hardcoded 45/55 mi cuts. Those
//      were Maya's numbers; they would be meaningless for a 20 mi/wk runner.
//   2. The session-label tally (prototype Fig. 03a — "6 of 7 after long runs")
//      is NOT built here. It needs a session label per day, and
//      `fetchTrainingDays` only selects distance. Volume-band tallies carry
//      the co-occurrence figure until that fetch is widened.
//

import Foundation

// MARK: - Rules

enum NiggleRule {
    /// A mention this recent keeps a thread active.
    static let activeWindowDays = 14
    /// A gap this long before a mention reads as a return, not a continuation.
    static let recurrenceGapDays = 21
    /// How far back the timeline looks.
    static let windowWeeks = 16
    /// A tally needs at least this many mentions before it renders as a
    /// pattern. Handoff §5.2: a single data point must never read as one.
    static let minTallyMentions = 3
}

// MARK: - Values

enum NiggleSide: String {
    case left, right, both, unspecified

    init(raw: String?) {
        switch (raw ?? "").lowercased() {
        case "left", "l":   self = .left
        case "right", "r":  self = .right
        case "both":        self = .both
        default:            self = .unspecified
        }
    }

    /// Label prefix. Unspecified contributes nothing rather than "Unspecified".
    var prefix: String {
        switch self {
        case .left: return "L."
        case .right: return "R."
        case .both: return "Both"
        case .unspecified: return ""
        }
    }
}

enum NiggleThreadStatus: Int {
    /// Sort rank doubles as the raw value: active first, resolved last.
    case active = 0, quiet = 1, resolved = 2

    var label: String {
        switch self {
        case .active: return "ACTIVE"
        case .quiet: return "QUIET"
        case .resolved: return "RESOLVED"
        }
    }
}

struct NiggleMention: Identifiable, Equatable {
    let id: UUID
    let bodyArea: String
    let side: NiggleSide
    /// The athlete's own words. Never paraphrased, never scored.
    let quote: String?
    let severityHint: String?
    /// UTC start-of-day, to line up with the bare DATE `mentioned_at`.
    let mentionedAt: Date
}

/// A gap long enough that the ache reads as having come back.
struct NiggleReturn: Equatable {
    let afterDays: Int
    let on: Date
}

/// Every mention of one body area + side, in date order.
struct NiggleThread: Identifiable, Equatable {
    let id: String
    let bodyArea: String
    let side: NiggleSide
    let label: String
    let status: NiggleThreadStatus
    let mentions: [NiggleMention]
    let resolvedAt: Date?
    let resolutionQuote: String?
    let firstSeen: Date
    let lastSeen: Date
    let spanDays: Int
    let daysSinceLast: Int
    let returns: [NiggleReturn]

    var mentionCount: Int { mentions.count }
    var lastQuote: String? { mentions.last?.quote }
}

/// One week of the training overlay. Volume only — this is the athlete's own
/// mileage, not a derived load score.
struct NiggleWeek: Identifiable, Equatable {
    let start: Date
    let miles: Double
    /// The in-progress week. Drawn lighter, never darker: an incomplete week
    /// must not read as more solid than a finished one.
    let partial: Bool

    var id: Date { start }
}

struct NiggleTally: Identifiable, Equatable {
    let label: String
    let count: Int
    var id: String { label }
}

// MARK: - The timeline

struct NiggleTimeline: Equatable {
    let threads: [NiggleThread]
    let weeks: [NiggleWeek]
    let spanStart: Date
    let spanEnd: Date
    /// Mentions per week, index-aligned with `weeks`. Drives the sparkline.
    let mentionsPerWeek: [Int]
    /// Athlete-referenced volume bands. Empty when there is too little
    /// mileage history to cut terciles that mean anything.
    let volumeBands: [NiggleTally]

    var isEmpty: Bool { threads.isEmpty }
    var activeCount: Int { threads.filter { $0.status == .active }.count }
    var quietCount: Int { threads.filter { $0.status == .quiet }.count }
    var resolvedCount: Int { threads.filter { $0.status == .resolved }.count }
    var returnCount: Int { threads.reduce(0) { $0 + $1.returns.count } }
    var totalMentions: Int { threads.reduce(0) { $0 + $1.mentionCount } }

    static let empty = NiggleTimeline(
        threads: [], weeks: [], spanStart: .distantPast, spanEnd: .distantPast,
        mentionsPerWeek: [], volumeBands: []
    )
}

// MARK: - Build

enum NiggleTimelineBuilder {

    static var utcCalendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC") ?? .current
        // Weeks start Monday, matching the prototype and the rest of the app.
        c.firstWeekday = 2
        return c
    }()

    static func days(from a: Date, to b: Date) -> Int {
        utcCalendar.dateComponents([.day], from: a, to: b).day ?? 0
    }

    /// Monday of the week containing `date`, at UTC start-of-day.
    static func weekStart(of date: Date) -> Date {
        let c = utcCalendar
        let comps = c.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return c.date(from: comps) ?? c.startOfDay(for: date)
    }

    static func titleCase(_ part: String) -> String {
        // The one body area whose casing is not simple capitalisation.
        if part.lowercased() == "it band" { return "IT band" }
        return part.prefix(1).uppercased() + part.dropFirst()
    }

    /// Builds the whole timeline. Pure: same inputs, same output.
    ///
    /// - Parameters:
    ///   - mentions: every `body_mentions` row, any order.
    ///   - resolutions: `niggle_resolutions`, keyed by area+side downstream.
    ///   - milesByDay: per-UTC-day run mileage, for the training overlay.
    ///   - today: the reference day. Injected so tests need no clock.
    static func build(
        mentions: [NiggleMention],
        resolutions: [(bodyArea: String, side: NiggleSide, resolvedAt: Date, quote: String?)],
        milesByDay: [Date: Double],
        today: Date
    ) -> NiggleTimeline {

        let todayDay = utcCalendar.startOfDay(for: today)
        let currentWeek = weekStart(of: todayDay)
        guard let spanStart = utcCalendar.date(
            byAdding: .weekOfYear, value: -(NiggleRule.windowWeeks - 1), to: currentWeek
        ) else { return .empty }

        // ── Weeks + overlay ────────────────────────────────────────────
        var weeks: [NiggleWeek] = []
        for i in 0..<NiggleRule.windowWeeks {
            guard let start = utcCalendar.date(byAdding: .weekOfYear, value: i, to: spanStart)
            else { continue }
            var miles = 0.0
            for d in 0..<7 {
                if let day = utcCalendar.date(byAdding: .day, value: d, to: start) {
                    miles += milesByDay[day] ?? 0
                }
            }
            weeks.append(NiggleWeek(start: start, miles: miles, partial: start == currentWeek))
        }

        // ── Threads ────────────────────────────────────────────────────
        // Scope to the window, but derive status from the mention's true
        // recency — an ache last mentioned 20 weeks ago is quiet, not absent.
        let inWindow = mentions.filter { $0.mentionedAt >= spanStart }

        var resolutionByKey: [String: (resolvedAt: Date, quote: String?)] = [:]
        for r in resolutions {
            let k = key(area: r.bodyArea, side: r.side)
            // Keep the most recent resolution per thread.
            if let existing = resolutionByKey[k], existing.resolvedAt >= r.resolvedAt { continue }
            resolutionByKey[k] = (r.resolvedAt, r.quote)
        }

        var groups: [String: [NiggleMention]] = [:]
        for m in inWindow {
            groups[key(area: m.bodyArea, side: m.side), default: []].append(m)
        }

        var threads: [NiggleThread] = []
        for (k, rows) in groups {
            let ordered = rows.sorted { $0.mentionedAt < $1.mentionedAt }
            guard let first = ordered.first, let lastMention = ordered.last else { continue }

            let resolution = resolutionByKey[k]
            // A resolution only closes the thread if nothing was said after it.
            let isResolved = (resolution?.resolvedAt).map { $0 >= lastMention.mentionedAt } ?? false

            let daysSinceLast = days(from: lastMention.mentionedAt, to: todayDay)
            let status: NiggleThreadStatus = isResolved
                ? .resolved
                : (daysSinceLast <= NiggleRule.activeWindowDays ? .active : .quiet)

            var returns: [NiggleReturn] = []
            for i in 1..<max(ordered.count, 1) {
                let gap = days(from: ordered[i - 1].mentionedAt, to: ordered[i].mentionedAt)
                if gap >= NiggleRule.recurrenceGapDays {
                    returns.append(NiggleReturn(afterDays: gap, on: ordered[i].mentionedAt))
                }
            }

            let prefix = first.side.prefix
            let name = titleCase(first.bodyArea)

            threads.append(NiggleThread(
                id: k,
                bodyArea: first.bodyArea,
                side: first.side,
                label: prefix.isEmpty ? name : "\(prefix) \(name)",
                status: status,
                mentions: ordered,
                resolvedAt: isResolved ? resolution?.resolvedAt : nil,
                resolutionQuote: isResolved ? resolution?.quote : nil,
                firstSeen: first.mentionedAt,
                lastSeen: lastMention.mentionedAt,
                spanDays: days(from: first.mentionedAt, to: lastMention.mentionedAt),
                daysSinceLast: daysSinceLast,
                returns: returns
            ))
        }

        // Active first, then most-recently-seen. Ties broken by label so the
        // order is stable across rebuilds (dictionary iteration is not).
        threads.sort {
            if $0.status != $1.status { return $0.status.rawValue < $1.status.rawValue }
            if $0.lastSeen != $1.lastSeen { return $0.lastSeen > $1.lastSeen }
            return $0.label < $1.label
        }

        // ── Sparkline ──────────────────────────────────────────────────
        var perWeek = [Int](repeating: 0, count: weeks.count)
        for t in threads {
            for m in t.mentions {
                let ws = weekStart(of: m.mentionedAt)
                if let idx = weeks.firstIndex(where: { $0.start == ws }) { perWeek[idx] += 1 }
            }
        }

        let allMentions = threads.flatMap(\.mentions)

        return NiggleTimeline(
            threads: threads,
            weeks: weeks,
            spanStart: spanStart,
            spanEnd: todayDay,
            mentionsPerWeek: perWeek,
            volumeBands: volumeBands(mentions: allMentions, weeks: weeks)
        )
    }

    static func key(area: String, side: NiggleSide) -> String {
        "\(area.lowercased())|\(side.rawValue)"
    }

    /// Counts mentions by the volume of the week they landed in, using bands
    /// cut from THIS athlete's own weeks (terciles of non-empty weeks). The
    /// prototype's fixed 45/55 mi cuts were one athlete's numbers.
    ///
    /// Returns empty when the evidence is too thin to read as a pattern —
    /// fewer than `minTallyMentions`, or a mileage spread too narrow to split.
    static func volumeBands(mentions: [NiggleMention], weeks: [NiggleWeek]) -> [NiggleTally] {
        guard mentions.count >= NiggleRule.minTallyMentions else { return [] }
        let run = weeks.filter { $0.miles > 0 }.map(\.miles).sorted()
        guard run.count >= 6 else { return [] }

        let low = run[run.count / 3]
        let high = run[(run.count * 2) / 3]
        // A spread this narrow means the bands would be noise, not signal.
        guard high - low >= 5 else { return [] }

        let milesForWeek = Dictionary(uniqueKeysWithValues: weeks.map { ($0.start, $0.miles) })
        func band(_ miles: Double) -> Int { miles < low ? 0 : (miles < high ? 1 : 2) }

        var counts = [0, 0, 0]
        for m in mentions {
            guard let miles = milesForWeek[weekStart(of: m.mentionedAt)], miles > 0 else { continue }
            counts[band(miles)] += 1
        }

        func mi(_ d: Double) -> String { String(format: "%.0f", d.rounded()) }
        return [
            NiggleTally(label: "Under \(mi(low)) mi", count: counts[0]),
            NiggleTally(label: "\(mi(low)) – \(mi(high)) mi", count: counts[1]),
            NiggleTally(label: "\(mi(high)) mi and up", count: counts[2]),
        ]
    }
}
