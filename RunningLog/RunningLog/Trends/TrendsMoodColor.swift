//
//  TrendsMoodColor.swift
//  RunningLog · Trends
//
//  Mood → color mapping for the Trends surfaces (mood ribbon + distribution).
//  Extracted from the retired UnifiedTrainingChart (2026-07-27 Trends cull) so
//  the live MoodDetailView keeps its palette. Warm mood ramp only — never the
//  pace blue, never the alert coral (the three-palette rule).
//

import SwiftUI

enum TrendsMoodColor {
    static func color(_ mood: String) -> Color {
        switch mood.lowercased() {
        case "energized":  Color.drip.energized
        case "positive":   Color.drip.positive
        case "neutral":    Color.drip.neutral
        case "tired":      Color.drip.tired
        case "struggling": Color.drip.struggling
        case "injured":    Color.drip.injured
        default:           Color.drip.neutral
        }
    }

    /// The vocabulary in order, best to worst. Same six words as
    /// `CLAUDE.md`'s closed mood vocabulary and the same order the recovery
    /// ledger scores them in — see `TrendsRecoveryFactors.moodPoints`.
    static let ordered = [
        "energized", "positive", "neutral", "tired", "struggling", "injured",
    ]

    /// Height fraction for a mood mark, 0…1.
    ///
    /// **Why mood has a height at all.** Colour-alone is not a safe encoding:
    /// three of these six are adjacent warm hues (tired amber, struggling
    /// terracotta, injured rose) and two are adjacent greens, so a
    /// colour-blind reader or anyone with a colour filter on sees one ribbon
    /// where the chart means six values. Height is the redundant channel.
    ///
    /// **Why an ordering is legitimate.** The app already orders these words —
    /// the recovery receipt scores them +12 down to −18. This ramp is the
    /// same order, so the chart and the ledger cannot disagree. It is a rank,
    /// never a measurement: the stored value stays TEXT and every readout
    /// still speaks the word.
    ///
    /// A word outside the vocabulary sits at the neutral step rather than at
    /// either extreme — the same fallback `color(_:)` makes.
    static func height(_ mood: String) -> Double {
        let steps: [Double] = [1.0, 0.85, 0.7, 0.55, 0.4, 0.25]
        guard let i = ordered.firstIndex(of: mood.lowercased()) else { return 0.7 }
        return steps[i]
    }
}
