//
//  CompareMetrics.swift
//  RunningLog · Trends
//
//  The head-to-head metric model. Extracted from the retired CompareDashboard
//  surface (2026-07-27 Trends cull) so the surviving `HeadToHeadCard` — the one
//  side-by-side comparison that stayed on the Trends tab — keeps its metric
//  definitions without dragging the whole dashboard back in.
//

import SwiftUI

// MARK: - Metrics

struct CompareMetric: Identifiable {
    enum Dir { case lowerBetter, higherBetter, neutral }
    let id: String
    let label: String
    let hint: String
    let dir: Dir
    let group: String
    let isPace: Bool
    /// Numeric value for deltas / plotting (nil when the session can't carry it).
    let value: (FastSession, Bool, Bool) -> Double?
    /// Display string for the head-to-head grid.
    let display: (FastSession, Bool, Bool) -> String
    /// Axis / tile unit line, e.g. "bpm · ▲ steadier".
    let trendUnit: String

    static func fmt1(_ d: Double) -> String { String(format: "%.1f", d) }
}

enum CompareMetrics {
    static let all: [CompareMetric] = [
        CompareMetric(id: "pace", label: "Pace", hint: "per mile", dir: .lowerBetter, group: "OUTPUT", isPace: true,
            value: { s, h, hi in Double(s.pace(heat: h, hills: hi)) },
            display: { s, h, hi in TrendsFormat.pace(s.pace(heat: h, hills: hi)) },
            trendUnit: "min/mi · ▲ faster"),
        CompareMetric(id: "vol", label: "Fast volume", hint: "mi at pace", dir: .higherBetter, group: "OUTPUT", isPace: false,
            value: { s, _, _ in s.fastMiles },
            display: { s, _, _ in CompareMetric.fmt1(s.fastMiles) + " mi" },
            trendUnit: "mi · ▲ more"),
        CompareMetric(id: "rep", label: "Rep length", hint: "avg fast rep", dir: .neutral, group: "OUTPUT", isPace: false,
            value: { s, _, _ in s.avgRepM.map(Double.init) },
            display: { s, _, _ in s.avgRepM.map { "\($0)m" } ?? "—" },
            trendUnit: "m"),
        CompareMetric(id: "dens", label: "Density", hint: "fast ÷ total", dir: .higherBetter, group: "OUTPUT", isPace: false,
            value: { s, _, _ in Double(s.densityPct) },
            display: { s, _, _ in "\(s.densityPct)%" },
            trendUnit: "% · ▲ denser"),
        CompareMetric(id: "rest", label: "Avg rest", hint: "between reps", dir: .neutral, group: "OUTPUT", isPace: false,
            value: { s, _, _ in s.isContinuous ? nil : Double(s.avgRestSec) },
            display: { s, _, _ in s.isContinuous ? "—" : "\(s.avgRestSec)s" },
            trendUnit: "s"),
        CompareMetric(id: "hr", label: "Avg HR", hint: "on the work", dir: .lowerBetter, group: "COST", isPace: false,
            value: { s, _, _ in s.avgHr.map(Double.init) },
            display: { s, _, _ in s.avgHr.map { "\($0)" } ?? "—" },
            trendUnit: "bpm · ▲ cheaper"),
        CompareMetric(id: "drift", label: "HR drift", hint: "start → end", dir: .lowerBetter, group: "COST", isPace: false,
            value: { s, _, _ in s.hrDriftBpm },
            display: { s, _, _ in s.hrDriftBpm.map { ($0 > 0 ? "+" : "") + String(format: "%.0f", $0) } ?? "—" },
            trendUnit: "bpm · ▲ steadier"),
        CompareMetric(id: "rec", label: "Rep recovery", hint: "HR drop bpm", dir: .higherBetter, group: "COST", isPace: false,
            value: { s, _, _ in s.recoveryDropBpm },
            display: { s, _, _ in s.recoveryDropBpm.map { "−" + String(format: "%.0f", $0) } ?? "—" },
            trendUnit: "bpm · ▲ faster"),
        CompareMetric(id: "dec", label: "Decoupling", hint: "effort fade", dir: .lowerBetter, group: "COST", isPace: false,
            value: { s, _, _ in s.decouplingPct },
            display: { s, _, _ in s.decouplingPct.map { String(format: "%.1f", $0) + "%" } ?? "—" },
            trendUnit: "% · ▲ held form"),
        CompareMetric(id: "heat", label: "Heat cost", hint: "s/mi back", dir: .neutral, group: "CONDITIONS", isPace: false,
            value: { s, _, _ in s.heatCostSec.map(Double.init) },
            display: { s, _, _ in s.heatCostSec.map { "+\($0)s" } ?? "—" },
            trendUnit: "s/mi"),
        CompareMetric(id: "hill", label: "Hill cost", hint: "s/mi back", dir: .neutral, group: "CONDITIONS", isPace: false,
            value: { s, _, _ in s.hillCostSec.map(Double.init) },
            display: { s, _, _ in s.hillCostSec.map { "+\($0)s" } ?? "—" },
            trendUnit: "s/mi"),
    ]
    static func by(_ id: String) -> CompareMetric { all.first { $0.id == id }! }
}
