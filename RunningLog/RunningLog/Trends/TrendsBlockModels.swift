//
//  TrendsBlockModels.swift
//  RunningLog · Trends
//
//  The derivations behind `TrendsBlockView` — the block-summary surface built
//  2026-08-18 from `trends-simplified-prototype.html`. Pure value types and
//  pure functions: no SwiftUI, no service, no fetch. Everything here is a
//  function of what `TrendsService` already loaded, so the surface adds no
//  request and the numbers can be unit-tested without a view.
//
//  ── ON THE "NO GENERATED PROSE" RULE ────────────────────────────────────
//  `TrendsLegacyTabView` carries a standing rule, learned on 2026-08-03: no
//  generated prose on this tab. Five paragraph generators were culled because
//  they restated the charts while claiming more than the data held — a
//  two-point pace comparison rendered as "the engine is growing under the
//  fatigue".
//
//  This file writes sentences, so it has to say how it stays inside that rule:
//
//    • EVERY sentence is a fixed template with computed numbers slotted in.
//      There is no model, no LLM, no adjective chosen by data. Change the
//      numbers and only the numbers change.
//    • Every clause is arithmetic the athlete could do off the chart beneath
//      it — a difference, a count, a ratio, a rank. Nothing infers cause,
//      trajectory or state of body.
//    • Where a claim needs three points to be honest (a trend), the guard is
//      the same one `ThresholdRead.trendSecPerMonth` uses, and the sentence is
//      omitted rather than hedged when the guard fails.
//
//  The rule was against narration that outran the data. These are captions.
//  If that reads as a distinction without a difference in use, delete the
//  `read` properties and the sections still stand — every one of them is
//  optional at the view layer.
//
//  ── ONE DEFINITION ──────────────────────────────────────────────────────
//  Partial-week handling (days into week, the on-pace projection, the
//  four-week average over COMPLETED weeks only, and the acute:chronic ratio
//  that projects mid-week rather than reading a false spike-down every
//  Monday) is copied deliberately from `VolumeDetailView` in
//  `TrendsDetailViews.swift`, which is canonical. If that file's rules change,
//  change them here in the same commit — see `02-week-mood-one-definition.patch`
//  for what happens when two surfaces disagree about what a week is.
//

import Foundation

// MARK: - Goal

/// The athlete's active race, as much of it as this surface needs.
///
/// Injected by the host rather than fetched here: `TrendsService` owns the
/// timeline request and this file owns no I/O. Nil is a supported state —
/// the plate drops the countdown and reads the window instead.
struct TrendsBlockGoal: Equatable {
    let raceDate: Date
    /// "Marathon", "Half", "10K" — already display-cased by the caller.
    let distanceLabel: String

    /// Whole weeks from today to race day, floored at 0.
    func weeksOut(asOf: Date = Date()) -> Int {
        var cal = Calendar(identifier: .iso8601)
        cal.firstWeekday = 2
        let days = cal.dateComponents([.day],
                                      from: cal.startOfDay(for: asOf),
                                      to: cal.startOfDay(for: raceDate)).day ?? 0
        return max(0, Int((Double(days) / 7.0).rounded()))
    }
}

// MARK: - Load

/// One column of section 01. `monthTick` is set on the first week of a month
/// so the axis can label months without drawing twelve dates.
struct BlockWeekPoint: Identifiable, Equatable {
    let id: String
    let dateLabel: String
    let monthTick: String?
    let miles: Double
    /// Quality miles in the week. Drawn as the sharp end ON TOP of the bar —
    /// the same slow-at-the-base convention `TrendsMoodLanes.zoneStack` uses.
    ///
    /// This replaced a row of key-session dots under the axis (2026-08-18).
    /// The dots were fine at twelve columns and became a grey smear at
    /// twenty-six: every week had one or two, so the row carried no
    /// information at exactly the range where you most want it. A stacked
    /// segment scales to any column width, says HOW MUCH quality rather than
    /// how many sessions, and cannot smear.
    let qualityMiles: Double
    /// Kept for the readout, which still counts sessions — the count is the
    /// thing you check, the miles are the thing you see.
    let keyCount: Int
    /// The week's Monday, for `TrendsWeekDrill`. Empty when the payload had no
    /// week start, in which case the column is not drillable.
    let weekStartISO: String
    let isCurrent: Bool

