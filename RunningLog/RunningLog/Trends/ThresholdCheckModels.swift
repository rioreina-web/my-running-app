//
//  ThresholdCheckModels.swift
//  RunningLog · Trends
//
//  Substrate for Trends section 05 — the threshold check. Section 04 draws the
//  band; this asks the only question it can't: is the band still right?
//
//  It answers from evidence, states what it cannot test, and **never moves the
//  band**. The athlete moves the band. Every competitor silently re-estimates
//  threshold and slides the number under the runner; that is the one thing
//  this app must not do (`CLAUDE.md` — observation, never prescription).
//
//  Spec and validation: `THRESHOLD-CHECK-APPLY.md`. Two of the three
//  estimators drafted for this surface died against real data (§V there):
//    · decoupling cannot locate threshold from long runs 15% off the band —
//      it tracks DURATION (R² 0.20) more than pace (R² 0.09). Hence the hard
//      ±5% gate, and UNTESTED as a first-class verdict rather than a failure.
//    · a rep-HR regression fit R² 0.775 and reported a tidy −5.8 bpm/30d from
//      5 observations and 4 parameters; leave-one-out swung it −19…+70 and
//      flipped its sign. Cut entirely rather than shipped with a caveat.
//  What survives: sustained tests (E1, the only verdict driver), efficiency
//  drift at band pace (E2, context, null-reporting), anchor age (E3, context).
//
//  No SwiftUI in this file — the rules are testable without a renderer.
//

import Foundation

// MARK: - Effort

/// One continuous effort that qualified to test the band.
struct ThresholdEffort: Identifiable {
    /// How the effort read against the band.
    enum Reading: String {
        /// Decoupling at or under `holdsPct` — the band was sustainable.
        case held
        /// Decoupling at or over `failsPct` — it was not.
        case failed
        /// Between the two. Says so rather than rounding to a side.
        case inconclusive
    }

    let id: String          // training_log_id, so a tap can open the workout
    let date: String
    let dateLabel: String
    let name: String
    /// Heat-neutral pace the effort is judged at (sec/mi).
    let paceSec: Int
    /// Signed deviation from the band anchor, percent. Negative = faster.
    let devPct: Double
    let durationMin: Double
    let decouplingPct: Double
    /// Heat mattered — the backend supplied a different neutral pace.
    let inHeat: Bool
    let reading: Reading

    /// Comfortably sustainable, not merely sustainable. Feeds MAY BE SLOW.
    var heldByMargin: Bool {
        reading == .held && decouplingPct <= ThresholdCheckBuilder.marginPct
    }
}

// MARK: - Verdict

enum ThresholdVerdict: String {
    /// Not enough qualifying evidence. The honest answer for most athletes
    /// most of the time — and it names what is missing.
    case untested
    /// The evidence agrees with the band.
    case consistent
    /// Efforts at band pace did not hold.
    case mayBeFast
    /// Efforts at band pace held comfortably, every one of them.
    case mayBeSlow
    /// A may-be-fast reading whose failing efforts were all run in heat.
    /// Heat inflates cardiac drift; a harsh verdict built on hot-day drift is
    /// a verdict about weather. Demoted, and the words say why.
    case heatConfounded

    var label: String {
        switch self {
        case .untested: "UNTESTED"
        case .consistent: "CONSISTENT"
        case .mayBeFast: "BAND MAY BE FAST"
        case .mayBeSlow: "BAND MAY BE SLOW"
        case .heatConfounded: "HEAT CONFOUNDED"
        }
    }
}

// MARK: - Drift

/// Efficiency at band pace, first half of the window against the second.
/// Context only — it can never carry a verdict on its own.
struct EfficiencyDrift {
    /// Point estimate, percent.
    let pct: Double
    /// Jackknife bounds, percent.
    let loPct: Double
    let hiPct: Double
    /// True only when the jackknife excludes zero. False means the honest
    /// output is "no change beyond ±x%" — a null with a stated resolution is
    /// a finding; a direction pulled out of noise is a lie.
    var isDirectional: Bool { loPct * hiPct > 0 }
    /// The resolution to quote when it isn't directional.
    var resolutionPct: Double { max(abs(loPct), abs(hiPct)) }
}

// MARK: - Read

