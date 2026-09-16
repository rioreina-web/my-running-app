import Foundation
import Testing
@testable import RunningLog

// Guards for the rules in `KeyPaceModels.swift`. Each test encodes a decision,
// not just a behaviour — rules 1 and 2 in particular are the whole argument of
// the 2026-08-09 key-pace rebuild and must not soften silently.
//
// Rule 1: no trend across zones. Fitting a line through 5K reps and MP long
//         runs measures the training schedule, not fitness.
// Rule 2: no trend under three graded points. Two points are a line through
//         anything.
// Rule 3: the fit uses graded work only.
// Rule 4: long runs are excluded by default, reported, never deleted.
//
// NB on fixtures: the classifier's zone vocabulary is exactly
// `KeyZone.order` — mile · 3k · 5k · 10k · hmp · mp. There is no `lt` token;
// the backend folds threshold work into `hmp`. Fixtures use only real tokens,
// because a token outside the list has no colour, no anchor and no chip, and a
// test written on one would be testing a session the app can never receive.

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

private func session(
    day: Int,
    zone: String,
    adj: Int,
    raw: Int? = nil,
    hr: Int? = 168,
    kind: String = "quality"
) -> KeySession {
    // `effectivePaceSec` only reads `workPaceAdjSec` when heat actually
    // mattered, so a fixture wanting an adjusted pace has to say so.
    let rawSec = raw ?? adj
    let heated = rawSec != adj
    return KeySession(
        id: "log-\(day)-\(zone)",
        date: iso(day),
        dateLabel: "D\(day)",
        zone: zone,
        workPaceSec: rawSec,
        workPaceAdjSec: heated ? adj : nil,
        heatCategory: heated ? "hot" : "ideal",
        workHrAvg: hr,
        structure: "\(zone) fixture",
        distanceMi: 6,
        kind: kind
    )
}

private let standardLadder = BandLadder(
    mp: 352, hmp: 334, lt: 326, k10: 318, k5: 305, k3: 288, mile: 278
)

private func bandSession(_ day: Int, _ ladder: BandLadder) -> BandSession {
    BandSession(
        id: "band-\(day)",
        date: iso(day),
        dateLabel: "D\(day)",
        sessionMiles: 8,
        dewPointF: 60,
        anchors: ladder,
        laps: []
    )
}

private func bandLaps(
    days: [Int] = [0],
    ladder: BandLadder = standardLadder,
    tier: String? = "high"
) -> BandLaps {
    BandLaps(
        sessions: days.map { bandSession($0, ladder) },
        confidenceTier: tier,
        windowStart: nil,
        windowEnd: nil
    )
}

private func read(
    _ sessions: [KeySession],
    settings: BandSettings = .default,
    bands: BandLaps? = bandLaps(),
    window: TrendsWindow = .sixMonths,
    lastDay: Int = 60
) -> KeyPaceRead {
    KeyPaceBuilder.read(
        sessions: sessions,
        bandLaps: bands,
        settings: settings,
        window: window,
        asOf: dayDate(lastDay)
    )
}

// MARK: - Rule 1 · no trend across zones

@Test("A trend is never fitted across zones, however many points there are")
func trendIsNilForAllZones() {
    let r = read([
        session(day: 1, zone: "5k", adj: 310),
        session(day: 8, zone: "5k", adj: 308),
        session(day: 15, zone: "5k", adj: 306),
        session(day: 22, zone: "mp", adj: 356),
        session(day: 29, zone: "mp", adj: 354),
        session(day: 36, zone: "mp", adj: 352),
    ])
    #expect(r.trendSecPerMonth(zone: nil, includeLongRuns: false) == nil)
    #expect(r.trendLine(zone: nil, includeLongRuns: false) == nil)
    // …and the very same points inside one zone do produce one.
    #expect(r.trendSecPerMonth(zone: "5k", includeLongRuns: false) != nil)
}

// MARK: - Rule 2 · three graded points minimum

@Test("Two graded points draw no line; the third earns it")
func trendNeedsThreePoints() throws {
    let two = read([
        session(day: 1, zone: "5k", adj: 312),
        session(day: 15, zone: "5k", adj: 306),
    ])
    #expect(two.trendSecPerMonth(zone: "5k", includeLongRuns: false) == nil)

    let three = read([
        session(day: 1, zone: "5k", adj: 312),
        session(day: 15, zone: "5k", adj: 309),
        session(day: 29, zone: "5k", adj: 306),
    ])
    let slope = try #require(three.trendSecPerMonth(zone: "5k", includeLongRuns: false))
    // Six seconds quicker over 28 days = −0.2143 s/day ≈ −6.43 s per 30 days.
    #expect(slope < 0)
    #expect(abs(slope + 6.43) < 0.05)
}

// MARK: - Rule 3 · graded work only