    /// Quality clamped to the bar it is drawn inside. A backend that ever
    /// reports more quality than total must not draw a segment taller than the
    /// column it sits in.
    var drawableQuality: Double { Swift.min(Swift.max(0, qualityMiles), miles) }
}

/// Where the acute:chronic ratio sits, as a word. The word is what the athlete
/// acts on; the ratio is the evidence, and the view prints both.
enum BlockBalance: String, Equatable {
    case easing, balanced, building, spiking

    init(acwr: Double) {
        switch acwr {
        case ..<0.80: self = .easing
        case ..<1.10: self = .balanced
        case ..<1.30: self = .building
        default:      self = .spiking
        }
    }

    var label: String {
        switch self {
        case .easing:   return "Easing"
        case .balanced: return "Balanced"
        case .building: return "Building"
        case .spiking:  return "Spiking"
        }
    }
}

struct BlockLoad: Equatable {
    let points: [BlockWeekPoint]
    let currentMiles: Double
    let projectedMiles: Double
    let daysIntoWeek: Int
    let isWeekComplete: Bool
    let fourWeekAvg: Double
    let peakMiles: Double
    /// Index into `points`, or nil when the window is empty.
    let peakIndex: Int?
    let acwr: Double
    let totalMiles: Double
    let keySessionCount: Int

    var balance: BlockBalance { BlockBalance(acwr: acwr) }
    var isEmpty: Bool { points.isEmpty }
    var totalQualityMiles: Double { points.reduce(0) { $0 + $1.drawableQuality } }

    /// Weeks between the peak week and the current one. 0 when the peak IS
    /// this week.
    var weeksSincePeak: Int? {
        guard let peakIndex else { return nil }
        return max(0, points.count - 1 - peakIndex)
    }

    /// Section 01's caption. Two clauses, both arithmetic:
    /// where the peak sits, and where this week sits against the baseline.
    var read: String? {
        guard !isEmpty, peakMiles > 0 else { return nil }
        var parts: [String] = []

        if let since = weeksSincePeak {
            let peak = Int(peakMiles.rounded())
            switch since {
            case 0:  parts.append("This is the biggest week in the window, at \(peak) miles.")
            case 1:  parts.append("Your biggest week in this window — \(peak) miles — was last week.")
            default: parts.append("Your biggest week in this window — \(peak) miles — was \(since) weeks ago.")
            }
        }

        let avg = Int(fourWeekAvg.rounded())
        if isWeekComplete {
            let now = Int(currentMiles.rounded())
            let delta = now - avg
            if avg > 0 {
                parts.append(delta == 0
                    ? "This week finished level with the four-week average of \(avg)."
                    : "This week finished \(abs(delta)) \(delta > 0 ? "over" : "under") the four-week average of \(avg).")
            }
        } else if avg > 0 {
            let proj = Int(projectedMiles.rounded())
            let delta = proj - avg
            let tail = delta == 0
                ? "level with the four-week average of \(avg)"
                : "\(abs(delta)) \(delta > 0 ? "over" : "under") the four-week average of \(avg)"
            parts.append("Day \(daysIntoWeek) of 7, on pace for \(proj) — \(tail).")
        }

        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    static let empty = BlockLoad(
        points: [], currentMiles: 0, projectedMiles: 0, daysIntoWeek: 1,
        isWeekComplete: false, fourWeekAvg: 0, peakMiles: 0, peakIndex: nil,
        acwr: 1.0, totalMiles: 0, keySessionCount: 0
    )
}

// MARK: - Threshold

/// One session of section 02, positioned on the same week axis as section 01
/// so the two charts can be read straight down.
struct BlockThresholdPoint: Identifiable, Equatable {
    let id: String
    let dateLabel: String
    /// Index into `BlockLoad.points`. -1 when the session predates the window.
    let weekIndex: Int
    let minutes: Double
    let adjSec: Int
}

struct BlockThreshold: Equatable {
    let points: [BlockThresholdPoint]
    let weekCount: Int
    /// Seconds per mile per month, negative = getting faster. Nil under three
    /// sessions — the same guard `ThresholdRead.trendSecPerMonth` applies.
    let trendSecPerMonth: Double?
    let anchorLabel: String

