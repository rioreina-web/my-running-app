//
//  WorkoutRepReceiptView.swift
//  RunningLog
//
//  Direction A · "Rep Receipt" — the dense, full-screen workout detail.
//  A drop-in for `WorkoutRepChart(workoutId:)` inside `WorkoutRepDetailSheet`.
//  Keeps everything the current screen does (type picker, prescribed-workout
//  notes, heat-adjust) and adds the full Strava-stream telemetry the redesign
//  called for. Act 2 is signals-first as of 2026-08-03 — the AI insight path
//  is gone; see WorkoutReceiptSignals.swift.
//
//    HERO rep chart (distance-width bars + HR line + target refs) →
//    stat strip → SIGNALS + one-line read → time-in-HR-zone →
//    HR-over-session → pace trace → cadence → elevation+grade →
//    per-rep HR recovery → SPLITS vs target (diverging bars + rest jogs) →
//    [comparison vs recent same-type — see port note] → route.
//
//  Two data sources, loaded in parallel:
//    • rep laps      — WorkoutLapsService (running_workout_laps / parsed reps)
//    • per-second    — ExternalStreamAdapter.load(forTrainingLogId:)
//                      (HR / velocity / cadence / altitude / latlng)
//  Every stream-derived section hides gracefully when a run has no streams
//  (e.g. a manual entry), so the lap-only path still renders.
//
//  Charts live in WorkoutReceiptCharts.swift (RR* views + rr_* helpers).
//

import SwiftUI
import CoreLocation
import Supabase
import os

struct WorkoutRepReceiptView: View {
    let workoutId: UUID?
    private let injectedLaps: [WorkoutLapRow]?
    private let injectedZones: RepChartZones?

    init(workoutId: UUID) {
        self.workoutId = workoutId; self.injectedLaps = nil; self.injectedZones = nil
    }
    /// Preview / test seam (lap-only; stream sections stay hidden).
    init(laps: [WorkoutLapRow], zones: RepChartZones) {
        self.workoutId = nil; self.injectedLaps = laps; self.injectedZones = zones
    }

    // lap data
    @State private var laps: [WorkoutLapRow] = []
    @State private var zones: RepChartZones = .none
    @State private var showStructureEditor = false
    @State private var prescription: WorkoutPrescription?
    @State private var parsedIntent: String?
    @State private var workoutType: String?
    @State private var loaded = false
    @State private var showTypePicker = false
    /// Act 2 — the voice memo opens on tap, and the niggles this run carries.
    @State private var memoExpanded = false
    @State private var niggles: [ReceiptNiggle] = []
    @State private var showMemoRecorder = false
    // stream data
    @State private var stream: VitalWorkoutStream?
    @State private var route: [CLLocationCoordinate2D] = []
    /// Full GPS samples (with timestamps) for the real map — pace coloring
    /// needs the timing that bare coordinates throw away.
    @State private var routeLocations: [CLLocation] = []
    @State private var streamMaxHR: Int?
    /// The athlete's observed max HR (highest lap max across their history) —
    /// the stable ceiling for HR-zone scaling. Fetched on load; see `maxHR`.
    @State private var athleteMaxHR: Int?
    /// Per-user max HR, set in Settings ("Max Heart Rate"). Drives the HR-zone
    /// scaling so a coach/athlete can tune their zones. Shared via UserDefaults.
    @AppStorage("userMaxHR") private var userMaxHR: Int = 180
    // tweaks
    @State private var heatOn = false
    // App-wide unit preference (persisted, shared across screens via this
    // UserDefaults key). Defaults to false = MILES, so everything reads in
    // miles even when a run was recorded in kilometres; flipping the toggle
    // switches units everywhere that reads "unit_use_km".
    @AppStorage("unit_use_km") private var km = false
    @State private var colorByZone = false
    /// Pace-spectrum coloring (pale blue→navy). On by default; the "PACE COLOR"
    /// chip toggles it off to the single coral accent.
    @State private var colorByPace = true
    /// Elevation profile overlay on the pace bars, toggleable. (HR lives in
    /// its own HR & DRIFT section now.)
    @State private var showElev = true

    // comparison vs recent same-type sessions
    @State private var recent: [RecentSimilarWorkout] = []
    // true when `laps` carry reliable work/rest tags (merged raw laps or parsed
    // structure) — then `is_rest` is authoritative and the pace heuristic is skipped
    @State private var trustRestTags = false
    // true when the watch recorded this as a continuous run (uniform distance
    // auto-laps) — a long / steady run lapped every km/mile. We then show those
    // recorded splits as-is and never merge/parse them into fake "reps".
    @State private var isContinuous = false

    // Act 1 / Act 2 — the run's identity (date, source) and its qualitative
    // signal (mood, the athlete's own words). A voice-logged run has none of
    // the lap data below but still has all of this, and still composes.
    @State private var summary = WorkoutLapsService.WorkoutSummary()
    // Act 3 — at most one trace is open at a time; nil = all collapsed.
    @State private var expandedTrace: TraceRow?

    private let mpm = 1609.344
    static let typeOptions = ["intervals", "threshold", "tempo", "fartlek", "progression", "easy", "long_run", "recovery", "race"]

    /// The rows of Act 3. `telemetry` is the unified HR × pace × cadence ×
    /// elevation panel (RRTelemetryPanel) — it replaced the four separate
    /// stacked charts in the May-2026 redesign and keeps its own scrub +
    /// fullscreen, so it stays one row rather than being split back apart.
    private enum TraceRow: String, CaseIterable, Identifiable {
        case hrZones, telemetry, recovery, comparison, route
        var id: String { rawValue }
        var title: String {
            switch self {
            case .hrZones:    "HR ZONES"
            case .telemetry:  "PACE · HR · ELEVATION"
            case .recovery:   "HR RECOVERY"
            case .comparison: "VS RECENT"
            case .route:      "ROUTE"
            }
        }
    }

    // MARK: Derived — work reps

    private var orderedLaps: [WorkoutLapRow] { laps.sorted { ($0.lap_index ?? 0) < ($1.lap_index ?? 0) } }

    private var reps: [WorkoutLapRow] {
        // A continuous run (uniform watch auto-laps) has no rep structure — its
        // "laps" are distance splits, not work reps. Force the whole-run path so
        // a long / steady run is never rendered as intervals.
        if isContinuous { return [] }
        return orderedLaps.filter { lap in
            guard lap.is_rest != true,
                  let p = lap.avg_pace_sec_per_mile, p > 0,
                  let d = lap.distance_meters, d >= 150,
                  let s = lap.moving_time_seconds, s >= 20 else { return false }
            // When the laps carry reliable work/rest tags (merged raw GPS laps or
            // parsed structure), `is_rest` is authoritative — a faded/slow rep
            // (e.g. an 11:45 mile in a hard session) is still a real rep and must
            // be kept. The pace cap only makes sense for untagged raw laps, where
            // we must separate a hard rep from a jog ourselves.
            if trustRestTags { return true }
            return p <= 370
        }
    }

    /// Work-rep windows in stream time (cumulative lap durations), plus the
    /// rest lap that follows each — used for shading, per-rep cadence, recovery.
    private struct RepSlot { let rep: Int; let lap: WorkoutLapRow; let start: Double; let end: Double; let restStart: Double?; let restEnd: Double?; let restLap: WorkoutLapRow? }
    private var slots: [RepSlot] {
        var out: [RepSlot] = []
        var t = 0.0
        var repNum = 0
        for (i, lap) in orderedLaps.enumerated() {
            let dur = Double(lap.moving_time_seconds ?? 0)
            let isWork = reps.contains { ($0.lap_index ?? -1) == (lap.lap_index ?? -2) }
            if isWork {
                repNum += 1
                // rest = next lap if it's a rest
                var rs: Double? = nil, re: Double? = nil
                var restLap: WorkoutLapRow? = nil
                if i + 1 < orderedLaps.count, orderedLaps[i + 1].is_rest == true {
                    let rl = orderedLaps[i + 1]
                    rs = t + dur; re = rs! + Double(rl.moving_time_seconds ?? 0)
                    restLap = rl
                }
                out.append(RepSlot(rep: repNum, lap: lap, start: t, end: t + dur, restStart: rs, restEnd: re, restLap: restLap))
            }
            t += dur
        }
        return out
    }

    /// The recovery segment's measured pace, shown as-is — a fartlek float or an
    /// alternation's fast recovery is a real pace we must not suppress or
    /// re-label. The only thing filtered is a lap that didn't meaningfully move
    /// (a standing rest, whose "pace" is GPS-drift noise, not effort): pace must
    /// be positive and the lap must cover ≥ 40 m. No effort/character is inferred.
    private func recoveryPace(_ rest: WorkoutLapRow?) -> Double? {
        guard let rest,
              let p = rest.avg_pace_sec_per_mile, p > 0,
              (rest.distance_meters ?? 0) >= 40 else { return nil }
        return p
    }

    // MARK: Stream arrays (downsampled for drawing)

    // Cached stream-derived arrays. Each maps over every per-second sample
    // (often thousands), so they are computed ONCE in `rebuildDerived()` after
    // the workout loads — never inside `body`. Leaving them as computed
    // properties re-ran all of this on every redraw, so tapping PACE COLOR /
    // HEAT-ADJ / MI / EXPAND rebuilt the whole screen and the button froze.
    @State private var sTimes: [Double] = []
    @State private var sHR: [Double] = []
    @State private var sPace: [Double] = []
    @State private var sCad: [Double] = []
    @State private var sAltFt: [Double] = []
    // Per-mile splits, derived once from the stream. Shown on EVERY workout
    // (steady or interval) so the screen always has a standard splits chart.
    @State private var mileSplits: [MileSplit] = []
    // Chosen continuous-run splits (native laps if regular, else stream miles),
    // computed once in rebuildDerived so the per-split elevation scan never
    // runs inside body.
    @State private var continuousSplits: [RRRep] = []
    /// True when `continuousSplits` came from the imported per-second stream
    /// rather than the watch's own laps — the hero then says MILE SPLITS, so
    /// the table never claims a provenance it doesn't have.
    @State private var continuousFromStream = false
    private var sGrade: [Double] {
        guard let alt = stream?.altitude, let dist = stream?.distance, alt.count == dist.count, alt.count > 1 else { return [] }
        return alt.indices.map { i in
            guard i > 0 else { return 0 }
            let dd = dist[i] - dist[i - 1]
            return dd > 0.5 ? min(max((alt[i] - alt[i - 1]) / dd * 100, -25), 25) : 0
        }
    }
    private var hasStream: Bool { sTimes.count > 5 && sHR.count > 5 }