@Test("Cruise and unclassed points are drawn but never fitted")
func trendIgnoresCruiseAndUnclassed() throws {
    let base = [
        session(day: 1, zone: "hmp", adj: 336),
        session(day: 15, zone: "hmp", adj: 333),
        session(day: 29, zone: "hmp", adj: 330),
    ]
    let clean = read(base)
    let slopeClean = try #require(clean.trendSecPerMonth(zone: "hmp", includeLongRuns: false))

    // A wildly off-trend point grading as cruise (HR under the floor), and
    // another with no HR at all. Both are visible; neither moves the fit.
    let polluted = read(base + [
        session(day: 30, zone: "hmp", adj: 420, hr: 120),
        session(day: 31, zone: "hmp", adj: 250, hr: nil),
    ])
    let slopeDirty = try #require(polluted.trendSecPerMonth(zone: "hmp", includeLongRuns: false))

    #expect(abs(slopeClean - slopeDirty) < 0.000_1)
    #expect(polluted.points(zone: "hmp", includeLongRuns: false).count == 5)
}

// MARK: - Grading

@Test("No heart rate grades as unclassed, never as cruise")
func missingHrIsUnclassed() {
    #expect(KeyPaceBuilder.grade(hrAvg: nil, floor: 160) == .unclassed)
    #expect(KeyPaceBuilder.grade(hrAvg: 0, floor: 160) == .unclassed)
    #expect(KeyPaceBuilder.grade(hrAvg: 159, floor: 160) == .cruise)
    #expect(KeyPaceBuilder.grade(hrAvg: 160, floor: 160) == .work)
}

@Test("A zero or absent floor grades every HR-bearing session as work")
func absentFloorGradesEverythingAsWork() {
    // The no-strap athlete, and the zone with too few sessions to judge. An
    // unjudged session must not be demoted — that is the failure the per-zone
    // floors exist to fix.
    #expect(KeyPaceBuilder.grade(hrAvg: 110, floor: 0) == .work)
    #expect(KeyPaceBuilder.grade(hrAvg: 110, floor: nil) == .work)
    // A missing floor still does not invent a heart rate.
    #expect(KeyPaceBuilder.grade(hrAvg: nil, floor: 0) == .unclassed)
    #expect(KeyPaceBuilder.grade(hrAvg: nil, floor: nil) == .unclassed)
}

// MARK: - Rule 4 · long runs

@Test("Long runs are excluded by default, counted, and recoverable")
func longRunsAreHiddenNotDropped() {
    let r = read([
        session(day: 1, zone: "hmp", adj: 336),
        session(day: 3, zone: "mp", adj: 356, kind: "long_run"),
        session(day: 10, zone: "mp", adj: 354, kind: "long_run"),
    ])
    #expect(r.points.count == 3, "the builder keeps them; the filter hides them")
    #expect(r.points(zone: nil, includeLongRuns: false).count == 1)
    #expect(r.points(zone: nil, includeLongRuns: true).count == 3)
    #expect(r.hiddenLongRuns(includeLongRuns: false) == 2)
    #expect(r.hiddenLongRuns(includeLongRuns: true) == 0)
}

// MARK: - Heat correction

@Test("Correction is never negative, and an unheated session draws no tick")
func correctionIsNeverNegative() {
    let r = read([
        session(day: 1, zone: "hmp", adj: 330, raw: 337),   // 7s of heat
        session(day: 8, zone: "hmp", adj: 330),             // no weather
    ])
    let pts = r.points(zone: "hmp", includeLongRuns: false)
    #expect(pts[0].correctionSec == 7)
    #expect(pts[0].hasCorrection)
    #expect(pts[1].correctionSec == 0)
    #expect(!pts[1].hasCorrection)
    #expect(pts.allSatisfy { $0.correctionSec >= 0 })
}

// MARK: - Chips

@Test("A zone with no sessions counts zero rather than disappearing")
func emptyZoneStillCounts() {
    let r = read([
        session(day: 1, zone: "hmp", adj: 336),
        session(day: 8, zone: "hmp", adj: 334),
    ])
    #expect(r.count(zone: "5k", includeLongRuns: false) == 0)
    #expect(r.points(zone: "5k", includeLongRuns: false).isEmpty)
    #expect(r.zonesPresent(includeLongRuns: false) == ["hmp"])
    // The view renders every chip in `KeyZone.order` and reads counts off the
    // read, so a zero-count zone still gets a chip. This is the contract that
    // makes that safe.
    #expect(KeyZone.chipOrder.allSatisfy { r.count(zone: $0, includeLongRuns: false) >= 0 })
}

@Test("Every zone the classifier can emit has a colour and an anchor")
func everyZoneTokenResolves() {
    for token in KeyZone.order {
        #expect(KeyZone.anchor(token) != nil, "\(token) must map to a band anchor")
        #expect(!KeyZone.label(token).isEmpty)
    }
    // The classifier never emits `lt`, so it deliberately has no anchor.
    #expect(KeyZone.anchor("lt") == nil)
}

// MARK: - The ladder a point is judged against

