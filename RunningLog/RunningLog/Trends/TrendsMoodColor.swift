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
}
