import Foundation
import Testing
@testable import RunningLog

// Guards for `TrendsRecoveryFactors.swift` — the 2026-08-05 ledger retool.
// The first two suites encode the two defects the retool exists to fix, so a
// future change that reintroduces either one fails here rather than shipping.

// MARK: - Fixtures

private func day(_ iso: String, _ miles: Double, mood: String? = nil, niggle: String? = nil) -> TrendsDay {
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

/// `n` consecutive days from 2026-06-01, every one a run unless `clearAt`
/// names its index.
private func block(_ n: Int, miles: Double = 8, clearAt: Set<Int> = []) -> [TrendsDay] {
    (0..<n).map { i in
        let date = Date(timeIntervalSince1970: 1_780_272_000 + Double(i) * 86_400)
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.locale = Locale(identifier: "en_US_POSIX")
        return day(f.string(from: date), clearAt.contains(i) ? 0 : miles)
    }
}

private func factor(_ name: String, _ factors: [TrendsRecoveryLedger.Factor]) -> TrendsRecoveryLedger.Factor? {
    factors.first { $0.name == name }
}

// MARK: - Defect 1 · consistency was only ever a penalty

@Suite("TrendsRecoveryFactors.clearDays")
struct RecoveryClearDaysTests {

    /// The retool's whole point. The old "Days on" factor scored 0 / −1 / −3 /
    /// −5 — every value zero or negative — so training consistently could only
    /// ever mark an athlete down. A normal week must not be a standing penalty.
    @Test("a normal week with a clear day scores positive, never negative")
    func normalWeekIsNotPunished() throws {
        // Clear on day 0, then six straight days of running.
        let days = block(7, clearAt: [0])
        let f = try #require(TrendsRecoveryFactors.clearDays(days: days, at: 6))
        #expect(f.points > 0)
        #expect(f.evidence.contains("6 days ago"))
    }

    @Test("a clear day today is credited")
    func clearTodayCredited() throws {
        let days = block(10, clearAt: [9])
        let f = try #require(TrendsRecoveryFactors.clearDays(days: days, at: 9))
        #expect(f.points == 5)
        #expect(f.evidence == "clear today")
    }

    /// Only a genuinely long unbroken stretch costs anything, and it still
    /// only counts — no instruction, no prescription.
    @Test("cost begins only after two unbroken weeks")
    func costOnlyAtTheExtreme() throws {
        let twelve = try #require(TrendsRecoveryFactors.clearDays(days: block(13, clearAt: [0]), at: 12))
        #expect(twelve.points == 0)

        let sixteen = try #require(TrendsRecoveryFactors.clearDays(days: block(17, clearAt: [0]), at: 16))
        #expect(sixteen.points == -3)

        let long = try #require(TrendsRecoveryFactors.clearDays(days: block(30, clearAt: [0]), at: 29))
        #expect(long.points == -5)
        #expect(long.evidence.contains("29 days since one clear"))
    }

    /// A short history with no clear day in it is not a long streak. Scoring
    /// it as one would penalise an athlete for having just installed the app.
    @Test("a short history with no clear day scores nothing and says so")
    func shortHistoryIsNotAStreak() throws {
        let f = try #require(TrendsRecoveryFactors.clearDays(days: block(5), at: 4))
        #expect(f.points == 0)
        #expect(f.evidence.contains("loaded window"))
    }

    /// Across every reachable state the factor must never be worse than the
    /// old one was for ordinary training.
    @Test("no ordinary streak length scores worse than zero")
    func ordinaryStreaksNeverNegative() {
        for streak in 0...13 {
            let days = block(streak + 2, clearAt: [0])
            let f = TrendsRecoveryFactors.clearDays(days: days, at: streak + 1)
            #expect(f.points >= 0, "streak of \(streak) scored \(f.points)")
        }
    }
}

// MARK: - Defect 2 · mood read only today

@Suite("TrendsRecoveryFactors.mood")
struct RecoveryMoodTests {

    private func moodBlock(_ moods: [String?]) -> [TrendsDay] {
        var days = block(moods.count)
        for (i, m) in moods.enumerated() {
            days[i] = day(days[i].date, 8, mood: m)
        }
        return days
    }

    /// The defect: the old factor read `days[i].mood` alone, so on a day with
    /// no log it scored zero and the athlete's actual week was ignored.
    @Test("a mood logged earlier in the week still counts today")
    func readsTheTrailingWeek() {
        let days = moodBlock(["struggling", nil, nil, nil])
        let f = TrendsRecoveryFactors.mood(days: days, at: 3)
        #expect(f.points < 0)
        #expect(f.evidence.contains("STRUGGLING"))
    }

    @Test("nothing logged in seven days scores zero and says so")
    func silentWeekScoresZero() {
        let f = TrendsRecoveryFactors.mood(days: block(7), at: 6)
        #expect(f.points == 0)
        #expect(f.evidence.contains("nothing logged"))
    }

    /// A weighted **mean**, not a sum. Logging more often must not by itself
    /// move the score — it should only make the same reading more confident.
    @Test("logging the same mood more often does not inflate the score")
    func meanNotSum() {
        let once = TrendsRecoveryFactors.mood(days: moodBlock(["positive"]), at: 0)
        let fiveTimes = TrendsRecoveryFactors.mood(
            days: moodBlock(["positive", "positive", "positive", "positive", "positive"]), at: 4
        )
        #expect(once.points == fiveTimes.points)
        #expect(fiveTimes.evidence.contains("5 days in 7"))
    }

    /// Recency-weighted, so today's word leads a week-old one.
    @Test("a recent log outweighs an older one")
    func recencyWins() {
        let improving = TrendsRecoveryFactors.mood(
            days: moodBlock(["struggling", nil, nil, nil, nil, nil, "energized"]), at: 6
        )
        let worsening = TrendsRecoveryFactors.mood(
            days: moodBlock(["energized", nil, nil, nil, nil, nil, "struggling"]), at: 6
        )
        #expect(improving.points > worsening.points)
    }

    /// The window is seven days and stops there.
    @Test("a log older than seven days is out of the window")
    func windowEndsAtSeven() {
        let days = moodBlock(["injured", nil, nil, nil, nil, nil, nil, nil])
        #expect(TrendsRecoveryFactors.mood(days: days, at: 7).points == 0)
    }

    /// The vocabulary is closed. An unknown label is not scored as neutral —
    /// it is not scored at all.
    @Test("a label outside the vocabulary is ignored, not treated as neutral")
    func closedVocabulary() {
        let f = TrendsRecoveryFactors.mood(days: moodBlock(["vibing"]), at: 0)
        #expect(f.points == 0)
        #expect(f.evidence.contains("nothing logged"))
    }

    @Test("the evidence de-duplicates a week of the same word")
    func evidenceDeduplicates() {
        let f = TrendsRecoveryFactors.mood(days: moodBlock(["tired", "tired", "tired"]), at: 2)
        #expect(f.evidence.hasPrefix("TIRED · 3 days in 7"))
    }
}

// MARK: - Defect 3 · the top band was unreachable

@Suite("TrendsRecoveryFactors reachability")
struct RecoveryReachabilityTests {

    /// The shipped factors summed to at most 69 against a `Clear` band
    /// starting at 75, so the best band could never be reached by anyone.
    @Test("every band is attainable within the factors' own range")
    func allBandsAttainable() {
        let range = TrendsRecoveryFactors.theoreticalRange
        #expect(range.high >= 75, "Clear unreachable — high is \(range.high)")
        #expect(range.low <= 44, "Flat unreachable — low is \(range.low)")

        for band in [TrendsRecoveryLedger.Band.flat, .worn, .steady, .clear] {
            let hit = (range.low...range.high).contains { TrendsRecoveryLedger.Band.of($0) == band }
            #expect(hit, "\(band.rawValue) is not reachable")
        }
    }

    /// The clamp is the ledger's, and the factors must not need it to stay in
    /// range — a factor set that only fits by clamping is a factor set whose
    /// arithmetic line will not add up on screen.
    @Test("the range sits inside the ledger's clamp without relying on it")
    func rangeFitsInsideClamp() {
        let range = TrendsRecoveryFactors.theoreticalRange
        #expect(range.low >= 8)
        #expect(range.high <= 96)
    }
}

// MARK: - Carried over unchanged

@Suite("TrendsRecoveryFactors carried-over factors")
struct RecoveryCarriedOverTests {

    /// Three days weighted by decay, not yesterday alone — a single-day term
    /// put a 24-point swing into the score on a calendar boundary.
    @Test("recent load reads three days, and the first day has none")
    func recentLoadWindow() {
        #expect(TrendsRecoveryFactors.recentLoad(days: block(5), at: 0) == nil)
        let f = TrendsRecoveryFactors.recentLoad(days: block(5), at: 4)
        #expect(f?.evidence.contains("over 3 days") == true)
    }

    @Test("nothing in the last three days is credited")
    func fullClearanceCredited() throws {
        let days = block(5, clearAt: [1, 2, 3])
        let f = try #require(TrendsRecoveryFactors.recentLoad(days: days, at: 4))
        #expect(f.points == 6)
    }
}

// MARK: - Recent load · recalibrated 2026-08-06

@Suite("TrendsRecoveryFactors.recentLoad recalibration")
struct RecoveryRecentLoadRecalibrationTests {

    /// The defect the recalibration fixes: the flat 0.42 × miles charge cost
    /// about −3 on ANY normal training day, so a healthy block could never
    /// read better than Worn (the 2026-08-06 backtest measured the top two
    /// bands at 2% of 145 real days). Carrying your usual load is the normal
    /// state of training — it must not be a standing penalty.
    @Test("carrying your usual load scores zero, not a standing charge")
    func usualLoadIsNotFatigue() throws {
        // Eight weeks at a steady 8 mi/day: the carried load IS the baseline.
        let f = try #require(TrendsRecoveryFactors.recentLoad(days: block(60), at: 59))
        #expect(f.points == 0)
        #expect(f.evidence.contains("about your usual"))
    }

    @Test("carrying well over your own usual subtracts")
    func heavyStretchSubtracts() throws {
        var days = block(60)
        for i in 56...58 { days[i] = day(days[i].date, 14) }
        let f = try #require(TrendsRecoveryFactors.recentLoad(days: days, at: 59))
        #expect(f.points == -6)   // 14 vs 8 usual → ratio 1.75
        #expect(f.evidence.contains("well over your usual"))
    }

    @Test("a light stretch against your own usual credits")
    func lightStretchCredits() throws {
        var days = block(60)
        for i in 56...58 { days[i] = day(days[i].date, 3) }
        let f = try #require(TrendsRecoveryFactors.recentLoad(days: days, at: 59))
        #expect(f.points == 4)    // 3 vs 8 usual → ratio 0.375
        #expect(f.evidence.contains("well under your usual"))
    }

    /// A brand-new athlete has no baseline to be relative to. The absolute
    /// fallback keeps the row sane instead of silent.
    @Test("under two weeks of history falls back to the absolute charge")
    func noBaselineFallsBack() throws {
        let f = try #require(TrendsRecoveryFactors.recentLoad(days: block(5), at: 4))
        #expect(f.points == -3)   // 8 mi/day × 0.42, the old arithmetic
        #expect(!f.evidence.contains("usual"))
    }

    /// The evidence still counts and states — miles first, the personal
    /// reading second, no instruction.
    @Test("the evidence names the miles and the personal reading")
    func evidenceCountsAndStates() throws {
        let f = try #require(TrendsRecoveryFactors.recentLoad(days: block(60), at: 59))
        #expect(f.evidence.contains("mi over 3 days"))
        #expect(f.evidence.contains("·"))
    }
}

// MARK: - Carried over unchanged · body & baseline

@Suite("TrendsRecoveryFactors carried-over factors · body & baseline")
struct RecoveryCarriedOverBodyBaselineTests {

    /// Two mentions of one area is the clustering trigger; one is not a
    /// pattern, and neither is ever interpreted.
    @Test("body mentions cluster at two, and quote the area verbatim")
    func bodyClustering() {
        var days = block(20)
        days[18] = day(days[18].date, 8, niggle: "knee")
        let single = TrendsRecoveryFactors.bodyMentions(days: days, at: 19)
        #expect(single.points == -3)
        #expect(single.name == "Knee")

        days[15] = day(days[15].date, 8, niggle: "knee")
        let clustered = TrendsRecoveryFactors.bodyMentions(days: days, at: 19)
        #expect(clustered.points == -6)
        #expect(clustered.evidence.contains("2 in 14 d"))
    }

    @Test("load against baseline stays silent without two weeks of history")
    func baselineNeedsHistory() {
        let f = TrendsRecoveryFactors.loadVsBaseline(days: block(10), at: 9)
        #expect(f.points == 0)
        #expect(f.evidence.contains("not enough history"))
    }

    @Test("a steady block reads as in line with its own average")
    func steadyBlockInLine() {
        let f = TrendsRecoveryFactors.loadVsBaseline(days: block(60), at: 59)
        #expect(f.points == 5)
        #expect(f.evidence.contains("in line"))
    }
}

// MARK: - The assembled ledger

@Suite("TrendsRecoveryFactors.all")
struct RecoveryAssemblyTests {

    @Test("five factors on any day past the first")
    func fiveFactors() {
        #expect(TrendsRecoveryFactors.all(days: block(60), at: 59).count == 5)
    }

    /// Day zero has no yesterday, so recent load is absent rather than zero.
    @Test("the first day carries four, with recent load absent not zeroed")
    func firstDayHasFour() {
        let factors = TrendsRecoveryFactors.all(days: block(60), at: 0)
        #expect(factors.count == 4)
        #expect(factor("Recent load", factors) == nil)
    }

    @Test("a consistent, well-logged block lands in a good band")
    func consistentBlockScoresWell() {
        var days = block(60, clearAt: [56])
        for i in 53..<60 { days[i] = day(days[i].date, days[i].miles, mood: "positive") }
        let factors = TrendsRecoveryFactors.all(days: days, at: 59)
        let total = TrendsRecoveryLedger.base + factors.reduce(0) { $0 + $1.points }
        // Old arithmetic put this same athlete under 60 — "Worn" — on the
        // strength of a "Days on" penalty for training every day.
        #expect(total >= 60, "consistent block scored \(total)")
    }

    /// With both biometric pipelines carrying data, the receipt grows to
    /// seven rows — and the score stays byte-identical to five-factor
    /// arithmetic when neither has data (the previous two tests).
    @Test("seven factors when overnight and sleep both have data")
    func sevenFactorsWithBiometrics() {
        var days = block(60)
        for i in 25..<60 {
            days[i].hrvRmssd = 60 + (i % 2 == 0 ? 4.0 : -4.0)
            days[i].restingHr = 44 + (i % 2 == 0 ? 2.0 : -2.0)
        }
        days[59].sleepQuality = "good"
        let factors = TrendsRecoveryFactors.all(days: days, at: 59)
        #expect(factors.count == 7)
        #expect(factor("Overnight", factors) != nil)
        #expect(factor("Sleep", factors)?.points == 4)
    }
}

// MARK: - The receipt's grouping (2026-08-05)

@Suite("TrendsRecoveryFactors grouping")
struct RecoveryGroupingTests {

    /// The receipt renders WORDS → RUNS → NIGHTS and the arithmetic line
    /// reads off the same array — so the array must arrive in that order.
    @Test("factors arrive words, then runs, then nights")
    func orderedBySource() throws {
        var days = block(60)
        for i in 25..<60 {
            days[i].hrvRmssd = 60 + (i % 2 == 0 ? 4.0 : -4.0)
            days[i].restingHr = 44 + (i % 2 == 0 ? 2.0 : -2.0)
        }
        days[59].sleepQuality = "good"
        let sources = TrendsRecoveryFactors.all(days: days, at: 59).map(\.source)

        let firstRun = try #require(sources.firstIndex(of: .runs))
        let firstNight = try #require(sources.firstIndex(of: .nights))
        #expect(sources.prefix(upTo: firstRun).allSatisfy { $0 == .words })
        #expect(!sources.suffix(from: firstRun).contains(.words))
        #expect(firstNight > firstRun)
    }

    /// Coverage counts channels that actually spoke. An unlogged mood is
    /// missing data; "none in 14 days" on niggles is information.
    @Test("unlogged channels drop out of coverage; quiet channels do not")
    func hasDataSemantics() {
        let factors = TrendsRecoveryFactors.all(days: block(60), at: 59)
        #expect(factor("Mood", factors)?.hasData == false)
        #expect(factor("Body mentions", factors)?.hasData == true)
        #expect(factor("Load", factors)?.hasData == true)
    }
}

// MARK: - Biometrics · Overnight (2026-08-05, SLEEP-HRV-APPLY-NOTES §4)

@Suite("TrendsRecoveryFactors.overnight")
struct RecoveryOvernightTests {

    /// 35 days: indices 0…27 carry baseline nights, 28…34 the trailing-week
    /// nights. Alternating jitter keeps the between-night SD non-zero (HRV
    /// SD ≈ 4 → threshold 2; RHR SD ≈ 2 → threshold 1), so a ±6 HRV / ±4 RHR
    /// shift clears the 0.5 × SD gate decisively.
    private func nights(hrvDelta: Double, rhrDelta: Double,
                        windowNights: Int = 7) -> [TrendsDay] {
        var days = block(35)
        for i in 0..<35 {
            let hrvJitter: Double = i % 2 == 0 ? 4 : -4
            let rhrJitter: Double = i % 2 == 0 ? 2 : -2
            if i < 28 {
                days[i].hrvRmssd = 60 + hrvJitter
                days[i].restingHr = 44 + rhrJitter
            } else if i - 28 < windowNights {
                days[i].hrvRmssd = 60 + hrvDelta + hrvJitter
                days[i].restingHr = 44 + rhrDelta + rhrJitter
            }
        }
        return days
    }

    /// The regression this factor's design exists to prevent: of the nine
    /// HRV × RHR cells, ONLY HRV-down-with-RHR-up may subtract.
    @Test("only HRV down with resting HR up subtracts")
    func onlyOneCellSubtracts() throws {
        let combos: [(hrv: Double, rhr: Double)] = [
            (-6, 4), (-6, 0), (-6, -4),
            (0, 4), (0, 0), (0, -4),
            (6, 4), (6, 0), (6, -4),
        ]
        for c in combos {
            let f = try #require(
                TrendsRecoveryFactors.overnight(days: nights(hrvDelta: c.hrv, rhrDelta: c.rhr), at: 34)
            )
            if c.hrv < 0 && c.rhr > 0 {
                #expect(f.points == -6, "HRV↓ RHR↑ must subtract, got \(f.points)")
            } else {
                #expect(f.points >= 0, "cell (\(c.hrv), \(c.rhr)) scored \(f.points)")
            }
        }
    }

    /// Both-low is usually adaptation and must stay quiet, per the 3×3 table.
    @Test("HRV and resting HR both low reads as adaptation, at zero")
    func bothLowIsAdaptation() throws {
        let f = try #require(
            TrendsRecoveryFactors.overnight(days: nights(hrvDelta: -6, rhrDelta: -4), at: 34)
        )
        #expect(f.points == 0)
        #expect(f.evidence.contains("adaptation"))
    }

    @Test("settled numbers earn a modest credit")
    func settledCredits() throws {
        let f = try #require(
            TrendsRecoveryFactors.overnight(days: nights(hrvDelta: 6, rhrDelta: -4), at: 34)
        )
        #expect(f.points == 3)
    }

    /// Fewer than five valid nights in the trailing week → the factor is
    /// absent, not zero. One extreme night can never flip it into existence.
    @Test("four valid nights is absent, five is present")
    func fiveNightGate() {
        #expect(TrendsRecoveryFactors.overnight(days: nights(hrvDelta: -6, rhrDelta: 4, windowNights: 4), at: 34) == nil)
        #expect(TrendsRecoveryFactors.overnight(days: nights(hrvDelta: -6, rhrDelta: 4, windowNights: 5), at: 34) != nil)
    }

    @Test("no biometrics pipeline means no Overnight row at all")
    func absentWithoutData() {
        #expect(TrendsRecoveryFactors.overnight(days: block(60), at: 59) == nil)
    }
}

