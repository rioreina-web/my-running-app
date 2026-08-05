//
//  SignalLabModels.swift
//  RunningLog · Analysis
//
//  The pure substrate for the Signal Lab — five signals, one athlete.
//
//  **What this screen is for.** Trends answers "how am I going". The Lab
//  answers "what is actually true about my engine", and it is allowed to be
//  slower, denser and more technical than a tab. It is pushed from Trends
//  rather than living in the tab bar for exactly that reason.
//
//  **Where the numbers come from.** Four of the five signals are computed here
//  from data `TrendsService` already holds — no new endpoint, no new query, no
//  deploy. The fifth, aerobic drift, needs per-second heart-rate and velocity
//  streams that deliberately do not travel on the `trends-timeline` wire (the
//  blobs stalled the response), so it is read from the `trends-insights` cards
//  instead, which fetch streams capped and chunked. When those cards have not
//  fired, the signal renders what it is waiting on rather than a blank.
//
//  **The rule every builder here follows:** a metric that cannot be computed
//  from real readings is absent, never estimated. `nil` is a supported answer
//  everywhere below.
//

import Foundation

// MARK: - Shared

enum SignalLabMath {
    /// Metres in a mile.
    static let metresPerMile = 1609.344

    /// Ordinary least-squares slope of y on x. `nil` when x has no spread or
    /// there are fewer than three points — two points fit anything.
    static func slope(xs: [Double], ys: [Double]) -> Double? {
        let n = Double(xs.count)
        guard xs.count >= 3, xs.count == ys.count else { return nil }
        let sx = xs.reduce(0, +), sy = ys.reduce(0, +)
        let sxx = zip(xs, xs).reduce(0) { $0 + $1.0 * $1.1 }
        let sxy = zip(xs, ys).reduce(0) { $0 + $1.0 * $1.1 }
        let denom = n * sxx - sx * sx
        guard abs(denom) > 0.000_001 else { return nil }
        return (n * sxy - sx * sy) / denom
    }

    static func mean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Metres travelled per heartbeat at a given pace and heart rate.
    ///
    /// Speed in metres per minute divided by beats per minute leaves metres
    /// per beat — the cleanest efficiency reading available without gas
    /// analysis. Higher is fitter, at a constant effort.
    static func metresPerBeat(paceSecPerMile: Int, hr: Int) -> Double? {
        guard paceSecPerMile > 0, hr > 0 else { return nil }
        let metresPerMinute = metresPerMile * 60 / Double(paceSecPerMile)
        return metresPerMinute / Double(hr)
    }

    /// Days since the epoch, so fits run over real time rather than sample
    /// index — sessions are not evenly spaced.
    static func dayNumber(_ iso: String) -> Double {
        guard let date = isoDay.date(from: iso) else { return 0 }
        return date.timeIntervalSince1970 / 86_400
    }

    static let isoDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}

// MARK: - Signal 01 · aerobic drift

/// One drift reading, sourced from a `trends-insights` card's series.
struct AerobicDriftPoint: Identifiable {
    let id = UUID()
    /// Position in the card's series.
    let index: Int
    /// The card's own label for the point, when it supplied one.
    let label: String?
    /// Decoupling percent. Positive is drifting.
    let pct: Double
}

struct AerobicDriftRead {
    let points: [AerobicDriftPoint]
    /// The card the series came from, so the screen can quote it rather than
    /// re-narrating the same finding in different words.
    let headline: String?
    let body: String?
    let confidence: String?
    /// The steady band the card supplied, when it had one.
    let bandLo: Double
    let bandHi: Double

    var isEmpty: Bool { points.isEmpty }
    var mean: Double? { SignalLabMath.mean(points.map(\.pct)) }
    var overBand: [AerobicDriftPoint] { points.filter { $0.pct > bandHi } }
    var worst: AerobicDriftPoint? { points.max { $0.pct < $1.pct } }