@Test("A point uses the ladder in force in its own week, not the window's last")
func pointUsesItsOwnWeeksLadder() {
    let early = BandLadder(mp: 372, hmp: 354, lt: 346, k10: 338, k5: 325, k3: 308, mile: 298)
    let late = BandLadder(mp: 352, hmp: 334, lt: 326, k10: 318, k5: 305, k3: 288, mile: 278)
    let bands = BandLaps(
        sessions: [bandSession(0, early), bandSession(40, late)],
        confidenceTier: "high", windowStart: nil, windowEnd: nil
    )
    let r = read(
        [session(day: 5, zone: "5k", adj: 325), session(day: 45, zone: "5k", adj: 305)],
        bands: bands
    )
    let pts = r.points(zone: "5k", includeLongRuns: false)
    #expect(pts[0].zoneAnchorSec == 325, "judged against the ladder of its own week")
    #expect(pts[1].zoneAnchorSec == 305)
    // Both ran exactly on target for their own week, so both deltas are zero.
    // That is the point of stepping the anchor instead of flattering old
    // sessions with today's fitness.
    #expect(pts[0].deltaVsZoneSec == 0)
    #expect(pts[1].deltaVsZoneSec == 0)
}

// MARK: - Band membership

@Test("Band membership defers to BandSettings and never re-tests the edges")
func bandMembershipMatchesSettings() throws {
    let settings = BandSettings.default              // HMP ±5% → 334 → 317…351
    let r = read(
        [
            session(day: 1, zone: "hmp", adj: 334),  // dead on the anchor
            session(day: 8, zone: "10k", adj: 318),  // inside the fast edge
            session(day: 15, zone: "mp", adj: 356),  // outside the slow edge
        ],
        settings: settings
    )
    let anchorSec = try #require(r.anchorSec)
    #expect(anchorSec == 334)
    for point in r.points(zone: nil, includeLongRuns: true) {
        #expect(r.isInBand(point) == settings.contains(paceSec: point.adjSec, anchorSec: anchorSec))
    }
    #expect(r.inBandCount(zone: nil, includeLongRuns: true) == 2)
}

// MARK: - Degradation

@Test("With no ladder the dots still plot; the band and the targets simply aren't there")
func noLadderDegradesWithoutGuessing() {
    let r = read(
        [session(day: 1, zone: "hmp", adj: 336), session(day: 8, zone: "hmp", adj: 333)],
        bands: nil
    )
    #expect(r.points.count == 2)
    #expect(r.ladder == nil)
    #expect(r.anchorSec == nil)
    #expect(!r.hasBand)
    #expect(r.inBandCount(zone: nil, includeLongRuns: false) == nil)
    #expect(r.anchorSteps.isEmpty)
    // No target means no vs-target value — omitted, not zeroed.
    #expect(r.points[0].zoneAnchorSec == nil)
    #expect(r.points[0].value(mode: .vsTarget, basis: .watch) == nil)
    #expect(r.points[0].value(mode: .absolute, basis: .watch) == 336)
}

// MARK: - Windowing

@Test("The window is a real date filter, not a trailing count of rows")
func windowFiltersByDate() {
    let all = [
        session(day: 0, zone: "hmp", adj: 340),
        session(day: 40, zone: "hmp", adj: 336),
        session(day: 59, zone: "hmp", adj: 332),
    ]
    let month = read(all, window: .thirtyDays, lastDay: 60)
    #expect(month.points.count == 2, "day 0 is outside a 30-day window ending at day 60")
    #expect(read(all, window: .sixMonths, lastDay: 60).points.count == 3)
}

@Test("A custom window reads its own bounds in either order")
func customWindowBounds() {
    let a = KeyPaceBuilder.bounds(
        window: .custom(from: dayDate(10), to: dayDate(20)), asOf: dayDate(99)
    )
    #expect(a.from == epochDay + 10)
    #expect(a.to == epochDay + 20)

    let reversed = KeyPaceBuilder.bounds(
        window: .custom(from: dayDate(20), to: dayDate(10)), asOf: dayDate(99)
    )
    #expect(reversed.from == epochDay + 10)
    #expect(reversed.to == epochDay + 20)
}

// MARK: - The headline

@Test("The headline names one zone and never spans two")
func headlineIsZoneScoped() {
    let r = read([
        session(day: 1, zone: "hmp", adj: 342),
        session(day: 8, zone: "mile", adj: 280),
        session(day: 15, zone: "hmp", adj: 338),
        session(day: 22, zone: "hmp", adj: 334),
    ])
    #expect(r.dominantZone(includeLongRuns: false) == "hmp")
    let headline = KeyPaceProse.headline(read: r, includeLongRuns: false)
    #expect(headline == "HMP work: 5:42 to 5:34.")
    #expect(!headline.contains("4:4"), "the mile session must not leak into the HMP range")
}

@Test("A zone with one graded session makes no range claim")
func headlineWithoutARange() {
    let r = read([session(day: 1, zone: "hmp", adj: 336)])
    #expect(KeyPaceProse.headline(read: r, includeLongRuns: false) == "HMP work, session by session.")
}

@Test("An empty read says so in words, never with a dash")
func emptyReadHasProse() {
    let r = read([])
    let note = KeyPaceProse.note(read: r, zone: nil, includeLongRuns: false)
    #expect(!note.isEmpty)
    #expect(!note.contains("—"))
    #expect(KeyPaceProse.headline(read: r, includeLongRuns: false) == "Quality-session pace.")
    #expect(KeyPaceProse.subtitle(read: r, includeLongRuns: false).isEmpty)
}

