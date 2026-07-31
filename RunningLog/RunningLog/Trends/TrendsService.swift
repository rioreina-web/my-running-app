//
//  TrendsService.swift
//  RunningLog
//
//  Loads the unified Trends timeline from the `trends-timeline` edge
//  function and exposes it as `[TrendsWeek]` for the Trends tab. Mirrors
//  the `DailyReadService` shape: an @Observable singleton with a cached
//  result + a `refresh()` the view calls on entry.
//
//  The endpoint is read-only and LLM-free; it returns the same 26-week
//  window every call and the view slices it by `TrendsRange`. See
//  `docs/specs/trends-tab-data-wiring.md` and
//  `supabase/functions/trends-timeline/`.
//

import Foundation
import os
import Supabase

@Observable
final class TrendsService {
    static let shared = TrendsService()

    /// Full window (up to 26 weeks), oldest → newest. The view slices this.
    private(set) var weeks: [TrendsWeek] = []
    /// Dense daily substrate backing the Trends-v2 calendar (Month/Block
    /// scales), oldest → newest, one entry per day through today. Rest days
    /// included so the weekday grid needs no gap-filling. Shares the weekly
    /// builder's math, so days can't drift from `weeks`.
    private(set) var days: [TrendsDay] = []
    /// Per-quality-session work-bout paces backing Section A of the Key
    /// Sessions chart. Date-sorted (oldest → newest). Empty when the athlete
    /// has no rep-level laps in range — the view shows the empty state.
    private(set) var keySessions: [KeySession] = []
    /// Weekly time-at-quality-pace backing Section B (the work behind it),
    /// oldest → newest, one entry per week in the window.
    private(set) var keyVolume: [QualityVolumeWeek] = []
    /// System-aware fast-segment trends (volume vs. each system's own range,
    /// conditions-adjusted pace, mixed-session breakdown). Empty until a load
    /// returns `fast_segments` — the Fast segments surface shows its empty state.
    private(set) var fastSegments: FastSegmentsData = .empty
    /// Implausible runs the timeline set aside (watch-not-paused etc.),
    /// undecided — surfaced to Trim or Keep. Never deleted.
    private(set) var flagged: [TrendsFlaggedRun] = []
    /// Runs the athlete explicitly trimmed — surfaced so they can Restore.
    private(set) var trimmed: [TrendsFlaggedRun] = []
    private(set) var isLoading = false
    private(set) var lastError: Error?

    /// True once a successful (or seeded) load has populated `weeks`.
    private var loaded = false

    private init() {}

    /// Preview / test seam — inject a fixed window without hitting the network.
    init(
        preview weeks: [TrendsWeek],
        days: [TrendsDay] = [],
        keySessions: [KeySession] = [],
        keyVolume: [QualityVolumeWeek] = []
    ) {
        self.weeks = weeks
        self.days = days
        self.keySessions = keySessions
        self.keyVolume = keyVolume
        self.loaded = true
    }

    /// Fetch the timeline. No-op if already loaded (unless `force`), so it's
    /// cheap to call on every tab entry.
    @MainActor
    func refresh(force: Bool = false) async {
        if loaded && !force { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let data = try await callEdgeFunction(name: "trends-timeline", body: ["weeks": 26])
            let payload = try JSONDecoder().decode(TrendsTimelinePayload.self, from: data)
            weeks = payload.weeks.map { $0.toModel() }
            days = (payload.days ?? []).map { $0.toModel() }
            flagged = (payload.flagged ?? []).map { $0.toModel() }
            trimmed = (payload.trimmed ?? []).map { $0.toModel() }
            keySessions = (payload.qualitySessions ?? []).map { $0.toModel() }
            keyVolume = (payload.qualityVolume ?? []).map { $0.toModel() }
            fastSegments = payload.fastSegments?.toData() ?? .empty
            loaded = true
            lastError = nil
            Log.coach.info("Trends timeline loaded (\(self.weeks.count) weeks)")
        } catch {
            lastError = error
            Log.coach.error("Trends timeline load failed: \(error.localizedDescription)")
        }
    }

