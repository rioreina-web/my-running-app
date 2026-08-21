//
//  TrendsRecoveryRead.swift
//  RunningLog · Trends
//
//  The recovery read, as TWO axes and a state — replacing the single summed
//  0–100 that shipped from 2026-08-05 to 2026-08-19.
//
//  ── What was wrong with one number ────────────────────────────────────────
//
//  `TrendsRecoveryLedger.total` adds demand (how big a hole training dug) to
//  supply (how well the athlete is absorbing it) and reports the sum. Three
//  things follow from that, and all three were visible on the shipped screen:
//
//  1 · THE NUMBER IS AMBIGUOUS. A 39 is "huge block, feeling fine" or "barely
//      running, feeling awful" — opposite situations, same number, opposite
//      things worth doing. The model already knows they are different: that is
//      exactly why `Quadrant` exists. It was computed on every ledger and then
//      never rendered on the Trends tab. The most useful output of the whole
//      model was dead code.
//
//  2 · THE SCALE IS FICTION. Base 50, factors topping out at +27 and bottoming
//      at −60 (clamped to 8). The real range is 8…77 drawn on a 0…100 gauge
//      with bands at 45/60/75. "39" is not 39% of anything — it is 50 minus 11.
//
//  3 · MISSING CHANNELS LOWER THE ROOF. Because absent channels remove POSITIVE
//      headroom from a sum, no-HRV + no-sleep-rating caps the score at 74
//      against a Clear band starting at 75 — arithmetically unreachable. The
//      shipped card had to apologise for this in four clauses of 9pt uppercase
//      ("CLEAR NEEDS 75 · TODAY'S INPUTS TOP OUT AT 74 · …"). The ceiling was
//      never a copy problem. It was the sum leaking.
//
//  ── What this does instead ────────────────────────────────────────────────
//
//  Report the two axes natively and let the STATE be the headline.
//
//    LOAD  — the Banister normalised difference already computed in
//            `TrendsRecoveryDemand`, in real units the athlete can read:
//            "+18% over your usual". No invented scale; nothing to calibrate.
//
//    BODY  — today's supply channels ranked as a PERCENTILE against this
//            athlete's own trailing history. 50 is their own median day.
//            Both ends are reachable BY CONSTRUCTION, so no band can ever be
//            dead territory and a missing channel cannot lower a roof — it
//            narrows the evidence, which is reported as confidence instead.
//
//    STATE — `TrendsRecoveryLedger.Quadrant`, finally rendered. Demand x
//            supply is the thing the athlete actually wants to know, and the
//            sentences for it were already written and already checked against
//            the copy ban list.
//
//  ── What deliberately did NOT change ──────────────────────────────────────
//
//  `TrendsRecoveryFactors.all()` is untouched, and stays the one home for the
//  arithmetic. Every per-factor point value, threshold and asymmetry survives
//  exactly as calibrated on 2026-08-06. This file only changes how those
//  factors are COMPOSED — sum → two axes — which is why the factor tests still
//  pass and why the ranking below is scale-free: percentile-ranking a sum
//  against its own history cancels whatever units the sum was in.
//
//  `TrendsRecoveryLedger` also survives, unchanged, for the surfaces that read
//  it (`TrendsReadModels`, and the DEBUG-only `TrendsV2View` lanes). It is no
//  longer what the Trends tab shows.
//

import Foundation

// MARK: - Standing

/// Where today's body signals sit against the athlete's OWN trailing history.
///
/// The band WORDS are carried over from `TrendsRecoveryLedger.Band` on purpose
/// — the athlete already reads Flat / Worn / Steady / Clear, and the change
/// here is what they mean, not what they are called. The bounds are
/// percentiles, so every band is occupied by roughly its own share of the
/// athlete's own days and none of them can be unreachable.
nonisolated enum TrendsRecoveryStanding: String, CaseIterable {
    case flat = "Flat"
    case worn = "Worn"
    case steady = "Steady"
    case clear = "Clear"

    /// Percentile floor. Chosen so the middle two bands carry the bulk of
    /// ordinary days and the outer two mean something when they appear:
    /// roughly a fifth of days read Flat, a quarter Worn, three-tenths
    /// Steady, a quarter Clear.
    var lowerPercentile: Int {
        switch self {
        case .flat: 0
        case .worn: 20
        case .steady: 45
        case .clear: 75
        }
    }

    var upperPercentile: Int {
        switch self {
        case .flat: 20
        case .worn: 45
        case .steady: 75
        case .clear: 100
        }
    }

    static func of(_ percentile: Int) -> TrendsRecoveryStanding {
        allCases.last { percentile >= $0.lowerPercentile } ?? .flat
    }

    /// Plain reading of the band, in the athlete's own terms. Describes a
    /// position against their own history; never prescribes, never grades.
    var note: String {
        switch self {
        case .flat: "bottom fifth of your own days"
        case .worn: "below your usual"
        case .steady: "about your usual"
        case .clear: "top quarter of your own days"
        }
    }
}

