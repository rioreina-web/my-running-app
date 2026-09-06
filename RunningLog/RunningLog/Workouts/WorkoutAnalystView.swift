//
//  WorkoutAnalystView.swift
//  RunningLog
//
//  The workout detail screen — what you get when you open a run.
//
//  Simplified 2026-09-06. The previous version stacked twelve charts of
//  equal visual weight, ~2,500pt of scroll, with no answer at the top.
//  This version answers first and buries the analysis:
//
//    DEFAULT (about one and a half screens)
//      · heading + 4-cell stat strip   — distance · time · pace · avg HR
//      · one plain-language read       — what the run was, in numbers
//      · SHAPE OF THE RUN              — pace × HR × elevation, ONE chart
//      · EFFORT                        — a single stacked zone bar
//      · SPLITS                        — mile · pace · HR
//
//    MORE DETAIL (collapsed; everything the old screen showed)
//      · AT A GLANCE   — cadence, elevation gain, decoupling, efficiency
//      · CADENCE       — DripCadenceChart
//      · EFFICIENCY    — DripHRPaceScatter
//      · DECOUPLING    — DripHRDriftChart
//      · HR RECOVERY   — DripHRRecoveryArc
//      · VS 4 WEEKS    — DripComparisonRow
//      · ROUTE
//
//  Six of the old blocks moved into the drawer unchanged. Four were
//  folded into something smaller that says the same thing:
//
//    · HR + elevation, pace-over-time  →  one DripRunShapeChart
//    · time-in-HR-zone (5 rows)        →  one DripZoneBar + a sentence
//    · mile-by-mile sparklines         →  dropped; the splits table
//                                         already said it
//
//  No primitive was deleted. `DripHRZoneChart`, `DripElevationProfile`,
//  `DripPaceOverTimeChart`, `DripTimeInZoneRow` and `DripMileSparklines`
//  are now unreferenced but stay in `DripWorkoutPrimitives.swift` —
//  removing them is a separate call, and a future full-analysis surface
//  is the obvious home for them.
//
//  The plain-language read is composed in Swift from the numbers on
//  screen (`runReadLine`) — no LLM, so no eval-harness gate. It states
//  what happened and never what to do about it, per
//  `docs/coaching/principles.md`.
//
//  Depends on:
//    • DripWorkoutPrimitives.swift  (this folder)
//    • DripEditorialPrimitives.swift (DripPlateStrip, DripHairline,
//      DripEyebrow, DripZone, DripZoneBar)
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

    /// Collapsed by default. The analytical charts are real work for a
    /// reader, and most opens of this screen are "how did that run go",
    /// not "walk me through my aerobic decoupling."
    @State private var showMoreDetail = false

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
                    header
                    heroRow
                    runReadBlock
                    shapeBlock
                    effortBlock
                    splitsBlock
                    moreDetailDrawer
                    Spacer().frame(height: 40)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadStream()
            await loadFourWeekAvg()
        }
    }

    // ════════════════════════════════════════════════════════════════
    // MARK: - Default view
    // ════════════════════════════════════════════════════════════════

    /// Plate strip, day, and one italic line of provenance. The old
    /// header crammed day, workout label, source, and time onto one row
    /// at 26pt; this gives the day the display size it deserves and
    /// demotes the rest to a serif subtitle.
    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            DripPlateStrip(
                leadingBottom: "WORKOUT · DETAIL",
                trailingTop: shortDate,
                trailingBottom: dayAndTime
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(dayOfWeek)
                    .font(.dripDisplay(44))
                    .foregroundStyle(Color.drip.textPrimary)
                Text(subtitleLine)
                    .font(.dripBody(14).italic())
                    .foregroundStyle(Color.drip.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 26)

            if !streamLoaded {
                noStreamNotice
            }
        }
    }

    /// Four cells, evenly weighted, hairline top and bottom. Distance,
    /// time and pace are the three numbers every runner reads first;
    /// avg HR earns the fourth cell and the screen's coral, which is
    /// also the colour of the heart-rate line in the shape chart.
    private var heroRow: some View {
        HStack(spacing: 0) {
            heroCell(String(format: "%.2f", workout.distanceMiles), "MILES")
            heroDivider
            heroCell(timeString, "TIME")
            heroDivider
            heroCell(paceString, "/MI")
            if avgHR > 0 {
                heroDivider
                heroCell("\(avgHR)", "AVG HR", coral: true)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .overlay(alignment: .top) { DripHairline().padding(.horizontal, 24) }
        .overlay(alignment: .bottom) { DripHairline().padding(.horizontal, 24) }
    }

    private func heroCell(_ value: String, _ label: String, coral: Bool = false) -> some View {
        VStack(spacing: 5) {
            Text(value)
                .font(.dripCaption(21)).fontWeight(.semibold).monospacedDigit()
                .foregroundStyle(coral ? Color.drip.coral : Color.drip.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.5)
            Text(label)
                .font(.dripCaption(9)).tracking(1.2)
                .foregroundStyle(Color.drip.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }

    private var heroDivider: some View {
        Rectangle().fill(Color.drip.divider).frame(width: 1, height: 34)
    }

    /// The one thing the old screen never had: a sentence telling you
    /// how the run went, before any chart. Composed from the numbers
    /// already on screen — observation only, never a recommendation.
    @ViewBuilder
    private var runReadBlock: some View {
        if let line = runReadLine {
            Text(line)
                .font(.dripBody(15).italic())
                .foregroundStyle(Color.drip.textPrimary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 22)
        }
    }

    /// Pace, heart rate and elevation in a single frame. Was three
    /// separately-scrolled charts plus two axis rows.
    @ViewBuilder
    private var shapeBlock: some View {
        if !paceSamples.isEmpty || !hrSamples.isEmpty {
            section(eyebrow: "SHAPE OF THE RUN", rightText: "PACE × HR × ELEVATION") {
                DripRunShapeChart(
                    paceSamples: paceSamples,
                    hrSamples: hrSamples,
                    elevationSamples: elevationSamples
                )
                .frame(height: 168)

                DripChartKey(
                    items: [
                        .init("PACE", color: Color.drip.textPrimary),
                        .init("HEART RATE", color: Color.drip.coral),
                        .init("ELEVATION", color: Color.drip.textPrimary.opacity(0.12), filled: true),
                    ],
                    trailing: timeString
                )
                .padding(.top, 8)
            }
        }
    }

    /// One stacked bar instead of five histogram rows, plus a sentence
    /// naming the zone the run actually lived in.
    @ViewBuilder
    private var effortBlock: some View {
        if zoneTotalSeconds > 0 {
            sectionRule
            section(eyebrow: "EFFORT", rightText: "\(timeString) TOTAL") {
                DripZoneBar(zones: effortZones, height: 16)
                HStack(spacing: 0) {
                    ForEach(zones) { z in
                        Text(zoneShare(z) >= 0.11 ? z.id : "")
                            .font(.dripCaption(9)).tracking(1.2)
                            .foregroundStyle(Color.drip.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.top, 6)

                if let sentence = effortSentence {
                    Text(sentence)
                        .font(.dripBody(13).italic())
                        .foregroundStyle(Color.drip.textSecondary)
                        .padding(.top, 10)
                }
            }
        }
    }

    /// Mile · pace · HR. The distance caption and cadence column moved
    /// out — cadence is one number in "at a glance", and every full
    /// split is a mile by definition.
    @ViewBuilder
    private var splitsBlock: some View {
        if !splits.isEmpty {
            sectionRule
            section(
                eyebrow: "SPLITS",
                rightText: splits.count == 1 ? "1 MILE" : "\(splits.count) MILES"
            ) {
                HStack(spacing: 10) {
                    Text("MI").font(.dripCaption(9)).tracking(1.2)
                        .foregroundStyle(Color.drip.textTertiary)
                        .frame(width: 20, alignment: .trailing)
                    Spacer(minLength: 0)
                    Text("PACE").font(.dripCaption(9)).tracking(1.2)
                        .foregroundStyle(Color.drip.textTertiary)
                        .frame(width: 50, alignment: .trailing)
                    Text("HR").font(.dripCaption(9)).tracking(1.2)
                        .foregroundStyle(Color.drip.textTertiary)
                        .frame(width: 36, alignment: .trailing)
                }
                .padding(.bottom, 6)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.drip.divider).frame(height: 1)
                }

                ForEach(splits) { split in
                    DripSplitRow(
                        index: split.mile,
                        distanceMi: split.isPartial ? split.partialDistance : 1.0,
                        paceSec: Int(split.paceMinutes * 60),
                        paceText: split.formattedPace,
                        hr: split.avgHeartRate,
                        cadence: split.avgCadence,
                        fastest: Int(split.paceMinutes * 60) == fastestSplitSec,
                        slowest: Int(split.paceMinutes * 60) == slowestSplitSec,
                        maxPaceSec: slowestSplitSec,
                        minPaceSec: fastestSplitSec,
                        compact: true
                    )
                }
            }
        }
    }

    // ════════════════════════════════════════════════════════════════
    // MARK: - More detail (collapsed)
    // ════════════════════════════════════════════════════════════════

    private var moreDetailDrawer: some View {
        VStack(spacing: 0) {
            sectionRule

            Button {
                withAnimation(.easeInOut(duration: 0.22)) { showMoreDetail.toggle() }
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        DripEyebrow(text: "MORE DETAIL")
                        Spacer()
                        Text(showMoreDetail ? "−" : "+")
                            .font(.dripCaption(15)).fontWeight(.semibold)
                            .foregroundStyle(Color.drip.coral)
                    }
                    if !showMoreDetail {
                        Text(moreDetailSummary)
                            .font(.dripBody(13).italic())
                            .foregroundStyle(Color.drip.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showMoreDetail ? "Hide more detail" : "Show more detail")

            if showMoreDetail {
                atAGlanceBlock
                cadenceBlock
                efficiencyBlock
                decouplingBlock
                recoveryBlock
                comparisonBlock
                routeBlock
            }
        }
    }

    /// Numbers that used to cost a whole chart each.
    @ViewBuilder
    private var atAGlanceBlock: some View {
        if !glanceRows.isEmpty {
            section(eyebrow: "AT A GLANCE", rightText: nil) {
                ForEach(glanceRows) { row in
                    DripKeyValueRow(label: row.label, value: row.value)
                }
            }
        }
    }

    @ViewBuilder
    private var cadenceBlock: some View {
        if !cadenceSamples.isEmpty {
            section(eyebrow: "CADENCE", rightText: "AVG \(avgCadence) SPM") {
                DripCadenceChart(samples: cadenceSamples).frame(height: 56)
            }
        }
    }

    @ViewBuilder
    private var efficiencyBlock: some View {
        if !hrSamples.isEmpty, !paceSamples.isEmpty {
            section(eyebrow: "EFFICIENCY", rightText: "HR × PACE, 30S WINDOWS") {
                DripHRPaceScatter(hrSamples: hrSamples, paceSamples: paceSamples)
                    .frame(height: 170)
            }
        }
    }

    @ViewBuilder
    private var decouplingBlock: some View {
        if !hrSamples.isEmpty, !paceSamples.isEmpty {
            section(eyebrow: "AEROBIC DECOUPLING", rightText: "1ST VS 2ND HALF") {
                DripHRDriftChart(hrSamples: hrSamples, paceSamples: paceSamples)
            }
        }
    }

    @ViewBuilder
    private var recoveryBlock: some View {
        if !recoverySamples.isEmpty {
            section(eyebrow: "HEART-RATE RECOVERY", rightText: "90S AFTER FINISH") {
                DripHRRecoveryArc(samples: recoverySamples).frame(height: 110)
            }
        }
    }

    @ViewBuilder
    private var comparisonBlock: some View {
        if hasBaseline {
            section(eyebrow: "VS YOUR LAST 4 WEEKS", rightText: nil) {
                VStack(spacing: 0) { comparisonRows }
            }
        }
    }

    private var routeBlock: some View {
        section(eyebrow: "ROUTE", rightText: nil) {
            // TODO: drop the existing MKMapView snapshot inside this well,
            // or wrap whatever map view the production code uses.
            Rectangle()
                .fill(Color.drip.paperDeep)
                .frame(height: 150)
                .overlay(
                    Text("ROUTE · \(String(format: "%.1f", workout.distanceMiles)) MI")
                        .font(.dripCaption(9)).tracking(1.2)
                        .foregroundStyle(Color.drip.textTertiary)
                )
                .overlay(Rectangle().stroke(Color.drip.divider, lineWidth: 1))
        }
    }

    /// Quiet italic-serif notice between the title and the hero row when
    /// no stream bundle exists for this workout. Stream loading happens
    /// automatically in `.task` on appear — there's no user action to
    /// take, so this is purely informational.
    private var noStreamNotice: some View {
        Text("Detailed stream data isn't available for this run — distance, time and pace only.")
            .font(.dripBody(13).italic())
            .foregroundStyle(Color.drip.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 14)
    }

    // ════════════════════════════════════════════════════════════════
    // MARK: - Section chrome
    // ════════════════════════════════════════════════════════════════

    /// Eyebrow row + content, on the 24pt editorial margin. Replaces the
    /// old `chartBlock` — same shape, but sections are now separated by
    /// explicit rules rather than by nothing at all, which is what made
    /// twelve of them read as one undifferentiated column.
    @ViewBuilder
    private func section<Content: View>(
        eyebrow: String,
        rightText: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                DripEyebrow(text: eyebrow)
                Spacer(minLength: 8)
                if let rightText {
                    Text(rightText)
                        .font(.dripCaption(9)).tracking(1.2)
                        .foregroundStyle(Color.drip.textTertiary)
                }
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 24)
    }

    private var sectionRule: some View {
        DripHairline()
            .padding(.horizontal, 24)
            .padding(.top, 24)
    }

    // ════════════════════════════════════════════════════════════════
    // MARK: - Copy
    // ════════════════════════════════════════════════════════════════

    /// "Easy · 6.9 miles · from Strava"
    private var subtitleLine: String {
        var parts: [String] = [workoutLabel.capitalized]
        parts.append(String(format: "%.1f miles", workout.distanceMiles))
        if !workout.sourceApp.isEmpty {
            parts.append("from \(workout.sourceApp)")
        }
        return parts.joined(separator: " · ")
    }

    /// One or two sentences describing what happened, built from the
    /// numbers already on screen. Every clause cites a figure; none of
    /// them tells the athlete what to do about it — this screen
    /// observes, the Coach tab advises, and neither prescribes.
    /// Returns nil when there isn't enough data to say anything true.
    private var runReadLine: String? {
        var clauses: [String] = []

        // Split shape — only claimed when the halves actually differ.
        if splits.count >= 4 {
            let secs = splits.filter { !$0.isPartial }.map { Int($0.paceMinutes * 60) }
            if secs.count >= 4 {
                let half = secs.count / 2
                let first = secs.prefix(half).reduce(0, +) / half
                let second = secs.suffix(secs.count - half).reduce(0, +) / (secs.count - half)
                let delta = abs(first - second)
                if delta >= 8 {
                    clauses.append(
                        second < first
                            ? "The second half ran \(delta) seconds a mile quicker than the first."
                            : "The second half ran \(delta) seconds a mile slower than the first."
                    )
                } else {
                    clauses.append("Pace held even across both halves, inside \(max(delta, 1)) seconds a mile.")
                }
            }
        }

        // Fastest mile — the detail runners look for.
        if splits.count >= 3, let fastest = splits.filter({ !$0.isPartial }).min(by: { $0.paceMinutes < $1.paceMinutes }) {
            clauses.append("Mile \(fastest.mile) was the quickest at \(fastest.formattedPace).")
        }

        // Drift — stated as a number, not as a verdict.
        if let drift = hrDriftPercent {
            clauses.append(String(format: "Heart rate drifted %+.1f%% between halves.", drift))
        }

        guard !clauses.isEmpty else { return nil }
        return clauses.prefix(3).joined(separator: " ")
    }

    /// "Mostly zone 3 — 23:30, or 46% of the run."
    private var effortSentence: String? {
        guard zoneTotalSeconds > 0 else { return nil }
        let ranked = zones
            .map { ($0, zoneSeconds[$0.id] ?? 0) }
            .sorted { $0.1 > $1.1 }
        guard let top = ranked.first, top.1 > 0 else { return nil }
        let pct = Int(((top.1 / zoneTotalSeconds) * 100).rounded())
        let label = top.0.id.replacingOccurrences(of: "Z", with: "zone ")
        return "Mostly \(label) — \(Self.formatElapsed(Int(top.1))), or \(pct)% of the run."
    }

    /// Names what's behind the drawer so the affordance isn't a mystery.
    private var moreDetailSummary: String {
        var items: [String] = []
        if !cadenceSamples.isEmpty { items.append("cadence") }
        if !hrSamples.isEmpty, !paceSamples.isEmpty {
            items.append(contentsOf: ["efficiency", "decoupling"])
        }
        if !recoverySamples.isEmpty { items.append("recovery") }
        if hasBaseline { items.append("four-week comparison") }
        items.append("route")
        let joined = items.joined(separator: ", ")
        return joined.prefix(1).uppercased() + String(joined.dropFirst()) + "."
    }

    /// One line of "at a glance". A struct rather than a tuple because
    /// `ForEach` needs a stable identity and Swift has no key paths into
    /// tuple components.
    private struct GlanceRow: Identifiable {
        let id = UUID()
        let label: String
        let value: String
    }

    /// Rows for "at a glance" — each one only appears when it has a real
    /// number behind it. No em-dash placeholders (hard rule #8).
    private var glanceRows: [GlanceRow] {
        var rows: [GlanceRow] = []
        if avgCadence > 0 { rows.append(GlanceRow(label: "CADENCE", value: "\(avgCadence) spm")) }
        if let gain = elevationGainFeet, gain > 0 { rows.append(GlanceRow(label: "ELEVATION GAIN", value: "\(gain) ft")) }
        if avgHR > 0, maxHR > 0 { rows.append(GlanceRow(label: "HEART RATE RANGE", value: "\(minHR)–\(maxHR) bpm")) }
        if let drift = hrDriftPercent {
            rows.append(GlanceRow(label: "AEROBIC DECOUPLING", value: String(format: "%+.1f%%", drift)))
        }
        if let ef = efficiencyFactor {
            rows.append(GlanceRow(label: "EFFICIENCY FACTOR", value: String(format: "%.2f", ef)))
        }
        if workout.calories > 0 {
            rows.append(GlanceRow(label: "ENERGY", value: "\(Int(workout.calories)) kcal"))
        }
        return rows
    }

    // ════════════════════════════════════════════════════════════════
    // MARK: - Derived figures
    // ════════════════════════════════════════════════════════════════

    private var zoneTotalSeconds: Double { zoneSeconds.values.reduce(0, +) }

    private func zoneShare(_ z: DripHRZone) -> Double {
        guard zoneTotalSeconds > 0 else { return 0 }
        return (zoneSeconds[z.id] ?? 0) / zoneTotalSeconds
    }

    /// Zone segments for the stacked effort bar. Coral marks the zone
    /// the run mostly lived in — one coral per cluster, and it's the
    /// segment the sentence underneath names.
    private var effortZones: [DripZone] {
        let dominant = zones.max(by: { zoneShare($0) < zoneShare($1) })?.id
        return zones.map { z in
            let share = zoneShare(z)
            let color: Color = z.id == dominant
                ? Color.drip.coral
                : Color.drip.textSecondary.opacity(0.15 + 0.45 * share)
            return DripZone(color: color, pct: share * 100)
        }
    }

    private var fastestSplitSec: Int {
        splits.filter { !$0.isPartial }.map { Int($0.paceMinutes * 60) }.min() ?? 0
    }

    private var slowestSplitSec: Int {
        splits.filter { !$0.isPartial }.map { Int($0.paceMinutes * 60) }.max() ?? 0
    }

    private var hasBaseline: Bool {
        fourWeekAvg.distMi != nil || fourWeekAvg.pace != nil
            || fourWeekAvg.hr != nil || fourWeekAvg.cadence != nil
    }

    /// Pa:Hr decoupling — the percentage change in heart-rate-per-pace
    /// between the two halves of the run. Reported as a number only;
    /// interpreting it is not this screen's job.
    private var hrDriftPercent: Double? {
        guard hrSamples.count >= 4, paceSamples.count >= 4 else { return nil }
        let hHalf = hrSamples.count / 2
        let pHalf = paceSamples.count / 2
        let hr1 = hrSamples.prefix(hHalf).reduce(0, +) / Double(hHalf)
        let hr2 = hrSamples.suffix(hrSamples.count - hHalf).reduce(0, +) / Double(hrSamples.count - hHalf)
        let sp1 = paceSamples.prefix(pHalf).reduce(0, +) / Double(pHalf)
        let sp2 = paceSamples.suffix(paceSamples.count - pHalf).reduce(0, +) / Double(paceSamples.count - pHalf)
        guard hr1 > 0, hr2 > 0, sp1 > 0, sp2 > 0 else { return nil }
        // Ratio of HR to speed; speed is the inverse of sec/mi.
        let r1 = hr1 * sp1
        let r2 = hr2 * sp2
        guard r1 > 0 else { return nil }
        return (r2 - r1) / r1 * 100
    }

    /// Speed per beat — higher is more aerobically efficient. Scaled to
    /// land near 1.0 for a typical easy run so it reads like the figure
    /// runners are used to seeing.
    private var efficiencyFactor: Double? {
        guard avgHR > 0 else { return nil }
        let secPerMile = workout.pacePerMile * 60
        guard secPerMile > 0 else { return nil }
        let yardsPerMinute = 1760.0 / (secPerMile / 60.0)
        return yardsPerMinute / Double(avgHR)
    }

    /// Total ascent in feet, summed from the positive deltas in the
    /// elevation stream (metres). Nil when there's no stream.
    private var elevationGainFeet: Int? {
        guard elevationSamples.count > 1 else { return nil }
        var gain = 0.0
        for i in 1 ..< elevationSamples.count {
            let d = elevationSamples[i] - elevationSamples[i - 1]
            if d > 0 { gain += d }
        }
        guard gain > 0 else { return nil }
        return Int((gain * 3.28084).rounded())
    }

    /// Per-metric comparison rows. Each only renders if the matching
    /// `fourWeekAvg.*` field is populated; otherwise the row is skipped
    /// silently so we don't compare today's value against a fake baseline.
    /// The whole block is gated on `hasBaseline`, so the old "no baseline
    /// data yet" placeholder is gone — an empty section simply doesn't
    /// render.
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
