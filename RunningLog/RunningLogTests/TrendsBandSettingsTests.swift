import Foundation
import Testing
@testable import RunningLog

// Guards for the adjustable threshold band — `TrendsBandSettings.swift` and
// the `BandLaps` path through `ThresholdBuilder`.
//
// Each test encodes a decision rather than a behaviour. The two that carry the
// most weight are the independent edges (the 2026-08-02 audit found the leak
// on the slow one, and a symmetric control can only fix it by damaging the
// fast one) and the two minimums (a total and an unbroken block catch
// different things, and the fixture proves it by failing one while clearing
// the other).

// MARK: - Fixtures

private let LADDER = BandLadder.previewLadder // HM 5:24, MP 5:39, 10K 5:10
private let LAB = BandLaps.preview

/// The window is fixed so `windowed` tests don't drift with the wall clock.
private let ASOF = ISO8601DateFormatter().date(from: "2026-08-05T12:00:00Z")!

private func read(
    _ anchor: BandAnchor = .hmp,
    fast: Double = 5,
    slow: Double = 5,
    minTotal: Double = 8,
    minBlock: Double = 5,
    hrFloor: Int = 160,
    windowDays: Int? = nil
) -> ThresholdRead {
    ThresholdBuilder.build(
        lab: LAB,
        settings: BandSettings(
            anchor: anchor,
            fastPct: fast,
            slowPct: slow,
            minTotalMinutes: minTotal,
            minBlockMinutes: minBlock,
            hrFloor: hrFloor
        ),
        windowDays: windowDays,
        asOf: ASOF
    )
}

private func point(_ r: ThresholdRead, _ date: String) -> ThresholdPoint? {
    r.points.first { $0.date == date }
}

// MARK: - The band edges

@Suite("Band edges")
struct BandEdgeTests {

    @Test("edges are the anchor ± their own percentage, rounded to the second")
    func edgesMath() {
        let s = BandSettings(
            anchor: .hmp, fastPct: 5, slowPct: 5,
            minTotalMinutes: 0, minBlockMinutes: 0, hrFloor: 160
        )
        let e = s.edges(anchorSec: 320)
        #expect(e.fast == 304)
        #expect(e.slow == 336)
    }

    /// The whole reason the two edges are separate controls: clamping the slow
    /// side must not move the fast side by a single second.
    @Test("tightening the slow edge leaves the fast edge exactly where it was")
    func edgesAreIndependent() {
        let wide = read(.hmp, fast: 5, slow: 5)
        let tight = read(.hmp, fast: 5, slow: 2)
        #expect(wide.fastSec == tight.fastSec)
        #expect(tight.slowSec < wide.slowSec)
    }

    /// The audit's finding, reproduced: the 28 Apr long run clips the band's
    /// slow edge four times. Pull that edge in and it stops counting at all,
    /// while the tempo sessions on the fast side are untouched.
    @Test("a tight slow edge drops long-run cruising without touching real work")
    func slowEdgeClampDropsCruise() {
        let wide = read(.hmp, slow: 5, minTotal: 0, minBlock: 0)
        let tight = read(.hmp, slow: 2, minTotal: 0, minBlock: 0)

        #expect(point(wide, "2026-04-28") != nil)
        #expect(point(tight, "2026-04-28") == nil)
        // The 4 Apr tempo sits on the fast side of the anchor and survives.
        #expect(point(wide, "2026-04-04") != nil)
        #expect(point(tight, "2026-04-04") != nil)
    }

    @Test("widening the slow edge admits sessions a tighter band never saw")
    func wideningAdmits() {
        let tight = read(.hmp, slow: 2, minTotal: 0, minBlock: 0)
        let wide = read(.hmp, slow: 10, minTotal: 0, minBlock: 0)
        #expect(wide.points.count > tight.points.count)
    }

    @Test("a zero-width band is clamped to the tightest real one, never empty by arithmetic")
    func zeroWidthClamped() {
        let s = BandSettings(
            anchor: .hmp, fastPct: 0, slowPct: 0,
            minTotalMinutes: 0, minBlockMinutes: 0, hrFloor: 160
        ).clamped()
        #expect(s.slowPct == BandSettings.pctStep)
    }
}

// MARK: - The anchor

@Suite("Band anchor")
struct BandAnchorTests {

