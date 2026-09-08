//
//  TrendsBandSettings.swift
//  RunningLog · Trends
//
//  The four decisions the athlete makes about her own threshold band, and
//  where they persist.
//
//  Every one of these was a constant somewhere until 2026-08-05: the ±5% skirt
//  and the two-minute gate were hardcoded in `paceBands.ts`, the anchor was a
//  two-case enum, and the 160 bpm floor was a `static let` with a comment
//  admitting it was tuned on nineteen sessions of one athlete's data. Making
//  them settings is not a preferences feature — it is the admission that the
//  right values are the athlete's to find, and that the honest default is the
//  one you can see and move.
//
//  **The edges are independent, and that is the point.** The 2026-08-02 band
//  audit found the leak on the SLOW edge: long-run cruising miles drifting into
//  the band and taking 49 minutes of threshold credit with them. A symmetric
//  ±% can only fix that by also tightening the fast edge, which throws away
//  genuine hard work to solve a problem the fast edge never had. Two edges,
//  set separately, fix the leak where the leak is.
//
//  No SwiftUI in the value type — the rules are testable without a renderer.
//

import Foundation
import SwiftUI

// MARK: - Settings

/// How the threshold band is drawn and what counts as being in it.
struct BandSettings: Equatable, Codable {

    /// What the band sits on.
    var anchor: BandAnchor

    /// The fast edge, as a percentage BELOW the anchor. `5` → `anchor × 0.95`.
    var fastPct: Double

    /// The slow edge, as a percentage ABOVE the anchor. `5` → `anchor × 1.05`.
    var slowPct: Double

    /// Minutes a session must hold in the band, summed across the run, before
    /// it counts as band work at all.
    var minTotalMinutes: Double

    /// Minutes of ONE unbroken stretch a session must hold. Catches what the
    /// total cannot: a long run that clips the band four times for three
    /// minutes each totals twelve honest minutes and is still not a threshold
    /// session.
    var minBlockMinutes: Double

    /// Average heart rate over the in-band minutes required to grade them as
    /// work. `0` turns the floor off — every in-band minute then counts, which
    /// is the right setting for an athlete training without a strap and the
    /// wrong one for anybody else.
    var hrFloor: Int

    // MARK: Limits

    static let pctRange: ClosedRange<Double> = 0...12
    static let pctStep: Double = 0.5
    static let minutesRange: ClosedRange<Double> = 0...45
    static let blockRange: ClosedRange<Double> = 0...30
    static let hrFloorRange: ClosedRange<Int> = 120...190

    /// The shipped starting point.
    ///
    /// Anchor and skirt reproduce exactly what the section drew before it had
    /// controls (half-marathon, ±5%), so turning the controls on doesn't
    /// silently restate the athlete's history. The two minimums do NOT: the
    /// old two-second-hand gate was 2 minutes, which is what let the drive-bys
    /// in. 8 total and 5 unbroken is the deliberate change.
    static let `default` = BandSettings(
        anchor: .hmp,
        fastPct: 5,
        slowPct: 5,
        minTotalMinutes: 8,
        minBlockMinutes: 5,
        hrFloor: 160
    )

    /// The band edges around one week's anchor, sec/mile. `fast` is the lower
    /// number — faster pace, drawn higher.
    func edges(anchorSec: Int) -> (fast: Int, slow: Int) {
        let a = Double(anchorSec)
        return (
            fast: Int((a * (1 - fastPct / 100)).rounded()),
            slow: Int((a * (1 + slowPct / 100)).rounded())
        )
    }

    /// True when this pace falls inside the band around `anchorSec`.
    /// Edges are inclusive, matching `paceBands.ts`'s BETWEEN.
    func contains(paceSec: Int, anchorSec: Int) -> Bool {
        let e = edges(anchorSec: anchorSec)
        return paceSec >= e.fast && paceSec <= e.slow
    }

    /// True when the athlete has moved anything off the shipped defaults —
    /// drives the "reset" affordance and the "adjusted" marker on the read.
    var isDefault: Bool { self == .default }

    /// Every value forced back inside its range. Applied on decode so a blob
    /// written by a future build (or a hand-edited one) can't produce a band
    /// with a negative width or a 6000-second minimum.
    func clamped() -> BandSettings {
        var s = self
        s.fastPct = min(max(fastPct, Self.pctRange.lowerBound), Self.pctRange.upperBound)
        s.slowPct = min(max(slowPct, Self.pctRange.lowerBound), Self.pctRange.upperBound)
        s.minTotalMinutes = min(
            max(minTotalMinutes, Self.minutesRange.lowerBound), Self.minutesRange.upperBound
        )
        s.minBlockMinutes = min(
            max(minBlockMinutes, Self.blockRange.lowerBound), Self.blockRange.upperBound
        )
        if hrFloor != 0 {
            s.hrFloor = min(max(hrFloor, Self.hrFloorRange.lowerBound), Self.hrFloorRange.upperBound)
        }
        // A band with no width can never hold a lap. Rather than render an
        // empty chart and let the athlete wonder, give the tightest real band.
        if s.fastPct == 0 && s.slowPct == 0 { s.slowPct = Self.pctStep }
        return s
    }

    /// "±5%" when symmetric, "−5% / +2%" when not. The controls and the read
    /// share this so they can't describe the same band differently.
    var widthLabel: String {
        let f = Self.pctText(fastPct)
        let s = Self.pctText(slowPct)
        return fastPct == slowPct ? "±\(f)%" : "−\(f)% / +\(s)%"
    }

    static func pctText(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }
}

// MARK: - Custom-pace parsing

extension BandSettings {

    /// "5:35" → 335 sec/mile. Also accepts a bare seconds count ("335") and
    /// tolerates surrounding whitespace. Returns nil for anything that isn't a
    /// plausible running pace, so a typo can't anchor the band at 12 sec/mile.
    static func parsePace(_ raw: String) -> Int? {
        let t = raw.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }

        let sec: Int
        if t.contains(":") {
            let parts = t.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 2,
                  let m = Int(parts[0]), let s = Int(parts[1]),
                  m >= 0, s >= 0, s < 60 else { return nil }
            sec = m * 60 + s
        } else {
            guard let n = Int(t) else { return nil }
            sec = n
        }

        // 3:00/mi is world-record territory; 20:00/mi is a walk. Outside that
        // it isn't a pace someone meant to type.
        guard (180...1200).contains(sec) else { return nil }
        return sec
    }
}

// MARK: - Store

/// Where the settings live between launches.
///
/// One shared store rather than view state: the Signal Lab's threshold section
/// and anything that reads the same band later must not be able to disagree
/// about what "in band" means for the same athlete.
@Observable
final class BandSettingsStore {
    static let shared = BandSettingsStore()

    private static let key = "signalLab.bandSettings.v1"

    var settings: BandSettings {
        didSet { persist() }
    }

    private let defaults: UserDefaults

    /// Test seam — pass a scratch `UserDefaults` to avoid touching the real one.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.settings = Self.load(from: defaults)
    }

    func reset() { settings = .default }

    private func persist() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.key)
    }

    /// A blob that fails to decode is a blob from a build that shaped these
    /// differently. Falling back to the default is the honest outcome — the
    /// alternative is a band drawn from half-read settings.
    private static func load(from defaults: UserDefaults) -> BandSettings {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(BandSettings.self, from: data)
        else { return .default }
        return decoded.clamped()
    }
}
