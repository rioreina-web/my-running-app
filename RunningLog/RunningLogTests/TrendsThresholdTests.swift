import Foundation
import Testing
@testable import RunningLog

// Guards for the rules in `TrendsThresholdModels.swift`. Each test encodes a
// decision, not just a behaviour — the grading rule in particular is the whole
// argument of the 2026-08-02 band audit and must not soften silently.

// MARK: - Fixtures

private func slice(
    minutes: Double,
    miles: Double = 3,
    adj: Int,
    raw: Int? = nil,
    hr: Int?
) -> PaceBandSlice {
    let rawSec = raw ?? adj
    return PaceBandSlice(
        minutes: minutes,
        miles: miles,
        paceAdjSec: adj,
        paceRawSec: rawSec,
        correctionSec: rawSec - adj,
        hrAvg: hr
    )
}

private func session(
    _ iso: String,
    hm: PaceBandSlice?,
    dew: Int? = 68
) -> PaceBandSession {
    PaceBandSession(
        id: "log-" + iso,
        date: iso,
        dateLabel: String(iso.suffix(5)),
        longDateLabel: iso,
        sessionMi: 12,
        hm: hm,
        mp: nil,
        overlapMin: 0,
        dewPointF: dew,
        hmAnchorSec: 323,
        mpAnchorSec: 338
    )
}

private func bands(_ sessions: [PaceBandSession], lowConfidence: Bool = false) -> PaceBands {
    let summary = PaceBandSummary(
        anchorSec: 323,
        fastSec: 307,
        slowSec: 339,
        sessionCount: sessions.count,
        minutes: sessions.reduce(0) { $0 + ($1.hm?.minutes ?? 0) },
        miles: sessions.reduce(0) { $0 + ($1.hm?.miles ?? 0) },
        paceAdjSec: 320,
        hrAvg: 165
    )
    let empty = PaceBandSummary(
        anchorSec: 338, fastSec: 321, slowSec: 355,
        sessionCount: 0, minutes: 0, miles: 0, paceAdjSec: nil, hrAvg: nil
    )
    return PaceBands(
        hm: summary,
        mp: empty,
        sessions: sessions,
        overlap: nil,
        confidenceTier: lowConfidence ? "low" : "high",
        windowStart: sessions.first?.date,
        windowEnd: sessions.last?.date
    )
}

// MARK: - The grading rule

@Suite("ThresholdBuilder.grade")
struct ThresholdGradeTests {

    /// The rule the band audit landed on: effort decides, not pace. A pace
    /// filter alone breaks on a hot day, when genuine threshold work
    /// legitimately slows into the slow half of the band.
    @Test("heart rate at or above the floor grades as work")
    func atFloorIsWork() {
        #expect(ThresholdBuilder.grade(hr: 160, floor: 160) == .work)
        #expect(ThresholdBuilder.grade(hr: 175, floor: 160) == .work)
    }

    @Test("heart rate under the floor grades as cruising")
    func underFloorIsCruise() {
        #expect(ThresholdBuilder.grade(hr: 159, floor: 160) == .cruise)
    }

    /// A session with no heart rate is not gradeable. Folding it quietly into
    /// either bucket would let the headline minutes drift with sensor
    /// coverage rather than with training.
    @Test("no heart rate is unclassed, never assumed either way")
    func missingHrIsUnclassed() {
        #expect(ThresholdBuilder.grade(hr: nil, floor: 160) == .unclassed)
        #expect(ThresholdBuilder.grade(hr: 0, floor: 160) == .unclassed)
    }
}

// MARK: - Totals

@Suite("ThresholdRead totals")
struct ThresholdTotalsTests {

    private var mixed: ThresholdRead {
        ThresholdBuilder.build(
            bands: bands([
                session("2026-04-04", hm: slice(minutes: 32, adj: 314, raw: 322, hr: 168)),
                session("2026-05-16", hm: slice(minutes: 6, adj: 364, hr: 148)),
                session("2026-07-21", hm: slice(minutes: 33, adj: 320, raw: 328, hr: 166)),
                session("2026-07-28", hm: slice(minutes: 35, adj: 316, hr: nil)),
            ]),
            band: .hm
        )
    }

