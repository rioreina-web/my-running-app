import Foundation
import Testing
@testable import RunningLog

// Guards for `SignalLabModels.swift`. The Lab's whole claim is that a metric
// it cannot compute from real readings is absent rather than estimated, so
// most of these tests are about what the builders refuse to do.

// MARK: - Fixtures

private func key(
    _ iso: String,
    zone: String = "hmp",
    raw: Int = 330,
    adj: Int? = nil,
    hr: Int? = 165,
    kind: String = "quality",
    category: String? = nil
) -> KeySession {
    KeySession(
        id: "log-" + iso,
        date: iso,
        dateLabel: String(iso.suffix(5)),
        zone: zone,
        workPaceSec: raw,
        workPaceAdjSec: adj,
        heatCategory: category ?? (adj == nil ? nil : "hot"),
        workHrAvg: hr,
        structure: nil,
        distanceMi: 10,
        qualityLoad: 40,
        kind: kind
    )
}

private func card(
    id: String,
    group: String,
    points: [Double],
    unit: String?,
    headline: String = "Drift is tracking the season",
    body: String = "Decoupling on your long runs.",
    band: (lo: Double, hi: Double)? = (0, 5)
) -> TrendInsightCard {
    // Decoded rather than constructed: `TrendInsightCard` and `TrendSeries`
    // are `Decodable` only, and going through JSON also exercises the wire
    // contract the Lab depends on.
    let bandJSON = band.map { "\"band\":{\"lo\":\($0.lo),\"hi\":\($0.hi)}," } ?? ""
    let unitJSON = unit.map { "\"unit\":\"\($0)\"," } ?? ""
    let json = """
    {
      "id": "\(id)", "group": "\(group)", "status": "active",
      "headline": "\(headline)", "body": "\(body)",
      "evidence": [], "confidence": "medium",
      "series": { "points": \(points), \(unitJSON)\(bandJSON)"polarity": "down_good" }
    }
    """
    // A fixture that will not decode is a broken test, not a passing one.
    return try! JSONDecoder().decode(TrendInsightCard.self, from: Data(json.utf8))
}

private func bucket(
    _ iso: String,
    miles: Double,
    load: Double,
    mood: String?,
    recovery: Int = 50
) -> TrendsBucket {
    TrendsBucket(
        startISO: iso, date: Date(timeIntervalSince1970: 0), label: iso,
        miles: miles, keyCount: load > 0 ? 1 : 0, longCount: 0,
        channel: miles > 0 ? .easy : .rest, qualityLoad: load, mood: mood,
        niggles: [], recovery: recovery, isWeekStart: false, dayCount: 1
    )
}

private func daySet(_ buckets: [TrendsBucket], grain: TrendsBucketSet.Grain = .day) -> TrendsBucketSet {
    TrendsBucketSet(grain: grain, buckets: buckets, days: [])
}

// MARK: - Maths

@Suite("SignalLabMath")
struct SignalLabMathTests {

    /// Metres per beat is speed over heart rate. A mile in 330 s is
    /// 1609.344 × 60 / 330 ≈ 292.6 m/min; at 165 bpm that is ≈ 1.77 m/beat.
    @Test("metres per beat is speed divided by heart rate")
    func metresPerBeat() throws {
        let mpb = try #require(SignalLabMath.metresPerBeat(paceSecPerMile: 330, hr: 165))
        #expect(abs(mpb - 1.7737) < 0.001)
    }

    @Test("a zero or missing input yields no reading")
    func rejectsZeroes() {
        #expect(SignalLabMath.metresPerBeat(paceSecPerMile: 0, hr: 165) == nil)
        #expect(SignalLabMath.metresPerBeat(paceSecPerMile: 330, hr: 0) == nil)
    }

    /// Two points fit anything, so the slope stays silent until three.
    @Test("no slope under three points")
    func slopeNeedsThree() {
        #expect(SignalLabMath.slope(xs: [0, 1], ys: [0, 1]) == nil)
        #expect(SignalLabMath.slope(xs: [0, 1, 2], ys: [0, 1, 2]) != nil)
    }

