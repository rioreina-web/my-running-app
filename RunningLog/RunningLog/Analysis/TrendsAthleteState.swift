//
//  TrendsAthleteState.swift
//  RunningLog
//
//  Minimal projection of `athlete_state` for the ACWR tile. Previously
//  lived inside `TrendsTabView.swift`; relocated here when the Trends tab
//  was retired (folded into the new analytical Training tab) so its other
//  consumer — `TrainingAnalysisView` — keeps compiling.
//

import Foundation
import Supabase
import os

/// Minimal projection of `athlete_state` for the ACWR tile.
struct TrendsAthleteState: Decodable {
    let acwr: Double?
    let rolling_7d_miles: Double?
    let rolling_28d_miles: Double?

    static func fetch() async -> TrendsAthleteState? {
        do {
            let rows: [TrendsAthleteState] = try await supabase
                .from("athlete_state")
                .select("acwr, rolling_7d_miles, rolling_28d_miles")
                .limit(1)
                .execute()
                .value
            return rows.first
        } catch {
            Log.coach.error("TrendsAthleteState fetch failed: \(error)")
            return nil
        }
    }
}