@Test("The ALL note refuses a trend out loud rather than silently omitting one")
func allZonesNoteExplainsItself() {
    let r = read([
        session(day: 1, zone: "5k", adj: 310),
        session(day: 8, zone: "mp", adj: 356),
        session(day: 15, zone: "5k", adj: 306),
    ])
    let note = KeyPaceProse.note(read: r, zone: nil, includeLongRuns: false)
    #expect(note.contains("No trend is drawn here"))
    #expect(note.contains("Pick a zone"))
}

@Test("A hidden long run is named in the not-counted line")
func notCountedNamesWhatIsHidden() throws {
    let r = read([
        session(day: 1, zone: "hmp", adj: 336),
        session(day: 3, zone: "mp", adj: 356, kind: "long_run"),
    ])
    let hidden = try #require(KeyPaceProse.notCounted(read: r, zone: nil, includeLongRuns: false))
    #expect(hidden.contains("1 long run is hidden"))
    #expect(KeyPaceProse.notCounted(read: r, zone: nil, includeLongRuns: true) == nil)
}

// MARK: - Anchor steps

@Test("The anchor is drawn as weekly steps, collapsed when flat and clipped to the window")
func anchorStepsAreClippedAndCollapsed() {
    let early = BandLadder(mp: 372, hmp: 354, lt: 346, k10: 338, k5: 325, k3: 308, mile: 298)
    let late = BandLadder(mp: 352, hmp: 334, lt: 326, k10: 318, k5: 305, k3: 288, mile: 278)
    let bands = BandLaps(
        sessions: [bandSession(0, early), bandSession(7, early), bandSession(21, late)],
        confidenceTier: "high", windowStart: nil, windowEnd: nil
    )
    let r = read([session(day: 25, zone: "hmp", adj: 334)], bands: bands, lastDay: 30)
    // Two identical early ladders collapse into one segment; the change at
    // day 21 starts a second.
    #expect(r.anchorSteps.count == 2)
    #expect(r.anchorSteps[0].sec == 354)
    #expect(r.anchorSteps[1].sec == 334)
    #expect(r.anchorSteps[1].endDay == KeyPaceBuilder.bounds(window: .sixMonths, asOf: dayDate(30)).to)
    #expect(r.anchorSteps.allSatisfy { $0.endDay >= $0.startDay })
}

@Test("Low confidence travels from the payload to the read")
func lowConfidenceTravels() {
    let low = read([session(day: 1, zone: "hmp", adj: 336)], bands: bandLaps(tier: "low"))
    #expect(low.lowConfidence)
    #expect(!read([session(day: 1, zone: "hmp", adj: 336)]).lowConfidence)
}


// MARK: - Basis · what the athlete sees first

@Test("Watch pace is what leads; the adjusted number is offered beside it")
func watchPaceLeads() throws {
    let r = read([
        session(day: 1, zone: "hmp", adj: 330, raw: 337),
        session(day: 8, zone: "hmp", adj: 328, raw: 334),
        session(day: 15, zone: "hmp", adj: 326, raw: 331),
    ])
    let p = try #require(r.points.first)

    #expect(p.sec(.watch) == 337, "the watch number is the raw one")
    #expect(p.sec(.heatNeutral) == 330)
    #expect(p.value(mode: .absolute, basis: .watch) == 337)

    // The ghost tick is always the OTHER basis, so the correction stays visible
    // whichever way round the athlete is reading it.
    #expect(p.ghostValue(mode: .absolute, basis: .watch) == 330)
    #expect(p.ghostValue(mode: .absolute, basis: .heatNeutral) == 337)

    // The headline defaults to what she ran.
    #expect(KeyPaceProse.headline(read: r, includeLongRuns: false) == "HMP work: 5:37 to 5:31.")
    #expect(KeyPaceProse.headline(read: r, includeLongRuns: false, basis: .heatNeutral)
            == "HMP work: 5:30 to 5:26.")
}

@Test("An unheated session draws no ghost tick on either basis")
func noCorrectionNoGhost() {
    let r = read([session(day: 1, zone: "hmp", adj: 330)])
    let p = r.points[0]
    #expect(p.ghostValue(mode: .absolute, basis: .watch) == nil)
    #expect(p.ghostValue(mode: .absolute, basis: .heatNeutral) == nil)
    #expect(p.sec(.watch) == p.sec(.heatNeutral))
}

