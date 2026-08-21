//
//  TrainingAnalyticsViewModel.swift
//  RunningLog
//
//  Data engine for the analytical **Training** tab (replaces the old
//  Train + Trends tabs — see `training-tab-spec.md`). One scope toggle
//  (WEEK · MONTH · BLOCK) re-renders every section against the selected
//  window. Everything is anchored to CURRENT fitness, never goal fitness:
//  pace-zone boundaries, histogram markers and zone coloring all derive
//  from the latest `FitnessSnapshot`'s race predictions plus the runner's
//  actual logged easy pace. Goal-derived numbers live only in the
//  collapsed Goals section.
//
//  Real-data sources (no fabricated values — per spec §core-rule-5):
//    • training_logs (last 400d) via TodayLogRow.fetchRecent — distance,
//      pace, type, mood, pace_segments (time-in-pace-zone primitive).
//    • Latest FitnessSnapshot via FitnessPredictorService.fetchHistory —
//      current predicted MP / HM(LT) / 5K paces.
//    • TrainingPlanService — active goal, plan block bounds, weekly target.
//    • RPE columns on training_logs (felt_rpe / planned_rpe / pull-quote /
//      tags), populated by the `extract-rpe` edge function. Fetched
//      resiliently: if the migration hasn't run yet the felt/planned
//      section simply renders nothing rather than fabricating effort.
//
//  In-progress weeks are excluded from averages and comparisons — this is
//  the bug that produced "−100% vs prior".
//

import Foundation
import SwiftUI
import Supabase
import os

// MARK: - Scope

enum TrainingScope: String, CaseIterable, Identifiable {
    case week, month, block
    var id: String { rawValue }
    var label: String {
        switch self {
        case .week:  return "Week"
        case .month: return "Month"
        case .block: return "Block"
        }
    }
}

/// Which volume chart the expanded detail sheet is showing.
enum VolumeChartKind: String, Identifiable {
    case intensity, easyHard, pace
    var id: String { rawValue }
    var title: String {
        switch self {
        case .intensity: return "Volume · By Intensity"
        case .easyHard:  return "Easy / Hard"
        case .pace:      return "Volume × Pace"
        }
    }
    /// Whether the x-axis is pace (fixed anchors) vs categorical bars.
    var isPaceAxis: Bool { self == .pace }
}

// MARK: - Intensity ramp (10 zones, pale sky → navy)
//
// The universal pace ramp: one hue, ten depths — pale sky (easy)
// through mid-blue to navy (mile+). Every colour means a pace.
// Mirrors `PaceSpectrum.stops` — the ten stops map to the canonical
// 10-zone taxonomy (Easy · Moderate · Steady · MP · HMP · LT · 10K · 5K ·
// 3K · Mile). Anything faster than mile clips to the Mile navy.

enum IntensityRamp {
    /// z1 (Easy) → z10 (Mile). Same hexes as `PaceSpectrum.stops`.
    static let colors: [Color] = [
        Color(hex: "93B9D6"), // z1 Easy (pale sky)
        Color(hex: "74A8CC"), // z2 Moderate
        Color(hex: "578FC0"), // z3 Steady
        Color(hex: "3F7CB5"), // z4 MP
        Color(hex: "2F66A8"), // z5 HMP
        Color(hex: "27549B"), // z6 LT / threshold+
        Color(hex: "20448B"), // z7 10K
        Color(hex: "1A3679"), // z8 5K
        Color(hex: "142964"), // z9 3K
        Color(hex: "0E1D4E"), // z10 Mile (navy)
    ]

    /// Stacked-bar simplification: easy = z1, aerobic = z3, threshold+ = z6.
    static var easy: Color      { colors[0] }
    static var aerobic: Color   { colors[2] }
    static var threshold: Color { colors[5] }

    /// RGB stops (0–255) mirroring `colors`, for continuous interpolation.
    private static let rgbStops: [(r: Double, g: Double, b: Double)] = [
        (147, 185, 214), // z1 Easy (pale sky)
        (116, 168, 204), // z2 Moderate
        ( 87, 143, 192), // z3 Steady
        ( 63, 124, 181), // z4 MP
        ( 47, 102, 168), // z5 HMP
        ( 39,  84, 155), // z6 LT / threshold+
        ( 32,  68, 139), // z7 10K
        ( 26,  54, 121), // z8 5K
        ( 20,  41, 100), // z9 3K
        ( 14,  29,  78), // z10 Mile (navy)
    ]

    /// Continuous spectrum colour at `t` in [0, 1] — 0 = slowest (pale),
    /// 1 = fastest (navy). Linearly interpolates between adjacent
    /// stops so the ramp reads as a smooth depth scale, not discrete bands.
    static func color(at t: Double) -> Color {
        let clamped = min(max(t, 0), 1)
        let scaled = clamped * Double(rgbStops.count - 1)
        let i = min(Int(scaled), rgbStops.count - 2)
        let f = scaled - Double(i)
        let a = rgbStops[i], b = rgbStops[i + 1]
        return Color(
            red:   (a.r + (b.r - a.r) * f) / 255.0,
            green: (a.g + (b.g - a.g) * f) / 255.0,
            blue:  (a.b + (b.b - a.b) * f) / 255.0
        )
    }

    /// Smooth left-to-right gradient of the full ramp — for legend bands.
    static var gradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
    }

    /// Colour for an absolute pace (sec/mi). `slowSec` anchors the pale
    /// (easy) end, `fastSec` the navy (mile) end. Faster paces
    /// (smaller seconds) move up the ramp. This is the *pace-zone* mapping:
    /// the same pace is the same colour in every chart, independent of any
    /// single workout's spread.
    static func color(forPaceSec pace: Double, slowSec: Double, fastSec: Double) -> Color {
        guard slowSec > fastSec else { return easy }
        return color(at: (slowSec - pace) / (slowSec - fastSec))
    }

    /// Ramp colour for a histogram bin, `0` slowest … `binCount-1` fastest.
    /// Samples the continuous spectrum rather than snapping to a stop.
    static func color(forBin index: Int, binCount: Int) -> Color {
        guard binCount > 1 else { return easy }
        return color(at: Double(index) / Double(binCount - 1))
    }
}

/// The three stacked buckets used across volume charts. Collapses the
/// five pace-zones (recovery/easy/moderate/tempo/intervals) into the
/// editorial easy / aerobic / threshold+ split the spec renders.
enum IntensityBucket: Hashable {
    case easy, aerobic, threshold
    var color: Color {
        switch self {
        case .easy:      return IntensityRamp.easy
        case .aerobic:   return IntensityRamp.aerobic
        case .threshold: return IntensityRamp.threshold
        }
    }
}

// MARK: - Aggregate value types

/// easy / aerobic / threshold+ miles for a single day or week.
struct ZoneSplit: Equatable {
    var easy: Double = 0
    var aerobic: Double = 0
    var threshold: Double = 0
    var total: Double { easy + aerobic + threshold }
    var hardMiles: Double { aerobic + threshold }

    /// Hardest bucket present, for the day-grid tick colour.
    var hardestBucket: IntensityBucket {
        if threshold > 0 { return .threshold }
        if aerobic > 0 { return .aerobic }
        return .easy
    }

    static func + (a: ZoneSplit, b: ZoneSplit) -> ZoneSplit {
        ZoneSplit(easy: a.easy + b.easy,
                  aerobic: a.aerobic + b.aerobic,
                  threshold: a.threshold + b.threshold)
    }
}

/// One bar in the WEEK volume chart.
struct DayVolume: Identifiable {
    let id = UUID()
    let date: Date
    let label: String       // MON / TUE …
    let split: ZoneSplit
    let isRest: Bool        // logged nothing, in the past
    let isFuture: Bool      // upcoming day (dashed placeholder)
}

/// One bar in the MONTH volume chart (a week) and one row in BLOCK.
struct WeekVolume: Identifiable {
    let id = UUID()
    let weekStart: Date
    let label: String       // MAY 11 …
    let split: ZoneSplit
    let inProgress: Bool     // current, partial week — excluded from avgs
}

/// One cell in the mileage-by-day grid.
struct DayCell: Identifiable {
    let id = UUID()
    let date: Date
    let miles: Double
    let split: ZoneSplit
    let isRest: Bool
    let isFuture: Bool
    /// Estimated distance from the active plan for an upcoming day. Kept
    /// separate from `miles` (logged) so plan estimates never inflate the
    /// logged weekly/block totals. 0 when there's no plan or no session.
    var plannedMiles: Double = 0
    /// An upcoming day that the plan has a run scheduled for.
    var isPlanned: Bool = false
}

/// One row of the mileage-by-day grid (a week, Mon→Sun).
struct GridWeek: Identifiable {
    let id = UUID()
    let label: String
    let weekStart: Date
    let cells: [DayCell]
}

/// A single logged session, surfaced when a day cell is tapped.
struct SessionDetail: Identifiable {
    let id: UUID
    let date: Date
    let typeLabel: String
    let miles: Double
    let pace: String?
    let pullQuote: String?    // voice-memo / cleaned-notes
    let feltLine: String?     // "FELT 8/10 · PLANNED 6/10 · TIRED"
    let bucket: IntensityBucket
    /// Writer of this row: `voice_log` | `auto_sync` | `strava`.
    let source: String?

    /// True when the full `WorkoutAnalystView` (stream charts) can be
    /// reached for this row. Only Strava rows carry `external_streams`
    /// JSONB today, so gate on source to avoid opening an empty analysis.
    var canOpenAnalysis: Bool { (source ?? "").lowercased() == "strava" }
}

/// One split/lap row in the Day Detail sheet — distance, pace, HR, and
/// the pace-zone color. `paceSeconds` also drives the row's mini bar.
struct DaySplit: Identifiable {
    let id = UUID()
    let index: Int
    let distanceMiles: Double
    let paceSeconds: Double
    /// How long the split took. The splits table reads as a rep-by-rep clock,
    /// so duration is the headline number; pace is still carried because the
    /// intensity colouring is bucketed off it.
    let elapsedSeconds: Double
    let hr: Int?
    let color: Color
}

