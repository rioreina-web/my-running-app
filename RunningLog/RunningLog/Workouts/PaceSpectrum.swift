//
//  PaceSpectrum.swift
//  RunningLog
//
//  Single source of truth for the "color == pace" visual language.
//
//  One hue, ten depths: pale sky (easy) deepening through mid-blue to
//  navy (mile). Pace reads as *intensity*, not as a rainbow.
//
//  Hue history (all on 2026-08-21, all reverted): the ramp was moved onto
//  the coral accent — pinning stop 6 to --coral exactly — and then onto a
//  wine ramp at ~330–348°. Coral was pulled because pace is the largest
//  coloured surface in the product, so putting it on the brand hue made
//  orange the dominant colour of every chart and left coral nothing to
//  point with. Wine was pulled by preference. Blue is the shipped ramp;
//  if it is ever moved again, the two constraints that bit last time are
//  (a) Easy must stay visible against --paper — this ramp reads 1.87:1,
//  the coral build only managed 1.20:1 — and (b) pinning any stop to a
//  brand token costs even spacing. (Rio, 2026-08-21.)
//
//  Collision note: pace, mood and alert occupy three separate hue lanes —
//  blue, the muted greens/ambers, and coral — so a colour's job is
//  unambiguous from the colour alone. When the athlete toggles
//  "PACE COLOR" off, workout-detail surfaces fall back to a single coral
//  accent instead.
//
//  Design note: the ten stops map to the canonical 10-zone pace taxonomy
//  (Easy · Moderate · Steady · MP · HMP · LT · 10K · 5K · 3K · Mile).
//  The scale is carried primarily by lightness (what the eye ranks),
//  with saturation deepening alongside.
//
//  Future: today the slow/fast bounds are passed in per-context (usually a
//  workout's own pace range), so the same pace can read slightly different
//  across workouts. A later pass can anchor the ramp on the athlete's
//  PaceZonesEngine so a given pace is always the same color everywhere.
//

import SwiftUI
import UIKit

enum PaceSpectrum {

    /// Ordered slow → fast stops. One color per canonical zone.
    static let stops: [Color] = [
        Color(hex: "93B9D6"), // Easy (pale sky)
        Color(hex: "74A8CC"), // Moderate
        Color(hex: "578FC0"), // Steady
        Color(hex: "3F7CB5"), // MP
        Color(hex: "2F66A8"), // HMP
        Color(hex: "27549B"), // LT
        Color(hex: "20448B"), // 10K
        Color(hex: "1A3679"), // 5K
        Color(hex: "142964"), // 3K
        Color(hex: "0E1D4E"), // Mile (navy)
    ]

    /// Legibility-darkened Easy for *small text* (marker labels, zone
    /// captions). The true Easy stop is too pale to read at 9–11 pt on
    /// paper; fills should still use `easy`. NOTE: at 2.97:1 on --paper
    /// (#F5F3F0) this is weak for its stated job — #427498 would hit
    /// 4.53:1 at the same hue if we ever want to fix it.
    static var easyText: Color { Color(hex: "5E93BE") }

    /// Named zone accessors, in taxonomy order — Easy … Mile.
    static var easy: Color     { stops[0] }
    static var moderate: Color { stops[1] }
    static var steady: Color   { stops[2] }
    static var mp: Color       { stops[3] }
    static var hmp: Color      { stops[4] }
    static var lt: Color       { stops[5] }
    static var tenK: Color     { stops[6] }
    static var fiveK: Color    { stops[7] }
    static var threeK: Color   { stops[8] }
    static var mile: Color     { stops[9] }

    /// SwiftUI gradient of the full ramp — handy for legend swatches.
    static var gradient: LinearGradient {
        LinearGradient(colors: stops, startPoint: .leading, endPoint: .trailing)
    }