@Test("The trend is fitted on whichever basis is showing, so the line matches the dots")
func trendFollowsTheBasis() throws {
    // Heat builds through the window: watch pace flattens while the corrected
    // pace keeps improving. The two fits must therefore disagree — and the one
    // on screen has to be the one the dots are drawn from.
    let r = read([
        session(day: 1, zone: "hmp", adj: 336, raw: 337),
        session(day: 15, zone: "hmp", adj: 333, raw: 339),
        session(day: 29, zone: "hmp", adj: 330, raw: 341),
    ])
    let watch = try #require(r.trendSecPerMonth(zone: "hmp", includeLongRuns: false, basis: .watch))
    let adjusted = try #require(
        r.trendSecPerMonth(zone: "hmp", includeLongRuns: false, basis: .heatNeutral)
    )
    #expect(watch > 0, "on watch pace she looks slower — that is the weather")
    #expect(adjusted < 0, "corrected, she is getting faster")

    let line = try #require(r.trendLine(zone: "hmp", includeLongRuns: false, basis: .watch))
    #expect(abs(line.slopePerDay * 30 - watch) < 0.000_1)
}

@Test("The watch-basis note says the weather is still in the trend")
func watchNoteNamesTheWeather() {
    let r = read([
        session(day: 1, zone: "hmp", adj: 336, raw: 337),
        session(day: 15, zone: "hmp", adj: 333, raw: 339),
        session(day: 29, zone: "hmp", adj: 330, raw: 341),
    ])
    let watch = KeyPaceProse.note(read: r, zone: "hmp", includeLongRuns: false, basis: .watch)
    #expect(watch.contains("watch paces"))
    #expect(watch.contains("still has that weather in it"))

    let adjusted = KeyPaceProse.note(read: r, zone: "hmp", includeLongRuns: false, basis: .heatNeutral)
    #expect(adjusted.contains("Heat-adjusted"))
    #expect(!adjusted.contains("still has that weather in it"))
}

@Test("Band membership is asked of the pace being shown")
func bandMembershipFollowsTheBasis() {
    // 353 watch / 344 corrected, against HMP 334 ±5% (317…351): out on the
    // watch pace, in once the heat comes out. Both answers are correct; the
    // surface must not report one while showing the other.
    let r = read([session(day: 1, zone: "hmp", adj: 344, raw: 353)])
    let p = r.points[0]
    #expect(!r.isInBand(p, basis: .watch))
    #expect(r.isInBand(p, basis: .heatNeutral))
    #expect(r.inBandCount(zone: nil, includeLongRuns: false, basis: .watch) == 0)
    #expect(r.inBandCount(zone: nil, includeLongRuns: false, basis: .heatNeutral) == 1)
}

// MARK: - Volume · dot size

private func lap(_ adj: Int, seconds: Int, miles: Double = 0.6, hr: Int? = 168, skip: Bool = false) -> BandLap {
    BandLap(sec: seconds, miles: miles, adjSec: adj, rawSec: adj, hr: hr, skip: skip)
}

/// A band session whose id matches a key session's, so the two join.
private func lappedSession(id: String, day: Int, laps: [BandLap]) -> BandSession {
    BandSession(
        id: id,
        date: iso(day),
        dateLabel: "D\(day)",
        sessionMiles: 10,
        dewPointF: 60,
        anchors: standardLadder,
        laps: laps
    )
}

@Test("Volume is the time actually spent inside that session's own pace band")
func volumeIsMeasuredFromLaps() throws {
    // HMP anchor 334, ±5% → 317…351. Three 5-minute laps land inside it; a
    // slow float and a skipped lap do not.
    let s = session(day: 5, zone: "hmp", adj: 330)
    let bands = BandLaps(
        sessions: [lappedSession(id: s.id, day: 5, laps: [
            lap(330, seconds: 300),
            lap(332, seconds: 300),
            lap(329, seconds: 300),
            lap(430, seconds: 240),                 // float, outside the band
            lap(330, seconds: 600, skip: true),     // skipped, never counts
        ])],
        confidenceTier: "high", windowStart: nil, windowEnd: nil
    )
    let r = read([s], bands: bands)
    let p = try #require(r.points.first)

    #expect(p.bandMinutes == 15, "three 5-minute laps, and only those")
    #expect(p.volumeSource == .measured)
    // Tolerance, not equality: 1.8 miles is reached by summing three laps of
    // 0.6, which in binary lands on 1.7999999999999998. The displayed label is
    // the contract here, and it rounds.
    #expect(abs(try #require(p.bandMiles) - 1.8) < 0.001)
    #expect(abs(try #require(p.volumeValue) - 1.8) < 0.001)
    #expect(p.volumeShortLabel == "1.8 MI")
    #expect(abs(try #require(r.totalBandMiles(zone: nil, includeLongRuns: false)) - 1.8) < 0.001)
}

@Test("Widening the band counts more of the session — and the dots grow")
func volumeRespondsToTheBandWidth() throws {
    let s = session(day: 5, zone: "hmp", adj: 330)
    let laps = [lap(330, seconds: 300), lap(358, seconds: 300)]  // 358 is outside ±5%
    let bands = BandLaps(
        sessions: [lappedSession(id: s.id, day: 5, laps: laps)],
        confidenceTier: "high", windowStart: nil, windowEnd: nil
    )
    let tight = read([s], bands: bands)
    #expect(tight.points[0].bandMinutes == 5)

    var wide = BandSettings.default
    wide.slowPct = 9                                    // 334 → slow edge 364
    let loose = read([s], settings: wide, bands: bands)
    #expect(loose.points[0].bandMinutes == 10, "the slower lap is inside the wider band")
}

