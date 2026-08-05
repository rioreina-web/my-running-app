import Foundation
import Testing
@testable import RunningLog

// Guards for `TrendsBlockModels.swift` — the substrate behind Trends sections
// 01 Load, 04 Key sessions and 05 Mood & block. Each test encodes a decision.

// MARK: - Fixtures

private func day(_ iso: String, _ miles: Double, mood: String? = nil) -> TrendsDay {
    TrendsDay(
        date: iso,
        miles: miles,
        type: .init(token: miles > 0 ? "easy" : "rest"),
        mood: mood,
        niggles: []
    )
}

private func week(_ monday: String, quality: Double, quote: String? = nil) -> TrendsWeek {
    TrendsWeek(
        month: String(monday.prefix(7)),
        dateLabel: monday,
        miles: 0,
        qualityMiles: quality,
        keyPaceSec: nil,
        mood: "",
        niggles: [],
        voiceQuote: quote,
        weekStart: monday
    )
}

private func key(_ iso: String, zone: String = "hmp", adj: Int? = nil, mi: Double = 6) -> KeySession {
    KeySession(
        id: "log-" + iso, date: iso, dateLabel: iso, zone: zone,
        workPaceSec: 330, workPaceAdjSec: adj, heatCategory: adj == nil ? nil : "hot",
        workHrAvg: 165, structure: nil, distanceMi: mi, qualityLoad: 40, kind: "quality"
    )
}

/// `weeks` consecutive Mondays from 2026-06-01 (a Monday), each with the given
/// mileage on every day unless a clear-day cadence is set.
private func set(weeks: Int, milesPerDay: Double = 8, clearEvery: Int = 0) -> TrendsBucketSet {
    var days: [TrendsDay] = []
    var cursor = TrendsBlockBuilder.isoDay.date(from: "2026-06-01")!
    for i in 0..<(weeks * 7) {
        let iso = TrendsBlockBuilder.isoDay.string(from: cursor)
        let clear = clearEvery > 0 && i % clearEvery == 0
        days.append(day(iso, clear ? 0 : milesPerDay))
        cursor = cursor.addingTimeInterval(86_400)
    }
    return TrendsBucketSet(grain: .day, buckets: [], days: days)
}

// MARK: - Week boundaries

@Suite("TrendsBlockBuilder.mondayISO")
struct BlockMondayTests {

    /// Weeks here must be the same seven days the server groups, or a session
    /// lands under the wrong volume bar.
    @Test("every day of a week maps to that week's Monday")
    func mapsToMonday() {
        // 2026-06-01 is a Monday.
        for (iso, expected) in [
            ("2026-06-01", "2026-06-01"),
            ("2026-06-04", "2026-06-01"),
            ("2026-06-07", "2026-06-01"),  // Sunday still belongs to Monday's week
            ("2026-06-08", "2026-06-08"),
        ] {
            #expect(TrendsBlockBuilder.mondayISO(iso) == expected)
        }
    }

    @Test("an unparseable date yields no week")
    func rejectsGarbage() {
        #expect(TrendsBlockBuilder.mondayISO("not-a-date") == nil)
    }
}

// MARK: - 01 · Load

@Suite("TrendsBlockBuilder.load")
struct BlockLoadTests {

    @Test("days roll into one row per week, oldest first")
    func rollsIntoWeeks() {
        let read = TrendsBlockBuilder.load(set: set(weeks: 6), weeks: [], keySessions: [])
        #expect(read.weeks.count == 6)
        #expect(read.weeks.map(\.weekStart) == read.weeks.map(\.weekStart).sorted())
        #expect(read.weeks[0].miles == 56)
    }

    /// Two points of a ratio need four weeks behind them. Dividing by a
    /// one-week "baseline" would make every second week look like a spike.
    @Test("the ratio is nil until four weeks of baseline exist")
    func ratioNeedsBaseline() {
        let read = TrendsBlockBuilder.load(set: set(weeks: 6), weeks: [], keySessions: [])
        #expect(read.weeks[0].loadRatio == nil)
        #expect(read.weeks[3].loadRatio == nil)
        #expect(read.weeks[4].loadRatio != nil)
    }

    @Test("a flat block sits at a ratio of one")
    func flatBlockIsOne() throws {
        let read = TrendsBlockBuilder.load(set: set(weeks: 6), weeks: [], keySessions: [])
        let ratio = try #require(read.weeks[5].loadRatio)
        #expect(abs(ratio - 1.0) < 0.001)
        #expect(read.outOfBand.isEmpty)
    }

