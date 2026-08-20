//
//  TrainingTip.swift
//  RunningLog · Analysis · Tips
//
//  Three or four things that would move the goal, derived from what the
//  athlete has actually run.
//
//  TWO CONSTRAINTS SHAPE THIS WHOLE FEATURE.
//
//  1. NO TRAINING SCHEDULE REQUIRED. Nothing here reads `training_plans`,
//     `scheduled_workouts` or `plan_weeks`. An athlete who just logs runs gets
//     the same tips as one following a plan, because every detector reads
//     completed training and the goal — never a prescription. Tips therefore
//     name a SESSION, never a day: "inside your next long run", not "on
//     Wednesday". A tip that needs a calendar slot to make sense is the wrong
//     tip for this surface.
//
//  2. EVERY TIP CITES ITS OWN NUMBERS. A tip with no evidence rows does not
//     render. The evidence is the athlete's own mileage, weeks and sessions —
//     the same rule the Week tab runs on, for the same reason.
//
//  Tips are ranked and the top few shown. The catalogue is deliberately larger
//  than the slot count so the surface says something different as training
//  changes, rather than repeating one note forever.
//

import SwiftUI

// MARK: - Goal

/// The athlete's goal, read from `user_goals` — NOT from a plan.
struct TipGoal {
    let raceDistance: String
    let targetSeconds: Int
    let targetDate: Date?
    let title: String

    /// Miles in the goal race.
    var raceMiles: Double {
        switch raceDistance.lowercased() {
        case "marathon": 26.2188
        case "half", "half_marathon", "half marathon": 13.1094
        case "10k": 6.21371
        case "5k": 3.10686
        case "mile": 1.0
        default: 26.2188
        }
    }

    /// Goal race pace, seconds per mile. The pace the race is actually run at,
    /// and the one the tips measure exposure against.
    var racePaceSec: Int { Int((Double(targetSeconds) / raceMiles).rounded()) }

    var racePaceLabel: String {
        let p = racePaceSec
        return "\(p / 60):\(String(format: "%02d", p % 60))"
    }

    /// The pace-spectrum token that IS this athlete's race pace. This is the
    /// single line that makes the whole surface goal-aware: a 5K athlete's
    /// tips key off `5k`, a marathoner's off `mp`.
    var racePaceToken: String {
        switch raceDistance.lowercased() {
        case "marathon": "mp"
        case "half", "half_marathon", "half marathon": "hmp"
        case "10k": "10k"
        case "5k": "5k"
        case "mile": "mile"
        default: "mp"
        }
    }

    var raceLabel: String {
        switch raceDistance.lowercased() {
        case "marathon": "marathon"
        case "half", "half_marathon", "half marathon": "half"
        case "10k": "10K"
        case "5k": "5K"
        case "mile": "mile"
        default: raceDistance
        }
    }

    var weeksOut: Int? {
        guard let targetDate else { return nil }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: targetDate).day ?? 0
        return days > 0 ? Int((Double(days) / 7).rounded()) : nil
    }

    var timeLabel: String {
        let h = targetSeconds / 3600
        let m = (targetSeconds % 3600) / 60
        let s = targetSeconds % 60
        return h > 0 ? "\(h):\(String(format: "%02d", m)):\(String(format: "%02d", s))"
                     : "\(m):\(String(format: "%02d", s))"
    }
}

// MARK: - Tip

struct TrainingTip: Identifiable {

    enum Category: String {
        case pace, load

        var label: String {
            switch self {
            case .pace: "Pace"
            case .load: "Load"
            }
        }

        var tint: Color {
            switch self {
            case .pace: PaceSpectrum.hmp
            case .load: Color.drip.coral
            }
        }
    }

    /// Stable key, so a tip can be dismissed or tracked later without
    /// depending on its position in the list.
    let id: String
    let category: Category
    /// The finding, in the athlete's own numbers.
    let headline: String
    /// What the data says, cited.
    let observation: String
    /// A session shape, never a date. See constraint 1 in the file header.
    let action: String
    /// The numbers behind it. A tip with none of these does not render.
    let evidence: [String]
    /// Higher sorts first. Goal-specificity beats generic training hygiene.
    let priority: Int
}