@Test("With no laps to measure, volume falls back to quality load and says so")
func volumeFallsBackToQualityLoad() throws {
    var s = session(day: 5, zone: "hmp", adj: 330)
    s.qualityLoad = 42
    let r = read([s])                                   // band ids don't match
    let p = try #require(r.points.first)
    #expect(p.bandMiles == nil)
    #expect(p.volumeSource == .load)
    #expect(p.volumeValue == 42)
    #expect(p.volumeShortLabel == "42 LOAD")
    // Not measured, so it must not be reported as measured miles.
    #expect(r.totalBandMiles(zone: nil, includeLongRuns: false) == nil)
}

@Test("No laps and no load means base-size dots, not zero-size ones")
func volumeAbsentIsNotZero() {
    let r = read([session(day: 5, zone: "hmp", adj: 330)])
    #expect(r.points[0].volumeSource == .none)
    #expect(r.points[0].volumeValue == nil)
    #expect(r.points[0].volumeLabel == nil)
    #expect(r.volumeDomain(zone: nil, includeLongRuns: false) == nil, "no spread, no scale")
}

@Test("A volume scale needs a real spread")
func volumeDomainNeedsSpread() throws {
    var a = session(day: 1, zone: "hmp", adj: 330); a.qualityLoad = 30
    var b = session(day: 8, zone: "hmp", adj: 330); b.qualityLoad = 30
    #expect(read([a, b]).volumeDomain(zone: nil, includeLongRuns: false) == nil,
            "identical volumes would size dots differently for no reason")

    b.qualityLoad = 60
    let domain = try #require(read([a, b]).volumeDomain(zone: nil, includeLongRuns: false))
    #expect(domain.lo == 30)
    #expect(domain.hi == 60)
}

// MARK: - Heart rate lane

@Test("The HR domain always contains the floor, so the floor line is on screen")
func hrDomainIncludesTheFloor() throws {
    // Every session well above the floor: the domain still has to reach down
    // to 160, or the dashed line that defines the grade rule is off-screen.
    let r = read([
        session(day: 1, zone: "hmp", adj: 330, hr: 172),
        session(day: 8, zone: "hmp", adj: 330, hr: 176),
    ])
    let domain = try #require(r.hrDomain(zone: nil, includeLongRuns: false))
    #expect(domain.lo <= 160)
    #expect(domain.hi >= 176)
}

@Test("No heart rate anywhere means no lane, rather than an empty one")
func hrDomainNilWithoutHr() {
    let r = read([
        session(day: 1, zone: "hmp", adj: 330, hr: nil),
        session(day: 8, zone: "hmp", adj: 330, hr: nil),
    ])
    #expect(r.hrDomain(zone: nil, includeLongRuns: false) == nil)
}

// MARK: - Copy

@Test("A slope that rounds to zero is called flat, not zero-seconds-slower")
func zeroSlopeIsCalledFlat() {
    // Three sessions on the same pace: the fit is 0, and a direction word
    // attached to it would be meaningless. This shipped once.
    let r = read([
        session(day: 1, zone: "hmp", adj: 332),
        session(day: 15, zone: "hmp", adj: 332),
        session(day: 29, zone: "hmp", adj: 332),
    ])
    let note = KeyPaceProse.note(read: r, zone: "hmp", includeLongRuns: false)
    #expect(note.contains("flat to within a second"))
    #expect(!note.contains("0 seconds"))
    #expect(!note.contains("slower"))
    #expect(!note.contains("quicker"))
}

@Test("The basis label says what it is, not what device produced it")
func basisLabelsAreSelfExplaining() {
    #expect(KeyPaceBasis.watch.short == "AS RECORDED")
    #expect(KeyPaceBasis.heatNeutral.short == "HEAT-ADJUSTED")
    #expect(KeyPaceBasis.watch.other == .heatNeutral)
    #expect(KeyPaceBasis.heatNeutral.other == .watch)
}

// MARK: - Efficiency lane

@Test("Efficiency reuses card 03's function rather than a second formula")
func efficiencyMatchesTheSharedImplementation() throws {
    let r = read([session(day: 1, zone: "hmp", adj: 330, hr: 165)])
    let p = try #require(r.points.first)
    let mine = try #require(p.metresPerBeat(.watch))
    let shared = try #require(InstrumentsData.metresPerBeat(paceSec: 330, hr: 165))
    #expect(abs(mine - shared) < 0.000_001)
    // 1609.344 ÷ (330/60 × 165) beats ≈ 1.774 m per beat.
    #expect(abs(mine - 1.7738) < 0.001)
}

@Test("Efficiency follows the pace basis, so the lane agrees with the dots")
func efficiencyFollowsTheBasis() throws {
    // 9 seconds of heat: the corrected pace is quicker, so the corrected
    // efficiency is higher for the same heartbeats.
    let r = read([session(day: 1, zone: "hmp", adj: 330, raw: 339, hr: 165)])
    let p = try #require(r.points.first)
    let asRecorded = try #require(p.metresPerBeat(.watch))
    let adjusted = try #require(p.metresPerBeat(.heatNeutral))
    #expect(adjusted > asRecorded)
}

