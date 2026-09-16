import Foundation
import Testing
@testable import RunningLog

// Guards for the rules in `EfficiencyIndexModels.swift`. Each test encodes a
// decision from the 2026-08-18 validation on real exported data, not just a
// behaviour:
//
// Rule 1: the index is scored against the athlete's OWN curve — a point on
//         the curve reads 100, +3% m/beat reads 103, at any pace.
// Rule 2: long runs are IN the fit (they anchor the slow end; validated) and
//         grouped apart (different quantity, same curve).
// Rule 3: heat can cost the index, never pay it. The heat term needs 5
//         non-ideal sessions, clamps at zero, and never moves the threshold
//         stat (which is evaluated cool by definition).
// Rule 4: the outlier gate uses DELETED residuals, because a high-leverage
//         HR-lag artefact bends an ordinary fit toward itself and hides.
//         (Validated: 8×200 @ HR 136 — invisible to a plain residual gate.)
// Rule 5: too little data says NOT YET in words; exclusions are counted,
//         never silently deleted.

// MARK: - Fixtures

private let epochDay = 20_000

private func dayDate(_ offset: Int) -> Date {
    Date(timeIntervalSince1970: Double(epochDay + offset) * 86_400)
}

private func iso(_ offset: Int) -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    f.timeZone = TimeZone(secondsFromGMT: 0)
    f.locale = Locale(identifier: "en_US_POSIX")
    return f.string(from: dayDate(offset))
}

/// The reference athlete every fixture is built from: m/beat = c0 + c1·speed
/// exactly, minus a per-severity heat penalty when a fixture says so. Pace
/// and HR are integers, so fixtures land within rounding of the line —
/// assertions use tolerances sized to that rounding, not to slack.
private let c0 = 0.43
private let c1 = 0.0046

/// A session ON the athlete's line at the given pace: HR is derived from the
/// line (then rounded to a legal integer). `mpbScale` shifts the session off
/// the line — 1.03 builds a session 3% more efficient than the norm.
/// `heatPenaltyPerStep` carves the drift a hot session's HR carries.
private func session(
    day: Int,
    zone: String,
    paceSec: Int,
    kind: String = "quality",
    heat: String? = nil,          // non-ideal category; nil = ideal
    rawPaceSec: Int? = nil,       // for heat sessions: the slower watch pace
    mpbScale: Double = 1.0,
    heatPenaltyPerStep: Double = 0.0,
    hrOverride: Int? = nil
) -> KeySession {
    let speed = 1609.344 * 60 / Double(paceSec)
    let severity: Double
    switch heat?.lowercased() {
    case "warm": severity = 1
    case "hot": severity = 2
    case "very_hot": severity = 3
    case "dangerous": severity = 4
    default: severity = 0
    }
    let target = (c0 + c1 * speed - heatPenaltyPerStep * severity) * mpbScale
    let hr = hrOverride ?? Int((speed / target).rounded())
    return KeySession(
        id: "log-\(day)-\(zone)-\(paceSec)",
        date: iso(day),
        dateLabel: "D\(day)",
        zone: zone,
        workPaceSec: rawPaceSec ?? paceSec,
        workPaceAdjSec: heat != nil ? paceSec : nil,
        heatCategory: heat ?? "ideal",
        workHrAvg: hr,
        structure: "\(zone) fixture",
        distanceMi: 6,
        kind: kind
    )
}

private let standardLadder = BandLadder(
    mp: 352, hmp: 334, lt: 326, k10: 318, k5: 305, k3: 288, mile: 278
)

private func bands(_ ladder: BandLadder = standardLadder) -> BandLaps {
    BandLaps(
        sessions: [BandSession(
            id: "band-0", date: iso(0), dateLabel: "D0",
            sessionMiles: 8, dewPointF: 60, anchors: ladder, laps: []
        )],
        confidenceTier: "high",
        windowStart: nil,
        windowEnd: nil
    )
}

private func build(
    _ sessions: [KeySession],
    bandLaps: BandLaps? = nil,
    window: TrendsWindow = .sixMonths,
    asOfDay: Int = 100
) -> EfficiencyIndexRead {
    EfficiencyIndexBuilder.build(
        sessions: sessions,
        bandLaps: bandLaps,
        settings: .default,
        window: window,
        asOf: dayDate(asOfDay)
    )
}

/// A spread of on-line sessions across paces and zones: intervals fast,
/// long runs slow — the validated shape of a real block.
private func baseline(days: [Int] = Array(1...12)) -> [KeySession] {
    days.enumerated().map { i, day in
        let fast = i % 2 == 0
        return session(
            day: day * 7,
            zone: fast ? "5k" : "mp",
            paceSec: fast ? 300 + (i % 3) * 8 : 390 + (i % 3) * 10,
            kind: fast ? "quality" : "long_run"
        )
    }
}

