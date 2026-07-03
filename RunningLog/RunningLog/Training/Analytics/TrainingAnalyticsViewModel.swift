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

// MARK: - Intensity ramp (9 zones, starts green at easy)
//
// New colour vocabulary introduced by the Training spec. Every colour
// means a pace. Distinct from the mood/zone colours in DesignSystem —
// this is the *one* ramp used everywhere on this tab.

enum IntensityRamp {
    /// z1 (easy) → z9 (mile / sharp end).
    static let colors: [Color] = [
        Color(hex: "A8B394"), // z1 easy
        Color(hex: "BFAE7C"), // z2
        Color(hex: "C49B52"), // z3 aerobic / MP-ish
        Color(hex: "C28438"), // z4
        Color(hex: "BE6A2E"), // z5
        Color(hex: "C04E27"), // z6 threshold+
        Color(hex: "A03A44"), // z7
        Color(hex: "84395C"), // z8
        Color(hex: "5F4A86"), // z9 mile / sharp end
    ]

    /// Stacked-bar simplification: easy = z1, aerobic = z3, threshold+ = z6.
    static var easy: Color      { colors[0] }
    static var aerobic: Color   { colors[2] }
    static var threshold: Color { colors[5] }

    /// Ramp colour for a histogram bin, `0` slowest … `binCount-1` fastest.
    static func color(forBin index: Int, binCount: Int) -> Color {
        guard binCount > 0 else { return easy }
        let z = Int(Double(index) / Double(binCount) * 9.0)
        return colors[min(8, max(0, z))]
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

struct SummaryStats {
    var miles: Double = 0
    var runs: Int = 0
    var durationMinutes: Double = 0
    var easyPercent: Int = 0
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
        didSet { UserDefaults.standard.set(scope.rawValue, forKey: Self.scopeKey) }
    }
    private static let scopeKey = "training.analytics.scope"

    var isLoading = false
    var hasLoaded = false

    // Raw inputs
    private var logs: [TodayLogRow] = []            // deduped, ascending by date
    private var rpeByLog: [UUID: RPERow] = [:]
    // Splits are fetched per session (laps query) on demand; cache so
    // re-opening the same day doesn't refetch. Cleared on reload.
    private var splitsCache: [UUID: [DaySplit]] = [:]
    private(set) var snapshot: FitnessSnapshot?     // latest current-fitness
    private(set) var goals: GoalsSummary?
    private var planStart: Date?
    private var planTotalWeeks: Int?
    private var planLabel: String?

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

        // Logs (400d covers any block) — deduped before any aggregation.
        let fetched = await TodayLogRow.fetchRecent(days: 400)
        logs = fetched.dedupedByPhysicalWorkout().sorted { $0.date < $1.date }
        splitsCache.removeAll()   // logs changed — drop stale per-session splits

        // Current-fitness snapshot (cheap — reads the history table).
        let predictor = FitnessPredictorService()
        await predictor.fetchHistory()
        snapshot = predictor.snapshotHistory.max(by: { $0.createdAt < $1.createdAt })

        // RPE columns (resilient — empty if the migration hasn't run).
        rpeByLog = await RPERow.fetchRecent(days: 120)

        // Goals + plan block bounds.
        await loadPlanAndGoals(predictor: predictor)

        hasLoaded = true
    }

