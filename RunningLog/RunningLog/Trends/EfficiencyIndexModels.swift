//
//  EfficiencyIndexModels.swift
//  RunningLog · Trends
//
//  Substrate for Instruments card 03 — the HR efficiency index. One composite
//  number: metres of ground per heartbeat, scored against the athlete's OWN
//  speed-and-heat curve, expressed at the threshold anchor, heat-neutral on
//  both sides of the ratio (pace via `workPaceAdjSec`, HR drift via a heat
//  term fit from the athlete's history).
//
//  Every input already arrives on `trends-timeline` via `KeySession` — no
//  backend work, no new fetch. See `HR-EFFICIENCY-INDEX-APPLY.md` for the
//  full spec and the 2026-08-18 validation on real exported data:
//    · pooled fit (quality + long runs) R² 0.957, leave-one-out ±2.3 pts
//    · long runs INCLUDED in the fit — they anchor the slow end and halve
//      slope wobble (8% → 5% under LOO). They still render as diamonds.
//    · the outlier gate uses DELETED residuals (predict-without-the-point),
//      because a high-leverage artefact (8×200 at HR 136) bends an ordinary
//      fit toward itself and hides its own residual. This gate caught it;
//      a plain residual gate did not.
//    · the heat term clamps to ≤ 0 and needs 5 non-ideal sessions to fit;
//      both failure directions are conservative — heat can cost the index,
//      never pay it.
//
//  No SwiftUI in this file — the rules are testable without a renderer.
//

import Foundation

// MARK: - Point

/// One eligible session's efficiency reading.
struct EfficiencyPoint: Identifiable {
    let id: String          // training_log_id, so a tap can open the workout
    let date: String        // "2026-06-23" (UTC day)
    let dateLabel: String
    let dayNumber: Int
    /// Zone token from the shared classifier: mile | 3k | 5k | 10k | hmp | mp.
    let zone: String
    let isLongRun: Bool
    let isHeatAdjusted: Bool
    let heatCategory: String?
    let heatSeverity: Int
    let hr: Int
    /// Heat-neutral pace (sec/mi) — `KeySession.effectivePaceSec`.
    let paceSec: Int
    /// Metres per minute, derived from `paceSec`.
    let speed: Double
    /// Metres per heartbeat.
    let mpb: Double
    let structure: String?
    /// 100 = exactly on the athlete's curve. Nil until a curve exists.
    var index: Double?
}

// MARK: - Curve

/// The athlete's own baseline: m/beat ≈ b0 + b1·speed + b2·heatSeverity,
/// fit over the trailing lookback. `b2` is 0 unless the heat term earned
/// its fit (≥ `minHeatSessions` non-ideal sessions), and never positive.
struct EfficiencyCurve {
    let b0: Double
    let b1: Double
    let b2: Double
    /// Speed range (m/min) the fit actually saw. Predictions outside it are
    /// extrapolation; the threshold stat refuses them (hard rule #8 — omit,
    /// never fill).
    let speedLo: Double
    let speedHi: Double
    let sessionCount: Int
    let heatTermFit: Bool

    func predict(speed: Double, severity: Int) -> Double {
        b0 + b1 * speed + b2 * Double(severity)
    }

    func covers(speed: Double) -> Bool {
        speed >= speedLo && speed <= speedHi
    }
}

// MARK: - Read

/// Why a session in the window did not feed the chart. Reported, never
/// silently deleted — a filter that silently deletes running is a filter
/// that lies (`TrendsThresholdModels.swift` header).
struct EfficiencyExclusion: Identifiable {
    let id: String     // reason token
    let label: String  // "MISSING HR"
    let count: Int
}

/// Everything the card renders, derived once.
struct EfficiencyIndexRead {
    /// Windowed, eligible, indexed sessions, oldest → newest.
    let points: [EfficiencyPoint]
    let curve: EfficiencyCurve?
    /// Mean session index over the trailing `headlineDays`; nil under
    /// `headlineMinSessions` — the headline reads NOT YET, the dots still draw.
    let headline: Double?
    let headlineCount: Int
    /// Index points per 30 days over the windowed series; nil under 3 points.
    let trendPerMonth: Double?
    /// Mean index per zone (≥ 3 sessions), fast → slow. Long runs group
    /// under the "long" token, labelled LONG.
    let zoneMeans: [(zone: String, mean: Double, count: Int)]
    /// The curve read out at the band's anchor pace in ideal heat — nil when
    /// no ladder exists or the anchor pace sits outside the fitted range.
    let anchorStat: (mpb: Double, paceSec: Int)?
    /// The athlete's own measured drift: β₂ as a percent of the curve per
    /// heat step. Nil when the heat term didn't fit.
    let heatCostPctPerStep: Double?
    /// Non-ideal sessions the fit saw — feeds the "HEAT TERM NOT YET —
    /// n of 5" wording.
    let nonIdealCount: Int
    let excluded: [EfficiencyExclusion]
    /// The words for the empty/NOT YET state; nil when a curve exists.
    let notYetReason: String?

