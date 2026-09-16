//
//  TrendsReadTests.swift
//  RunningLogTests
//
//  Pins every string `TrendsReadBuilder` can emit. The Read's headline and
//  story are templates over computed values — no model runs on that
//  surface — so this is the whole safety net for it: unit assertions, not
//  cassettes.
//
//  The cases that matter most are the two that decide *which* sentence
//  gets written: the alert precedence (a live body mention outranks any
//  volume news above it) and the `dominantArea` tie-break (the only place
//  the builder picks between two equally-supported strings, and therefore
//  the only place the headline could change on reload without the data
//  changing).
//

import Foundation
import Testing
@testable import RunningLog

@Suite("Trends · the Read")
struct TrendsReadTests {

    // MARK: - Fixtures

    private static let calendar: Calendar = {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return c
    }()

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// `offset` days after `start`, as a "yyyy-MM-dd" key.
    private static func day(_ start: String, plus offset: Int) -> String {
        guard let base = formatter.date(from: start),
              let shifted = calendar.date(byAdding: .day, value: offset, to: base)
        else { return start }
        return formatter.string(from: shifted)
    }

    /// A window of consecutive days. `miles` is applied to every day unless
    /// `milesAt` overrides that index.
    private static func window(
        from start: String = "2026-07-08",
        count: Int,
        miles: Double = 8,
        milesAt: [Int: Double] = [:],
        moodAt: [Int: String] = [:],
        keyAt: Set<Int> = [],
        nigglesAt: [Int: [TrendsDay.DayNiggle]] = [:]
    ) -> [TrendsDay] {
        (0 ..< count).map { i in
            let distance = milesAt[i] ?? miles
            return TrendsDay(
                date: day(start, plus: i),
                miles: distance,
                type: keyAt.contains(i) ? .key : (distance > 0 ? .easy : .rest),
                mood: moodAt[i],
                niggles: nigglesAt[i] ?? []
            )
        }
    }

    private static func niggle(
        _ area: String, side: String? = nil, quote: String = "felt it on the back half"
    ) -> TrendsDay.DayNiggle {
        TrendsDay.DayNiggle(area: area, side: side, severity: "tight", quote: quote)
    }

    // MARK: - The floor

    @Test("Four running days is too thin to read")
    func fourRunningDaysIsThin() {
        let read = TrendsReadBuilder.build(days: Self.window(count: 4))

        #expect(read.isThin)
        #expect(read.headline == "Not enough logged yet.")
        #expect(read.subline.isEmpty)
        // The grid still builds — the athlete sees her days, just no verdict.
        #expect(!read.weeks.isEmpty)
    }

    @Test("Five running days turns the read on")
    func fiveRunningDaysIsEnough() {
        let read = TrendsReadBuilder.build(days: Self.window(count: 5))

        #expect(!read.isThin)
        #expect(read.headline != "Not enough logged yet.")
        #expect(!read.subline.isEmpty)
    }

    @Test("Rest days don't count toward the floor")
    func restDaysDoNotCountTowardFloor() {
        // Ten days, only four of them run.
        let days = Self.window(
            count: 10, miles: 0,
            milesAt: [0: 6, 2: 6, 4: 6, 6: 6]
        )
        #expect(TrendsReadBuilder.build(days: days).isThin)
    }

    // MARK: - Headline precedence

    @Test("A body mention inside 7 days outranks any volume news")
    func recentNiggleWinsTheHeadline() {
        // Volume doubles across the window — normally a "Volume, up" headline.
        let days = Self.window(
            count: 10,
            milesAt: [0: 5, 1: 5, 2: 5, 3: 5, 4: 5,
                      5: 10, 6: 10, 7: 10, 8: 10, 9: 10],
            nigglesAt: [9: [Self.niggle("calf", side: "left")]]
        )
        let read = TrendsReadBuilder.build(days: days)

        #expect(read.headline == "Left calf, 1 mention.")
    }

    @Test("A body mention older than 7 days lets volume take the headline")
    func staleNiggleFallsThrough() {
        let days = Self.window(
            count: 20,
            milesAt: Dictionary(
                uniqueKeysWithValues: (0 ..< 20).map { ($0, $0 < 10 ? 5.0 : 10.0) }
            ),
            nigglesAt: [0: [Self.niggle("calf", side: "left")]]
        )
        let read = TrendsReadBuilder.build(days: days)

        #expect(read.headline == "Volume, up 100%.")
        // …and the niggle is still told, with its date, in the story.
        #expect(read.beats.contains { $0.text.contains("last on") })
    }

