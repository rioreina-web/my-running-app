//
//  WeekTrainingLoadTests.swift
//  RunningLogTests
//
//  Guards the two things `WeekTrainingLoadSection` can silently get wrong:
//  the circle sizing, and the zone taxonomy reconciliation between the
//  backend's vocabulary and the colour ramp's.
//
//  The marimekko width tests that used to live here went with the marimekko
//  on 2026-08-11 — `columnWidths` no longer exists. The failure mode they
//  guarded (one day silently swallowing the row) is now `dotDiameter`'s.
//
//  The load maths itself is NOT retested here — it is `QualityLoad.score`,
//  already pinned by `TrendsQualityLoadTests`. Asserting it a second time
//  against literals is how the two copies drift apart.
//

import Testing
import SwiftUI
@testable import RunningLog

@Suite("Week training load")
struct WeekTrainingLoadTests {

    typealias S = WeekTrainingLoadSection

    // MARK: Circle sizing

    @Test("area is proportional to miles, so diameter goes as the square root")
    func areaNotDiameter() {
        // 20 miles is 4x 5 miles. If the diameter scaled directly the big day
        // would be drawn with 16x the ink — the classic circle-chart lie.
        let big   = S.dotDiameter(miles: 20, maxMiles: 20, maxDiameter: 46, minDiameter: 11)
        let small = S.dotDiameter(miles: 5,  maxMiles: 20, maxDiameter: 46, minDiameter: 11)

        #expect(abs(big - 46) < 0.01)
        #expect(abs(small - 23) < 0.01)          // √(5/20) = 0.5
        #expect(abs(big / small - 2.0) < 0.01)   // 2x the diameter…
        // …and therefore 4x the area, matching 4x the miles.
        let areaRatio = (big * big) / (small * small)
        #expect(abs(areaRatio - 4.0) < 0.05)
    }

