//
//  NiggleTimeline.swift
//  RunningLog
//
//  The niggle mention-timeline — derivation only, no UI, no interpretation.
//
//  REBUILT 2026-08-24 against the real `body_mentions` rows. The first version
//  was ported from a web prototype built on mock data, and the mock data lied
//  about the shape of the real thing in three ways that all produced visible
//  bugs:
//
//   1. `side` is usually NULL, even when the athlete clearly said "left" —
//      "sore left knee" arrives with side = null. Keying a thread on
//      (area, side) therefore split one knee into "Knee" and "L. Knee".
//      Threads are now keyed on BODY AREA ALONE and side is demoted to a
//      descriptor derived from whichever rows did capture it.
//
//   2. `niggle_resolutions` contains complaints, not just all-clears. Of the
//      five rows on file, three read "I did have a knee issue", "I felt it a
//      little bit", "was feeling a little tight". So a resolution row is NOT
//      trusted to close a thread on its own: it must fall strictly after the
//      last mention, and any mention after any resolution voids it. Even then
//      we say "settled", never "healed" — the system does not know that.
//
//   3. The same ache gets logged twice on one day from one memo. Mentions are
//      deduped per (area, day).
//
//  Everything here is still a mechanical function of dates and mileage.
//  Nothing interprets.
//

import Foundation

// MARK: - Rules

enum NiggleRule {
    /// A mention this recent keeps a thread active.
    static let activeWindowDays = 14
    /// A gap this long before a mention reads as a return, not a continuation.
    static let recurrenceGapDays = 21
    /// The timeline is ongoing — it runs from the first ache ever recorded to
    /// today, and never truncates. This bound exists only so a corrupt far-past
    /// date cannot stretch the axis to nothing; it is not a display window.
    static let sanityFloorWeeks = 520   // 10 years
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
}

enum NiggleThreadStatus: Int {
    /// Raw value doubles as sort rank.
    case active = 0, quiet = 1, settled = 2
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

/// A row from `niggle_resolutions`. Named "positive note" rather than
/// "resolution" because the table demonstrably contains both.
struct NigglePositiveNote: Equatable {
    let on: Date
    let quote: String?
}

struct NiggleReturn: Equatable {
    let afterDays: Int
    let on: Date
}

/// Every mention of one body area, in date order. Side is an attribute of the
/// thread, not part of its identity — see the header note.
struct NiggleThread: Identifiable, Equatable {
    let id: String
    let bodyArea: String
    let label: String
    /// "left", "mostly left", or nil when no row ever captured a side.
    let sideNote: String?
    /// The raw side to send to `resolve-niggle`. `.unspecified` when no row
    /// captured one — the edge function treats that as "any side".
    let dominantSide: NiggleSide
    let status: NiggleThreadStatus
    let mentions: [NiggleMention]
    let positiveNotes: [NigglePositiveNote]
    let firstSeen: Date
    let lastSeen: Date
    let spanDays: Int
    let daysSinceLast: Int
    let returns: [NiggleReturn]

    var mentionCount: Int { mentions.count }
    var lastQuote: String? { mentions.last?.quote }

    /// Plain-language recency. The screen never says "healed".
    var recencyLine: String {
        switch daysSinceLast {
        case 0: return "mentioned today"
        case 1: return "mentioned yesterday"
        case 2...13: return "mentioned \(daysSinceLast)d ago"
        case 14...59: return "last mentioned \(daysSinceLast / 7)w ago"
        default: return "last mentioned \(daysSinceLast / 30)mo ago"
        }
    }
}

struct NiggleWeek: Identifiable, Equatable {
    let start: Date
    let miles: Double
    let partial: Bool
    var id: Date { start }
}

// MARK: - The timeline

struct NiggleTimeline: Equatable {
    let threads: [NiggleThread]
    let weeks: [NiggleWeek]
    let spanStart: Date
    let spanEnd: Date

    var isEmpty: Bool { threads.isEmpty }
    var activeCount: Int { threads.filter { $0.status == .active }.count }
    var totalMentions: Int { threads.reduce(0) { $0 + $1.mentionCount } }

    /// Where a date sits across the drawn span, 0...1.
    func position(of date: Date) -> Double {
        let total = spanEnd.timeIntervalSince(spanStart)
        guard total > 0 else { return 1 }
        return min(max(date.timeIntervalSince(spanStart) / total, 0), 1)
    }

    static let empty = NiggleTimeline(
        threads: [], weeks: [], spanStart: .distantPast, spanEnd: .distantPast
    )
}

// MARK: - Build

enum NiggleTimelineBuilder {

    static var utcCalendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC") ?? .current
        c.firstWeekday = 2   // Monday
        return c
    }()

    static func days(from a: Date, to b: Date) -> Int {
        utcCalendar.dateComponents([.day], from: a, to: b).day ?? 0
    }

    static func weekStart(of date: Date) -> Date {
        let c = utcCalendar
        let comps = c.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return c.date(from: comps) ?? c.startOfDay(for: date)
    }

    static func titleCase(_ part: String) -> String {
        if part.lowercased() == "it band" { return "IT band" }
        return part.prefix(1).uppercased() + part.dropFirst()
    }