    /// Slope in percent per ten readings — the series carries no dates, so the
    /// fit is over sample order and the unit says so.
    var trendPctPerTen: Double? {
        SignalLabMath.slope(
            xs: points.map { Double($0.index) },
            ys: points.map(\.pct)
        ).map { $0 * 10 }
    }

    static let empty = AerobicDriftRead(
        points: [], headline: nil, body: nil, confidence: nil, bandLo: 0, bandHi: 5
    )
}

enum AerobicDriftBuilder {
    /// Units a decoupling series can arrive in. A card measured in bpm or
    /// seconds is a different signal and is not adopted.
    static let acceptedUnits = ["%"]

    /// Pull the drift series out of the insight cards.
    ///
    /// Group B is the stream-backed family, and decoupling is the one that
    /// reports a percentage. Matching on unit rather than on card id keeps
    /// this working when the detector set is renumbered.
    static func build(cards: [TrendInsightCard]) -> AerobicDriftRead {
        let candidate = cards.first { card in
            guard card.group == "B", let series = card.series else { return false }
            guard acceptedUnits.contains(series.unit ?? "") else { return false }
            return series.points.count >= 3 && mentionsDrift(card)
        }

        guard let card = candidate, let series = card.series else { return .empty }

        let points = series.points.enumerated().map { index, value in
            AerobicDriftPoint(
                index: index,
                label: series.labels?.indices.contains(index) == true ? series.labels?[index] : nil,
                pct: value
            )
        }

        return AerobicDriftRead(
            points: points,
            headline: card.headline,
            body: card.body,
            confidence: card.confidence,
            bandLo: series.band?.lo ?? 0,
            bandHi: series.band?.hi ?? 5
        )
    }

    /// The card is about drift when it says so. Cheap, and it keeps a future
    /// percentage-valued Group B card from being mistaken for this one.
    static func mentionsDrift(_ card: TrendInsightCard) -> Bool {
        let text = (card.headline + " " + card.body).lowercased()
        return text.contains("drift") || text.contains("decoupl")
    }
}

// MARK: - Signal 03 · heart-rate efficiency

/// One session's efficiency reading.
struct BeatEfficiencyPoint: Identifiable {
    let id: String
    let date: String
    let dateLabel: String
    /// Metres per heartbeat over the session's work.
    let metresPerBeat: Double
    let hr: Int
    let paceSec: Int
    /// Rep sessions and long efforts are different instruments and never share
    /// a trend line.
    let isLong: Bool
}

struct BeatEfficiencyRead {
    let reps: [BeatEfficiencyPoint]
    let longs: [BeatEfficiencyPoint]

    var isEmpty: Bool { reps.isEmpty && longs.isEmpty }
    var all: [BeatEfficiencyPoint] { (reps + longs).sorted { $0.date < $1.date } }

    var repsMean: Double? { SignalLabMath.mean(reps.map(\.metresPerBeat)) }
    var longsMean: Double? { SignalLabMath.mean(longs.map(\.metresPerBeat)) }

    /// Change in metres per beat per 30 days, per series. Negative is losing
    /// efficiency.
    func trendPerMonth(_ series: [BeatEfficiencyPoint]) -> Double? {
        SignalLabMath.slope(
            xs: series.map { SignalLabMath.dayNumber($0.date) },
            ys: series.map(\.metresPerBeat)
        ).map { $0 * 30 }
    }

    var repsTrend: Double? { trendPerMonth(reps) }
    var longsTrend: Double? { trendPerMonth(longs) }
}

enum BeatEfficiencyBuilder {
    /// Heart rates outside this range are sensor artefacts, not readings.
    /// Matches the `HR_MIN` / `HR_MAX` gate in `_shared/fitnessSignal.ts`.
    static let hrRange = 90...205