    var isEmpty: Bool { points.count < 2 }
    var latest: BlockThresholdPoint? { points.last }
    var first: BlockThresholdPoint? { points.first }
    var totalMinutes: Double { points.reduce(0) { $0 + $1.minutes } }
    var longest: BlockThresholdPoint? { points.max { $0.minutes < $1.minutes } }

    /// Minutes in the last three sessions against the first three, as a
    /// percentage. Nil under six sessions — below that the comparison is two
    /// noisy numbers, not a change.
    var minutesChangePct: Int? {
        guard points.count >= 6 else { return nil }
        let firstThree = points.prefix(3).reduce(0) { $0 + $1.minutes }
        let lastThree = points.suffix(3).reduce(0) { $0 + $1.minutes }
        guard firstThree > 0 else { return nil }
        return Int((((lastThree - firstThree) / firstThree) * 100).rounded())
    }

    /// Pace difference between the first and last session, seconds per mile.
    /// Negative = the later session was faster.
    var paceDeltaSec: Int? {
        guard let a = first, let b = latest, points.count >= 2 else { return nil }
        return b.adjSec - a.adjSec
    }

    /// Section 02's caption — the two end sessions, stated. No trend claim
    /// unless `trendSecPerMonth` cleared its own three-point guard, and even
    /// then the sentence reports the fitted slope rather than the endpoints.
    var read: String? {
        guard let a = first, let b = latest, !isEmpty else { return nil }
        let m0 = Int(a.minutes.rounded()), m1 = Int(b.minutes.rounded())
        var s = "Last session: \(m1) minutes in band at \(TrendsBlockFormat.pace(b.adjSec))/mi. "
            + "First in this window: \(m0) at \(TrendsBlockFormat.pace(a.adjSec))/mi."
        if let slope = trendSecPerMonth, abs(slope) >= 1 {
            let dir = slope < 0 ? "faster" : "slower"
            s += " Across every session the band pace is trending \(Int(abs(slope).rounded()))s/mi per month \(dir)."
        }
        return s
    }

    static let empty = BlockThreshold(points: [], weekCount: 0,
                                      trendSecPerMonth: nil, anchorLabel: "")
}

// MARK: - Mix

/// Where the miles fell, folded from the ten-zone taxonomy into the three
/// bands an athlete acts on. Token → band mapping mirrors
/// `TrendsMoodLanes.zoneStack`, which is the canonical order.
struct BlockMix: Equatable {
    let easyMiles: Double
    /// Moderate + steady — between easy and marathon pace.
    let greyMiles: Double
    /// Marathon pace and faster.
    let qualityMiles: Double
    /// Miles logged with no lap breakdown. Never guessed at, never folded into
    /// a band, always stated — see the `hasZoneBreakdown` contract.
    let unclassifiedMiles: Double

    var classifiedMiles: Double { easyMiles + greyMiles + qualityMiles }
    var isEmpty: Bool { classifiedMiles <= 0 }

    func pct(_ miles: Double) -> Int {
        guard classifiedMiles > 0 else { return 0 }
        return Int(((miles / classifiedMiles) * 100).rounded())
    }

    var easyPct: Int { pct(easyMiles) }
    var greyPct: Int { pct(greyMiles) }
    var qualityPct: Int { pct(qualityMiles) }

