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
    /// The adjustable-band substrate — every lap of every session plus the
    /// week's race-pace ladder, so band width, anchor and minimums are decided
    /// on device. `nil` against a backend that predates `bandLaps.ts`, or when
    /// the athlete has no usable fitness anchor; the threshold section then
    /// falls back to the fixed `paceBands` read.
    private(set) var bandLaps: BandLaps?
    /// Implausible runs the timeline set aside (watch-not-paused etc.),
    /// undecided — surfaced to Trim or Keep. Never deleted.
    private(set) var flagged: [TrendsFlaggedRun] = []
    /// Runs the athlete explicitly trimmed — surfaced so they can Restore.
    private(set) var trimmed: [TrendsFlaggedRun] = []
    private(set) var isLoading = false
    private(set) var lastError: Error?

    /// True once a successful (or seeded) load has populated `weeks`.
    private var loaded = false

    /// The load failed and there is nothing behind it to fall back on.
    ///
    /// Views should branch on THIS rather than on `lastError != nil`: a failed
    /// background refresh sitting on top of data that is already drawn is not
    /// an error the athlete needs to be shown. An empty screen is.
    var failedWithNothingToShow: Bool { lastError != nil && !loaded }

    /// Wall-clock bound on the whole fetch. The timeline normally lands in
    /// under ten seconds. The number exists for the day the backend is unwell:
    /// on 2026-08-11 the gateway took 38-54 seconds to return a 401, and every
    /// surface that waits on this one sat on a spinner for the duration.
    private static let loadTimeout: TimeInterval = 20

    private init() {}

    /// Preview / test seam — inject a fixed window without hitting the network.
    init(
        preview weeks: [TrendsWeek],
        days: [TrendsDay] = [],
        keySessions: [KeySession] = [],
        keyVolume: [QualityVolumeWeek] = [],
        paceBands: PaceBands? = nil,
        bandLaps: BandLaps? = nil
    ) {
        self.weeks = weeks
        self.days = days
        self.keySessions = keySessions
        self.keyVolume = keyVolume
        self.paceBands = paceBands
        self.bandLaps = bandLaps
        self.loaded = true
    }

    /// Fetch the timeline. No-op if already loaded (unless `force`), so it's
    /// cheap to call on every tab entry.
    @MainActor
    func refresh(force: Bool = false) async {
        if loaded && !force { return }
        // Two surfaces now call this (Trends, and the Train tab's week strip),
        // so a second entrance while a fetch is in flight is normal. Joining
        // the fetch already running beats firing a duplicate at a backend that
        // is, by hypothesis, the slow part.
        if isLoading { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let data = try await withNetworkTimeout(seconds: Self.loadTimeout) {
                try await callEdgeFunction(name: "trends-timeline", body: ["weeks": 26])
            }
            let payload = try JSONDecoder().decode(TrendsTimelinePayload.self, from: data)
            weeks = payload.weeks.map { $0.toModel() }
            days = (payload.days ?? []).map { $0.toModel() }
            flagged = (payload.flagged ?? []).map { $0.toModel() }
            trimmed = (payload.trimmed ?? []).map { $0.toModel() }
            keySessions = (payload.qualitySessions ?? []).map { $0.toModel() }
            keyVolume = (payload.qualityVolume ?? []).map { $0.toModel() }
            fastSegments = payload.fastSegments?.toData() ?? .empty
            paceBands = payload.paceBands?.toModel()
            bandLaps = payload.bandLaps?.toModel()
            loaded = true
            lastError = nil
            Log.coach.info("Trends timeline loaded (\(self.weeks.count) weeks)")
            // Kick the TLS repair sweep once per session, off the load path —
            // see `sweepMissingStressLoads` for why a single null row matters.
            Task { await self.sweepMissingStressLoads() }
        } catch {
            lastError = error
            Log.coach.error("Trends timeline load failed: \(error.localizedDescription)")
        }
    }

    // MARK: - TLS repair sweep

    /// Once per app session; the sweep is repair, not a hot path.
    private var sweepAttempted = false
    /// More than this many broken rows means something systemic is wrong and
    /// a client loop is the wrong tool — sweep the first batch, log the rest.
    private static let sweepCap = 20

    /// Backfills `training_logs.stress_load` — TLS, weighted training-minutes
    /// — so the recovery model can measure load in it.
    ///
    /// `TrendsRecoveryDemand.loadUnit` only picks the `stressLoad` rung when
    /// EVERY run day in the window carries one (mixing units inside one EWMA
    /// is the documented artifact — see the LoadUnit doc). So a single null
    /// row silently drops the whole recovery score down the ladder to
    /// duration × channel intensity. Nulls happen two ways in practice:
    /// rows whose features were computed before the `20260731120000` column
    /// existed (batch mode skips any log that already has a features row, so
    /// they stay null forever), and Strava-ingested rows that nothing ever
    /// triggered (`strava-sync` does not call compute-workout-features).
    ///
    /// The repair: query this athlete's run logs where `stress_load` is null
    /// and invoke compute-workout-features once per log — per-log mode
    /// processes the log even when a features row already exists. When
    /// anything was repaired, reload the timeline so the recovery score
    /// recomputes in TLS on this visit rather than the next one.
    @MainActor
    private func sweepMissingStressLoads() async {
        guard !sweepAttempted else { return }
        sweepAttempted = true
        // Only bother when the loaded timeline shows a run day with no
        // stress_load — the exact condition that drops the load unit.
        guard days.contains(where: { $0.miles > 0 && $0.stressLoad == nil }) else { return }
        struct Row: Decodable { let id: UUID }
        do {
            let rows: [Row] = try await supabase
                .from("training_logs")
                .select("id")
                .eq("user_id", value: AuthManager.shared.userId)
                .is("stress_load", value: nil)
                .gt("workout_distance_miles", value: 0)
                .limit(Self.sweepCap)
                .execute()
                .value
            guard !rows.isEmpty else { return }
            var repaired = 0
            for row in rows {
                do {
                    _ = try await callEdgeFunction(
                        name: "compute-workout-features",
                        body: [
                            "user_id": AuthManager.shared.userId,
                            "training_log_id": row.id.uuidString.lowercased(),
                        ]
                    )
                    repaired += 1
                } catch {
                    Log.coach.error("TLS sweep: \(row.id) failed: \(error.localizedDescription)")
                }
            }
            Log.coach.info("TLS sweep repaired \(repaired)/\(rows.count) logs")
            if repaired > 0 { await refresh(force: true) }
        } catch {
            Log.coach.error("TLS sweep query failed: \(error.localizedDescription)")
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
                .select(TrainingLog.columns)
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
    /// The un-bucketed sibling of `pace_bands` — raw laps plus each week's
    /// race-pace ladder, so the Signal Lab's band can be re-anchored and
    /// re-widened on device. Optional for the same reason: a deploy predating
    /// `bandLaps.ts` omits it, and the section falls back to the fixed band.
    let bandLaps: BandLapsDTO?

    enum CodingKeys: String, CodingKey {
        case weeks, days, flagged, trimmed
        case qualitySessions = "quality_sessions"
        case qualityVolume = "quality_volume"
        case fastSegments = "fast_segments"
        case paceBands = "pace_bands"
        case bandLaps = "band_laps"
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
    /// Load inputs for the recovery-need demand term (additive, 2026-08-06).
    /// Optional for the same reason as the biometrics: a deploy predating them
    /// omits them, and the demand term then degrades to miles x intensity.
    let durationMin: Int?
    let stressLoad: Double?
    /// Per-zone breakdown of the day (additive, 2026-08-10). Keyed by the raw
    /// zone token from `workoutSegmentation.ts` (easy | moderate | steady | mp
    /// | hmp | 10k | 5k | 3k | mile | recovery). Optional and nil-when-absent:
    /// a deploy predating the field omits them, and so does a day whose runs
    /// carried no laps. Nil means "we cannot say", which is NOT the same as a
    /// rest day — see `TrendsDay.hasZoneBreakdown`.
    let zoneMinutes: [String: Double]?
    let zoneMiles: [String: Double]?
    let zoneLoad: [String: Double]?
    /// The day unrolled (additive, 2026-08-11). Optional and nil-when-absent
    /// for the usual reason — a deploy predating the field omits it — and the
    /// week stress strip degrades to "cannot say" rather than to "rest day".
    let runs: [TrendsRunDTO]?

    enum CodingKeys: String, CodingKey {
        case date, miles, type, mood, niggles, runs
        case hrvRmssd = "hrv_rmssd"
        case restingHr = "resting_hr"
        case sleepTotalMin = "sleep_total_min"
        case sleepQuality = "sleep_quality"
        case durationMin = "duration_min"
        case stressLoad = "stress_load"
        case zoneMinutes = "zone_minutes"
        case zoneMiles = "zone_miles"
        case zoneLoad = "zone_load"
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
            sleepQuality: sleepQuality,
            durationMin: durationMin,
            stressLoad: stressLoad,
            zoneMinutes: zoneMinutes,
            zoneMiles: zoneMiles,
            zoneLoad: zoneLoad,
            runs: (runs ?? []).compactMap { $0.toModel() }
        )
    }
}

/// One `days[].runs[]` entry. Exists so a surface can place a run at the time
/// of day it started; the day rollup above cannot express that, and cannot
/// express a double at all.
private struct TrendsRunDTO: Decodable {
    let id: String
    let startedAt: String
    let durationMin: Double
    /// Added 2026-08-11 alongside the exact-duration display. Optional so a
    /// payload predating it still decodes — it then degrades to whole minutes,
    /// which reads as `:00` seconds rather than as a wrong number.
    let durationSec: Double?
    let miles: Double
    let zoneMinutes: [String: Double]?
    let zoneMiles: [String: Double]?
    let zoneLoad: [String: Double]?

    enum CodingKeys: String, CodingKey {
        case id, miles
        case startedAt = "started_at"
        case durationMin = "duration_min"
        case durationSec = "duration_sec"
        case zoneMinutes = "zone_minutes"
        case zoneMiles = "zone_miles"
        case zoneLoad = "zone_load"
    }

    /// Nil when the row cannot be placed in time — an unparseable `started_at`
    /// or a non-UUID id. A run we cannot position is DROPPED, not defaulted to
    /// midnight: a bar sitting at the far left of Tuesday is a claim about when
    /// the athlete ran, and a wrong one is worse than a missing one.
    func toModel() -> TrendsDay.Run? {
        guard let uuid = UUID(uuidString: id),
              let parsed = Self.parse(startedAt) else { return nil }
        return TrendsDay.Run(
            id: uuid,
            startedAt: parsed.date,
            statedOffsetSeconds: parsed.statedOffset,
            durationSec: durationSec ?? (durationMin * 60),
            miles: miles,
            zoneMinutes: zoneMinutes,
            zoneMiles: zoneMiles,
            zoneLoad: zoneLoad
        )
    }

    /// Parse an ISO8601 timestamp and decide which timezone its time-of-day
    /// should be read in.
    ///
    /// THE PROBLEM. `training_logs.workout_date` is `TIMESTAMPTZ`. Postgres
    /// normalizes that to UTC on write and PostgREST returns it with a `+00:00`
    /// offset, so **the offset the run was actually recorded at is gone by the
    /// time it reaches us.** Reading the hour straight off the string puts a
    /// 6:29am Chicago run at 11:29am — which is exactly what shipped on the
    /// first pass of the week stress strip.
    ///
    /// THE RULE. A non-zero offset in the string is a real local offset that
    /// some writer went to the trouble of preserving, so it is returned and
    /// trusted. A `Z` / `+00:00` / absent offset is treated as Postgres
    /// normalization rather than a genuine UTC athlete, and returns **nil** —
    /// `TrendsDay.Run.minuteOfDay` then resolves it through `AthleteTimeZone`
    /// at read time, so the Settings choice applies immediately instead of at
    /// the next fetch.
    ///
    /// WHAT IT STILL COSTS. An athlete who has not set a zone and travels will
    /// see past runs slide, because the device zone moved under them. That is
    /// what the Settings row is for. The complete fix is a per-run offset
    /// column written at ingest — Strava sends `utc_offset` and `timezone` on
    /// the activity, Garmin/Vital send the local start — which would make the
    /// stated branch hit every time and retire the guessing entirely.
    private static func parse(_ s: String) -> (date: Date, statedOffset: Int?)? {
        guard let date = isoWithFraction.date(from: s) ?? iso.date(from: s)
                ?? dateOnly.date(from: s) else { return nil }
        let stated = offsetSeconds(in: s)
        return (date, (stated ?? 0) != 0 ? stated : nil)
    }

    /// "…+02:00" → 7200, "…-0500" → -18000, "…Z" → 0, no suffix → nil.
    private static func offsetSeconds(in s: String) -> Int? {
        guard let tIndex = s.firstIndex(of: "T") else { return nil }
        let time = s[s.index(after: tIndex)...]
        if time.hasSuffix("Z") || time.hasSuffix("z") { return 0 }
        // Scan from the end so the date's own hyphens are never mistaken for
        // a negative offset sign.
        guard let signIndex = time.lastIndex(where: { $0 == "+" || $0 == "-" })
        else { return nil }
        let sign = time[signIndex] == "-" ? -1 : 1
        let digits = time[time.index(after: signIndex)...]
            .filter { $0.isNumber }
        guard digits.count == 4,
              let h = Int(digits.prefix(2)), let m = Int(digits.suffix(2))
        else { return nil }
        return sign * (h * 3600 + m * 60)
    }

    private static let isoWithFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let dateOnly: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        return f
    }()
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
