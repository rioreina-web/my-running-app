import Foundation
import Testing
@testable import RunningLog

// Guards for the rules in `TrendsSignalModels.swift` that would otherwise
// regress silently — each one encodes a decision, not just a behaviour.

private func day(
    _ iso: String, _ miles: Double, _ type: String,
    mood: String? = nil, niggle: (area: String, severity: String)? = nil
) -> TrendsDay {
    TrendsDay(
        date: iso, miles: miles, type: .init(token: type), mood: mood,
        niggles: niggle.map {
            [TrendsDay.DayNiggle(area: $0.area, side: nil, severity: $0.severity, quote: "her own words")]
        } ?? []
    )
}

private func key(_ iso: String, kind: String = "quality", load: Double? = 40) -> KeySession {
    KeySession(
        id: iso + kind, date: iso, dateLabel: iso, zone: "mp",
        workPaceSec: 400, workPaceAdjSec: nil, heatCategory: nil, workHrAvg: nil,
        structure: nil, distanceMi: 10, qualityLoad: load, kind: kind
    )
}

// MARK: - Mood rollup

// The hardest-session rule ("a bad workout is not outvoted by a good warm-up
// and cool-down") is a DAY-level rule, and it lives in
// `trends-timeline/timeline.ts` → `hardestSessionMood`, because only the
// server sees a day's individual logs. It is tested there, in
// `timelineDaily.test.ts`.
//
// What this suite guards is the boundary: the client must NOT re-apply that
// rank when rolling days into weeks.

@Suite("TrendsSignalBuilder.weekMood")
struct TrendsWeekMoodTests {

    /// A week is a distribution over separate days, not several readings of
    /// one session. Ranking here would reduce a whole week to its single
    /// hardest day — a sample of one.
    @Test("the week's mood is modal across its days, not the hardest day's")
    func weekIsModalNotRanked() {
        // Four easy positive days against one hard tired day.
        let week = [
            day("2026-06-08", 6, "easy", mood: "positive"),
            day("2026-06-09", 6, "easy", mood: "positive"),
            day("2026-06-10", 8, "key",  mood: "tired"),
            day("2026-06-11", 6, "easy", mood: "positive"),
            day("2026-06-12", 6, "easy", mood: "positive"),
        ]
        // Pad past the daily-grain limit so the builder buckets weekly.
        let padding = (0..<130).map { i in
            day(String(format: "2026-01-%02d", 1 + i % 28), 5, "easy", mood: "neutral")
        }
        let set = TrendsSignalBuilder.build(days: padding + week, keySessions: [], window: .oneYear)
        #expect(set.grain == .week)
        let last = set.buckets.last
        #expect(last?.mood == "positive")
    }

    @Test("a week with no logged mood carries none")
    func silentWeekCarriesNoMood() {
        let days = (0..<140).map { i in
            day(String(format: "2026-%02d-%02d", 1 + i / 28, 1 + i % 28), 6, "easy")
        }
        let set = TrendsSignalBuilder.build(days: days, keySessions: [], window: .oneYear)
        #expect(set.buckets.allSatisfy { $0.mood == nil })
    }
}

// MARK: - key + long

@Suite("TrendsSessionChannel.keyLong")
struct TrendsKeyLongTests {

    private func sets(_ sessions: [KeySession]) -> (quality: Set<String>, long: Set<String>) {
        (
            Set(sessions.filter { !$0.isLongRun && QualityLoad.qualifies($0.qualityLoad) }.map(\.date)),
            Set(sessions.filter(\.isLongRun).map(\.date))
        )
    }

    /// `TrendsDay.SessionChannel` gives `long` precedence over `key`, so a long
    /// run with real quality work in it arrives as plain `long` and its key
    /// work disappears. This is the recovery.
    @Test("a `long` day carrying qualifying key work becomes keyLong")
    func recoversKeyLong() {
        let s = sets([key("2026-07-05"), key("2026-07-05", kind: "long_run", load: 30)])
        let ch = TrendsSignalBuilder.channel(
            for: day("2026-07-05", 18, "long"), quality: s.quality, longRuns: s.long
        )
        #expect(ch == .keyLong)
    }

    @Test("a plain long day stays long")
    func plainLongStaysLong() {
        let ch = TrendsSignalBuilder.channel(
            for: day("2026-07-12", 18, "long"), quality: [], longRuns: ["2026-07-12"]
        )
        #expect(ch == .long)
    }

    /// A nil or sub-floor quality load never clears the key-session gate, so an
    /// older payload degrades to "not key" rather than inventing one.
    @Test("a session under the quality floor never promotes the day")
    func floorHolds() {
        let s = sets([key("2026-07-19", load: nil)])
        let ch = TrendsSignalBuilder.channel(
            for: day("2026-07-19", 18, "long"), quality: s.quality, longRuns: ["2026-07-19"]
        )
        #expect(ch == .long)
    }

    @Test("keyLong counts as both key and long, never one or the other")
    func countsAsBoth() {
        #expect(TrendsSessionChannel.keyLong.isKey)
        #expect(TrendsSessionChannel.keyLong.isLong)
    }
}

// MARK: - Which log opens first

@Suite("TrendsSessionOrder")
struct TrendsSessionOrderTests {

    private func c(load: Double, mi: Double, hour: Int) -> TrendsSessionOrder.Candidate {
        .init(qualityLoad: load, distanceMi: mi,
              at: Date(timeIntervalSince1970: 1_785_000_000 + Double(hour) * 3600))
    }

