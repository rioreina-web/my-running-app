import Foundation
import Testing
@testable import RunningLog

// Guards for the decisions in `TrendsMoodRead`. Each one encodes a judgment
// that would otherwise read as a bug and get "fixed".

private func day(
    _ iso: String, _ miles: Double, _ type: String,
    mood: String? = nil, niggle: (area: String, severity: String)? = nil
) -> TrendsDay {
    TrendsDay(
        date: iso, miles: miles, type: .init(token: type), mood: mood,
        niggles: niggle.map {
            [TrendsDay.DayNiggle(area: $0.area, side: nil, severity: $0.severity, quote: "her own words")]
        } ?? []
    )
}

/// `count` consecutive days from 2026-01-01, all easy, all carrying `mood`.
private func run(_ count: Int, mood: String?) -> [TrendsDay] {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    let formatter = DateFormatter()
    formatter.calendar = cal
    formatter.timeZone = cal.timeZone
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"

    return (0..<count).map { i in
        var comps = DateComponents(year: 2026, month: 1, day: 1)
        comps.day = 1 + i
        return day(formatter.string(from: cal.date(from: comps)!), 6, "easy", mood: mood)
    }
}

@Suite("TrendsMoodRead")
struct TrendsMoodReadTests {

    /// A tired day after a hard session is training working. Counting it would
    /// put the headline in the red through every honest build.
    @Test("tired is not a low day; struggling and injured are")
    func tiredIsNotLow() {
        #expect(TrendsMoodRead.isLow("tired") == false)
        #expect(TrendsMoodRead.isLow("struggling"))
        #expect(TrendsMoodRead.isLow("injured"))
        #expect(TrendsMoodRead.lowCount(["tired", "tired", "struggling"]) == 1)
    }

    /// An unrecognised label is a vocabulary drift. It must show up as a
    /// missing day, never as a day quietly bucketed somewhere.
    @Test("an unrecognised label is dropped, not bucketed")
    func unknownLabelIsDropped() {
        #expect(TrendsMoodRead.isLogged("elated") == false)
        #expect(TrendsMoodRead.isLogged("") == false)
        #expect(TrendsMoodRead.isLogged(nil) == false)
        #expect(TrendsMoodRead.counts(["elated", "tired"]) == ["tired": 1])
    }

    /// Two files hold this vocabulary for two reasons — one draws it, one
    /// counts it — and neither may drift.
    @Test("the vocabulary matches the palette's, in the same order")
    func vocabularyMatchesPalette() {
        #expect(TrendsMoodRead.vocabulary == TrendsMoodColor.ordered)
    }

    /// Four scattered days and four in a row are not the same fortnight, and
    /// the count alone cannot tell them apart. This is what the sentence under
    /// the header exists to say.
    @Test("the longest run distinguishes clustered from scattered")
    func longestRunSeesClustering() {
        let scattered: [String?] = ["struggling", "positive", "struggling", "positive", "struggling"]
        let clustered: [String?] = ["struggling", "struggling", "struggling", "positive", "positive"]

        #expect(TrendsMoodRead.lowCount(scattered) == 3)
        #expect(TrendsMoodRead.lowCount(clustered) == 3)
        #expect(TrendsMoodRead.longestLowRun(scattered) == 1)
        #expect(TrendsMoodRead.longestLowRun(clustered) == 3)
    }

    /// An unlogged day is not evidence of a bad one, so it breaks the run
    /// rather than bridging it. This under-claims on purpose.
    @Test("a day with no log breaks a low run rather than bridging it")
    func unloggedDayBreaksTheRun() {
        #expect(TrendsMoodRead.longestLowRun(["struggling", nil, "struggling"]) == 1)
    }

    /// One day of movement is not a trend. The header would otherwise announce
    /// a direction every single fortnight.
    @Test("the move needs two days of change before it calls a direction")
    func moveHasSlack() {
        #expect(TrendsMoodRead.Move.of(now: 4, then: 3) == .flat)
        #expect(TrendsMoodRead.Move.of(now: 2, then: 3) == .flat)
        #expect(TrendsMoodRead.Move.of(now: 5, then: 3) == .worse)
        #expect(TrendsMoodRead.Move.of(now: 1, then: 3) == .better)
    }
}

