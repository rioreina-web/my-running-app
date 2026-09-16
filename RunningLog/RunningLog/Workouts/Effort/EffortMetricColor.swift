//
//  EffortMetricColor.swift
//  RunningLog
//
//  The view-side bridge from an EffortMetric to a Post Run Drip color token.
//  Kept out of the engine so EffortMetric.swift stays SwiftUI-free.
//
//  Palette per the handoff metric table, mapped to `Color.drip.*` (the token
//  source of truth). Pace uses `paceFast` — the navy end of the pace ramp
//  — honoring the three-palette rule (pace owns the ramp); it is a hair deeper than the
//  handoff's #1B2A4A but stays in-system rather than introducing a new hex.
//

import SwiftUI

extension EffortMetric {
    /// The trace / accent color for this metric.
    var color: Color {
        switch self {
        case .hr:   return Color.drip.coral          // #D4592A
        case .pace: return Color.drip.paceFast       // navy — pace ramp
        case .cad:  return Color.drip.textSecondary  // #6B6560 ink-2
        case .elev: return Color.drip.positive       // #4A9E6B green
        }
    }
}