    var isEmpty: Bool { points.isEmpty }
    var latest: EfficiencyPoint? { points.last }

    func points(zone: String?) -> [EfficiencyPoint] {
        guard let zone else { return points }
        if zone == EfficiencyIndexBuilder.longZoneToken {
            return points.filter { $0.isLongRun }
        }
        return points.filter { $0.zone == zone && !$0.isLongRun }
    }
}

// MARK: - Builder

enum EfficiencyIndexBuilder {

    /// Heart rates outside this range are sensor artefacts, not readings.
    /// Matches `HR_MIN` / `HR_MAX` in `_shared/fitnessSignal.ts`.
    static let hrRange = 90...205
    /// The curve needs this many sessions and this many distinct zones —
    /// a curve fit to one zone is a point wearing a slope.
    static let minSessions = 8
    static let minZones = 2
    /// The heat term needs heat to learn from.
    static let minHeatSessions = 5
    /// The composite headline: trailing days and its session floor.
    static let headlineDays = 28
    static let headlineMinSessions = 3
    /// The baseline lookback the curve is fit on.
    static let lookbackDays = 180
    /// Deleted-residual outlier gate: |z| above this is an artefact
    /// (validated against a real HR-lag session, z = 5.3). The gate only
    /// runs with `outlierMinSessions`+ so a small fit can't eat itself.
    static let outlierZ = 4.0
    static let outlierRounds = 2
    static let outlierMinSessions = 10

    static let metresPerMile = 1609.344
    /// Pseudo-zone token long runs group under for chips and means.
    static let longZoneToken = "long"

    /// `heatCategory` → ordinal severity. One coefficient across the ladder;
    /// five separate dummies would fit noise on a beta athlete's counts.
    static func severity(_ heatCategory: String?) -> Int {
        switch heatCategory?.lowercased() {
        case "warm": 1
        case "hot": 2
        case "very_hot": 3
        case "dangerous": 4
        default: 0   // ideal / nil (nil only passes eligibility when ideal-equivalent)
        }
    }

    // MARK: Build