// MARK: - Rule 1 · the index is relative to the athlete's own curve

@Test func onCurveSessionIndexesAtHundred() {
    let read = build(baseline())
    #expect(read.curve != nil)
    for point in read.points {
        guard let idx = point.index else { continue }
        #expect(abs(idx - 100) < 2, "on-line fixture should read ~100, got \(idx)")
    }
}

@Test func threePercentBetterReadsOneOhThree() {
    var sessions = baseline()
    sessions.append(session(day: 95, zone: "5k", paceSec: 302, mpbScale: 1.03))
    let read = build(sessions)
    let last = read.points.last
    #expect(last != nil)
    if let idx = last?.index {
        #expect(abs(idx - 103) < 2, "3% above the curve should read ~103, got \(idx)")
    }
}

@Test func curveRecoversTheLine() throws {
    let read = build(baseline())
    let curve = try #require(read.curve)
    // Integer pace/HR rounding bounds how exactly the fit can recover the
    // generating line; these tolerances are rounding-sized.
    #expect(abs(curve.b1 - c1) < 0.0012)
    #expect(curve.b2 == 0)
}

// MARK: - Rule 2 · long runs are in the fit, grouped apart

@Test func longRunsFeedTheFitAndGroupApart() {
    let read = build(baseline())
    #expect(read.curve != nil)
    #expect(read.points.contains { $0.isLongRun })
    // Long runs group under LONG for chips and means, never under a work zone.
    let longMean = read.zoneMeans.first { $0.zone == EfficiencyIndexBuilder.longZoneToken }
    #expect(longMean != nil)
    // Hoisted out of #expect: the macro expands `.allSatisfy(_:)` to
    // `$0.allSatisfy($1)` without a `try`, and allSatisfy takes a throwing
    // closure — inside the macro that is a compile error that takes the
    // whole test target down with it.
    let allLong = read.points(zone: EfficiencyIndexBuilder.longZoneToken)
        .allSatisfy(\.isLongRun)
    #expect(allLong)
}

// MARK: - Rule 3 · heat

@Test func hotSessionScoredOnAdjustedPace() {
    var sessions = baseline()
    // Hot session: watch pace 320, cool-equivalent 305. On the line at 305.
    sessions.append(session(day: 95, zone: "5k", paceSec: 305, heat: "hot", rawPaceSec: 320))
    let read = build(sessions)
    let hot = read.points.first { $0.isHeatAdjusted }
    #expect(hot != nil)
    #expect(hot?.paceSec == 305, "scored on the adjusted pace, not the watch pace")
    if let idx = hot?.index {
        #expect(abs(idx - 100) < 2)
    }
}

@Test func hotWithoutAdjustmentIsCountedOut() {
    var sessions = baseline()
    var s = session(day: 95, zone: "5k", paceSec: 320)
    s = KeySession(
        id: s.id, date: s.date, dateLabel: s.dateLabel, zone: s.zone,
        workPaceSec: s.workPaceSec, workPaceAdjSec: nil, heatCategory: "hot",
        workHrAvg: s.workHrAvg, structure: s.structure, distanceMi: s.distanceMi,
        kind: s.kind
    )
    sessions.append(s)
    let read = build(sessions)
    #expect(!read.points.contains { $0.id == s.id }, "never scored at raw hot pace")
    #expect(read.excluded.contains { $0.id == "heat" && $0.count == 1 })
}

@Test func heatTermNeedsFiveHotSessionsAndClampsPositive() throws {
    // Four hot sessions: term not granted, b2 stays 0.
    var four = baseline()
    for i in 0..<4 {
        four.append(session(day: 80 + i * 2, zone: "hmp", paceSec: 335 + i, heat: "hot",
                            rawPaceSec: 350 + i, heatPenaltyPerStep: 0.01))
    }
    let readFour = build(four)
    #expect(readFour.curve?.b2 == 0)
    #expect(readFour.heatCostPctPerStep == nil)
    #expect(readFour.nonIdealCount == 4)

    // Five hot sessions carrying a real per-step penalty: term granted,
    // negative, and the hot sessions come back to ~100 under it.
    var five = baseline()
    for i in 0..<5 {
        five.append(session(day: 78 + i * 2, zone: "hmp", paceSec: 335 + i, heat: "hot",
                            rawPaceSec: 350 + i, heatPenaltyPerStep: 0.01))
    }
    let readFive = build(five)
    let curve = try #require(readFive.curve)
    #expect(curve.heatTermFit)
    #expect(curve.b2 < 0)
    for point in readFive.points where point.isHeatAdjusted {
        guard let idx = point.index else { continue }
        #expect(abs(idx - 100) < 3, "drift-corrected hot session should read ~100, got \(idx)")
    }

    // Hot sessions that are somehow BETTER than cool ones: a positive fitted
    // term is noise and clamps to zero — heat never pays the index.
    var flattering = baseline()
    for i in 0..<5 {
        flattering.append(session(day: 78 + i * 2, zone: "hmp", paceSec: 335 + i, heat: "hot",
                                  rawPaceSec: 350 + i, mpbScale: 1.05))
    }
    let readFlattering = build(flattering)
    #expect(readFlattering.curve?.b2 == 0)
    #expect(readFlattering.heatCostPctPerStep == nil)
}