    /// Moving the anchor has to move the band, not just its label.
    @Test("re-anchoring on 10K changes which minutes qualify")
    func anchorMovesTheBand() {
        // 12 Apr is 5 × 1 mi at 5:05–5:10. Against the half anchor only three
        // reps land; against 10K all five do.
        let hmp = read(.hmp, minTotal: 0, minBlock: 0)
        let k10 = read(.k10, minTotal: 0, minBlock: 0)

        let a = try! #require(point(hmp, "2026-04-12"))
        let b = try! #require(point(k10, "2026-04-12"))
        #expect(b.minutes > a.minutes)
        #expect(abs(a.minutes - 15.45) < 0.1)
        #expect(abs(b.minutes - 25.63) < 0.1)
    }

    @Test("anchoring on mile pace finds nothing in a threshold block, and says so")
    func mileAnchorIsEmpty() {
        let r = read(.mile, minTotal: 0, minBlock: 0)
        #expect(r.isEmpty)
        // Still knows what band it drew — an empty chart is a readable result.
        #expect(r.anchorSec == BandLadder.previewLadderJul.mile)
    }

    @Test("a typed pace anchors the band on exactly that number")
    func customAnchor() {
        let r = read(.custom(310), minTotal: 0, minBlock: 0)
        #expect(r.anchorSec == 310)
        #expect(r.fastSec == 295)  // 310 × 0.95
        #expect(r.slowSec == 326)  // 310 × 1.05
    }

    /// The ladder steps weekly. A session run in April is judged against
    /// April's fitness even though the chart draws August's band.
    @Test("each session is judged against its own week's anchor")
    func anchorStepsWeekly() {
        let r = read(.hmp, minTotal: 0, minBlock: 0)
        let april = try! #require(point(r, "2026-04-04"))
        let july = try! #require(point(r, "2026-07-21"))
        #expect(april.anchorSec == BandLadder.previewLadder.hmp)
        #expect(july.anchorSec == BandLadder.previewLadderJul.hmp)
        // The drawn band is the latest one, not April's.
        #expect(r.anchorSec == BandLadder.previewLadderJul.hmp)
    }

    @Test("anchor labels and paces come from the ladder, not from constants")
    func anchorLadderLookup() {
        #expect(BandAnchor.lt.sec(in: LADDER) == LADDER.lt)
        #expect(BandAnchor.k5.sec(in: LADDER) == LADDER.k5)
        #expect(BandAnchor.custom(333).sec(in: LADDER) == 333)
        #expect(BandAnchor.zones.count == 7)
    }
}

// MARK: - The two minimums

@Suite("Minimum duration")
struct BandMinimumTests {

    /// The case the block gate exists for. The 28 Apr long run touches the
    /// band four separate times for about four minutes each: seventeen honest
    /// minutes in total, and not one threshold session.
    @Test("a fragmented long run clears the total and fails the block")
    func fragmentedFailsBlock() {
        let noGates = read(.hmp, minTotal: 0, minBlock: 0)
        let p = try! #require(point(noGates, "2026-04-28"))
        #expect(p.minutes > 12)          // clears a twelve-minute total
        #expect(p.blockMinutes < 5)      // fails a five-minute block
        #expect(p.isFragmented)

        // With both gates on, it is out.
        #expect(point(read(.hmp, minTotal: 8, minBlock: 5), "2026-04-28") == nil)
        // With only the total gate, it wrongly counts — which is why both exist.
        #expect(point(read(.hmp, minTotal: 8, minBlock: 0), "2026-04-28") != nil)
    }

    /// Recovery jogs ship flagged precisely so this can be true. If they were
    /// filtered out on the wire, five reps would read as one unbroken block.
    @Test("rest laps break a block — an interval set is reps, not one effort")
    func restLapsBreakBlocks() {
        let r = read(.k10, minTotal: 0, minBlock: 0)
        let intervals = try! #require(point(r, "2026-04-12"))
        #expect(abs(intervals.minutes - 25.63) < 0.1)
        // One rep, not the sum of five.
        #expect(abs(intervals.blockMinutes - 5.13) < 0.1)
        #expect(intervals.isFragmented)
    }

    @Test("a six-minute block gate holds out a five-minute-rep interval session")
    func blockGateOnIntervals() {
        #expect(point(read(.k10, minTotal: 0, minBlock: 5), "2026-04-12") != nil)
        #expect(point(read(.k10, minTotal: 0, minBlock: 6), "2026-04-12") == nil)
    }