    static func build(keySessions: [KeySession], windowDates: Set<String>) -> BeatEfficiencyRead {
        var reps: [BeatEfficiencyPoint] = []
        var longs: [BeatEfficiencyPoint] = []

        for s in keySessions where windowDates.contains(s.date) {
            guard let hr = s.workHrAvg, hrRange.contains(hr) else { continue }
            // Heat-neutral pace, so a hot week does not read as lost
            // efficiency — the same correction every other surface applies.
            guard let mpb = SignalLabMath.metresPerBeat(paceSecPerMile: s.effectivePaceSec, hr: hr)
            else { continue }

            let point = BeatEfficiencyPoint(
                id: s.id,
                date: s.date,
                dateLabel: s.dateLabel,
                metresPerBeat: mpb,
                hr: hr,
                paceSec: s.effectivePaceSec,
                isLong: s.isLongRun
            )
            if s.isLongRun { longs.append(point) } else { reps.append(point) }
        }

        return BeatEfficiencyRead(
            reps: reps.sorted { $0.date < $1.date },
            longs: longs.sorted { $0.date < $1.date }
        )
    }
}

// MARK: - Signal 04 · mood against load

/// One mood label with the training that carried it.
struct MoodLoadGroup: Identifiable {
    /// The mood label, from the closed vocabulary.
    let id: String
    /// Days logged with this label.
    let dayCount: Int
    /// Mean miles on those days.
    let meanMiles: Double
    /// Mean quality load on those days.
    let meanLoad: Double
    /// Mean recovery score on those days.
    let meanRecovery: Double
}

struct MoodLoadRead {
    /// Ordered by the mood vocabulary, brightest first, so the chart's order
    /// is a fixed scale rather than a ranking that reshuffles.
    let groups: [MoodLoadGroup]
    /// Days in the window carrying no mood log at all.
    let unloggedDays: Int
    let totalDays: Int

    var isEmpty: Bool { groups.count < 2 }

    var loggedDays: Int { totalDays - unloggedDays }

    /// The spread in mean load between the heaviest and lightest mood group.
    var loadSpread: Double? {
        guard let hi = groups.map(\.meanLoad).max(),
              let lo = groups.map(\.meanLoad).min()
        else { return nil }
        return hi - lo
    }

    /// Whether load meaningfully separates the mood groups.
    ///
    /// The test is deliberately blunt: if the heaviest and lightest mood
    /// groups sit within a tenth of each other on mean load, load is not what
    /// is moving mood in this window. It is a statement about this data, not a
    /// finding about training in general, and the copy says so.
    var loadSeparates: Bool? {
        guard let spread = loadSpread,
              let overall = SignalLabMath.mean(groups.map(\.meanLoad)),
              overall > 0
        else { return nil }
        return spread / overall >= 0.10
    }

    var heaviestMood: MoodLoadGroup? { groups.max { $0.meanLoad < $1.meanLoad } }
    var lightestMood: MoodLoadGroup? { groups.min { $0.meanLoad < $1.meanLoad } }
}

enum MoodLoadBuilder {
    /// The closed vocabulary, in register order. Any label off this list is
    /// dropped rather than appended — the vocabulary is closed by design.
    static let vocabulary = ["energized", "positive", "neutral", "tired", "struggling", "injured"]

    /// A mood needs this many logged days before its mean means anything.
    static let minimumDaysPerMood = 2

    static func build(set: TrendsBucketSet) -> MoodLoadRead {
        // Day grain only. At week grain a bucket's mood is already a modal
        // rollup and pairing it with the week's load would compare a summary
        // to a sum.
        let buckets = set.grain == .day ? set.buckets : []

        var byMood: [String: [TrendsBucket]] = [:]
        for b in buckets {
            guard let mood = b.mood?.lowercased(), vocabulary.contains(mood) else { continue }
            byMood[mood, default: []].append(b)
        }

        let groups: [MoodLoadGroup] = vocabulary.compactMap { mood in
            guard let days = byMood[mood], days.count >= minimumDaysPerMood else { return nil }
            return MoodLoadGroup(
                id: mood,
                dayCount: days.count,
                meanMiles: SignalLabMath.mean(days.map(\.miles)) ?? 0,
                meanLoad: SignalLabMath.mean(days.map(\.qualityLoad)) ?? 0,
                meanRecovery: SignalLabMath.mean(days.map { Double($0.recovery) }) ?? 0
            )
        }

        let logged = buckets.filter { ($0.mood?.isEmpty == false) }.count
        return MoodLoadRead(
            groups: groups,
            unloggedDays: max(0, buckets.count - logged),
            totalDays: buckets.count
        )
    }
}