@Test func heatTermNeverMovesTheThresholdStat() throws {
    var cool = baseline()
    var hot = baseline()
    for i in 0..<5 {
        hot.append(session(day: 78 + i * 2, zone: "hmp", paceSec: 335 + i, heat: "hot",
                           rawPaceSec: 350 + i, heatPenaltyPerStep: 0.01))
        cool.append(session(day: 78 + i * 2, zone: "hmp", paceSec: 335 + i))
    }
    let readHot = build(hot, bandLaps: bands())
    let readCool = build(cool, bandLaps: bands())
    let anchorHot = try #require(readHot.anchorStat)
    let anchorCool = try #require(readCool.anchorStat)
    #expect(anchorHot.paceSec == standardLadder.hmp)
    // Evaluated at severity 0 by definition — the drift term cannot touch it.
    // The two fits differ only by rounding on the shared cool population.
    #expect(abs(anchorHot.mpb - anchorCool.mpb) < 0.03)
}

// MARK: - Rule 4 · the outlier gate catches leverage

@Test func hrLagArtefactIsDroppedByDeletedResiduals() {
    var sessions = baseline()
    // The real case from validation: 8×200 at HR 136 — far off the line AND
    // far outside the speed range, so an ordinary fit bends toward it.
    sessions.append(session(day: 96, zone: "mile", paceSec: 250, hrOverride: 136))
    let read = build(sessions)
    #expect(read.excluded.contains { $0.id == "outlier" && $0.count == 1 })
    // An artefact never draws — the NOT COUNTED panel owns it.
    #expect(!read.points.contains { $0.hr == 136 })
    #expect(!read.points.compactMap(\.index).isEmpty)
    // The surviving curve is the clean one: on-line sessions still read ~100.
    for point in read.points where point.hr != 136 {
        guard let idx = point.index else { continue }
        #expect(abs(idx - 100) < 2)
    }
}

@Test func smallFitsDoNotRunTheGate() {
    // 8 sessions is under `outlierMinSessions` — with this little data the
    // gate could eat real readings, so it must not run.
    let read = build(baseline(days: Array(1...8)))
    #expect(read.curve != nil)
    #expect(!read.excluded.contains { $0.id == "outlier" })
}

// MARK: - Rule 5 · NOT YET in words, exclusions counted

@Test func sevenSessionsSayNotYet() {
    let read = build(baseline(days: Array(1...7)))
    #expect(read.curve == nil)
    #expect(read.notYetReason?.contains("NOT YET") == true)
}

@Test func oneZoneSaysNotYet() {
    let sessions = (1...9).map { session(day: $0 * 7, zone: "5k", paceSec: 300 + $0) }
    let read = build(sessions)
    #expect(read.curve == nil)
    #expect(read.notYetReason?.contains("one zone") == true)
}

@Test func artefactHeartRatesAreCountedOut() {
    var sessions = baseline()
    sessions.append(session(day: 95, zone: "5k", paceSec: 300, hrOverride: 89))
    sessions.append(session(day: 96, zone: "5k", paceSec: 300, hrOverride: 206))
    let read = build(sessions)
    #expect(read.excluded.contains { $0.id == "artefact" && $0.count == 2 })
    #expect(!read.points.contains { $0.hr == 89 || $0.hr == 206 })
}

@Test func headlineNeedsThreeRecentSessions() {
    // All sessions are old: the curve exists, the dots draw, the composite waits.
    let read = build(baseline(), asOfDay: 160)
    #expect(read.curve != nil)
    #expect(read.headline == nil)
    #expect(!read.points.isEmpty)
}

@Test func anchorOutsideFittedRangeIsOmitted() {
    // Every fixture sits at 5K-and-slower paces; a mile-anchored band asks
    // the curve to extrapolate, and the stat refuses (omit, never fill).
    var settings = BandSettings.default
    settings.anchor = .mile
    let read = EfficiencyIndexBuilder.build(
        sessions: baseline(),
        bandLaps: bands(BandLadder(mp: 352, hmp: 334, lt: 326, k10: 318, k5: 305, k3: 288, mile: 230)),
        settings: settings,
        window: .sixMonths,
        asOf: dayDate(100)
    )
    #expect(read.curve != nil)
    #expect(read.anchorStat == nil)
}
