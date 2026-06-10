//
//  FitnessPredictorView_Rebrand.swift
//  RunningLog
//
//  Post Run Drip rebrand of FitnessPredictorView — view-only port from
//  the design at `Downloads/handoff 3/design/fitness-predictor-rebrand.jsx`
//  (latest: handoff 3, May 22). Service + models are unchanged.
//
//  Status: built, not yet wired. To go live, swap two callsites from
//  `FitnessPredictorView(...)` to `FitnessPredictorRebrandView(...)`:
//    • RunningLog/App/RunningLogApp.swift:245 (Route.fitnessPredictor)
//    • RunningLog/App/InsightsView.swift:214
//  Then the legacy `FitnessPredictorView.swift` can be deleted.
//
//  Design intent (from the design system README): "restraint as
//  foundation, intensity as accent." Editorial running magazine.
//  Warm paper. Black ink. One coral per visual cluster, used like
//  punctuation. Hairlines between cells, no card-in-card.
//
//  Differences vs the current production view, by section:
//   • Header     — toolbar/DripBackground stripped, inline plate strip
//   • Error      — italic between two hairlines, coral label only
//   • Anchor     — eyebrow + race in coral + display time + italic deck
//   • Races      — flat hairline list with 400/1K/mile split triples
//   • Training   — Paces ↔ Stimulus toggle, hairline rows
//   • Trend      — same canvas, card shell dropped
//   • Summary    — italic paragraph between hairlines
//   • Sources    — mono row, no chips
//   • Volume     — NEW (was TrainingEffortChart). Empty state only until
//                  minutes-by-zone-by-day is shaped — TODO.
//
//  Hard rule reminders:
//   • CLAUDE.md #7: predictions ship with range + confidence, never a
//     point. Marathon/half round to the minute. Already enforced in
//     `RacePredictionFormatting`; this view depends on that.
//   • Eyebrow type token in this codebase is `.dripEyebrow(n)` (SF Mono).
//     The handoff README says `.dripCaption(n)` — that's the legacy iOS
//     drift CLAUDE.md flags. We use `.dripEyebrow`.
//

import Supabase
import SwiftUI

// MARK: - FitnessPredictorRebrandView

struct FitnessPredictorRebrandView: View {
    @EnvironmentObject private var healthKitManager: HealthKitManager
    @Environment(VitalManager.self) private var vitalManager
    @Bindable var trainingViewModel: TrainingPlanViewModel
    @State private var predictor = FitnessPredictorService()

    var body: some View {
        ZStack {
            Color.drip.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    RebrandHeader(
                        isAnalyzing: predictor.isAnalyzing,
                        onRefresh: predict
                    )
                    .padding(.top, 12)

                    if let error = predictor.errorMessage {
                        RebrandErrorBanner(message: error)
                            .padding(.top, 10)
                    }

                    Group {
                        if let predictions = predictor.predictions {
                            // Body region (24pt horizontal gutter throughout)
                            VStack(alignment: .leading, spacing: 0) {

                                RebrandDateline()
                                    .padding(.top, 18)

                                editorialBreak

                                if let anchor = predictions.raceAnchor {
                                    RebrandAnchorStrip(anchor: anchor)
                                    editorialBreak
                                }

                                RebrandRaceList(races: predictions.races)

                                Text(racesFootnote)
                                    .font(.system(size: 11, design: .serif).italic())
                                    .foregroundStyle(Color.drip.textTertiary)
                                    .lineSpacing(2)
                                    .padding(.top, 10)

                                editorialBreak
                                    .padding(.top, 24)

                                if predictions.trainingPaces != nil || predictions.trainingStimulus != nil {
                                    RebrandTrainingSection(
                                        paces: predictions.trainingPaces,
                                        stimulus: predictions.trainingStimulus
                                    )

                                    editorialBreak
                                        .padding(.top, 24)
                                }

                                RebrandVolumeChart()

                                if predictor.snapshotHistory.count >= 2 {
                                    editorialBreak
                                        .padding(.top, 24)

                                    RebrandFitnessTrend(
                                        snapshots: predictor.snapshotHistory,
                                        changeFromPrevious: predictor.tenKChangeFromPrevious,
                                        previousDate: predictor.previousSnapshotDate
                                    )
                                }

                                if let summary = predictions.fitnessSummary {
                                    editorialBreak
                                        .padding(.top, 24)

                                    RebrandSummary(text: summary)
                                }

                                editorialBreak
                                    .padding(.top, 24)

                                RebrandDataSources(sources: predictions.dataSources)
                                    .padding(.top, 12)
                            }
                            .padding(.horizontal, 24)
                        } else if predictor.isAnalyzing {
                            RebrandAnalyzing()
                                .padding(.horizontal, 24)
                                .padding(.top, 60)
                        } else {
                            RebrandEmpty(onPredict: predict)
                                .padding(.horizontal, 24)
                                .padding(.top, 40)
                        }
                    }

                    Spacer().frame(height: 100)
                }
            }
        }
        .navigationBarHidden(true)
        .task {
            async let historyTask: () = predictor.fetchHistory()
            async let predictTask: () = loadPredictions()
            _ = await (historyTask, predictTask)
        }
    }

    private var editorialBreak: some View {
        EditorialRule()
            .padding(.vertical, 14)
    }

    private var racesFootnote: String {
        "Range is where the time lives 80% of the time, off today's fitness. " +
        "Marathon and half round to the minute — seconds at that distance are math, not signal."
    }

    private func predict() {
        Task { await loadPredictions() }
    }

    private func loadPredictions() async {
        _ = await healthKitManager.requestAuthorization()
        await predictor.predictFitness(plan: trainingViewModel.activePlan)
    }
}