/// Aggregate stats for a whole day (may span multiple sessions).
struct DaySummary {
    let totalMiles: Double
    let totalMinutes: Double
    let avgPaceSeconds: Double?   // sec/mi, nil when miles/time missing
    let runCount: Int
    let zone: ZoneSplit           // easy / aerobic / threshold miles
}

/// A bin in the volume × pace histogram.
struct PaceBin: Identifiable {
    let id = UUID()
    let index: Int
    let miles: Double
    let color: Color
}

/// A vertical marker over the histogram, anchored to current fitness.
struct PaceMarker: Identifiable {
    let id = UUID()
    let label: String
    let paceSeconds: Double
    let color: Color
    /// 0 = slow (left), 1 = fast (right).
    func fraction(slow: Double, fast: Double) -> Double {
        guard slow > fast else { return 0 }
        return min(1, max(0, (slow - paceSeconds) / (slow - fast)))
    }
}

/// One row of the easy-pace trend line (month scope).
struct EasyPacePoint: Identifiable {
    let id = UUID()
    let weekStart: Date
    let avgPaceSeconds: Double
}

/// One hard session in the felt-vs-planned section.
struct FeltVsPlanned: Identifiable {
    let id: UUID
    let date: Date
    let typeLabel: String
    let felt: Int
    let planned: Int
    var matched: Bool { felt <= planned }
}

/// Aggregated weather for one completed run, built from the raw GPS lap
/// rows (`running_workout_laps.temp_f / dew_point_f /
/// heat_adjusted_pace_sec_per_mile`). Surfaced as a conditions readout on
/// the CURRENT week's day rows — observation only, never advice.
struct RunConditions {
    var tempF: Int?
    var dewPointF: Int?
    /// Seconds per mile the heat cost — raw pace minus heat-adjusted
    /// ("fair air") pace, distance-agnostic mean over work laps carrying
    /// both. Only kept when ≥ 3 s/mi (the same threshold
    /// `WorkoutForecast` uses) so trivial noise never renders.
    var heatCostSecPerMile: Int?

    /// "Hot run" per the dewpoint-first heuristic the heat model uses.
    var isHot: Bool { (dewPointF ?? 0) >= 65 || (tempF ?? 0) >= 78 }