    var read: String? {
        guard !isEmpty else { return nil }
        return "\(greyPct)% of your classified miles are moderate or steady — "
            + "faster than easy, slower than marathon pace."
    }

    static let empty = BlockMix(easyMiles: 0, greyMiles: 0,
                                qualityMiles: 0, unclassifiedMiles: 0)

    /// slow → fast, matching `TrendsMoodLanes.zoneStack`.
    static let easyTokens: Set<String> = ["recovery", "easy"]
    static let greyTokens: Set<String> = ["moderate", "steady"]
    static let qualityTokens: Set<String> = ["mp", "hmp", "lt", "10k", "5k", "3k", "mile"]
}

// MARK: - Moments

/// One row of section 04. Picked by a rule, never by a model: each moment is
/// the maximum of one column over the window, so the same block always
/// produces the same three rows.
struct BlockMoment: Identifiable, Equatable {
    let id: String
    /// "BIGGEST WEEK"
    let kicker: String
    /// "75 miles"
    let value: String
    /// The arithmetic that made it notable. Nil when there is nothing true to
    /// add — an empty line is better than a padded one.
    let note: String?
    let dateLabel: String
}

// MARK: - Focus

/// Section 05. A rule set, first match wins; nil hides the section entirely.
/// Thresholds are stated here rather than buried in the view so they can be
/// argued with in one place.
struct BlockFocus: Equatable {
    let title: String
    let body: String

    static func make(mix: BlockMix, load: BlockLoad, threshold: BlockThreshold) -> BlockFocus? {
        // 1 · The grey zone. The most common shape in a marathon build and the
        //     cheapest to fix, so it leads when it's present.
        if !mix.isEmpty, mix.greyPct >= 30 {
            let miles = Int(mix.greyMiles.rounded())
            let total = Int(mix.classifiedMiles.rounded())
            return BlockFocus(
                title: "The grey zone",
                body: "\(miles) of your \(total) classified miles are moderate or steady — "
                    + "too hard to recover from, too slow to build speed. "
                    + "Running those easy costs nothing and leaves more for the hard days."
            )
        }
        // 2 · Not enough easy. Polarised training's floor is usually put at 75–80%;
        //     65 is the point where it is a fact about the block, not a rounding.
        if !mix.isEmpty, mix.easyPct < 65 {
            return BlockFocus(
                title: "Not enough easy",
                body: "\(mix.easyPct)% of your classified miles are easy. "
                    + "Most marathon blocks run 75–80% easy — the gap is where recovery goes."
            )
        }
        // 3 · The ramp. Reads the same ratio the chip prints, so the two can
        //     never disagree.
        if load.balance == .spiking {
            return BlockFocus(
                title: "The ramp",
                body: String(format: "Acute load is running at %.2f of chronic. ", load.acwr)
                    + "Above 1.30 the week is outpacing what the last four built."
            )
        }
        // 4 · Thin quality. Only when there is enough of a window to say so.
        if load.points.count >= 6, load.keySessionCount < load.points.count / 2 {
            return BlockFocus(
                title: "Thin on quality",
                body: "\(load.keySessionCount) key sessions across \(load.points.count) weeks. "
                    + "Under one every other week, the hard days stop compounding."
            )
        }
        // 5 · Threshold holding. The positive case — stated only when the
        //     minutes comparison cleared its six-session guard.
        if let pct = threshold.minutesChangePct, pct >= 20 {
            return BlockFocus(
                title: "Threshold is holding",
                body: "Time in band is up \(pct)% across this window. "
                    + "Nothing in the load or the mix argues against another block of it."
            )
        }
        return nil
    }
}

// MARK: - The read

/// Everything section 01–05 needs, built once per render.
struct TrendsBlockRead: Equatable {
    let load: BlockLoad
    let threshold: BlockThreshold
    let mix: BlockMix
    let moments: [BlockMoment]
    let focus: BlockFocus?
    let goal: TrendsBlockGoal?