struct ThresholdCheckRead {
    let verdict: ThresholdVerdict
    /// Every qualifying effort, oldest → newest.
    let efforts: [ThresholdEffort]
    /// The band this was measured against.
    let anchorSec: Int?
    let anchorLabel: String
    /// Days since the anchor pace last CHANGED in the ladder sequence.
    let anchorAgeDays: Int?
    let drift: EfficiencyDrift?
    /// Continuous efforts in the window that failed only the ±5% gate — the
    /// count makes "nothing tested your band" concrete instead of abstract.
    let nearMissCount: Int
    /// The closest any continuous effort came to the band, percent.
    let closestDevPct: Double?

    var isEmpty: Bool { anchorSec == nil }
    var held: Int { efforts.filter { $0.reading == .held }.count }
    var failed: Int { efforts.filter { $0.reading == .failed }.count }
}

// MARK: - Builder

enum ThresholdCheckBuilder {

    /// An effort must run this long before drift has had time to appear.
    static let minMinutes: Double = 20
    /// **The gate that matters.** Decoupling on a run well off the band tests
    /// sustainability there, not at threshold — validated the hard way (§V).
    static let tolerancePct: Double = 5
    /// Conventional aerobic-decoupling reading.
    static let holdsPct: Double = 5
    static let failsPct: Double = 8
    /// Held *comfortably* — the bar for suggesting the band may be slow.
    static let marginPct: Double = 3
    /// One session is a day, not a trend.
    static let minEfforts = 2

    static func build(
        fastSessions: [FastSession],
        keySessions: [KeySession],
        bandLaps: BandLaps?,
        settings: BandSettings,
        window: TrendsWindow,
        asOf: Date = Date()
    ) -> ThresholdCheckRead {

        let today = Int(asOf.timeIntervalSince1970 / 86_400)
        let from: Int
        let to: Int
        switch window {
        case .custom(let a, let b):
            from = Int(a.timeIntervalSince1970 / 86_400)
            to = Int(b.timeIntervalSince1970 / 86_400)
        default:
            from = today - window.days + 1
            to = today
        }

        // The band, read from the one store, resolved through the ladder
        // exactly as `KeyPaceModels.steps(ladders:anchor:)` resolves it.
        let ladders = (bandLaps?.sessions ?? [])
            .map { (day: ThresholdRead.dayNumber($0.date), ladder: $0.anchors) }
            .sorted { $0.day < $1.day }
        guard let latest = ladders.last?.ladder else {
            return ThresholdCheckRead(
                verdict: .untested, efforts: [], anchorSec: nil,
                anchorLabel: settings.anchor.label, anchorAgeDays: nil,
                drift: nil, nearMissCount: 0, closestDevPct: nil
            )
        }
        let anchorSec = settings.anchor.sec(in: latest)
        guard anchorSec > 0 else {
            return ThresholdCheckRead(
                verdict: .untested, efforts: [], anchorSec: nil,
                anchorLabel: settings.anchor.label, anchorAgeDays: nil,
                drift: nil, nearMissCount: 0, closestDevPct: nil
            )
        }

        // E3 · anchor age — days since the anchor pace last CHANGED. A ladder
        // that arrives weekly with the same number has not re-anchored.
        var anchorAge: Int?
        var changedDay: Int?
        for entry in ladders.reversed() {
            if settings.anchor.sec(in: entry.ladder) != anchorSec { break }
            changedDay = entry.day
        }
        if let changedDay { anchorAge = max(0, today - changedDay) }

        // E1 · sustained tests.
        var efforts: [ThresholdEffort] = []
        var nearMiss = 0
        var closest: Double?

        for s in fastSessions {
            let day = ThresholdRead.dayNumber(s.date)
            guard day >= from, day <= to else { continue }
            guard s.isContinuous else { continue }

            let pace = s.neutralPaceSec ?? s.avgPaceSec
            guard pace > 0, s.fastMiles > 0 else { continue }
            let minutes = s.fastMiles * Double(pace) / 60
            guard minutes >= minMinutes else { continue }

            let dev = 100 * (Double(pace) - Double(anchorSec)) / Double(anchorSec)
            if closest == nil || abs(dev) < abs(closest ?? .infinity) { closest = dev }

            guard abs(dev) <= tolerancePct else { nearMiss += 1; continue }
            guard let decoupling = s.decouplingPct else { continue }

            let reading: ThresholdEffort.Reading =
                decoupling <= holdsPct ? .held
                : decoupling >= failsPct ? .failed
                : .inconclusive

            efforts.append(ThresholdEffort(
                id: s.id,
                date: s.date,
                dateLabel: s.dateLabel,
                name: s.name,
                paceSec: pace,
                devPct: dev,
                durationMin: minutes,
                decouplingPct: decoupling,
                inHeat: s.neutralPaceSec != nil && s.neutralPaceSec != s.avgPaceSec,
                reading: reading
            ))
        }
        efforts.sort { $0.date < $1.date }

        // E2 · efficiency drift at band pace — context, null-reporting.
        let drift = EfficiencyIndexBuilder.driftAtBand(
            sessions: keySessions,
            anchorSec: anchorSec,
            from: from,
            to: to
        )

        // Verdict.
        let verdict = self.verdict(efforts: efforts)

        return ThresholdCheckRead(
            verdict: verdict,
            efforts: efforts,
            anchorSec: anchorSec,
            anchorLabel: settings.anchor.label,
            anchorAgeDays: anchorAge,
            drift: drift,
            nearMissCount: nearMiss,
            closestDevPct: closest
        )
    }

