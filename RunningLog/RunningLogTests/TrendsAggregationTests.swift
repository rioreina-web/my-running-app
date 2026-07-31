import Foundation
import Testing
@testable import RunningLog

@Suite("TrendsAggregation.monthly")
struct TrendsAggregationMonthlyTests {

    private func wk(
        _ month: String, _ label: String,
        miles: Double, quality: Double, pace: Int?, mood: String,
        niggles: [String] = []
    ) -> TrendsWeek {
        TrendsWeek(
            month: month, dateLabel: label,
            miles: miles, qualityMiles: quality,
            keyPaceSec: pace, mood: mood, niggles: niggles
        )
    }

    @Test("rolls contiguous weeks into one row per month")
    func monthCount() {
        let weeks = [
            wk("Apr", "Apr 7",  miles: 40, quality: 9,  pace: 414, mood: "tired"),
            wk("Apr", "Apr 14", miles: 44, quality: 11, pace: 410, mood: "positive"),
            wk("May", "May 5",  miles: 50, quality: 14, pace: 405, mood: "tired"),
            wk("May", "May 12", miles: 52, quality: 15, pace: 402, mood: "tired"),
        ]
        let months = TrendsAggregation.monthly(weeks)
        #expect(months.count == 2)
        #expect(months.map(\.month) == ["Apr", "May"])
        #expect(months[0].dateLabel == "April")
    }

    @Test("sums miles and quality miles across the month")
    func sums() {
        let weeks = [
            wk("May", "May 5",  miles: 50, quality: 14, pace: 405, mood: "tired"),
            wk("May", "May 12", miles: 52, quality: 15, pace: 402, mood: "tired"),
        ]
        let may = TrendsAggregation.monthly(weeks)[0]
        #expect(may.miles == 102)
        #expect(may.qualityMiles == 29)
    }

    @Test("keyPace is the month's fastest key session")
    func fastestPace() {
        let weeks = [
            wk("Apr", "Apr 7",  miles: 40, quality: 9,  pace: 414, mood: "tired"),
            wk("Apr", "Apr 14", miles: 44, quality: 11, pace: 410, mood: "positive"),
        ]
        #expect(TrendsAggregation.monthly(weeks)[0].keyPaceSec == 410)
    }

    @Test("a month with no quality session has nil keyPace")
    func noQuality() {
        let weeks = [wk("Jun", "Jun 2", miles: 30, quality: 0, pace: nil, mood: "neutral")]
        #expect(TrendsAggregation.monthly(weeks)[0].keyPaceSec == nil)
    }

    @Test("mood is the modal mood; ties break to the most recent")
    func modalMood() {
        let weeks = [
            wk("May", "May 5",  miles: 50, quality: 14, pace: 405, mood: "tired"),
            wk("May", "May 12", miles: 52, quality: 15, pace: 402, mood: "positive"),
            wk("May", "May 19", miles: 49, quality: 13, pace: 403, mood: "tired"),
        ]
        #expect(TrendsAggregation.monthly(weeks)[0].mood == "tired")
    }

    @Test("niggles are the de-duplicated, verbatim union")
    func niggleUnion() {
        let weeks = [
            wk("May", "May 5",  miles: 50, quality: 14, pace: 405, mood: "tired", niggles: ["R achilles"]),
            wk("May", "May 12", miles: 52, quality: 15, pace: 402, mood: "tired", niggles: ["R achilles", "L hip"]),
        ]
        #expect(TrendsAggregation.monthly(weeks)[0].niggles == ["R achilles", "L hip"])
    }

    @Test("empty input yields no months")
    func empty() {
        #expect(TrendsAggregation.monthly([]).isEmpty)
    }
}