    @Test("Mentions are pluralised on the count, never on severity")
    func mentionsPluralise() {
        let days = Self.window(
            count: 10,
            nigglesAt: [
                8: [Self.niggle("calf", side: "left")],
                9: [Self.niggle("calf", side: "left")],
            ]
        )
        #expect(TrendsReadBuilder.build(days: days).headline == "Left calf, 2 mentions.")
    }

    // MARK: - Volume

    @Test("A back half 10% or more above the front reads as up")
    func volumeUp() {
        let days = Self.window(
            count: 10,
            milesAt: Dictionary(
                uniqueKeysWithValues: (0 ..< 10).map { ($0, $0 < 5 ? 5.0 : 10.0) }
            )
        )
        #expect(TrendsReadBuilder.build(days: days).headline == "Volume, up 100%.")
    }

    @Test("A back half 10% or more below the front reads as down")
    func volumeDown() {
        let days = Self.window(
            count: 10,
            milesAt: Dictionary(
                uniqueKeysWithValues: (0 ..< 10).map { ($0, $0 < 5 ? 10.0 : 5.0) }
            )
        )
        #expect(TrendsReadBuilder.build(days: days).headline == "Volume, down 50%.")
    }

    @Test("Inside ±10% the window is called flat rather than ranked")
    func flatWindow() {
        let read = TrendsReadBuilder.build(days: Self.window(count: 10, miles: 8))
        #expect(read.headline == "A flat 10 days.")
    }

    // MARK: - The subline

    @Test("The subline states miles, key sessions and logging density")
    func sublineCountsAreHonest() {
        let days = Self.window(
            count: 10, miles: 5,
            moodAt: [0: "tired", 3: "energized"],
            keyAt: [2, 7]
        )
        let read = TrendsReadBuilder.build(days: days)

        #expect(read.subline == "50 mi · 2 key · 2/10 logged")
    }

    // MARK: - Mood

    @Test("Only moods that occur are tallied — never a zero row")
    func moodTallyOmitsAbsentWords() {
        let days = Self.window(
            count: 10,
            moodAt: [0: "struggling", 1: "struggling", 5: "energized"]
        )
        let read = TrendsReadBuilder.build(days: days)

        #expect(read.moodCounts.count == 2)
        #expect(read.moodCounts.first?.mood == "struggling")
        #expect(read.moodCounts.first?.count == 2)
    }

    @Test("A window with no feelings logged still builds")
    func noMoodsStillBuilds() {
        let read = TrendsReadBuilder.build(days: Self.window(count: 10))

        #expect(read.moodCounts.isEmpty)
        #expect(!read.weeks.isEmpty)
        // No opening beat: there were no low logs to open with.
        #expect(!read.beats.contains { $0.text.contains("opened rough") })
    }

    @Test("Two or more low logs in the first five days opens the story")
    func roughOpeningIsToldWhenItHappened() {
        let days = Self.window(
            count: 10,
            moodAt: [0: "struggling", 1: "tired", 2: "struggling"]
        )
        let read = TrendsReadBuilder.build(days: days)

        let opening = read.beats.first { $0.text.contains("opened rough") }
        #expect(opening != nil)
        #expect(opening?.callout == 1)
    }

    @Test("One low log is not a rough opening")
    func singleLowLogIsNotAnOpening() {
        let days = Self.window(count: 10, moodAt: [0: "struggling"])
        let read = TrendsReadBuilder.build(days: days)

        #expect(!read.beats.contains { $0.text.contains("opened rough") })
    }

    // MARK: - The month grid

    @Test("Rows are Monday-first and pad out to seven slots")
    func gridRowsAreMondayFirstAndSevenWide() {
        // 2026-07-08 is a Wednesday, so the first row carries two nil slots.
        let read = TrendsReadBuilder.build(days: Self.window(count: 30))

        #expect(read.weeks.allSatisfy { $0.days.count == 7 })
        #expect(read.weeks.first?.days[0] == nil)   // Monday, before the window
        #expect(read.weeks.first?.days[1] == nil)   // Tuesday, before the window
        #expect(read.weeks.first?.days[2] != nil)   // Wednesday Jul 8
    }

    @Test("Day numerals reset across a month boundary")
    func gridCrossesMonthEnd() {
        // Jul 28 → Aug 3.
        let read = TrendsReadBuilder.build(
            days: Self.window(from: "2026-07-28", count: 7)
        )
        let numerals = read.weeks
            .flatMap { $0.days.compactMap { $0?.dayOfMonth } }

        #expect(numerals.contains(31))
        #expect(numerals.contains(1))
    }

    @Test("Week margins total only the miles inside the window")
    func weekMarginsSumTheWindowOnly() {
        let read = TrendsReadBuilder.build(days: Self.window(count: 30, miles: 5))
        let total = read.weeks.reduce(0) { $0 + $1.miles }

        #expect(total == 150)
    }