    private var windows: [RRWindow] { slots.map { RRWindow(id: $0.rep, start: $0.start, end: $0.end) } }

    private var maxHR: Int {
        // Per-user max HR (Settings) drives the zones — so zones are tunable per
        // athlete. Floored by REAL data: your true max can't be below a HR you've
        // actually recorded (observed lap max across history) or this session's
        // own peak. So the setting can only RAISE the ceiling above what's been
        // seen — which is the real use (your known max often exceeds recorded
        // runs). A single sub-maximal workout can't compress the zones into Z5.
        let observed = athleteMaxHR ?? 0
        let thisWorkout = streamMaxHR ?? reps.compactMap { $0.avg_heart_rate }.max() ?? 0
        let best = max(userMaxHR, observed, thisWorkout)
        return best > 0 ? best : 188
    }
    private var hrZones: [RRZone] { rr_zones(maxHR: maxHR) }

    // RRRep models for the hero chart + splits
    private func perRepCadence(_ slot: RepSlot) -> Int? {
        guard hasStream, !sCad.isEmpty else { return nil }
        let vals = sTimes.indices.filter { sTimes[$0] >= slot.start && sTimes[$0] < slot.end && $0 < sCad.count }.map { sCad[$0] }
        guard !vals.isEmpty else { return nil }
        return Int((vals.reduce(0, +) / Double(vals.count)).rounded())
    }
    // Cached once in `rebuildDerived()` — `perRepCadence` scans the full stream
    // per rep, so this must not re-run on every redraw.
    @State private var rrReps: [RRRep] = []
    /// Every lap as its own split — warmup, work reps, recovery jogs and
    /// cooldown, in order — so the hero chart is the WHOLE workout, not just
    /// the reps. Cached because building it scans the altitude stream per lap.
    @State private var allSplits: [RRRep] = []
    private var targetSec: Double {
        let p = reps.compactMap { $0.avg_pace_sec_per_mile }
        return p.isEmpty ? 330 : p.reduce(0, +) / Double(p.count)
    }

    // time in zone — cached once in `rebuildDerived()` (the stream loop is O(n)).
    @State private var zoneSeconds: [String: Double] = [:]
    private var dominantZone: String { zoneSeconds.max { $0.value < $1.value }?.key ?? "Z4" }

    // recoveries — cached once in `rebuildDerived()` (scans the stream per rep).
    @State private var recoveries: [RRRecovery] = []

    // route hr parallel
    private var routeHR: [Int] {
        guard !route.isEmpty else { return [] }
        // map stream HR onto route points by index proportion
        guard !sHR.isEmpty else { return [] }
        return route.indices.map { i in
            let f = Double(i) / Double(max(route.count - 1, 1))
            let j = min(Int(f * Double(sHR.count - 1)), sHR.count - 1)
            return Int(sHR[j])
        }
    }
    private var repStartIdx: [(idx: Int, rep: Int)] {
        guard !route.isEmpty, !sTimes.isEmpty else { return [] }
        return slots.map { s in
            let f = s.start / max(sTimes.last ?? 1, 1)
            return (idx: min(Int(f * Double(route.count - 1)), route.count - 1), rep: s.rep)
        }
    }

    /// Numbered interval pins for the route map, placed at each rep's start.
    private var routeRepMarkers: [RouteMarker] {
        repStartIdx.compactMap { rs in
            guard rs.idx >= 0, rs.idx < routeLocations.count else { return nil }
            return RouteMarker(
                coordinate: routeLocations[rs.idx].coordinate,
                label: "\(rs.rep)",
                kind: .rep
            )
        }
    }

    // MARK: Body

    /// True when the run has a real interval structure (work reps detected).
    private var hasReps: Bool { !reps.isEmpty }
    /// True when there's anything to chart — reps, a per-second stream, or laps.
    /// A voice-logged / manual run with none of these gets the honest no-data state.
    private var hasAnalytics: Bool { hasReps || hasStream || !orderedLaps.isEmpty }

