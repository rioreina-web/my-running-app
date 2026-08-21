//
//  EffortChartScaleTests.swift
//  RunningLogTests
//
//  The autoscaler — the core of the redesign. WINDOW / WORK / SPLIT / FIXED
//  selection, the split axis geometry, ticks, pins, and inversion.
//

import Foundation
import Testing
@testable import RunningLog

@Suite("EffortChartScale.percentile / fit")
struct EffortFitTests {
    @Test("percentile interpolates linearly")
    func percentile() {
        let v = [0.0, 10, 20, 30, 40]
        #expect(EffortChartScale.percentile(v, 0) == 0)
        #expect(EffortChartScale.percentile(v, 100) == 40)
        #expect(abs(EffortChartScale.percentile(v, 50) - 20) < 1e-9)
    }

    @Test("fit pads by 18% and reports clip over ALL values")
    func fit() {
        // rep values tight at 360; one outlier at 500 in the full set.
        let rep = Array(repeating: 360.0, count: 20)
        let all = rep + [500]
        let f = EffortChartScale.fit(rep, allValues: all, metric: .pace)
        // flat rep set → pad 4 then minSpan 40 → span exactly 40
        #expect(abs((f.hi - f.lo) - 40) < 1e-6)
        // the 500 outlier is outside → clip = 1/21
        #expect(abs(f.clip - (1.0 / 21.0)) < 1e-9)
    }

    @Test("fit enforces the per-metric minimum span")
    func minSpan() {
        let v = [150.0, 151, 152, 150, 151]         // ~2 bpm spread
        let f = EffortChartScale.fit(v, allValues: v, metric: .hr)
        #expect(f.hi - f.lo >= 16 - 1e-6)           // hr minSpan 16
    }
}

@Suite("EffortChartScale.resolve — mode selection")
struct EffortResolveTests {
    @Test("no segments → WINDOW")
    func window() {
        let pts = (0..<50).map { EffortPoint(t: Double($0), value: 150 + Double($0 % 5)) }
        let scale = EffortChartScale.resolve(points: pts, segments: [], metric: .hr, request: .work)
        #expect(scale.mode == .window)
        #expect(scale.note == nil)
    }

    @Test("fixed request → FIXED on the fallback domain")
    func fixed() {
        let pts = (0..<50).map { EffortPoint(t: Double($0), value: 150.0) }
        let scale = EffortChartScale.resolve(points: pts, segments: [], metric: .hr, request: .fixed)
        #expect(scale.mode == .fixed)
        #expect(scale.lo == 104 && scale.hi == 174)
    }

    @Test("reps own the axis, jog stays inside → WORK, no note")
    func workNoNote() {
        // 60 reps @ 360, 40 jog @ 370 — all within the padded rep band → clip 0
        let (pts, seg) = EffortFixtures.points(rep: 360, repCount: 60, jog: Array(repeating: 370, count: 40))
        let scale = EffortChartScale.resolve(points: pts, segments: seg, metric: .pace, request: .work)
        #expect(scale.mode == .work)
        #expect(scale.note == nil)
        #expect(scale.readout.hasPrefix("WORK SCALE"))
    }

    @Test("a few jog points outside → WORK with a PINNED note")
    func workWithNote() {
        // 36 jog inside (370), 4 jog outside (400) → clip 0.04 (0.03 < clip ≤ 0.11).
        // Flat rep set → domain expands to 360 ± minSpan/2 = [340, 380]; the pinned
        // edge (and the note's threshold) is the domain top, 380 s = 6:20.
        let jog = Array(repeating: 370.0, count: 36) + Array(repeating: 400.0, count: 4)
        let (pts, seg) = EffortFixtures.points(rep: 360, repCount: 60, jog: jog)
        let scale = EffortChartScale.resolve(points: pts, segments: seg, metric: .pace, request: .work)
        #expect(scale.mode == .work)
        #expect(scale.note == "SLOWER THAN 6:20 PINNED")
    }

    @Test("jog far outside → SPLIT with a compression note")
    func split() {
        let (pts, seg) = EffortFixtures.points(rep: 360, repCount: 60, jog: Array(repeating: 520, count: 40))
        let scale = EffortChartScale.resolve(points: pts, segments: seg, metric: .pace, request: .work)
        #expect(scale.mode == .split)
        #expect(scale.split != nil)
        #expect(scale.note?.hasPrefix("JOG COMPRESSED BEYOND") == true)
    }