    /// Trim (excluded = true), Keep/Restore (excluded = false) a run. Writes
    /// `training_logs.stats_excluded` (owner UPDATE is RLS-allowed), then
    /// reloads so the chart + lists recompute.
    @MainActor
    func setExcluded(_ trainingLogId: String, excluded: Bool) async {
        do {
            try await supabase
                .from("training_logs")
                .update(["stats_excluded": excluded])
                .eq("id", value: trainingLogId)
                .execute()
            await refresh(force: true)
        } catch {
            lastError = error
            Log.coach.error("setExcluded failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Wire format

/// Matches the `trends-timeline` response. Snake-case keys mapped to the
/// `TrendsWeek` view model. `mood`/`key_pace_sec`/`voice_quote` are
/// nullable — an empty week carries no fabricated values.
private struct TrendsTimelinePayload: Decodable {
    let weeks: [TrendsWeekDTO]
    let days: [TrendsDayDTO]?
    let flagged: [FlaggedRunDTO]?
    let trimmed: [FlaggedRunDTO]?
    let qualitySessions: [KeySessionDTO]?
    let qualityVolume: [QualityVolumeDTO]?
    let fastSegments: FastSegmentsDTO?

    enum CodingKeys: String, CodingKey {
        case weeks, days, flagged, trimmed
        case qualitySessions = "quality_sessions"
        case qualityVolume = "quality_volume"
        case fastSegments = "fast_segments"
    }
}

/// One `days[]` entry from `trends-timeline`. `type` is the coarse session
/// channel (key | long | easy | rest); an unknown token degrades to `rest`.
/// `niggles` are verbatim with the raw `severity_hint` passed through.
private struct TrendsDayDTO: Decodable {
    let date: String
    let miles: Double
    let type: String
    let mood: String?
    let niggles: [DayNiggleDTO]

    struct DayNiggleDTO: Decodable {
        let area: String
        let side: String?
        let severity: String?
        let quote: String

        func toModel() -> TrendsDay.DayNiggle {
            TrendsDay.DayNiggle(area: area, side: side, severity: severity, quote: quote)
        }
    }

    func toModel() -> TrendsDay {
        TrendsDay(
            date: date,
            miles: miles,
            type: TrendsDay.SessionChannel(token: type),
            mood: mood,
            niggles: niggles.map { $0.toModel() }
        )
    }
}

/// One `quality_volume[]` entry from `trends-timeline`. `zone_seconds` is a
/// free-form work-zone → seconds map; `date_label` derived from `week_start`.
private struct QualityVolumeDTO: Decodable {
    let weekStart: String
    let dateLabel: String
    let zoneSeconds: [String: Int]

    enum CodingKeys: String, CodingKey {
        case weekStart = "week_start"
        case dateLabel = "date_label"
        case zoneSeconds = "zone_seconds"
    }

    func toModel() -> QualityVolumeWeek {
        QualityVolumeWeek(weekStart: weekStart, dateLabel: dateLabel, zoneSeconds: zoneSeconds)
    }
}

/// One `quality_sessions[]` entry from `trends-timeline`. Snake-case keys
/// mapped to the `KeySession` view model; `date_label` is derived here from
/// the ISO `date` so the model carries a display string.
private struct KeySessionDTO: Decodable {
    let date: String
    let logId: String
    let zone: String
    let workPaceSec: Int
    let workPaceAdjSec: Int?
    let heatCategory: String?
    let workHrAvg: Int?
    let structure: String?
    let distanceMi: Double?
    /// Optional: older payloads (and any deploy predating `qualityLoad.ts`)
    /// omit it. A nil load never clears the key-session floor.
    let qualityLoad: Double?
    /// Optional: predates the long-run change. Absent → "quality".
    let kind: String?

    enum CodingKeys: String, CodingKey {
        case date
        case logId = "log_id"
        case zone
        case workPaceSec = "work_pace_sec"
        case workPaceAdjSec = "work_pace_adj_sec"
        case heatCategory = "heat_category"
        case workHrAvg = "work_hr_avg"
        case structure
        case distanceMi = "distance_mi"
        case qualityLoad = "quality_load"
        case kind
    }

    private static let monthAbbr = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun",
        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    ]

    /// "2026-06-23" → "Jun 23". Falls back to the raw string if unparseable.
    private var derivedLabel: String {
        let parts = date.split(separator: "-")
        guard parts.count == 3,
              let m = Int(parts[1]), (1...12).contains(m),
              let d = Int(parts[2]) else { return date }
        return "\(Self.monthAbbr[m - 1]) \(d)"
    }

    func toModel() -> KeySession {
        KeySession(
            id: logId,
            date: date,
            dateLabel: derivedLabel,
            zone: zone,
            workPaceSec: workPaceSec,
            workPaceAdjSec: workPaceAdjSec,
            heatCategory: heatCategory,
            workHrAvg: workHrAvg,
            structure: structure,
            distanceMi: distanceMi,
            qualityLoad: qualityLoad,
            kind: kind ?? "quality"
        )
    }
}

/// A run the timeline set aside as implausible (e.g. watch left running).
/// Surfaced for review/trim — never auto-deleted.
struct TrendsFlaggedRun: Identifiable {
    let id: String          // training_log_id
    let date: String        // "2026-04-10"
    let miles: Double
    let pace: String?
    let reason: String
}

private struct FlaggedRunDTO: Decodable {
    let date: String
    let miles: Double
    let pace: String?
    let reason: String
    let trainingLogId: String

    enum CodingKeys: String, CodingKey {
        case date, miles, pace, reason
        case trainingLogId = "training_log_id"
    }

    func toModel() -> TrendsFlaggedRun {
        TrendsFlaggedRun(id: trainingLogId, date: date, miles: miles, pace: pace, reason: reason)
    }
}

private struct TrendsWeekDTO: Decodable {
    let weekStart: String
    let month: String
    let dateLabel: String
    let miles: Double
    let qualityMiles: Double
    let keyPaceSec: Int?
    let mood: String?
    let niggles: [String]
    let voiceQuote: String?

    enum CodingKeys: String, CodingKey {
        case weekStart = "week_start"
        case month
        case dateLabel = "date_label"
        case miles
        case qualityMiles = "quality_miles"
        case keyPaceSec = "key_pace_sec"
        case mood
        case niggles
        case voiceQuote = "voice_quote"
    }

    func toModel() -> TrendsWeek {
        TrendsWeek(
            month: month,
            dateLabel: dateLabel,
            miles: miles,
            qualityMiles: qualityMiles,
            keyPaceSec: keyPaceSec,
            mood: mood ?? "",          // "" = no mood; the chart skips the dot
            niggles: niggles,
            voiceQuote: voiceQuote,
            weekStart: weekStart
        )
    }
}