    /// A tail week of three days is not a down week, and averaging it in would
    /// say the block was smaller than it was.
    @Test("a partial week is drawn but excluded from the mean")
    func partialWeekExcludedFromMean() throws {
        var days = set(weeks: 4).days
        // Add a three-day fifth week.
        var cursor = TrendsBlockBuilder.isoDay.date(from: "2026-06-29")!
        for _ in 0..<3 {
            days.append(day(TrendsBlockBuilder.isoDay.string(from: cursor), 8))
            cursor = cursor.addingTimeInterval(86_400)
        }
        let read = TrendsBlockBuilder.load(
            set: TrendsBucketSet(grain: .day, buckets: [], days: days),
            weeks: [], keySessions: []
        )
        #expect(read.weeks.count == 5)
        #expect(read.weeks[4].isPartial)
        #expect(read.fullWeeks.count == 4)
        let mean = try #require(read.meanMiles)
        #expect(abs(mean - 56) < 0.001)     // the 24-mile stub does not drag it
    }

    /// The tint that carries the section's finding.
    @Test("a week with no clear day is flagged; a partial week never is")
    func unbrokenFlag() {
        let unbroken = TrendsBlockBuilder.load(set: set(weeks: 3), weeks: [], keySessions: [])
        #expect(unbroken.unbrokenWeeks.count == 3)

        let rested = TrendsBlockBuilder.load(
            set: set(weeks: 3, clearEvery: 7), weeks: [], keySessions: []
        )
        #expect(rested.unbrokenWeeks.isEmpty)
    }

    /// Quality miles ride on the weekly payload, joined by Monday.
    @Test("quality miles join by week start and never exceed the week's miles")
    func qualityJoins() {
        let read = TrendsBlockBuilder.load(
            set: set(weeks: 2),
            weeks: [week("2026-06-01", quality: 12), week("2026-06-08", quality: 999)],
            keySessions: []
        )
        #expect(read.weeks[0].qualityMiles == 12)
        // A payload disagreeing with the day substrate is clamped, not trusted.
        #expect(read.weeks[1].qualityMiles == 56)
    }

    @Test("a week with no reported split carries no quality cap")
    func missingSplitIsZero() {
        let read = TrendsBlockBuilder.load(set: set(weeks: 2), weeks: [], keySessions: [])
        #expect(read.weeks.allSatisfy { $0.qualityMiles == 0 })
    }

    @Test("key sessions are counted into the week they land in")
    func keyCounts() {
        let read = TrendsBlockBuilder.load(
            set: set(weeks: 2),
            weeks: [],
            keySessions: [key("2026-06-03"), key("2026-06-06"), key("2026-06-09")]
        )
        #expect(read.weeks[0].keyCount == 2)
        #expect(read.weeks[1].keyCount == 1)
    }

    @Test("an empty window is an empty read, not a crash")
    func emptyWindow() {
        let read = TrendsBlockBuilder.load(
            set: TrendsBucketSet(grain: .day, buckets: [], days: []),
            weeks: [], keySessions: []
        )
        #expect(read.isEmpty)
        #expect(read.meanMiles == nil)
    }
}

// MARK: - 04 · Key sessions

@Suite("TrendsBlockBuilder.keySessions")
struct BlockKeySessionTests {

    @Test("only sessions inside the window count")
    func honoursWindow() {
        let read = TrendsBlockBuilder.keySessions(
            set: set(weeks: 2),
            keySessions: [key("2026-06-03"), key("2025-01-01")]
        )
        #expect(read.count == 1)
    }

    /// The number that says whether the hard work is spaced or stacked.
    @Test("the median gap is measured in days between consecutive sessions")
    func medianGap() {
        let read = TrendsBlockBuilder.keySessions(
            set: set(weeks: 3),
            keySessions: [key("2026-06-02"), key("2026-06-06"), key("2026-06-10"), key("2026-06-13")]
        )
        #expect(read.gaps == [4, 4, 3])
        #expect(read.medianGap == 4)
    }

    @Test("sessions on consecutive days are counted as back to back")
    func backToBack() {
        let read = TrendsBlockBuilder.keySessions(
            set: set(weeks: 2),
            keySessions: [key("2026-06-02"), key("2026-06-03"), key("2026-06-09")]
        )
        #expect(read.backToBackCount == 1)
    }