    /// "74° · DP 68° · HEAT ADJ −9S" — absent components drop out.
    var readout: String? {
        var parts: [String] = []
        if let t = tempF { parts.append("\(t)°") }
        if let d = dewPointF { parts.append("DP \(d)°") }
        if let h = heatCostSecPerMile { parts.append("HEAT ADJ −\(h)S") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

struct SummaryStats {
    var miles: Double = 0
    var runs: Int = 0
    var durationMinutes: Double = 0
    var easyPercent: Int = 0
    /// Count of voice-memo / qualitative entries in the window — rows that
    /// carry a recording (`audio_url` non-nil) or were written as a
    /// `voice_log` / `check_in` (see `isVoiceMemo`). Surfaces the qualitative
    /// input stream alongside the quantitative one — a plain count, never
    /// interpreted on this tab.
    var voiceMemos: Int = 0
}

struct BlockStats {
    var blockMiles: Double = 0
    var avgWeek: Double = 0          // completed weeks only
    var peakWeek: Double = 0
    var longRun: Double = 0
    var label: String = "BLOCK"      // e.g. "BASE BLOCK · WK 4 OF 20"
}

struct GoalsSummary {
    let raceGoal: String          // "SUB-1:07 HALF · OCT 3"
    let currentFitness: String    // "1:12 – 1:14"
    let gap: String               // "5–7 MIN · 16 WKS"
    let weeklyTarget: String?     // "30 MI → 45 MI"
}

// MARK: - View model

@MainActor
@Observable
final class TrainingAnalyticsViewModel {

    // Selected scope. Persisted so deep-linking back returns the user
    // to the same window.
    var scope: TrainingScope = .week {
        didSet {
            UserDefaults.standard.set(scope.rawValue, forKey: Self.scopeKey)
            // Switching Week ↔ Month ↔ Block re-anchors the calendar on the
            // current period — a deep-history offset in one scope shouldn't
            // strand the athlete in a different window after a scope flip.
            if scope != oldValue { calendarPeriodOffset = 0 }
        }
    }
    private static let scopeKey = "training.analytics.scope"

    /// Calendar-mode period paging. 0 = the current period (the window ending
    /// this week); each increment steps one whole window into the past so the
    /// athlete can review history. Forward paging never goes past the current
    /// period. Calendar mode only — the Current and History surfaces stay
    /// anchored to now.
    var calendarPeriodOffset = 0

    var isLoading = false
    var hasLoaded = false
    /// True when the initial load failed (e.g. no connection). Lets the
    /// view show a Retry state instead of an empty analytics screen.
    var loadFailed = false

    // Raw inputs
    private var logs: [TodayLogRow] = []            // deduped, ascending by date
    private var rpeByLog: [UUID: RPERow] = [:]

    // Performance caches. All `@ObservationIgnored` so writing to them from a
    // getter during a view render never triggers observation (which would
    // cause "modifying state during update" loops). They're derived purely
    // from `logs` + `scope`, both observed, so correctness is preserved:
    // `rebuildLogIndex()` bumps `cacheToken` on every reload, and the memo
    // getters re-key on `scope`.
    //
    // `logsByDay` makes `logs(on:)` / `logs(inWeekStarting:)` O(1) lookups
    // instead of full-history filters — those were called weeks×7 times per
    // redraw from gridWeeks()/dayVolumes(), the main source of Train-tab lag.
    @ObservationIgnored private var logsByDay: [Date: [TodayLogRow]] = [:]
    @ObservationIgnored private var cacheToken = 0
    @ObservationIgnored private var weekVolumesCache: (token: Int, scope: TrainingScope, value: [WeekVolume])?
    @ObservationIgnored private var gridWeeksCache: (token: Int, scope: TrainingScope, offset: Int, value: [GridWeek])?
    @ObservationIgnored private var dayVolumesCache: (token: Int, value: [DayVolume])?
    @ObservationIgnored private var easyPaceTrendCache: (token: Int, scope: TrainingScope, value: [EasyPacePoint])?
    // Splits are fetched per session (laps query) on demand; cache so
    // re-opening the same day doesn't refetch. Cleared on reload.
    private var splitsCache: [UUID: [DaySplit]] = [:]
    /// Weather readouts for THIS week's runs, keyed by training-log id.
    /// Loaded in one batched `running_workout_laps` query after the main
    /// load — an enrichment: absence just means no readout renders.
    private(set) var conditionsByLog: [UUID: RunConditions] = [:]
    private(set) var snapshot: FitnessSnapshot?     // latest current-fitness
    private(set) var goals: GoalsSummary?
    private var planStart: Date?
    private var planTotalWeeks: Int?
    private var planLabel: String?
    /// Planned distance (miles) per calendar day, from the active plan's
    /// scheduled workouts. Drives the calendar's estimated upcoming days.
    /// Empty when no plan is active.
    private var plannedMilesByDay: [Date: Double] = [:]

    private let cal = Calendar.iso8601Monday
    private let log = Logger(subsystem: "com.runninglog", category: "training-analytics")

    init() {
        if let raw = UserDefaults.standard.string(forKey: Self.scopeKey),
           let s = TrainingScope(rawValue: raw) {
            scope = s
        }
    }

    // MARK: Load

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        // Stale-while-revalidate fast path: if a last-known snapshot exists
        // (memory or disk via TrainingLogStore), build the charts from it
        // NOW so the tab renders instantly; the network pass below replaces
        // it seconds later. Enrichments (snapshot, goals, RPE, weather)
        // arrive with the network pass — charts first, garnish after.
        if !hasLoaded {
            let cached = TrainingLogStore.shared.cachedRows(days: 400)
            if !cached.isEmpty {
                logs = cached.dedupedByPhysicalWorkout().sorted { $0.date < $1.date }
                rebuildLogIndex()
                hasLoaded = true
            }
        }

        // Logs (400d covers any block) — deduped before any aggregation.
        // Through the shared store: coalesces with any launch-time refresh
        // from Log/Today, and persists the snapshot for next launch. The
        // throwing path is kept so a real failure surfaces a Retry state —
        // but only when there's no cached data on screen; stale charts beat
        // an error screen.
        let fetched: [TodayLogRow]
        do {
            fetched = try await TrainingLogStore.shared.refresh(days: 400)
        } catch {
            log.error("Training analytics load failed: \(error.localizedDescription)")
            if !hasLoaded { loadFailed = true }
            return
        }
        loadFailed = false
        logs = fetched.dedupedByPhysicalWorkout().sorted { $0.date < $1.date }
        rebuildLogIndex()         // refresh day index + invalidate memo caches

        splitsCache.removeAll()   // logs changed — drop stale per-session splits

        // The steps below are two independent chains, so run them
        // concurrently instead of serially — previously each `await` blocked
        // the next and the tab's load time was the SUM of ~6 round trips
        // (see PERF-AUDIT-2026-08-10.md, finding #3). Only the plan/goals
        // step has a real dependency (it reads `snapshot`, so it must follow
        // fetchHistory); everything else just needs `logs`, already in hand.
        //
        // Key-session ingest: feed the store the DEDUPED set. It sums
        // quality_load per day off these ids; raw rows would double-count a
        // run that arrived from both Strava and HealthKit. LogDedup is the
        // canonical picker — the store must not reimplement it.
        async let keySessionIngest: Void = KeySessionStore.shared.ingestLoads(forDedupedLogs: logs)
        // RPE columns (resilient — empty if the migration hasn't run).
        async let rpeFetch = RPERow.fetchRecent(days: 120)
        // Weather on this week's runs (CURRENT-mode conditions readouts).
        async let conditionsFetch: Void = loadCurrentWeekConditions()

        // Current-fitness snapshot (cheap — reads the history table), then
        // goals + plan block bounds, which read the snapshot.
        let predictor = FitnessPredictorService()
        await predictor.fetchHistory()
        snapshot = predictor.snapshotHistory.max(by: { $0.createdAt < $1.createdAt })
        await loadPlanAndGoals(predictor: predictor)

        rpeByLog = await rpeFetch
        _ = await (keySessionIngest, conditionsFetch)

        hasLoaded = true
    }

    /// Batched fetch of lap-level weather for this week's runs. One query,
    /// aggregated per run: max temp, max dewpoint, mean heat cost. Degrades
    /// to an empty map on any failure — the readout is enrichment, never
    /// load-bearing.
    private func loadCurrentWeekConditions() async {
        let ids = logs(inWeekStarting: thisWeekStart).map(\.id.uuidString)
        guard !ids.isEmpty else { conditionsByLog = [:]; return }
        struct LapWx: Decodable {
            let workout_id: UUID
            let temp_f: Double?
            let dew_point_f: Double?
            let avg_pace_sec_per_mile: Double?
            let heat_adjusted_pace_sec_per_mile: Double?
            let is_rest: Bool?
        }
        do {
            let rows: [LapWx] = try await supabase
                .from("running_workout_laps")
                .select("workout_id,temp_f,dew_point_f,avg_pace_sec_per_mile,heat_adjusted_pace_sec_per_mile,is_rest")
                .in("workout_id", values: ids)
                .execute().value
            var out: [UUID: RunConditions] = [:]
            for (id, laps) in Dictionary(grouping: rows, by: { $0.workout_id }) {
                var c = RunConditions()
                if let t = laps.compactMap(\.temp_f).max() { c.tempF = Int(t.rounded()) }
                if let d = laps.compactMap(\.dew_point_f).max() { c.dewPointF = Int(d.rounded()) }
                let costs = laps.filter { $0.is_rest != true }.compactMap { l -> Double? in
                    guard let raw = l.avg_pace_sec_per_mile,
                          let adj = l.heat_adjusted_pace_sec_per_mile,
                          raw > adj else { return nil }
                    return raw - adj
                }
                if !costs.isEmpty {
                    let mean = costs.reduce(0, +) / Double(costs.count)
                    if mean >= 3 { c.heatCostSecPerMile = Int(mean.rounded()) }
                }
                if c.tempF != nil || c.dewPointF != nil { out[id] = c }
            }
            conditionsByLog = out
        } catch {
            conditionsByLog = [:]
            log.error("Week conditions load failed: \(error.localizedDescription)")
        }
    }

    /// Conditions for a day — the day's biggest run that has a readout.
    func conditions(on day: Date) -> RunConditions? {
        for row in logs(on: day).sorted(by: { ($0.miles ?? 0) > ($1.miles ?? 0) }) {
            if let c = conditionsByLog[row.id] { return c }
        }
        return nil
    }

    /// The day's mood label — preferring the biggest run's mood, falling
    /// back to any logged mood that day (e.g. a rest-day check-in).
    /// Verbatim from the closed vocabulary; rendered by `MoodBadge`.
    func mood(on day: Date) -> String? {
        logs(on: day)
            .sorted { ($0.miles ?? 0) > ($1.miles ?? 0) }
            .compactMap(\.mood)
            .first { !$0.isEmpty }
    }

    /// Runs this week logged in hot conditions (dewpoint ≥ 65° or ≥ 78°).
    func hotRunCount() -> Int { hotRunCount(forWeekStart: thisWeekStart) }

    func hotRunCount(forWeekStart start: Date) -> Int {
        logs(inWeekStarting: start)
            .filter { conditionsByLog[$0.id]?.isHot == true }
            .count
    }

    /// Quiet qualitative observation for the week — the athlete's own
    /// fatigue-class mood labels, verbatim, with their weekdays. Nil when
    /// the week carried none. Observation only; never advice (the "push or
    /// pull" call belongs to the athlete/coach — AI advises, never acts).
    func weekMoodObservation() -> String? { weekMoodObservation(forWeekStart: thisWeekStart) }

    func weekMoodObservation(forWeekStart start: Date) -> String? {
        let fatigueMoods: Set<String> = ["tired", "struggling", "injured"]
        var seen = Set<String>()
        let f = DateFormatter(); f.dateFormat = "EEEE"
        let hits: [String] = logs(inWeekStarting: start).compactMap { row in
            guard let m = row.mood?.lowercased(), fatigueMoods.contains(m) else { return nil }
            let key = "\(m)-\(cal.startOfDay(for: row.date))"
            guard seen.insert(key).inserted else { return nil }
            return "\u{201C}\(m)\u{201D} \(f.string(from: row.date))"
        }
        guard !hits.isEmpty else { return nil }
        return "You logged " + hits.joined(separator: " · ") + "."
    }

    private func loadPlanAndGoals(predictor: FitnessPredictorService) async {
        let planService = TrainingPlanService()
        await planService.loadActivePlan(then: {})

        if let plan = planService.activePlan {
            planStart = cal.startOfDay(for: plan.startDate)
            let weeks = cal.dateComponents([.weekOfYear], from: plan.startDate, to: plan.endDate).weekOfYear
            planTotalWeeks = weeks.map { max(1, $0) }
        }

        // Estimated distance per upcoming day, summed across any scheduled
        // sessions on that date. Logged totals are untouched by this.
        var byDay: [Date: Double] = [:]
        for sw in planService.allScheduledWorkouts {
            let miles = sw.workout?.totalDistanceMiles ?? 0
            guard miles > 0 else { continue }
            byDay[cal.startOfDay(for: sw.date), default: 0] += miles
        }
        plannedMilesByDay = byDay
        gridWeeksCache = nil   // planned data arrived — force a recompute

        goals = Self.buildGoals(plan: planService.activePlan,
                                goal: planService.activeGoal,
                                snapshot: snapshot,
                                avgWeekMiles: averageWeeklyMiles())
        if let plan = planService.activePlan, let total = planTotalWeeks {
            let wk = currentBlockWeekIndex() + 1
            planLabel = "\(plan.name.uppercased()) · WK \(wk) OF \(total)"
        }
    }

    // MARK: Current-fitness paces (seconds per mile)

    var marathonPaceSec: Double? {
        snapshot.map { Double($0.predictedMarathonSeconds) / 26.21875 }
    }
    var halfPaceSec: Double? {   // HMP — current predicted half pace
        snapshot.map { Double($0.predictedHalfSeconds) / RaceDistanceConstants.halfMarathonMiles }
    }
    /// LT = one-hour race pace (canonical), interpolated between 10K and half
    /// via `PaceCalculator` so it never collapses onto half pace for runners
    /// whose half takes over an hour. See the pace-zone rules in CLAUDE.md.
    var thresholdPaceSec: Double? {
        guard let s = snapshot else { return nil }
        return PaceCalculator.calculateOneHourPace(fromDistance: "5K",
                                                    totalSeconds: Int(s.predicted5kSeconds))
    }
    var tenKPaceSec: Double? {
        snapshot.map { Double($0.predicted10kSeconds) / RaceDistanceConstants.tenKMiles }
    }
    var fiveKPaceSec: Double? {
        snapshot.map { Double($0.predicted5kSeconds) / 3.106856 }
    }
    /// EASY marker = median pace of recent logged easy runs; falls back to
    /// MP × 1.30 when there aren't enough easy runs yet.
    var easyPaceSec: Double? {
        if let m = medianEasyPaceSeconds() { return m }
        return marathonPaceSec.map { $0 * 1.30 }
    }
    /// The anchor the pace-ratio classifier keys off — current MP.
    private var mpAnchor: Double { marathonPaceSec ?? 0 }

    // MARK: Scope window → list of week-starts rendered

    /// Monday of the current ISO week.
    private var thisWeekStart: Date { cal.startOfWeek(for: Date()) }

    /// Week-starts (ascending) the current scope renders, oldest → newest.
    private func scopedWeekStarts() -> [Date] {
        switch scope {
        case .week:
            return [thisWeekStart]
        case .month:
            return (0..<5).reversed().compactMap {
                cal.date(byAdding: .weekOfYear, value: -$0, to: thisWeekStart)
            }
        case .block:
            let weeks = blockWeekCount()
            return (0..<weeks).reversed().compactMap {
                cal.date(byAdding: .weekOfYear, value: -$0, to: thisWeekStart)
            }
        }
    }

    // MARK: Calendar-mode window (offset-aware, for TrainingCalendarSection)

    /// How many weeks the current scope's calendar window spans. This is also
    /// the step size for one page back/forward.
    private func calendarStepWeeks() -> Int {
        switch scope {
        case .week:  return 1
        case .month: return 5
        case .block: return blockWeekCount()
        }
    }

    /// The newest week-start in the currently paged calendar window. At offset
    /// 0 this is `thisWeekStart`; each page-back steps one whole window earlier.
    private var calendarAnchorWeekStart: Date {
        let step = calendarStepWeeks()
        return cal.date(byAdding: .weekOfYear,
                        value: -(max(0, calendarPeriodOffset) * step),
                        to: thisWeekStart) ?? thisWeekStart
    }

    /// Week-starts (ascending) the paged calendar renders, oldest → newest.
    /// Mirrors `scopedWeekStarts()` but anchored on `calendarAnchorWeekStart`
    /// so Calendar mode can move through history; the analytics surfaces keep
    /// using `scopedWeekStarts()` and stay pinned to now.
    private func calendarWeekStarts() -> [Date] {
        let anchor = calendarAnchorWeekStart
        let n = calendarStepWeeks()
        return (0..<n).reversed().compactMap {
            cal.date(byAdding: .weekOfYear, value: -$0, to: anchor)
        }
    }

    /// True when the calendar is showing the current, up-to-now period.
    var calendarIsCurrent: Bool { calendarPeriodOffset == 0 }

    /// Human label for the paged window — "WEEK OF MAR 3" (week) or
    /// "MAR 3 – APR 6" (month/block).
    var calendarRangeLabel: String {
        let starts = calendarWeekStarts()
        guard let first = starts.first, let last = starts.last else { return "" }
        if scope == .week {
            return "WEEK OF \(Self.monthDayLabel(first))"
        }
        let end = cal.date(byAdding: .day, value: 6, to: last) ?? last
        return "\(Self.monthDayLabel(first)) – \(Self.monthDayLabel(end))"
    }

    /// Step one whole window into the past.
    func calendarGoBack() { calendarPeriodOffset += 1 }

    /// Step one window forward (toward now); never past the current period.
    func calendarGoForward() {
        if calendarPeriodOffset > 0 { calendarPeriodOffset -= 1 }
    }

    /// Jump straight back to the current period.
    func calendarGoToCurrent() { calendarPeriodOffset = 0 }

    /// Number of weeks in the block window. Uses elapsed plan weeks (capped
    /// at 12 for legibility) when a plan exists, else a rolling 5 weeks.
    private func blockWeekCount() -> Int {
        guard let start = planStart else { return 5 }
        let elapsed = (cal.dateComponents([.weekOfYear], from: start, to: thisWeekStart).weekOfYear ?? 4) + 1
        return min(12, max(1, elapsed))
    }

    private func currentBlockWeekIndex() -> Int {
        guard let start = planStart else { return 0 }
        return max(0, cal.dateComponents([.weekOfYear], from: start, to: thisWeekStart).weekOfYear ?? 0)
    }

    // MARK: Per-day / per-week aggregation

    /// Rebuild the day index from `logs` and invalidate the memo caches. Call
    /// whenever `logs` changes. Keyed by start-of-day so per-day / per-week
    /// lookups are dictionary hits rather than full-array scans.
    private func rebuildLogIndex() {
        var index: [Date: [TodayLogRow]] = [:]
        for row in logs {
            index[cal.startOfDay(for: row.date), default: []].append(row)
        }
        logsByDay = index
        cacheToken &+= 1
        weekVolumesCache = nil
        gridWeeksCache = nil
        dayVolumesCache = nil
        easyPaceTrendCache = nil
    }

    private func logs(on day: Date) -> [TodayLogRow] {
        logsByDay[cal.startOfDay(for: day)] ?? []
    }

    private func logs(inWeekStarting weekStart: Date) -> [TodayLogRow] {
        let start = cal.startOfDay(for: weekStart)
        var out: [TodayLogRow] = []
        for offset in 0..<7 {
            guard let day = cal.date(byAdding: .day, value: offset, to: start) else { continue }
            if let rows = logsByDay[cal.startOfDay(for: day)] { out.append(contentsOf: rows) }
        }
        return out
    }

    /// Split a single run's miles into easy/aerobic/threshold buckets using
    /// pace_segments when present (the real time-in-pace-zone primitive),
    /// falling back to the run's average pace.
    private func split(for log: TodayLogRow) -> ZoneSplit {
        var out = ZoneSplit()
        if let segments = log.paceSegments, !segments.isEmpty {
            for seg in segments where seg.distanceMiles > 0 {
                let bucket = self.bucket(forPaceSeconds: paceSeconds(seg.pacePerMile))
                add(seg.distanceMiles, to: bucket, in: &out)
            }
            // Reconcile rounding drift against the row's logged miles.
            if let miles = log.miles, miles > 0, out.total > 0 {
                let scale = miles / out.total
                out = ZoneSplit(easy: out.easy * scale,
                                aerobic: out.aerobic * scale,
                                threshold: out.threshold * scale)
            }
            return out
        }
        guard let miles = log.miles, miles > 0 else { return out }
        add(miles, to: bucket(forPaceSeconds: avgPaceSeconds(for: log)), in: &out)
        return out
    }

    private func add(_ miles: Double, to bucket: IntensityBucket, in split: inout ZoneSplit) {
        switch bucket {
        case .easy:      split.easy += miles
        case .aerobic:   split.aerobic += miles
        case .threshold: split.threshold += miles
        }
    }

    /// Bucket boundaries as a multiple of current marathon pace. A pace
    /// faster than `thresholdRatio × MP` is threshold+, between that and
    /// `easyRatio × MP` is aerobic, slower than `easyRatio × MP` is easy.
    /// Shared by the classifier and the zone pace-band guideline so the
    /// two never drift.
    static let thresholdRatio = 1.07
    static let easyRatio = 1.20

    /// Pace-ratio classifier, anchored to CURRENT marathon pace. Mirror of
    /// the 5-zone scheme used across the app, collapsed to 3 buckets.
    private func bucket(forPaceSeconds paceSec: Double?) -> IntensityBucket {
        guard let paceSec, paceSec > 0, mpAnchor > 0 else { return .easy }
        let ratio = paceSec / mpAnchor
        if ratio < Self.thresholdRatio { return .threshold }
        if ratio < Self.easyRatio { return .aerobic }
        return .easy
    }

    /// Human-readable pace band for a zone, anchored to current MP. nil
    /// when there's no fitness snapshot to anchor on.
    func zoneGuideline(_ b: IntensityBucket) -> String? {
        guard let mp = marathonPaceSec, mp > 0 else { return nil }
        let easyEdge = mp * Self.easyRatio        // slow edge (easy ≥ this)
        let hardEdge = mp * Self.thresholdRatio   // fast edge of aerobic
        switch b {
        case .easy:      return "SLOWER THAN \(Self.formatPaceMMSS(easyEdge))"
        case .aerobic:   return "\(Self.formatPaceMMSS(easyEdge))–\(Self.formatPaceMMSS(hardEdge))"
        case .threshold: return "FASTER THAN \(Self.formatPaceMMSS(hardEdge))"
        }
    }

    private func split(forDay day: Date) -> ZoneSplit {
        logs(on: day).map(split(for:)).reduce(ZoneSplit(), +)
    }

    private func split(forWeekStarting weekStart: Date) -> ZoneSplit {
        logs(inWeekStarting: weekStart).map(split(for:)).reduce(ZoneSplit(), +)
    }

    // MARK: Outputs — summary

    func summary() -> SummaryStats {
        let rows: [TodayLogRow]
        switch scope {
        case .week:  rows = logs(inWeekStarting: thisWeekStart)
        case .month: rows = logsInLast(days: 30)
        case .block: rows = logsInScopedWeeks()
        }
        var s = SummaryStats()
        var split = ZoneSplit()
        for r in rows {
            s.miles += r.miles ?? 0
            s.runs += 1
            s.durationMinutes += r.durationMinutes ?? 0
            if isVoiceMemo(r) { s.voiceMemos += 1 }
            split = split + self.split(for: r)
        }
        s.easyPercent = split.total > 0 ? Int((split.easy / split.total * 100).rounded()) : 0
        return s
    }

    /// Whether a row represents a voice memo / qualitative journal entry.
    ///
    /// `source == "voice_log"` alone under-counts: the dedup cron (and the
    /// one-time `20260702150000_reattach_voice_memos_to_runs` migration)
    /// folds a voice memo about a GPS run onto the run row, deleting the
    /// standalone `voice_log` entry and leaving `source == "strava"` with a
    /// non-nil `audio_url`. So the recording itself — not the writer label —
    /// is the reliable signal. Mirrors the backend's own qualitative /
    /// audio-bearing definition (`source IN ('voice_log','check_in') OR
    /// audio_url IS NOT NULL`) from `20260702200000_dedupe_never_touch_voice_logs`.
    /// Note: `manual` is intentionally excluded — a typed run is not a memo.
    private func isVoiceMemo(_ r: TodayLogRow) -> Bool {
        if r.audioUrl != nil { return true }
        switch r.source {
        case "voice_log", "check_in": return true
        default: return false
        }
    }

    private func logsInLast(days: Int) -> [TodayLogRow] {
        guard let cutoff = cal.date(byAdding: .day, value: -days, to: Date()) else { return logs }
        return logs.filter { $0.date >= cutoff }
    }

    private func logsInScopedWeeks() -> [TodayLogRow] {
        let starts = scopedWeekStarts()
        guard let first = starts.first else { return [] }
        return logs.filter { $0.date >= first }
    }

    // MARK: Outputs — volume by intensity

    func dayVolumes() -> [DayVolume] {
        if let c = dayVolumesCache, c.token == cacheToken { return c.value }
        let value = computeDayVolumes()
        dayVolumesCache = (cacheToken, value)
        return value
    }

    private func computeDayVolumes() -> [DayVolume] {
        dayVolumes(forWeekStart: thisWeekStart)
    }

    /// Monday start of the week `weeksAgo` before the current one (0 = current).
    func weekStart(weeksAgo: Int) -> Date {
        cal.date(byAdding: .weekOfYear, value: -max(0, weeksAgo), to: thisWeekStart) ?? thisWeekStart
    }

    /// True when `start` is the current, in-progress week.
    func isCurrentWeek(_ start: Date) -> Bool {
        cal.isDate(start, inSameDayAs: thisWeekStart)
    }

    /// Total miles logged in the week beginning `start`.
    func weekTotalMiles(forWeekStart start: Date) -> Double {
        split(forWeekStarting: start).total
    }

    /// Day rows (Mon→Sun) for the week beginning `start`. Same shape as
    /// `dayVolumes()` but for any week, so the This-Week section can page back.
    func dayVolumes(forWeekStart start: Date) -> [DayVolume] {
        let today = cal.startOfDay(for: Date())
        return (0..<7).compactMap { offset in
            guard let day = cal.date(byAdding: .day, value: offset, to: start) else { return nil }
            let split = self.split(forDay: day)
            let isFuture = day > today
            let isRest = !isFuture && split.total == 0
            return DayVolume(date: day,
                             label: Self.weekdayLabel(day),
                             split: split,
                             isRest: isRest,
                             isFuture: isFuture)
        }
    }

    func weekVolumes() -> [WeekVolume] {
        if let c = weekVolumesCache, c.token == cacheToken, c.scope == scope { return c.value }
        let value = scopedWeekStarts().map { ws in
            WeekVolume(weekStart: ws,
                       label: Self.monthDayLabel(ws),
                       split: split(forWeekStarting: ws),
                       inProgress: cal.isDate(ws, inSameDayAs: thisWeekStart))
        }
        weekVolumesCache = (cacheToken, scope, value)
        return value
    }

    /// 4-week rolling average of weekly miles, completed weeks only, aligned
    /// to `weekVolumes()`. Returns nil entries where a window isn't full.
    func rollingFourWeekAverage() -> [Double?] {
        let weeks = weekVolumes()
        let totals = weeks.map { $0.inProgress ? Double.nan : $0.split.total }
        return weeks.indices.map { i in
            let lo = max(0, i - 3)
            let window = totals[lo...i].filter { !$0.isNaN }
            guard window.count >= 1 else { return nil }
            return window.reduce(0, +) / Double(window.count)
        }
    }

    func blockStats() -> BlockStats {
        let weeks = weekVolumes()
        let completed = weeks.filter { !$0.inProgress }
        var s = BlockStats()
        s.blockMiles = weeks.reduce(0) { $0 + $1.split.total }
        s.avgWeek = completed.isEmpty ? 0 : completed.reduce(0) { $0 + $1.split.total } / Double(completed.count)
        s.peakWeek = weeks.map { $0.split.total }.max() ?? 0
        s.longRun = longestRunMiles(inScopedWeeks: true)
        s.label = planLabel ?? "BLOCK · LAST \(weeks.count) WEEKS"
        return s
    }

    // MARK: Outputs — the week in progress

    // These mirror `VolumeDetailView` (Trends › Load) definition for
    // definition, deliberately: one week must not read "on pace ~32" here and
    // "~34" there. Change one, change both.
    //
    //   • miles so far — logged this ISO week; honest and partial
    //   • projection   — flat per-day rate × 7, rounded, labelled "~"
    //   • 4-week avg   — the last four COMPLETED weeks that have miles. The
    //                    in-progress week is excluded, or a Tuesday glance
    //                    would be measured against a baseline it just dragged
    //                    down and every mid-week would read as a shortfall.
    //
    // The average is taken from the four weeks before this one DIRECTLY, not
    // from `weekVolumes()` — that array follows the scope segmenter, and on
    // WEEK scope it holds a single week, which would collapse the average to
    // zero without anything on screen saying why.

    /// Monday = 1 … Sunday = 7. How far into the current week we are.
    var daysIntoWeek: Int {
        var c = Calendar(identifier: .iso8601)
        c.firstWeekday = 2
        let weekday = c.component(.weekday, from: Date())   // 1=Sun…7=Sat
        return ((weekday + 5) % 7) + 1
    }

    var isWeekComplete: Bool { daysIntoWeek >= 7 }

    /// Miles logged so far in the current week.
    func thisWeekMiles() -> Double { weekTotalMiles(forWeekStart: thisWeekStart) }

    /// Where the week lands if the rest of it runs like the days so far.
    /// An estimate, never a promise — the UI marks it "~". Once the week is
    /// complete this is simply the total.
    func projectedWeekMiles() -> Double {
        let soFar = thisWeekMiles()
        guard !isWeekComplete, daysIntoWeek > 0 else { return soFar }
        return soFar / Double(daysIntoWeek) * 7
    }

    /// Average weekly miles over the last four completed weeks. 0 when there
    /// is nothing to average — callers show a dash rather than a fake zero.
    func fourWeekAvgMiles() -> Double {
        let totals = (1...4)
            .compactMap { cal.date(byAdding: .weekOfYear, value: -$0, to: thisWeekStart) }
            .map { weekTotalMiles(forWeekStart: $0) }
            .filter { $0 > 0 }
        guard !totals.isEmpty else { return 0 }
        return totals.reduce(0, +) / Double(totals.count)
    }

    /// The projected week against that average, as a whole percent. nil when
    /// there is no baseline — no baseline means no comparison, not "+0%".
    func percentVsFourWeekAvg() -> Int? {
        let avg = fourWeekAvgMiles()
        guard avg > 0 else { return nil }
        return Int(((projectedWeekMiles() - avg) / avg * 100).rounded())
    }

    /// The longest single run in the last 30 days. Rows are deduped by
    /// physical workout upstream, so an AM/PM day can't sum into a fake
    /// long run.
    func longestRunLast30Days() -> Double {
        logsInLast(days: 30).compactMap { $0.miles }.max() ?? 0
    }

    /// Easy share over the same 30 days, so the sub-line's two numbers are
    /// measured over one window and can be labelled once.
    func easyPercentLast30Days() -> Int {
        let split = logsInLast(days: 30).map(self.split(for:)).reduce(ZoneSplit(), +)
        guard split.total > 0 else { return 0 }
        return Int((split.easy / split.total * 100).rounded())
    }

    private func longestRunMiles(inScopedWeeks: Bool) -> Double {
        let rows = inScopedWeeks ? logsInScopedWeeks() : logs
        return rows.compactMap { $0.miles }.max() ?? 0
    }

    // MARK: Outputs — mileage by day grid

    func gridWeeks() -> [GridWeek] {
        if let c = gridWeeksCache, c.token == cacheToken, c.scope == scope,
           c.offset == calendarPeriodOffset { return c.value }
        let value = computeGridWeeks()
        gridWeeksCache = (cacheToken, scope, calendarPeriodOffset, value)
        return value
    }

    private func computeGridWeeks() -> [GridWeek] {
        let today = cal.startOfDay(for: Date())
        return calendarWeekStarts().map { ws in
            let cells: [DayCell] = (0..<7).compactMap { offset in
                guard let day = cal.date(byAdding: .day, value: offset, to: ws) else { return nil }
                let split = self.split(forDay: day)
                let isFuture = day > today
                let isRest = !isFuture && split.total == 0
                // Upcoming days carry a plan estimate (if any); logged `miles`
                // stays 0 for them so totals remain logged-only.
                let planned = isFuture ? (plannedMilesByDay[cal.startOfDay(for: day)] ?? 0) : 0
                return DayCell(date: day, miles: split.total, split: split,
                               isRest: isRest, isFuture: isFuture,
                               plannedMiles: planned, isPlanned: planned > 0)
            }
            return GridWeek(label: Self.monthDayLabel(ws), weekStart: ws, cells: cells)
        }
    }

    /// Sessions logged on a tapped day — drives the inline detail expansion.
    func sessions(on day: Date) -> [SessionDetail] {
        logs(on: day).map(sessionDetail(from:))
    }

    /// Shared row → `SessionDetail` mapper, used by every surface that
    /// lists runs (day expansion + the volume-detail sheet).
    private func sessionDetail(from row: TodayLogRow) -> SessionDetail {
        let rpe = rpeByLog[row.id]
        return SessionDetail(
            id: row.id,
            date: row.date,
            typeLabel: Self.typeLabel(row.typeKey),
            miles: row.miles ?? 0,
            pace: row.pace,
            // `rpe_pull_quote` is extracted from the memo, so it is already the
            // athlete's. `cleanedNotes` is not: on a synced run it holds
            // Strava's auto-title, and the day sheet was rendering “Evening
            // Run” in italic quotation marks under the session header — the
            // same typographic voice it uses for a real memo. Quote marks are a
            // claim about authorship; only put words inside them the athlete
            // actually said.
            pullQuote: rpe?.pullQuote ?? PlaceholderNote.athleteWords(row.cleanedNotes),
            feltLine: feltLine(for: row, rpe: rpe),
            bucket: split(for: row).hardestBucket,
            source: row.source
        )
    }

    /// Per-split rows for a session — the splits table in the Day Detail
    /// sheet. Prefers `external_streams.laps` (rep/lap granularity, carries
    /// HR); falls back to the in-memory per-mile `pace_segments` (effort +
    /// HR). Each row is colored by the current-fitness pace bucket so it
    /// reads in the same vocabulary as the volume charts.
    func splits(forSessionId id: UUID) async -> [DaySplit] {
        if let cached = splitsCache[id] { return cached }
        let result = await computeSplits(forSessionId: id)
        splitsCache[id] = result
        return result
    }

    private func computeSplits(forSessionId id: UUID) async -> [DaySplit] {
        guard let row = logs.first(where: { $0.id == id }) else { return [] }

        if (row.source ?? "").lowercased() == "strava",
           let laps = await ExternalStreamAdapter.loadLaps(forTrainingLogId: id),
           laps.count >= 2 {
            return laps.enumerated().map { (i, lap) in
                DaySplit(index: i + 1,
                         distanceMiles: lap.distanceMiles,
                         paceSeconds: lap.paceSeconds,
                         elapsedSeconds: lap.elapsedSeconds,
                         hr: lap.avgHeartRate,
                         color: bucket(forPaceSeconds: lap.paceSeconds).color)
            }
        }

        let segs = (row.paceSegments ?? []).filter { $0.distanceMiles > 0 }
        return segs.enumerated().compactMap { (i, seg) in
            let p = paceSeconds(seg.pacePerMile)
            guard p > 0 else { return nil }
            // The per-mile fallback path carries no clock of its own, so the
            // duration here is derived rather than measured.
            return DaySplit(index: i + 1,
                            distanceMiles: seg.distanceMiles,
                            paceSeconds: p,
                            elapsedSeconds: p * seg.distanceMiles,
                            hr: seg.avgHeartRate,
                            color: bucket(forPaceSeconds: p).color)
        }
    }

    /// The day's "session of note" — the hardest-intensity run, ties broken by
    /// distance. Lets a doubles day be labelled by its KEY workout rather than
    /// the first (often easy) leg of the day. nil when nothing with miles ran.
    func dominantSession(on day: Date) -> SessionDetail? {
        func rank(_ b: IntensityBucket) -> Int {
            switch b {
            case .threshold: return 2
            case .aerobic:   return 1
            case .easy:      return 0
            }
        }
        return sessions(on: day)
            .filter { $0.miles > 0 }
            .max { a, b in
                rank(a.bucket) != rank(b.bucket)
                    ? rank(a.bucket) < rank(b.bucket)
                    : a.miles < b.miles
            }
    }

    /// Aggregate summary for a whole day (sums every logged session).
    func daySummary(_ day: Date) -> DaySummary {
        let rows = logs(on: day)
        let miles = rows.compactMap { $0.miles }.reduce(0, +)
        let mins = rows.compactMap { $0.durationMinutes }.reduce(0, +)
        let zone = rows.map(split(for:)).reduce(ZoneSplit(), +)
        let avg = (miles > 0 && mins > 0) ? (mins / miles) * 60 : nil
        return DaySummary(totalMiles: miles, totalMinutes: mins,
                          avgPaceSeconds: avg, runCount: rows.count, zone: zone)
    }

    /// Build a `RunningWorkout` for a session row so the day-detail can
    /// deep-link into `WorkoutAnalystView`. The row id doubles as the
    /// `training_logs` id the analyst uses to load `external_streams`
    /// (path 1). `logs` is already deduped, so for a day with a Strava
    /// import this resolves to that GPS row — the one holding streams.
    func runningWorkout(forSessionId id: UUID) -> RunningWorkout? {
        guard let row = logs.first(where: { $0.id == id }),
              let miles = row.miles, miles > 0,
              let mins = row.durationMinutes, mins > 0 else { return nil }
        let sourceApp = (row.source ?? "").lowercased() == "strava"
            ? "Strava"
            : (row.source ?? "Unknown")
        return RunningWorkout(
            id: row.id,
            startDate: row.date,
            endDate: row.date.addingTimeInterval(mins * 60),
            distanceMiles: miles,
            durationMinutes: mins,
            pacePerMile: mins / miles,
            calories: 0,
            sourceApp: sourceApp,
            vitalWorkoutId: nil
        )
    }

    // MARK: Outputs — volume detail (expanded sheets)

    /// One bar in an expanded volume chart, carrying everything the detail
    /// sheet needs: the x label, exact miles, color, and a `key` that
    /// resolves back to the runs that built the bar.
    struct VolumeDetailBar: Identifiable {
        let id = UUID()
        let label: String          // x-axis label (MON · MAY 11 · EASY · 7:00…)
        let miles: Double
        let color: Color
        let key: SessionKey
        /// Optional secondary line — e.g. the pace band for a zone.
        var subLabel: String? = nil
    }

    /// How a bar maps back to its contributing runs.
    enum SessionKey: Hashable {
        case day(Date)
        case week(Date)
        case bucket(IntensityBucket)
        case paceBin(Int)
    }

    /// Bars for the expanded view of a given chart, in the current scope.
    func detailBars(for kind: VolumeChartKind) -> [VolumeDetailBar] {
        switch kind {
        case .intensity:
            if scope == .week {
                return dayVolumes().map {
                    VolumeDetailBar(label: $0.label, miles: $0.split.total,
                                    color: $0.split.hardestBucket.color, key: .day($0.date))
                }
            }
            return weekVolumes().map {
                VolumeDetailBar(label: $0.label, miles: $0.split.total,
                                color: $0.split.hardestBucket.color, key: .week($0.weekStart))
            }
        case .easyHard:
            let s = scopedSplit()
            return [
                VolumeDetailBar(label: "EASY", miles: s.easy,
                                color: IntensityRamp.easy, key: .bucket(.easy),
                                subLabel: zoneGuideline(.easy)),
                VolumeDetailBar(label: "AEROBIC", miles: s.aerobic,
                                color: IntensityRamp.aerobic, key: .bucket(.aerobic),
                                subLabel: zoneGuideline(.aerobic)),
                VolumeDetailBar(label: "THRESHOLD+", miles: s.threshold,
                                color: IntensityRamp.threshold, key: .bucket(.threshold),
                                subLabel: zoneGuideline(.threshold)),
            ]
        case .pace:
            // Named canonical zones (not fixed pace bins). Each logged mile
            // lands in the zone whose pace window contains it, so the rows
            // read Easy / Moderate / Steady / MP / LT / 10K / 5K / Faster
            // instead of arbitrary 13-second slots.
            let bands = paceZoneBands()
            guard !bands.isEmpty else { return [] }
            var miles = [Double](repeating: 0, count: bands.count)
            for row in scopedRowsForHistogram() {
                distributeIntoBands(row, bands: bands, into: &miles)
            }
            return bands.enumerated().map { (i, band) in
                VolumeDetailBar(label: band.label, miles: miles[i],
                                color: band.color, key: .paceBin(i),
                                subLabel: band.rangeText)
            }
        }
    }

    /// The runs that contributed to a given bar.
    func sessions(forKey key: SessionKey) -> [SessionDetail] {
        switch key {
        case .day(let d):
            return sessions(on: d)
        case .week(let ws):
            return logs(inWeekStarting: ws).map(sessionDetail(from:)).sorted { $0.date > $1.date }
        case .bucket(let b):
            return scopedRowsForHistogram()
                .filter { split(for: $0).hardestBucket == b }
                .map(sessionDetail(from:)).sorted { $0.date > $1.date }
        case .paceBin(let i):
            // A run is listed under the zone of its average pace (the bar's
            // miles use rep-level structure, but a run maps to one row here).
            let bands = paceZoneBands()
            guard bands.indices.contains(i) else { return [] }
            let band = bands[i]
            return scopedRowsForHistogram()
                .filter { row in
                    guard let p = avgPaceSeconds(for: row) else { return false }
                    return band.contains(p)
                }
                .map(sessionDetail(from:)).sorted { $0.date > $1.date }
        }
    }

    /// Total miles in the current scope (header figure for detail sheets).
    func scopedTotalMiles() -> Double { scopedSplit().total }

    /// Round a max-miles value up to a legible axis top (whole numbers for
    /// small windows, multiples of 5 / 10 as volume grows). Shared by the
    /// inline histogram and the expanded charts.
    static func niceMilesTop(_ v: Double) -> Double {
        if v <= 5 { return max(1, ceil(v)) }
        if v <= 20 { return (v / 5).rounded(.up) * 5 }
        return (v / 10).rounded(.up) * 10
    }

    static func fmtMiles(_ v: Double) -> String {
        v == v.rounded() ? String(format: "%.0f", v) : String(format: "%.1f", v)
    }

    private func feltLine(for row: TodayLogRow, rpe: RPERow?) -> String? {
        guard let felt = rpe?.feltRpe else {
            // No extracted RPE — surface mood instead of fabricating effort.
            return row.mood.map { "\($0.uppercased())" }
        }
        let planned = rpe?.plannedRpe ?? Self.defaultPlanned(for: row.typeKey)
        var line = "FELT \(felt)/10 · PLANNED \(planned)/10"
        if let tags = rpe?.tags, !tags.isEmpty {
            line += " · " + tags.joined(separator: " ").uppercased()
        }
        return line
    }

    // MARK: Outputs — easy / hard split

    func easyHardSplit() -> (easyPercent: Int, hardPercent: Int) {
        let split = scopedSplit()
        guard split.total > 0 else { return (0, 0) }
        let easy = Int((split.easy / split.total * 100).rounded())
        return (easy, 100 - easy)
    }

    private func scopedSplit() -> ZoneSplit {
        switch scope {
        case .week:  return split(forWeekStarting: thisWeekStart)
        case .month: return logsInLast(days: 30).map(split(for:)).reduce(ZoneSplit(), +)
        case .block: return logsInScopedWeeks().map(split(for:)).reduce(ZoneSplit(), +)
        }
    }

    // MARK: Outputs — volume × pace histogram

    static let histogramBinCount = 18
    /// Axis bounds in seconds/mile: 8:00 (slow, left) → 4:30 (fast, right).
    let axisSlowSeconds: Double = 480   // 8:00/mi
    let axisFastSeconds: Double = 240   // 4:00/mi — was 4:30, too slow to hold sub-5:00 rep work

    func paceHistogram() -> [PaceBin] {
        let n = Self.histogramBinCount
        var miles = [Double](repeating: 0, count: n)
        let step = (axisSlowSeconds - axisFastSeconds) / Double(n)
        for row in scopedRowsForHistogram() {
            distribute(row, into: &miles, step: step)
        }
        return miles.enumerated().map { (i, m) in
            PaceBin(index: i, miles: m, color: IntensityRamp.color(forBin: i, binCount: n))
        }
    }

    private func scopedRowsForHistogram() -> [TodayLogRow] {
        switch scope {
        case .week:  return logs(inWeekStarting: thisWeekStart)
        case .month: return logsInLast(days: 30)
        case .block: return logsInScopedWeeks()
        }
    }

    private func distribute(_ row: TodayLogRow, into miles: inout [Double], step: Double) {
        let n = miles.count
        func addMiles(_ m: Double, paceSec: Double) {
            guard paceSec > 0, m > 0 else { return }
            let idx = Int((axisSlowSeconds - paceSec) / step)
            miles[min(n - 1, max(0, idx))] += m
        }
        // Prefer the athlete's REP-LEVEL structure: each rep and recovery is
        // counted at its OWN pace, so a 4:40 interval rep lands in the fast bands
        // instead of being averaged into the 6:30 mile it lived inside. This is
        // the fix for "my sub-5:00 reps don't show up." `pace_segments` (per-mile
        // splits) and the whole-run average are fallbacks for runs with no
        // parsed structure. Any distance the structure didn't cover (a warmup or
        // cooldown the parser skipped) is added at the run average so the total
        // volume still balances.
        if let blocks = row.structureBlocks, !blocks.isEmpty {
            var covered = 0.0
            for b in blocks {
                guard let d = b.distanceMiles, d > 0,
                      let ap = b.avgPace else { continue }   // standing rests carry no pace
                let p = paceSeconds(ap)
                guard p > 0 else { continue }
                addMiles(d, paceSec: p)
                covered += d
            }
            if let total = row.miles, total - covered > 0.15 {
                addMiles(total - covered, paceSec: avgPaceSeconds(for: row) ?? 0)
            }
            return
        }
        if let segs = row.paceSegments, !segs.isEmpty {
            for seg in segs { addMiles(seg.distanceMiles, paceSec: paceSeconds(seg.pacePerMile)) }
        } else if let m = row.miles {
            addMiles(m, paceSec: avgPaceSeconds(for: row) ?? 0)
        }
    }

    func paceMarkers() -> [PaceMarker] {
        var out: [PaceMarker] = []
        // Marker colors ride the universal pace ramp (PaceSpectrum)
        // so the labels match the zone color under them in the histogram.
        // EASY uses the legibility-darkened text variant — the true Easy
        // stop is too pale for 11 pt text on paper.
        if let e = easyPaceSec      { out.append(PaceMarker(label: "EASY", paceSeconds: e, color: PaceSpectrum.easyText)) }
        if let mp = marathonPaceSec { out.append(PaceMarker(label: "MP", paceSeconds: mp, color: PaceSpectrum.mp)) }
        if let lt = thresholdPaceSec { out.append(PaceMarker(label: "LT", paceSeconds: lt, color: PaceSpectrum.lt)) }
        if let k = fiveKPaceSec     { out.append(PaceMarker(label: "5K", paceSeconds: k, color: PaceSpectrum.fiveK)) }
        return out
    }

    // MARK: Outputs — canonical pace-zone bands (Volume × Pace breakdown)

    /// One named training zone in the Volume × Pace breakdown, ordered
    /// slowest → fastest. `slowEdge` is the slower (greater sec/mi) bound and
    /// `fastEdge` the faster (smaller sec/mi) bound; the slowest zone runs to
    /// +∞ and the fastest to 0, so every logged mile falls in exactly one.
    struct PaceZoneBand: Identifiable {
        let id = UUID()
        let label: String
        let color: Color
        let slowEdge: Double
        let fastEdge: Double
        let rangeText: String
        func contains(_ paceSec: Double) -> Bool { paceSec >= fastEdge && paceSec < slowEdge }
    }

    /// The canonical named pace zones, anchored to CURRENT fitness. Zone
    /// centres come from the fitness snapshot's race predictions (MP, LT, 10K,
    /// 5K) plus the runner's real easy pace; Moderate/Steady interpolate
    /// between Easy and MP using the canonical share-of-MP-speed factor.
    /// Boundaries are midpoints between adjacent centres. Returns [] when
    /// there's no snapshot to anchor on. Mirrors the taxonomy in CLAUDE.md;
    /// HMP/3K/Mile fold into their neighbours to keep the distribution legible.
    func paceZoneBands() -> [PaceZoneBand] {
        guard let mp = marathonPaceSec, mp > 0 else { return [] }
        let easyC     = easyPaceSec ?? mp * 1.30
        let steadyC   = mp / 0.925                 // Steady speed = 0.925 × MP speed
        let moderateC = (easyC + steadyC) / 2      // between Easy and Steady
        let ltC       = thresholdPaceSec ?? mp * 0.955
        let tenKC     = tenKPaceSec ?? (ltC + (fiveKPaceSec ?? ltC * 0.95)) / 2
        let fiveKC    = fiveKPaceSec ?? tenKC * 0.96
        let fasterC   = fiveKC * 0.94              // representative sub-5K rep pace

        // (label, colour, centre) slowest → fastest.
        let raw: [(String, Color, Double)] = [
            ("EASY",     PaceSpectrum.easyText, easyC),
            ("MODERATE", PaceSpectrum.moderate, moderateC),
            ("STEADY",   PaceSpectrum.steady,   steadyC),
            ("MP",       PaceSpectrum.mp,       mp),
            ("LT",       PaceSpectrum.lt,       ltC),
            ("10K",      PaceSpectrum.tenK,     tenKC),
            ("5K",       PaceSpectrum.fiveK,    fiveKC),
            ("FASTER",   PaceSpectrum.mile,     fasterC),
        ]

        // Keep only strictly-decreasing centres so the midpoints are always
        // well-defined, even if two predictions crowd together.
        var zones: [(String, Color, Double)] = []
        for z in raw {
            if let last = zones.last, z.2 >= last.2 { continue }
            zones.append(z)
        }
        guard zones.count >= 2 else { return [] }

        return zones.enumerated().map { (i, z) in
            let slowEdge = i == 0 ? Double.infinity : (zones[i - 1].2 + z.2) / 2
            let fastEdge = i == zones.count - 1 ? 0 : (z.2 + zones[i + 1].2) / 2
            let rangeText: String
            if i == 0 {
                rangeText = "SLOWER THAN \(Self.formatPaceMMSS(fastEdge))"
            } else if i == zones.count - 1 {
                rangeText = "FASTER THAN \(Self.formatPaceMMSS(slowEdge))"
            } else {
                rangeText = "\(Self.formatPaceMMSS(slowEdge))–\(Self.formatPaceMMSS(fastEdge))"
            }
            return PaceZoneBand(label: z.0, color: z.1, slowEdge: slowEdge,
                                fastEdge: fastEdge, rangeText: rangeText)
        }
    }

    /// Distribute one run's miles into the zone bands, preferring rep-level
    /// structure (so a 4:40 rep lands in FASTER, not averaged into the easy
    /// miles around it), then per-mile segments, then the whole-run average.
    /// Same source precedence as the continuous histogram's `distribute`.
    private func distributeIntoBands(_ row: TodayLogRow, bands: [PaceZoneBand], into miles: inout [Double]) {
        func add(_ m: Double, paceSec: Double) {
            guard m > 0, paceSec > 0,
                  let idx = bands.firstIndex(where: { $0.contains(paceSec) }) else { return }
            miles[idx] += m
        }
        if let blocks = row.structureBlocks, !blocks.isEmpty {
            var covered = 0.0
            for b in blocks {
                guard let d = b.distanceMiles, d > 0, let ap = b.avgPace else { continue }
                let p = paceSeconds(ap)
                guard p > 0 else { continue }
                add(d, paceSec: p)
                covered += d
            }
            if let total = row.miles, total - covered > 0.15 {
                add(total - covered, paceSec: avgPaceSeconds(for: row) ?? 0)
            }
            return
        }
        if let segs = row.paceSegments, !segs.isEmpty {
            for seg in segs { add(seg.distanceMiles, paceSec: paceSeconds(seg.pacePerMile)) }
        } else if let m = row.miles {
            add(m, paceSec: avgPaceSeconds(for: row) ?? 0)
        }
    }

    // MARK: Outputs — easy pace trend (month scope)

    func easyPaceTrend() -> [EasyPacePoint] {
        if let c = easyPaceTrendCache, c.token == cacheToken, c.scope == scope { return c.value }
        let value = scopedWeekStarts().compactMap { ws -> EasyPacePoint? in
            // One pass: compute each row's pace once, keep only easy ones.
            let paces = logs(inWeekStarting: ws).compactMap { row -> Double? in
                let p = avgPaceSeconds(for: row)
                return bucket(forPaceSeconds: p) == .easy ? p : nil
            }
            guard !paces.isEmpty else { return nil }
            return EasyPacePoint(weekStart: ws, avgPaceSeconds: paces.reduce(0, +) / Double(paces.count))
        }
        easyPaceTrendCache = (cacheToken, scope, value)
        return value
    }

    /// "▼ 19 SEC / 4 WK" delta string, or nil when there isn't enough trend.
    func easyPaceDelta() -> String? {
        let pts = easyPaceTrend()
        guard let first = pts.first, let last = pts.last, pts.count >= 2 else { return nil }
        let delta = Int((first.avgPaceSeconds - last.avgPaceSeconds).rounded())
        guard abs(delta) >= 1 else { return nil }
        let arrow = delta > 0 ? "▼" : "▲"
        return "\(arrow) \(abs(delta)) SEC / \(pts.count - 1) WK"
    }

    // MARK: Outputs — felt vs planned
    //
    // NOT DEAD CODE. The rendered section was replaced by
    // `WeekTrainingLoadSection` on 2026-08-10, so nothing calls
    // `feltVsPlanned()` from a view right now — but `feltInsight()` below
    // reads it, and that sentence is a candidate for the header insight
    // slot. Deliberately unlinked, not abandoned; deleting the model would
    // take the insight with it.

    func feltVsPlanned() -> [FeltVsPlanned] {
        // Only hard sessions, only where felt RPE actually exists.
        let rows = logsInLast(days: scope == .week ? 10 : (scope == .month ? 35 : 120))
        return rows.compactMap { row -> FeltVsPlanned? in
            guard let rpe = rpeByLog[row.id], let felt = rpe.feltRpe else { return nil }
            guard split(for: row).hardMiles > 0 || Self.isHardType(row.typeKey) else { return nil }
            let planned = rpe.plannedRpe ?? Self.defaultPlanned(for: row.typeKey)
            return FeltVsPlanned(id: row.id, date: row.date,
                                 typeLabel: Self.typeLabel(row.typeKey),
                                 felt: felt, planned: planned)
        }
        .sorted { $0.date > $1.date }
    }

    // MARK: Insight sentences (data-derived, never fabricated)

    func headlineInsight() -> String {
        let s = summary()
        guard s.runs > 0 else {
            return "No runs logged in this window yet."
        }
        let target = 80
        if let hard = hardestSession() {
            if s.easyPercent >= target {
                return "\(s.runs) runs in, \(s.easyPercent)% easy — right on the polarised line. \(hard) was the session that earned its place."
            }
            return "\(s.runs) runs, \(s.easyPercent)% easy. Hard share is creeping above the 80/20 line — \(hard) led it."
        }
        return "\(s.runs) runs, \(formatMiles(s.miles)) miles, \(s.easyPercent)% easy."
    }

    private func hardestSession() -> String? {
        let rows = scopedRowsForHistogram()
        let hardest = rows
            .filter { split(for: $0).hardMiles > 0 }
            .min { (avgPaceSeconds(for: $0) ?? .greatestFiniteMagnitude) < (avgPaceSeconds(for: $1) ?? .greatestFiniteMagnitude) }
        return hardest.map { Self.typeLabel($0.typeKey).capitalized + " on " + Self.monthDayLabel($0.date).capitalized }
    }

    func feltInsight() -> String? {
        let rows = feltVsPlanned()
        guard rows.count >= 2 else { return nil }
        let over = rows.prefix(3).filter { !$0.matched }.count
        if over >= 2 {
            return "Two of your last three hard sessions felt harder than planned. Worth an extra easy day before the next one."
        }
        return "Effort is tracking the plan — felt and planned line up on your recent hard days."
    }

    // MARK: Averages used by goals

    private func averageWeeklyMiles() -> Double {
        let weeks = (0..<5).reversed().compactMap {
            cal.date(byAdding: .weekOfYear, value: -$0, to: thisWeekStart)
        }
        let completed = weeks.filter { !cal.isDate($0, inSameDayAs: thisWeekStart) }
        let totals = completed.map { ws in logs(inWeekStarting: ws).compactMap { $0.miles }.reduce(0, +) }
        guard !totals.isEmpty else { return 0 }
        return totals.reduce(0, +) / Double(totals.count)
    }

    private func medianEasyPaceSeconds() -> Double? {
        let paces = logsInLast(days: 30)
            .filter { bucket(forPaceSeconds: avgPaceSeconds(for: $0)) == .easy }
            .compactMap { avgPaceSeconds(for: $0) }
            .sorted()
        guard !paces.isEmpty else { return nil }
        let mid = paces.count / 2
        return paces.count % 2 == 0 ? (paces[mid - 1] + paces[mid]) / 2 : paces[mid]
    }

    // MARK: Pace helpers

    private func paceSeconds(_ s: String) -> Double {
        let parts = s.split(separator: ":")
        guard parts.count == 2, let m = Int(parts[0]), let sec = Int(parts[1]) else { return 0 }
        return Double(m * 60 + sec)
    }

    private func avgPaceSeconds(for row: TodayLogRow) -> Double? {
        if let p = row.pace, !p.isEmpty {
            let s = paceSeconds(p)
            if s > 0 { return s }
        }
        if let miles = row.miles, miles > 0, let mins = row.durationMinutes, mins > 0 {
            return (mins / miles) * 60.0
        }
        return nil
    }

    func formatMiles(_ m: Double) -> String {
        m >= 100 ? String(format: "%.0f", m) : String(format: "%.1f", m)
    }
    static func formatPaceMMSS(_ seconds: Double) -> String {
        let t = Int(seconds.rounded())
        return "\(t / 60):\(String(format: "%02d", t % 60))"
    }
    static func formatDurationHours(_ minutes: Double) -> String {
        let h = Int(minutes) / 60
        let m = Int(minutes) % 60
        return "\(h):\(String(format: "%02d", m))"
    }

    // MARK: Static label helpers

    private static func buildGoals(plan: TrainingPlan?, goal: UserGoal?, snapshot: FitnessSnapshot?, avgWeekMiles: Double) -> GoalsSummary? {
        guard plan != nil || goal != nil else { return nil }
        let raceGoal = goal?.goalTitle.uppercased() ?? plan?.name.uppercased() ?? "RACE GOAL"
        // Current fitness prediction for the goal distance.
        var current = "—"
        var gap = "—"
        if let plan, let snapshot {
            let predicted = predictedSeconds(for: plan.raceDistance, snapshot: snapshot)
            current = formatClock(predicted)
            let target = plan.targetTimeSeconds
            if target > 0 {
                let delta = predicted - Double(target)
                gap = delta > 0 ? "+\(formatClock(delta)) TO TARGET" : "ON TARGET"
            }
        }
        let weeklyTarget: String? = avgWeekMiles > 0
            ? "\(Int(avgWeekMiles.rounded())) MI / WK CURRENT"
            : nil
        return GoalsSummary(raceGoal: raceGoal, currentFitness: current, gap: gap, weeklyTarget: weeklyTarget)
    }

    private static func predictedSeconds(for distance: RaceDistance, snapshot: FitnessSnapshot) -> Double {
        switch distance {
        case .marathon:     return Double(snapshot.predictedMarathonSeconds)
        case .halfMarathon: return Double(snapshot.predictedHalfSeconds)
        case .tenK:         return Double(snapshot.predicted10kSeconds)
        case .fiveK:        return Double(snapshot.predicted5kSeconds)
        case .mile1500:     return Double(snapshot.predictedMileSeconds)
        }
    }

    static func formatClock(_ seconds: Double) -> String {
        let t = Int(seconds.rounded())
        let h = t / 3600, m = (t % 3600) / 60, s = t % 60
        return h > 0
            ? "\(h):\(String(format: "%02d", m)):\(String(format: "%02d", s))"
            : "\(m):\(String(format: "%02d", s))"
    }

    static func defaultPlanned(for typeKey: String?) -> Int {
        switch (typeKey ?? "").lowercased() {
        case let t where t.contains("interval"): return 7
        case let t where t.contains("tempo"), let t where t.contains("threshold"): return 6
        case let t where t.contains("long"): return 5
        case let t where t.contains("recovery"): return 2
        default: return 3   // easy
        }
    }

    static func isHardType(_ typeKey: String?) -> Bool {
        let t = (typeKey ?? "").lowercased()
        return t.contains("interval") || t.contains("tempo") || t.contains("threshold") || t.contains("race")
    }

    /// The day chip's text. Routed through `WorkoutLabel` — the documented
    /// source of truth for this vocabulary — rather than the substring ladder
    /// that used to live here.
    ///
    /// That ladder was a SECOND taxonomy and it had drifted: it knew six
    /// keys and sent everything else to "EASY". So `steady`, `moderate`,
    /// `fartlek` and `progression` all rendered as EASY — an 11-miler stored
    /// as `steady` was labelled EASY on the Train tab, and re-typing it to
    /// Moderate would have changed nothing on screen, because this function
    /// could not say the word. It also still said TEMPO, which was folded
    /// into `threshold` on 2026-08-10.
    ///
    /// An absent type still reads EASY, unchanged — that is a separate call
    /// about what to claim for an untyped run, not part of this mapping.
    ///
    /// The chip's COLOUR is unaffected: it comes from
    /// `bucket(forPaceSeconds:)`, i.e. how fast the run actually was, which
    /// is deliberately independent of what it was called.
    static func typeLabel(_ typeKey: String?) -> String {
        let raw = (typeKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return "EASY" }
        return WorkoutLabel.display(WorkoutLabel.normalize(raw) ?? raw).uppercased()
    }

    /// "AUG 3 – 9" / "JUL 28 – AUG 3". Lives here beside `weekdayLabel` and
    /// `monthDayLabel` so the Train tab's week nav and any other week-paging
    /// surface read the same string from one place.
    static func weekRangeLabel(_ start: Date) -> String {
        var cal = Calendar(identifier: .iso8601)
        cal.firstWeekday = 2
        let end = cal.date(byAdding: .day, value: 6, to: start) ?? start
        let startFmt = DateFormatter(); startFmt.dateFormat = "MMM d"
        let sameMonth = cal.isDate(start, equalTo: end, toGranularity: .month)
        let endFmt = DateFormatter(); endFmt.dateFormat = sameMonth ? "d" : "MMM d"
        return "\(startFmt.string(from: start)) – \(endFmt.string(from: end))".uppercased()
    }

    static func weekdayLabel(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "EEE"
        return f.string(from: date).uppercased()
    }
    static func monthDayLabel(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MMM d"
        return f.string(from: date).uppercased()
    }
    static func dayMonthLabel(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MMM d"
        return f.string(from: date).uppercased()
    }
    func scopeDateline() -> String {
        switch scope {
        case .week:
            let f = DateFormatter(); f.dateFormat = "MMM d"
            return "WEEK OF \(f.string(from: thisWeekStart).uppercased()) · \(Self.dayMonthLabel(Date()))"
        case .month:
            let f = DateFormatter(); f.dateFormat = "MMM d"
            guard let start = cal.date(byAdding: .day, value: -30, to: Date()) else { return "LAST 30 DAYS" }
            return "\(f.string(from: start).uppercased()) – \(f.string(from: Date()).uppercased())"
        case .block:
            return planLabel ?? "THE BLOCK"
        }
    }
}

// MARK: - RPE row (resilient fetch)

/// Projection of the RPE columns added by the `extract-rpe` migration.
/// Fetched in its own query so the rest of the tab keeps working if the
/// migration hasn't been applied — a decode/column error yields an empty
/// map and the felt-vs-planned section simply renders nothing.
struct RPERow: Decodable {
    let id: UUID
    let feltRpe: Int?
    let plannedRpe: Int?
    let pullQuote: String?
    let tags: [String]?

    enum CodingKeys: String, CodingKey {
        case id
        case feltRpe = "felt_rpe"
        case plannedRpe = "planned_rpe"
        case pullQuote = "rpe_pull_quote"
        case tags = "rpe_tags"
    }

    static func fetchRecent(days: Int) async -> [UUID: RPERow] {
        let cutoff = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-Double(days) * 86_400))
        do {
            let rows: [RPERow] = try await supabase
                .from("training_logs")
                .select("id, felt_rpe, planned_rpe, rpe_pull_quote, rpe_tags")
                .gte("workout_date", value: cutoff)
                .limit(1500)
                .execute()
                .value
            return Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        } catch {
            // Columns not present yet (pre-migration) — degrade silently.
            return [:]
        }
    }
}

// MARK: - ISO-8601 Monday calendar
//
// File-private to this view model — `Calendar.iso8601Monday` / `startOfWeek`
// also exist as file-private helpers in PlanMonthSummaryView and other
// plan views. Keeping ours file-scoped avoids cross-file ambiguity.

fileprivate extension Calendar {
    /// Monday-first ISO week calendar, used across the analytics tab.
    static var iso8601Monday: Calendar {
        var c = Calendar(identifier: .iso8601)
        c.firstWeekday = 2
        return c
    }

    func startOfWeek(for date: Date) -> Date {
        let comps = dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return self.date(from: comps) ?? startOfDay(for: date)
    }
}
