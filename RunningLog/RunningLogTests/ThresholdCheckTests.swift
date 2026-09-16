import Foundation
import Testing
@testable import RunningLog

// Guards for the rules in `ThresholdCheckModels.swift`. Each test encodes a
// decision from the 2026-08-18 validation (`THRESHOLD-CHECK-APPLY.md` §V),
// not just a behaviour:
//
// Rule 1: only continuous efforts of 20+ minutes WITHIN ±5% of the band can
//         test the band. Validation: this athlete's decoupling data comes from
//         long runs 15% off the band, where decoupling tracks duration
//         (R² 0.20) more than pace (R² 0.09). A wider gate would have shipped
//         a confident, wrong threshold.
// Rule 2: two agreeing efforts before any verdict. One session is a day.
// Rule 3: heat can prevent a harsh verdict, never create one.
// Rule 4: UNTESTED is a first-class answer and names what is missing.
// Rule 5: the check never returns a band value to write. There is no API here
//         that produces a new threshold — by construction, not by convention.

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

private let ladder = BandLadder(
    mp: 352, hmp: 334, lt: 326, k10: 318, k5: 305, k3: 288, mile: 278
)
/// The band under test: `BandSettings.default.anchor` is `.hmp` → 334 s/mi.
private let bandSec = 334

private func bands(_ days: [Int] = [0], ladders: [BandLadder]? = nil) -> BandLaps {
    let list = ladders ?? Array(repeating: ladder, count: days.count)
    return BandLaps(
        sessions: zip(days, list).map { day, l in
            BandSession(id: "band-\(day)", date: iso(day), dateLabel: "D\(day)",
                        sessionMiles: 8, dewPointF: 60, anchors: l, laps: [])
        },
        confidenceTier: "high", windowStart: nil, windowEnd: nil
    )
}

/// A continuous effort. `devPct` places it relative to the band; `minutes`
/// sets its length; `heat` gives it a neutral pace different from the raw one.
private func effort(
    day: Int,
    devPct: Double = 0,
    minutes: Double = 30,
    decoupling: Double? = 3,
    heat: Bool = false,
    continuous: Bool = true
) -> FastSession {
    let pace = Int((Double(bandSec) * (1 + devPct / 100)).rounded())
    let miles = minutes * 60 / Double(pace)
    return FastSession(
        id: "log-\(day)",
        date: iso(day),
        dateLabel: "D\(day)",
        name: "Effort \(day)",
        repCount: continuous ? 1 : 6,
        fastMiles: miles,
        // In heat the watch pace is slower; the neutral pace is the one judged.
        avgPaceSec: heat ? pace + 15 : pace,
        neutralPaceSec: heat ? pace : nil,
        avgHr: 168,
        densityPct: 100,
        avgRestSec: 0,
        metersPerBeat: nil,
        feelsF: heat ? 78 : 55,
        bySystem: [],
        decouplingPct: decoupling
    )
}

private func build(
    _ efforts: [FastSession],
    keySessions: [KeySession] = [],
    bandLaps: BandLaps? = nil,
    asOfDay: Int = 100
) -> ThresholdCheckRead {
    ThresholdCheckBuilder.build(
        fastSessions: efforts,
        keySessions: keySessions,
        bandLaps: bandLaps ?? bands(),
        settings: .default,
        window: .sixMonths,
        asOf: dayDate(asOfDay)
    )
}

// MARK: - Rule 1 · only efforts that actually test the band get in

@Test func repSessionsAreRejected() {
    let read = build([effort(day: 90, continuous: false), effort(day: 92, continuous: false)])
    #expect(read.efforts.isEmpty)
    #expect(read.verdict == .untested)
}

@Test func shortEffortsAreRejected() {
    let read = build([effort(day: 90, minutes: 19), effort(day: 92, minutes: 12)])
    #expect(read.efforts.isEmpty)
    #expect(read.verdict == .untested)
}

@Test func effortsOffTheBandAreRejectedAndCounted() {
    // The real shape of this athlete's log: long runs 15% slower than the band.
    let read = build([effort(day: 90, devPct: 15), effort(day: 92, devPct: 12)])
    #expect(read.efforts.isEmpty)
    #expect(read.verdict == .untested)
    #expect(read.nearMissCount == 2, "off-band efforts are counted, not deleted")
    let closest = try? #require(read.closestDevPct)
    #expect((closest ?? 0) > 11)
}

@Test func effortsWithoutDecouplingAreRejected() {
    let read = build([effort(day: 90, decoupling: nil), effort(day: 92, decoupling: nil)])
    #expect(read.efforts.isEmpty)
}