    @Test("Only key sessions carry a zone; easy days carry none")
    func zonesAreKeySessionsOnly() {
        let days = Self.window(count: 10, keyAt: [3])
        let session = KeySession(
            id: "log-1",
            date: Self.day("2026-07-08", plus: 3),
            dateLabel: "Jul 11",
            zone: "5k",
            workPaceSec: 320,
            workPaceAdjSec: nil,
            heatCategory: nil,
            workHrAvg: nil,
            structure: nil,
            distanceMi: 6
        )
        let read = TrendsReadBuilder.build(days: days, keySessions: [session])
        let all = read.weeks.flatMap { $0.days.compactMap { $0 } }

        #expect(all.first { $0.date == session.date }?.zoneToken == "5k")
        #expect(all.filter { $0.zoneToken != nil }.count == 1)
    }

    // MARK: - Month slicing

    @Test("A six-month payload splits into months, newest first")
    func monthsAreNewestFirst() {
        // Feb 9 → Aug 7, the shape the service actually returns.
        let days = Self.window(from: "2026-02-09", count: 180)
        let months = TrendsReadBuilder.months(days)

        #expect(months.count == 7)          // Feb…Aug inclusive
        #expect(months.first?.id == "2026-08")
        #expect(months.last?.id == "2026-02")
        #expect(months.first?.title == "August 2026")
    }

    @Test("Every day lands in exactly one month, none dropped")
    func monthsPartitionThePayload() {
        let days = Self.window(from: "2026-02-09", count: 180)
        let months = TrendsReadBuilder.months(days)

        #expect(months.reduce(0) { $0 + $1.days.count } == 180)
        #expect(Set(months.flatMap { $0.days.map(\.date) }).count == 180)
    }

    @Test("Days inside a month are oldest first")
    func monthDaysAreChronological() {
        let days = Self.window(from: "2026-02-09", count: 180)
        guard let august = TrendsReadBuilder.months(days).first else {
            Issue.record("no months built"); return
        }
        let keys = august.days.map(\.date)
        #expect(keys == keys.sorted())
        #expect(august.days.first?.date == "2026-08-01")
    }

    @Test("A month read sums that month only, not the payload")
    func readIsScopedToItsMonth() {
        // 180 days at 8 miles is 1440 miles across the payload. One month
        // must never state that number — that was the six-month bug.
        let days = Self.window(from: "2026-02-09", count: 180, miles: 8)
        guard let july = TrendsReadBuilder.months(days).first(where: { $0.id == "2026-07" })
        else { Issue.record("July missing"); return }

        let read = TrendsReadBuilder.build(days: july.days)

        #expect(july.days.count == 31)
        #expect(read.subline.hasPrefix("248 mi"))   // 31 × 8
        #expect(!read.subline.contains("1440"))
    }

    // MARK: - Stability

    @Test("A tie in body areas resolves to the earliest mention, every run")
    func dominantAreaTieIsStable() {
        let days = Self.window(
            count: 10,
            nigglesAt: [
                8: [Self.niggle("calf", side: "left")],
                9: [Self.niggle("knee", side: "right")],
            ]
        )

        // Same input, ten builds, one answer. An unstable tie-break here
        // would change the headline on reload without the data changing.
        let headlines = Set((0 ..< 10).map { _ in
            TrendsReadBuilder.build(days: days).headline
        })

        #expect(headlines.count == 1)
        #expect(headlines.first == "Left calf, 1 mention.")
    }

    @Test("Day order in the payload doesn't change the read")
    func buildIsOrderIndependent() {
        let days = Self.window(count: 10, moodAt: [0: "struggling", 1: "tired"])
        let forward = TrendsReadBuilder.build(days: days)
        let shuffled = TrendsReadBuilder.build(days: days.reversed())

        #expect(forward.headline == shuffled.headline)
        #expect(forward.subline == shuffled.subline)
        #expect(forward.weeks.count == shuffled.weeks.count)
    }

    // MARK: - The line the copy can't cross

    @Test("No emitted string uses second person or a trajectory word")
    func copyStaysInsideItsRules() {
        let days = Self.window(
            count: 30,
            moodAt: [0: "struggling", 1: "struggling", 2: "tired", 20: "energized"],
            keyAt: [3, 10, 17],
            nigglesAt: [7: [Self.niggle("calf", side: "left")]]
        )
        let read = TrendsReadBuilder.build(days: days)
        let copy = ([read.headline, read.subline] + read.beats.map(\.text))
            .joined(separator: " ")
            .lowercased()

        for banned in [
            "you", "your", "coming back", "on the up", "turning a corner",
            "bouncing back", "great", "crushed", "rough patch", "keep it up",
        ] {
            #expect(!copy.contains(banned), "copy leaked a banned phrase: \(banned)")
        }
    }
}