    @Test("no slope when x has no spread")
    func slopeNeedsSpread() {
        #expect(SignalLabMath.slope(xs: [3, 3, 3], ys: [1, 2, 3]) == nil)
    }
}

// MARK: - 01 · drift

@Suite("AerobicDriftBuilder")
struct AerobicDriftTests {

    @Test("a percentage-valued Group B drift card is adopted")
    func adoptsDriftCard() {
        let read = AerobicDriftBuilder.build(cards: [
            card(id: "B1", group: "B", points: [1.2, 3.4, 5.6, 2.1], unit: "%"),
        ])
        #expect(read.points.count == 4)
        #expect(read.bandHi == 5)
        #expect(read.overBand.count == 1)
    }

    /// Matching on unit and subject rather than on card id keeps this working
    /// when the detector set is renumbered — and keeps a future
    /// percentage-valued Group B card from being mistaken for drift.
    @Test("a Group B card about something else is not adopted")
    func rejectsUnrelatedCard() {
        let read = AerobicDriftBuilder.build(cards: [
            card(
                id: "B9", group: "B", points: [1, 2, 3, 4], unit: "%",
                headline: "Your easy share is climbing",
                body: "Share of easy miles week to week."
            ),
        ])
        #expect(read.isEmpty)
    }

    /// A card measured in bpm is a different signal wearing a similar word.
    @Test("a card in the wrong unit is not adopted")
    func rejectsWrongUnit() {
        let read = AerobicDriftBuilder.build(cards: [
            card(id: "B2", group: "B", points: [4, 6, 8], unit: "bpm"),
        ])
        #expect(read.isEmpty)
    }

    @Test("a card with fewer than three points is not adopted")
    func rejectsTinySeries() {
        let read = AerobicDriftBuilder.build(cards: [
            card(id: "B1", group: "B", points: [2, 4], unit: "%"),
        ])
        #expect(read.isEmpty)
    }

    @Test("no cards at all is an empty read, not a crash")
    func emptyCards() {
        #expect(AerobicDriftBuilder.build(cards: []).isEmpty)
    }

    /// Without a band on the wire the read still needs one to draw against.
    @Test("a missing band falls back to nought to five percent")
    func defaultBand() {
        let read = AerobicDriftBuilder.build(cards: [
            card(id: "B1", group: "B", points: [1, 2, 3], unit: "%", band: nil),
        ])
        #expect(read.bandLo == 0)
        #expect(read.bandHi == 5)
    }
}

// MARK: - 03 · efficiency

@Suite("BeatEfficiencyBuilder")
struct BeatEfficiencyTests {

    private let window = Set(["2026-06-01", "2026-06-08", "2026-06-15", "2026-06-22"])

    /// Reps and long efforts are different instruments. Pooling them would
    /// make the trend a function of which kind of session happened to land
    /// where in the window.
    @Test("reps and long efforts are separated")
    func separatesSeries() {
        let read = BeatEfficiencyBuilder.build(
            keySessions: [
                key("2026-06-01", raw: 300),
                key("2026-06-08", raw: 420, kind: "long_run"),
            ],
            windowDates: window
        )
        #expect(read.reps.count == 1)
        #expect(read.longs.count == 1)
    }

    /// The one thing that would quietly ruin this metric: reading raw pace, so
    /// a hot month looks like lost efficiency.
    @Test("efficiency uses heat-neutral pace, not raw")
    func usesHeatNeutralPace() throws {
        let read = BeatEfficiencyBuilder.build(
            keySessions: [key("2026-06-01", raw: 330, adj: 318, hr: 165)],
            windowDates: window
        )
        let point = try #require(read.reps.first)
        #expect(point.paceSec == 318)
        let expected = try #require(SignalLabMath.metresPerBeat(paceSecPerMile: 318, hr: 165))
        #expect(abs(point.metresPerBeat - expected) < 0.0001)
    }