    /// Zones come back in canonical fast→slow order, so the caption is a scale
    /// rather than whatever order the payload happened to arrive in.
    @Test("zones are de-duplicated and ordered fast to slow")
    func zoneOrder() {
        let read = TrendsBlockBuilder.keySessions(
            set: set(weeks: 2),
            keySessions: [key("2026-06-02", zone: "mp"), key("2026-06-04", zone: "5k"),
                          key("2026-06-06", zone: "mp")]
        )
        #expect(read.zones == ["5k", "mp"])
    }

    @Test("only heat-adjusted sessions are counted as such")
    func heatCount() {
        let read = TrendsBlockBuilder.keySessions(
            set: set(weeks: 2),
            keySessions: [key("2026-06-02", adj: 318), key("2026-06-04")]
        )
        #expect(read.heatAdjustedCount == 1)
    }

    @Test("one session yields no gaps and no median")
    func singleSessionNoGap() {
        let read = TrendsBlockBuilder.keySessions(set: set(weeks: 2), keySessions: [key("2026-06-02")])
        #expect(read.gaps.isEmpty)
        #expect(read.medianGap == nil)
    }
}

// MARK: - 05 · Mood & block

@Suite("TrendsBlockBuilder.moodBlock")
struct BlockMoodTests {

    private func moodySet() -> TrendsBucketSet {
        var days = set(weeks: 2).days
        // Week one: two tired, one positive → modal is tired.
        days[0] = day(days[0].date, 8, mood: "tired")
        days[1] = day(days[1].date, 8, mood: "positive")
        days[2] = day(days[2].date, 8, mood: "tired")
        // Week two: silent.
        return TrendsBucketSet(grain: .day, buckets: [], days: days)
    }

    /// Modal across the week's days, matching every other weekly mood rollup.
    /// Ranking by hardest day would reduce a week to a sample of one.
    @Test("a week's mood is the most-logged label across its days")
    func modalMood() {
        let read = TrendsBlockBuilder.moodBlock(set: moodySet(), weeks: [])
        #expect(read.ribbon[0].mood == "tired")
        #expect(read.ribbon[0].loggedDays == 3)
    }

    /// A silent week stays silent. Carrying the previous week's colour forward
    /// would invent a reading the athlete never gave.
    @Test("a week with no logs carries no mood")
    func silentWeekStaysSilent() {
        let read = TrendsBlockBuilder.moodBlock(set: moodySet(), weeks: [])
        #expect(read.ribbon[1].mood == nil)
        #expect(read.ribbon[1].loggedDays == 0)
    }

    @Test("the legend lists only moods actually logged, in vocabulary order")
    func moodsUsed() {
        var days = set(weeks: 2).days
        days[0] = day(days[0].date, 8, mood: "struggling")
        days[8] = day(days[8].date, 8, mood: "positive")
        let read = TrendsBlockBuilder.moodBlock(
            set: TrendsBucketSet(grain: .day, buckets: [], days: days), weeks: []
        )
        #expect(read.moodsUsed == ["positive", "struggling"])
    }

    /// The quote is the athlete's own words and comes from the latest week in
    /// the window that carried one.
    @Test("the quote is the most recent one inside the window")
    func latestQuote() {
        let read = TrendsBlockBuilder.moodBlock(
            set: set(weeks: 2),
            weeks: [
                week("2026-06-01", quality: 0, quote: "older line"),
                week("2026-06-08", quality: 0, quote: "newer line"),
            ]
        )
        #expect(read.quote == "newer line")
    }

    @Test("a quote from outside the window is not borrowed")
    func quoteHonoursWindow() {
        let read = TrendsBlockBuilder.moodBlock(
            set: set(weeks: 2),
            weeks: [week("2025-01-06", quality: 0, quote: "last year")]
        )
        #expect(read.quote == nil)
    }

    @Test("the longest streak counts consecutive days with running")
    func streak() {
        // clearEvery 5 → a clear day every fifth day, so runs of four.
        let read = TrendsBlockBuilder.moodBlock(set: set(weeks: 3, clearEvery: 5), weeks: [])
        #expect(read.longestStreak == 4)
    }

    @Test("a block with no clear day is one unbroken streak")
    func unbrokenStreak() {
        let read = TrendsBlockBuilder.moodBlock(set: set(weeks: 2), weeks: [])
        #expect(read.longestStreak == 14)
        #expect(read.daysClear == 0)
    }

    @Test("peak week is the biggest single week in the window")
    func peakWeek() {
        var days = set(weeks: 2).days
        for i in 7..<14 { days[i] = day(days[i].date, 12) }
        let read = TrendsBlockBuilder.moodBlock(
            set: TrendsBucketSet(grain: .day, buckets: [], days: days), weeks: []
        )
        #expect(read.peakWeekMiles == 84)
    }
}