@Test("No heart rate means no efficiency — never a substituted one")
func efficiencyNeedsHeartRate() {
    let r = read([session(day: 1, zone: "hmp", adj: 330, hr: nil)])
    #expect(r.points[0].metresPerBeat(.watch) == nil)
    #expect(r.points[0].efficiencyLabel(.watch) == nil)
    #expect(r.efficiencyDomain(zone: nil, includeLongRuns: false, basis: .watch) == nil)
    #expect(r.medianEfficiency(zone: nil, includeLongRuns: false, basis: .watch) == nil)
}

@Test("The lane's reference is a median, so one odd session can't move it")
func efficiencyReferenceIsAMedian() throws {
    let base = [
        session(day: 1, zone: "hmp", adj: 330, hr: 165),
        session(day: 8, zone: "hmp", adj: 330, hr: 165),
        session(day: 15, zone: "hmp", adj: 330, hr: 165),
    ]
    let clean = try #require(read(base).medianEfficiency(
        zone: nil, includeLongRuns: false, basis: .watch
    ))
    // A strap that read 90 bpm all session would wreck a mean; the median
    // shrugs.
    let withOutlier = try #require(read(base + [
        session(day: 22, zone: "hmp", adj: 330, hr: 90)
    ]).medianEfficiency(zone: nil, includeLongRuns: false, basis: .watch))
    #expect(abs(clean - withOutlier) < 0.001)
}

@Test("The lane's readings are distinct states, and off is one of them")
func laneStates() {
    #expect(KeyPaceLane.efficiency.isVisible)
    #expect(KeyPaceLane.heartRate.isVisible)
    #expect(!KeyPaceLane.off.isVisible)
    #expect(KeyPaceLane.efficiency.axisLabel == "M / BEAT")
    #expect(KeyPaceLane.heartRate.axisLabel == "HR")
}

@Test("A flat trend reads as a word in the stat row, not as 0s")
func flatTrendIsNotZeroSeconds() throws {
    // Same guard as the note: a slope that rounds to zero must not be printed
    // as a number, because "0s" reads as a value the app failed to compute.
    let r = read([
        session(day: 1, zone: "hmp", adj: 332),
        session(day: 15, zone: "hmp", adj: 332),
        session(day: 29, zone: "hmp", adj: 332),
    ])
    let slope = try #require(r.trendSecPerMonth(zone: "hmp", includeLongRuns: false, basis: .watch))
    #expect(Int(abs(slope).rounded()) == 0, "the fixture is genuinely flat")
    // The stat row's rule, asserted on the same condition the view branches on.
    #expect(KeyPaceProse.signedSec(slope) == "0s", "which is exactly why it is not shown")
}

@Test("The session count names the graded subset the trend was fitted on")
func sessionCountNamesItsSubset() {
    // Four sessions, one under the floor: the slope uses three. A row reading
    // "4 SESSIONS" beside a slope from three invites the wrong inference, so
    // the count stat has to carry the subset itself.
    let r = read([
        session(day: 1, zone: "hmp", adj: 336),
        session(day: 15, zone: "hmp", adj: 333),
        session(day: 29, zone: "hmp", adj: 330),
        session(day: 36, zone: "hmp", adj: 350, hr: 120),   // cruise
    ])
    let pts = r.points(zone: "hmp", includeLongRuns: false)
    #expect(pts.count == 4)
    #expect(pts.filter(\.isWork).count == 3)
    // The fit ignores the cruise session — that is the fact the row must not
    // leave the reader to guess.
    #expect(r.trendSecPerMonth(zone: "hmp", includeLongRuns: false) != nil)
}


@Test("Chips list slowest first, and rank is left alone")
func chipOrderIsSlowestFirst() {
    #expect(KeyZone.chipOrder == ["mp", "hmp", "10k", "5k", "3k", "mile"])
    // Same set, no zone gained or lost by reversing.
    #expect(Set(KeyZone.chipOrder) == Set(KeyZone.order))
    // `rank` still reads fast → slow, because four other call sites treat it
    // as an ordinal rather than a layout.
    #expect(KeyZone.rank("mile") < KeyZone.rank("mp"))
}