    /// The reported bug: a workout day is warm-up + workout + cool-down, the
    /// fetch returns them newest-first, and `entries[0]` opened the cool-down.
    @Test("opens the workout, not the newest row on the day")
    func opensTheWorkout() {
        let day = [
            c(load: 0,  mi: 2, hour: 9),   // cool-down, newest
            c(load: 40, mi: 6, hour: 8),   // the workout
            c(load: 0,  mi: 2, hour: 7),   // warm-up
        ]
        #expect(TrendsSessionOrder.hardestIndex(day) == 1)
    }

    @Test("falls back to distance when nothing carries a quality load")
    func fallsBackToDistance() {
        let day = [
            c(load: 0, mi: 3,  hour: 6),
            c(load: 0, mi: 18, hour: 15),
            c(load: 0, mi: 4,  hour: 19),
        ]
        #expect(TrendsSessionOrder.hardestIndex(day) == 1)
    }

    @Test("a double opens the harder of the two sessions")
    func doubleOpensHarder() {
        let day = [c(load: 55, mi: 8, hour: 17), c(load: 30, mi: 10, hour: 6)]
        #expect(TrendsSessionOrder.hardestIndex(day) == 0)
    }

    /// Deterministic, so the page you land on never jitters between renders.
    @Test("an exact tie breaks to the most recent, every time")
    func tiesAreDeterministic() {
        let day = [c(load: 40, mi: 6, hour: 7), c(load: 40, mi: 6, hour: 18)]
        for _ in 0..<50 { #expect(TrendsSessionOrder.hardestIndex(day) == 1) }
    }

    @Test("a single log opens itself; an empty day opens nothing")
    func edges() {
        #expect(TrendsSessionOrder.hardestIndex([c(load: 0, mi: 5, hour: 8)]) == 0)
        #expect(TrendsSessionOrder.hardestIndex([]) == nil)
    }
}

// MARK: - Windowing and degradation

@Suite("TrendsSignalBuilder.window")
struct TrendsWindowTests {

    private var fourMonths: [TrendsDay] {
        (0..<140).map { i in
            day(String(format: "2026-%02d-%02d", 1 + i / 28, 1 + i % 28), 6, "easy",
                mood: i % 7 == 0 ? "tired" : nil)
        }
    }

    @Test("windows over 120 days bucket weekly")
    func weeklyGrain() {
        let set = TrendsSignalBuilder.build(days: fourMonths, keySessions: [], window: .oneYear)
        #expect(set.grain == .week)
    }

    /// A week with one check-in out of seven must not read as "logged".
    @Test("mood coverage is counted in days, never in buckets")
    func coverageInDays() {
        let set = TrendsSignalBuilder.build(days: fourMonths, keySessions: [], window: .oneYear)
        #expect(set.days.count == 140)
        #expect(set.moodLoggedDays == 20)
        #expect(set.buckets.count < 40)
    }

    @Test("weekly grain announces what it dropped")
    func degradationIsStated() {
        let set = TrendsSignalBuilder.build(days: fourMonths, keySessions: [], window: .oneYear)
        #expect(set.degradationNote.contains("weekly columns"))
        // "1-month", not "30-day": the window pills were unified on months so
        // the row stopped reading as three options and one oddity. The window
        // is still 30 days — only the word changed.
        #expect(set.degradationNote.contains("1-month"))
    }

    @Test("30 days is the default window")
    func defaultIsThirty() {
        #expect(TrendsWindow.thirtyDays.days == 30)
        #expect(TrendsWindow.presets.first == .thirtyDays)
    }
}

// MARK: - The read

@Suite("TrendsSignalRead")
struct TrendsSignalReadTests {

    /// The most important line on the surface: the difference between a tool
    /// that observes and one that manufactures signal.
    @Test("a flat window says nothing is proven yet")
    func noiseGuard() {
        let flat = (0..<40).map {
            day(String(format: "2026-06-%02d", 1 + $0 % 28), 6, "easy", mood: "neutral")
        }
        let read = TrendsSignalRead.compute(
            TrendsSignalBuilder.build(days: flat, keySessions: [], window: .thirtyDays)
        )
        // Asserts the property, not the exact sentence. The copy this test was
        // written against was the recovery note ("Recovery moved N points …
        // Nothing is proven here yet."); d0e5b57 removed the recovery score and
        // rewrote the line for mileage, ending "Nothing is proven here." — same
        // disclosure, one word shorter. The test kept the old wording and was
        // never caught because the bundle stopped compiling in the same commit.
        #expect(read.note.contains("Nothing is proven here"))
    }

    @Test("an absence of body mentions is reported as a finding, not an empty state")
    func absenceIsAFinding() {
        let clean = (0..<40).map {
            day(String(format: "2026-06-%02d", 1 + $0 % 28), 6, "easy", mood: "positive")
        }
        let read = TrendsSignalRead.compute(
            TrendsSignalBuilder.build(days: clean, keySessions: [], window: .thirtyDays)
        )
        #expect(read.findings.contains { $0.text.contains("Absence is a real finding") })
    }
}

// MARK: - Severity

@Suite("TrendsSeverity")
struct TrendsSeverityTests {

    /// Severity renders as opacity derived from the athlete's own word. The
    /// 1–10 score in `InjuryModels` exists for sorting and is never displayed.
    @Test("opacity ramps with the athlete's own severity word")
    func ramp() {
        #expect(TrendsSeverity.opacity("tight") < TrendsSeverity.opacity("sore"))
        #expect(TrendsSeverity.opacity("sore") < TrendsSeverity.opacity("pain"))
        #expect(TrendsSeverity.opacity("pain") < TrendsSeverity.opacity("sharp"))
    }

    @Test("an unknown word sits mid-ramp, neither loud nor invisible")
    func unknownWordIsMidRamp() {
        let unknown = TrendsSeverity.opacity("subtalar grumble")
        #expect(unknown > TrendsSeverity.opacity("tight"))
        #expect(unknown < TrendsSeverity.opacity("sharp"))
    }
}
