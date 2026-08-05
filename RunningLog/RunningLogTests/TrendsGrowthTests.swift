import Foundation
import Testing
@testable import RunningLog

// Guards for `TrendsGrowthModels.swift` — the one section on Trends allowed to
// point forward, and therefore the one with the strictest rules. Each test
// encodes a decision: when a rule is allowed to speak, when it must stay quiet,
// and what it is never allowed to say.

// MARK: - Fixtures

private func day(
    _ iso: String,
    _ miles: Double,
    mood: String? = nil,
    niggle: String? = nil
) -> TrendsDay {
    TrendsDay(
        date: iso,
        miles: miles,
        type: .init(token: miles > 0 ? "easy" : "rest"),
        mood: mood,
        niggles: niggle.map {
            [TrendsDay.DayNiggle(area: $0, side: nil, severity: "sore", quote: "her own words")]
        } ?? []
    )
}

private func bucket(
    _ iso: String,
    miles: Double,
    load: Double = 0,
    mood: String? = nil,
    recovery: Int = 50
) -> TrendsBucket {
    TrendsBucket(
        startISO: iso,
        date: Date(timeIntervalSince1970: 0),
        label: String(iso.suffix(5)),
        miles: miles,
        keyCount: load > 0 ? 1 : 0,
        longCount: 0,
        channel: miles > 0 ? .easy : .rest,
        qualityLoad: load,
        mood: mood,
        niggles: [],
        recovery: recovery,
        isWeekStart: false,
        dayCount: 1
    )
}

/// A 28-day window. `clearEvery` inserts a zero-mile day at that cadence;
/// 0 means no clear days at all.
private func set(
    days count: Int = 28,
    clearEvery: Int = 0,
    moodEvery: Int = 0,
    niggles: Int = 0
) -> TrendsBucketSet {
    var trendsDays: [TrendsDay] = []
    var buckets: [TrendsBucket] = []
    for i in 0..<count {
        let iso = String(format: "2026-06-%02d", (i % 28) + 1)
        let isClear = clearEvery > 0 && i % clearEvery == 0
        let mood = moodEvery > 0 && i % moodEvery == 0 ? "positive" : nil
        let niggle = i < niggles ? "knee" : nil
        trendsDays.append(day(iso, isClear ? 0 : 8, mood: mood, niggle: niggle))
        buckets.append(bucket(iso, miles: isClear ? 0 : 8, mood: mood))
    }
    return TrendsBucketSet(grain: .day, buckets: buckets, days: trendsDays)
}

private func spectrum(_ slices: [(String, Int, Double)]) -> QualitySpectrumRead {
    QualitySpectrumRead(
        slices: slices.map { token, pace, miles in
            QualityZoneSlice(
                id: token,
                label: KeyZone.label(token),
                paceSec: pace,
                seconds: Int(miles * Double(pace)),
                miles: miles,
                sessionCount: 3
            )
        },
        totalMiles: slices.reduce(0) { $0 + $1.2 },
        windowMiles: 200
    )
}

private func keySession(
    _ iso: String,
    raw: Int,
    adj: Int?,
    category: String? = "hot"
) -> KeySession {
    KeySession(
        id: "log-" + iso,
        date: iso,
        dateLabel: String(iso.suffix(5)),
        zone: "hmp",
        workPaceSec: raw,
        workPaceAdjSec: adj,
        heatCategory: adj == nil ? nil : category,
        workHrAvg: 165,
        structure: nil,
        distanceMi: 10,
        qualityLoad: 40,
        kind: "quality"
    )
}

// MARK: - The vocabulary lint

@Suite("GrowthVocabulary")
struct GrowthVocabularyTests {

    /// The same lint the `trends-insights` detectors are held to, enforced on
    /// this side of the wire too. Clinical verbs, instruction and causal
    /// claims are all outside what this data can support.
    @Test("banned terms are caught on a word boundary")
    func catchesBannedWords() {
        #expect(!GrowthVocabulary.isClean("You should take a rest day"))
        #expect(!GrowthVocabulary.isClean("The load caused it"))
        #expect(!GrowthVocabulary.isClean("Stop running for a week"))
    }

    /// A substring match would fire on "wrestling" and "greatest". Word
    /// boundaries keep the lint usable.
    @Test("innocent words containing a banned substring pass")
    func noSubstringFalsePositives() {
        #expect(GrowthVocabulary.isClean("The greatest week of the block"))
        #expect(GrowthVocabulary.isClean("Wrestling with the heat"))
        #expect(GrowthVocabulary.isClean("Musty air on the long run"))
    }