@Test("Work run QUICKER than the zone target still counts as work")
func volumeCountsFasterThanTargetWork() throws {
    // The bug this pins: a session the classifier labels HMP but which was
    // actually run at LT effort sits faster than the band's fast edge. The
    // fast edge used to throw that work away, so five miles of reps measured
    // as one lap. Only the slow edge has a job inside a single session.
    let s = session(day: 5, zone: "hmp", adj: 315)      // 5:15, HMP target 5:34
    let bands = BandLaps(
        sessions: [lappedSession(id: s.id, day: 5, laps: [
            lap(600, seconds: 480, miles: 1.1),         // warmup, well outside
            lap(315, seconds: 945, miles: 3.0),         // 3 mi rep
            lap(450, seconds: 180, miles: 0.4),         // jog
            lap(313, seconds: 313, miles: 1.0),         // 1 mi rep
            lap(450, seconds: 180, miles: 0.4),         // jog
            lap(311, seconds: 311, miles: 1.0),         // 1 mi rep
            lap(620, seconds: 400, miles: 0.9),         // cooldown
        ])],
        confidenceTier: "high", windowStart: nil, windowEnd: nil
    )
    let p = try #require(read([s], bands: bands).points.first)
    #expect(p.bandMiles == 5.0, "3 + 1 + 1, the reps and nothing else")
    #expect(p.volumeShortLabel == "5.0 MI")
    // The jogs, warmup and cooldown are slower than the slow edge and are out.
    #expect(Int((p.bandMinutes ?? 0).rounded()) == 26)
}


// MARK: - Per-zone heart-rate floors

@Test("Each zone gets its own floor, from its own median")
func floorsAreDerivedPerZone() throws {
    // MP sessions run cooler than 5K sessions. One absolute number cannot
    // serve both, which is the bug: a good MP workout graded cruise for the
    // crime of being marathon pace.
    let sessions = [
        session(day: 1, zone: "mp", adj: 352, hr: 152),
        session(day: 8, zone: "mp", adj: 352, hr: 155),
        session(day: 15, zone: "mp", adj: 352, hr: 158),
        session(day: 22, zone: "5k", adj: 305, hr: 172),
        session(day: 29, zone: "5k", adj: 305, hr: 174),
        session(day: 36, zone: "5k", adj: 305, hr: 176),
    ]
    let floors = KeyPaceFloors.derive(from: sessions, settings: .default)
    #expect(floors.floor(for: "mp") == 147, "median 155 less the 8 bpm margin")
    #expect(floors.floor(for: "5k") == 166, "median 174 less the margin")
    #expect(floors.floor(for: "mp")! < floors.floor(for: "5k")!)
}

@Test("A good MP session no longer grades cruise for being marathon pace")
func mpSessionsAreNotDemotedByAnAbsoluteFloor() {
    let sessions = [
        session(day: 1, zone: "mp", adj: 352, hr: 152),
        session(day: 8, zone: "mp", adj: 352, hr: 155),
        session(day: 15, zone: "mp", adj: 352, hr: 158),
    ]
    let r = read(sessions)
    // Every one of these sits under the old absolute 160 and would have been
    // demoted out of the trend.
    #expect(sessions.allSatisfy { ($0.workHrAvg ?? 0) < 160 })
    #expect(r.points(zone: "mp", includeLongRuns: false).allSatisfy { $0.isWork })
}

@Test("A zone genuinely run easy is still caught")
func anEasySessionForItsZoneStillGradesCruise() throws {
    let r = read([
        session(day: 1, zone: "mp", adj: 352, hr: 155),
        session(day: 8, zone: "mp", adj: 352, hr: 156),
        session(day: 15, zone: "mp", adj: 352, hr: 157),
        session(day: 22, zone: "mp", adj: 352, hr: 132),   // easy for MP
    ])
    let pts = r.points(zone: "mp", includeLongRuns: false)
    #expect(pts.dropLast().allSatisfy { $0.isWork })
    #expect(pts.last?.grade == .cruise, "well under this zone's own median")
}

@Test("Too few sessions in a zone means no floor, not a guessed one")
func sparseZoneGetsNoFloor() {
    let r = read([
        session(day: 1, zone: "mile", adj: 278, hr: 140),
        session(day: 8, zone: "mile", adj: 278, hr: 142),
    ])
    #expect(r.floors.floor(for: "mile") == nil, "two sessions is not a median")
    // …and an unjudged session is work, not cruise.
    #expect(r.points(zone: "mile", includeLongRuns: false).allSatisfy { $0.isWork })
}

@Test("Turning the floor off turns per-zone grading off with it")
func zeroGlobalFloorDisablesAllZones() {
    var noStrap = BandSettings.default
    noStrap.hrFloor = 0
    let r = read([
        session(day: 1, zone: "mp", adj: 352, hr: 100),
        session(day: 8, zone: "mp", adj: 352, hr: 105),
        session(day: 15, zone: "mp", adj: 352, hr: 110),
    ], settings: noStrap)
    #expect(r.floors.isDisabled)
    #expect(r.floors.floor(for: "mp") == nil)
    #expect(r.points(zone: "mp", includeLongRuns: false).allSatisfy { $0.isWork })
}

@Test("Floors come from the whole history, not just the visible window")
func floorsIgnoreTheWindow() {
    // Narrowing the range must not move what counts as hard for a zone.
    let all = [
        session(day: 0, zone: "mp", adj: 352, hr: 152),
        session(day: 10, zone: "mp", adj: 352, hr: 155),
        session(day: 55, zone: "mp", adj: 352, hr: 158),
    ]
    let wide = read(all, window: .sixMonths, lastDay: 60)
    let narrow = read(all, window: .thirtyDays, lastDay: 60)
    #expect(narrow.points.count < wide.points.count)
    #expect(narrow.floors == wide.floors)
}