    private func loadPlanAndGoals(predictor: FitnessPredictorService) async {
        let planService = TrainingPlanService()
        await planService.loadActivePlan(then: {})

        if let plan = planService.activePlan {
            planStart = cal.startOfDay(for: plan.startDate)
            let weeks = cal.dateComponents([.weekOfYear], from: plan.startDate, to: plan.endDate).weekOfYear
            planTotalWeeks = weeks.map { max(1, $0) }
        }

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
    var thresholdPaceSec: Double? {   // LT ≈ current predicted half pace
        snapshot.map { Double($0.predictedHalfSeconds) / 13.109375 }
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

    private func logs(on day: Date) -> [TodayLogRow] {
        logs.filter { cal.isDate($0.date, inSameDayAs: day) }
    }

    private func logs(inWeekStarting weekStart: Date) -> [TodayLogRow] {
        guard let end = cal.date(byAdding: .day, value: 7, to: weekStart) else { return [] }
        return logs.filter { $0.date >= weekStart && $0.date < end }
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
            split = split + self.split(for: r)
        }
        s.easyPercent = split.total > 0 ? Int((split.easy / split.total * 100).rounded()) : 0
        return s
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
        let today = cal.startOfDay(for: Date())
        return (0..<7).compactMap { offset in
            guard let day = cal.date(byAdding: .day, value: offset, to: thisWeekStart) else { return nil }
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
        scopedWeekStarts().map { ws in
            WeekVolume(weekStart: ws,
                       label: Self.monthDayLabel(ws),
                       split: split(forWeekStarting: ws),
                       inProgress: cal.isDate(ws, inSameDayAs: thisWeekStart))
        }
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

    private func longestRunMiles(inScopedWeeks: Bool) -> Double {
        let rows = inScopedWeeks ? logsInScopedWeeks() : logs
        return rows.compactMap { $0.miles }.max() ?? 0
    }

    // MARK: Outputs — mileage by day grid

    func gridWeeks() -> [GridWeek] {
        let today = cal.startOfDay(for: Date())
        return scopedWeekStarts().map { ws in
            let cells: [DayCell] = (0..<7).compactMap { offset in
                guard let day = cal.date(byAdding: .day, value: offset, to: ws) else { return nil }
                let split = self.split(forDay: day)
                let isFuture = day > today
                let isRest = !isFuture && split.total == 0
                return DayCell(date: day, miles: split.total, split: split, isRest: isRest, isFuture: isFuture)
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
            pullQuote: rpe?.pullQuote ?? row.cleanedNotes,
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
                         hr: lap.avgHeartRate,
                         color: bucket(forPaceSeconds: lap.paceSeconds).color)
            }
        }

        let segs = (row.paceSegments ?? []).filter { $0.distanceMiles > 0 }
        return segs.enumerated().compactMap { (i, seg) in
            let p = paceSeconds(seg.pacePerMile)
            guard p > 0 else { return nil }
            return DaySplit(index: i + 1,
                            distanceMiles: seg.distanceMiles,
                            paceSeconds: p,
                            hr: seg.avgHeartRate,
                            color: bucket(forPaceSeconds: p).color)
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
            let bins = paceHistogram()
            let step = (axisSlowSeconds - axisFastSeconds) / Double(bins.count)
            return bins.map { b in
                let center = axisSlowSeconds - (Double(b.index) + 0.5) * step
                return VolumeDetailBar(label: Self.formatPaceMMSS(center), miles: b.miles,
                                       color: b.color, key: .paceBin(b.index))
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
            let step = (axisSlowSeconds - axisFastSeconds) / Double(Self.histogramBinCount)
            return scopedRowsForHistogram()
                .filter { row in
                    guard let p = avgPaceSeconds(for: row) else { return false }
                    let idx = Int((axisSlowSeconds - p) / step)
                    return min(Self.histogramBinCount - 1, max(0, idx)) == i
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
    let axisSlowSeconds: Double = 480
    let axisFastSeconds: Double = 270

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
        if let segs = row.paceSegments, !segs.isEmpty {
            for seg in segs { addMiles(seg.distanceMiles, paceSec: paceSeconds(seg.pacePerMile)) }
        } else if let m = row.miles {
            addMiles(m, paceSec: avgPaceSeconds(for: row) ?? 0)
        }
    }

    func paceMarkers() -> [PaceMarker] {
        var out: [PaceMarker] = []
        if let e = easyPaceSec      { out.append(PaceMarker(label: "EASY", paceSeconds: e, color: Color.drip.positive)) }
        if let mp = marathonPaceSec { out.append(PaceMarker(label: "MP", paceSeconds: mp, color: Color.drip.textPrimary)) }
        if let lt = thresholdPaceSec { out.append(PaceMarker(label: "LT", paceSeconds: lt, color: Color.drip.coral)) }
        if let k = fiveKPaceSec     { out.append(PaceMarker(label: "5K", paceSeconds: k, color: Color.drip.textPrimary)) }
        return out
    }

    // MARK: Outputs — easy pace trend (month scope)

    func easyPaceTrend() -> [EasyPacePoint] {
        scopedWeekStarts().compactMap { ws in
            let rows = logs(inWeekStarting: ws).filter { bucket(forPaceSeconds: avgPaceSeconds(for: $0)) == .easy }
            let paces = rows.compactMap { avgPaceSeconds(for: $0) }
            guard !paces.isEmpty else { return nil }
            return EasyPacePoint(weekStart: ws, avgPaceSeconds: paces.reduce(0, +) / Double(paces.count))
        }
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

    private static func formatClock(_ seconds: Double) -> String {
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

    static func typeLabel(_ typeKey: String?) -> String {
        switch (typeKey ?? "").lowercased() {
        case let t where t.contains("interval"): return "INTERVALS"
        case let t where t.contains("tempo"):    return "TEMPO"
        case let t where t.contains("threshold"): return "THRESHOLD"
        case let t where t.contains("long"):     return "LONG RUN"
        case let t where t.contains("recovery"): return "RECOVERY"
        case let t where t.contains("race"):     return "RACE"
        default: return "EASY"
        }
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
