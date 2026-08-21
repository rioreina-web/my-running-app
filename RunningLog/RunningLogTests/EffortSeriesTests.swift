//
//  EffortSeriesTests.swift
//  RunningLogTests
//
//  Sampling / smoothing / derivation for the Effort chart engine.
//

import Foundation
import Testing
@testable import RunningLog

@Suite("EffortFormat")
struct EffortFormatTests {
    @Test("pace 365 s formats as 6:05")
    func paceMMSS() {
        #expect(EffortFormat.pace(365) == "6:05")
    }

    @Test("pace rounds to the nearest second")
    func paceRounds() {
        #expect(EffortFormat.pace(364.6) == "6:05")
        #expect(EffortFormat.pace(360) == "6:00")
    }

    @Test("pace never prints a :60 boundary")
    func paceBoundary() {
        // 419.7 → 420 → 7:00, not 6:60
        #expect(EffortFormat.pace(419.7) == "7:00")
    }

    @Test("clock formats seconds-from-start as m:ss")
    func clock() {
        #expect(EffortFormat.clock(5920) == "98:40")
        #expect(EffortFormat.clock(65) == "1:05")
    }

    @Test("delta uses a true minus sign")
    func delta() {
        #expect(EffortFormat.deltaSeconds(-4) == "\u{2212}4s")
        #expect(EffortFormat.deltaSeconds(2) == "+2s")
        #expect(EffortFormat.deltaSeconds(0) == "0s")
    }
}

@Suite("EffortSeries.smooth")
struct EffortSmoothTests {
    @Test("centered mean over ±2 samples")
    func centered() {
        let v = [10.0, 10, 10, 10, 10]
        #expect(EffortSeries.smooth(v) == [10, 10, 10, 10, 10])
    }

    @Test("edges clamp the window")
    func edges() {
        let v = [0.0, 10, 20, 30, 40]
        let s = EffortSeries.smooth(v)
        // i=0: mean(0,10,20)=10 ; i=4: mean(20,30,40)=30
        #expect(abs(s[0] - 10) < 1e-9)
        #expect(abs(s[4] - 30) < 1e-9)
        // i=2: mean(0,10,20,30,40)=20
        #expect(abs(s[2] - 20) < 1e-9)
    }

    @Test("a single sample is returned unchanged")
    func single() {
        #expect(EffortSeries.smooth([42]) == [42])
    }
}

@Suite("EffortSeries.mileMarks")
struct EffortMileMarkTests {
    @Test("marks land at integer-mile crossings, monotonic, ~14 for the session")
    func sessionMarks() {
        let (samples, _) = EffortFixtures.session()
        let marks = EffortSeries.mileMarks(samples)
        #expect(marks.count >= 13)                 // ~14.4 mi session
        #expect(marks.first?.mile == 1)
        // strictly increasing mile numbers and times
        for i in 1..<marks.count {
            #expect(marks[i].mile == marks[i - 1].mile + 1)
            #expect(marks[i].t > marks[i - 1].t)
        }
    }

    @Test("no marks before the first mile")
    func none() {
        let s = [EffortSample(t: 0, distanceMiles: 0, hr: 0, paceSecPerMile: 600, cadenceSPM: 0, elevationFt: 0),
                 EffortSample(t: 4, distanceMiles: 0.5, hr: 0, paceSecPerMile: 600, cadenceSPM: 0, elevationFt: 0)]
        #expect(EffortSeries.mileMarks(s).isEmpty)
    }
}

@Suite("EffortSeries.resample")
struct EffortResampleTests {
    @Test("resamples toward ~1 point per 2.2 pt of width")
    func density() {
        let (samples, _) = EffortFixtures.session()
        let full = 0.0...5920.0
        let pts = EffortSeries.resample(samples, window: full, plotWidth: 350,
                                        sampleInterval: 4) { $0.paceSecPerMile }
        // bucket = (5920/350)*2.2 ≈ 37.2 s → ~5920/37.2 ≈ 159 points; loosely 120…220.
        #expect(pts.count > 100 && pts.count < 260)
        // times are increasing
        for i in 1..<pts.count { #expect(pts[i].t >= pts[i - 1].t) }
    }

    @Test("a narrow window keeps the raw sample interval as the floor")
    func floor() {
        let (samples, _) = EffortFixtures.session()
        // 40 s window / big width → bucket floored at sampleInterval (4 s) → ~10 pts
        let pts = EffortSeries.resample(samples, window: 100.0...140.0, plotWidth: 800,
                                        sampleInterval: 4) { $0.hr }
        #expect(pts.count >= 8 && pts.count <= 12)
    }
}

@Suite("EffortSeries.repStats / workShare")
struct EffortRepStatTests {
    @Test("per-rep mean pace and delta vs target")
    func repStats() {
        let (samples, segments) = EffortFixtures.session()
        let stats = EffortSeries.repStats(samples, segments: segments, targetPaceSecPerMile: 365)
        #expect(stats.count == 5)
        #expect(stats[0].label == "R1")
        #expect(abs(stats[0].meanPace - 366) < 1)         // R1 ≈ 6:06
        #expect(abs(stats[0].deltaVsTarget - 1) < 1)      // +1 s vs 6:05 target
        #expect(stats[4].deltaVsTarget < 0)               // R5 (5:57) faster than target
    }

    @Test("workShare of the fixture session ≈ 0.61")
    func workShare() {
        let (samples, segments) = EffortFixtures.session()
        let pts = samples.map { EffortPoint(t: $0.t, value: $0.paceSecPerMile) }
        let share = EffortSeries.workShare(points: pts, segments: segments)
        #expect(abs(share - 0.615) < 0.02)
    }
}
