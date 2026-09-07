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

/// Minimal projection of `athlete_state` for the ACWR tile and the Trends
/// Recovery section. Snake_case field names match the JSON columns 1:1 — the
/// SDK decoder is NOT convertFromSnakeCase (see ModelOfYouState). Every field
/// is optional so a thin/partial state still decodes.
struct TrendsAthleteState: Decodable {
    let acwr: Double?
    let rolling_7d_miles: Double?
    let rolling_28d_miles: Double?

    // Recovery read — surfaced in the Trends "Recovery" section. `recovery_read`
    // is nested under `load_distribution` (mirrors ModelOfYouState).
    let last_readiness_score: Int?
    let load_distribution: LoadDistribution?
    let active_injuries: [InjuryMention]?
    let possible_injuries: [InjuryMention]?

    struct LoadDistribution: Decodable {
        let recovery_read: RecoveryRead?
    }

    struct RecoveryRead: Decodable {
        let down_week: Bool?
        let hard_sessions_28d: Int?
        // Backend emits this as an AVERAGE (e.g. 5.7), so it must decode as a
        // Double — an Int? here threw "not representable" and blanked the whole
        // decode. See the same note in ModelOfYouState.RecoveryRead.
        let avg_days_between_hard: Double?
    }

    /// We only need the body area to count active body signals; the injury
    /// shapes carry more (status/severity/excerpt) but Decodable ignores it.
    struct InjuryMention: Decodable {
        let body_area: String?
    }

    /// Distinct body areas across active + possible injuries — the "watching"
    /// count for the recovery headline. Surface-not-diagnose: a count only.
    var bodySignalCount: Int {
        let areas = ((active_injuries ?? []) + (possible_injuries ?? []))
            .compactMap { $0.body_area?.lowercased() }
        return Set(areas).count
    }

    static func fetch() async -> TrendsAthleteState? {
        do {
            let rows: [TrendsAthleteState] = try await supabase
                .from("athlete_state")
                .select("""
                    acwr, rolling_7d_miles, rolling_28d_miles, \
                    last_readiness_score, load_distribution, \
                    active_injuries, possible_injuries
                """)
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
