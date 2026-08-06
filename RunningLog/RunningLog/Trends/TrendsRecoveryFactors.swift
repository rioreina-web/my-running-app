//
//  TrendsRecoveryFactors.swift
//  RunningLog · Trends
//
//  The recovery ledger's factors, retooled 2026-08-05: the five words-and-runs
//  factors, plus two biometric factors (Overnight, Sleep — per
//  SLEEP-HRV-APPLY-NOTES.md) that appear only when the sleep/HRV pipeline
//  has data.
//
//  `TrendsRecoveryLedger` keeps its shape — base 50, five factors, each
//  carrying the evidence it moved on, clamped 8…96. What changed is the
//  arithmetic inside three of them, for three reasons found by reading the
//  score against real training rather than against its own spec.
//
//  ─────────────────────────────────────────────────────────────────────
//  1 · CONSISTENCY WAS ONLY EVER A PENALTY
//
//  The old fifth factor, "Days on", scored 0 / −1 / −3 / −5 by consecutive
//  days running. Every possible value was zero or negative: an athlete who
//  trained consistently could only ever be marked down for it, and the best
//  available outcome was to not be punished. That is the wrong shape for a
//  metric in a training app — consistency is the point of training.
//
//  It is replaced by **Clear days**, which measures the same underlying fact
//  from the other end: not "how long have you been running" but "how recently
//  did you have a day fully clear". Recent clearance is credited; only a
//  genuinely long unbroken stretch costs anything. Six days on after a Sunday
//  off now reads +2 where it used to read −3, and the extreme case — three
//  weeks without a clear day — still says so.
//
//  ─────────────────────────────────────────────────────────────────────
//  2 · MOOD READ ONLY TODAY
//
//  The old mood factor read `days[i].mood` and nothing else, scoring zero when
//  today carried no log. On a typical block that is most days, so the factor
//  that the ledger's own header calls the most load-bearing of the five was
//  silent most of the time, and the score lurched whenever a log did land.
//
//  It now reads the **trailing 7 days**, weighted toward the recent end, and
//  says how many days it rests on. A single log still moves it; it just no
//  longer vanishes the next morning. Mood is still never stored as a number —
//  the label is the input, the points are derived and disclosed, exactly as
//  before.
//
//  ─────────────────────────────────────────────────────────────────────
//  3 · THE TOP BAND WAS UNREACHABLE
//
//  Old factor maxima summed to 50 + 10 + 5 + 0 + 4 + 0 = **69**, against a
//  `Clear` band that starts at 75. No athlete, however fresh, could ever
//  reach the best band — and the floor was 9, so the whole scale lived in
//  9…69 while presenting as 8…96. The retooled maxima reach 78 and the floor
//  still clamps at 8, so all four bands are now attainable.
//
//  ─────────────────────────────────────────────────────────────────────
//  Factor 3 (body mentions) is carried over unchanged — it was right. Factor
//  2 (recent load) was carried over on 08-05 and then recalibrated on 08-06,
//  when the backtest showed its flat per-mile charge made a normal training
//  week read Worn forever — see its own doc comment. All factors live here so
//  the arithmetic has exactly one home.
//

import Foundation

enum TrendsRecoveryFactors {

    typealias Factor = TrendsRecoveryLedger.Factor

    // MARK: - Tunables, in one place

    /// Points per mood label. Unchanged from the shipped table apart from
    /// `energized`, lifted 10 → 12 so the top band is reachable.
    static let moodPoints: [String: Int] = [
        "energized": 12, "positive": 7, "neutral": 0,
        "tired": -8, "struggling": -14, "injured": -18,
    ]

    /// Days of mood history the factor reads, including today.
    static let moodWindowDays = 7

    /// Recency weights across that window, newest first. A log today counts
    /// for roughly three times one a week ago — recent enough to move the
    /// score, old enough not to be forgotten overnight.
    static let moodWeights: [Double] = [1.0, 0.9, 0.75, 0.6, 0.5, 0.4, 0.3]

    // MARK: - All factors