    static func build(
        sessions: [KeySession],
        bandLaps: BandLaps?,
        settings: BandSettings,
        window: TrendsWindow,
        asOf: Date = Date()
    ) -> EfficiencyIndexRead {

        let today = Int(asOf.timeIntervalSince1970 / 86_400)
        let windowFrom: Int
        let windowTo: Int
        switch window {
        case .custom(let from, let to):
            windowFrom = Int(from.timeIntervalSince1970 / 86_400)
            windowTo = Int(to.timeIntervalSince1970 / 86_400)
        default:
            windowFrom = today - window.days + 1
            windowTo = today
        }
        let lookbackFrom = today - lookbackDays + 1

        // 1 · Eligibility, via the one classifier. Excluded sessions are
        // counted, never deleted.
        var missingHr = 0
        var hrArtefact = 0
        var unadjustedHeat = 0
        var all: [EfficiencyPoint] = []

        for s in sessions {
            switch classify(s) {
            case .ok(let point): all.append(point)
            case .excluded(let reason):
                switch reason {
                case .missingHr: missingHr += 1
                case .hrArtefact: hrArtefact += 1
                case .unadjustedHeat: unadjustedHeat += 1
                case .unusablePace: break
                }
            }
        }
        all.sort { $0.dayNumber < $1.dayNumber }

        // 2 · The fit population: trailing lookback, regardless of the display
        // window — the baseline is a property of the athlete's recent history
        // and narrowing the chart must not move it.
        var fit = all.filter { $0.dayNumber >= lookbackFrom && $0.dayNumber <= today }

        // 3 · Guards, in the NOT YET voice.
        var notYet: String?
        let zonesSeen = Set(fit.map { $0.isLongRun ? longZoneToken : $0.zone })
        if fit.count < minSessions {
            notYet = "NOT YET — \(fit.count) of \(minSessions) sessions with heart rate in the last \(lookbackDays) days."
        } else if zonesSeen.count < minZones {
            notYet = "NOT YET — every session sits in one zone. The curve needs two."
        }

        // 4 · Outlier gate — deleted residuals, so leverage can't hide.
        var outlierIds = Set<String>()
        var curve: EfficiencyCurve?
        if notYet == nil {
            if fit.count >= outlierMinSessions {
                for _ in 0..<outlierRounds {
                    let dropped = dropOutliers(&fit)
                    outlierIds.formUnion(dropped)
                    if dropped.isEmpty { break }
                }
            }
            curve = solve(fit)
            if curve == nil {
                // Degenerate geometry (e.g. all sessions at one speed).
                notYet = "NOT YET — the sessions don't span enough paces to fit a curve."
            }
        }

        // 5 · Index every windowed point against the curve. A session the
        // gate called an artefact does not draw — a dot at an impossible
        // index is a lie, and the NOT COUNTED panel already owns it.
        var points = all.filter {
            $0.dayNumber >= windowFrom && $0.dayNumber <= windowTo && !outlierIds.contains($0.id)
        }
        if let curve {
            for i in points.indices {
                let predicted = curve.predict(speed: points[i].speed, severity: points[i].heatSeverity)
                if predicted > 0 {
                    points[i].index = 100 * points[i].mpb / predicted
                }
            }
        }
        let indexed = points.compactMap { p -> (EfficiencyPoint, Double)? in
            guard let idx = p.index else { return nil }
            return (p, idx)
        }

        // 6 · Headline: trailing 28-day mean, floor of 3 sessions.
        let recent = indexed.filter { $0.0.dayNumber > today - headlineDays }
        let headline: Double? = recent.count >= headlineMinSessions
            ? recent.map(\.1).reduce(0, +) / Double(recent.count)
            : nil

        // 7 · Trend: index points per 30 days across the windowed series.
        let trend: Double? = indexed.count >= 3
            ? ThresholdRead.slope(
                xs: indexed.map { Double($0.0.dayNumber) },
                ys: indexed.map(\.1)
            ).map { $0 * 30 }
            : nil

        // 8 · Per-zone means, fast → slow, floor of 3. Long runs are their
        // own group — different quantity, same curve.
        var byZone: [String: [Double]] = [:]
        for (p, idx) in indexed {
            byZone[p.isLongRun ? longZoneToken : p.zone, default: []].append(idx)
        }
        var zoneMeans: [(zone: String, mean: Double, count: Int)] = []
        for token in KeyZone.order + [longZoneToken] {
            if let values = byZone[token], values.count >= 3 {
                zoneMeans.append((token, values.reduce(0, +) / Double(values.count), values.count))
            }
        }

        // 9 · The threshold anchor, evaluated cool (severity 0) — the only
        // version of the number comparable across a summer. Judged against
        // the latest ladder, same as the band.
        var anchorStat: (mpb: Double, paceSec: Int)?
        if let curve, let ladder = bandLaps?.sessions.last?.anchors {
            let anchorSec = settings.anchor.sec(in: ladder)
            if anchorSec > 0 {
                let anchorSpeed = metresPerMile * 60 / Double(anchorSec)
                if curve.covers(speed: anchorSpeed) {
                    anchorStat = (curve.predict(speed: anchorSpeed, severity: 0), anchorSec)
                }
            }
        }

        // 10 · The athlete's own heat cost, as a percent per step.
        var heatCost: Double?
        if let curve, curve.heatTermFit, curve.b2 < 0 {
            let midSpeed = (curve.speedLo + curve.speedHi) / 2
            let base = curve.predict(speed: midSpeed, severity: 0)
            if base > 0 { heatCost = 100 * curve.b2 / base }
        }

        var excluded: [EfficiencyExclusion] = []
        if missingHr > 0 { excluded.append(.init(id: "hr", label: "NO HEART RATE", count: missingHr)) }
        if hrArtefact > 0 { excluded.append(.init(id: "artefact", label: "HR ARTEFACT", count: hrArtefact)) }
        if unadjustedHeat > 0 { excluded.append(.init(id: "heat", label: "HOT, NO ADJUSTMENT", count: unadjustedHeat)) }
        if !outlierIds.isEmpty { excluded.append(.init(id: "outlier", label: "HR LAG OUTLIER", count: outlierIds.count)) }

        return EfficiencyIndexRead(
            points: points,
            curve: curve,
            headline: headline,
            headlineCount: recent.count,
            trendPerMonth: trend,
            zoneMeans: zoneMeans,
            anchorStat: anchorStat,
            heatCostPctPerStep: heatCost,
            nonIdealCount: fit.filter { $0.heatSeverity > 0 }.count,
            excluded: excluded,
            notYetReason: notYet
        )
    }