    @Test("a session with no heart rate is skipped, never estimated")
    func skipsMissingHr() {
        let read = BeatEfficiencyBuilder.build(
            keySessions: [key("2026-06-01", hr: nil)],
            windowDates: window
        )
        #expect(read.isEmpty)
    }

    /// Matches the HR gate in `_shared/fitnessSignal.ts` — a reading of 40 or
    /// 240 is a sensor artefact, not an athlete.
    @Test("heart rates outside the plausible range are dropped")
    func dropsImplausibleHr() {
        let read = BeatEfficiencyBuilder.build(
            keySessions: [key("2026-06-01", hr: 42), key("2026-06-08", hr: 240)],
            windowDates: window
        )
        #expect(read.isEmpty)
    }

    @Test("sessions outside the window are ignored")
    func honoursWindow() {
        let read = BeatEfficiencyBuilder.build(
            keySessions: [key("2025-01-01")],
            windowDates: window
        )
        #expect(read.isEmpty)
    }

    @Test("the trend is metres per beat per thirty days")
    func trendUnits() throws {
        let read = BeatEfficiencyBuilder.build(
            keySessions: [
                key("2026-06-01", raw: 330, hr: 170),
                key("2026-06-08", raw: 330, hr: 165),
                key("2026-06-15", raw: 330, hr: 160),
                key("2026-06-22", raw: 330, hr: 155),
            ],
            windowDates: window
        )
        let trend = try #require(read.repsTrend)
        // Same pace at a falling heart rate is rising efficiency.
        #expect(trend > 0)
    }
}

// MARK: - 04 · mood and load

@Suite("MoodLoadBuilder")
struct MoodLoadTests {

    @Test("each logged mood becomes a group with its own means")
    func groupsByMood() throws {
        let read = MoodLoadBuilder.build(set: daySet([
            bucket("d1", miles: 10, load: 60, mood: "positive"),
            bucket("d2", miles: 8, load: 40, mood: "positive"),
            bucket("d3", miles: 6, load: 20, mood: "tired"),
            bucket("d4", miles: 6, load: 20, mood: "tired"),
        ]))
        #expect(read.groups.count == 2)
        let positive = try #require(read.groups.first { $0.id == "positive" })
        #expect(positive.meanLoad == 50)
        #expect(positive.meanMiles == 9)
    }

    /// One day is a day, not a mean.
    @Test("a mood logged once is not a group")
    func singleDayNotAGroup() {
        let read = MoodLoadBuilder.build(set: daySet([
            bucket("d1", miles: 10, load: 60, mood: "positive"),
            bucket("d2", miles: 8, load: 40, mood: "positive"),
            bucket("d3", miles: 6, load: 20, mood: "injured"),
        ]))
        #expect(read.groups.map(\.id) == ["positive"])
    }

    /// The vocabulary is closed by design. A stray label is dropped rather
    /// than appended, so the chart's rows are always a known scale.
    @Test("a label outside the vocabulary is dropped")
    func closedVocabulary() {
        let read = MoodLoadBuilder.build(set: daySet([
            bucket("d1", miles: 10, load: 60, mood: "vibing"),
            bucket("d2", miles: 10, load: 60, mood: "vibing"),
            bucket("d3", miles: 8, load: 40, mood: "tired"),
            bucket("d4", miles: 8, load: 40, mood: "tired"),
        ]))
        #expect(read.groups.map(\.id) == ["tired"])
    }

    /// Groups come back in register order, so the chart is a fixed scale
    /// rather than a ranking that reshuffles as data lands.
    @Test("groups are in vocabulary order, not by size")
    func vocabularyOrder() {
        let read = MoodLoadBuilder.build(set: daySet([
            bucket("d1", miles: 6, load: 10, mood: "struggling"),
            bucket("d2", miles: 6, load: 10, mood: "struggling"),
            bucket("d3", miles: 6, load: 10, mood: "struggling"),
            bucket("d4", miles: 10, load: 90, mood: "positive"),
            bucket("d5", miles: 10, load: 90, mood: "positive"),
        ]))
        #expect(read.groups.map(\.id) == ["positive", "struggling"])
    }

