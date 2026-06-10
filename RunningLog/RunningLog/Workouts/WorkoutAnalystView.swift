//
//  WorkoutAnalystView.swift
//  RunningLog
//
//  Direction B · "Analyst" — Swift port of the chart-dense workout
//  detail screen. Renders 12 distinct charts in editorial chrome:
//
//    1. Hero stat row             (distance · time · avg HR)
//    2. HR + Elevation stacked    (DripHRZoneChart + DripElevationProfile)
//    3. Pace over time            (DripPaceOverTimeChart, neg-split shading)
//    4. Cadence                   (DripCadenceChart)
//    5. Time in HR zone histogram (DripTimeInZoneRow × 5)
//    6. Efficiency · HR × Pace    (DripHRPaceScatter)
//    7. Aerobic decoupling        (DripHRDriftChart)
//    8. HR recovery 90s           (DripHRRecoveryArc)
//    9. Mile-by-mile sparklines   (DripMileSparklines)
//   10. Splits table              (DripSplitRow × N)
//   11. This-run vs 4w avg        (DripComparisonRow × 4)
//   12. Route                     (existing map snapshot, wrapped)
//
//  Depends on:
//    • DripWorkoutPrimitives.swift  (this folder)
//    • DripEditorialPrimitives.swift (DripPlateStrip, DripHairline, DripEyebrow)
//    • Existing tokens (Color.drip.*, .dripCaption(n), .dripDisplay(n))
//    • Existing models (RunningWorkout, MileSplit)
//

import Supabase
import SwiftUI

struct WorkoutAnalystView: View {
    let workout: RunningWorkout

    /// Training log row id (table `training_logs.id`), passed in when the
    /// caller knows which log this `RunningWorkout` was matched to.
    /// Used by path 1 (Strava / Vital ingestion) to look up the
    /// `external_streams` JSONB on the right row.
    ///
    /// `workout.id` is the HKWorkout UUID, *not* the training_logs id —
    /// they're different identifiers. Passing this in lets path 1
    /// actually find the row. If omitted, path 1 is skipped and we go
    /// straight to the HealthKit fallback (path 2).
    let trainingLogId: UUID?

    init(workout: RunningWorkout, trainingLogId: UUID? = nil) {
        self.workout = workout
        self.trainingLogId = trainingLogId
    }

    @StateObject private var healthKitManager = HealthKitManager()

    // ── Loaded data ─────────────────────────────────────────────────
    @State private var hrSamples: [Double] = []
    @State private var paceSamples: [Double] = []         // sec/mi, smoothed
    @State private var cadenceSamples: [Double] = []      // spm
    @State private var elevationSamples: [Double] = []
    @State private var recoverySamples: [Double] = []     // 1Hz, 90s after finish
    @State private var splits: [MileSplit] = []
    @State private var zoneSeconds: [String: TimeInterval] = [:]

    /// Set to `true` once `loadStream()` returns an actual stream bundle.
    /// Drives the no-stream notice at the top of the screen.
    @State private var streamLoaded = false

    // ── Recent baseline (for comparison block) ──────────────────────
    // Each field is optional — present only when we have real data to
    // compare against. Distance + pace come from `RunningWorkout` history
    // (cheap). HR is averaged from `training_logs.avg_heart_rate` over
    // the last 28 days. Cadence is stream-only and expensive to roll up,
    // so we leave it nil for now and skip that row.
    @State private var fourWeekAvg: (hr: Double?, pace: Double?, cadence: Double?, distMi: Double?) = (nil, nil, nil, nil)

    // ── Athlete profile ─────────────────────────────────────────────
    private var zones: [DripHRZone] { DripHRZone.defaultZones(maxHR: 185) }