    @Test("a continuous tempo has one block equal to its total")
    func continuousTempo() {
        let p = try! #require(point(read(.hmp, minTotal: 0, minBlock: 0), "2026-04-04"))
        #expect(abs(p.minutes - p.blockMinutes) < 0.01)
        #expect(!p.isFragmented)
    }

    /// The drive-by the whole control was asked for: three minutes at pace
    /// inside a long run is not a session.
    @Test("a three-minute drive-by is excluded by the default minimum")
    func driveByExcluded() {
        let open = read(.hmp, minTotal: 0, minBlock: 0)
        let p = try! #require(point(open, "2026-05-05"))
        #expect(p.minutes < 4)
        #expect(point(read(.hmp), "2026-05-05") == nil)
    }

    /// A filter that silently deletes running reads as "there was none".
    @Test("excluded sessions are counted and their minutes reported, never dropped in silence")
    func exclusionsAreReported() {
        let r = read(.hmp, minTotal: 8, minBlock: 5)
        #expect(r.excludedSessions > 0)
        #expect(r.excludedMinutes > 0)

        // Turning the gates off moves those sessions into the read rather than
        // making them disappear — the two counts trade, they don't leak.
        let open = read(.hmp, minTotal: 0, minBlock: 0)
        #expect(open.excludedSessions == 0)
        #expect(open.points.count == r.points.count + r.excludedSessions)
    }

    /// Landing nothing in the band at all is a different fact from landing
    /// something and falling under a minimum. Only the second is an exclusion.
    @Test("a session with no in-band time is absent, not counted as excluded")
    func noInBandTimeIsNotAnExclusion() {
        // Anchored on mile pace nothing lands anywhere in the window.
        let r = read(.mile, minTotal: 8, minBlock: 5)
        #expect(r.isEmpty)
        #expect(r.excludedSessions == 0)
    }
}

// MARK: - Grading

@Suite("Grading under settings")
struct BandGradingTests {

    @Test("in the band on pace, under the floor on effort — graded as cruising")
    func cruiseGrading() {
        let p = try! #require(point(read(.hmp, minTotal: 0, minBlock: 0), "2026-05-28"))
        #expect(p.grade == .cruise)
    }

    @Test("no heart rate is unclassed, never folded into either bucket")
    func unclassedGrading() {
        let p = try! #require(point(read(.hmp, minTotal: 0, minBlock: 0), "2026-06-09"))
        #expect(p.grade == .unclassed)
    }

    /// Turning the floor off is the athlete saying she doesn't train with a
    /// strap. Under that setting a missing reading is not a missing answer.
    @Test("floor off grades every in-band minute as work, including HR-less ones")
    func floorOffGradesAllWork() {
        let r = read(.hmp, minTotal: 0, minBlock: 0, hrFloor: 0)
        #expect(r.cruisePoints.isEmpty)
        #expect(r.unclassedPoints.isEmpty)
        #expect(r.workPoints.count == r.points.count)
        #expect(ThresholdBuilder.grade(hr: nil, floor: 0) == .work)
    }

    @Test("raising the floor reclassifies work as cruising without deleting it")
    func raisingTheFloor() {
        let low = read(.hmp, minTotal: 0, minBlock: 0, hrFloor: 140)
        let high = read(.hmp, minTotal: 0, minBlock: 0, hrFloor: 175)
        #expect(low.points.count == high.points.count)   // same sessions
        #expect(high.workMinutes < low.workMinutes)      // fewer graded as work
        #expect(high.cruiseMinutes > low.cruiseMinutes)
    }
}

// MARK: - Window

@Suite("Band window")
struct BandWindowTests {

    @Test("the window is a filter over what was already fetched")
    func windowFilters() {
        let all = LAB.windowed(days: nil, asOf: ASOF)
        let month = LAB.windowed(days: 30, asOf: ASOF)
        #expect(all.sessions.count == LAB.sessions.count)
        #expect(month.sessions.allSatisfy { $0.date >= "2026-07-06" })
        #expect(month.sessions.count < all.sessions.count)
    }

    @Test("the drawn band is the one in force at the end of the window")
    func bandIsLatest() {
        let r = read(.hmp, minTotal: 0, minBlock: 0, windowDays: 30)
        #expect(r.anchorSec == BandLadder.previewLadderJul.hmp)
    }
}

// MARK: - Settings value type

@Suite("BandSettings")
struct BandSettingsValueTests {