    // MARK: Eligibility

    /// Why a session cannot be scored.
    enum ExclusionReason {
        case missingHr
        case hrArtefact
        case unadjustedHeat
        case unusablePace
    }

    enum Eligibility {
        case ok(EfficiencyPoint)
        case excluded(ExclusionReason)
    }

    /// **The one definition** of what counts as a scoreable session. Both the
    /// efficiency card and the threshold check read it, so the two surfaces
    /// cannot start disagreeing about the same run.
    static func classify(_ s: KeySession) -> Eligibility {
        guard let hr = s.workHrAvg else { return .excluded(.missingHr) }
        guard hrRange.contains(hr) else { return .excluded(.hrArtefact) }
        // Heat is trustworthy when ideal, or non-ideal WITH an adjusted pace.
        // Never score a hot session at its raw pace — that reads heat as lost
        // fitness, the error the correction exists to stop.
        let category = s.heatCategory?.lowercased()
        let nonIdeal = category != nil && category != "ideal"
        if nonIdeal && s.workPaceAdjSec == nil { return .excluded(.unadjustedHeat) }

        let pace = s.effectivePaceSec
        guard pace > 0 else { return .excluded(.unusablePace) }
        let speed = metresPerMile * 60 / Double(pace)
        return .ok(EfficiencyPoint(
            id: s.id,
            date: s.date,
            dateLabel: s.dateLabel,
            dayNumber: ThresholdRead.dayNumber(s.date),
            zone: s.zone,
            isLongRun: s.isLongRun,
            isHeatAdjusted: s.isHeatAdjusted,
            heatCategory: s.heatCategory,
            heatSeverity: nonIdeal ? severity(s.heatCategory) : 0,
            hr: hr,
            paceSec: pace,
            speed: speed,
            mpb: speed / Double(hr),
            structure: s.structure,
            index: nil
        ))
    }

    static func eligiblePoints(_ sessions: [KeySession]) -> [EfficiencyPoint] {
        sessions.compactMap {
            if case .ok(let p) = classify($0) { return p }
            return nil
        }
        .sorted { $0.dayNumber < $1.dayNumber }
    }

    // MARK: Drift at a pace

    /// Efficiency at one pace, first half of the window against the second —
    /// the threshold check's context row (`ThresholdCheckModels.swift`).
    ///
    /// Returns nil unless BOTH halves carry enough sessions and BOTH fits
    /// actually cover the pace: extrapolating a curve to a pace it never saw
    /// is how a context row becomes a claim. The caller decides whether the
    /// change is directional — `EfficiencyDrift.isDirectional` requires the
    /// jackknife to exclude zero, because a sign that flips is noise.
    static func driftAtBand(
        sessions: [KeySession],
        anchorSec: Int,
        from: Int,
        to: Int
    ) -> EfficiencyDrift? {
        guard anchorSec > 0 else { return nil }
        let speed = metresPerMile * 60 / Double(anchorSec)

        let windowed = eligiblePoints(sessions).filter { $0.dayNumber >= from && $0.dayNumber <= to }
        guard windowed.count >= 2 * minSessions else { return nil }
        let mid = windowed.count / 2
        let first = Array(windowed[..<mid])
        let second = Array(windowed[mid...])

        func predict(_ points: [EfficiencyPoint]) -> Double? {
            guard points.count >= minSessions, let curve = solve(points),
                  curve.covers(speed: speed) else { return nil }
            let value = curve.predict(speed: speed, severity: 0)
            return value > 0 ? value : nil
        }

        guard let a = predict(first), let b = predict(second) else { return nil }
        let point = 100 * (b / a - 1)

        // Full jackknife: drop one session from each half in turn.
        var lo = point
        var hi = point
        for i in first.indices {
            var trimmedFirst = first
            trimmedFirst.remove(at: i)
            guard let ai = predict(trimmedFirst) else { continue }
            for j in second.indices {
                var trimmedSecond = second
                trimmedSecond.remove(at: j)
                guard let bj = predict(trimmedSecond) else { continue }
                let value = 100 * (bj / ai - 1)
                lo = min(lo, value)
                hi = max(hi, value)
            }
        }
        return EfficiencyDrift(pct: point, loPct: lo, hiPct: hi)
    }