// MARK: - Signal 05 · heat impact

/// One session's heat correction.
struct HeatImpactPoint: Identifiable {
    let id: String
    let date: String
    let dateLabel: String
    /// What the watch said, sec/mi.
    let rawSec: Int
    /// The same run with the weather taken out, sec/mi.
    let adjSec: Int
    /// `rawSec - adjSec`. Always positive here — a zero correction is not a
    /// point on this chart.
    let penaltySec: Int
    /// The heat bucket the backend assigned: ideal | warm | hot | very_hot |
    /// dangerous.
    let category: String?
    /// Dew point °F, when the pace-bands payload carried it for this session.
    let dewPointF: Int?
}

struct HeatImpactRead {
    let points: [HeatImpactPoint]
    /// Sessions in the window with no weather at all, named so the sample is
    /// honest about its own coverage.
    let uncorrectedCount: Int

    var isEmpty: Bool { points.isEmpty }
    var meanPenalty: Int? {
        SignalLabMath.mean(points.map { Double($0.penaltySec) }).map { Int($0.rounded()) }
    }
    var worst: HeatImpactPoint? { points.max { $0.penaltySec < $1.penaltySec } }

    var dewRange: (lo: Int, hi: Int)? {
        let dews = points.compactMap(\.dewPointF)
        guard let lo = dews.min(), let hi = dews.max(), lo != hi else { return nil }
        return (lo, hi)
    }

    /// Seconds per mile charged per ten degrees of dew point, fitted over the
    /// sessions that carried a dew reading. `nil` under three such sessions.
    var secPerTenDegDew: Double? {
        let paired = points.compactMap { p -> (Double, Double)? in
            guard let dew = p.dewPointF else { return nil }
            return (Double(dew), Double(p.penaltySec))
        }
        return SignalLabMath.slope(xs: paired.map(\.0), ys: paired.map(\.1)).map { $0 * 10 }
    }
}

enum HeatImpactBuilder {
    static func build(
        keySessions: [KeySession],
        bands: PaceBands?,
        windowDates: Set<String>
    ) -> HeatImpactRead {
        // Dew point rides on the pace-bands payload rather than the key-session
        // one, so it is joined in by log id where it exists.
        var dewByID: [String: Int] = [:]
        for s in bands?.sessions ?? [] {
            if let dew = s.dewPointF { dewByID[s.id] = dew }
        }

        let inWindow = keySessions.filter { windowDates.contains($0.date) }
        var points: [HeatImpactPoint] = []
        var uncorrected = 0

        for s in inWindow {
            guard s.isHeatAdjusted, let adj = s.workPaceAdjSec else {
                uncorrected += 1
                continue
            }
            let penalty = s.workPaceSec - adj
            guard penalty > 0 else {
                uncorrected += 1
                continue
            }
            points.append(
                HeatImpactPoint(
                    id: s.id,
                    date: s.date,
                    dateLabel: s.dateLabel,
                    rawSec: s.workPaceSec,
                    adjSec: adj,
                    penaltySec: penalty,
                    category: s.heatCategory,
                    dewPointF: dewByID[s.id]
                )
            )
        }

        return HeatImpactRead(
            points: points.sorted { $0.date < $1.date },
            uncorrectedCount: uncorrected
        )
    }
}