// MARK: - Biometrics · Sleep (2026-08-05, SLEEP-HRV-APPLY-NOTES §4)

@Suite("TrendsRecoveryFactors.sleep")
struct RecoverySleepTests {

    /// Tier 1 first: the one-tap self-report decides the factor outright.
    @Test("self-reported quality maps rough −6 / ok 0 / good +4")
    func qualityMapping() throws {
        for (label, pts) in [("rough", -6), ("ok", 0), ("good", 4)] {
            var days = block(30)
            days[29].sleepQuality = label
            let f = try #require(TrendsRecoveryFactors.sleep(days: days, at: 29))
            #expect(f.points == pts, "\(label) scored \(f.points)")
            #expect(f.evidence.contains("logged"))
        }
    }

    /// The self-report wins regardless of what the watch measured.
    @Test("a rough rating subtracts even over a long measured night")
    func qualityBeatsDuration() throws {
        var days = block(30)
        for i in 8..<30 { days[i].sleepTotalMin = 540 }   // long nights on the watch
        days[29].sleepQuality = "rough"
        let f = try #require(TrendsRecoveryFactors.sleep(days: days, at: 29))
        #expect(f.points == -6)
    }

    /// No check-ins and no watch sleep in 21 days → no Sleep row. The receipt
    /// must not carry a permanent "not enough data" line for a pipeline the
    /// athlete never connected.
    @Test("no sleep data of any kind means no Sleep row at all")
    func absentWithoutData() {
        #expect(TrendsRecoveryFactors.sleep(days: block(60), at: 59) == nil)
    }

    /// The Tier-3 fallback is deliberately weak: a 7-day mean against the
    /// athlete's own 3-week average, gated at ±45 minutes.
    @Test("a short-sleep week reads under average; one bad night does not")
    func fallbackUsesWeeklyMean() throws {
        // Consistently ~60 min under the 2-week base → subtracts.
        var short = block(30)
        for i in 9..<23 { short[i].sleepTotalMin = 460 }
        for i in 23..<30 { short[i].sleepTotalMin = 400 }
        let f = try #require(TrendsRecoveryFactors.sleep(days: short, at: 29))
        #expect(f.points == -3)
        #expect(f.evidence.contains("under your average"))

        // One 3-hour night inside an otherwise normal week moves the 7-day
        // mean ~34 min — inside the gate, so it reads in line.
        var oneBad = block(30)
        for i in 9..<30 { oneBad[i].sleepTotalMin = 420 }
        oneBad[29].sleepTotalMin = 180
        let g = try #require(TrendsRecoveryFactors.sleep(days: oneBad, at: 29))
        #expect(g.points == 0)
        #expect(g.evidence.contains("in line"))
    }
}
