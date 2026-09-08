//
//  TrendsQualityLoadTests.swift
//  RunningLogTests
//
//  Pins the effort score, the gate, and the Mon-first calendar maths behind
//  the Key Sessions grid. The floor cases use the real numbers this was
//  calibrated on (23 lap-scored sessions in prod, 2026-07-27), so a future
//  change to the weights or the floor fails here loudly rather than quietly
//  re-admitting stride sets as key sessions.
//

import Testing
@testable import RunningLog

@Suite("Trends quality load")
struct TrendsQualityLoadTests {

    // MARK: weights

    @Test("Zone weights mirror the canonical 1–8 scale")
    func zoneWeightsMatchBackend() {
        // These must equal ZONE_WEIGHTS in _shared/workoutSegmentation.ts.
        // moderate/steady reweighted 2026-08-11 to remove the steady→MP cliff.
        #expect(TrendsZoneWeight.weight("moderate") == 1.4)
        #expect(TrendsZoneWeight.weight("steady") == 2.15)
        #expect(TrendsZoneWeight.weight("mp") == 2.5)
        #expect(TrendsZoneWeight.weight("hmp") == 3.25)
        #expect(TrendsZoneWeight.weight("10k") == 4.0)
        #expect(TrendsZoneWeight.weight("5k") == 5.5)
        #expect(TrendsZoneWeight.weight("3k") == 6.75)
        #expect(TrendsZoneWeight.weight("mile") == 8.0)
        #expect(TrendsZoneWeight.weight("easy") == 1.0)
    }

    @Test("An unknown zone weighs 1.0 rather than inflating the score")
    func unknownZoneIsNeutral() {
        #expect(TrendsZoneWeight.weight("threshold") == 1.0)
        #expect(TrendsZoneWeight.weight("") == 1.0)
    }

    @Test("Zone lookup is case-insensitive")
    func zoneLookupIgnoresCase() {
        #expect(TrendsZoneWeight.weight("HMP") == 3.25)
        #expect(TrendsZoneWeight.weight("Mile") == 8.0)
    }

    // MARK: the score

    @Test("One bout scores seconds × weight ÷ 60")
    func singleBoutScore() {
        // 30 minutes at HMP → 1800 × 3.25 / 60 = 97.5
        #expect(QualityLoad.score(workSeconds: 1800, zone: "hmp") == 97.5)
        // 10 minutes at 5K → 600 × 5.5 / 60 = 55
        #expect(QualityLoad.score(workSeconds: 600, zone: "5k") == 55)
    }

    @Test("Zero or negative work seconds score zero, never NaN")
    func degenerateBoutsScoreZero() {
        #expect(QualityLoad.score(workSeconds: 0, zone: "mile") == 0)
        #expect(QualityLoad.score(workSeconds: -60, zone: "mile") == 0)
    }

    @Test("Load is the SUM across bouts, not the average")
    func loadIntegratesRatherThanAverages() {
        // A rep session: 5×3min at 5K, plus a 20min MP block in the same run.
        let bouts: [(seconds: Double, zone: String)] = [
            (180, "5k"), (180, "5k"), (180, "5k"), (180, "5k"), (180, "5k"),
            (1200, "mp"),
        ]
        // 900×5.5/60 = 82.5, plus 1200×2.5/60 = 50 → 132.5
        #expect(QualityLoad.total(bouts) == 132.5)

        // The retired whole-workout intensity_score would have divided the
        // weighted sum by total time and produced ~3.1 — a number that says
        // nothing about how big the session was. Guard the distinction.
        let totalSeconds = bouts.reduce(0) { $0 + $1.seconds }
        #expect(QualityLoad.total(bouts) > totalSeconds / 60)
    }

    @Test("An empty bout list scores zero")
    func emptyBoutsScoreZero() {
        #expect(QualityLoad.total([]) == 0)
    }

    // MARK: the gate — calibrated against real prod sessions

