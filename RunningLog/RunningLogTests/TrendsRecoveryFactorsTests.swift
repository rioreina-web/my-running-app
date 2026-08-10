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
        // `block(streak + 2, clearAt: [0])` read at `streak + 1` gives the
        // factor `since == streak + 1`, so the loop bound runs one ahead of
        // the ladder's bands. 12 is the last streak that stays inside the
        // non-negative 8...13 band; 13 lands on 14, which the ladder scores
        // −3 deliberately. The old 0...13 bound crossed that line by one.
        for streak in 0...12 {
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

    /// The 2026-08-06 asymmetry. A big session can leave an athlete elated in
    /// the moment yet needing days to recover, so mood's UPSIDE is capped small
    /// (energized +4, matching a good sleep — no larger) while the DOWNSIDE
    /// keeps full weight (a dragging self-report is the evidenced early signal).
    /// Reverting energized to +12 / positive to +7 would let a good feeling
    /// lift the score out of a load-driven hole — this pins that shut.
    @Test("positive mood upside is capped; negative keeps full weight")
    func moodUpsideIsCapped() {
        #expect(TrendsRecoveryFactors.mood(days: moodBlock(["energized"]), at: 0).points == 4)
        #expect(TrendsRecoveryFactors.mood(days: moodBlock(["positive"]), at: 0).points == 2)
        // Downside unchanged — feeling wrecked is still a real signal.
        #expect(TrendsRecoveryFactors.mood(days: moodBlock(["struggling"]), at: 0).points == -14)
        #expect(TrendsRecoveryFactors.mood(days: moodBlock(["injured"]), at: 0).points == -18)
        // And the upside is no bigger than a good night's sleep.
        #expect(TrendsRecoveryFactors.mood(days: moodBlock(["energized"]), at: 0).points <= 4)
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

    /// Four past the warm-up gate, not the old five: the demand swap
    /// (2026-08-06) replaced the two overlapping load ratios — `Recent load`
    /// and `Load` — with the single `Recovery need` term. One row left the
    /// receipt; no signal did.
    @Test("four factors on any day past the warm-up gate")
    func fourFactors() {
        let factors = TrendsRecoveryFactors.all(days: block(60), at: 59)
        #expect(factors.count == 4)
        #expect(factor("Recovery need", factors) != nil)
    }

    /// Below the gate the need index is untrustworthy, so the previous load
    /// pair still carries those windows — and the receipt keeps its old shape.
    @Test("below the warm-up gate the old load pair still ships")
    func belowGateKeepsOldPair() {
        let factors = TrendsRecoveryFactors.all(days: block(30), at: 29)
        #expect(factors.count == 5)
        #expect(factor("Load", factors) != nil)
        #expect(factor("Recent load", factors) != nil)
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

    /// The rule the mood cap exists to enforce (2026-08-06): a big recent
    /// training load with an upbeat mood must NOT read as a good band. A hard
    /// session can feel great in the moment and still need days to recover —
    /// so a positive feeling cannot cancel the load-driven recovery need.
    @Test("feeling good cannot lift a big-load day into a good band")
    func feelingGoodCannotCancelLoad() {
        var days = block(60, clearAt: [56])
        for i in 57..<60 { days[i] = day(days[i].date, 20) }              // a heavy 3-day block
        for i in 53..<60 { days[i] = day(days[i].date, days[i].miles, mood: "energized") }
        let factors = TrendsRecoveryFactors.all(days: days, at: 59)
        let total = TrendsRecoveryLedger.base + factors.reduce(0) { $0 + $1.points }
        #expect(total < 60, "big load + energized scored \(total) — a good feeling cancelled the load")
    }

    /// With both biometric pipelines carrying data, the receipt grows to
    /// seven rows — and the score stays byte-identical to five-factor
    /// arithmetic when neither has data (the previous two tests).
    @Test("six factors when overnight and sleep both have data")
    func sixFactorsWithBiometrics() {
        var days = block(60)
        for i in 25..<60 {
            days[i].hrvRmssd = 60 + (i % 2 == 0 ? 4.0 : -4.0)
            days[i].restingHr = 44 + (i % 2 == 0 ? 2.0 : -2.0)
        }
        days[59].sleepQuality = "good"
        let factors = TrendsRecoveryFactors.all(days: days, at: 59)
        // Six, not the old seven — see `fourFactors`: the demand swap folded
        // two load rows into one.
        #expect(factors.count == 6)
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
        #expect(factor("Recovery need", factors)?.hasData == true)
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

    /// The median makes outlier rejection structural rather than a side effect
    /// of a wide gate. A mean would move ~34 min on this input; the median does
    /// not move at all, so the result no longer depends on the gate being wide
    /// enough to hide it.
    @Test("one freak night cannot move the median at all")
    func medianIgnoresASingleNight() throws {
        var days = block(30)
        for i in 9..<30 { days[i].sleepTotalMin = 420 }
        days[29].sleepTotalMin = 90            // 1.5 h — far worse than the old test's 3 h
        let f = try #require(TrendsRecoveryFactors.sleep(days: days, at: 29))
        #expect(f.points == 0)
        #expect(f.evidence.contains("in line"))
    }

    /// The threshold is 0.5 × the athlete's own between-night SD, so the same
    /// 30-minute shift is signal for a consistent sleeper and noise for a
    /// variable one. Under the old fixed ±45 both read "in line".
    @Test("the gate scales to the athlete's own variability")
    func thresholdScalesWithSD() throws {
        // Metronome sleeper: base alternates 415/425 (SD 5 → threshold floors
        // at 20). A 30-minute drop is plainly unlike them, and now reads so.
        var steady = block(30)
        for i in 9..<23 { steady[i].sleepTotalMin = i.isMultiple(of: 2) ? 415 : 425 }
        for i in 23..<30 { steady[i].sleepTotalMin = 390 }
        let tight = try #require(TrendsRecoveryFactors.sleep(days: steady, at: 29))
        #expect(tight.points == -3, "a metronome sleeper's 30 min drop should register")

        // Variable sleeper: base swings 300…540 (SD ≈ 85 → threshold caps at
        // 60). The same 30-minute drop is inside their ordinary scatter.
        var swingy = block(30)
        let pattern = [300.0, 540, 360, 480, 300, 540, 420]
        for i in 9..<23 { swingy[i].sleepTotalMin = Int(pattern[(i - 9) % 7]) }
        for i in 23..<30 { swingy[i].sleepTotalMin = 390 }
        let loose = try #require(TrendsRecoveryFactors.sleep(days: swingy, at: 29))
        #expect(loose.points == 0, "the same drop inside a variable sleeper's scatter is not signal")
    }

    /// Adequacy is surfaced as measurement and scored at zero — the deviation
    /// model cannot see a chronic deficit, because the deficit IS the baseline.
    @Test("chronic short sleep is stated in the evidence and costs nothing")
    func chronicShortSleepIsSurfacedNotCharged() throws {
        var short = block(30)
        for i in 9..<30 { short[i].sleepTotalMin = 355 }   // ~5h55 every night
        let f = try #require(TrendsRecoveryFactors.sleep(days: short, at: 29))
        #expect(f.points == 0, "a flat baseline has no deviation to charge for")
        #expect(f.evidence.contains("in line"))
        #expect(f.evidence.contains("watch median 5h55"))
    }

    /// …and stays quiet once the athlete is over the seven-hour line, so the
    /// note never becomes permanent furniture on the receipt.
    @Test("no adequacy note above seven hours")
    func noNoteWhenSleepIsAdequate() throws {
        var fine = block(30)
        for i in 9..<30 { fine[i].sleepTotalMin = 450 }    // 7h30
        let f = try #require(TrendsRecoveryFactors.sleep(days: fine, at: 29))
        #expect(!f.evidence.contains("watch median"))
    }
}

// MARK: - Defect 3 · a degraded read announced itself as a full one

/// Until 2026-08-07 the receipt's coverage line said "full read" whenever any
/// nights factor existed, and the band gauge drew `Clear` as open territory
/// regardless. On the production athlete both were false at once: HRV was
/// empty (0 of 30 nights) so Overnight ran its resting-HR-only branch, and
/// `daily_checkins` had never held a row so Sleep only ever ran its Tier-3
/// duration fallback. The score was honest; the frame around it was not.
@Suite("TrendsRecoveryLedger degradation + ceiling")
struct RecoveryDegradationTests {

    /// 30 days of resting HR and sleep duration, no HRV, no nightly rating —
    /// the exact shape of the shipped Apple Health pipeline.
    private func rhrOnlyBlock() -> [TrendsDay] {
        var days = block(30)
        for i in days.indices {
            days[i].restingHr = 50
            days[i].sleepTotalMin = 420
        }
        return days
    }

    @Test("resting HR without HRV is marked degraded, not silently scored")
    func overnightDegradesLoudly() throws {
        let days = rhrOnlyBlock()
        let f = try #require(TrendsRecoveryFactors.overnight(days: days, at: 29))
        #expect(f.degraded != nil, "RHR-only branch must name the missing HRV")
        #expect(f.bestCase == 2, "one-axis ceiling is +2, not the two-axis +3")
    }

    @Test("both axes present scores a full read with no degradation")
    func overnightFullReadIsClean() throws {
        var days = rhrOnlyBlock()
        for i in days.indices { days[i].hrvRmssd = 60 }
        let f = try #require(TrendsRecoveryFactors.overnight(days: days, at: 29))
        #expect(f.degraded == nil)
        #expect(f.bestCase == 3)
    }

    @Test("sleep duration without a nightly rating is marked degraded")
    func sleepFallbackDegradesLoudly() throws {
        let f = try #require(TrendsRecoveryFactors.sleep(days: rhrOnlyBlock(), at: 29))
        #expect(f.degraded != nil, "TST fallback must say the rating is missing")
        #expect(f.bestCase == 2, "fallback tops out at +2, not the Tier-1 +4")
    }

    @Test("a logged rating takes the Tier-1 branch and is not degraded")
    func sleepTierOneIsClean() throws {
        var days = rhrOnlyBlock()
        days[29].sleepQuality = "good"
        let f = try #require(TrendsRecoveryFactors.sleep(days: days, at: 29))
        #expect(f.points == 4)
        #expect(f.degraded == nil)
        #expect(f.bestCase == 4)
    }

    /// The regression that motivated all of this: with both night channels
    /// degraded the roof lands at 74 and `Clear` starts at 75, so the best
    /// band is arithmetically out of reach and the gauge must say so.
    @Test("no HRV and no sleep rating puts Clear out of reach")
    func clearIsUnreachableOnDegradedInputs() {
        let ledger = TrendsRecoveryLedger.ledger(days: rhrOnlyBlock(), at: 29)
        #expect(ledger.ceiling < 75, "ceiling is \(ledger.ceiling), expected under 75")
        #expect(ledger.unreachableBands.contains(.clear))
        #expect(!ledger.degradations.isEmpty)
    }

    /// …and with every channel live it must come back, or the ceiling logic
    /// has replaced one unreachable band with a permanent one.
    @Test("full inputs restore Clear")
    func clearReturnsOnFullInputs() {
        var days = rhrOnlyBlock()
        for i in days.indices {
            days[i].hrvRmssd = 60
            days[i].sleepQuality = "good"
        }
        let ledger = TrendsRecoveryLedger.ledger(days: days, at: 29)
        #expect(ledger.ceiling >= 75, "ceiling is \(ledger.ceiling), expected 75+")
        #expect(ledger.unreachableBands.isEmpty)
        #expect(ledger.degradations.isEmpty)
    }

    /// The ceiling is a bound, so no day may ever score above it.
    @Test("the score never exceeds its own ceiling")
    func ceilingBoundsTheScore() {
        let days = rhrOnlyBlock()
        for i in days.indices {
            let ledger = TrendsRecoveryLedger.ledger(days: days, at: i)
            #expect(ledger.total <= ledger.ceiling,
                    "day \(i) scored \(ledger.total) over a ceiling of \(ledger.ceiling)")
        }
    }

    /// An athlete with no watch at all keeps the old two-group receipt: no
    /// nights factors, so nothing to degrade and no cap to draw.
    @Test("no night pipeline degrades nothing")
    func noNightsNoDegradation() {
        let ledger = TrendsRecoveryLedger.ledger(days: block(30), at: 29)
        #expect(ledger.degradations.isEmpty)
    }
}
