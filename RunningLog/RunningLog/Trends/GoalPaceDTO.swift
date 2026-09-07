//
//  GoalPaceDTO.swift
//  RunningLog
//
//  Wire format for the `goal_pace` block of the `trends-timeline` response,
//  produced by `trends-timeline/goalPace.ts`. Same snake_case → camelCase DTO
//  pattern as FastSegmentsDTO.
//
//  The unit is PERCENT OF GOAL RACE PACE, not pace. Raw pace makes the surface
//  unreadable — a 5:20 goal and a 7:30 easy day share no scale — and it strands
//  history the moment the athlete re-targets. Percent of goal *speed* fixes
//  both, and it is the currency the workout library already speaks, so the
//  bands are its own constants (80 easy / 85 moderate / 90 steady / 95 the fast
//  leg of an alternation / 100 race pace) rather than anything a plan invents.
//  No training plan is required for this surface to render.
//
//  A float session reports its AGGREGATE pace across the whole continuous span:
//  an alternation's float leg is aerobic support, not rest. Ringed in the chart
//  so the reader knows the value spans both legs.
//

import Foundation

// MARK: - View models

/// One key session, positioned by how close it ran to goal race pace.
struct GoalPaceSession: Identifiable, Equatable {
    let id: String
    let date: Date
    let workoutType: String?
    /// Percent of goal-race-pace speed. 100 = exactly goal pace, >100 = faster.
    let pctOfGoal: Double
    /// Work + float — the span actually run without stopping to jog.
    let continuousMiles: Double
    /// RAW — what the watch recorded.
    let paceSec: Int
    /// The same span credited for the conditions it was run in. Equals
    /// `paceSec` when no weather is on file, so this can be read unbranched.
    let paceSecHeatAdj: Int
    let heatGainSec: Int
    let pctOfGoalHeatAdj: Double
    /// Fast legs only. Non-nil only for a float session.
    let fastPaceSec: Int?
    let floatPaceSec: Int?
    let isFloatSession: Bool
    /// Fast legs. A 20k alternation is 10 cycles, not 20 reps.
    let cycles: Int
    let atOrAboveSpecific: Bool
}

/// One gridline, straight from the workout library's ladder.
struct GoalPaceBand: Identifiable, Equatable {
    var id: Int { pct }
    let pct: Int
    let label: String
    let paceSec: Int
}

struct GoalPaceGoal: Equatable {
    let raceKey: String
    let timeSeconds: Int
    let paceSecPerMile: Double
    /// Where the goal was resolved from — `active_goal`, `user_goals`, …
    let source: String
}

struct GoalPaceSummary: Equatable {
    let sessions: Int
    let specificMiles: Double
    /// The longest single continuous span at goal pace or faster. THE number:
    /// a marathon build wants this climbing, not the count of hard days.
    let longestSpecificMiles: Double
    let meanPctFirstHalf: Double?
    let meanPctSecondHalf: Double?
}

/// Faster than goal · on goal pace · slower. The lane IS the reading — there is
/// no continuous axis to measure against, which is what makes this legible at
/// phone width where a scatter wasn't.
enum GoalPaceLane: String, CaseIterable, Identifiable {
    case faster, onPace, slower
    var id: String { rawValue }
    var label: String {
        switch self {
        case .faster: return "FASTER THAN GOAL"
        case .onPace: return "ON GOAL PACE"
        case .slower: return "SLOWER THAN GOAL"
        }
    }
    /// ±2% — the width a coach would call "at pace" without hedging. Mirrors
    /// the tolerance in `_shared/analyzers/racePaceSpecificity.ts`.
    static func of(_ pct: Double) -> GoalPaceLane {
        if pct > 102 { return .faster }
        if pct >= 98 { return .onPace }
        return .slower
    }
}

struct GoalPaceData: Equatable {
    let goal: GoalPaceGoal
    let bands: [GoalPaceBand]
    let sessions: [GoalPaceSession]
    let summary: GoalPaceSummary

    var isEmpty: Bool { sessions.isEmpty }

    /// Sessions in a lane, honouring the heat toggle.
    func sessions(in lane: GoalPaceLane, heatAdjusted: Bool) -> [GoalPaceSession] {
        sessions.filter { GoalPaceLane.of(heatAdjusted ? $0.pctOfGoalHeatAdj : $0.pctOfGoal) == lane }
    }

    /// Continuous miles in a lane. This is the specificity answer, and the
    /// reason marks are sized by volume rather than counted.
    func miles(in lane: GoalPaceLane, heatAdjusted: Bool) -> Double {
        sessions(in: lane, heatAdjusted: heatAdjusted).reduce(0) { $0 + $1.continuousMiles }
    }

    var totalMiles: Double { sessions.reduce(0) { $0 + $1.continuousMiles } }

    /// True when any session actually has a correction to show. Without this
    /// the toggle would appear on a block with no weather and do nothing.
    var hasHeatData: Bool { sessions.contains { $0.heatGainSec > 0 } }

