//
//  AthleteState.swift
//  RunningLog
//
//  Slim iOS readers for athlete_state fields that gate UI behavior.
//

import Foundation
import os
import Supabase

/// data_depth (0..3) — drives editorial register on Today and gates pull-quote surfaces.
/// Source of truth: supabase/functions/_shared/athlete-state.ts:computeDataDepth.
struct AthleteDataDepth {
    let value: Int

    static func fetch() async -> AthleteDataDepth {
        struct Row: Decodable { let data_depth: Int }
        do {
            let rows: [Row] = try await supabase
                .from("athlete_state")
                .select("data_depth")
                .limit(1)
                .execute()
                .value
            return AthleteDataDepth(value: rows.first?.data_depth ?? 0)
        } catch {
            Log.app.error("AthleteDataDepth fetch failed: \(error)")
            return AthleteDataDepth(value: 0)
        }
    }

    var isEmpty: Bool { value == 0 }
    var isMinimal: Bool { value == 1 }
    var isModerate: Bool { value == 2 }
    var isFull: Bool { value == 3 }

    /// True when editorial register (italics, pull-quotes, trend deltas) is allowed.
    var allowsEditorialVoice: Bool { value >= 2 }
}