    /// The ledger's factors for day `i`, in display order. The two biometric
    /// factors (Overnight, Sleep — added 2026-08-05 per
    /// `SLEEP-HRV-APPLY-NOTES.md`) are appended only when their data exists;
    /// an athlete with no watch pipeline sees exactly the five-factor receipt
    /// they always did.
    static func all(days: [TrendsDay], at i: Int) -> [Factor] {
        // Ordered words → runs → nights, matching the receipt's grouped
        // rendering (and the arithmetic line, which reads off this order).
        // The athlete's words lead; the watch corroborates.
        var out: [Factor] = [mood(days: days, at: i)]
        out.append(bodyMentions(days: days, at: i))
        if let sleepRow = sleep(days: days, at: i) { out.append(sleepRow) }
        if let load = recentLoad(days: days, at: i) { out.append(load) }
        out.append(loadVsBaseline(days: days, at: i))
        out.append(clearDays(days: days, at: i))
        if let overnightRow = overnight(days: days, at: i) { out.append(overnightRow) }
        return out
    }

    // MARK: - 1 · Mood, over the trailing week

    static func mood(days: [TrendsDay], at i: Int) -> Factor {
        let start = max(0, i - (moodWindowDays - 1))
        let window = Array(days[start...i]).reversed()   // newest first

        var weighted = 0.0
        var weightUsed = 0.0
        var logged: [String] = []

        for (offset, day) in window.enumerated() {
            guard offset < moodWeights.count else { break }
            guard let label = day.mood?.lowercased(), !label.isEmpty else { continue }
            guard let points = moodPoints[label] else { continue }
            let w = moodWeights[offset]
            weighted += Double(points) * w
            weightUsed += w
            logged.append(label)
        }

        guard weightUsed > 0 else {
            return Factor(
                name: "Mood",
                evidence: "nothing logged in \(moodWindowDays) days",
                points: 0,
                source: .words,
                hasData: false
            )
        }

        // The weighted mean of the labels' points — not their sum. Logging
        // more often must not by itself move the score; it should only make
        // the same reading more confident.
        let mean = weighted / weightUsed
        let points = Int(mean.rounded())

        // Evidence names what it read, most recent first, de-duplicated so a
        // week of "tired" reads as one word rather than five.
        var seen = Set<String>()
        let words = logged.filter { seen.insert($0).inserted }.prefix(3)
        let dayWord = logged.count == 1 ? "day" : "days"
        return Factor(
            name: "Mood",
            evidence: "\(words.joined(separator: " · ").uppercased()) · \(logged.count) \(dayWord) in 7",
            points: points,
            source: .words
        )
    }

    // MARK: - 2 · The work you're still carrying (recalibrated 2026-08-06)

    /// The last three days, decayed. Not yesterday alone: a single-day term
    /// flips between +5 and −7 overnight, and the cost of Sunday's long run
    /// does not vanish at midnight on Monday.
    ///
    /// **Recalibrated 2026-08-06** against 202 days of production history
    /// (`outputs/recovery-score-backtest.py`, re-run after the retool). The
    /// old flat charge — 0.42 × the decayed daily equivalent — cost about −3
    /// on any normal training day, so a healthy, well-managed block could
    /// never read better than Worn: across seven real months the top two
    /// bands occurred on 2% of days and Clear on none. Carrying your usual
    /// load is the normal state of an athlete in training; it is not fresh
    /// fatigue, and it now scores 0.
    ///
    /// The carried load is read against the athlete's OWN 8-week average
    /// daily load — the same window the Load factor uses, never a population
    /// number. Only carrying meaningfully more than your own usual subtracts;
    /// carrying meaningfully less credits. With under two weeks of baseline
    /// the old absolute charge remains as the fallback, so a brand-new
    /// athlete still gets a sane row.
    static func recentLoad(days: [TrendsDay], at i: Int) -> Factor? {
        guard i > 0 else { return nil }
        let weights: [Double] = [1.0, 0.6, 0.3]
        var carried = 0.0
        var totalWeight = 0.0
        var recentMiles: [Double] = []

        for (offset, w) in weights.enumerated() {
            let idx = i - 1 - offset
            guard idx >= 0 else { break }
            carried += days[idx].miles * w
            totalWeight += w
            recentMiles.append(days[idx].miles)
        }

        let dailyEquivalent = totalWeight > 0 ? carried / totalWeight : 0
        let restDays = recentMiles.filter { $0 <= 0 }.count

        if dailyEquivalent <= 0 {
            return Factor(
                name: "Recent load",
                evidence: "nothing in the last \(recentMiles.count) days",
                points: 6
            )
        }

        let sum = recentMiles.reduce(0, +)
        let milesPart = String(format: "%.0f mi over %d days", sum, recentMiles.count)
            + (restDays > 0 ? " · \(restDays) clear" : "")

        // The athlete's own average daily load over the 8-week window ending
        // a week ago (56 → 7 days back), zero days included.
        let baselineDays = days[max(0, i - 55)..<max(0, i - 6)]
        let baselineDaily = baselineDays.count >= 14
            ? baselineDays.reduce(0) { $0 + $1.miles } / Double(baselineDays.count)
            : 0

        guard baselineDaily > 0.5 else {
            // Not enough history for a personal read — the absolute fallback.
            let cost = -min(8, Int((dailyEquivalent * 0.42).rounded()))
            return Factor(name: "Recent load", evidence: milesPart, points: cost)
        }

        let ratio = dailyEquivalent / baselineDaily
        let (points, reading): (Int, String) = switch ratio {
        case ...0.5: (4, "well under your usual")
        case ...0.85: (2, "lighter than your usual")
        case ...1.25: (0, "about your usual")
        case ...1.6: (-4, "heavier than your usual")
        case ...2.0: (-6, "well over your usual")
        default: (-8, "far over your usual")
        }
        return Factor(name: "Recent load", evidence: milesPart + " · " + reading, points: points)
    }