// MARK: - Header

/// Inline plate strip + back / refresh row. Replaces both the toolbar
/// title block and the `DripBackground` from the legacy view. Refresh is
/// a small italic link (`Refresh ↻`) — not an SF Symbol button.
private struct RebrandHeader: View {
    let isAnalyzing: Bool
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PlateStrip(
                surface: "FITNESS PREDICTOR · FORWARD READ",
                fig: "FIG. 29"
            )
            .padding(.horizontal, 24)

            // Sub-strip with the dateline-style "TRENDS · MM.YYYY"
            HStack {
                Spacer()
                Text("TRENDS · \(monthYear)")
                    .font(.dripEyebrow(10))
                    .tracking(1.4)
                    .foregroundStyle(Color.drip.textTertiary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 2)

            // Back / Refresh row
            HStack(alignment: .firstTextBaseline) {
                Text("Back")
                    .font(.custom("CrimsonPro-Regular", size: 13).weight(.semibold))
                    .foregroundStyle(Color.drip.coral)

                Spacer()

                Button(action: onRefresh) {
                    HStack(spacing: 4) {
                        Text("Refresh")
                            .font(.system(size: 13, design: .serif).italic())
                            .foregroundStyle(Color.drip.coral)
                        if isAnalyzing {
                            ProgressView()
                                .tint(Color.drip.coral)
                                .scaleEffect(0.6)
                        } else {
                            Text("\u{21BB}") // ↻
                                .font(.system(size: 13))
                                .foregroundStyle(Color.drip.coral)
                        }
                    }
                }
                .disabled(isAnalyzing)
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)
        }
    }

    private var monthYear: String {
        let f = DateFormatter()
        f.dateFormat = "MM.yyyy"
        return f.string(from: Date())
    }
}

// MARK: - Dateline

/// "Today · May 22" eyebrow row + "Predicted times." display + italic deck.
/// New section — not present in the legacy view. Pure presentation, no data.
private struct RebrandDateline: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Today · \(today)")
                    .font(.dripEyebrow(11))
                    .tracking(1.3)
                    .foregroundStyle(Color.drip.coral)

                Spacer()

                Text("Reading ⟶ Trends")
                    .font(.dripEyebrow(11))
                    .tracking(1.3)
                    .foregroundStyle(Color.drip.textSecondary)
            }

            Text("Predicted times.")
                .font(.dripDisplay(32))
                .foregroundStyle(Color.drip.textPrimary)
                .padding(.top, 4)

            Text("Off today's fitness — what the next five distances look like, give or take a few seconds.")
                .font(.system(size: 14, design: .serif).italic())
                .foregroundStyle(Color.drip.textSecondary)
                .lineSpacing(3)
                .padding(.top, 6)
        }
    }

    private var today: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: Date())
    }
}

// MARK: - Anchor strip

private struct RebrandAnchorStrip: View {
    let anchor: RaceAnchorInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Anchored on")
                    .font(.dripEyebrow(11))
                    .tracking(1.3)
                    .foregroundStyle(Color.drip.textSecondary)