    // MARK: Fit

    /// OLS over m/beat ≈ b0 + b1·speed [+ b2·severity]. The heat term is only
    /// granted when ≥ `minHeatSessions` non-ideal sessions exist, and is
    /// clamped ≤ 0 — heat cannot make a human more efficient, so a positive
    /// fitted coefficient is sampling noise wearing a conclusion.
    static func solve(_ points: [EfficiencyPoint]) -> EfficiencyCurve? {
        guard points.count >= 2 else { return nil }
        let speeds = points.map(\.speed)
        guard let lo = speeds.min(), let hi = speeds.max(), hi - lo > 1 else { return nil }

        let nonIdeal = points.filter { $0.heatSeverity > 0 }.count
        let wantHeat = nonIdeal >= minHeatSessions && points.count > nonIdeal

        if wantHeat,
           let b = normalSolve(points, heat: true) {
            let b2 = min(b[2], 0)
            // A clamped heat term means the two-covariate solution no longer
            // holds; refit the speed line with severity pinned at the clamp.
            if b2 == 0, let flat = normalSolve(points, heat: false) {
                return EfficiencyCurve(
                    b0: flat[0], b1: flat[1], b2: 0,
                    speedLo: lo, speedHi: hi,
                    sessionCount: points.count, heatTermFit: true
                )
            }
            return EfficiencyCurve(
                b0: b[0], b1: b[1], b2: b2,
                speedLo: lo, speedHi: hi,
                sessionCount: points.count, heatTermFit: true
            )
        }

        guard let b = normalSolve(points, heat: false) else { return nil }
        return EfficiencyCurve(
            b0: b[0], b1: b[1], b2: 0,
            speedLo: lo, speedHi: hi,
            sessionCount: points.count, heatTermFit: false
        )
    }

    /// Normal-equation solve; heat=false fits [1, speed], heat=true fits
    /// [1, speed, severity]. Returns nil when the system is singular.
    static func normalSolve(_ points: [EfficiencyPoint], heat: Bool) -> [Double]? {
        let k = heat ? 3 : 2
        var ata = [[Double]](repeating: [Double](repeating: 0, count: k), count: k)
        var atb = [Double](repeating: 0, count: k)
        for p in points {
            let row = heat ? [1.0, p.speed, Double(p.heatSeverity)] : [1.0, p.speed]
            for i in 0..<k {
                atb[i] += row[i] * p.mpb
                for j in 0..<k { ata[i][j] += row[i] * row[j] }
            }
        }
        return gaussian(ata, atb)
    }

    /// Tiny Gaussian elimination with partial pivoting — 2×2 or 3×3 only.
    static func gaussian(_ matrix: [[Double]], _ rhs: [Double]) -> [Double]? {
        var a = matrix
        var b = rhs
        let n = b.count
        for col in 0..<n {
            var pivot = col
            for row in (col + 1)..<n where abs(a[row][col]) > abs(a[pivot][col]) {
                pivot = row
            }
            if abs(a[pivot][col]) < 1e-12 { return nil }
            if pivot != col {
                a.swapAt(pivot, col)
                b.swapAt(pivot, col)
            }
            for row in (col + 1)..<n {
                let factor = a[row][col] / a[col][col]
                for j in col..<n { a[row][j] -= factor * a[col][j] }
                b[row] -= factor * b[col]
            }
        }
        var x = [Double](repeating: 0, count: n)
        for row in stride(from: n - 1, through: 0, by: -1) {
            var sum = b[row]
            for j in (row + 1)..<n { sum -= a[row][j] * x[j] }
            x[row] = sum / a[row][row]
        }
        return x
    }

    // MARK: Outliers