    var body: some View {
        ZStack {
            Color.drip.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    // ─ 0 · Plate strip + heading ─────────────────────
                    DripPlateStrip(
                        leadingBottom: "WORKOUT · ANALYSIS",
                        trailingTop: shortDate,
                        trailingBottom: dayAndTime
                    )

                    HStack(alignment: .firstTextBaseline) {
                        Text("\(dayOfWeek) · \(workoutLabel)")
                            .font(.dripDisplay(26))
                            .foregroundStyle(Color.drip.textPrimary)
                        Spacer()
                        Text("\(workout.sourceApp.uppercased()) · \(timeShort)")
                            .font(.dripCaption(9)).tracking(1.2)
                            .foregroundStyle(Color.drip.textTertiary)
                    }
                    .padding(.horizontal, 24).padding(.top, 16)

                    // ─ No-stream notice (only when stream is empty) ──
                    if !streamLoaded {
                        noStreamNotice
                    }

                    // ─ 1 · Hero row 3-up ─────────────────────────────
                    heroRow

                    // ─ 2 · HR + 3 · Pace + 4 · Cadence ───────────────
                    chartBlock(
                        eyebrow: "HEART RATE · ELEVATION",
                        rightText: "00:00 → \(timeString)"
                    ) {
                        DripHRZoneChart(samples: hrSamples, zones: zones).frame(height: 150)
                        if !elevationSamples.isEmpty {
                            DripElevationProfile(samples: elevationSamples).frame(height: 36)
                        }
                        timeAxis
                    }

                    chartBlock(
                        eyebrow: "PACE · SMOOTHED 30S",
                        rightText: "AVG \(paceString) /MI"
                    ) {
                        DripPaceOverTimeChart(samples: paceSamples, showSplit: true)
                            .frame(height: 120)
                    }

                    chartBlock(
                        eyebrow: "CADENCE · SPM",
                        rightText: "AVG \(avgCadence)"
                    ) {
                        DripCadenceChart(samples: cadenceSamples).frame(height: 56)
                    }

                    // ─ 5 · Time in HR zone ───────────────────────────
                    timeInZoneBlock

                    // ─ 6 · Efficiency scatter ────────────────────────
                    chartBlock(
                        eyebrow: "EFFICIENCY · HR × PACE",
                        rightText: "30s WINDOWS"
                    ) {
                        Text("— each dot is a 30s window; coral line is the fit. —")
                            .font(.dripBody(12).italic())
                            .foregroundStyle(Color.drip.textTertiary)
                        DripHRPaceScatter(hrSamples: hrSamples, paceSamples: paceSamples)
                            .frame(height: 180)
                    }

                    // ─ 7 · Aerobic decoupling ────────────────────────
                    chartBlock(eyebrow: "AEROBIC DECOUPLING", rightText: "1st vs 2nd HALF") {
                        DripHRDriftChart(hrSamples: hrSamples, paceSamples: paceSamples)
                    }

                    // ─ 8 · HR recovery ───────────────────────────────
                    chartBlock(eyebrow: "HR RECOVERY · 90S", rightText: nil) {
                        DripHRRecoveryArc(samples: recoverySamples).frame(height: 110)
                    }

                    // ─ 9 · Mile-by-mile sparklines ───────────────────
                    chartBlock(eyebrow: "MILE BY MILE · HR + PACE", rightText: "\(splits.count) SPLITS") {
                        DripMileSparklines(
                            hrSamples: hrSamples,
                            splits: mileSparklineSplits
                        )
                    }

                    // ─ 10 · Splits table ─────────────────────────────
                    splitsTableBlock

                    // ─ 11 · Comparison vs 4w avg ─────────────────────
                    chartBlock(eyebrow: "THIS RUN · vs 4-WEEK AVG", rightText: nil) {
                        VStack(spacing: 0) { comparisonRows }
                    }

                    // ─ 12 · Route ────────────────────────────────────
                    routeBlock

                    Spacer().frame(height: 32)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadStream()
            await loadFourWeekAvg()
        }
    }

    /// Quiet italic-serif notice between the title and the hero row when
    /// no stream bundle exists for this workout. Stream loading happens
    /// automatically in `.task` on appear — there's no user action to
    /// take, so this is purely informational.
    @ViewBuilder
    private var noStreamNotice: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("——")
                .foregroundStyle(Color.drip.textTertiary)
            Text("Detailed stream data isn't available for this workout.")
                .font(.system(size: 13, design: .serif).italic())
                .foregroundStyle(Color.drip.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
    }