    /// Positive when the second half of the window ran closer to goal pace.
    var convergenceDelta: Double? {
        guard let a = summary.meanPctFirstHalf, let b = summary.meanPctSecondHalf else { return nil }
        return b - a
    }
}

// MARK: - Wire format

struct GoalPaceDTO: Decodable {
    let goal: GoalDTO
    let bands: [BandDTO]
    let sessions: [SessionDTO]
    let summary: SummaryDTO

    struct GoalDTO: Decodable {
        let raceKey: String
        let timeSeconds: Int
        let paceSecPerMile: Double
        let source: String
        private enum CodingKeys: String, CodingKey {
            case raceKey = "race_key"
            case timeSeconds = "time_seconds"
            case paceSecPerMile = "pace_sec_per_mile"
            case source
        }
    }

    struct BandDTO: Decodable {
        let pct: Int
        let label: String
        let paceSec: Int
        private enum CodingKeys: String, CodingKey {
            case pct, label
            case paceSec = "pace_sec"
        }
    }

    struct SessionDTO: Decodable {
        let workoutId: String
        let date: String
        let workoutType: String?
        let pctOfGoal: Double
        let continuousMiles: Double
        let paceSec: Int
        let paceSecHeatAdj: Int?
        let heatGainSec: Int?
        let pctOfGoalHeatAdj: Double?
        let fastPaceSec: Int?
        let floatPaceSec: Int?
        let isFloatSession: Bool
        let cycles: Int
        let atOrAboveSpecific: Bool
        private enum CodingKeys: String, CodingKey {
            case workoutId = "workout_id"
            case date
            case workoutType = "workout_type"
            case pctOfGoal = "pct_of_goal"
            case continuousMiles = "continuous_miles"
            case paceSec = "pace_sec"
            case paceSecHeatAdj = "pace_sec_heat_adj"
            case heatGainSec = "heat_gain_sec"
            case pctOfGoalHeatAdj = "pct_of_goal_heat_adj"
            case fastPaceSec = "fast_pace_sec"
            case floatPaceSec = "float_pace_sec"
            case isFloatSession = "is_float_session"
            case cycles
            case atOrAboveSpecific = "at_or_above_specific"
        }
    }

    struct SummaryDTO: Decodable {
        let sessions: Int
        let specificMiles: Double
        let longestSpecificMiles: Double
        let meanPctFirstHalf: Double?
        let meanPctSecondHalf: Double?
        private enum CodingKeys: String, CodingKey {
            case sessions
            case specificMiles = "specific_miles"
            case longestSpecificMiles = "longest_specific_miles"
            case meanPctFirstHalf = "mean_pct_first_half"
            case meanPctSecondHalf = "mean_pct_second_half"
        }
    }

    /// `workout_date` arrives as a DATE or a timestamp depending on the row.
    /// The SDK's default decoder throws on bare DATE columns, so parse by hand
    /// — see `feedback_supabase_swift_date_decoder`.
    private static func parseDate(_ s: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }
        let plain = DateFormatter()
        plain.calendar = Calendar(identifier: .iso8601)
        plain.timeZone = TimeZone(identifier: "UTC")
        plain.dateFormat = "yyyy-MM-dd"
        return plain.date(from: String(s.prefix(10)))
    }

    func toData() -> GoalPaceData? {
        let sessions: [GoalPaceSession] = self.sessions.compactMap { s in
            guard let d = Self.parseDate(s.date) else { return nil }
            return GoalPaceSession(
                id: s.workoutId,
                date: d,
                workoutType: s.workoutType,
                pctOfGoal: s.pctOfGoal,
                continuousMiles: s.continuousMiles,
                paceSec: s.paceSec,
                // Optional on the wire so an older deploy still decodes; falls
                // back to raw, which is exactly "no correction".
                paceSecHeatAdj: s.paceSecHeatAdj ?? s.paceSec,
                heatGainSec: s.heatGainSec ?? 0,
                pctOfGoalHeatAdj: s.pctOfGoalHeatAdj ?? s.pctOfGoal,
                fastPaceSec: s.fastPaceSec,
                floatPaceSec: s.floatPaceSec,
                isFloatSession: s.isFloatSession,
                cycles: s.cycles,
                atOrAboveSpecific: s.atOrAboveSpecific
            )
        }
        guard !sessions.isEmpty else { return nil }
        return GoalPaceData(
            goal: GoalPaceGoal(
                raceKey: goal.raceKey,
                timeSeconds: goal.timeSeconds,
                paceSecPerMile: goal.paceSecPerMile,
                source: goal.source
            ),
            bands: bands.map { GoalPaceBand(pct: $0.pct, label: $0.label, paceSec: $0.paceSec) },
            sessions: sessions,
            summary: GoalPaceSummary(
                sessions: summary.sessions,
                specificMiles: summary.specificMiles,
                longestSpecificMiles: summary.longestSpecificMiles,
                meanPctFirstHalf: summary.meanPctFirstHalf,
                meanPctSecondHalf: summary.meanPctSecondHalf
            )
        )
    }
}