                Spacer()

                Text("\(anchor.weeksAgo)w ago")
                    .font(.dripEyebrow(9))
                    .tracking(1.0)
                    .foregroundStyle(Color.drip.textTertiary)
                    .monospacedDigit()
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(anchor.raceType.uppercased())
                    .font(.dripEyebrow(11))
                    .tracking(1.3)
                    .foregroundStyle(Color.drip.coral)

                Text(anchor.time)
                    .font(.dripStat(26))
                    .foregroundStyle(Color.drip.textPrimary)
                    .monospacedDigit()
            }

            Text("\(anchor.date) — your most recent timed effort. The forward read is rooted here.")
                .font(.system(size: 13, design: .serif).italic())
                .foregroundStyle(Color.drip.textSecondary)
                .lineSpacing(2)
        }
    }
}

// MARK: - Race list + row

private struct RebrandRaceList: View {
    let races: [RacePredictionItem]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(races.enumerated()), id: \.element.id) { idx, race in
                RebrandRaceRow(race: race, isLast: idx == races.count - 1)
            }
        }
    }
}

private struct RebrandRaceRow: View {
    let race: RacePredictionItem
    let isLast: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Head row: distance + display time + range
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(displayDistance)
                        .font(.dripEyebrow(11))
                        .tracking(1.3)
                        .foregroundStyle(Color.drip.textSecondary)

                    Text(RacePredictionFormatting.headline(for: race))
                        .font(.dripStat(headlineSize))
                        .foregroundStyle(Color.drip.textPrimary)
                        .monospacedDigit()
                }

                Spacer()

                if let range = RacePredictionFormatting.range(for: race) {
                    Text(range)
                        .font(.dripEyebrow(9))
                        .tracking(1.0)
                        .foregroundStyle(Color.drip.textTertiary)
                        .monospacedDigit()
                }
            }

            // Splits triple — 400m · per km · per mile, one coral marquee
            SplitTriple(
                pointSeconds: race.pointSeconds,
                distanceMeters: distanceMeters,
                marquee: marquee
            )
            .padding(.top, 10)
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(Color.drip.divider)
                    .frame(height: 1)
            }
        }
    }

    /// Big finish for the marathon row matches the JSX's `bigFinish: true`.
    private var headlineSize: CGFloat {
        race.distance.uppercased() == "MARATHON" ? 30 : 28
    }

    private var displayDistance: String {
        // Models store "5K" / "10K" / "HALF" / "MARATHON" / "MILE" already.
        race.distance.uppercased() == "HALF" ? "Half".uppercased() : race.distance.capitalizedKeepingAcronyms
    }

    /// Distance in meters used to derive splits. Mirrors the JSX hardcoded values.
    private var distanceMeters: Double {
        switch race.distance.uppercased() {
        case "MILE":     return 1609.344
        case "5K":       return 5_000
        case "10K":      return 10_000
        case "HALF":     return 21_097.5
        case "MARATHON": return 42_195
        default:         return 1609.344
        }
    }

    /// Which split is the coral marquee — copied from the JSX intent: a
    /// runner plans a mile by 400s, a 5K/10K by km, a half/marathon by mile.
    private var marquee: SplitMarquee {
        switch race.distance.uppercased() {
        case "MILE":              return .p400
        case "5K", "10K":         return .p1k
        case "HALF", "MARATHON":  return .pmi
        default:                  return .pmi
        }
    }
}

// MARK: - Split triple

private enum SplitMarquee { case p400, p1k, pmi }

/// Three-column split row: 400 m · per km · per mi. The marquee column
/// renders in coral; the other two are ink. Hairlines between columns.
/// Numbers are derived from a single source (`pointSeconds / distance_m`)
/// — not separate fields. Three unit conversions of the same pace.
private struct SplitTriple: View {
    let pointSeconds: Int
    let distanceMeters: Double
    let marquee: SplitMarquee