    /// Three acts (Phase B, 2026-07-14):
    ///   1 — the run at a glance: who/when/what, the four stats, conditions.
    ///   2 — the story: the Read, what the athlete said, and Workouts & Reps
    ///       as the hero — the visual centre of the screen.
    ///   3 — the traces, collapsed to one line each; tap to expand.
    /// A voice-logged run has no laps at all and still composes: Act 1's
    /// identity, Act 2's mood + quote, then the honest no-data state.
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if !loaded {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
            } else if !hasAnalytics {
                actOne
                qualitativeRow
                noDataState
            } else {
                actOne
                DripHairline()
                actTwo
                DripHairline()
                actThree
            }
        }
        .task { await load() }
        .onChange(of: km) { chooseContinuousSplits() }
        // Re-bucket HR zones when the user changes their max HR in Settings.
        .onChange(of: userMaxHR) { rebuildDerived() }
        .sheet(isPresented: $showStructureEditor) {
            if let workoutId {
                EditWorkoutStructureSheet(
                    workoutId: workoutId,
                    initialLaps: laps,
                    initialIntent: parsedIntent ?? prescription?.pattern,
                    onSaved: { Task { await load() } }
                )
            }
        }
        .sheet(isPresented: $showMemoRecorder) {
            if let workoutId {
                // The pipeline (transcribe → mood → niggles) runs server-side
                // after the attach, so the reload picks up the audio straight
                // away and the words as they land.
                AttachMemoSheet(workoutId: workoutId, dateLabel: displayTitle) {
                    Task { await load() }
                }
            }
        }
    }

    /// Honest empty state for runs with no GPS/stream/lap data (voice or manual
    /// entries). Eyebrow + plain prose per the empty-state convention — no
    /// em-dash placeholder, no fabricated "steady effort" claim.
    private var noDataState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text((workoutType.map(prettyType) ?? "Run").uppercased())
                .font(.dripStat(10)).tracking(1.3).foregroundStyle(Color.drip.coral)
            Text("Logged without GPS")
                .font(.dripDisplay(22)).foregroundStyle(Color.drip.textPrimary)
            Text("This run was logged by voice or entered by hand, so there are no splits or sensor traces to chart here. What you said and how it felt live on the log entry.")
                .font(.dripBody(14)).lineSpacing(3)
                .foregroundStyle(Color.drip.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
    }

    // MARK: Sections

    // MARK: Act 1 — the run at a glance

    /// Fits a 6.1" screen without scrolling: eyebrow, date, source line, the
    /// four stats, and the conditions plate. The workout type stays editable —
    /// it's the eyebrow's second half, tap to change.
    private var actOne: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { showTypePicker = true } label: {
                HStack(spacing: 5) {
                    Text(actOneEyebrow).font(.dripEyebrow(11)).tracking(1.3)
                    Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold))
                }
                .foregroundStyle(Color.drip.textTertiary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .confirmationDialog("Change workout type", isPresented: $showTypePicker, titleVisibility: .visible) {
                ForEach(Self.typeOptions, id: \.self) { t in Button(prettyType(t)) { updateType(t) } }
                Button("Cancel", role: .cancel) {}
            }

            // The one coral mark in this cluster: the period. (The other is
            // THE READ eyebrow, a cluster away — see the three-palette rule.)
            Text("\(Text(displayTitle).foregroundStyle(Color.drip.textPrimary))\(Text(".").foregroundStyle(Color.drip.coral))")
                .font(.dripDisplay(34))

            if let line = sourceLine {
                Text(line)
                    .font(.dripBody(13)).italic()
                    .foregroundStyle(Color.drip.textSecondary)
            }

            statStrip4

            ConditionsPlate(tempF: condTempF, dewF: condDewF,
                            heatAdjSec: heatAdjustSec, climb: climb, km: km)
        }
    }

    /// "TUESDAY · QUALITY" — the day it happened and what it was. Drops the
    /// weekday when the run has no date rather than inventing one.
    private var actOneEyebrow: String {
        let type = (workoutType.map(prettyType) ?? "Run").uppercased()
        guard let d = summary.date else { return type }
        let df = DateFormatter()
        df.dateFormat = "EEEE"
        return "\(df.string(from: d).uppercased()) · \(type)"
    }

    /// "July 9" when we know the date; otherwise the session's own structure
    /// ("6×800") so the screen still has a real title — never a placeholder.
    private var displayTitle: String {
        if let d = summary.date {
            let df = DateFormatter()
            df.dateFormat = "MMMM d"
            return df.string(from: d)
        }
        return repHeadline
    }

    /// "7.42 mi · 51:08 · HealthKit" — middle dots, and any part we don't have
    /// simply isn't said.
    private var sourceLine: String? {
        var parts: [String] = []
        if wrDistanceMi > 0 {
            let d = km ? wrDistanceMi * 1.60934 : wrDistanceMi
            parts.append(String(format: "%.2f %@", d, km ? "km" : "mi"))
        }
        if wrTimeSec > 0 { parts.append(clock(Int(wrTimeSec))) }
        if let s = summary.sourceLabel { parts.append(s) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// DISTANCE · DURATION · AVG PACE · AVG HR — the whole run, always, whether
    /// or not it had reps. A cell with no data drops out (hard rule #8: never an
    /// em-dash placeholder); if none survive, the strip doesn't render at all.
    @ViewBuilder private var statStrip4: some View {
        let cells: [(String, String, String)] = {
            var out: [(String, String, String)] = []
            if wrDistanceMi > 0 {
                let d = km ? wrDistanceMi * 1.60934 : wrDistanceMi
                out.append((String(format: "%.2f", d), km ? "km" : "mi", "Distance"))
            }
            if wrTimeSec > 0 { out.append((clock(Int(wrTimeSec)), "", "Duration")) }
            if wrPaceSec > 0 { out.append((rr_pace(wrPaceSec, km: km), km ? "/km" : "/mi", "Avg Pace")) }
            if let hr = wrAvgHR { out.append(("\(hr)", "bpm", "Avg HR")) }
            return out
        }()
        if !cells.isEmpty {
            HStack(spacing: 0) {
                ForEach(Array(cells.enumerated()), id: \.offset) { i, c in
                    VStack(spacing: 4) {
                        Text("\(Text(c.0).font(.dripStat(20)).foregroundStyle(Color.drip.textPrimary))\(Text(c.1.isEmpty ? "" : " \(c.1)").font(.dripStat(9)).foregroundStyle(Color.drip.textTertiary))")
                        Text(c.2.uppercased())
                            .font(.dripStat(9)).tracking(1.0)
                            .foregroundStyle(Color.drip.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .overlay(i < cells.count - 1
                             ? AnyView(Rectangle().fill(Color.drip.divider).frame(width: 1).frame(maxHeight: .infinity))
                             : AnyView(EmptyView()), alignment: .trailing)
                }
            }
            .padding(.vertical, 12)
            .overlay(Rectangle().fill(Color.drip.textPrimary).frame(height: 1), alignment: .top)
        }
    }

    // MARK: Act 1 — conditions

    /// Conditions are run-level facts carried on the laps. Temp and dew show
    /// whenever they were recorded — no dew-point floor here, unlike the
    /// heat-adjust maths, because 50°F and dry is still worth stating.
    private var condTempF: Double? { laps.compactMap { $0.temp_f }.max() }
    private var condDewF: Double? { laps.compactMap { $0.dew_point_f }.max() }

    /// Mean heat penalty across the work laps (raw pace minus its neutral-air
    /// equivalent), in sec per display unit. Nil below 3 s/mi — the same bar
    /// `WorkoutForecast.isMeaningful` uses, so the plate and the forecast agree.
    /// A "0s" cell would say less than no cell.
    private var heatAdjustSec: Int? {
        let deltas: [Double] = laps.compactMap { lap in
            guard lap.is_rest != true,
                  let raw = lap.avg_pace_sec_per_mile, raw > 0,
                  let adj = lap.heat_adjusted_pace_sec_per_mile, adj > 0
            else { return nil }
            return raw - adj
        }
        guard !deltas.isEmpty else { return nil }
        let meanPerMile = deltas.reduce(0, +) / Double(deltas.count)
        guard meanPerMile >= 3 else { return nil }
        let shown = km ? meanPerMile / 1.60934 : meanPerMile
        return Int(shown.rounded())
    }

    /// Total climb. Nil when the run carries no altitude stream (HealthKit rows
    /// often don't) — the cell then drops out rather than reading zero.
    private var climb: Int? {
        guard sAltFt.count > 1 else { return nil }
        let gain = rr_elevGain()
        return gain > 0 ? gain : nil
    }

    /// Steepest grade seen, used only to decide whether a hilly run should open
    /// its trace by default.
    private var maxGradePct: Double { sGrade.map(abs).max() ?? 0 }

    // MARK: Act 2 — the story

    /// SIGNALS → the workout recipe → the memo → niggles → the hero.
    /// Everything above the hairline is signal: a chip, a row of the note, one
    /// line of the athlete's own words. Nothing is a paragraph.
    private var actTwo: some View {
        VStack(alignment: .leading, spacing: 24) {
            signalsSection
            workoutRecipeSection
            qualitativeRow
            heroWorkoutsAndReps
        }
    }

    // MARK: Act 2 — signals

    /// The five chips, then the read as a single sentence. Replaces the
    /// multi-sentence AI paragraph and its "Generate AI insight" button
    /// (removed 2026-08-03) — the chart and these numbers say it.
    @ViewBuilder private var signalsSection: some View {
        let signals = receiptSignals
        if !signals.isEmpty || !computedRead.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("SIGNALS")
                    .font(.dripEyebrow(11)).tracking(1.3)
                    .foregroundStyle(Color.drip.coral)
                if !signals.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(signals) { SignalChip(signal: $0) }
                    }
                }
                Text(computedRead)
                    .font(.dripBody(13)).italic()
                    .foregroundStyle(Color.drip.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Every chip is one measured quantity. A chip whose input is missing is
    /// simply absent — never a placeholder, never a zero (hard rule #8).
    private var receiptSignals: [ReceiptSignal] {
        var out: [ReceiptSignal] = []

        // SPREAD — the work reps' pace range, stated as a band around the
        // midpoint so "±13s" is literally true of the fastest and slowest rep.
        if let spread = repSpreadSec {
            let half = Int((Double(spread) / 2).rounded())
            out.append(.init(key: "SPREAD", value: "±\(half)s",
                             tone: spread <= 15 ? .good : spread <= 30 ? .warn : .hot))
        }

        // HR — the zone that carried the session, and the rep it arrived on.
        if let (zone, rep) = hrZoneOnset {
            let n = Int(zone.dropFirst()) ?? 4
            out.append(.init(key: "HR", value: "\(zone) FROM R\(rep)",
                             tone: n <= 3 ? .good : n == 4 ? .warn : .hot))
        }

        // DRIFT — aerobic decoupling, first half vs second (same maths as
        // DripHRDriftChart, so the chip and the chart can't disagree).
        if let drift = driftPct {
            out.append(.init(key: "DRIFT", value: "\(drift > 0 ? "+" : "")\(drift)%",
                             tone: abs(drift) < 5 ? .good : abs(drift) <= 10 ? .warn : .hot))
        }

        // HEAT — what the conditions cost, already gated at ≥3 s/mi.
        if let heat = heatAdjustSec {
            out.append(.init(key: "HEAT", value: "+\(heat)s/\(km ? "km" : "mi")", tone: .warn))
        }

        // VS PLAN — only when the note actually states a target pace. Without
        // one there is nothing to compare against, so the chip drops out
        // rather than measuring the reps against their own average.
        if let target = prescribedTargetSec, !reps.isEmpty {
            let delta = Int((targetSec - target).rounded())
            let a = abs(delta)
            let value = a <= 5 ? "ON TARGET" : "\(delta > 0 ? "+" : "-")\(a)s/\(km ? "km" : "mi")"
            out.append(.init(key: "VS PLAN", value: value,
                             tone: a <= 5 ? .good : a <= 15 ? .warn : .hot))
        }

        return out
    }

    /// Fastest-to-slowest work-rep range, in seconds per mile. Needs at least
    /// two reps — one rep has no spread.
    private var repSpreadSec: Int? {
        let paces = reps.compactMap { $0.avg_pace_sec_per_mile }.filter { $0 > 0 }
        guard paces.count >= 2, let hi = paces.max(), let lo = paces.min() else { return nil }
        return Int((hi - lo).rounded())
    }

    /// The zone that carried the most time, and the first work rep whose average
    /// HR lands in it. Nil when no rep carries HR.
    private var hrZoneOnset: (zone: String, rep: Int)? {
        guard !zoneSeconds.isEmpty, zoneSeconds.values.contains(where: { $0 > 0 }) else { return nil }
        let zone = dominantZone
        guard let z = hrZones.first(where: { $0.id == zone }) else { return nil }
        for (i, r) in reps.enumerated() {
            guard let hr = r.avg_heart_rate, hr > 0 else { continue }
            if hr >= z.lo && hr < z.hi { return (zone, i + 1) }
        }
        return nil
    }

    /// Aerobic decoupling across the work reps: how far the pace-to-HR ratio
    /// moved from the first half to the second. Positive = HR rising for the
    /// same pace. Needs HR on at least four reps to mean anything.
    private var driftPct: Int? {
        let rows = reps.compactMap { r -> (pace: Double, hr: Double)? in
            guard let p = r.avg_pace_sec_per_mile, p > 0, let h = r.avg_heart_rate, h > 0
            else { return nil }
            return (p, Double(h))
        }
        guard rows.count >= 4 else { return nil }
        let m = rows.count / 2
        let first = Array(rows.prefix(m)), second = Array(rows.suffix(rows.count - m))
        func mean(_ a: [Double]) -> Double { a.isEmpty ? 0 : a.reduce(0, +) / Double(a.count) }
        let ratioA = mean(first.map(\.pace)) / max(mean(first.map(\.hr)), 1)
        let ratioB = mean(second.map(\.pace)) / max(mean(second.map(\.hr)), 1)
        guard ratioA > 0 else { return nil }
        return Int(((ratioB - ratioA) / ratioA * 100).rounded())
    }

    /// A target pace stated in the workout note ("1 mi @ 6:00"), in sec per
    /// mile. Nil when the note names no pace — we never invent a target, and
    /// never treat the session's own average as one.
    private var prescribedTargetSec: Double? {
        let text = [prescription?.notes, prescription?.pattern, parsedIntent]
            .compactMap { $0 }.joined(separator: " ")
        guard !text.isEmpty,
              let r = text.range(of: #"(?:@|at)\s*(\d{1,2}):(\d{2})"#, options: .regularExpression)
        else { return nil }
        let stamp = text[r].split(separator: ":")
        guard stamp.count == 2,
              let mm = Int(stamp[0].filter(\.isNumber)), let ss = Int(stamp[1].prefix(2))
        else { return nil }
        let perMile = Double(mm * 60 + ss)
        // Notes are written in the athlete's display unit; targetSec is sec/mi.
        return km ? perMile * 1.60934 : perMile
    }

    // MARK: Act 2 — the workout, as a recipe

    /// The prescribed session, one row per segment. Falls back to the note as a
    /// single line whenever the structure can't be read — the note is never
    /// hidden, and a recipe is never guessed.
    @ViewBuilder private var workoutRecipeSection: some View {
        let source = prescription?.notes ?? prescription?.pattern
        if let text = source?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline) {
                    Text("THE WORKOUT")
                        .font(.dripEyebrow(11)).tracking(1.3)
                        .foregroundStyle(Color.drip.textSecondary)
                    Spacer(minLength: 8)
                    Text(repHeadline.uppercased())
                        .font(.dripStat(9)).tracking(1.0)
                        .foregroundStyle(Color.drip.textTertiary)
                        .lineLimit(1)
                }
                if let steps = WorkoutRecipeParser.parse(text) {
                    WorkoutRecipeView(steps: steps)
                } else {
                    Text(text)
                        .font(.dripBody(13))
                        .foregroundStyle(Color.drip.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Act 2 — the athlete's own words, and what their body said

    /// The memo as one line until tapped, then the niggles this run carried.
    /// Both surfaced, never interpreted (niggles rule). Each drops out when the
    /// run carries nothing — no placeholder, no invented sentiment.
    @ViewBuilder private var qualitativeRow: some View {
        let quote = summary.quote?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let mood = summary.mood ?? ""
        // The memo slot never silently disappears: with a memo it's the
        // collapsed row, without one it's the record affordance (§6). An
        // auto-imported run has notes but no memo, so `hasMemo` — not the
        // presence of text — is what decides.
        let showMemo = summary.hasMemo && !quote.isEmpty
        let showRecord = !summary.hasMemo && workoutId != nil
        if showMemo || showRecord || !mood.isEmpty || !niggles.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                if showMemo {
                    VoiceMemoRow(mood: mood.isEmpty ? nil : mood, quote: quote,
                                 kind: summary.hasAudio ? "VOICE MEMO" : "NOTE",
                                 expanded: $memoExpanded)
                } else {
                    if !mood.isEmpty { MoodBadge(mood: mood) }
                    if showRecord {
                        RecordMemoCard { showMemoRecorder = true }
                    }
                }
                if !niggles.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(niggles) { NiggleChip(niggle: $0) }
                    }
                }
            }
        }
    }

    /// The hero — the visual centre of the screen. Everything above earns its
    /// place by leading here: what the session actually was, rep by rep.
    private var heroWorkoutsAndReps: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Eyebrow left, the rep-average line right — it used to sit under
            // the table, where it read as an afterthought.
            HStack(alignment: .firstTextBaseline) {
                Text(heroEyebrow)
                    .font(.dripEyebrow(11)).tracking(1.3)
                    .foregroundStyle(Color.drip.textSecondary)
                Spacer(minLength: 8)
                repsSummaryLine
            }

            tweaksRow

            if hasReps {
                // Bars + table both driven by EVERY lap (warmup → reps →
                // recoveries → cooldown), compressed to fit the screen width.
                RRRepBars(reps: allSplits, targetSec: targetSec, colorByZone: colorByZone,
                          colorByPace: colorByPace, heatOn: heatOn, km: km, zones: hrZones,
                          showElev: showElev, fitToWidth: true)
                LapSplitsList(laps: orderedLaps, km: km, mpSec: targetSec)
            } else if !continuousSplits.isEmpty {
                RRRepBars(reps: continuousSplits, targetSec: continuousAvgPaceSec,
                          colorByZone: colorByZone, colorByPace: colorByPace,
                          heatOn: heatOn, km: km, zones: hrZones, showElev: showElev,
                          fitToWidth: true)
                RepsTable(reps: continuousSplits, km: km, heatOn: heatOn)
            } else {
                noSplitsRow
            }

            if workoutId != nil { fixRepsButton }
        }
    }

    /// "WORKOUTS & REPS" for a session with reps; otherwise the splits' own
    /// provenance — the watch's recorded laps, or the mile splits derived from
    /// the imported stream when the watch never lapped the run.
    private var heroEyebrow: String {
        if hasReps { return "WORKOUTS & REPS" }
        if continuousSplits.isEmpty { return "SPLITS" }
        return continuousFromStream
            ? "MILE SPLITS"
            : "SPLITS · \(continuousSplits.count) \(lapsAreKm ? "KM" : "MI")"
    }

    /// The one honest thing to say when the activity carries no laps and no
    /// stream: nothing was imported. We never synthesise splits to fill a
    /// table (spec §5).
    private var noSplitsRow: some View {
        Text("No splits from Strava")
            .font(.dripBody(13)).italic()
            .foregroundStyle(Color.drip.textTertiary)
            .padding(.vertical, 6)
    }

    private var continuousAvgPaceSec: Double {
        let p = continuousSplits.map(\.paceSec)
        return p.isEmpty ? 0 : p.reduce(0, +) / Double(p.count)
    }

    /// "REP AVG 6:41 · RECOVERIES 2:00 AVG" — sits beside the hero eyebrow.
    /// No TARGET — see `RepsTable`.
    @ViewBuilder private var repsSummaryLine: some View {
        let rows = hasReps ? rrReps : continuousSplits
        if !rows.isEmpty {
            // Respect the HEAT-ADJ toggle so the average tracks the (faster)
            // adjusted splits instead of staying pinned to the raw pace — the
            // mismatch made the avg read HIGHER than the reps once heat was on.
            let avg = rows.map { heatOn ? ($0.adjPaceSec ?? $0.paceSec) : $0.paceSec }
                .reduce(0, +) / Double(rows.count)
            let rests = rows.compactMap(\.restSec)
            let parts: [String] = {
                var p = ["\(hasReps ? "REP" : "SPLIT") AVG \(rr_pace(avg, km: km))"]
                if !rests.isEmpty {
                    p.append("RECOVERIES \(clock(rests.reduce(0, +) / rests.count)) AVG")
                }
                return p
            }()
            Text(parts.joined(separator: " · "))
                .font(.dripStat(9)).tracking(1.0)
                .foregroundStyle(Color.drip.textTertiary)
        }
    }

    private var fixRepsButton: some View {
        Button { showStructureEditor = true } label: {
            HStack(spacing: 5) {
                Image(systemName: "slider.horizontal.3").font(.system(size: 11, weight: .semibold))
                Text("Fix reps").font(.dripLabel(13))
            }
            .foregroundStyle(Color.drip.coral)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Color.drip.coralWash)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    // MARK: Whole-run analytics (no-rep runs)

    /// Total run distance — lap sum, then the stream, then what the athlete
    /// logged. That last fallback is what lets a voice-logged run (no laps, no
    /// stream) still state its distance in Act 1 instead of dropping the cell.
    /// Whole-run distance — the activity total as recorded (Strava/HealthKit),
    /// NOT a sum of rep laps. Summing laps double-counts nothing, but it pairs
    /// with the work-only time below to make pace = distance / time nonsense
    /// (all your distance ÷ only your rep time → a pace faster than any split).
    /// Prefer the real activity total; fall back to the GPS stream, then to
    /// summed laps only when no activity total exists (e.g. a voice-only run).
    private var wrDistanceMi: Double {
        if let d = summary.distanceMi, d > 0 { return d }
        if let d = stream?.distance, let last = d.last, last > 0 { return last / mpm }
        return orderedLaps.compactMap { $0.distance_meters }.reduce(0, +) / mpm
    }
    /// Whole-run moving time — the activity total (Strava's moving_time already
    /// excludes pauses like a water break), matched to the distance above so
    /// pace is always a real pace. Falls back to the stream, then summed laps.
    private var wrTimeSec: Double {
        if let m = summary.durationMin, m > 0 { return m * 60 }
        if let t = sTimes.last, t > 0 { return t }
        return Double(orderedLaps.compactMap { $0.moving_time_seconds }.reduce(0, +))
    }
    private var wrPaceSec: Double { wrDistanceMi > 0 ? wrTimeSec / wrDistanceMi : 0 }
    private var wrAvgHR: Int? {
        if hasStream, !sHR.isEmpty { return Int((sHR.reduce(0, +) / Double(sHR.count)).rounded()) }
        let hrs = orderedLaps.compactMap { $0.avg_heart_rate }
        return hrs.isEmpty ? nil : hrs.reduce(0, +) / hrs.count
    }

    /// mm:ss, or h:mm:ss past the hour.
    private func clock(_ totalSeconds: Int) -> String {
        let t = max(totalSeconds, 0)
        let h = t / 3600, m = (t % 3600) / 60, s = t % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }

    /// Standard per-mile splits chart. Mile number, a fast→slow bar coloured
    /// by the pace spectrum, and the mile pace. Renders on every workout with
    /// a stream, so steady runs get the same splits treatment as intervals.
    /// Per-mile splits mapped into the same `RRRep` model the interval reps
    /// use, so steady runs render with the identical bar chart + splits table.
    /// Width = mile distance (full miles equal, partial last mile narrower);
    /// height = mile pace. Cheap to map (one row per mile).
    /// Neutral-air equivalent pace for a stream-derived split, from the run's
    /// conditions. Continuous splits aren't lap rows, so they carry no stored
    /// heat-adjusted pace — without this the HEAT-ADJ toggle can't move them
    /// (single-lap / steady runs looked unaffected). Full adjustment: a
    /// continuous mile isn't an interval rep, so no rep-length scaling.
    private func mileHeatAdjusted(_ paceSec: Double) -> Double? {
        guard paceSec > 0, let t = condTempF, let d = condDewF else { return nil }
        return PaceCalculator.calculateDewPointAdjustment(
            paceSeconds: paceSec, temperatureF: t, dewPointF: d
        ).neutralEquivalentPaceSeconds
    }

    private var mileReps: [RRRep] {
        mileSplits.enumerated().map { i, s in
            let dist = s.isPartial ? max(s.partialDistance, 0.0001) : 1.0
            let paceSec = s.paceMinutes * 60
            let label = s.isPartial
                ? "MI \(String(format: "%.1f", Double(s.mile - 1) + s.partialDistance))"
                : "MI \(s.mile)"
            let start = i == 0 ? 0 : mileSplits[i - 1].elapsedTime
            return RRRep(
                id: s.mile,
                label: label,
                distMi: dist,
                paceSec: paceSec,
                hr: s.avgHeartRate,
                cad: s.avgCadence,
                restSec: nil,                       // continuous run — no rest between miles
                adjPaceSec: mileHeatAdjusted(paceSec),
                durSec: Int((paceSec * dist).rounded()),
                elevFt: elevNetFt(start: start, end: s.elapsedTime)
            )
        }
    }

    /// Whether the recorded distance laps are kilometres (vs miles).
    private var lapsAreKm: Bool {
        let dists = distanceLaps.compactMap { $0.distance_meters }.sorted()
        guard !dists.isEmpty else { return false }
        let median = dists[dists.count / 2]
        return abs(median - 1000) < abs(median - mpm)
    }

    /// Non-rest distance laps as actually recorded (excludes warmup/cooldown
    /// outliers only by the regularity check in `lapSplits`).
    private var distanceLaps: [WorkoutLapRow] {
        orderedLaps.filter {
            $0.is_rest != true
            && ($0.distance_meters ?? 0) >= 150
            && ($0.moving_time_seconds ?? 0) >= 20
            && ($0.avg_pace_sec_per_mile ?? 0) > 0
        }
    }

    /// Splits built from the native auto-laps (1K or 1mi), so the table
    /// matches what the watch recorded instead of re-cutting the stream into
    /// miles. Returns [] when laps aren't regular distance splits, so the
    /// stream-derived `mileReps` stays the fallback.
    private var lapSplits: [RRRep] {
        let dl = distanceLaps
        guard dl.count >= 3 else { return [] }
        let dists = dl.compactMap { $0.distance_meters }.sorted()
        let median = dists[dists.count / 2]
        // Treat as distance auto-laps only if most laps are near the median
        // length (uniform splits), not an ad-hoc set of manual laps.
        let regular = dl.filter { abs(($0.distance_meters ?? 0) - median) < median * 0.2 }
        guard Double(regular.count) >= Double(dl.count) * 0.6 else { return [] }
        let unitLabel = lapsAreKm ? "KM" : "MI"
        var cum = 0.0
        return dl.enumerated().map { i, lap in
            let start = cum
            let end = cum + Double(lap.moving_time_seconds ?? 0)
            cum = end
            return RRRep(
                id: i + 1,
                label: "\(unitLabel) \(i + 1)",
                distMi: (lap.distance_meters ?? 0) / mpm,
                paceSec: lap.avg_pace_sec_per_mile ?? 0,
                hr: lap.avg_heart_rate,
                cad: nil,
                restSec: nil,
                adjPaceSec: lap.heat_adjusted_pace_sec_per_mile,
                durSec: lap.moving_time_seconds,
                elevFt: elevNetFt(start: start, end: end)
            )
        }
    }

    /// Net elevation change (ft, signed) over a stream time window
    /// [start, end] — end altitude minus start altitude, so a net descent
    /// reads negative. nil when there's no usable altitude stream.
    private func elevNetFt(start: Double, end: Double) -> Int? {
        guard sAltFt.count > 1, sTimes.count == sAltFt.count else { return nil }
        let idxs = sTimes.indices.filter { sTimes[$0] > start && sTimes[$0] <= end }
        guard let first = idxs.first, let last = idxs.last else { return nil }
        return Int((sAltFt[last] - sAltFt[first]).rounded())
    }

    private var tweaksRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(heatOn ? "HEAT-ADJ ON" : "HEAT-ADJ", on: heatOn, color: Color.drip.tired) { withAnimation(.easeOut(duration: 0.2)) { heatOn.toggle() } }
                    .opacity(heatConds == nil ? 0.4 : 1).disabled(heatConds == nil)
                chip(colorByPace ? "PACE COLOR" : "SINGLE COLOR", on: colorByPace, color: Color.drip.coral) { withAnimation(.easeOut(duration: 0.2)) { colorByPace.toggle() } }
                chip("ELEV", on: showElev, color: Color.drip.textSecondary) { withAnimation(.easeOut(duration: 0.2)) { showElev.toggle() } }
                unitToggle
            }
        }
    }

    /// Clear two-state unit switch — both options always visible, the active
    /// one filled. Writes the app-wide `unit_use_km` preference.
    private var unitToggle: some View {
        HStack(spacing: 0) {
            unitSegment("MI", active: !km) { km = false }
            unitSegment("KM", active: km)  { km = true }
        }
        .padding(2)
        .background(Color.drip.paperDeep)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.drip.divider, lineWidth: 1))
    }

    private func unitSegment(_ label: String, active: Bool, _ set: @escaping () -> Void) -> some View {
        Text(label)
            .font(.dripStat(11)).tracking(1)
            .foregroundStyle(active ? Color.drip.background : Color.drip.textSecondary)
            .padding(.horizontal, 13).padding(.vertical, 6)
            .background(active ? Color.drip.textPrimary : Color.clear)
            .clipShape(Capsule())
            .contentShape(Capsule())
            .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { set() } }
    }

    // MARK: Act 3 — the traces, collapsed

    /// One line per trace, each with a real summary stat so the row says
    /// something even while closed. Traces the run doesn't have are omitted
    /// entirely rather than shown disabled.
    private var actThree: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("TRACES")
                .font(.dripEyebrow(11)).tracking(1.3)
                .foregroundStyle(Color.drip.textSecondary)
                .padding(.bottom, 4)
            ForEach(availableTraces) { row in
                traceDisclosure(row)
            }
        }
    }

    /// The traces this run actually has. Order is the reading order.
    private var availableTraces: [TraceRow] {
        var out: [TraceRow] = []
        if hasStream || hasReps { out.append(.hrZones) }
        if hasStream { out.append(.telemetry) }
        if hasReps, !recoveries.isEmpty { out.append(.recovery) }
        if hasReps, recent.count >= 2 { out.append(.comparison) }
        if !routeLocations.isEmpty { out.append(.route) }
        return out
    }

    @ViewBuilder private func traceDisclosure(_ row: TraceRow) -> some View {
        let open = expandedTrace == row
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    expandedTrace = open ? nil : row
                }
            } label: {
                HStack(alignment: .center, spacing: 8) {
                    Text(row.title)
                        .font(.dripEyebrow(11)).tracking(1.3)
                        .foregroundStyle(Color.drip.textPrimary)
                    Spacer(minLength: 8)
                    if let s = traceSummary(row) {
                        Text(s)
                            .font(.dripStat(9)).tracking(0.8)
                            .foregroundStyle(Color.drip.textTertiary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.drip.textTertiary)
                        .rotationEffect(.degrees(open ? 90 : 0))
                }
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if open {
                traceContent(row).padding(.bottom, 16)
            }
        }
        .overlay(Rectangle().fill(Color.drip.divider).frame(height: 1), alignment: .bottom)
    }

    /// The one-line stat that makes a closed row worth reading.
    private func traceSummary(_ row: TraceRow) -> String? {
        switch row {
        case .hrZones:
            // Top two zones by time in them — "31 MIN Z4 · 12 MIN Z2".
            let top = zoneSeconds.filter { $0.value > 0 }
                .sorted { $0.value > $1.value }
                .prefix(2)
                .map { "\(Int(($0.value / 60).rounded())) MIN \($0.key.uppercased())" }
            return top.isEmpty ? nil : top.joined(separator: " · ")
        case .telemetry:
            var parts: [String] = []
            if let hr = wrAvgHR { parts.append("\(hr) AVG HR") }
            if let c = climb { parts.append("+\(c) \(km ? "M" : "FT")") }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        case .recovery:
            let drops = recoveries.map(\.drop)
            guard !drops.isEmpty else { return nil }
            return "−\(drops.reduce(0, +) / drops.count) BPM AVG"
        case .comparison:
            guard !recent.isEmpty else { return nil }
            let priorAvg = recent.map(\.avgPaceSec).reduce(0, +) / Double(recent.count)
            let delta = targetSec - priorAvg          // negative = faster than usual
            let perUnit = km ? abs(delta) / 1.60934 : abs(delta)
            return "\(delta <= 0 ? "−" : "+")\(Int(perUnit.rounded()))S VS RECENT"
        case .route:
            guard wrDistanceMi > 0 else { return nil }
            let d = km ? wrDistanceMi * 1.60934 : wrDistanceMi
            return String(format: "%.2f %@", d, km ? "KM" : "MI")
        }
    }

    @ViewBuilder private func traceContent(_ row: TraceRow) -> some View {
        switch row {
        case .hrZones:
            RRZoneBar(seconds: zoneSeconds, zones: hrZones, mainZone: dominantZone)
        case .telemetry:
            // The unified panel — HR, pace, cadence and elevation on one shared
            // axis, with rep-window bands, a scrub tooltip and a fullscreen
            // expand. It replaced the four separate stacked charts, so it stays
            // whole here rather than being split back into four rows.
            RRTelemetryPanel(times: sTimes, hr: sHR, paceSec: sPace,
                             cadence: sCad, altFt: sAltFt,
                             windows: windows, km: km, zones: hrZones)
        case .recovery:
            RRRecoveryRow(recoveries: recoveries)
        case .comparison:
            comparisonContent
        case .route:
            RouteMapView(route: routeLocations, repMarkers: routeRepMarkers)
        }
    }

    /// "This session vs your last N same-type sessions" — average work pace.
    private var comparisonContent: some View {
        let typeLabel = workoutType.map(prettyType) ?? "Quality"
        let curHRs = reps.compactMap { $0.avg_heart_rate }
        let current = RecentSimilarWorkout(
            dateLabel: "NOW",
            avgPaceSec: targetSec,
            avgHR: curHRs.isEmpty ? nil : curHRs.reduce(0, +) / curHRs.count
        )
        let series = recent + [current]
        let priorAvg = recent.map(\.avgPaceSec).reduce(0, +) / Double(recent.count)
        let delta = targetSec - priorAvg                 // negative = faster than usual
        let faster = delta <= 0
        let perUnit = km ? abs(delta) / 1.60934 : abs(delta)
        let secStr = "\(Int(perUnit.rounded()))s/\(km ? "km" : "mi")"
        return VStack(alignment: .leading, spacing: 10) {
            RRComparison(series: series, km: km)
            Text("Average work pace against your last \(recent.count) \(typeLabel.lowercased()) session\(recent.count == 1 ? "" : "s"). Today \(faster ? "ran \(secStr) quicker than" : "sat \(secStr) off") your recent average.")
                .font(.dripBody(13)).italic().foregroundStyle(Color.drip.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Exactly one trace opens by default, chosen by what the session was: a
    /// quality run is a question about HR response; a long or hilly run is a
    /// question about the pace/elevation trace (both live in the telemetry
    /// panel now). Anything else starts fully collapsed.
    private func defaultExpandedTrace() -> TraceRow? {
        let available = availableTraces
        let t = (workoutType ?? "").lowercased()
        let quality = ["intervals", "threshold", "tempo", "fartlek", "progression", "race"]

        if quality.contains(t) || hasReps, available.contains(.hrZones) { return .hrZones }
        if t == "long_run", available.contains(.telemetry) { return .telemetry }
        if (climb ?? 0) >= 150 || maxGradePct >= 4, available.contains(.telemetry) { return .telemetry }
        return nil
    }

    // MARK: Section chrome

    // `sectionHead` / `section` went with the flat stack they framed — Act 1
    // and Act 2 lead with an eyebrow, and Act 3's rows carry their own header.

    private func chip(_ label: String, on: Bool, color: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.dripStat(9)).tracking(0.8)
                .foregroundStyle(on ? Color.white : color)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(on ? color : color.opacity(0.12)).clipShape(Capsule())
        }.buttonStyle(.plain)
    }

    // MARK: Copy helpers

    private var heatConds: (Double, Double)? {
        guard let t = reps.compactMap({ $0.temp_f }).max(),
              let d = reps.compactMap({ $0.dew_point_f }).max(),
              d >= PaceCalculator.heatDewPointFloorF else { return nil }
        return (t, d)
    }
    /// The read, in one sentence: what happened, in numbers this run actually
    /// carries. Every clause is conditional on its own data — a run with no HR
    /// makes no claim about zones, and nothing here grades the session
    /// ("controlled and even" was said whatever the spread was). The chips
    /// carry the status; this line carries the facts.
    private var computedRead: String {
        let unit = km ? "/km" : "/mi"
        if reps.isEmpty {
            let dist = String(format: "%.1f", km ? wrDistanceMi * 1.60934 : wrDistanceMi)
            var s = "\(dist) \(km ? "km" : "mi") at \(rr_pace(wrPaceSec, km: km))\(unit)"
            if let hr = wrAvgHR { s += ", average heart rate \(hr)" }
            s += ". No rep structure to break out"
            if let zone = timedZone { s += " — \(zone) carried the most time" }
            return s + "."
        }
        var s = "\(reps.count) reps at \(rr_pace(targetSec, km: km))\(unit)"
        if let spread = repSpreadSec { s += ", inside a \(spread)-second spread" }
        if let (zone, rep) = hrZoneOnset { s += ", HR in \(zone) from rep \(rep) on" }
        return s + "."
    }

    /// The zone that actually carried time. Nil when the run has no HR at all —
    /// `dominantZone` falls back to "Z4" for the chart's scaling, which must
    /// never become a sentence claiming a zone the athlete never recorded.
    private var timedZone: String? {
        guard zoneSeconds.values.contains(where: { $0 > 0 }) else { return nil }
        return dominantZone
    }
    private func prettyType(_ t: String) -> String {
        WorkoutLabel.display(t)
    }
    private func rr_elevGain() -> Int {
        guard sAltFt.count > 1 else { return 0 }
        var gain = 0.0
        for i in 1..<sAltFt.count { let d = sAltFt[i] - sAltFt[i - 1]; if d > 0 { gain += d } }
        return Int((km ? gain * 0.3048 : gain).rounded())
    }
    // The clean, athlete-stated structure ("3k tempo + 3 × (1k, 600m)") when
    // the workout has an intent pattern — from a correction or the parser. It
    // reads far better than the raw rounded-meters dump and, crucially, makes a
    // correction VISIBLE: after "Fix reps" the headline reflects what the
    // athlete typed instead of the watch's mis-rounded splits.
    private var repHeadline: String {
        if let ip = parsedIntent?.trimmingCharacters(in: .whitespaces), !ip.isEmpty {
            return ip
        }
        return repBreakdown
    }
    // The measured breakdown ("3500m·1K·600m·…") — actual GPS distances rounded
    // to 100m. Headline when there's no intent pattern; subtitle when there is.
    private var repBreakdown: String {
        if reps.isEmpty {
            if wrDistanceMi > 0 {
                return String(format: "%.1f %@", km ? wrDistanceMi * 1.60934 : wrDistanceMi, km ? "km" : "mi")
            }
            return workoutType.map(prettyType) ?? "Run"
        }
        let labels = reps.map { rr_repLabel($0.distance_meters ?? 0) }
        if Set(labels).count == 1 { return "\(reps.count)×\(labels[0])" }
        return labels.count <= 8 ? labels.joined(separator: "·") : "\(reps.count) reps"
    }

    /// True when the athlete's OWN words (cleaned notes / voice) describe a
    /// structured workout. This gates only the workout TITLE — it lets the
    /// memo's stated pattern name a run even when the splits are the watch's
    /// continuous mile/km splits. It NEVER supplies split geometry (those come
    /// from the watch). Conservative on purpose: a false negative just drops the
    /// title to the plain type, a false positive lets a described-but-unlapped
    /// run keep its name. Auto-import notes ("Morning Run · Avg pace: 6:47/mi")
    /// contain no structure keywords, so they read as unnamed.
    private func mentionsStructuredWorkout(_ text: String?) -> Bool {
        guard let t = text?.lowercased(), !t.isEmpty else { return false }
        // Rep notation the athlete would type/say: "8x800", "6 × 1k", "4x1mi".
        if t.range(of: #"\d+\s*[x×]\s*\d"#, options: .regularExpression) != nil { return true }
        let keywords = [
            "repeat", "interval", "fartlek", "tempo", "threshold",
            "ladder", "cutdown", "track workout", "mile rep", "surges",
        ]
        return keywords.contains { t.contains($0) }
    }

    // MARK: Loading

    private func updateType(_ t: String) {
        workoutType = t
        guard let workoutId else { return }
        Task { await WorkoutLapsService.setType(workoutId: workoutId, type: t) }
    }

    /// Compute the heavy stream-derived arrays a single time, after the workout
    /// loads. Everything here used to live in `body` as computed properties,
    /// which meant every chip toggle re-ran thousands of per-sample operations
    /// and froze the UI. None of these values depend on the display toggles
    /// (HEAT-ADJ / PACE COLOR / MI-KM), so caching them is safe.
    private func rebuildDerived() {
        // Stream maps (thousands of samples) — order matters: set these first so
        // the aggregates below read the populated arrays.
        sTimes = (stream?.time ?? []).map(Double.init)
        sHR = (stream?.heartrate ?? []).map(Double.init)
        sPace = (stream?.velocitySmooth ?? []).map { v in v > 0.4 ? min(mpm / v, 900) : 900 }
        let c = stream?.cadence ?? []
        let avg = c.isEmpty ? 0 : c.reduce(0, +) / Double(c.count)
        sCad = avg < 120 ? c.map { $0 * 2 } : c   // Strava run cadence is per-leg
        sAltFt = (stream?.altitude ?? []).map { $0 * 3.281 }

        // Per-rep models (perRepCadence scans the stream per rep).
        rrReps = slots.map { s in
            RRRep(
                id: s.rep,
                label: rr_repLabel(s.lap.distance_meters ?? 0),
                distMi: (s.lap.distance_meters ?? 0) / mpm,
                paceSec: s.lap.avg_pace_sec_per_mile ?? 0,
                hr: s.lap.avg_heart_rate,
                cad: perRepCadence(s),
                restSec: (s.restStart != nil && s.restEnd != nil) ? Int(s.restEnd! - s.restStart!) : nil,
                adjPaceSec: s.lap.heat_adjusted_pace_sec_per_mile,
                durSec: s.lap.moving_time_seconds,
                restPaceSec: recoveryPace(s.restLap),
                restHR: s.restLap?.avg_heart_rate
            )
        }

        // Every lap as its own bar — warmup, work reps, recovery jogs and
        // cooldown all present, so the chart shows the whole workout end to
        // end. `restSec` is nil for every row (each lap is its own bar, so
        // rest is a bar of its own, not a gap after a rep).
        do {
            var cum = 0.0
            allSplits = orderedLaps.enumerated().map { i, lap in
                let start = cum
                let end = cum + Double(lap.moving_time_seconds ?? 0)
                cum = end
                return RRRep(
                    id: i + 1,
                    label: rr_repLabel(lap.distance_meters ?? 0),
                    distMi: (lap.distance_meters ?? 0) / mpm,
                    paceSec: lap.avg_pace_sec_per_mile ?? 0,
                    hr: lap.avg_heart_rate,
                    cad: nil,
                    restSec: nil,
                    adjPaceSec: lap.heat_adjusted_pace_sec_per_mile,
                    durSec: lap.moving_time_seconds,
                    elevFt: elevNetFt(start: start, end: end)
                )
            }
        }

        // Time in HR zone (O(n) over the HR stream).
        var acc: [String: Double] = [:]
        hrZones.forEach { acc[$0.id] = 0 }
        if hasStream {
            for i in sHR.indices {
                let dt = i + 1 < sTimes.count ? sTimes[i + 1] - sTimes[i] : 2
                let z = hrZones.first { Int(sHR[i]) >= $0.lo && Int(sHR[i]) < $0.hi } ?? hrZones.last!
                acc[z.id, default: 0] += dt
            }
        } else {
            for s in slots {
                guard let hr = s.lap.avg_heart_rate else { continue }
                let z = hrZones.first { hr >= $0.lo && hr < $0.hi } ?? hrZones.last!
                acc[z.id, default: 0] += (s.end - s.start)
            }
        }
        zoneSeconds = acc

        // HR recovery after each rep (scans a 60s window of the stream per rep).
        if hasStream {
            recoveries = slots.compactMap { s in
                guard let rs = s.restStart else { return nil }
                let idxs = sTimes.indices.filter { sTimes[$0] >= rs && sTimes[$0] <= rs + 60 && $0 < sHR.count }
                guard idxs.count >= 2 else { return nil }
                let series = idxs.map { Int(sHR[$0]) }
                let peak = series.first ?? 0
                let endHR = series.min() ?? peak
                let step = max(series.count / 12, 1)   // sample ~12 points
                let pts = stride(from: 0, to: series.count, by: step).map { series[$0] }
                return RRRecovery(id: s.rep, drop: max(peak - endHR, 0), endHR: endHR, pts: pts)
            }
        } else {
            recoveries = []
        }

        // Per-mile splits from the stream (moving-time based). Reuses the
        // existing tested VitalManager logic so every workout — steady or
        // interval — shows the same standard splits chart.
        if let s = stream {
            mileSplits = VitalManager.shared.calculateSplits(from: s)
        } else {
            mileSplits = []
        }

        chooseContinuousSplits()
    }

    /// Pick the continuous-run splits: the workout's own recorded laps when
    /// they're regular distance splits, else stream-derived mile splits. The
    /// distance per split is stored in miles; the display unit (mi/km) is
    /// applied at render, so this doesn't depend on the toggle. Computed here
    /// (not in body) — the per-split elevation scan is O(stream).
    private func chooseContinuousSplits() {
        let ls = lapSplits
        continuousSplits = ls.isEmpty ? mileReps : ls
        continuousFromStream = ls.isEmpty && !mileReps.isEmpty
    }

    private func load() async {
        if let injectedLaps {
            laps = injectedLaps; zones = injectedZones ?? .none
            rebuildDerived()
            expandedTrace = defaultExpandedTrace()
            loaded = true
            return
        }
        guard let workoutId else { loaded = true; return }
        async let l = WorkoutLapsService.fetchLaps(workoutId: workoutId)
        async let rolesFetch = WorkoutLapsService.fetchLapRoles(workoutId: workoutId)
        async let pr = WorkoutLapsService.fetchParsedReps(workoutId: workoutId)
        async let z = WorkoutLapsService.fetchZones()
        async let ty = WorkoutLapsService.fetchType(workoutId: workoutId)
        async let pre = WorkoutLapsService.fetchPrescription(workoutId: workoutId)
        async let sum = WorkoutLapsService.fetchSummary(workoutId: workoutId)
        async let bundle = ExternalStreamAdapter.load(forTrainingLogId: workoutId)
        // The body-part mentions this run carried. Non-fatal: the chip row just
        // drops out if it fails, the rest of the sheet is unaffected.
        async let nigs = ReceiptNiggleService.fetch(workoutId: workoutId,
                                                    userId: AuthManager.shared.userId)

        let rawLapRows = await l
        let roleByIndex = await rolesFetch
        // Source each lap's work/rest LABEL from the parser
        // (parsed_structure.lap_roles) rather than the DB's generated `is_rest`
        // column — that column flags any lap under 200m as rest, which hid real
        // sub-200m reps (a 200m interval day showed 5 of 8). The parser's
        // velocity bout-detection labels them honestly. Only the is_rest tag is
        // rewritten; distance / pace / HR stay exactly as the watch recorded, and
        // every lap is kept. When the workout hasn't been parsed yet the map is
        // empty and we fall back to the stored `is_rest` unchanged.
        let lapRows: [WorkoutLapRow] = roleByIndex.isEmpty ? rawLapRows : rawLapRows.map { row in
            guard let idx = row.lap_index, let role = roleByIndex[idx] else { return row }
            var r = row
            r.is_rest = role != "rep"   // only a "rep" is work; warmup/recovery/cooldown are rest
            return r
        }
        let parsed = await pr
        let sumVal = await sum
        summary = sumVal

        // Rep geometry precedence — the actual splits come from the WATCH (it
        // records the laps) or from YOU (a hand-correction). The LLM parser
        // never restructures splits the watch already recorded: it re-splits
        // continuous reps and bleeds recovery into work bouts (see
        // `mergeWorkBouts` note). It supplies geometry only when the watch
        // didn't lap the run at all but you described a structured workout.
        //
        //   1. A hand-correction always wins — this is YOU.
        //   2. Uniform watch auto-laps → the watch's own recorded splits, as-is.
        //   3. The watch recorded rest laps → the watch's own laps, merged
        //      deterministically (a rep auto-split every km/mile is re-joined,
        //      rests pass through). This is the workout as recorded; the parser
        //      is not consulted for the geometry.
        //   4. Otherwise → CONTINUOUS. Stream mile/km splits from the watch.
        //      The parser NEVER supplies split geometry from the voice memo:
        //      if the watch didn't lap it, the honest record is the watch's
        //      own splits, not reps reconstructed from what you said.
        let rawHasRests = lapRows.contains { $0.is_rest == true }
        let parsedWork = parsed.laps.filter { $0.is_rest != true }.count
        if parsed.edited && parsedWork >= 1 {
            laps = parsed.laps
            trustRestTags = true
        } else if WorkoutLapsService.isContinuousAutoLap(lapRows) {
            laps = lapRows
            trustRestTags = false
            isContinuous = true
        } else if rawHasRests {
            // The watch lapped work + rest — that IS the workout's splits.
            laps = WorkoutLapsService.mergeWorkBouts(lapRows)
            trustRestTags = true
        } else {
            // No recorded lap structure → continuous. `isContinuous` forces the
            // whole-run / mile-split path (see `reps`), so the chart shows the
            // watch's own splits and a voice-memo parse can never render here.
            laps = lapRows
            trustRestTags = rawHasRests
            isContinuous = true
        }

        // Weather lives on the raw GPS laps (running_workout_laps.temp_f /
        // dew_point_f). When the parsed or merged geometry wins above, those
        // rows are rebuilt WITHOUT weather, which greyed out the HEAT-ADJ
        // toggle even on genuinely humid runs. Conditions are a run-level
        // fact, so carry the max temp/dew across onto any rep that lost them,
        // and recompute a per-rep heat-adjusted pace with the same engine the
        // pace chart uses so the toggle actually adjusts the displayed splits.
        // Prefer per-lap weather; fall back to the run-level `weather_actual`
        // (via the summary) when NO lap carries temp/dew — e.g. an
        // open-meteo-backfill run that only got the run summary, which left
        // HEAT-ADJ greyed out on a genuinely humid run. The dew-point floor is
        // still enforced downstream in `heatConds`, so a cool run stays inert.
        if let runTempF = lapRows.compactMap({ $0.temp_f }).max() ?? sumVal.weatherTempF,
           let runDewF = lapRows.compactMap({ $0.dew_point_f }).max() ?? sumVal.weatherDewF {
            laps = laps.map { rep in
                guard rep.temp_f == nil else { return rep }
                var r = rep
                r.temp_f = runTempF
                r.dew_point_f = runDewF
                if r.is_rest != true, let p = r.avg_pace_sec_per_mile, p > 0 {
                    r.heat_adjusted_pace_sec_per_mile = PaceCalculator
                        .calculateDewPointAdjustment(
                            paceSeconds: p,
                            temperatureF: runTempF,
                            dewPointF: runDewF
                        )
                        .neutralEquivalentPaceSeconds
                }
                return r
            }
        }

        // The workout TITLE comes from your voice memo, even when the SPLITS
        // are the watch's continuous mile/km splits — title and geometry are
        // separate concerns. Keep the parser's stated pattern whenever your own
        // words named a workout ("8×1K", "tempo"), OR the watch actually lapped
        // it as intervals. Null it only for a plain continuous run you never
        // described, so a GPS-invented pattern ("4 work bouts with varying
        // distances and paces") can never name a run you didn't call a workout.
        let memoNamedWorkout = mentionsStructuredWorkout(sumVal.quote)
        parsedIntent = (memoNamedWorkout || !isContinuous) ? parsed.intentPattern : nil
        zones = await z; workoutType = await ty
        var pre2 = await pre
        if let ip = parsedIntent, !ip.isEmpty { pre2.pattern = ip }
        prescription = pre2

        if let b = await bundle {
            stream = b.stream
            routeLocations = b.route
            route = b.route.map { $0.coordinate }
            streamMaxHR = b.meta.maxHr
            if heatConds != nil { heatOn = false }
        }

        // comparison strip — needs the (possibly just-resolved) workout_type
        if let t = workoutType, !t.isEmpty {
            recent = await WorkoutLapsService.fetchRecentSimilar(type: t, excluding: workoutId)
        }
        // Athlete's observed max HR — set BEFORE rebuildDerived() so the zone
        // bucketing (which reads `maxHR`) scales to the real ceiling.
        athleteMaxHR = await WorkoutLapsService.fetchObservedMaxHR(userId: AuthManager.shared.userId)
        niggles = await nigs
        rebuildDerived()
        // After the derived arrays exist — the default row depends on climb /
        // grade / reps, none of which are known before rebuildDerived().
        expandedTrace = defaultExpandedTrace()
        loaded = true
    }
}

// MARK: - Conditions plate (Act 1)

/// The air the run happened in, promoted out of a buried prose sentence into a
/// plate of facts. Ink only — conditions are facts, not alerts, so no coral.
/// Any cell we don't have data for drops out; if none survive, the whole plate
/// does (hard rule #8 — never an em-dash placeholder).
struct ConditionsPlate: View {
    let tempF: Double?
    let dewF: Double?
    /// Already thresholded at ≥3 s/mi by the caller — nil means "not meaningful".
    let heatAdjSec: Int?
    let climb: Int?
    let km: Bool

    private struct Cell: Identifiable {
        let id = UUID()
        let value: String
        let label: String
    }

    private var cells: [Cell] {
        var out: [Cell] = []
        if let t = tempF { out.append(Cell(value: "\(Int(t.rounded()))°", label: "Temp")) }
        if let d = dewF { out.append(Cell(value: "\(Int(d.rounded()))°", label: "Dewpoint")) }
        if let h = heatAdjSec {
            // Negative: in neutral air the same effort is worth this much faster.
            out.append(Cell(value: "−\(h)s/\(km ? "km" : "mi")", label: "Heat Adj"))
        }
        if let c = climb { out.append(Cell(value: "+\(c) \(km ? "m" : "ft")", label: "Climb")) }
        return out
    }

    var body: some View {
        if !cells.isEmpty {
            HStack(spacing: 0) {
                ForEach(cells) { c in
                    VStack(spacing: 4) {
                        Text(c.value)
                            .font(.dripStat(15))
                            .foregroundStyle(Color.drip.textPrimary)
                        Text(c.label.uppercased())
                            .font(.dripStat(8)).tracking(1.0)
                            .foregroundStyle(Color.drip.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 12)
            .background(Color.drip.paperDeep)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

// MARK: - Reps table (Act 2 hero)

/// The hero table: REP · PACE · HR. The rep index is a chip filled with that
/// rep's pace-zone colour, so the table reads in the same blue depth ramp as
/// every other pace surface in the app.
///
/// There is deliberately no TARGET column: nothing in the data model carries a
/// prescribed per-rep pace (`WorkoutPrescription` is free text, and
/// `training_logs` has no scheduled-workout link), and the session's own mean
/// is an average, not a target — labelling it one would be a lie.
/// Same reason there's no GAP column: lap rows carry no grade.
/// TODO(TARGET): add the column once a prescribed per-rep pace actually exists.
/// TODO(GAP): add grade-adjusted pace once laps carry grade (altitude stream).
struct RepsTable: View {
    let reps: [RRRep]
    let km: Bool
    let heatOn: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("REP").frame(width: 64, alignment: .leading)
                Spacer(minLength: 0)
                Text("TIME").frame(width: 56, alignment: .trailing)
                Text("PACE").frame(width: 60, alignment: .trailing)
                Text("HR").frame(width: 34, alignment: .trailing)
            }
            .font(.dripStat(9)).tracking(1.0)
            .foregroundStyle(Color.drip.textTertiary)
            .padding(.vertical, 8)
            // Ink header rule — this is the hero, it earns the heavier line.
            .overlay(Rectangle().fill(Color.drip.textPrimary).frame(height: 1), alignment: .bottom)

            ForEach(reps) { r in
                repRow(r)
                // The recovery between reps is an interval too: render each one
                // as its own subordinate row so the rest reads as part of the
                // session, not just an averaged footer note.
                if let rest = r.restSec, rest > 0 {
                    recoveryRow(r)
                }
            }
        }
    }

    private func repRow(_ r: RRRep) -> some View {
        let pace = heatOn ? (r.adjPaceSec ?? r.paceSec) : r.paceSec
        return HStack(spacing: 8) {
            HStack(spacing: 8) {
                zoneChip(r.id, paceSec: pace)
                Text(r.label)
                    .font(.dripStat(11))
                    .foregroundStyle(Color.drip.textSecondary)
            }
            .frame(width: 64, alignment: .leading)
            Spacer(minLength: 0)
            Text(clockMS(splitSec(r)))
                .font(.dripStat(13))
                .foregroundStyle(Color.drip.textSecondary)
                .frame(width: 56, alignment: .trailing)
            Text(rr_pace(pace, km: km))
                .font(.dripStat(14))
                .foregroundStyle(Color.drip.textPrimary)
                .frame(width: 60, alignment: .trailing)
            // No HR on this rep → the cell is simply blank, never an em-dash.
            Text(r.hr.map(String.init) ?? "")
                .font(.dripStat(12))
                .foregroundStyle(Color.drip.textSecondary)
                .frame(width: 34, alignment: .trailing)
        }
        .padding(.vertical, 10)
        .overlay(Rectangle().fill(Color.drip.divider).frame(height: 1), alignment: .bottom)
    }

    /// The recovery interval that follows a rep — visually subordinate to the
    /// work reps (grey dot instead of a numbered chip, muted ink, tinted band).
    /// Labelled neutrally as REC and left to its own numbers: a fartlek float or
    /// an alternation's fast recovery is neither a "jog" nor a "rest", so we
    /// never characterise it — duration always shows, pace/HR show as measured.
    private func recoveryRow(_ r: RRRep) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(PaceZoneScale.recoveryGrey)
                    .frame(width: 8, height: 8)
                    .padding(.horizontal, 6)
                Text("REC")
                    .font(.dripStat(9)).tracking(1.0)
                    .foregroundStyle(Color.drip.textTertiary)
            }
            .frame(width: 64, alignment: .leading)
            Spacer(minLength: 0)
            Text(clockMS(r.restSec ?? 0))
                .font(.dripStat(13))
                .foregroundStyle(Color.drip.textTertiary)
                .frame(width: 56, alignment: .trailing)
            Text(r.restPaceSec.map { rr_pace($0, km: km) } ?? "")
                .font(.dripStat(12))
                .foregroundStyle(Color.drip.textTertiary)
                .frame(width: 60, alignment: .trailing)
            Text(r.restHR.map(String.init) ?? "")
                .font(.dripStat(11))
                .foregroundStyle(Color.drip.textTertiary)
                .frame(width: 34, alignment: .trailing)
        }
        .padding(.vertical, 7)
        .background(PaceZoneScale.recoveryGrey.opacity(0.08))
        .overlay(Rectangle().fill(Color.drip.divider).frame(height: 1), alignment: .bottom)
    }

    private func clockMS(_ s: Int) -> String {
        s < 60 ? String(format: "0:%02d", s) : String(format: "%d:%02d", s / 60, s % 60)
    }

    /// Actual split time for the rep: the recorded lap duration when we have it,
    /// else pace × distance. Never a guess about the effort — just the clock.
    private func splitSec(_ r: RRRep) -> Int {
        r.durSec ?? Int((r.paceSec * r.distMi).rounded())
    }

    /// Rep index in its pace-zone colour. The pale end of the ramp needs ink to
    /// stay legible; the deep navy end needs paper.
    private func zoneChip(_ n: Int, paceSec: Double) -> some View {
        let pos = PaceZoneScale.pos(forPaceSec: paceSec)
        return Text("\(n)")
            .font(.dripStat(9))
            .foregroundStyle(pos < 0.35 ? Color.drip.textPrimary : Color.drip.background)
            .frame(width: 20, height: 20)
            .background(PaceZoneScale.color(forPaceSec: paceSec))
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

/// Compact distance label ("2K" / "1K" / "1mi" / "800m").
func rr_repLabel(_ meters: Double) -> String {
    let mpm = 1609.344
    let miles = meters / mpm
    if abs(miles - miles.rounded()) / max(miles, 1) < 0.08, miles >= 1 { return "\(Int(miles.rounded()))mi" }
    for r in [400.0, 600, 800, 1000, 1200, 1600, 2000, 3000] where abs(meters - r) / r < 0.08 {
        return r.truncatingRemainder(dividingBy: 1000) == 0 ? "\(Int(r / 1000))K" : "\(Int(r))m"
    }
    return "\(Int((meters / 100).rounded() * 100))m"
}

// MARK: - Preview

#Preview {
    func lap(_ i: Int, _ m: Double, _ s: Int, _ p: Double, _ hr: Int, _ rest: Bool = false, _ t: Double = 74, _ dew: Double = 66, _ adj: Double? = nil) -> WorkoutLapRow {
        WorkoutLapRow(lap_index: i, distance_meters: m, moving_time_seconds: s, avg_pace_sec_per_mile: p, avg_heart_rate: hr, is_rest: rest, temp_f: t, dew_point_f: dew, heat_adjusted_pace_sec_per_mile: adj)
    }
    // `heat_adjusted_pace_sec_per_mile` is the NEUTRAL-AIR EQUIVALENT — what the
    // same effort would have been worth in fair air — so it is FASTER than the
    // raw pace, not slower. (fetch-workout-weather writes
    // `neutralEquivalentPaceSeconds`.) This sample had it inverted, which made
    // the conditions plate's HEAT ADJ cell drop out in previews.
    let laps: [WorkoutLapRow] = [
        lap(0, 1609, 480, 480, 132),
        lap(1, 2000, 395, 318, 168, false, 74, 66, 310),
        lap(2, 220, 80, 1900, 150, true),
        lap(3, 1000, 194, 312, 174, false, 74, 66, 304),
        lap(4, 210, 80, 1900, 148, true),
        lap(5, 1000, 194, 312, 175, false, 74, 66, 304),
        lap(6, 210, 80, 1900, 150, true),
        lap(7, 2000, 399, 321, 175, false, 74, 66, 313),
        lap(8, 210, 80, 1900, 150, true),
        lap(9, 1000, 193, 310, 175, false, 74, 66, 302),
        lap(10, 210, 80, 1900, 150, true),
        lap(11, 1000, 195, 314, 175, false, 74, 66, 306),
        lap(12, 1300, 560, 560, 120),
    ]
    let zones = RepChartZones(fiveK: 300, tenK: 312, threshold: 326)
    return ScrollView {
        WorkoutRepReceiptView(laps: laps, zones: zones).padding(20)
    }
    .background(Color.drip.background.ignoresSafeArea())
}
