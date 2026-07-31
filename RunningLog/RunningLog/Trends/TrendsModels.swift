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
    /// Monday of this week, "yyyy-MM-dd". `TrendsSessionGrid` uses it to place
    /// a session in the right column. Empty for monthly rollups, which have no
    /// single week — the grid hides itself in that case rather than guessing.
    var weekStart: String = ""
}

// MARK: - Day model (Trends-v2 calendar substrate)

/// One calendar day on the Trends-v2 grid. The daily substrate the Month/Block
/// calendar renders on — **dense** (one entry per day in the window, rest days
/// included) so the weekday layout needs no gap-filling on device.
///
/// Source: `trends-timeline` → `days[]` (`buildDailyTimeline`). Shares the
/// weekly builder's dedup / quality / mood logic, so a day can never disagree
/// with the week it sums into.
struct TrendsDay: Identifiable {
    let id = UUID()
    /// "yyyy-MM-dd" (UTC day).
    let date: String
    /// Deduped running miles that day (doubles summed). 0 on a rest day.
    let miles: Double
    /// The coarse session channel the calendar colours by.
    let type: SessionChannel
    /// Dominant mood that day (closed vocabulary), or `nil` when no feeling was
    /// logged — a true rest day carries no mood, and it is never fabricated.
    let mood: String?
    /// Body mentions that landed on this day, verbatim. Surface, never diagnose.
    let niggles: [DayNiggle]

    /// The session channel the calendar colours by — **not** a pace zone. Per
    /// the calendar encoding: `key` gets the coral accent, `long` its own dark-
    /// grey channel (precedence over key), `easy` light grey, `rest` no run.
    enum SessionChannel: String {
        case key, long, easy, rest

        /// Unknown/absent tokens degrade to `rest`, never a faked session.
        init(token: String?) {
            self = SessionChannel(rawValue: (token ?? "").lowercased()) ?? .rest
        }
    }

    /// One body mention on a day, verbatim. `severity` is the raw
    /// `body_mentions.severity_hint` (tight | sore | pain | sharp); the view
    /// maps it to an opacity ramp — the model never interprets it.
    struct DayNiggle: Identifiable {
        let id = UUID()
        let area: String
        let side: String?
        let severity: String?
        let quote: String
    }
}

// MARK: - Key session (Section A of the redesigned Key Sessions chart)

/// One quality session on the honest pace chart. Unlike `TrendsWeek.keyPaceSec`
/// (one whole-workout average per week), this is a single session's **work-bout
/// pace** — rest excluded, classified to the athlete's own pace zone, with the
/// heat-adjusted pace carried alongside the raw one (never replacing it).
///
/// Source: `trends-timeline` → `quality_sessions[]` (see
/// `supabase/functions/trends-timeline/keySessions.ts`). Missing lap data means
/// a session simply isn't here — the surface degrades, it never fakes a dot.
struct KeySession: Identifiable {
    let id: String          // training_log_id
    let date: String        // "2026-06-23" (UTC day)
    let dateLabel: String   // "Jun 23"
    /// Zone token from the shared classifier: mile | 3k | 5k | 10k | hmp | mp.
    /// NB: the backend classifier folds LT/threshold into `hmp`, so LT is
    /// surfaced as HMP here — the honest label given the current zone table.
    let zone: String
    let workPaceSec: Int
    let workPaceAdjSec: Int?
    let heatCategory: String?  // ideal | warm | hot | very_hot | dangerous | nil
    let workHrAvg: Int?
    let structure: String?     // "5K 5×1km · 6.0 mi"
    let distanceMi: Double?
    /// Weighted minutes of work — Σ(work-bout seconds × zone weight) — from
    /// `trends-timeline`. Drives dot size on the session grid and the gate
    /// that decides whether this counts as a key session at all. Optional so
    /// an older payload still decodes; a nil load never clears the floor.
    /// See `QualityLoad` in `TrendsQualityLoad.swift`.
    var qualityLoad: Double? = nil
    /// `"quality"` = a rep/threshold session, classified by its work bouts.
    /// `"long_run"` = an aerobic anchor session with no MP-or-faster work,
    /// admitted on the classifier's label. Their paces are NOT comparable —
    /// a long run's is the whole run's mean, a quality session's is its work
    /// bouts — so the grid colours and labels them apart and never plots them
    /// on one scale.
    var kind: String = "quality"

    /// Convenience for the grid and the readout.
    var isLongRun: Bool { kind == "long_run" }

    /// The heat model applied only when conditions weren't ideal AND an
    /// adjusted number exists. Drives the hollow-dot rendering.
    var isHeatAdjusted: Bool {
        guard workPaceAdjSec != nil, let c = heatCategory?.lowercased() else { return false }
        return c != "ideal"
    }

    /// Pace the dot is plotted at: adjusted when heat mattered, else raw.
    var effectivePaceSec: Int { isHeatAdjusted ? (workPaceAdjSec ?? workPaceSec) : workPaceSec }
}

/// Zone display + ordering for the chip row and chart. Fast → slow, matching
/// the work zones the classifier emits.
enum KeyZone {
    /// Canonical fast→slow order of the work zones.
    static let order = ["mile", "3k", "5k", "10k", "hmp", "mp"]

    nonisolated static func label(_ token: String) -> String {
        switch token.lowercased() {
        case "mile": "Mile"
        case "3k": "3K"
        case "5k": "5K"
        case "10k": "10K"
        case "hmp": "HMP"
        case "mp": "MP"
        default: token.uppercased()
        }
    }

    /// Sort index for chips; unknown zones sort last.
    static func rank(_ token: String) -> Int {
        order.firstIndex(of: token.lowercased()) ?? order.count
    }
}

// MARK: - Quality volume (Section B: the work behind it)

/// One week of time-at-quality-pace, keyed by work zone. Backs the Section-B
/// stacked bars. A down week comes back with an empty `zoneSeconds` — a real
/// zero, drawn as a gap in the bar row, never faked.
///
/// Source: `trends-timeline` → `quality_volume[]`
/// (`buildQualityVolume` in `keySessions.ts`), aggregated from the same laps
/// as Section A so the two surfaces never disagree.
struct QualityVolumeWeek: Identifiable {
    let id = UUID()
    let weekStart: String       // "2026-06-08"
    let dateLabel: String       // "Jun 8"
    let zoneSeconds: [String: Int]  // work zone token → seconds

    /// Total quality seconds this week (all work zones summed).
    var total: Int { zoneSeconds.values.reduce(0, +) }
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