    // MARK: - 3 · Body mentions (unchanged)

    /// 14-day lookback on the same area. Two mentions of one area is the
    /// clustering trigger; one is not a pattern.
    static func bodyMentions(days: [TrendsDay], at i: Int) -> Factor {
        let lookback = days[max(0, i - 13)...i].filter { !$0.niggles.isEmpty }
        guard !lookback.isEmpty else {
            return Factor(name: "Body mentions", evidence: "none in 14 days", points: 0, source: .words)
        }

        var counts: [String: Int] = [:]
        for d in lookback {
            for n in d.niggles { counts[n.area.lowercased(), default: 0] += 1 }
        }
        let top = counts.max { a, b in a.value == b.value ? a.key > b.key : a.value < b.value }
        let area = top?.key ?? "body"
        let n = top?.value ?? 1
        let lastISO = lookback.last?.date ?? days[i].date
        let gap = dayGap(from: lastISO, to: days[i].date)

        return Factor(
            name: area.prefix(1).uppercased() + area.dropFirst(),
            evidence: (gap == 0 ? "mentioned today" : "quiet \(gap) d") + " · \(n) in 14 d",
            points: n >= 2 ? -6 : -3,
            source: .words
        )
    }

    // MARK: - 4 · Load against the athlete's own average (unchanged shape)

    /// Not ACWR. The last seven days against the athlete's own 8-week average.
    static func loadVsBaseline(days: [TrendsDay], at i: Int) -> Factor {
        let last7 = days[max(0, i - 6)...i].reduce(0) { $0 + $1.miles }
        let baselineDays = days[max(0, i - 55)..<max(0, i - 6)]
        let weeksOfBaseline = Double(baselineDays.count) / 7.0

        guard weeksOfBaseline >= 2 else {
            return Factor(name: "Load", evidence: "not enough history yet", points: 0, hasData: false)
        }
        let baseline = baselineDays.reduce(0) { $0 + $1.miles } / weeksOfBaseline
        guard baseline > 0 else {
            return Factor(name: "Load", evidence: "no baseline mileage", points: 0, hasData: false)
        }

        let ratio = last7 / baseline
        let pct = Int((abs(ratio - 1) * 100).rounded())
        let (points, evidence): (Int, String) = switch ratio {
        case 1.25...: (-5, "\(pct)% over your 8-wk average")
        case 1.10..<1.25: (-2, "\(pct)% over your 8-wk average")
        case ..<0.85: (3, "\(pct)% under your 8-wk average")
        default: (5, "in line with your 8-wk average")
        }
        return Factor(name: "Load", evidence: evidence, points: points)
    }

    // MARK: - 5 · Clear days (retooled — was "Days on")