    /// The point of the lint: nothing this section can emit may break it, for
    /// any input. Exercising every rule at once is the cheapest proof.
    @Test("every string the builder can emit is clean")
    func everyEmittedStringIsClean() {
        let reads = [
            GrowthBuilder.build(
                set: set(clearEvery: 0, moodEvery: 0, niggles: 3),
                threshold: nil,
                spectrum: spectrum([("hmp", 330, 40), ("mp", 350, 4)]),
                keySessions: (1...5).map { keySession(String(format: "2026-06-%02d", $0), raw: 330, adj: 318) }
            ),
            GrowthBuilder.build(
                set: set(clearEvery: 2, moodEvery: 1),
                threshold: nil,
                spectrum: spectrum([("hmp", 330, 20), ("5k", 300, 18)]),
                keySessions: []
            ),
        ]
        for read in reads {
            for o in read.opportunities {
                #expect(GrowthVocabulary.isClean(o.title), "title not clean: \(o.title)")
                #expect(GrowthVocabulary.isClean(o.body), "body not clean: \(o.body)")
                #expect(GrowthVocabulary.isClean(o.stat), "stat not clean: \(o.stat)")
            }
        }
    }
}

// MARK: - When the section speaks at all

@Suite("GrowthBuilder gating")
struct GrowthGatingTests {

    /// Three weeks is the floor. Under it, a run of continuous days is a
    /// schedule, not a pattern.
    @Test("a window under three weeks yields nothing")
    func shortWindowSilent() {
        let read = GrowthBuilder.build(
            set: set(days: 14),
            threshold: nil,
            spectrum: spectrum([]),
            keySessions: []
        )
        #expect(read.isEmpty)
        #expect(read.dayCount == 14)
    }

    /// An empty section is a correct answer. A window where everything sits
    /// where it wants gets silence, never filler.
    @Test("a well-balanced window yields nothing")
    func balancedWindowSilent() {
        let read = GrowthBuilder.build(
            set: set(clearEvery: 5, moodEvery: 1),
            threshold: nil,
            spectrum: spectrum([("hmp", 330, 12), ("5k", 300, 10)]),
            keySessions: []
        )
        #expect(read.isEmpty)
    }

    /// Cheapest first, always. The order is editorial and fixed: the move that
    /// removes load precedes the one that adds different training.
    @Test("opportunities come back ranked cheapest first")
    func rankedByCost() {
        let read = GrowthBuilder.build(
            set: set(clearEvery: 0, moodEvery: 0),
            threshold: nil,
            spectrum: spectrum([("hmp", 330, 40), ("mp", 350, 4)]),
            keySessions: (1...5).map { keySession(String(format: "2026-06-%02d", $0), raw: 330, adj: 318) }
        )
        #expect(read.opportunities.map(\.rank) == read.opportunities.map(\.rank).sorted())
        #expect(read.opportunities.first?.id == "days-clear")
    }
}

// MARK: - Rule by rule

@Suite("GrowthBuilder.daysClear")
struct GrowthDaysClearTests {

    @Test("an unbroken window fires")
    func unbrokenFires() throws {
        let o = try #require(GrowthBuilder.daysClear(set(clearEvery: 0)))
        #expect(o.id == "days-clear")
        #expect(o.stat == "0 of 28")
    }

    /// Deliberately lax: a normal six-day schedule is not an opportunity.
    @Test("a normal schedule with a day off each week stays quiet")
    func weeklyDayOffQuiet() {
        #expect(GrowthBuilder.daysClear(set(clearEvery: 7)) == nil)
    }

    /// The body names the body mentions when there are any, so the row is
    /// carried by evidence rather than by a general principle.
    @Test("body mentions inside the window are named")
    func nigglesNamed() throws {
        let o = try #require(GrowthBuilder.daysClear(set(clearEvery: 0, niggles: 2)))
        #expect(o.body.contains("knee"))
        #expect(GrowthVocabulary.isClean(o.body))
    }
}

@Suite("GrowthBuilder.bandLength")
struct GrowthBandLengthTests {

    private func read(minutes: Double, sessions: Int, cruise: Double = 0) -> ThresholdRead {
        var points = (0..<sessions).map { i in
            ThresholdPoint(
                id: "w\(i)", date: String(format: "2026-06-%02d", i + 1),
                dateLabel: "Jun \(i + 1)", minutes: minutes, miles: 3,
                adjSec: 320, rawSec: 320, correctionSec: 0, hrAvg: 168,
                dewPointF: 68, grade: .work
            )
        }
        if cruise > 0 {
            points.append(
                ThresholdPoint(
                    id: "c", date: "2026-06-20", dateLabel: "Jun 20",
                    minutes: cruise, miles: 1, adjSec: 366, rawSec: 366,
                    correctionSec: 0, hrAvg: 145, dewPointF: 70, grade: .cruise
                )
            )
        }
        return ThresholdRead(
            points: points, band: .hm, anchorSec: 323, fastSec: 307, slowSec: 339,
            hrFloor: 160, lowConfidence: false
        )
    }