    var weekCount: Int { load.points.count }
    var isEmpty: Bool { load.isEmpty }
}

// MARK: - Builder

enum TrendsBlockBuilder {

    /// Build the whole surface from what the service already holds.
    ///
    /// - Parameters:
    ///   - weeks: the tab's window, oldest first. The LAST element is always
    ///     the current in-progress week — the same contract `VolumeDetailView`
    ///     relies on.
    ///   - days: every day in the fetch. Filtered to the window here.
    ///   - keySessions: every key session in the fetch. Filtered to the window.
    ///   - threshold: the already-built `ThresholdRead`, or nil when the
    ///     backend predates `band_laps` and no fallback was available.
    ///   - goal: the athlete's active race, or nil.
    ///   - canonicalAcwr: the intensity-weighted ratio from `athlete_state`
    ///     when it is built. Preferred over the miles-based fallback so this
    ///     surface prints the same number as every other one.
    static func build(
        weeks: [TrendsWeek],
        days: [TrendsDay],
        keySessions: [KeySession],
        threshold: ThresholdRead?,
        goal: TrendsBlockGoal?,
        canonicalAcwr: Double? = nil,
        asOf: Date = Date()
    ) -> TrendsBlockRead {

        let load = buildLoad(weeks: weeks, keySessions: keySessions,
                             canonicalAcwr: canonicalAcwr, asOf: asOf)
        let windowStart = weeks.first?.weekStart ?? ""
        let windowDays = days.filter { windowStart.isEmpty || $0.date >= windowStart }
        let windowKeys = keySessions.filter { windowStart.isEmpty || $0.date >= windowStart }

        let band = buildThreshold(threshold, weeks: weeks, windowStart: windowStart)
        let mix = buildMix(days: windowDays)
        let moments = buildMoments(load: load, weeks: weeks, days: windowDays,
                                   keySessions: windowKeys, threshold: band)

        return TrendsBlockRead(
            load: load,
            threshold: band,
            mix: mix,
            moments: moments,
            focus: BlockFocus.make(mix: mix, load: load, threshold: band),
            goal: goal
        )
    }

    // MARK: 01 · load

    static func buildLoad(
        weeks: [TrendsWeek],
        keySessions: [KeySession],
        canonicalAcwr: Double?,
        asOf: Date
    ) -> BlockLoad {
        guard !weeks.isEmpty else { return .empty }

        // Key sessions per week: a session belongs to the last week whose
        // start is on or before its date. Weeks arrive oldest-first.
        var keyCounts = [Int](repeating: 0, count: weeks.count)
        for session in keySessions {
            var idx: Int?
            for (i, w) in weeks.enumerated() where !w.weekStart.isEmpty && w.weekStart <= session.date {
                idx = i
            }
            if let idx { keyCounts[idx] += 1 }
        }

        var lastMonth: String?
        var points: [BlockWeekPoint] = []
        for (i, w) in weeks.enumerated() {
            let tick = (w.month != lastMonth) ? w.month.uppercased() : nil
            lastMonth = w.month
            points.append(BlockWeekPoint(
                id: w.weekStart.isEmpty ? "wk-\(i)" : w.weekStart,
                dateLabel: w.dateLabel,
                monthTick: tick,
                miles: w.miles,
                qualityMiles: w.qualityMiles,
                keyCount: keyCounts[i],
                weekStartISO: w.weekStart,
                isCurrent: i == weeks.count - 1
            ))
        }

        // — partial-week rules, copied from VolumeDetailView (see file note) —
        var cal = Calendar(identifier: .iso8601)
        cal.firstWeekday = 2
        let weekday = cal.component(.weekday, from: asOf)
        let daysIntoWeek = ((weekday + 5) % 7) + 1
        let isComplete = daysIntoWeek >= 7

        let current = weeks[weeks.count - 1].miles
        let projected = isComplete
            ? current
            : (daysIntoWeek > 0 ? (current / Double(daysIntoWeek) * 7).rounded() : current)

        let completed = weeks.dropLast().filter { $0.miles > 0 }
        let last4 = Array(completed.suffix(4))
        let avg4 = last4.isEmpty ? 0 : last4.map(\.miles).reduce(0, +) / Double(last4.count)

        let peak = weeks.map(\.miles).max() ?? 0
        let peakIndex = weeks.firstIndex { $0.miles == peak }

        let acwr: Double = {
            if let canonicalAcwr { return canonicalAcwr }
            guard avg4 > 0 else { return 1.0 }
            return (isComplete ? current : projected) / avg4
        }()

        return BlockLoad(
            points: points,
            currentMiles: current,
            projectedMiles: projected,
            daysIntoWeek: daysIntoWeek,
            isWeekComplete: isComplete,
            fourWeekAvg: avg4,
            peakMiles: peak,
            peakIndex: peakIndex,
            acwr: acwr,
            totalMiles: weeks.map(\.miles).reduce(0, +),
            keySessionCount: keyCounts.reduce(0, +)
        )
    }