@Test func deviationIsMeasuredOnHeatNeutralPace() {
    // Watch pace is 15s slower than the band edge; the neutral pace is on it.
    // Judging the watch pace would push this effort out of the window.
    let read = build([effort(day: 90, heat: true), effort(day: 92, heat: true)])
    #expect(read.efforts.count == 2)
    #expect(read.efforts.allSatisfy { abs($0.devPct) < 0.5 })
    // Hoisted: as the whole #expect argument, the macro rewrites this to
    // `$0.allSatisfy($1)` with no `try` — a compile error. Wrapped in a
    // comparison it would be fine; bare it is not.
    let allInHeat = read.efforts.allSatisfy(\.inHeat)
    #expect(allInHeat)
}

// MARK: - Rule 2 · two agreeing efforts before any verdict

@Test func oneEffortIsNotAVerdict() {
    let read = build([effort(day: 90, decoupling: 2)])
    #expect(read.efforts.count == 1)
    #expect(read.verdict == .untested)
}

@Test func twoHeldEffortsReadConsistent() {
    // Held, but not comfortably — 4.5% is under the 5% bar and over the 3% one.
    let read = build([effort(day: 88, decoupling: 4.5), effort(day: 94, decoupling: 4.2)])
    #expect(read.verdict == .consistent)
    #expect(read.held == 2)
}

@Test func twoFailedEffortsReadMayBeFast() {
    let read = build([effort(day: 88, decoupling: 9.5), effort(day: 94, decoupling: 11)])
    #expect(read.verdict == .mayBeFast)
    #expect(read.failed == 2)
}

@Test func comfortableHoldsReadMayBeSlow() {
    let read = build([effort(day: 88, decoupling: 1.2), effort(day: 94, decoupling: 2.0)])
    #expect(read.verdict == .mayBeSlow)
}

@Test func inconclusiveEffortsDoNotVote() {
    // 6.5% sits between the two bars: recorded, but it cannot carry a verdict.
    let read = build([effort(day: 88, decoupling: 6.5), effort(day: 94, decoupling: 6.8)])
    #expect(read.efforts.count == 2)
    #expect(read.efforts.allSatisfy { $0.reading == .inconclusive })
    #expect(read.verdict == .untested)
}

// MARK: - Rule 3 · heat can prevent a harsh verdict, never create one

@Test func allHotFailuresAreHeatConfounded() {
    let read = build([
        effort(day: 88, decoupling: 9.5, heat: true),
        effort(day: 94, decoupling: 10.2, heat: true),
    ])
    #expect(read.verdict == .heatConfounded, "hot-day drift must not be called a fast band")
}

@Test func oneCoolFailureStandsAsMayBeFast() {
    let read = build([
        effort(day: 88, decoupling: 9.5, heat: true),
        effort(day: 94, decoupling: 10.2, heat: false),
    ])
    #expect(read.verdict == .mayBeFast)
}

@Test func heatNeverCreatesAHarshVerdict() {
    // Held efforts run in heat stay held. Heat is only ever a demotion.
    let read = build([
        effort(day: 88, decoupling: 2.0, heat: true),
        effort(day: 94, decoupling: 1.5, heat: true),
    ])
    #expect(read.verdict == .mayBeSlow)
}

// MARK: - Rule 4 · UNTESTED names what is missing

@Test func untestedSaysWhatIsMissing() {
    let read = build([effort(day: 90, devPct: 15)])
    #expect(read.verdict == .untested)
    let note = try? #require(ThresholdCheckProse.note(read))
    #expect(note?.contains("closest") == true)
    #expect(note?.contains("—") == false, "no em-dash placeholders (hard rule #8)")
}

@Test func noBandMeansNoCheck() {
    let read = ThresholdCheckBuilder.build(
        fastSessions: [effort(day: 90)],
        keySessions: [],
        bandLaps: nil,
        settings: .default,
        window: .sixMonths,
        asOf: dayDate(100)
    )
    #expect(read.isEmpty)
    #expect(read.verdict == .untested)
}

// MARK: - Anchor age counts to the last CHANGE

@Test func anchorAgeCountsToTheLastChange() {
    // Three weekly ladders; the HMP value changed at day 60 and has been
    // repeated since. Age is measured from the change, not the last ladder.
    let moved = BandLadder(mp: 352, hmp: 340, lt: 326, k10: 318, k5: 305, k3: 288, mile: 278)
    let read = build(
        [],
        bandLaps: bands([40, 60, 80, 95], ladders: [moved, ladder, ladder, ladder])
    )
    #expect(read.anchorAgeDays == 40, "100 - 60, the day the number last changed")
}