    /// Color for a normalized position `t` in [0, 1]; 0 = slowest, 1 = fastest.
    static func color(at t: Double) -> Color {
        guard stops.count > 1 else { return stops.first ?? .gray }
        let clamped = min(max(t, 0), 1)
        let scaled = clamped * Double(stops.count - 1)
        let i = min(Int(scaled), stops.count - 2)
        let frac = scaled - Double(i)
        return mix(stops[i], stops[i + 1], frac)
    }

    /// Color for a pace (sec/mi) given the slow/fast bounds of the context.
    /// `slowSec` maps to the pale end, `fastSec` to the navy end. Faster
    /// paces (smaller seconds) move deeper.
    static func color(forPaceSec pace: Double, slowSec: Double, fastSec: Double) -> Color {
        guard slowSec > fastSec else { return stops.first ?? .gray }
        let t = (slowSec - pace) / (slowSec - fastSec)
        return color(at: t)
    }

    // MARK: - Zone-anchored mapping

    /// The "later pass" promised in the header note, now real: pins the ramp
    /// to the athlete's own zone table (`PaceZonesEngine`) so a given pace is
    /// the *same color on every surface* — a 5K rep is the same red in a list
    /// row, a skyline, and a receipt. Each available zone anchor maps to its
    /// canonical stop; paces between anchors interpolate between adjacent
    /// stops. Returns nil when no zone table exists — callers fall back to
    /// per-context bounds (`color(forPaceSec:slowSec:fastSec:)`) or the
    /// single-accent treatment.
    static func anchoredColor(paceSec: Double, zones: PaceZonesEngine?) -> Color? {
        let anchors = anchorTable(zones)
        guard anchors.count >= 2 else { return nil }
        // Slower than the slowest anchor clamps green; faster than the
        // fastest clamps deep red.
        if paceSec >= anchors[0].pace { return color(at: anchors[0].t) }
        if let last = anchors.last, paceSec <= last.pace { return color(at: last.t) }
        for i in 0..<(anchors.count - 1) {
            let a = anchors[i], b = anchors[i + 1]
            if paceSec <= a.pace, paceSec >= b.pace {
                let span = a.pace - b.pace
                let frac = span > 0 ? (a.pace - paceSec) / span : 0
                return color(at: a.t + (b.t - a.t) * frac)
            }
        }
        return nil
    }

    /// (ramp position t, anchor pace sec/mi) pairs, slow → fast, built from
    /// whichever engine zones exist. Sanitized to strictly-decreasing pace so
    /// interpolation is well-defined even if a stored zone table is odd.
    private static func anchorTable(_ zones: PaceZonesEngine?) -> [(t: Double, pace: Double)] {
        guard let z = zones else { return [] }
        let n = Double(stops.count - 1)
        let raw: [(index: Int, pace: Double?)] = [
            (0, z.easyMidpoint),
            (1, z.moderateMidpoint),
            (2, z.steadyMidpoint),
            (3, z.marathon?.pace),
            (4, z.halfMarathon?.pace),
            (5, z.thresholdPace),
            (6, z.tenK?.pace),
            (7, z.fiveK?.pace),
            (8, z.threeK?.pace),
            (9, z.mile?.pace),
        ]
        var out: [(t: Double, pace: Double)] = []
        for entry in raw {
            guard let p = entry.pace, p > 0 else { continue }
            if let prev = out.last, p >= prev.pace { continue }
            out.append((t: Double(entry.index) / n, pace: p))
        }
        return out
    }

    /// Linear RGB interpolation between two colors.
    private static func mix(_ a: Color, _ b: Color, _ t: Double) -> Color {
        let ca = UIColor(a), cb = UIColor(b)
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        ca.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        cb.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let f = CGFloat(min(max(t, 0), 1))
        return Color(
            red:   Double(r1 + (r2 - r1) * f),
            green: Double(g1 + (g2 - g1) * f),
            blue:  Double(b1 + (b2 - b1) * f)
        )
    }
}