    /// Verdict from the sustained tests alone. Drift never votes.
    static func verdict(efforts: [ThresholdEffort]) -> ThresholdVerdict {
        let decisive = efforts.filter { $0.reading != .inconclusive }
        guard decisive.count >= minEfforts else { return .untested }

        let failed = decisive.filter { $0.reading == .failed }
        let held = decisive.filter { $0.reading == .held }

        if failed.count > held.count {
            // Heat inflates cardiac drift. A harsh verdict resting entirely on
            // hot-day efforts is a verdict about the weather. Conservative
            // direction: heat can prevent a harsh call, never create one.
            if failed.allSatisfy(\.inHeat) { return .heatConfounded }
            return .mayBeFast
        }
        if failed.isEmpty {
            // Every effort held, and every one of them by a margin.
            if held.count >= minEfforts, held.allSatisfy(\.heldByMargin) { return .mayBeSlow }
            return .consistent
        }
        return .consistent
    }
}

// MARK: - Prose

/// Derived observation. Never authored copy: every number in the sentence is a
/// number already on screen, and no sentence contains an instruction.
enum ThresholdCheckProse {

    static func headline(_ read: ThresholdCheckRead) -> String {
        guard let anchor = read.anchorSec else {
            return "No band to check yet."
        }
        let pace = TrendsFormat.pace(anchor)
        switch read.verdict {
        case .untested:
            return "Your \(read.anchorLabel) band reads \(pace). Nothing in this window tested it."
        case .consistent:
            return "Your \(read.anchorLabel) band reads \(pace), and \(read.efforts.count) efforts at that pace held."
        case .mayBeFast:
            return "Your \(read.anchorLabel) band reads \(pace). \(read.failed) efforts at that pace did not hold."
        case .mayBeSlow:
            return "Your \(read.anchorLabel) band reads \(pace), and every effort at that pace held comfortably."
        case .heatConfounded:
            return "Your \(read.anchorLabel) band reads \(pace). The efforts that missed it were all run in heat."
        }
    }

    static func note(_ read: ThresholdCheckRead) -> String? {
        guard read.anchorSec != nil else { return nil }
        var parts: [String] = []

        switch read.verdict {
        case .untested:
            if let closest = read.closestDevPct {
                parts.append(String(
                    format: "The closest sustained effort ran %.0f%% %@ the band, outside the %.0f%% window this check reads.",
                    abs(closest), closest > 0 ? "slower than" : "faster than",
                    ThresholdCheckBuilder.tolerancePct
                ))
            } else {
                parts.append("No continuous effort of \(Int(ThresholdCheckBuilder.minMinutes)) minutes or more in this window.")
            }
            if read.efforts.count == 1 {
                parts.append("One effort cleared the window; this reads two before it says anything.")
            }
        case .consistent, .mayBeSlow:
            parts.append("\(read.held) of \(read.efforts.count) efforts at band pace held under \(Int(ThresholdCheckBuilder.holdsPct))% drift.")
        case .mayBeFast:
            parts.append("\(read.failed) of \(read.efforts.count) efforts at band pace drifted past \(Int(ThresholdCheckBuilder.failsPct))%.")
        case .heatConfounded:
            parts.append("Heat raises drift on its own, so this cannot separate a fast band from a hot morning.")
        }

        if let drift = read.drift {
            if drift.isDirectional {
                parts.append(String(format: "Efficiency at band pace moved %+.1f%% across the window.", drift.pct))
            } else {
                parts.append(String(format: "Efficiency at band pace shows no change beyond %.0f%%.", drift.resolutionPct))
            }
        }

        if let age = read.anchorAgeDays, age >= 14 {
            parts.append("The band has read this number for \(age / 7) weeks.")
        }

        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}