    var body: some View {
        let pacePerMeter = Double(pointSeconds) / distanceMeters
        let p400 = SplitsFormatter.mmss(seconds: pacePerMeter * 400)
        let p1k  = SplitsFormatter.mmss(seconds: pacePerMeter * 1_000)
        let pmi  = SplitsFormatter.mmss(seconds: pacePerMeter * 1_609.344)

        HStack(spacing: 0) {
            splitCell(label: "400 m", value: p400, isMarquee: marquee == .p400, leadingPad: 0)
            divider
            splitCell(label: "per km", value: p1k, isMarquee: marquee == .p1k, leadingPad: 12)
            divider
            splitCell(label: "per mi", value: pmi, isMarquee: marquee == .pmi, leadingPad: 12)
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.drip.divider)
                .frame(height: 1)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.drip.divider)
            .frame(width: 1)
            .padding(.vertical, 6)
    }

    private func splitCell(label: String, value: String, isMarquee: Bool, leadingPad: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.dripEyebrow(9))
                .tracking(1.0)
                .foregroundStyle(isMarquee ? Color.drip.coral : Color.drip.textTertiary)

            Text(value)
                .font(.dripStat(14))
                .foregroundStyle(isMarquee ? Color.drip.coral : Color.drip.textPrimary)
                .monospacedDigit()
        }
        .padding(.top, 10)
        .padding(.bottom, 6)
        .padding(.leading, leadingPad)
        .padding(.trailing, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Training section (Paces ↔ Stimulus)

private struct RebrandTrainingSection: View {
    let paces: TrainingPacesSummary?
    let stimulus: TrainingStimulusInfo?

    @State private var tab: Tab = .paces

    enum Tab { case paces, stimulus }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Tab eyebrow row with status pill on the right
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 14) {
                    tabLabel("Paces", isActive: tab == .paces)
                        .onTapGesture { withAnimation(.easeInOut(duration: 0.15)) { tab = .paces } }
                    tabLabel("Stimulus", isActive: tab == .stimulus)
                        .onTapGesture { withAnimation(.easeInOut(duration: 0.15)) { tab = .stimulus } }
                }

                Spacer()

                if let stimulus = stimulus {
                    statusPill(label: trainingStatus(stimulus))
                }
            }
            .padding(.bottom, 8)

            switch tab {
            case .paces:
                if let paces { RebrandPacesContent(paces: paces) }
            case .stimulus:
                if let stimulus { RebrandStimulusContent(stimulus: stimulus) }
            }
        }
        .onAppear {
            if paces != nil { tab = .paces }
            else if stimulus != nil { tab = .stimulus }
        }
    }

    private func tabLabel(_ text: String, isActive: Bool) -> some View {
        Text(text)
            .font(.dripEyebrow(11).weight(isActive ? .semibold : .medium))
            .tracking(1.3)
            .foregroundStyle(isActive ? Color.drip.textPrimary : Color.drip.textTertiary)
    }

    private func statusPill(label: String) -> some View {
        Text(label.uppercased())
            .font(.dripEyebrow(10))
            .tracking(1.2)
            .foregroundStyle(Color.drip.coral)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.drip.coralWash)
            .clipShape(Capsule())
    }

    /// Same logic as the legacy `TrainingCard.trainingStatus`.
    private func trainingStatus(_ s: TrainingStimulusInfo) -> String {
        if s.stimulusTrend > 1.2 && s.volumeTrend > 1.0 { return "Building" }
        if s.stimulusMinutes > 10 && s.volumeTrend >= 0.8 { return "Maintaining" }
        if s.stimulusMinutes > 0 || s.runsPerWeek >= 2 { return "Light" }
        return "Detraining"
    }
}

// MARK: - Paces content

private struct RebrandPacesContent: View {
    let paces: TrainingPacesSummary

    var body: some View {
        VStack(spacing: 0) {
            paceRow(id: .easy,       label: "Easy",      pace: paces.easyPace)
            paceRow(id: .long,       label: "Long Run",  pace: paces.longRunPace)
            paceRow(id: .marathon,   label: "Marathon",  pace: paces.marathonPace)
            paceRow(id: .threshold,  label: "Threshold", pace: paces.thresholdPace)
            paceRow(id: .interval,   label: "Interval",  pace: paces.intervalPace, isLast: true)
        }
    }

    private enum PaceID { case easy, long, marathon, threshold, interval }

