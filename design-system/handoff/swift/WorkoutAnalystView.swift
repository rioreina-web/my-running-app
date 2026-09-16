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

import SwiftUI

struct WorkoutAnalystView: View {
    let workout: RunningWorkout

    // ── Loaded data ─────────────────────────────────────────────────
    @State private var hrSamples: [Double] = []
    @State private var paceSamples: [Double] = []         // sec/mi, smoothed
    @State private var cadenceSamples: [Double] = []      // spm
    @State private var elevationSamples: [Double] = []
    @State private var recoverySamples: [Double] = []     // 1Hz, 90s after finish
    @State private var splits: [MileSplit] = []
    @State private var zoneSeconds: [String: TimeInterval] = [:]

    // ── Recent baseline (for comparison block) ──────────────────────
    @State private var fourWeekAvg = (hr: 138.0, pace: 458.0, cadence: 172.0, distMi: 5.4)

    // ── Athlete profile ─────────────────────────────────────────────
    private var zones: [DripHRZone] { DripHRZone.defaultZones(maxHR: 185) }

    var body: some View {
        ZStack {
            Color.drip.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    // ─ 0 · Plate strip + heading ─────────────────────
                    DripPlateStrip(
                        leadingBottom: "WORKOUT · TELEMETRY",
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
        .task { await loadStream() }
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

    @ViewBuilder
    private var comparisonRows: some View {
        let pctDist = (workout.distanceMiles - fourWeekAvg.distMi) / fourWeekAvg.distMi * 100
        let pctHR = (Double(avgHR) - fourWeekAvg.hr) / fourWeekAvg.hr * 100
        let pctPace = (Double(workout.pacePerMile * 60) - fourWeekAvg.pace) / fourWeekAvg.pace * 100
        let pctCad = (Double(avgCadence) - fourWeekAvg.cadence) / fourWeekAvg.cadence * 100

        DripComparisonRow(
            label: "DISTANCE",
            nowText: String(format: "%.1f mi", workout.distanceMiles),
            thenText: String(format: "%.1f mi", fourWeekAvg.distMi),
            nowNorm: min(1, workout.distanceMiles / max(workout.distanceMiles, fourWeekAvg.distMi)),
            thenNorm: fourWeekAvg.distMi / max(workout.distanceMiles, fourWeekAvg.distMi),
            pctDelta: pctDist, better: pctDist >= 0
        )
        DripComparisonRow(
            label: "AVG HR",
            nowText: "\(avgHR) bpm",
            thenText: "\(Int(fourWeekAvg.hr)) bpm",
            nowNorm: Double(avgHR) / max(Double(avgHR), fourWeekAvg.hr),
            thenNorm: fourWeekAvg.hr / max(Double(avgHR), fourWeekAvg.hr),
            pctDelta: pctHR, better: pctHR <= 0
        )
        DripComparisonRow(
            label: "AVG PACE",
            nowText: paceString,
            thenText: formatPace(Int(fourWeekAvg.pace)),
            nowNorm: 1 - (Double(workout.pacePerMile * 60) - 400) / 200,
            thenNorm: 1 - (fourWeekAvg.pace - 400) / 200,
            pctDelta: pctPace, better: pctPace <= 0
        )
        DripComparisonRow(
            label: "CADENCE",
            nowText: "\(avgCadence) spm",
            thenText: "\(Int(fourWeekAvg.cadence)) spm",
            nowNorm: Double(avgCadence) / max(Double(avgCadence), fourWeekAvg.cadence),
            thenNorm: fourWeekAvg.cadence / max(Double(avgCadence), fourWeekAvg.cadence),
            pctDelta: pctCad, better: pctCad >= 0
        )
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
        return String(format: "%d:%02d", total / 60, total % 60)
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
            let t = Int(Double(total) * f)
            return String(format: "%d:%02d", t / 60, t % 60)
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
    // Wire to whatever stream service the production app already uses:
    //
    //   let stream = await VitalManager.shared.fetchWorkoutStream(workoutId:)
    //   self.hrSamples = stream?.heartRateSeries.map(\.bpm) ?? []
    //   self.paceSamples = stream?.paceSeries ?? []        // sec/mi smoothed
    //   self.cadenceSamples = stream?.cadenceSeries ?? []
    //   self.elevationSamples = stream?.elevationSeries ?? []
    //   self.recoverySamples = stream?.postFinishHR ?? []  // 90s after end
    //   self.splits = VitalManager.shared.calculateSplits(from: stream)
    //
    //   // Bucket HR into zones
    //   var zs: [String: TimeInterval] = [:]
    //   let dt = workout.durationMinutes * 60 / Double(max(hrSamples.count, 1))
    //   for bpm in hrSamples {
    //       if let z = zones.first(where: { Int(bpm) >= $0.low && Int(bpm) < $0.high }) {
    //           zs[z.id, default: 0] += dt
    //       }
    //   }
    //   self.zoneSeconds = zs
    //
    //   // 4-week baseline from training_logs / workout summary table
    //   self.fourWeekAvg = await fetchRecentAverage(weeks: 4)
    //
    private func loadStream() async {
        // Empty arrays render skeletal UI — replace with real fetch.
    }
}