    /// At week grain a bucket's mood is already a modal rollup; pairing it
    /// with the week's summed load would compare a summary to a sum.
    @Test("week grain yields no groups")
    func weekGrainRefused() {
        let read = MoodLoadBuilder.build(set: daySet([
            bucket("w1", miles: 60, load: 300, mood: "positive"),
            bucket("w2", miles: 60, load: 300, mood: "positive"),
        ], grain: .week))
        #expect(read.isEmpty)
    }

    /// The verdict the section turns on: groups within a tenth of each other
    /// on load are not separated by load.
    @Test("load separates the groups only when the spread earns it")
    func separationVerdict() throws {
        let flat = MoodLoadBuilder.build(set: daySet([
            bucket("d1", miles: 8, load: 80, mood: "positive"),
            bucket("d2", miles: 8, load: 80, mood: "positive"),
            bucket("d3", miles: 8, load: 78, mood: "struggling"),
            bucket("d4", miles: 8, load: 78, mood: "struggling"),
        ]))
        #expect(try #require(flat.loadSeparates) == false)

        let split = MoodLoadBuilder.build(set: daySet([
            bucket("d1", miles: 12, load: 120, mood: "positive"),
            bucket("d2", miles: 12, load: 120, mood: "positive"),
            bucket("d3", miles: 4, load: 20, mood: "struggling"),
            bucket("d4", miles: 4, load: 20, mood: "struggling"),
        ]))
        #expect(try #require(split.loadSeparates) == true)
    }
}

// MARK: - 05 · heat

@Suite("HeatImpactBuilder")
struct HeatImpactTests {

    private let window = Set(["2026-06-01", "2026-06-08", "2026-06-15"])

    @Test("the penalty is raw minus heat-neutral")
    func penaltyArithmetic() throws {
        let read = HeatImpactBuilder.build(
            keySessions: [key("2026-06-01", raw: 330, adj: 318)],
            bands: nil,
            windowDates: window
        )
        let point = try #require(read.points.first)
        #expect(point.penaltySec == 12)
        #expect(read.meanPenalty == 12)
    }

    /// A session with no weather is counted as uncorrected, not as a zero —
    /// a zero would drag the mean toward "no heat" as coverage thins.
    @Test("a session with no weather is counted apart, never as zero")
    func uncorrectedCountedApart() {
        let read = HeatImpactBuilder.build(
            keySessions: [
                key("2026-06-01", raw: 330, adj: 318),
                key("2026-06-08", raw: 330, adj: nil),
            ],
            bands: nil,
            windowDates: window
        )
        #expect(read.points.count == 1)
        #expect(read.uncorrectedCount == 1)
        #expect(read.meanPenalty == 12)
    }

    /// A correction that made a pace slower is not a heat penalty; it is
    /// something else, and it is not silently sign-flipped into one.
    @Test("a non-positive correction is not a heat point")
    func rejectsNegativePenalty() {
        let read = HeatImpactBuilder.build(
            keySessions: [key("2026-06-01", raw: 318, adj: 330)],
            bands: nil,
            windowDates: window
        )
        #expect(read.isEmpty)
        #expect(read.uncorrectedCount == 1)
    }

    @Test("sessions outside the window are ignored")
    func honoursWindow() {
        let read = HeatImpactBuilder.build(
            keySessions: [key("2025-01-01", raw: 330, adj: 315)],
            bands: nil,
            windowDates: window
        )
        #expect(read.isEmpty)
        #expect(read.uncorrectedCount == 0)
    }

    /// With no dew readings there is nothing to fit, and the slope says so
    /// rather than fitting against a constant.
    @Test("no dew-point slope without dew points")
    func noSlopeWithoutDew() {
        let read = HeatImpactBuilder.build(
            keySessions: [
                key("2026-06-01", raw: 330, adj: 318),
                key("2026-06-08", raw: 330, adj: 320),
                key("2026-06-15", raw: 330, adj: 322),
            ],
            bands: nil,
            windowDates: window
        )
        #expect(read.secPerTenDegDew == nil)
        #expect(read.dewRange == nil)
    }
}
