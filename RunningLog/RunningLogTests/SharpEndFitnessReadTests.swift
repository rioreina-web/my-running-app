//
//  SharpEndFitnessReadTests.swift
//  RunningLogTests
//
//  Covers the maths behind the "Are you getting fitter?" read — the part that
//  must be right even though the chart can't be unit-tested. Mirrors the
//  Testing-framework style of TrendsAggregationTests.swift.
//

import Foundation
import Testing
@testable import RunningLog

@Suite("FitnessRead")
struct FitnessReadTests {

    /// Minimal FastSession for the read: only the fields the maths touches.
    private func sess(_ date: String, pace: Int, hr: Int?, feels: Int? = 60, miles: Double = 5) -> FastSession {
        FastSession(
            id: date, date: date, dateLabel: date, name: "s",
            repCount: 6, fastMiles: miles, avgPaceSec: pace,
            neutralPaceSec: nil, avgHr: hr, densityPct: 70, avgRestSec: 60,
            metersPerBeat: nil, feelsF: feels, bySystem: []
        )
    }

    // MARK: heat-adjusted effort

    @Test("heat offset: none in the cool, capped in the heat")
    func heatOffset() {
        #expect(FastSession.heatHrOffset(feelsF: 60) == 0)
        #expect(FastSession.heatHrOffset(feelsF: 68) == 0)
        #expect(FastSession.heatHrOffset(feelsF: 80) == 4)   // (80-68)*0.30 = 3.6 → 4
        #expect(FastSession.heatHrOffset(feelsF: 120) == 12) // capped
        #expect(FastSession.heatHrOffset(feelsF: nil) == 0)
    }

    @Test("effortHr pulls a hot-day HR back toward its cool equivalent")
    func effortHr() {
        let hot = sess("2026-07-01", pace: 300, hr: 170, feels: 90)
        #expect(hot.effortHr(heat: false) == 170)
        #expect(hot.effortHr(heat: true) == 170 - FastSession.heatHrOffset(feelsF: 90))
        let noHR = sess("2026-07-02", pace: 300, hr: nil)
        #expect(noHR.effortHr(heat: true) == nil)
    }

    // MARK: the gain

    @Test("a block that gets faster at fixed effort reads as a positive gain")
    func improving() {
        // 12 sessions, HR held at 165, pace falling 322 → 300.
        var rows: [FastSession] = []
        for i in 0..<12 {
            let pace = 322 - i * 2
            rows.append(sess("2026-03-\(String(format: "%02d", i + 1))", pace: pace, hr: 165))
        }
        let r = FitnessRead.compute(sessions: rows, heat: false, hills: false)
        #expect(r.hasVerdict)
        #expect(r.gain > 8)                       // clearly faster now
        #expect(Int(r.midHr) == 165)
        #expect(r.recentLevel < r.earlyLevel)     // faster = lower pace
    }

    @Test("a flat block reads as no gain")
    func flat() {
        var rows: [FastSession] = []
        for i in 0..<12 { rows.append(sess("2026-03-\(String(format: "%02d", i + 1))", pace: 310, hr: 165)) }
        let r = FitnessRead.compute(sessions: rows, heat: false, hills: false)
        #expect(abs(r.gain) < 1.0)
    }

    @Test("too few sessions withholds a verdict")
    func smallN() {
        let rows = (0..<5).map { sess("2026-03-0\($0 + 1)", pace: 310 - $0, hr: 165) }
        let r = FitnessRead.compute(sessions: rows, heat: false, hills: false)
        #expect(!r.hasVerdict)
    }

    @Test("sessions without heart rate are dropped, not plotted")
    func dropsMissingHR() {
        let rows = [
            sess("2026-03-01", pace: 310, hr: 165),
            sess("2026-03-02", pace: 308, hr: nil),
            sess("2026-03-03", pace: 306, hr: 166),
        ]
        let r = FitnessRead.compute(sessions: rows, heat: false, hills: false)
        #expect(r.plotted.count == 2)
    }

    // MARK: stats helpers

    @Test("linfit recovers a known line")
    func linfit() {
        let line = FitnessRead.linfit([1, 2, 3, 4], [3, 5, 7, 9]) // y = 2x + 1
        #expect(abs(line.slope - 2) < 1e-9)
        #expect(abs(line.intercept - 1) < 1e-9)
    }

    @Test("median handles odd and even counts")
    func median() {
        #expect(FitnessRead.median([3, 1, 2]) == 2)
        #expect(FitnessRead.median([4, 1, 3, 2]) == 2.5)
    }
}