    @Test("the shipped default reproduces the old fixed band, but not the old minimum")
    func defaults() {
        let d = BandSettings.default
        #expect(d.anchor == .hmp)
        #expect(d.fastPct == 5)
        #expect(d.slowPct == 5)
        #expect(d.hrFloor == 160)
        // The deliberate change: 2 minutes is what let the drive-bys in.
        #expect(d.minTotalMinutes == 8)
        #expect(d.minBlockMinutes == 5)
        #expect(d.isDefault)
    }

    @Test("out-of-range values are clamped rather than trusted")
    func clamping() {
        let wild = BandSettings(
            anchor: .lt, fastPct: -4, slowPct: 900,
            minTotalMinutes: -10, minBlockMinutes: 9_999, hrFloor: 20
        ).clamped()
        #expect(wild.fastPct == BandSettings.pctRange.lowerBound)
        #expect(wild.slowPct == BandSettings.pctRange.upperBound)
        #expect(wild.minTotalMinutes == BandSettings.minutesRange.lowerBound)
        #expect(wild.minBlockMinutes == BandSettings.blockRange.upperBound)
        #expect(wild.hrFloor == BandSettings.hrFloorRange.lowerBound)
    }

    @Test("a floor of zero survives clamping — it means off, not out of range")
    func zeroFloorSurvives() {
        var s = BandSettings.default
        s.hrFloor = 0
        #expect(s.clamped().hrFloor == 0)
    }

    @Test("the width label says symmetric and asymmetric differently")
    func widthLabels() {
        var s = BandSettings.default
        #expect(s.widthLabel == "±5%")
        s.slowPct = 2
        #expect(s.widthLabel == "−5% / +2%")
        s.fastPct = 7.5
        #expect(s.widthLabel == "−7.5% / +2%")
    }
}

// MARK: - Custom-pace parsing

@Suite("Custom pace parsing")
struct BandPaceParsingTests {

    @Test("min:sec and bare seconds both parse")
    func parses() {
        #expect(BandSettings.parsePace("5:35") == 335)
        #expect(BandSettings.parsePace(" 5:35 ") == 335)
        #expect(BandSettings.parsePace("335") == 335)
        #expect(BandSettings.parsePace("10:00") == 600)
    }

    /// A typo must not be able to anchor the band at 12 sec/mile.
    @Test("nonsense and implausible paces are rejected, not coerced")
    func rejects() {
        #expect(BandSettings.parsePace("") == nil)
        #expect(BandSettings.parsePace("abc") == nil)
        #expect(BandSettings.parsePace("5:99") == nil)   // seconds out of range
        #expect(BandSettings.parsePace("5:3:5") == nil)
        #expect(BandSettings.parsePace("0:12") == nil)   // faster than possible
        #expect(BandSettings.parsePace("45:00") == nil)  // slower than a walk
    }
}

// MARK: - Persistence

@Suite("Band settings persistence")
struct BandSettingsStoreTests {

    private func scratch() -> UserDefaults {
        let d = UserDefaults(suiteName: "band-settings-test-\(UUID().uuidString)")!
        return d
    }

    @Test("an anchor round-trips through its token, custom paces included")
    func anchorTokens() {
        for a in BandAnchor.zones + [.custom(335)] {
            #expect(BandAnchor(token: a.token) == a)
        }
        #expect(BandAnchor(token: "nonsense") == nil)
    }

    @Test("settings survive a restart")
    func persists() {
        let defaults = scratch()
        let store = BandSettingsStore(defaults: defaults)
        store.settings.anchor = .custom(311)
        store.settings.slowPct = 2
        store.settings.minBlockMinutes = 9

        let reopened = BandSettingsStore(defaults: defaults)
        #expect(reopened.settings.anchor == .custom(311))
        #expect(reopened.settings.slowPct == 2)
        #expect(reopened.settings.minBlockMinutes == 9)
    }

    /// A blob written by a build that shaped these differently is not worth
    /// half-reading — the default is the honest fallback.
    @Test("a corrupt blob falls back to the default rather than a half-read band")
    func corruptFallsBack() {
        let defaults = scratch()
        defaults.set(Data("not json".utf8), forKey: "signalLab.bandSettings.v1")
        #expect(BandSettingsStore(defaults: defaults).settings == .default)
    }

    @Test("reset returns the shipped band")
    func resets() {
        let store = BandSettingsStore(defaults: scratch())
        store.settings.anchor = .k5
        store.reset()
        #expect(store.settings == .default)
    }
}
