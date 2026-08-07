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

// MARK: - The time control (2026-08-07)

/// The window presets, and the range the control states.
///
/// Not threshold arithmetic, but the threshold detail states its range from
/// these, and a control that names a range the chart beneath it is not drawing
/// is the exact confusion the single-time-control rule exists to prevent.
@Suite("Trends window")
struct TrendsWindowTests {

    /// Every preset reads in months or years. "30 D" sat in a row with
    /// "3 MO / 6 MO / 1 YR" as the only member in a different unit.
    @Test("presets label in month units")
    func monthUnits() {
        #expect(TrendsWindow.thirtyDays.label == "1 MO")
        #expect(TrendsWindow.thirtyDays.plateTitle == "1-Month View")
        // The window itself did not move.
        #expect(TrendsWindow.thirtyDays.days == 30)
        #expect(TrendsWindow.thirtyDays.id == "30d")
    }

    /// UTC, calendar-field based. The file header's standing warning: never do
    /// this by adding 86_400 per day — that bug shipped once and blanked the
    /// screen in America/Chicago while passing every test under UTC.
    @Test("ISO days parse at UTC midnight, or not at all")
    func isoParsing() throws {
        let d = try #require(TrendsWindow.day(fromISO: "2026-08-07"))
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try #require(TimeZone(identifier: "UTC"))
        let c = cal.dateComponents([.year, .month, .day, .hour], from: d)
        #expect(c.year == 2026 && c.month == 8 && c.day == 7 && c.hour == 0)
        // A full timestamp is tolerated; junk is not.
        #expect(TrendsWindow.day(fromISO: "2026-08-07T12:00:00Z") == d)
        #expect(TrendsWindow.day(fromISO: "not-a-date") == nil)
        #expect(TrendsWindow.day(fromISO: "") == nil)
    }

    /// The meta line reads the RESOLVED SLICE, never the preset's nominal span.
    ///
    /// A preset is `days.suffix(n)` — the last n rows that exist. An athlete
    /// twelve days into her timeline on the 1-month view is looking at twelve
    /// days, and a control that labelled that "Jul 9 – Aug 7" would be naming a
    /// range the chart beneath it is not drawing.
    @Test("the range label names the days actually in the window")
    func rangeLabelFollowsTheSlice() throws {
        let days = TrendsDay.previewMonthRich
        let set = TrendsSignalBuilder.build(days: days, keySessions: [], window: .thirtyDays)
        let first = try #require(set.days.first?.date)
        let last = try #require(set.days.last?.date)
        #expect(first != last, "the fixture needs more than one day for this to mean anything")
        #expect(
            set.dateRangeLabel
                == "\(TrendsSignalBuilder.shortLabel(first)) – \(TrendsSignalBuilder.shortLabel(last))"
        )
    }

    /// A window wider than the timeline must not invent the days it is missing.
    ///
    /// The fixture's length is deliberately not assumed — `suffix(n)` is a
    /// count of rows, so the year view holds at least what the month view does
    /// and never more than the timeline itself, whatever the fixture is.
    @Test("a wider window never claims days the timeline doesn't have")
    func widerWindowThanData() throws {
        let days = TrendsDay.previewMonthRich
        let month = TrendsSignalBuilder.build(days: days, keySessions: [], window: .thirtyDays)
        let year = TrendsSignalBuilder.build(days: days, keySessions: [], window: .oneYear)

        #expect(year.days.count >= month.days.count)
        #expect(year.days.count <= days.count)
        // Whatever it holds, the label names ITS OWN first and last day.
        for set in [month, year] {
            let first = try #require(set.days.first?.date)
            let last = try #require(set.days.last?.date)
            let expected = first == last
                ? TrendsSignalBuilder.shortLabel(first)
                : "\(TrendsSignalBuilder.shortLabel(first)) – \(TrendsSignalBuilder.shortLabel(last))"
            #expect(set.dateRangeLabel == expected)
        }
    }

    /// Run DAYS, not runs — a double day is one day, and the meta line's copy
    /// says so.
    @Test("run days count days that carried running")
    func runDaysCountsDays() {
        let set = TrendsSignalBuilder.build(
            days: TrendsDay.previewMonthRich, keySessions: [], window: .thirtyDays
        )
        #expect(set.runDays == set.days.filter { $0.miles > 0 }.count)
        #expect(set.runDays + set.restDays == set.days.count)
    }

    /// An empty slice states nothing rather than a bare dash or a stale range.
    @Test("an empty window has no range to state")
    func emptySlice() {
        let set = TrendsSignalBuilder.build(days: [], keySessions: [], window: .thirtyDays)
        #expect(set.dateRangeLabel.isEmpty)
    }
}

// MARK: - One band, two surfaces

@Suite("Threshold detail shares the inline read")
struct ThresholdDetailParityTests {

    /// The settings are load-bearing on the read.
    ///
    /// The inline card and the detail are handed the SAME `ThresholdRead`, built
    /// once by the host. Asserting two identical builder calls match would prove
    /// only that the builder is deterministic. What is worth pinning is the
    /// contrast: if a future refactor let the detail build its own read from its
    /// own settings, THIS is the difference the athlete would see — one band,
    /// two sets of numbers.
    @Test("moving the band moves the read")
    func settingsAreLoadBearing() {
        let shipped = ThresholdBuilder.build(lab: .preview, settings: .default)

        var tightened = BandSettings.default
        tightened.slowPct = 1          // the leak the 2026-08-02 audit found
        let narrow = ThresholdBuilder.build(lab: .preview, settings: tightened)

        // A tighter slow edge can only ever admit fewer sessions, never more.
        #expect(narrow.points.count <= shipped.points.count)
        #expect(narrow.slowSec < shipped.slowSec)

        var noFloor = BandSettings.default
        noFloor.hrFloor = 0
        let ungraded = ThresholdBuilder.build(lab: .preview, settings: noFloor)

        // With the floor off every in-band minute is work, so nothing is held
        // apart as cruising and nothing is left ungradeable.
        #expect(ungraded.cruisePoints.isEmpty)
        #expect(ungraded.unclassedPoints.isEmpty)
        #expect(ungraded.workPoints.count == ungraded.points.count)
    }

    /// The detail's session list renders `read.points` — every session that
    /// cleared the minimums, not just the graded work. A list that showed only
    /// `workPoints` would silently drop the cruising sessions the slow edge let
    /// in, which are the whole reason the effort floor exists.
    @Test("the list covers every counted session, not just graded work")
    func listCoversAllPoints() {
        // No `windowDays`, so the fixture's 2026 dates are not filtered against
        // a wall clock that keeps moving. A test that quietly empties itself in
        // January is a test that stops guarding anything.
        let read = ThresholdBuilder.build(lab: .preview, settings: .default)
        #expect(read.points.count >= read.workPoints.count)
        #expect(
            read.points.count
                == read.workPoints.count + read.cruisePoints.count + read.unclassedPoints.count
        )
    }
}