// MARK: - The read

/// Today's recovery, as two axes and a state.
struct TrendsRecoveryRead {

    typealias Factor = TrendsRecoveryLedger.Factor

    // MARK: Axis 1 · Load (demand)

    /// What training is asking. Every number here is already in real units —
    /// nothing on this axis is scaled, normalised or invented.
    struct Load {
        /// `100 x (acute − chronic) / chronic` in the pinned load unit.
        /// Positive is a hole. `nil` while the warm-up gate is closed.
        let needIndex: Double?
        /// Which rung of the ladder the EWMAs were denominated in. Surfaced
        /// so the athlete can see when the read is running on duration
        /// instead of real TLS.
        let unit: TrendsRecoveryDemand.LoadUnit
        /// Today as a multiple of the longest day in the prior 30, when it
        /// cleared the spike threshold. `nil` on every ordinary day.
        let spikeMultiple: Double?
        /// Days of history the EWMAs actually ran over.
        let historyDays: Int
        /// Schedule context, from `athlete_state` — passed through rather than
        /// recomputed, so it cannot disagree with the server.
        var hardSessions28d: Int?
        var avgDaysBetweenHard: Double?
        var downWeek: Bool?

        /// "18% over your usual load" / "in line with your usual load".
        var headline: String {
            guard let needIndex else { return "not enough history yet" }
            let pct = Int(abs(needIndex).rounded())
            if pct < 10 { return "in line with your usual" }
            return needIndex > 0 ? "\(pct)% over your usual" : "\(pct)% under your usual"
        }

        /// Compact form for a collapsed row.
        var chip: String {
            guard let needIndex else { return "warming up" }
            let pct = Int(abs(needIndex).rounded())
            if pct < 10 { return "in line" }
            return (needIndex > 0 ? "+" : "−") + "\(pct)% vs usual"
        }

        /// True when the load unit is the real per-workout TLS.
        var isTLS: Bool { unit == .stressLoad }
    }

    // MARK: Axis 2 · Body (supply)

    /// How the athlete is absorbing it, ranked against their own history.
    struct Body {
        /// 0…100 against the trailing window. 50 is this athlete's own median
        /// day. `nil` until the window holds `minimumSample` days — a rank
        /// against six days of history is noise wearing a number.
        let percentile: Int?
        /// How many prior days the rank was taken against.
        let sampleDays: Int
        /// The raw supply sum today, kept for the receipt's arithmetic line
        /// and for the trend. Arbitrary units by design — it is only ever
        /// compared to itself.
        let rawPoints: Int
        /// Supply-sourced factors only (words + nights), in display order.
        let factors: [Factor]

        var standing: TrendsRecoveryStanding? {
            percentile.map(TrendsRecoveryStanding.of)
        }

        /// Channels that spoke today, out of the four supply channels.
        var channelsWithData: Int { factors.filter(\.hasData).count }
        var channelCount: Int { factors.count }

        /// Factors currently subtracting — the absolute anchor that keeps a
        /// purely relative rank honest. An athlete who has been flat for six
        /// months ranks near their own median every day; this is what still
        /// says the median itself is low.
        var negatives: [Factor] { factors.filter { $0.points < 0 } }

        /// The single biggest drag today, for the collapsed row.
        var biggestDrag: Factor? { factors.min { $0.points < $1.points } }

        /// Fallback paths in play (no HRV, no sleep rating…).
        var degradations: [String] { factors.compactMap(\.degraded) }
        var gaps: [Factor.Gap] { factors.compactMap(\.gap) }
    }

    // MARK: Confidence

    /// How much evidence stood behind the read. Replaces the old ceiling: a
    /// thin read now says it is thin instead of quietly lowering a roof.
    enum Confidence {
        case full       // every supply channel present, none degraded
        case partial    // present but running a fallback path
        case thin       // a channel is silent, or the rank has no sample yet

        var label: String {
            switch self {
            case .full: "full read"
            case .partial: "partial read"
            case .thin: "thin read"
            }
        }
    }

    let load: Load
    let body: Body
    let state: TrendsRecoveryLedger.Quadrant
    let confidence: Confidence

