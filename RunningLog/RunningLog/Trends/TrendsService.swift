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
    /// The Pace Bands surface — one band at a time (HM / MP), membership
    /// decided on heat-adjusted lap pace against a weekly-median anchor.
    /// `nil` until a load returns `pace_bands`, and `nil` for good whenever
    /// the athlete has no usable fitness anchor or nothing has held a band for
    /// longer than two minutes. The Trends row hides itself in that case
    /// rather than rendering a guessed band.
    private(set) var paceBands: PaceBands?
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
        keyVolume: [QualityVolumeWeek] = [],
        paceBands: PaceBands? = nil
    ) {
        self.weeks = weeks
        self.days = days
        self.keySessions = keySessions
        self.keyVolume = keyVolume
        self.paceBands = paceBands
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
            paceBands = payload.paceBands?.toModel()
            loaded = true
            lastError = nil
            Log.coach.info("Trends timeline loaded (\(self.weeks.count) weeks)")
        } catch {
            lastError = error
            Log.coach.error("Trends timeline load failed: \(error.localizedDescription)")
        }
    }

    /// The workouts logged on a given UTC day ("yyyy-MM-dd"), newest first —
    /// for the calendar-day / key-session drill-downs, which open the full
    /// `HistoryDetailPager`. Mirrors `TrainingPlanService.loadLogEntries`.
    @MainActor
    func fetchWorkouts(dayISO: String) async -> [TrainingLog] {
        guard let next = Self.nextDayISO(dayISO) else { return [] }
        do {
            let entries: [TrainingLog] = try await supabase
                .from("training_logs")
                .select()
                .eq("user_id", value: AuthManager.shared.userId)
                .gte("workout_date", value: dayISO)
                .lt("workout_date", value: next)
                .order("workout_date", ascending: false, nullsFirst: false)
                .limit(20)
                .execute()
                .value
            return entries
        } catch {
            Log.coach.error("Trends day workouts load failed: \(error.localizedDescription)")
            return []
        }
    }

    /// A day's logs plus the one the pager should open on.
    ///
    /// Both drill-downs land here — the lanes' day-grain tap and the week
    /// sheet's day rows — so a day can never open on one session from the
    /// chart and a different one from the week list. The ranking itself lives
    /// in `TrendsSessionOrder`, which mirrors the server's mood ordering.
    ///
    /// `entries` is passed through in feed order: `HistoryDetailPager` mirrors
    /// it into reading order itself and explicitly warns against re-sorting, so
    /// every log on the day stays reachable by paging.
    ///
    /// Returns `nil` when the day has no logs — nothing to open.
    @MainActor
    func resolveDay(dayISO: String, focusLogId: String? = nil) async -> DayWorkouts? {
        let entries = await fetchWorkouts(dayISO: dayISO)
        guard !entries.isEmpty else { return nil }

        // An explicit tap on one session wins over the ranking.
        if let focusLogId,
           let focused = entries.first(where: {
               $0.id.uuidString.lowercased() == focusLogId.lowercased()
           }) {
            return DayWorkouts(entries: entries, initial: focused)
        }

        // Quality load by log id, from the timeline the tab already holds.
        var loadByLogID: [String: Double] = [:]
        for s in keySessions where QualityLoad.qualifies(s.qualityLoad) {
            loadByLogID[s.id.lowercased()] = s.qualityLoad ?? 0
        }

        let candidates = entries.map { log in
            TrendsSessionOrder.Candidate(
                qualityLoad: loadByLogID[log.id.uuidString.lowercased()] ?? 0,
                distanceMi: log.workoutDistanceMiles ?? 0,
                at: log.displayDate
            )
        }
        let initial = TrendsSessionOrder.hardestIndex(candidates)
            .map { entries[$0] } ?? entries[0]

        return DayWorkouts(entries: entries, initial: initial)
    }

    /// "2026-07-28" → "2026-07-29".
    private static func nextDayISO(_ iso: String) -> String? {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let parts = iso.split(separator: "-")
        guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              let date = cal.date(from: DateComponents(year: y, month: m, day: d)),
              let next = cal.date(byAdding: .day, value: 1, to: date) else { return nil }
        let f = DateFormatter(); f.timeZone = TimeZone(identifier: "UTC")!; f.dateFormat = "yyyy-MM-dd"
        return f.string(from: next)
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
    /// Optional: any deploy predating `paceBands.ts` omits it, and the module
    /// itself returns null when there's no usable anchor.
    let paceBands: PaceBandsDTO?

    enum CodingKeys: String, CodingKey {
        case weeks, days, flagged, trimmed
        case qualitySessions = "quality_sessions"
        case qualityVolume = "quality_volume"
        case fastSegments = "fast_segments"
        case paceBands = "pace_bands"
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
    /// Sleep + overnight biometrics (additive, 2026-08-05). Optional: any
    /// deploy predating the decoration — or a night with no data — omits them.
    let hrvRmssd: Double?
    let restingHr: Double?
    let sleepTotalMin: Int?
    let sleepQuality: String?

    enum CodingKeys: String, CodingKey {
        case date, miles, type, mood, niggles
        case hrvRmssd = "hrv_rmssd"
        case restingHr = "resting_hr"
        case sleepTotalMin = "sleep_total_min"
        case sleepQuality = "sleep_quality"
    }

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
            niggles: niggles.map { $0.toModel() },
            hrvRmssd: hrvRmssd,
            restingHr: restingHr,
            sleepTotalMin: sleepTotalMin,
            sleepQuality: sleepQuality
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