    private func paceRow(id: PaceID, label: String, pace: String, isLast: Bool = false) -> some View {
        // Pace strings arrive as "7:10/mi" (or "7:10 – 7:38/mi" for ranged
        // aerobic zones). We anchor on the lower bound's per-mile seconds
        // and derive 400m / 1K from it. View-only derivation — see the
        // SplitsFormatter helper for the parser.
        let perMileSeconds = SplitsFormatter.parsePerMileSeconds(pace) ?? 0
        let p400 = SplitsFormatter.mmss(seconds: Double(perMileSeconds) * 400 / 1_609.344)
        let p1k  = SplitsFormatter.mmss(seconds: Double(perMileSeconds) * 1_000 / 1_609.344)
        let pmi  = SplitsFormatter.mmss(seconds: Double(perMileSeconds))

        return HStack(spacing: 12) {
            // 3px colored marker
            RoundedRectangle(cornerRadius: 1)
                .fill(markerColor(for: id))
                .frame(width: 3, height: 18)

            Text(label)
                .font(.dripBody(14))
                .foregroundStyle(Color.drip.textPrimary)

            Spacer()

            // Per-row split triple, mono, one coral marquee
            HStack(spacing: 8) {
                splitChip(value: p400, suffix: " / 400", isMarquee: marquee(for: id) == .p400)
                separator
                splitChip(value: p1k, suffix: " / km", isMarquee: marquee(for: id) == .p1k)
                separator
                splitChip(value: pmi, suffix: " / mi", isMarquee: marquee(for: id) == .pmi)
            }
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(Color.drip.divider).frame(height: 1)
            }
        }
    }

    private var separator: some View {
        Text("·").font(.dripStat(12)).foregroundStyle(Color.drip.textTertiary)
    }

    private func splitChip(value: String, suffix: String, isMarquee: Bool) -> some View {
        HStack(spacing: 0) {
            Text(value)
                .font(.dripStat(12))
                .foregroundStyle(isMarquee ? Color.drip.coral : Color.drip.textPrimary)
                .monospacedDigit()
            Text(suffix)
                .font(.dripStat(12).weight(.medium))
                .foregroundStyle(isMarquee ? Color.drip.coral : Color.drip.textSecondary)
        }
    }

    private func markerColor(for id: PaceID) -> Color {
        switch id {
        case .easy:      return Color.drip.energized
        case .long:      return Color.drip.positive
        case .marathon:  return Color.drip.coralLight
        case .threshold: return Color.drip.coral
        case .interval:  return Color.drip.tired
        }
    }

    private func marquee(for id: PaceID) -> SplitMarquee {
        // Mirrors the JSX: interval is planned by 400s, everything else by mile.
        id == .interval ? .p400 : .pmi
    }
}

// MARK: - Stimulus content

private struct RebrandStimulusContent: View {
    let stimulus: TrainingStimulusInfo

    var body: some View {
        HStack(spacing: 0) {
            stat(value: format(stimulus.weeklyMiles),       unit: "mi",  label: "per week",   trend: stimulus.volumeTrend)
            stat(value: format(stimulus.runsPerWeek),       unit: "ct",  label: "runs / wk",  trend: nil)
            stat(value: format(stimulus.stimulusMinutes),   unit: "min", label: "hard min",   trend: stimulus.stimulusTrend)
            stat(value: "\(stimulus.structuredSessions)",   unit: "ct",  label: "quality",    trend: nil)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.drip.divider).frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.drip.divider).frame(height: 1)
        }
    }

    private func format(_ d: Double) -> String { String(format: "%.0f", d) }

    private func stat(value: String, unit: String, label: String, trend: Double?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.dripStat(22))
                    .foregroundStyle(Color.drip.textPrimary)
                    .monospacedDigit()
                Text(unit)
                    .font(.dripStat(10))
                    .foregroundStyle(Color.drip.textSecondary)
                if let trend = trend {
                    Text(trendGlyph(trend))
                        .font(.dripStat(10))
                        .foregroundStyle(trendColor(trend))
                }
            }
            Text(label.uppercased())
                .font(.dripEyebrow(9))
                .tracking(1.0)
                .foregroundStyle(Color.drip.textTertiary)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func trendGlyph(_ t: Double) -> String {
        if t > 1.15 { return "↑" }
        if t < 0.85 { return "↓" }
        return "→"
    }

    private func trendColor(_ t: Double) -> Color {
        if t > 1.15 { return Color.drip.energized }
        if t < 0.85 { return Color.drip.coral }
        return Color.drip.textTertiary
    }
}

// MARK: - Training volume — empty state only (TODO: wire data)

/// New section vs the legacy view. Ships in empty state until the volume
/// data is shaped (need: minutes-by-zone per day for the chosen window).
/// The segmented controls render but are inert by design — building them
/// fully now would mean wiring a data path we don't have yet.
private struct RebrandVolumeChart: View {
    @State private var period: Period = .week