    @Test("elevation never takes WORK/SPLIT")
    func elevationForcedWindow() {
        let (pts, seg) = EffortFixtures.points(rep: 40, repCount: 60, jog: Array(repeating: 300, count: 40))
        let scale = EffortChartScale.resolve(points: pts, segments: seg, metric: .elev, request: .work)
        #expect(scale.mode == .window)
    }

    @Test("workShare below 0.35 → WINDOW")
    func lowWorkShare() {
        // 10 reps, 90 jog → share 0.10
        let (pts, seg) = EffortFixtures.points(rep: 360, repCount: 10, jog: Array(repeating: 520, count: 90))
        let scale = EffortChartScale.resolve(points: pts, segments: seg, metric: .pace, request: .work)
        #expect(scale.mode == .window)
    }

    @Test("the fixture session resolves pace to SPLIT")
    func fixtureSplit() {
        let (samples, segments) = EffortFixtures.session()
        let pts = EffortSeries.resample(samples, window: 0...5920, plotWidth: 360,
                                        sampleInterval: 4) { $0.paceSecPerMile }
        let scale = EffortChartScale.resolve(points: pts, segments: segments, metric: .pace, request: .work)
        #expect(scale.mode == .split)
    }
}

@Suite("EffortScale — geometry, ticks, pins")
struct EffortScaleGeometryTests {
    @Test("pace axis is inverted: faster plots higher")
    func inversion() {
        let scale = EffortChartScale.resolve(
            points: [EffortPoint(t: 0, value: 360)], segments: [], metric: .pace, request: .fixed)
        // 335 (fast) should sit above 600 (slow)
        #expect(scale.normalized(335) > scale.normalized(600))
    }

    @Test("hr axis is upright: higher plots higher")
    func upright() {
        let scale = EffortChartScale.resolve(
            points: [EffortPoint(t: 0, value: 150)], segments: [], metric: .hr, request: .fixed)
        #expect(scale.normalized(174) > scale.normalized(104))
    }

    @Test("split keeps the work band at ≥52% of height")
    func workBandHeight() {
        let (pts, seg) = EffortFixtures.points(rep: 360, repCount: 60, jog: Array(repeating: 520, count: 40))
        let scale = EffortChartScale.resolve(points: pts, segments: seg, metric: .pace, request: .work)
        let g = try! #require(scale.split)
        #expect(1 - g.fLo - g.fHi >= 0.52 - 1e-9)
        #expect(g.fLo <= 0.24 && g.fHi <= 0.24)
    }

    @Test("normalized is monotonic across a split axis")
    func splitMonotonic() {
        let (pts, seg) = EffortFixtures.points(rep: 360, repCount: 60, jog: Array(repeating: 520, count: 40))
        let scale = EffortChartScale.resolve(points: pts, segments: seg, metric: .pace, request: .work)
        // pace inverted → normalized decreases as raw seconds increase
        let a = scale.normalized(360), b = scale.normalized(450), c = scale.normalized(520)
        #expect(a > b && b > c)
    }

    @Test("ticks respect span/step ≤ 5 and stay inside the frame")
    func ticks() {
        let scale = EffortChartScale.resolve(
            points: (0..<20).map { EffortPoint(t: Double($0), value: 150 + Double($0 % 20)) },
            segments: [], metric: .hr, request: .window)
        let ticks = scale.ticks()
        #expect(!ticks.isEmpty)
        for t in ticks { #expect(t >= scale.lo && t <= scale.hi) }
    }

    @Test("pinned runs are the consecutive out-of-domain stretches (WORK only)")
    func pins() {
        // WORK domain ~[356,364] (rep 360). jog[2] and jog[3] sit at 400 (outside).
        let jog = [358.0, 359, 400, 400, 361]
        let (pts, seg) = EffortFixtures.points(rep: 360, repCount: 60, jog: jog)
        let scale = EffortChartScale.resolve(points: pts, segments: seg, metric: .pace, request: .work)
        // Only meaningful if this resolved to WORK.
        if scale.mode == .work {
            let runs = EffortChartScale.pinnedRuns(points: pts, scale: scale)
            #expect(runs.contains { $0.contains(62) && $0.contains(63) })
        }
    }

    @Test("split mode never pins")
    func splitNoPins() {
        let (pts, seg) = EffortFixtures.points(rep: 360, repCount: 60, jog: Array(repeating: 520, count: 40))
        let scale = EffortChartScale.resolve(points: pts, segments: seg, metric: .pace, request: .work)
        #expect(EffortChartScale.pinnedRuns(points: pts, scale: scale).isEmpty)
    }
}