    static func build(
        mentions rawMentions: [NiggleMention],
        resolutions: [(bodyArea: String, side: NiggleSide, resolvedAt: Date, quote: String?)],
        milesByDay: [Date: Double],
        today: Date
    ) -> NiggleTimeline {

        let todayDay = utcCalendar.startOfDay(for: today)
        guard let floor = utcCalendar.date(
            byAdding: .weekOfYear, value: -NiggleRule.sanityFloorWeeks, to: todayDay
        ) else { return .empty }

        // ── Group by body area alone; dedupe per (area, day) ───────────
        var groups: [String: [NiggleMention]] = [:]
        for m in rawMentions where m.mentionedAt >= floor {
            groups[m.bodyArea.lowercased(), default: []].append(m)
        }

        var notesByArea: [String: [NigglePositiveNote]] = [:]
        for r in resolutions where r.resolvedAt >= floor {
            notesByArea[r.bodyArea.lowercased(), default: []]
                .append(NigglePositiveNote(on: r.resolvedAt, quote: r.quote))
        }

        var threads: [NiggleThread] = []
        for (area, rows) in groups {
            // One mention per day: a single memo can write the same ache twice.
            var seenDays = Set<Date>()
            let ordered = rows
                .sorted { $0.mentionedAt < $1.mentionedAt }
                .filter { seenDays.insert($0.mentionedAt).inserted }

            guard let first = ordered.first, let last = ordered.last else { continue }

            let notes = (notesByArea[area] ?? []).sorted { $0.on < $1.on }

            // A positive note only settles the thread if it lands strictly
            // AFTER the last mention. Same-day ties go to the mention — if you
            // mentioned it that day, it is not settled.
            let settled = (notes.last?.on).map { $0 > last.mentionedAt } ?? false

            let daysSinceLast = days(from: last.mentionedAt, to: todayDay)
            let status: NiggleThreadStatus = settled
                ? .settled
                : (daysSinceLast <= NiggleRule.activeWindowDays ? .active : .quiet)

            var returns: [NiggleReturn] = []
            if ordered.count > 1 {
                for i in 1..<ordered.count {
                    let gap = days(from: ordered[i - 1].mentionedAt, to: ordered[i].mentionedAt)
                    if gap >= NiggleRule.recurrenceGapDays {
                        returns.append(NiggleReturn(afterDays: gap, on: ordered[i].mentionedAt))
                    }
                }
            }

            threads.append(NiggleThread(
                id: area,
                bodyArea: area,
                label: titleCase(area),
                sideNote: sideNote(for: ordered),
                dominantSide: dominantSide(for: ordered),
                status: status,
                mentions: ordered,
                positiveNotes: notes,
                firstSeen: first.mentionedAt,
                lastSeen: last.mentionedAt,
                spanDays: days(from: first.mentionedAt, to: last.mentionedAt),
                daysSinceLast: daysSinceLast,
                returns: returns
            ))
        }

        threads.sort {
            if $0.status != $1.status { return $0.status.rawValue < $1.status.rawValue }
            if $0.mentionCount != $1.mentionCount { return $0.mentionCount > $1.mentionCount }
            return $0.label < $1.label
        }

        // ── Span: first mention ever → today. No window. ───────────────
        let earliest = threads.map(\.firstSeen).min() ?? todayDay
        let spanStart = weekStart(of: max(earliest, floor))

        var weeks: [NiggleWeek] = []
        let currentWeek = weekStart(of: todayDay)
        var cursor = spanStart
        while cursor <= currentWeek {
            var miles = 0.0
            for d in 0..<7 {
                if let day = utcCalendar.date(byAdding: .day, value: d, to: cursor) {
                    miles += milesByDay[day] ?? 0
                }
            }
            weeks.append(NiggleWeek(start: cursor, miles: miles, partial: cursor == currentWeek))
            guard let next = utcCalendar.date(byAdding: .weekOfYear, value: 1, to: cursor)
            else { break }
            cursor = next
        }

        return NiggleTimeline(
            threads: threads, weeks: weeks, spanStart: spanStart, spanEnd: todayDay
        )
    }

    /// The most-reported side, ignoring rows that captured none.
    static func dominantSide(for mentions: [NiggleMention]) -> NiggleSide {
        var counts: [NiggleSide: Int] = [:]
        for s in mentions.map(\.side) where s != .unspecified { counts[s, default: 0] += 1 }
        return counts.max(by: { $0.value < $1.value })?.key ?? .unspecified
    }

    /// Side is unreliable per-row, so report what the rows that DID capture it
    /// agree on, and hedge when they disagree. nil when none captured a side.
    static func sideNote(for mentions: [NiggleMention]) -> String? {
        let sided = mentions.map(\.side).filter { $0 != .unspecified }
        guard !sided.isEmpty else { return nil }
        var counts: [NiggleSide: Int] = [:]
        for s in sided { counts[s, default: 0] += 1 }
        guard let (top, n) = counts.max(by: { $0.value < $1.value }) else { return nil }
        let word = top == .both ? "both sides" : top.rawValue
        if n == sided.count {
            // Every sided row agrees, but some rows had no side at all.
            return n == mentions.count ? word : "mostly \(word)"
        }
        return "mostly \(word)"
    }
}
