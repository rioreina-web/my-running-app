//
//  TrendsModels.swift
//  RunningLog
//
//  Data model for the **Trends** tab — the chart-centric "show me what I
//  can't see" surface (revived from the retired Trends tab; see the
//  tombstone history in this folder). One shared timeline fuses five
//  streams the athlete can't easily correlate from inside a block:
//  mileage, intensity, key-session pace, mood, and niggles.
//
//  V1 ships with `TrendsSampleData` so the surface is fully designed and
//  reviewable. The real wiring is a follow-up:
//    • miles / qualityMiles → `_shared/dataAnalysis.ts` weekly volume +
//      the quality-mile split (HealthKit-synced training_logs).
//    • keyPaceSec           → the week's hardest quality session pace.
//    • mood                 → dominant voice-log mood for the week
//      (vocabulary: energized | positive | neutral | tired | struggling
//      | injured — see CLAUDE.md).
//    • niggles / voiceQuote → `body_mentions` (verbatim, surface-not-
//      diagnose). Quotes are the athlete's own words; never coerced.
//

import Foundation

// MARK: - Range window

/// The timeframe segmenter at the top of the chart. Raw value == number of
/// weeks shown (also used to slice the sample tail).
enum TrendsRange: Int, CaseIterable, Identifiable {
    case fourWeek = 4
    case twelveWeek = 12
    case sixMonth = 26

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .fourWeek: "4 wk"
        case .twelveWeek: "12 wk"
        case .sixMonth: "6 mo"
        }
    }
}

// MARK: - Week model

/// One week on the unified timeline. All five tracks read off the same row,
/// so a vertical scrub lines up volume, the key session, how she felt, and
/// any body-part mentions for that week.
struct TrendsWeek: Identifiable {
    let id = UUID()
    /// Short month tag for the x-axis ("May"). Drawn only when the month
    /// changes across the window.
    let month: String
    /// Full label shown in the readout ("May 26").
    let dateLabel: String
    /// Weekly mileage.
    let miles: Double
    /// Quality (non-easy) miles inside `miles` — rendered as the darker bar
    /// cap so intensity rides inside volume rather than needing its own chart.
    let qualityMiles: Double
    /// Pace of the week's key quality session, sec/mile. `nil` for weeks
    /// with no quality session (e.g. a down week).
    let keyPaceSec: Int?
    /// Dominant voice-log mood for the week (closed vocabulary).
    let mood: String
    /// Body parts mentioned this week, verbatim labels. Surface, never
    /// diagnose.
    let niggles: [String]
    /// An optional verbatim voice-log line to surface in an insight.
    var voiceQuote: String? = nil
}

// MARK: - Pace formatting

enum TrendsFormat {
    /// 401 → "6:41". Returns "—" for nil (callers should prefer the
    /// empty-state component for real empty cells; this is for inline stats).
    static func pace(_ sec: Int?) -> String {
        guard let sec else { return "—" }
        return "\(sec / 60):\(String(format: "%02d", sec % 60))"
    }
}

// MARK: - Sample data

