//
//  HomePage.swift
//  RunningLog
//
//  The page model behind the paged Today surface.
//
//  Today used to be one vertical ScrollView holding every section at once.
//  It is now a horizontal run of pages turned like a newspaper — one local
//  calendar day per page, today's page first, turning back through the log.
//
//  This file is model only: sessions in, pages out, no views. Keeping it pure
//  means the page run can be reasoned about without a device; the layout risk
//  lives next door in HomeDayPager.swift.
//
//  Three rules the builder enforces. Each is a thing that went wrong somewhere
//  else in this app first:
//
//  1. A DAY IS NOT A RUN. Grouping goes through `SessionRollup`, so a double
//     is two sessions on one page and a track day is one session assembled
//     from five uploads. A page laid out around a single headline run is the
//     error recorded in WEEK-TAB-APPLY §0.
//  2. NOTHING IS INVENTED. A day with no rows is not a page with a stand-in
//     in it. One empty day is a page that says it is empty; a run of them
//     collapses into a gap page that says how many.
//  3. LOCAL DAYS ONLY. `SessionRollup.localDay` is the grouping key — see its
//     note about the 8 rows in this account that a UTC day misplaces.
//

import Foundation

// MARK: - HomePage

/// One turn of the paper.
enum HomePage: Identifiable, Hashable {

    /// A day the athlete has rows for, or a single dayless day between two
    /// days that do. `date` is always a local start-of-day.
    case day(Date)

    /// Fitness trend, zone shifts, race predictions. Account-level — it
    /// belongs to no day, which is why it is its own page rather than a
    /// section hanging off today's.
    case cockpit

    /// Two or more consecutive dayless days, collapsed. Rendering them one
    /// per page would make a rest week feel like a bug.
    case gap(from: Date, through: Date, days: Int)

    var id: String {
        switch self {
        case .day(let d):       return "day-\(Int(d.timeIntervalSince1970))"
        case .cockpit:          return "cockpit"
        case .gap(let f, _, _): return "gap-\(Int(f.timeIntervalSince1970))"
        }
    }

    /// The date this page stands on, for the rail and for VoiceOver.
    /// `nil` for the cockpit, which stands on no date.
    var date: Date? {
        switch self {
        case .day(let d):       return d
        case .gap(_, let t, _): return t
        case .cockpit:          return nil
        }
    }
}

// MARK: - Builder

enum HomePageBuilder {

    /// How far back the paper goes. `TrainingLogStore` holds 400 days, but a
    /// rail of 400 ticks is not a rail — it is a scrollbar. Travelling
    /// further back is the Log tab's job.
    ///
    /// Raising this is cheap (the pages are lazy); the rail is what suffers.
    static let maxDays = 60

    /// Sessions → pages, newest first.
    ///
    /// - Parameters:
    ///   - sessions: output of `SessionRollup.sessions(from:)`. Order does not
    ///     matter here; this regroups by `session.day`.
    ///   - today: injectable for tests. Normalised to a local start-of-day.
    /// - Returns: `[.day(today), .cockpit, …]`, then one page per day walking
    ///   backwards, with dayless runs collapsed. Never empty — today's page
    ///   always exists, even with no rows at all.
    static func pages(from sessions: [TrainingSession],
                      today: Date = Date()) -> [HomePage] {

        let calendar = Calendar.current
        let todayStart = SessionRollup.localDay(today)
        let daysWithRows = Set(sessions.map(\.day))

        // Anything stamped in the future (a watch with a wrong clock, a
        // manual entry typed ahead) is not a page. The paper stops at today.
        let oldestWithRows = daysWithRows.filter { $0 <= todayStart }.min()

        // Nothing logged at all: today's page and the cockpit, nothing to
        // turn back to. The empty state lives in the view.
        guard let oldestWithRows else { return [.day(todayStart), .cockpit] }

        let bound = calendar.date(byAdding: .day, value: -maxDays, to: todayStart) ?? todayStart
        let stopAt = max(oldestWithRows, bound)

        var pages: [HomePage] = [.day(todayStart), .cockpit]

        var cursor = calendar.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart
        var emptyRun: [Date] = []

        /// Flush the accumulated dayless days. One becomes its own page (it
        /// is a rest day, and a rest day is part of the training); two or
        /// more become a gap.
        func flushEmptyRun() {
            guard !emptyRun.isEmpty else { return }
            if emptyRun.count == 1 {
                pages.append(.day(emptyRun[0]))
            } else {
                // emptyRun walks backwards, so last is the older edge.
                pages.append(.gap(from: emptyRun[emptyRun.count - 1],
                                  through: emptyRun[0],
                                  days: emptyRun.count))
            }
            emptyRun.removeAll()
        }

        while cursor >= stopAt {
            if daysWithRows.contains(cursor) {
                flushEmptyRun()
                pages.append(.day(cursor))
            } else {
                emptyRun.append(cursor)
            }
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }

        // A trailing empty run is the space *before* the athlete's first
        // logged day, or before the 60-day bound. It is not a rest week —
        // it is the edge of the paper. Dropped, deliberately.

        return pages
    }

    /// The sessions belonging to one page, in clock order.
    ///
    /// `SessionRollup` already sorts chronologically within a day; this
    /// re-sorts anyway so the page does not depend on that staying true.
    static func sessions(on day: Date, from sessions: [TrainingSession]) -> [TrainingSession] {
        sessions.filter { $0.day == day }.sorted { $0.start < $1.start }
    }
}