    @Test("short band sessions fire")
    func shortFires() throws {
        let o = try #require(GrowthBuilder.bandLength(read(minutes: 12, sessions: 4)))
        #expect(o.stat == "12 min")
        #expect(o.rank == 2)
    }

    @Test("sessions already at the target stay quiet")
    func atTargetQuiet() {
        #expect(GrowthBuilder.bandLength(read(minutes: 24, sessions: 4)) == nil)
    }

    /// One session is a session, not an average.
    @Test("a single graded session is not an average")
    func singleSessionQuiet() {
        #expect(GrowthBuilder.bandLength(read(minutes: 8, sessions: 1)) == nil)
    }

    /// Cruising minutes are reported separately and never folded into the
    /// per-session average — the whole point of grading them apart.
    @Test("cruising minutes are named apart from the average")
    func cruiseReportedSeparately() throws {
        let o = try #require(GrowthBuilder.bandLength(read(minutes: 12, sessions: 4, cruise: 9)))
        #expect(o.stat == "12 min")
        #expect(o.body.contains("9 minutes"))
    }
}

@Suite("GrowthBuilder.heat")
struct GrowthHeatTests {

    @Test("a meaningful mean correction fires")
    func meaningfulCorrectionFires() throws {
        let sessions = (1...4).map { keySession(String(format: "2026-06-%02d", $0), raw: 330, adj: 318) }
        let o = try #require(GrowthBuilder.heat(set: set(), keySessions: sessions))
        #expect(o.stat == "12 s/mi")
    }

    @Test("a trivial correction stays quiet")
    func trivialCorrectionQuiet() {
        let sessions = (1...4).map { keySession(String(format: "2026-06-%02d", $0), raw: 330, adj: 328) }
        #expect(GrowthBuilder.heat(set: set(), keySessions: sessions) == nil)
    }

    @Test("two corrected sessions are too few to claim a season")
    func needsThreeSessions() {
        let sessions = (1...2).map { keySession(String(format: "2026-06-%02d", $0), raw: 330, adj: 315) }
        #expect(GrowthBuilder.heat(set: set(), keySessions: sessions) == nil)
    }

    /// Sessions with no weather are absent from the mean, not zeros in it — a
    /// zero would drag the average toward "no heat" as coverage thins.
    @Test("uncorrected sessions are not counted as zero penalty")
    func uncorrectedNotZero() throws {
        let corrected = (1...3).map { keySession(String(format: "2026-06-%02d", $0), raw: 330, adj: 318) }
        let bare = (4...9).map { keySession(String(format: "2026-06-%02d", $0), raw: 330, adj: nil) }
        let o = try #require(GrowthBuilder.heat(set: set(), keySessions: corrected + bare))
        #expect(o.stat == "12 s/mi")
    }

    /// A session outside the window cannot carry a finding about the window.
    @Test("sessions outside the window are ignored")
    func windowFilterApplies() {
        let outside = (1...5).map { keySession(String(format: "2025-01-%02d", $0), raw: 330, adj: 315) }
        #expect(GrowthBuilder.heat(set: set(), keySessions: outside) == nil)
    }
}

@Suite("GrowthBuilder.felt")
struct GrowthFeltTests {

    @Test("thin mood coverage fires")
    func thinCoverageFires() throws {
        let o = try #require(GrowthBuilder.felt(set(moodEvery: 7)))
        #expect(o.id == "felt")
        #expect(o.stat == "4 / 28")
    }

    @Test("good coverage stays quiet")
    func goodCoverageQuiet() {
        #expect(GrowthBuilder.felt(set(moodEvery: 2)) == nil)
    }
}

@Suite("GrowthBuilder.spread")
struct GrowthSpreadTests {

    @Test("work concentrated in one zone fires")
    func concentratedFires() throws {
        let o = try #require(GrowthBuilder.spread(spectrum([("hmp", 330, 40), ("mp", 350, 4)])))
        #expect(o.rank == 5)
        #expect(o.body.contains("HMP"))
    }

    @Test("an even spread stays quiet")
    func evenSpreadQuiet() {
        #expect(GrowthBuilder.spread(spectrum([("hmp", 330, 20), ("5k", 300, 18)])) == nil)
    }

    /// With one zone there is no spread to comment on — 100% of one thing is
    /// arithmetic, not a finding.
    @Test("a single zone is not a concentration finding")
    func singleZoneQuiet() {
        #expect(GrowthBuilder.spread(spectrum([("hmp", 330, 40)])) == nil)
    }
}