/// 26 weeks of base-phase data ending "this" Monday, mirroring the approved
/// HTML prototype (`trends-tab-prototype.html`). Tail-sliced by `TrendsRange`.
///
/// NB: deliberately static + synchronous for V1. Replace `weeks` with a
/// data-service load when wiring real streams; the views depend only on the
/// `[TrendsWeek]` shape.
enum TrendsSampleData {
    static let weeks: [TrendsWeek] = [
        TrendsWeek(month: "Dec", dateLabel: "Dec 16", miles: 32, qualityMiles: 5,  keyPaceSec: 438, mood: "positive",   niggles: []),
        TrendsWeek(month: "Dec", dateLabel: "Dec 23", miles: 30, qualityMiles: 4,  keyPaceSec: nil, mood: "neutral",    niggles: []),
        TrendsWeek(month: "Dec", dateLabel: "Dec 30", miles: 34, qualityMiles: 6,  keyPaceSec: 440, mood: "positive",   niggles: []),
        TrendsWeek(month: "Jan", dateLabel: "Jan 6",  miles: 36, qualityMiles: 6,  keyPaceSec: 436, mood: "energized",  niggles: []),
        TrendsWeek(month: "Jan", dateLabel: "Jan 13", miles: 35, qualityMiles: 7,  keyPaceSec: 434, mood: "tired",      niggles: []),
        TrendsWeek(month: "Jan", dateLabel: "Jan 20", miles: 38, qualityMiles: 8,  keyPaceSec: 432, mood: "positive",   niggles: []),
        TrendsWeek(month: "Jan", dateLabel: "Jan 27", miles: 37, qualityMiles: 7,  keyPaceSec: 430, mood: "positive",   niggles: []),
        TrendsWeek(month: "Feb", dateLabel: "Feb 3",  miles: 40, qualityMiles: 9,  keyPaceSec: 431, mood: "tired",      niggles: ["L hip"]),
        TrendsWeek(month: "Feb", dateLabel: "Feb 10", miles: 39, qualityMiles: 8,  keyPaceSec: 428, mood: "positive",   niggles: []),
        TrendsWeek(month: "Feb", dateLabel: "Feb 17", miles: 42, qualityMiles: 10, keyPaceSec: 427, mood: "energized",  niggles: []),
        TrendsWeek(month: "Feb", dateLabel: "Feb 24", miles: 41, qualityMiles: 9,  keyPaceSec: 426, mood: "neutral",    niggles: []),
        TrendsWeek(month: "Mar", dateLabel: "Mar 3",  miles: 44, qualityMiles: 11, keyPaceSec: 425, mood: "tired",      niggles: []),
        TrendsWeek(month: "Mar", dateLabel: "Mar 10", miles: 43, qualityMiles: 10, keyPaceSec: 423, mood: "positive",   niggles: []),
        TrendsWeek(month: "Mar", dateLabel: "Mar 17", miles: 46, qualityMiles: 12, keyPaceSec: 422, mood: "positive",   niggles: []),
        // ---- last 12 weeks (default window) ----
        TrendsWeek(month: "Mar", dateLabel: "Mar 24", miles: 38, qualityMiles: 8,  keyPaceSec: 418, mood: "positive",   niggles: []),
        TrendsWeek(month: "Mar", dateLabel: "Mar 31", miles: 41, qualityMiles: 9,  keyPaceSec: 416, mood: "positive",   niggles: []),
        TrendsWeek(month: "Apr", dateLabel: "Apr 7",  miles: 43, qualityMiles: 10, keyPaceSec: 414, mood: "tired",      niggles: []),
        TrendsWeek(month: "Apr", dateLabel: "Apr 14", miles: 40, qualityMiles: 9,  keyPaceSec: 415, mood: "positive",   niggles: []),
        TrendsWeek(month: "Apr", dateLabel: "Apr 21", miles: 46, qualityMiles: 12, keyPaceSec: 410, mood: "energized",  niggles: []),
        TrendsWeek(month: "Apr", dateLabel: "Apr 28", miles: 48, qualityMiles: 13, keyPaceSec: 408, mood: "tired",      niggles: []),
        TrendsWeek(month: "May", dateLabel: "May 5",  miles: 44, qualityMiles: 10, keyPaceSec: 407, mood: "struggling", niggles: ["R achilles"], voiceQuote: "Achilles grumbled on the warm-up, eased off after a mile."),
        TrendsWeek(month: "May", dateLabel: "May 12", miles: 50, qualityMiles: 14, keyPaceSec: 405, mood: "positive",   niggles: []),
        TrendsWeek(month: "May", dateLabel: "May 19", miles: 52, qualityMiles: 15, keyPaceSec: 404, mood: "energized",  niggles: ["R achilles"]),
        TrendsWeek(month: "May", dateLabel: "May 26", miles: 49, qualityMiles: 13, keyPaceSec: 403, mood: "positive",   niggles: []),
        TrendsWeek(month: "Jun", dateLabel: "Jun 2",  miles: 53, qualityMiles: 16, keyPaceSec: 402, mood: "tired",      niggles: ["R achilles", "L hip"]),
        TrendsWeek(month: "Jun", dateLabel: "Jun 9",  miles: 53, qualityMiles: 16, keyPaceSec: 401, mood: "energized",  niggles: ["R achilles"], voiceQuote: "Heavy and short on patience today — nothing in the legs."),
    ]

    /// The most recent `range.rawValue` weeks, oldest → newest.
    static func window(_ range: TrendsRange) -> [TrendsWeek] {
        Array(weeks.suffix(range.rawValue))
    }
}