    /// The headline figure counts graded work only. This is the number the
    /// growth read leans on, so a long run clipping the slow edge must not
    /// inflate it.
    @Test("headline minutes count work only, not cruising or unclassed")
    func headlineExcludesCruise() {
        let read = mixed
        #expect(read.workMinutes == 65)
        #expect(read.cruiseMinutes == 6)
        #expect(read.unclassedMinutes == 35)
        #expect(read.points.count == 4)
    }

    @Test("the per-session average divides work minutes by work sessions")
    func perSessionAverage() {
        #expect(mixed.minutesPerWorkSession == 32.5)
    }

    @Test("best and latest are drawn from graded work")
    func bestAndLatest() {
        let read = mixed
        #expect(read.best?.adjSec == 314)
        // 07-28 is later but unclassed, so the latest *work* session is 07-21.
        #expect(read.latest?.date == "2026-07-21")
    }

    /// Heart rate is weighted by the minutes it covers — a five-minute clip
    /// must not pull the average as hard as a thirty-five-minute block.
    @Test("average heart rate is weighted by minutes in band")
    func hrIsTimeWeighted() {
        let read = ThresholdBuilder.build(
            bands: bands([
                session("2026-04-04", hm: slice(minutes: 30, adj: 314, hr: 160)),
                session("2026-04-11", hm: slice(minutes: 10, adj: 314, hr: 180)),
            ]),
            band: .hm
        )
        // Unweighted would be 170; weighted is 165.
        #expect(read.workHrAvg == 165)
    }

    @Test("a session with no time in the band is not a point")
    func zeroMinutesDropped() {
        let read = ThresholdBuilder.build(
            bands: bands([
                session("2026-04-04", hm: slice(minutes: 0, adj: 314, hr: 168)),
                session("2026-04-11", hm: nil),
            ]),
            band: .hm
        )
        #expect(read.isEmpty)
    }

    @Test("the mean correction averages only sessions that had one")
    func meanCorrection() {
        let read = ThresholdBuilder.build(
            bands: bands([
                session("2026-04-04", hm: slice(minutes: 20, adj: 314, raw: 322, hr: 168)),
                session("2026-04-11", hm: slice(minutes: 20, adj: 316, hr: 168)),
                session("2026-04-18", hm: slice(minutes: 20, adj: 310, raw: 322, hr: 168)),
            ]),
            band: .hm
        )
        // 8 and 12 average to 10; the uncorrected session is not a zero.
        #expect(read.meanCorrectionSec == 10)
    }
}

// MARK: - Trend

@Suite("ThresholdRead.trend")
struct ThresholdTrendTests {

    /// Two points fit anything. The trend stays silent until three sessions
    /// can argue with each other.
    @Test("no trend under three graded sessions")
    func needsThree() {
        let read = ThresholdBuilder.build(
            bands: bands([
                session("2026-04-04", hm: slice(minutes: 20, adj: 320, hr: 168)),
                session("2026-05-04", hm: slice(minutes: 20, adj: 310, hr: 168)),
            ]),
            band: .hm
        )
        #expect(read.trendSecPerMonth == nil)
    }

    /// Ten seconds quicker across sixty days is five seconds a month, and the
    /// sign is negative for improvement.
    @Test("the slope is sec per mile per thirty days, negative when quickening")
    func slopeUnits() throws {
        let read = ThresholdBuilder.build(
            bands: bands([
                session("2026-04-01", hm: slice(minutes: 20, adj: 330, hr: 168)),
                session("2026-05-01", hm: slice(minutes: 20, adj: 325, hr: 168)),
                session("2026-05-31", hm: slice(minutes: 20, adj: 320, hr: 168)),
            ]),
            band: .hm
        )
        let trend = try #require(read.trendSecPerMonth)
        #expect(trend < 0)
        #expect(abs(trend + 5) < 0.6)
    }