    enum Period: String, CaseIterable { case week, month, custom
        var label: String { rawValue.capitalized }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Eyebrow + period segmented
            HStack(alignment: .firstTextBaseline) {
                Text("TRAINING VOLUME")
                    .font(.dripEyebrow(11))
                    .tracking(1.3)
                    .foregroundStyle(Color.drip.textSecondary)

                Spacer()

                HStack(spacing: 4) {
                    ForEach(Period.allCases, id: \.self) { p in
                        Button {
                            period = p
                        } label: {
                            Text(p.label.uppercased())
                                .font(.dripEyebrow(10))
                                .tracking(1.0)
                                .foregroundStyle(period == p ? Color.drip.coral : Color.drip.textSecondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(period == p ? Color.drip.coralWash : Color.clear)
                                .clipShape(Capsule())
                        }
                    }
                }
            }

            // Zones / %MP toggle + date range
            HStack(alignment: .firstTextBaseline) {
                Text("ZONES")
                    .font(.dripEyebrow(10))
                    .tracking(1.0)
                    .foregroundStyle(Color.drip.coral)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.drip.coralWash)
                    .clipShape(Capsule())

                Text("% MP")
                    .font(.dripEyebrow(10))
                    .tracking(1.0)
                    .foregroundStyle(Color.drip.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)

                Spacer()

                HStack(spacing: 0) {
                    Text(dateRangeLabel)
                        .foregroundStyle(Color.drip.textSecondary)
                    Text(" · ")
                        .foregroundStyle(Color.drip.textTertiary)
                    Text("0.0 mi")
                        .foregroundStyle(Color.drip.textPrimary)
                }
                .font(.dripStat(11))
                .monospacedDigit()
            }
            .padding(.top, 10)

            // Empty state — italic centered between two hairlines.
            // TODO: replace with stacked bar chart once minutes-by-zone-by-day
            //       is available. See `outputs/five-pillars-and-weather-calc.md`
            //       for the planned data shape on Training Volume.
            VStack {
                Text("No data for this period. When you log a run, your minutes by zone land here.")
                    .font(.system(size: 14, design: .serif).italic())
                    .foregroundStyle(Color.drip.textSecondary)
                    .lineSpacing(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            }
            .overlay(alignment: .top) {
                Rectangle().fill(Color.drip.divider).frame(height: 1)
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.drip.divider).frame(height: 1)
            }
            .padding(.top, 18)
        }
    }

    private var dateRangeLabel: String {
        let cal = Calendar.current
        let today = Date()
        // Show "Mon DD – Mon DD" for the current week.
        guard let interval = cal.dateInterval(of: .weekOfYear, for: today) else {
            return ""
        }
        let start = interval.start
        let endInclusive = cal.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return "\(f.string(from: start)) – \(f.string(from: endInclusive))"
    }
}

// MARK: - Fitness trend (canvas, no card)

private struct RebrandFitnessTrend: View {
    let snapshots: [FitnessSnapshot]
    let changeFromPrevious: Int?
    let previousDate: Date?
    @State private var showAllDistances = false

    private var chronological: [FitnessSnapshot] {
        snapshots.reversed()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("FITNESS TREND")
                    .font(.dripEyebrow(11))
                    .tracking(1.3)
                    .foregroundStyle(Color.drip.textSecondary)

                Spacer()

                if let change = changeFromPrevious, let date = previousDate {
                    RebrandChangeIndicator(changeSeconds: change, comparedTo: date)
                }
            }

