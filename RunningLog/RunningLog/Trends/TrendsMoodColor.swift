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

    /// Rank for the VoiceOver audio graph, 0…1. **Never a drawn height.**
    ///
    /// Mood is drawn as colour alone (2026-08-06): one swatch per logged day,
    /// all the same height. The height ramp this replaced read as a bar chart
    /// of feelings and made the lane harder to scan than the colour did on
    /// its own.
    ///
    /// The ordering survives here because the audio graph has to place each
    /// point on an axis. It is the same order the recovery receipt scores
    /// moods in (`TrendsRecoveryFactors.moodPoints`, +12 down to −18), so the
    /// chart and the ledger cannot disagree. It is a rank, never a
    /// measurement: the stored value stays TEXT and every readout still
    /// speaks the word.
    ///
    /// A word outside the vocabulary sits at the neutral step rather than at
    /// either extreme — the same fallback `color(_:)` makes.
    static func rank(_ mood: String) -> Double {
        let steps: [Double] = [1.0, 0.85, 0.7, 0.55, 0.4, 0.25]
        guard let i = ordered.firstIndex(of: mood.lowercased()) else { return 0.7 }
        return steps[i]
    }
}