    /// Cruising miles are long-run pace. Fitting through them measures how
    /// many long runs happened to clip the band, which is not a fitness claim.
    @Test("cruising sessions are excluded from the fit")
    func cruiseExcludedFromTrend() throws {
        let clean = bands([
            session("2026-04-01", hm: slice(minutes: 20, adj: 320, hr: 168)),
            session("2026-05-01", hm: slice(minutes: 20, adj: 320, hr: 168)),
            session("2026-05-31", hm: slice(minutes: 20, adj: 320, hr: 168)),
        ])
        let withCruise = bands([
            session("2026-04-01", hm: slice(minutes: 20, adj: 320, hr: 168)),
            session("2026-04-15", hm: slice(minutes: 20, adj: 372, hr: 140)),
            session("2026-05-01", hm: slice(minutes: 20, adj: 320, hr: 168)),
            session("2026-05-31", hm: slice(minutes: 20, adj: 320, hr: 168)),
        ])
        let a = try #require(ThresholdBuilder.build(bands: clean, band: .hm).trendSecPerMonth)
        let b = try #require(ThresholdBuilder.build(bands: withCruise, band: .hm).trendSecPerMonth)
        #expect(abs(a - b) < 0.001)
    }

    /// The fit runs over calendar days, not sample index — sessions are not
    /// evenly spaced, and treating them as if they were would let a cluster of
    /// sessions in one week outvote two months of training.
    @Test("the fit is over real time, not sample order")
    func fitIsOverTime() throws {
        let clustered = bands([
            session("2026-04-01", hm: slice(minutes: 20, adj: 330, hr: 168)),
            session("2026-04-02", hm: slice(minutes: 20, adj: 329, hr: 168)),
            session("2026-04-03", hm: slice(minutes: 20, adj: 328, hr: 168)),
            session("2026-06-30", hm: slice(minutes: 20, adj: 300, hr: 168)),
        ])
        let trend = try #require(ThresholdBuilder.build(bands: clustered, band: .hm).trendSecPerMonth)
        // Over sample index the last point would be one step from the third;
        // over time it is ninety days out, so the monthly slope stays modest.
        #expect(trend > -20 && trend < 0)
    }
}

// MARK: - Band metadata

@Suite("ThresholdBuilder band metadata")
struct ThresholdBandTests {

    @Test("the read carries the band's own edges, not a hardcoded pair")
    func edgesComeFromPayload() {
        let read = ThresholdBuilder.build(
            bands: bands([session("2026-04-04", hm: slice(minutes: 20, adj: 314, hr: 168))]),
            band: .hm
        )
        #expect(read.fastSec == 307)
        #expect(read.slowSec == 339)
        #expect(read.anchorSec == 323)
    }

    /// A low-confidence prediction gets dashed band edges rather than a hard
    /// line. The flag has to survive the build for the view to honour it.
    @Test("low confidence carries through to the read")
    func lowConfidenceCarries() {
        let read = ThresholdBuilder.build(
            bands: bands([session("2026-04-04", hm: slice(minutes: 20, adj: 314, hr: 168))], lowConfidence: true),
            band: .hm
        )
        #expect(read.lowConfidence)
    }

    @Test("points come back oldest first regardless of payload order")
    func sortedByDate() {
        let read = ThresholdBuilder.build(
            bands: bands([
                session("2026-07-21", hm: slice(minutes: 20, adj: 320, hr: 168)),
                session("2026-04-04", hm: slice(minutes: 20, adj: 314, hr: 168)),
                session("2026-06-02", hm: slice(minutes: 20, adj: 318, hr: 168)),
            ]),
            band: .hm
        )
        #expect(read.points.map(\.date) == ["2026-04-04", "2026-06-02", "2026-07-21"])
    }
}