            // 10K is the canonical anchor — biggest by default, others reveal on tap.
            TrendSparkline(
                snapshots: chronological,
                keyPath: \.predicted10kSeconds,
                label: "10K",
                height: 72
            )

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showAllDistances.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text(showAllDistances ? "Hide distances" : "All distances")
                        .font(.dripEyebrow(11))
                        .tracking(1.0)
                        .foregroundStyle(Color.drip.textTertiary)
                    Text(showAllDistances ? "▴" : "▾")
                        .font(.dripEyebrow(11))
                        .foregroundStyle(Color.drip.textTertiary)
                }
            }

            if showAllDistances {
                VStack(spacing: 10) {
                    TrendSparkline(snapshots: chronological, keyPath: \.predictedMileSeconds, label: "MILE", height: 44)
                    TrendSparkline(snapshots: chronological, keyPath: \.predicted5kSeconds, label: "5K", height: 44)
                    TrendSparkline(snapshots: chronological, keyPath: \.predictedHalfSeconds, label: "HALF", height: 44)
                    TrendSparkline(snapshots: chronological, keyPath: \.predictedMarathonSeconds, label: "MARATHON", height: 44)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

private struct RebrandChangeIndicator: View {
    let changeSeconds: Int
    let comparedTo: Date

    private var isImproving: Bool { changeSeconds < 0 }
    private var absChange: Int { abs(changeSeconds) }

    private var changeText: String {
        let mins = absChange / 60
        let secs = absChange % 60
        let arrow = isImproving ? "↓" : "↑"
        return mins > 0 ? "\(arrow) \(mins)m \(secs)s" : "\(arrow) \(secs)s"
    }

    private var relativeDate: String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: comparedTo, relativeTo: Date())
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(changeText)
                .font(.dripStat(11))
                .monospacedDigit()
            Text("from \(relativeDate)")
                .font(.dripEyebrow(9))
                .tracking(1.0)
        }
        .foregroundStyle(isImproving ? Color.drip.success : Color.drip.coral)
    }
}

// MARK: - Summary

private struct RebrandSummary: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 14, design: .serif).italic())
            .foregroundStyle(Color.drip.textPrimary)
            .lineSpacing(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 14)
            .overlay(alignment: .top) {
                Rectangle().fill(Color.drip.divider).frame(height: 1)
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.drip.divider).frame(height: 1)
            }
    }
}

// MARK: - Data sources

private struct RebrandDataSources: View {
    let sources: DataSources

    var body: some View {
        HStack(spacing: 0) {
            cell(value: "\(sources.workoutCount)",     label: "workouts")
            cell(value: "\(sources.voiceLogCount)",    label: "voice logs")
            cell(value: "\(sources.hardEffortCount)",  label: "hard efforts")
            cell(value: sources.confidence,            label: "confidence")
        }
    }

    private func cell(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.dripStat(13))
                .foregroundStyle(Color.drip.textPrimary)
                .monospacedDigit()
            Text(label.uppercased())
                .font(.dripEyebrow(9))
                .tracking(1.0)
                .foregroundStyle(Color.drip.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Error banner

/// Quiet italic between two hairlines, coral label only — never a fill.
/// Per the design system: no chunky banners, no exclamation icons.
private struct RebrandErrorBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text("Network · Offline")
                .font(.dripEyebrow(10))
                .tracking(1.2)
                .foregroundStyle(Color.drip.coral)

            Text(message)
                .font(.system(size: 13, design: .serif).italic())
                .foregroundStyle(Color.drip.textSecondary)
                .lineSpacing(2)

            Spacer()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 24)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.drip.divider).frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.drip.divider).frame(height: 1)
        }
    }
}

// MARK: - Analyzing / Empty states

private struct RebrandAnalyzing: View {
    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(Color.drip.coral)
                .scaleEffect(1.1)
            Text("Analyzing your training…")
                .font(.system(size: 14, design: .serif).italic())
                .foregroundStyle(Color.drip.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

private struct RebrandEmpty: View {
    let onPredict: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Predicted times")
                .font(.dripDisplay(28))
                .foregroundStyle(Color.drip.textPrimary)

            Text("A forward read of the next five distances. We need a couple of runs and a voice log to root the read.")
                .font(.system(size: 14, design: .serif).italic())
                .foregroundStyle(Color.drip.textSecondary)
                .lineSpacing(3)
                .padding(.top, 6)

            Button(action: onPredict) {
                Text("Get Predictions")
                    .font(.dripLabel(15))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.drip.coral)
                    .clipShape(Capsule())
            }
            .padding(.top, 20)
        }
    }
}

// MARK: - TrendSparkline (private copy)
//
// `TrendSparkline` is declared `private` in the legacy FitnessPredictorView.swift,
// so we can't reference it across files. Swift `private` at the top level is
// file-scoped, so two files can each declare a same-named private type without
// conflict. Once the legacy view is deleted, this copy becomes canonical.

private struct TrendSparkline: View {
    let snapshots: [FitnessSnapshot]
    let keyPath: KeyPath<FitnessSnapshot, Int>
    let label: String
    var height: CGFloat = 80

    private var latestValue: Int {
        snapshots.last.map { $0[keyPath: keyPath] } ?? 0
    }