    /// How recently the athlete had a day fully clear.
    ///
    /// The replacement for "Days on", and the reason this file exists. The old
    /// factor could only subtract, so a consistent block was a standing
    /// penalty with no upside. This one credits recent clearance and charges
    /// only a genuinely long unbroken stretch, which is the fact that actually
    /// carries information.
    ///
    /// It still only counts and states. No instruction, no prescription — the
    /// evidence line says how long it has been and stops there.
    static func clearDays(days: [TrendsDay], at i: Int) -> Factor {
        // Days since the most recent zero-mile day. 0 means today is clear.
        var since = 0
        var k = i
        while k >= 0, days[k].miles > 0 {
            since += 1
            k -= 1
        }
        let foundClearDay = k >= 0

        // Never a clear day in the loaded history is not the same as a
        // 40-day streak — it is a short history. Say so and score nothing.
        guard foundClearDay || since >= 14 else {
            return Factor(
                name: "Clear days",
                evidence: "no clear day in the loaded window",
                points: 0
            )
        }

        let (points, evidence): (Int, String) = switch since {
        case 0:
            (5, "clear today")
        case 1...3:
            (5, "clear \(since) \(since == 1 ? "day" : "days") ago")
        case 4...7:
            (2, "clear \(since) days ago")
        case 8...13:
            (0, "\(since) days since one clear")
        case 14...20:
            (-3, "\(since) days since one clear")
        default:
            (-5, "\(since) days since one clear")
        }
        return Factor(name: "Clear days", evidence: evidence, points: points)
    }

    // MARK: - 6 · Overnight (HRV paired with resting HR) — 2026-08-05

    /// `nil` == factor not shown (no biometrics pipeline, or fewer than 5
    /// valid nights in the trailing 7, or under 2 weeks of baseline). A lone
    /// HRV number is uninterpretable (recovery-trend-v2 §2c, §7.2), so HRV is
    /// read ONLY paired with resting HR, both weekly-aggregated against the
    /// athlete's own 28-day baseline, thresholded at 0.5 × their own
    /// between-night SD. Only ONE of the nine HRV × RHR cells subtracts —
    /// HRV down with resting HR up. Both-low is usually adaptation and stays
    /// quiet; a single extreme night can never flip the factor.
    ///
    /// Known confound, by design kept gentle at −6: cycle phase moves both
    /// numbers for roughly half of every cycle (v2 §3a, §8.3). Gating behind
    /// cycle capture — or lowering to −4 — is the open call in the design doc.
    static func overnight(days: [TrendsDay], at i: Int) -> Factor? {
        let window = Array(days[max(0, i - 6)...i])
        let baseWin = Array(days[max(0, i - 27)...max(0, i - 7)])   // own 28-day baseline

        let hrvNow = window.compactMap { $0.hrvRmssd }
        let rhrNow = window.compactMap { $0.restingHr }
        guard hrvNow.count >= 5, rhrNow.count >= 5 else { return nil }   // ≥5 valid nights

        let hrvBase = baseWin.compactMap { $0.hrvRmssd }
        let rhrBase = baseWin.compactMap { $0.restingHr }
        guard hrvBase.count >= 14, rhrBase.count >= 14 else { return nil } // ≥2 wks baseline

        // Direction, thresholded at 0.5 × the athlete's OWN between-night SD.
        func dir(_ now: [Double], _ base: [Double]) -> Int {
            let mNow = now.reduce(0, +) / Double(now.count)
            let mBase = base.reduce(0, +) / Double(base.count)
            let sd = stdev(base)
            guard sd > 0 else { return 0 }
            let delta = mNow - mBase
            if delta >= 0.5 * sd { return 1 }      // up
            if delta <= -0.5 * sd { return -1 }    // down
            return 0                                // flat
        }

        let h = dir(hrvNow, hrvBase)   // HRV direction
        let r = dir(rhrNow, rhrBase)   // resting-HR direction

        // The 3×3 table (v2 §2c), compressed to points.
        switch (h, r) {
        case (-1, 1):   // HRV down, RHR up — the ONE interpretable cell
            return Factor(name: "Overnight", evidence: "7-day HRV down, resting HR up", points: -6, source: .nights)
        case (-1, -1):  // both low — usually adaptation, stay quiet
            return Factor(name: "Overnight", evidence: "HRV & resting HR both low · usually adaptation", points: 0, source: .nights)
        case (1, -1):   // HRV up, RHR down — settled
            return Factor(name: "Overnight", evidence: "overnight numbers settled", points: 3, source: .nights)
        default:
            return Factor(name: "Overnight", evidence: "overnight numbers inside your usual range", points: 0, source: .nights)
        }
    }