@Suite("TrendsMoodBlocks")
struct TrendsMoodBlockTests {

    /// Stepping back must not quietly shorten the window — an 11-day "block"
    /// would still call itself fourteen days and move the denominator under
    /// the headline.
    @Test("a block is always exactly fourteen days, or nil")
    func blocksAreWholeOrAbsent() {
        let days = run(42, mood: "neutral")

        #expect(TrendsMoodBlocks.block(days: days, keySessions: [], blocksBack: 0)?.dayCount == 14)
        #expect(TrendsMoodBlocks.block(days: days, keySessions: [], blocksBack: 2)?.dayCount == 14)
        #expect(TrendsMoodBlocks.block(days: days, keySessions: [], blocksBack: 3) == nil)
        #expect(TrendsMoodBlocks.maxBlocksBack(dayCount: 42) == 2)
    }

    @Test("stepping back moves the window a whole fortnight, without overlap")
    func blocksDoNotOverlap() {
        let days = run(42, mood: "neutral")
        let latest = TrendsMoodBlocks.block(days: days, keySessions: [], blocksBack: 0)
        let older = TrendsMoodBlocks.block(days: days, keySessions: [], blocksBack: 1)

        #expect(older?.buckets.last?.startISO == days[27].date)
        #expect(latest?.buckets.first?.startISO == days[28].date)
    }

    @Test("a timeline shorter than one block has nothing to show")
    func shortTimelineHasNoBlock() {
        #expect(TrendsMoodBlocks.block(days: run(13, mood: "positive"), keySessions: [], blocksBack: 0) == nil)
        #expect(TrendsMoodBlocks.maxBlocksBack(dayCount: 13) == 0)
    }

    /// The headline counts THIS block and compares it with the one before, so
    /// stepping back moves both halves of the claim together.
    @Test("the headline counts the block, against the block before it")
    func headlineCountsTheBlock() {
        var days = run(28, mood: "positive")
        for i in 14..<21 { days[i] = day(days[i].date, 6, "easy", mood: "struggling") }
        for i in 2..<4 { days[i] = day(days[i].date, 6, "easy", mood: "injured") }

        let latest = TrendsMoodBlocks.block(days: days, keySessions: [], blocksBack: 0)
        let older = TrendsMoodBlocks.block(days: days, keySessions: [], blocksBack: 1)

        #expect(latest?.dayCount == 14)
        #expect(latest?.lowDays == 7)
        #expect(older?.lowDays == 2)
        #expect(TrendsMoodRead.Move.of(now: 7, then: 2) == .worse)
    }

    @Test("a fortnight with few logs is marked as thin")
    func thinFortnightIsMarked() {
        var days = run(14, mood: nil)
        for i in 10..<14 { days[i] = day(days[i].date, 6, "easy", mood: "struggling") }

        let block = TrendsMoodBlocks.block(days: days, keySessions: [], blocksBack: 0)
        #expect(block?.loggedDays == 4)
        #expect(block?.isThin == true)
        #expect(block?.lowDays == 4)
    }

    @Test("a fully logged fortnight is not marked as thin")
    func fullFortnightIsNotThin() {
        let block = TrendsMoodBlocks.block(days: run(14, mood: "positive"), keySessions: [], blocksBack: 0)
        #expect(block?.loggedDays == 14)
        #expect(block?.isThin == false)
    }

    @Test("the block's counts read off the days it actually holds")
    func blockCounts() {
        var days = run(14, mood: "positive")
        days[3] = day(days[3].date, 6, "easy", mood: "struggling", niggle: ("calf", "sore"))
        days[4] = day(days[4].date, 6, "easy", mood: "injured", niggle: ("calf", "pain"))

        let block = TrendsMoodBlocks.block(days: days, keySessions: [], blocksBack: 0)

        #expect(block?.loggedDays == 14)
        #expect(block?.lowDays == 2)
        #expect(block?.longestLowRun == 2)
        #expect(block?.niggleDays == 2)
        #expect(block?.topNiggleArea == "calf")
        #expect(block?.counts["positive"] == 12)
    }
}