    // MARK: 02 · threshold

    static func buildThreshold(
        _ read: ThresholdRead?,
        weeks: [TrendsWeek],
        windowStart: String
    ) -> BlockThreshold {
        guard let read, !read.isEmpty else { return .empty }
        // Work sessions only. Cruise and unclassed points are in the read for
        // the detail view's ledger; a fitness caption should not average a
        // tempo the HR floor already said wasn't threshold.
        let work = read.workPoints.filter { windowStart.isEmpty || $0.date >= windowStart }
        guard !work.isEmpty else { return .empty }

        let starts = weeks.map(\.weekStart)
        func weekIndex(for date: String) -> Int {
            var idx = -1
            for (i, s) in starts.enumerated() where !s.isEmpty && s <= date { idx = i }
            return idx
        }

        let points = work.map {
            BlockThresholdPoint(
                id: $0.id,
                dateLabel: $0.dateLabel,
                weekIndex: weekIndex(for: $0.date),
                minutes: $0.minutes,
                adjSec: $0.adjSec
            )
        }

        return BlockThreshold(
            points: points,
            weekCount: weeks.count,
            trendSecPerMonth: read.trendSecPerMonth,
            anchorLabel: read.anchor.label
        )
    }

    // MARK: 03 · mix

    static func buildMix(days: [TrendsDay]) -> BlockMix {
        var easy = 0.0, grey = 0.0, quality = 0.0, unclassified = 0.0
        for day in days {
            guard let zones = day.zoneMiles, !zones.isEmpty else {
                unclassified += day.miles
                continue
            }
            var seen = 0.0
            for (token, miles) in zones {
                let key = token.lowercased()
                if BlockMix.easyTokens.contains(key) { easy += miles }
                else if BlockMix.greyTokens.contains(key) { grey += miles }
                else if BlockMix.qualityTokens.contains(key) { quality += miles }
                else { continue }
                seen += miles
            }
            // A day whose laps only partly classify still has honest miles in
            // the gap. They go to unclassified rather than inflating a band.
            unclassified += max(0, day.miles - seen)
        }
        return BlockMix(easyMiles: easy, greyMiles: grey,
                        qualityMiles: quality, unclassifiedMiles: unclassified)
    }

    // MARK: 04 · moments