    // MARK: - 7 · Sleep — 2026-08-05

    /// Self-reported quality preferred (Tier 1 — the strongest single
    /// prospective signal in the runner injury literature); total sleep time
    /// is a deliberately weak Tier-3 fallback. Never sleep stages, scores, or
    /// efficiency (v2 §7.4).
    ///
    /// `nil` == factor not shown: an athlete with no check-ins and no watch
    /// sleep in the trailing 21 days has no Sleep row at all — the receipt
    /// must not carry a permanent "not enough data" line for a pipeline the
    /// athlete never connected. Once data exists but is thin, the factor
    /// shows and says so honestly at 0 points.
    static func sleep(days: [TrendsDay], at i: Int) -> Factor? {
        let day = days[i]

        // Preferred: self-reported quality for the night (Tier 1).
        if let q = day.sleepQuality?.lowercased() {
            switch q {
            case "good":  return Factor(name: "Sleep", evidence: "good · logged", points: 4, source: .words)
            case "rough": return Factor(name: "Sleep", evidence: "rough · logged", points: -6, source: .words)
            default:      return Factor(name: "Sleep", evidence: "ok · logged", points: 0, source: .words)
            }
        }

        // No sleep data of any kind in the trailing 21 days → no factor.
        let recent = Array(days[max(0, i - 20)...i])
        guard recent.contains(where: { $0.sleepQuality != nil || $0.sleepTotalMin != nil }) else {
            return nil
        }

        // Fallback: total sleep time vs the athlete's own 3-week average. Weak
        // on purpose — single-night TST error is ±83…160 min, so use a 7-day
        // mean and a wide gate, and never react to one night.
        let window = Array(days[max(0, i - 6)...i]).compactMap { $0.sleepTotalMin }
        let base = Array(days[max(0, i - 20)...max(0, i - 7)]).compactMap { $0.sleepTotalMin }
        guard window.count >= 5, base.count >= 7 else {
            return Factor(name: "Sleep", evidence: "not enough sleep data yet", points: 0, source: .words, hasData: false)
        }
        let mNow = Double(window.reduce(0, +)) / Double(window.count)
        let mBase = Double(base.reduce(0, +)) / Double(base.count)
        let delta = mNow - mBase   // minutes
        if delta <= -45 {
            return Factor(name: "Sleep", evidence: "sleeping ~\(Int(-delta)) min under your average", points: -3, source: .words)
        } else if delta >= 45 {
            return Factor(name: "Sleep", evidence: "sleeping above your average", points: 2, source: .words)
        }
        return Factor(name: "Sleep", evidence: "sleep in line with your average", points: 0, source: .words)
    }

    /// Population SD (n), matching the between-night SD used for the SWC
    /// threshold in `overnight`.
    static func stdev(_ xs: [Double]) -> Double {
        guard xs.count > 1 else { return 0 }
        let m = xs.reduce(0, +) / Double(xs.count)
        let v = xs.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(xs.count)
        return v.squareRoot()
    }

    // MARK: - Reachability

    /// The best and worst totals the factors can produce, including the base.
    /// Exposed so a test can assert every band stays attainable — the shipped
    /// scale had a `Clear` band that no athlete could ever reach.
    ///
    /// Words + runs only (the five always-on factors): 50 + 12 + 6 + 0 + 5 + 5
    /// = 78 best, 8 worst after the clamp. With the two biometric factors
    /// present the raw range widens to 85 / −4, and the ledger's 8…96 clamp
    /// still holds both ends.
    static var theoreticalRange: (low: Int, high: Int) {
        let best = TrendsRecoveryLedger.base + 12 + 6 + 0 + 5 + 5 + 3 + 4   // = 85
        let rawWorst = TrendsRecoveryLedger.base - 18 - 8 - 6 - 5 - 5 - 6 - 6
        let worst = max(8, rawWorst)                                        // clamped = 8
        return (worst, best)
    }

    // MARK: - Dates

    static func dayGap(from: String, to: String) -> Int {
        guard let a = isoDay.date(from: from), let b = isoDay.date(from: to) else { return 0 }
        return max(0, Int((b.timeIntervalSince(a) / 86_400).rounded()))
    }

    private static let isoDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}