    /// The headline sentence. Already copy-checked where it is defined.
    var sentence: String { state.sentence }

    // MARK: - Tunables

    /// Days the percentile ranks against. Six months is long enough to hold a
    /// full build-and-taper so a taper week is not ranked only against other
    /// taper weeks, and short enough that last season's fitness is not still
    /// setting the bar.
    static let rankWindowDays = 180

    /// Below this many ranked days there is no percentile — the read reports
    /// direction and factors instead of a number it cannot support.
    static let minimumSample = 30

    // MARK: - Computation

    /// Supply points for one day: the words and nights channels only.
    ///
    /// Deliberately NOT `TrendsRecoveryFactors.all()`. The demand factors walk
    /// the whole history to build their EWMAs, so calling `all()` once per day
    /// across the rank window is quadratic; the four supply factors carry
    /// bounded lookbacks and are cheap to run 180 times.
    static func supplyFactors(days: [TrendsDay], at i: Int) -> [Factor] {
        var out: [Factor] = [TrendsRecoveryFactors.mood(days: days, at: i)]
        out.append(TrendsRecoveryFactors.bodyMentions(days: days, at: i))
        if let sleep = TrendsRecoveryFactors.sleep(days: days, at: i) { out.append(sleep) }
        if let overnight = TrendsRecoveryFactors.overnight(days: days, at: i) { out.append(overnight) }
        return out
    }

    static func supplyPoints(days: [TrendsDay], at i: Int) -> Int {
        supplyFactors(days: days, at: i).reduce(0) { $0 + $1.points }
    }

    /// Today's read.
    static func read(
        days: [TrendsDay],
        at i: Int,
        hardSessions28d: Int? = nil,
        avgDaysBetweenHard: Double? = nil,
        downWeek: Bool? = nil
    ) -> TrendsRecoveryRead? {
        guard days.indices.contains(i) else { return nil }

        // ── Load ──────────────────────────────────────────────────────────
        let balance = TrendsRecoveryDemand.balance(days: days, at: i)
        let spike = TrendsRecoveryDemand.spikeMultiple(days: days, at: i)
        let load = Load(
            needIndex: balance.needIndex,
            unit: TrendsRecoveryDemand.loadUnit(for: days),
            spikeMultiple: (spike ?? 0) >= TrendsRecoveryDemand.spikeThreshold ? spike : nil,
            historyDays: balance.historyDays,
            hardSessions28d: hardSessions28d,
            avgDaysBetweenHard: avgDaysBetweenHard,
            downWeek: downWeek
        )

        // ── Body ──────────────────────────────────────────────────────────
        let factors = supplyFactors(days: days, at: i)
        let today = factors.reduce(0) { $0 + $1.points }

        // Rank against the athlete's own trailing window, today excluded.
        let start = max(0, i - rankWindowDays)
        let priors: [Int] = start < i
            ? (start..<i).map { supplyPoints(days: days, at: $0) }
            : []

        // Mid-rank: ties split, so a long run of identical median days lands
        // at 50 rather than at 0 or 100 depending on comparison direction.
        var percentile: Int?
        if priors.count >= minimumSample {
            let below = priors.filter { $0 < today }.count
            let equal = priors.filter { $0 == today }.count
            let rank = Double(below) + Double(equal) / 2.0
            percentile = Int((rank / Double(priors.count) * 100).rounded())
        }

        let body = Body(
            percentile: percentile,
            sampleDays: priors.count,
            rawPoints: today,
            factors: factors
        )

        // ── State ─────────────────────────────────────────────────────────
        // Supply is dragging when any WORDS channel is subtracting — the same
        // rule `TrendsRecoveryLedger` uses, kept identical on purpose so the
        // two surfaces can never disagree about what the words are saying.
        let dragging = factors.contains { $0.source == .words && $0.points < 0 }
        let state: TrendsRecoveryLedger.Quadrant = switch TrendsRecoveryDemand.demandLevel(days: days, at: i) {
        case .high: dragging ? .followingDown : .adaptingWell
        case .low: dragging ? .quietButDragging : .fresh
        case .unknown: .unknown
        }

        // ── Confidence ────────────────────────────────────────────────────
        let confidence: Confidence
        if percentile == nil || body.channelsWithData < body.channelCount {
            confidence = .thin
        } else if !body.degradations.isEmpty || !load.isTLS {
            confidence = .partial
        } else {
            confidence = .full
        }

        return TrendsRecoveryRead(load: load, body: body, state: state, confidence: confidence)
    }
}