    @Test("the week's biggest day exactly fills the slot")
    func biggestFillsSlot() {
        #expect(abs(S.dotDiameter(miles: 13.1, maxMiles: 13.1,
                                  maxDiameter: 46, minDiameter: 11) - 46) < 0.01)
    }

    @Test("a shakeout stays visible instead of rendering as a speck")
    func floorHolds() {
        // √(0.5/22) x 46 ≈ 6.9pt, below the floor and below a tappable mark.
        let d = S.dotDiameter(miles: 0.5, maxMiles: 22, maxDiameter: 46, minDiameter: 11)
        #expect(d == 11)
    }

    @Test("a day that did not run gets no circle at all")
    func restIsZero() {
        #expect(S.dotDiameter(miles: 0, maxMiles: 22, maxDiameter: 46, minDiameter: 11) == 0)
        #expect(S.dotDiameter(miles: -3, maxMiles: 22, maxDiameter: 46, minDiameter: 11) == 0)
    }

    @Test("no day can overflow the slot, even if miles exceed the week max")
    func neverOverflows() {
        // Defensive: `maxMiles` is derived from the same days, so this should
        // be unreachable — but a circle wider than its column would collide
        // with its neighbours rather than clip.
        let d = S.dotDiameter(miles: 30, maxMiles: 20, maxDiameter: 46, minDiameter: 11)
        #expect(d == 46)
    }

    @Test("a degenerate week does not divide by zero or emit NaN")
    func degenerate() {
        let d = S.dotDiameter(miles: 5, maxMiles: 0, maxDiameter: 46, minDiameter: 11)
        #expect(d == 11)
        #expect(d.isFinite)

        let z = S.dotDiameter(miles: 5, maxMiles: 20, maxDiameter: 0, minDiameter: 11)
        #expect(z == 11)
    }

    // MARK: Circle colour

    // A day's circle is filled by the zone that carried the most LOAD. The
    // load bar these replaced was cut on 2026-08-11 as one object too many.

    @Test("colour follows load, not mileage")
    func dominantIsByLoad() throws {
        // A session: 6 easy miles (48 min, weight 1.0 -> 48) plus 4 at 5K
        // (21 min, weight 5.5 -> 115). Easy has more MILES; 5K did the work.
        let day = makeDay(zones: [
            S.ZoneTotal(token: "easy", miles: 6.0, minutes: 48, load: 48),
            S.ZoneTotal(token: "5k",   miles: 4.0, minutes: 21, load: 115),
        ])
        let z = try #require(day.dominantZone)
        #expect(z.token == "5k")
    }

    @Test("a genuinely easy day still reads easy")
    func easyStaysEasy() throws {
        // The rule must not just pick the fastest zone present. A long run
        // with a few strides is an easy day and has to colour as one.
        let day = makeDay(zones: [
            S.ZoneTotal(token: "easy", miles: 15.0, minutes: 120, load: 120),
            S.ZoneTotal(token: "mile", miles: 0.3,  minutes: 1.5, load: 12),
        ])
        let z = try #require(day.dominantZone)
        #expect(z.token == "easy")
    }

    @Test("a run without laps has no dominant zone, so it cannot be coloured")
    func noZonesNoColour() {
        // Nil here is what drives the paper-deep fill. Falling back to easy
        // would assert a pace for a run whose pace never arrived.
        #expect(makeDay(zones: []).dominantZone == nil)
    }

    /// Minimal LoadDay for colour tests — only `zones` matters here.
    private func makeDay(zones: [S.ZoneTotal]) -> S.LoadDay {
        S.LoadDay(
            date: Date(timeIntervalSince1970: 0), label: "MON",
            miles: zones.reduce(0) { $0 + $1.miles },
            minutes: zones.reduce(0) { $0 + $1.minutes },
            zones: zones,
            load: zones.reduce(0) { $0 + $1.load },
            timeMin: zones.reduce(0) { $0 + $1.minutes },
            zonedMiles: zones.reduce(0) { $0 + $1.miles },
            mood: nil, niggle: nil, isRest: false, isFuture: false
        )
    }

    // MARK: Taxonomy

    @Test("recovery folds into easy — both weigh 1.0, so a separate row is noise")
    func recoveryFolds() {
        #expect(ZoneTaxonomy.normalise("recovery") == "easy")
        #expect(ZoneTaxonomy.color("recovery") == ZoneTaxonomy.color("easy"))
    }

    @Test("every backend zone maps to a distinct ramp stop")
    func zonesAreDistinct() {
        let colors = ZoneTaxonomy.ordered.map { ZoneTaxonomy.color($0) }
        #expect(Set(colors.map { $0.description }).count == ZoneTaxonomy.ordered.count)
    }

    @Test("ordering is slow to fast, so the ramp reads pale to navy")
    func ordering() {
        let shuffled = ["5k", "easy", "mp", "mile", "steady"]
        let sorted = shuffled.sorted { ZoneTaxonomy.rank($0) < ZoneTaxonomy.rank($1) }
        #expect(sorted == ["easy", "steady", "mp", "5k", "mile"])
    }

    @Test("an unrecognised zone is kept as volume, not dropped")
    func unknownZone() {
        // A zone added to the backend before this client knows about it must
        // still render — silently discarding it would make the zone table
        // disagree with the day's mileage.
        #expect(ZoneTaxonomy.normalise("ultra") == "easy")
        #expect(ZoneTaxonomy.rank("ultra") == 0)
    }

    // MARK: Average pace

    @Test("zone average pace is time over distance, not a mean of means")
    func timeWeightedPace() throws {
        // 3 mi at 8:30 (25.5 min) + 12 mi at 8:02 (96.4 min) = 15 mi, 121.9 min
        // → 8:07/mi. A mean of the two paces gives 8:16 and is wrong.
        let z = S.ZoneTotal(token: "easy", miles: 15.0, minutes: 121.9, load: 121.9)
        let pace = try #require(z.avgPaceSec)
        #expect(abs(pace - 487.6) < 1.0)      // 8:07.6
        #expect(abs(pace - 496.0) > 5.0)      // definitively not 8:16
    }

    @Test("a zone with no distance reports no pace rather than infinity")
    func noDistanceNoPace() {
        let z = S.ZoneTotal(token: "easy", miles: 0, minutes: 10, load: 10)
        #expect(z.avgPaceSec == nil)
    }
}