    // ════════════════════════════════════════════════════════════════
    // MARK: - Blocks
    // ════════════════════════════════════════════════════════════════

    private var heroRow: some View {
        HStack(spacing: 0) {
            DripHeroStatBlock(label: "DISTANCE",
                              value: String(format: "%.2f", workout.distanceMiles),
                              sub: "MILES")
                .padding(.trailing, 16)
            Rectangle().fill(Color.drip.divider).frame(width: 1)
            DripHeroStatBlock(label: "TIME", value: timeString,
                              sub: "\(paceString) /MI")
                .padding(.horizontal, 16)
            Rectangle().fill(Color.drip.divider).frame(width: 1)
            DripHeroStatBlock(label: "AVG HR", value: "\(avgHR)",
                              sub: "\(minHR)–\(maxHR) BPM",
                              coral: true, alignment: .trailing)
                .padding(.leading, 16)
        }
        .padding(.horizontal, 24).padding(.top, 14)
        .overlay(alignment: .top) { DripHairline().padding(.horizontal, 24) }
        .overlay(alignment: .bottom) { DripHairline().padding(.horizontal, 24) }
    }

    @ViewBuilder
    private func chartBlock<Content: View>(
        eyebrow: String,
        rightText: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                DripEyebrow(text: eyebrow)
                Spacer()
                if let rightText {
                    Text(rightText)
                        .font(.dripCaption(9)).tracking(1.2)
                        .foregroundStyle(Color.drip.textTertiary)
                }
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24).padding(.top, 22)
    }

    private var timeAxis: some View {
        HStack {
            ForEach(Array(timeAxisLabels.enumerated()), id: \.offset) { idx, label in
                Text(label).font(.dripCaption(9)).tracking(1.2).monospacedDigit()
                    .foregroundStyle(Color.drip.textTertiary)
                    .frame(maxWidth: .infinity,
                           alignment: idx == 0 ? .leading
                                      : idx == timeAxisLabels.count - 1 ? .trailing : .center)
            }
        }
    }

    private var timeInZoneBlock: some View {
        let total = zoneSeconds.values.reduce(0, +)
        return chartBlock(eyebrow: "TIME IN HR ZONE", rightText: "OF \(timeString)") {
            VStack(spacing: 0) {
                ForEach(zones) { z in
                    DripTimeInZoneRow(
                        id: z.id,
                        seconds: zoneSeconds[z.id] ?? 0,
                        totalSeconds: total,
                        isPrimary: z.isPrimary
                    )
                }
            }
        }
    }

    private var splitsTableBlock: some View {
        let paceSecs = splits.filter { !$0.isPartial }.map { Int($0.paceMinutes * 60) }
        let minP = paceSecs.min() ?? 0, maxP = paceSecs.max() ?? 0
        return chartBlock(
            eyebrow: "SPLITS",
            rightText: "\(formatPace(minP)) → \(formatPace(maxP))"
        ) {
            // Header
            HStack(spacing: 10) {
                Text("#").font(.dripCaption(9)).tracking(1.2)
                    .foregroundStyle(Color.drip.textTertiary)
                    .frame(width: 20, alignment: .trailing)
                Text("DIST").font(.dripCaption(9)).tracking(1.2)
                    .foregroundStyle(Color.drip.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("PACE").font(.dripCaption(9)).tracking(1.2)
                    .foregroundStyle(Color.drip.textTertiary)
                    .frame(width: 50, alignment: .trailing)
                Text("HR").font(.dripCaption(9)).tracking(1.2)
                    .foregroundStyle(Color.drip.textTertiary)
                    .frame(width: 36, alignment: .trailing)
                Text("CAD").font(.dripCaption(9)).tracking(1.2)
                    .foregroundStyle(Color.drip.textTertiary)
                    .frame(width: 36, alignment: .trailing)
            }
            .padding(.vertical, 4)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.drip.divider).frame(height: 1)
            }
            VStack(spacing: 0) {
                ForEach(splits) { split in
                    let secs = Int(split.paceMinutes * 60)
                    DripSplitRow(
                        index: split.mile,
                        distanceMi: split.isPartial ? split.partialDistance : 1.0,
                        paceSec: secs,
                        paceText: split.formattedPace,
                        hr: split.avgHeartRate,
                        cadence: split.avgCadence,
                        fastest: secs == minP,
                        slowest: secs == maxP,
                        maxPaceSec: maxP,
                        minPaceSec: minP
                    )
                }
            }
        }
    }

    /// Per-metric comparison rows. Each only renders if the matching
    /// `fourWeekAvg.*` field is populated; otherwise the row is skipped
    /// silently so we don't compare today's value against a fake baseline.
    @ViewBuilder
    private var comparisonRows: some View {
        if let then = fourWeekAvg.distMi, then > 0 {
            let pct = (workout.distanceMiles - then) / then * 100
            DripComparisonRow(
                label: "DISTANCE",
                nowText: String(format: "%.1f mi", workout.distanceMiles),
                thenText: String(format: "%.1f mi", then),
                nowNorm: min(1, workout.distanceMiles / max(workout.distanceMiles, then)),
                thenNorm: then / max(workout.distanceMiles, then),
                pctDelta: pct, better: pct >= 0
            )
        }
        if let then = fourWeekAvg.hr, then > 0, avgHR > 0 {
            let now = Double(avgHR)
            let pct = (now - then) / then * 100
            DripComparisonRow(
                label: "AVG HR",
                nowText: "\(avgHR) bpm",
                thenText: "\(Int(then)) bpm",
                nowNorm: now / max(now, then),
                thenNorm: then / max(now, then),
                pctDelta: pct, better: pct <= 0
            )
        }
        if let then = fourWeekAvg.pace, then > 0 {
            let now = Double(workout.pacePerMile * 60)
            let pct = (now - then) / then * 100
            DripComparisonRow(
                label: "AVG PACE",
                nowText: paceString,
                thenText: formatPace(Int(then)),
                nowNorm: 1 - (now - 400) / 200,
                thenNorm: 1 - (then - 400) / 200,
                pctDelta: pct, better: pct <= 0
            )
        }
        if let then = fourWeekAvg.cadence, then > 0, avgCadence > 0 {
            let now = Double(avgCadence)
            let pct = (now - then) / then * 100
            DripComparisonRow(
                label: "CADENCE",
                nowText: "\(avgCadence) spm",
                thenText: "\(Int(then)) spm",
                nowNorm: now / max(now, then),
                thenNorm: then / max(now, then),
                pctDelta: pct, better: pct >= 0
            )
        }

        // If we couldn't load anything yet, render a quiet placeholder so
        // the section doesn't look broken — it's just waiting for data.
        if fourWeekAvg.distMi == nil && fourWeekAvg.pace == nil
            && fourWeekAvg.hr == nil && fourWeekAvg.cadence == nil {
            Text("No baseline data yet — needs at least a few logged runs in the last 28 days.")
                .font(.system(size: 13, design: .serif).italic())
                .foregroundStyle(Color.drip.textSecondary)
                .padding(.vertical, 8)
        }
    }

    private var routeBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                DripEyebrow(text: "ROUTE")
                Spacer()
                Button {
                    // present existing GPS map sheet
                } label: {
                    Text("OPEN MAP ↗")
                        .font(.dripCaption(10)).tracking(1.4)
                        .foregroundStyle(Color.drip.coral)
                }
                .buttonStyle(.plain)
            }
            // TODO: drop the existing MKMapView snapshot inside this well,
            // or wrap whatever map view the production code uses.
            Rectangle()
                .fill(Color.drip.paperDeep)
                .frame(height: 140)
                .overlay(
                    Text("ROUTE · \(String(format: "%.1f", workout.distanceMiles))MI")
                        .font(.dripCaption(9)).tracking(1.2)
                        .foregroundStyle(Color.drip.textTertiary)
                )
                .overlay(Rectangle().stroke(Color.drip.divider, lineWidth: 1))
        }
        .padding(.horizontal, 24).padding(.top, 22)
    }

    // ════════════════════════════════════════════════════════════════
    // MARK: - Computed labels
    // ════════════════════════════════════════════════════════════════

    private var dayOfWeek: String {
        let f = DateFormatter(); f.dateFormat = "EEEE"
        return f.string(from: workout.startDate)
    }
    private var workoutLabel: String { "easy" } // TODO: classifier
    private var shortDate: String {
        let f = DateFormatter(); f.dateFormat = "MM.dd"
        return f.string(from: workout.startDate).uppercased()
    }
    private var dayAndTime: String {
        let f = DateFormatter(); f.dateFormat = "EEE · HH:mm"
        return f.string(from: workout.startDate).uppercased()
    }
    private var timeShort: String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: workout.startDate)
    }
    private var timeString: String {
        let total = Int(workout.durationMinutes * 60)
        return Self.formatElapsed(total)
    }

    /// Render an elapsed duration as `m:ss` under an hour, `h:mm:ss` at
    /// or above an hour. Used for the TIME hero cell, chart range
    /// labels, and "OF" totals so a 1h2m run reads as `1:02:16`, not
    /// `62:16`.
    static func formatElapsed(_ totalSeconds: Int) -> String {
        let s = max(0, totalSeconds)
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, sec)
        }
        return String(format: "%d:%02d", m, sec)
    }
    private var paceString: String {
        let total = Int(workout.pacePerMile * 60)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
    private var avgHR: Int {
        guard !hrSamples.isEmpty else { return 0 }
        return Int(hrSamples.reduce(0, +) / Double(hrSamples.count))
    }
    private var minHR: Int { Int(hrSamples.min() ?? 0) }
    private var maxHR: Int { Int(hrSamples.max() ?? 0) }
    private var avgCadence: Int {
        guard !cadenceSamples.isEmpty else { return 0 }
        return Int(cadenceSamples.reduce(0, +) / Double(cadenceSamples.count))
    }

    private var timeAxisLabels: [String] {
        let total = Int(workout.durationMinutes * 60)
        return [0.0, 0.25, 0.5, 0.75, 1.0].map { f in
            Self.formatElapsed(Int(Double(total) * f))
        }
    }

    private var mileSparklineSplits:
        [(mile: Int, paceText: String, hr: Int, paceSec: Int, isFastest: Bool)]
    {
        let secs = splits.map { Int($0.paceMinutes * 60) }
        let minP = secs.min() ?? 0
        return splits.map { s in
            let p = Int(s.paceMinutes * 60)
            return (mile: s.mile,
                    paceText: s.formattedPace,
                    hr: s.avgHeartRate ?? 0,
                    paceSec: p,
                    isFastest: p == minP)
        }
    }

    private func formatPace(_ sec: Int) -> String {
        String(format: "%d:%02d", sec / 60, sec % 60)
    }

    // ════════════════════════════════════════════════════════════════
    // MARK: - Data loading
    // ════════════════════════════════════════════════════════════════
    //
    // Pulls the same external_streams bundle VitalWorkoutDetailView /
    // WorkoutAnalysisView already consume (Strava etc. via
    // ExternalStreamAdapter), then derives the per-chart series. Splits
    // come from the production calculator (VitalManager.calculateSplits)
    // so this screen stays consistent with the rest of the app.
    //
    // Not yet wired (data not present in the stream bundle):
    //   • recoverySamples — post-finish HR isn't in the activity stream.
    //   • fourWeekAvg — keeps its placeholder baseline until a recent-
    //     average query is added (see comparison block).
    //
    private func loadStream() async {
        print("[WorkoutAnalyst] loadStream START · workout.id=\(workout.id) · source=\(workout.sourceApp) · vitalId=\(workout.vitalWorkoutId ?? "nil") · trainingLogId=\(trainingLogId?.uuidString ?? "nil")")

        // Path 1 — `training_logs.external_streams` JSONB
        if let logId = trainingLogId {
            if let bundle = await ExternalStreamAdapter.load(forTrainingLogId: logId),
               let stream = bundle.stream {
                print("[WorkoutAnalyst] path 1 (JSONB) HIT · hr=\(stream.heartrate?.count ?? 0) pts · pace=\(stream.velocitySmooth?.count ?? 0) pts")
                await processVitalStream(stream)
                return
            } else {
                print("[WorkoutAnalyst] path 1 (JSONB) NIL — external_streams empty or row not found for trainingLogId=\(logId.uuidString)")
            }
        } else {
            print("[WorkoutAnalyst] path 1 (JSONB) SKIPPED — no trainingLogId provided")
        }

        // Path 2 — Vital live fetch
        if let vitalId = workout.vitalWorkoutId {
            if let stream = await VitalManager.shared.fetchWorkoutStream(workoutId: vitalId) {
                print("[WorkoutAnalyst] path 2 (Vital live) HIT · vitalId=\(vitalId) · hr=\(stream.heartrate?.count ?? 0) pts")
                await processVitalStream(stream)
                return
            } else {
                print("[WorkoutAnalyst] path 2 (Vital live) NIL — fetchWorkoutStream returned nil for vitalId=\(vitalId)")
            }
        } else {
            print("[WorkoutAnalyst] path 2 (Vital live) SKIPPED — workout has no vitalWorkoutId")
        }

        // Path 3 — HealthKit fallback
        if let hkWorkout = await healthKitManager.fetchWorkoutWithUUID(workout.id) {
            if let payload = await healthKitManager.buildExternalStreams(
                for: hkWorkout,
                calories: workout.calories
            ) {
                print("[WorkoutAnalyst] path 3 (HK live) HIT · hr=\(payload.streams.heartrate?.count ?? 0) pts")
                let splits = await healthKitManager.fetchWorkoutSplits(for: hkWorkout)
                await processHealthKitPayload(payload, splits: splits)
                return
            } else {
                print("[WorkoutAnalyst] path 3 (HK live) NIL — buildExternalStreams returned nil")
            }
        } else {
            print("[WorkoutAnalyst] path 3 (HK live) NIL — no HKWorkout matches workout.id=\(workout.id)")
        }

        print("[WorkoutAnalyst] loadStream END · ALL PATHS EMPTY")
    }

    /// Shared parser — accepts the raw sample arrays from either stream
    /// source and writes them into the @State vars the charts read from.
    @MainActor
    private func assignSamples(
        hr: [Double], pace: [Double], cad: [Double],
        elev: [Double], splits: [MileSplit]
    ) {
        // Bucket HR samples into zones. Each sample represents `dt` seconds.
        var zs: [String: TimeInterval] = [:]
        if !hr.isEmpty {
            let dt = (workout.durationMinutes * 60) / Double(hr.count)
            for bpm in hr {
                if let z = zones.first(where: { Int(bpm) >= $0.low && Int(bpm) < $0.high }) {
                    zs[z.id, default: 0] += dt
                }
            }
        }

        self.hrSamples = hr
        self.paceSamples = pace
        self.cadenceSamples = cad
        self.elevationSamples = elev
        self.splits = splits
        self.zoneSeconds = zs
        self.streamLoaded = true
    }

    /// Strava / Vital path — operates on the existing VitalWorkoutStream
    /// shape ExternalStreamAdapter returns.
    private func processVitalStream(_ stream: VitalWorkoutStream) async {
        let hr = (stream.heartrate ?? []).map(Double.init)
        let metersPerMile = 1609.344
        let rawPace = (stream.velocitySmooth ?? [])
            .filter { $0 > 0.3 }
            .map { metersPerMile / $0 }
        let pace = Self.movingAverage(rawPace, window: 30)

        // Cadence → steps/min. Strava reports single-leg; double when median < 120.
        var cad = (stream.cadence ?? []).filter { $0 > 0 }
        if let med = Self.median(cad), med < 120 {
            cad = cad.map { $0 * 2 }
        }

        let elev = stream.altitude ?? []
        let computedSplits = VitalManager.shared.calculateSplits(from: stream)

        await assignSamples(hr: hr, pace: pace, cad: cad, elev: elev, splits: computedSplits)
    }

    /// HealthKit fallback path — operates on the ExternalStreamsPayload
    /// produced by `HealthKitManager.buildExternalStreams`. Same shape
    /// fields as the Strava path; splits come straight from HK GPS.
    private func processHealthKitPayload(_ payload: ExternalStreamsPayload, splits: [MileSplit]) async {
        let hr = (payload.streams.heartrate ?? []).map(Double.init)
        let metersPerMile = 1609.344
        let rawPace = (payload.streams.velocitySmooth ?? [])
            .filter { $0 > 0.3 }
            .map { metersPerMile / $0 }
        let pace = Self.movingAverage(rawPace, window: 30)

        // HK cadence is already two-leg spm (HK reports a single per-step
        // value at full stride). No doubling needed.
        let cad = (payload.streams.cadence ?? []).filter { $0 > 0 }
        let elev = payload.streams.altitude ?? []

        await assignSamples(hr: hr, pace: pace, cad: cad, elev: elev, splits: splits)
    }

    /// Compute a real 4-week baseline for the THIS RUN · vs 4-WEEK AVG
    /// comparison block. Replaces the hardcoded mock that used to live
    /// in `fourWeekAvg`.
    ///
    /// - Distance + pace: averaged from `HealthKitManager` workouts in
    ///   the last 28 days, excluding the current workout.
    /// - HR: averaged from `training_logs.avg_heart_rate` (cheap aggregate
    ///   query — far cheaper than fetching streams per workout).
    /// - Cadence: stream-only, expensive to roll up; left nil for now.
    ///   The matching comparison row is skipped when nil.
    private func loadFourWeekAvg() async {
        // Distance + pace from HealthKit
        let workouts = await healthKitManager.fetchRecentRunningWorkouts(limit: 40)
        let cutoff = Calendar.current.date(byAdding: .day, value: -28, to: Date()) ?? Date()
        let recent = workouts.filter {
            $0.startDate >= cutoff && $0.id != workout.id && $0.distanceMiles > 0
        }

        var distMi: Double?
        var paceSec: Double?
        if !recent.isEmpty {
            distMi = recent.map(\.distanceMiles).reduce(0, +) / Double(recent.count)
            // pacePerMile is minutes/mile (Double); convert to sec/mi
            paceSec = recent.map { $0.pacePerMile * 60 }.reduce(0, +) / Double(recent.count)
        }

        // HR average from training_logs over the same window
        var hrAvg: Double?
        do {
            struct Row: Decodable { let avg_heart_rate: Int? }
            let isoFormatter = ISO8601DateFormatter()
            let rows: [Row] = try await supabase
                .from("training_logs")
                .select("avg_heart_rate")
                .gte("workout_date", value: isoFormatter.string(from: cutoff))
                .not("avg_heart_rate", operator: .is, value: "null")
                .neq("id", value: workout.id.uuidString)
                .execute()
                .value
            let bpms = rows.compactMap { $0.avg_heart_rate }.map(Double.init)
            if !bpms.isEmpty {
                hrAvg = bpms.reduce(0, +) / Double(bpms.count)
            }
        } catch {
            print("[WorkoutAnalyst] 4w avg HR query failed: \(error)")
        }

        await MainActor.run {
            fourWeekAvg = (hr: hrAvg, pace: paceSec, cadence: nil, distMi: distMi)
        }
    }

    /// Simple trailing moving average. `window` is in samples (≈ seconds for
    /// 1 Hz streams). Returns the input unchanged if it's shorter than 2.
    private static func movingAverage(_ values: [Double], window: Int) -> [Double] {
        guard values.count > 1, window > 1 else { return values }
        var out: [Double] = []
        out.reserveCapacity(values.count)
        var sum = 0.0
        var queue: [Double] = []
        for v in values {
            queue.append(v); sum += v
            if queue.count > window { sum -= queue.removeFirst() }
            out.append(sum / Double(queue.count))
        }
        return out
    }

    /// Median of a sample set (nil if empty). Used to detect single-leg cadence.
    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }
}