    @Test("Real stride sets fall below the floor")
    func stridesAreGatedOut() {
        // Measured loads of the four sub-floor sessions in prod.
        for strideLoad in [5.4, 6.4, 11.7, 13.1] {
            #expect(QualityLoad.qualifies(strideLoad) == false)
        }
    }

    @Test("Real sessions clear the floor")
    func realSessionsQualify() {
        // The smallest and largest genuine sessions in the same window.
        for sessionLoad in [42.1, 49.8, 55.8, 87.3, 103.5] {
            #expect(QualityLoad.qualifies(sessionLoad) == true)
        }
    }

    @Test("The floor sits inside the empty gap, so its exact value is not load-bearing")
    func floorSitsInTheGap() {
        // Largest stride set 13.1, smallest real session 42.1, nothing between.
        #expect(QualityLoad.floor > 13.1)
        #expect(QualityLoad.floor < 42.1)
    }

    @Test("A missing load never promotes a session")
    func nilLoadDoesNotQualify() {
        // An older payload with no quality_load must not silently pass the gate.
        #expect(QualityLoad.qualifies(nil) == false)
    }

    @Test("The floor is inclusive at the boundary")
    func floorIsInclusive() {
        #expect(QualityLoad.qualifies(QualityLoad.floor) == true)
        #expect(QualityLoad.qualifies(QualityLoad.floor - 0.01) == false)
    }

    // MARK: calendar maths

    @Test("Weekday index is Mon = 0 through Sun = 6")
    func weekdayIndexIsMondayFirst() {
        // 2026-07-27 is a Monday.
        #expect(TrendsWeekday.index(from: "2026-07-27") == 0)
        #expect(TrendsWeekday.index(from: "2026-07-28") == 1)  // Tue
        #expect(TrendsWeekday.index(from: "2026-07-29") == 2)  // Wed
        #expect(TrendsWeekday.index(from: "2026-07-30") == 3)  // Thu
        #expect(TrendsWeekday.index(from: "2026-07-31") == 4)  // Fri
        #expect(TrendsWeekday.index(from: "2026-08-01") == 5)  // Sat
        #expect(TrendsWeekday.index(from: "2026-08-02") == 6)  // Sun
    }

    @Test("A datetime string is accepted, not just a bare date")
    func weekdayIndexAcceptsDatetime() {
        #expect(TrendsWeekday.index(from: "2026-07-28T14:30:00Z") == 1)
    }

    @Test("An unparseable date yields nil rather than defaulting to Monday")
    func badDateYieldsNil() {
        #expect(TrendsWeekday.index(from: "not-a-date") == nil)
        #expect(TrendsWeekday.index(from: "") == nil)
        #expect(TrendsWeekday.weekStart(from: "2026-13-99") == nil)
    }

    @Test("Week start is the Monday of that date's week")
    func weekStartIsMonday() {
        // Every day of the week of Mon 2026-07-27 maps to that Monday.
        for day in ["2026-07-27", "2026-07-29", "2026-08-01", "2026-08-02"] {
            #expect(TrendsWeekday.weekStart(from: day) == "2026-07-27")
        }
        // Sun 2026-08-02 belongs to the week that began six days EARLIER, not
        // the one about to start — the off-by-one a Sun-first calendar makes.
        #expect(TrendsWeekday.weekStart(from: "2026-08-02") == "2026-07-27")
        // And the next Monday does open a new week.
        #expect(TrendsWeekday.weekStart(from: "2026-08-03") == "2026-08-03")
    }

    @Test("Week start crosses month and year boundaries correctly")
    func weekStartCrossesBoundaries() {
        // Thu 2026-01-01 sits in the week beginning Mon 2025-12-29.
        #expect(TrendsWeekday.weekStart(from: "2026-01-01") == "2025-12-29")
    }

    @Test("Row labels and names are seven long and Mon-first")
    func rowLabelsAreWellFormed() {
        #expect(TrendsWeekday.initials.count == 7)
        #expect(TrendsWeekday.names.count == 7)
        #expect(TrendsWeekday.initials.first == "M")
        #expect(TrendsWeekday.names.first == "Mon")
        #expect(TrendsWeekday.names.last == "Sun")
    }
}