    private var formattedTime: String {
        let totalSecs = latestValue
        let hours = totalSecs / 3600
        let mins = (totalSecs % 3600) / 60
        let secs = totalSecs % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, mins, secs)
        }
        return String(format: "%d:%02d", mins, secs)
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.dripEyebrow(10))
                    .tracking(1.0)
                    .foregroundStyle(Color.drip.textTertiary)

                Text(formattedTime)
                    .font(.dripStat(height > 60 ? 16 : 13))
                    .foregroundStyle(Color.drip.textPrimary)
                    .monospacedDigit()
            }
            .frame(width: 70, alignment: .leading)

            GeometryReader { geo in
                let values = snapshots.map { Double($0[keyPath: keyPath]) }
                let minVal = (values.min() ?? 0) * 0.995
                let maxVal = (values.max() ?? 1) * 1.005
                let range = max(maxVal - minVal, 1)

                ZStack {
                    Path { path in
                        guard values.count >= 2 else { return }
                        let stepX = geo.size.width / CGFloat(values.count - 1)
                        path.move(to: CGPoint(x: 0, y: geo.size.height))
                        for (i, val) in values.enumerated() {
                            let y = (val - minVal) / range * Double(geo.size.height)
                            path.addLine(to: CGPoint(x: CGFloat(i) * stepX, y: y))
                        }
                        path.addLine(to: CGPoint(x: CGFloat(values.count - 1) * stepX, y: geo.size.height))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [Color.drip.coral.opacity(0.25), Color.drip.coral.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    Path { path in
                        guard values.count >= 2 else { return }
                        let stepX = geo.size.width / CGFloat(values.count - 1)
                        for (i, val) in values.enumerated() {
                            let y = (val - minVal) / range * Double(geo.size.height)
                            if i == 0 {
                                path.move(to: CGPoint(x: 0, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: CGFloat(i) * stepX, y: y))
                            }
                        }
                    }
                    .stroke(Color.drip.coral, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                    if let lastVal = values.last {
                        let x = geo.size.width
                        let y = (lastVal - minVal) / range * Double(geo.size.height)
                        Circle()
                            .fill(Color.drip.coral)
                            .frame(width: 6, height: 6)
                            .position(x: x, y: y)
                    }
                }
            }
            .frame(height: height)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - SplitsFormatter

/// View-only helper. The models expose `pointSeconds` per race and a
/// per-mile string per training pace; everything else (400m, 1K) is a
/// unit conversion of that one value. If the service later exposes raw
/// `secondsPerMile` on `TrainingPacesSummary`, this parser collapses to
/// a pass-through and we delete the regex.
enum SplitsFormatter {
    /// "M:SS" formatter, rounded to the nearest second.
    static func mmss(seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    /// Parse "7:10/mi" (or "7:10 – 7:38/mi" range) into per-mile seconds.
    /// For ranges we anchor on the lower bound — that's the marquee value
    /// a runner plans by. Returns `nil` on malformed input.
    static func parsePerMileSeconds(_ s: String) -> Int? {
        // Take everything before the first " – " or "/" and parse it as M:SS.
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        let lower: String = {
            if let dash = trimmed.range(of: " – ") {
                return String(trimmed[..<dash.lowerBound])
            }
            if let slash = trimmed.range(of: "/") {
                return String(trimmed[..<slash.lowerBound])
            }
            return trimmed
        }()
        let parts = lower.split(separator: ":")
        guard parts.count == 2,
              let m = Int(parts[0]),
              let sec = Int(parts[1]) else { return nil }
        return m * 60 + sec
    }
}

// MARK: - String helper

private extension String {
    /// "5K" / "10K" / "HALF" / "MARATHON" / "MILE" → presentation form.
    /// We want "Mile" / "5K" / "10K" / "Half" / "Marathon" in body, but
    /// the labels in this view render through .dripEyebrow + .tracking
    /// uppercase, so this is just a defensive normalizer.
    var capitalizedKeepingAcronyms: String {
        let upper = self.uppercased()
        switch upper {
        case "5K", "10K": return upper
        case "MILE":      return "Mile".uppercased()
        case "HALF":      return "Half".uppercased()
        case "MARATHON":  return "Marathon".uppercased()
        default:          return upper
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        FitnessPredictorRebrandView(trainingViewModel: TrainingPlanViewModel())
    }
}