    /// Each point is scored by a fit that never saw it: z = |what the
    /// rest-fit predicts for the point, missed by| ÷ |how well that rest-fit
    /// explains its own points|. A high-leverage artefact bends an ordinary
    /// fit toward itself and hides its own residual; here it is judged by
    /// the CLEAN fit (huge z) while every clean point is judged by the
    /// polluted one (small z). Validated both ways on real exported data:
    /// the 8×200 @ HR 136 artefact scores z ≈ 20 and nothing else scores
    /// above 4 — and a plain MAD-of-residuals gate missed it entirely.
    ///
    /// The denominator is floored at 1% of the mean reading: pace and HR
    /// carry at least that much measurement noise, so on data cleaner than
    /// life the gate cannot call a genuinely strong session an artefact.
    /// Removes points with z above `outlierZ`; returns the dropped ids so
    /// the read keeps them off the chart too.
    static func dropOutliers(_ points: inout [EfficiencyPoint]) -> Set<String> {
        let n = points.count
        guard n >= outlierMinSessions else { return [] }

        let meanMpb = points.map(\.mpb).reduce(0, +) / Double(n)
        let floor = 0.01 * meanMpb
        var z = [Double](repeating: 0, count: n)
        for i in 0..<n {
            var rest = points
            rest.remove(at: i)
            guard let curve = solve(rest) else { return [] }
            let deleted = points[i].mpb - curve.predict(
                speed: points[i].speed, severity: points[i].heatSeverity
            )
            let restError = rest.map { q in
                let r = q.mpb - curve.predict(speed: q.speed, severity: q.heatSeverity)
                return r * r
            }.reduce(0, +) / Double(rest.count)
            z[i] = abs(deleted) / max(restError.squareRoot(), floor)
        }

        let keep = (0..<n).filter { z[$0] <= outlierZ }
        guard keep.count < n else { return [] }
        let dropped = Set((0..<n).filter { !keep.contains($0) }.map { points[$0].id })
        points = keep.map { points[$0] }
        return dropped
    }
}

// MARK: - Prose

/// The derived observation the card prints. Never authored copy: every number
/// in the sentence is a number already on screen (the `InstrumentNote`
/// contract). Observation, never prescription.
enum EfficiencyIndexProse {

    static func headline(_ read: EfficiencyIndexRead) -> String {
        if let headline = read.headline {
            return String(format: "Index %.0f over the last %d days.", headline, EfficiencyIndexBuilder.headlineDays)
        }
        if read.curve != nil {
            return "Ground per heartbeat, against your own curve."
        }
        return "Metres per heartbeat."
    }

    static func subtitle(_ read: EfficiencyIndexRead) -> String {
        guard read.curve != nil else { return "" }
        let n = read.points.count
        var text = "\(n) session\(n == 1 ? "" : "s") against your \(EfficiencyIndexBuilder.lookbackDays)-day speed-and-heat curve. 100 is your norm."
        if !read.excluded.isEmpty {
            let total = read.excluded.reduce(0) { $0 + $1.count }
            text += " \(total) not counted."
        }
        return text
    }

    static func note(_ read: EfficiencyIndexRead) -> String? {
        guard let headline = read.headline else {
            if read.curve != nil, !read.points.isEmpty {
                return "Fewer than \(EfficiencyIndexBuilder.headlineMinSessions) sessions in the last \(EfficiencyIndexBuilder.headlineDays) days — the dots draw, the composite waits."
            }
            return nil
        }
        var parts: [String] = []
        let delta = headline - 100
        if abs(delta) < 0.5 {
            parts.append(String(format: "Last %d days: %d sessions averaged %.0f — right on your %d-day curve.", EfficiencyIndexBuilder.headlineDays, read.headlineCount, headline, EfficiencyIndexBuilder.lookbackDays))
        } else {
            parts.append(String(format: "Last %d days: %d sessions averaged %.0f — %.0f%% %@ ground per beat than your %d-day curve.", EfficiencyIndexBuilder.headlineDays, read.headlineCount, headline, abs(delta), delta > 0 ? "more" : "less", EfficiencyIndexBuilder.lookbackDays))
        }
        let zones = read.zoneMeans.filter { $0.zone == "mp" || $0.zone == "hmp" }
        if !zones.isEmpty {
            let text = zones
                .map { String(format: "%@ %.0f", KeyZone.label($0.zone), $0.mean) }
                .joined(separator: ", ")
            parts.append("\(text).")
        }
        if let cost = read.heatCostPctPerStep {
            parts.append(String(format: "Heat costs you %.1f%% per step, by your own history.", abs(cost)))
        } else if read.nonIdealCount > 0, read.nonIdealCount < EfficiencyIndexBuilder.minHeatSessions {
            parts.append("Heat term: NOT YET — \(read.nonIdealCount) of \(EfficiencyIndexBuilder.minHeatSessions) hot sessions.")
        }
        return parts.joined(separator: " ")
    }
}