    static func buildMoments(
        load: BlockLoad,
        weeks: [TrendsWeek],
        days: [TrendsDay],
        keySessions: [KeySession],
        threshold: BlockThreshold
    ) -> [BlockMoment] {
        var out: [BlockMoment] = []

        // Biggest week — completed weeks only. A partial week cannot win a
        // superlative it hasn't finished earning.
        let completed = weeks.dropLast()
        if let big = completed.max(by: { $0.miles < $1.miles }), big.miles > 0 {
            let keys = load.points.first { $0.id == big.weekStart }?.keyCount ?? 0
            out.append(BlockMoment(
                id: "week-\(big.weekStart)",
                kicker: "Biggest week",
                value: "\(Int(big.miles.rounded())) miles",
                note: keys > 0 ? "\(keys) key session\(keys == 1 ? "" : "s") inside it." : nil,
                dateLabel: "wk of \(big.dateLabel)"
            ))
        }

        // Longest RUN, not longest day. `TrendsDay.runs` is uploads — a track
        // session stopped between warm-up, reps and cool-down is three of
        // them — so the day is folded through `TrendsDay.sessions(from:)`,
        // which is the app's one answer to "what is one run". A double day
        // must not win this row by summing two runs into one superlative.
        //
        // Empty `runs` means the payload predates the field, which the
        // contract on `TrendsDay.runs` says to read as "cannot say", never as
        // "did not run" — so that day falls back to its total.
        var longestMiles = 0.0
        var longestDate = ""
        var longestSeconds: Double?
        for day in days {
            if day.runs.isEmpty {
                guard day.miles > longestMiles else { continue }
                longestMiles = day.miles
                longestDate = day.date
                longestSeconds = day.durationMin.map { Double($0) * 60 }
            } else {
                for run in TrendsDay.sessions(from: day.runs) where run.miles > longestMiles {
                    longestMiles = run.miles
                    longestDate = day.date
                    longestSeconds = run.durationSec
                }
            }
        }
        if longestMiles > 0 {
            let note: String? = longestSeconds.map { secs in
                let total = Int(secs.rounded())
                let h = total / 3600, m = (total % 3600) / 60
                return h > 0 ? "\(h)h \(m)m on the feet." : "\(m) minutes on the feet."
            }
            out.append(BlockMoment(
                id: "day-\(longestDate)",
                kicker: "Longest run",
                value: String(format: "%.1f mi", longestMiles),
                note: note,
                dateLabel: TrendsBlockFormat.shortDate(longestDate)
            ))
        }

        // The biggest threshold session, or the fastest key session when there
        // is no band data. One row either way — never both, never neither.
        if let best = threshold.longest {
            out.append(BlockMoment(
                id: "band-\(best.id)",
                kicker: "Most time at threshold",
                value: "\(Int(best.minutes.rounded())) min in band",
                note: "Held \(TrendsBlockFormat.pace(best.adjSec))/mi.",
                dateLabel: best.dateLabel
            ))
        } else if let fast = keySessions.filter({ !$0.isLongRun })
            .min(by: { $0.effectivePaceSec < $1.effectivePaceSec }) {
            out.append(BlockMoment(
                id: "key-\(fast.id)",
                kicker: "Fastest key session",
                value: "\(TrendsBlockFormat.pace(fast.effectivePaceSec))/mi",
                note: fast.structure,
                dateLabel: fast.dateLabel
            ))
        }

        return out
    }
}

// MARK: - Formatting

enum TrendsBlockFormat {
    /// 316 → "5:16".
    static func pace(_ sec: Int) -> String {
        guard sec > 0 else { return "—" }
        return String(format: "%d:%02d", sec / 60, sec % 60)
    }

    /// "2026-07-27" → "Jul 27".
    static func shortDate(_ iso: String) -> String {
        let parts = iso.split(separator: "-")
        guard parts.count == 3, let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m) else { return iso }
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                      "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return "\(months[m - 1]) \(d)"
    }

    /// Spelled-out small numbers for the plate, which is display type and
    /// reads badly with digits. Falls back to digits past twenty.
    static func spelled(_ n: Int) -> String {
        let words = ["zero", "one", "two", "three", "four", "five", "six",
                     "seven", "eight", "nine", "ten", "eleven", "twelve",
                     "thirteen", "fourteen", "fifteen", "sixteen", "seventeen",
                     "eighteen", "nineteen", "twenty"]
        return (0...20).contains(n) ? words[n] : "\(n)"
    }
}
