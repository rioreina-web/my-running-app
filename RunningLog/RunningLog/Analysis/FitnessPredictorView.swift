//
//  FitnessPredictorView.swift
//  RunningLog
//
//  AI-powered race time predictions based on training data.
//
//  Editorial port — Post Run Drip rebrand. The chunky `.toolbar` nav,
//  `DripBackground`, and card-in-card chrome are gone. Plate strip header,
//  hairline-row tables, eyebrows for section labels, italic prose for
//  network errors and definitions. One coral per visual cluster — race
//  names + the marquee pace, never the whole row.
//
//  Service + models stay untouched.
//

import Supabase
import SwiftUI

// MARK: - File-private date helper
//
// Plate strip wants "TRENDS · 05.2026" — mono uppercase.

private extension Date {
    var editorialMonthYearString: String {
        let f = DateFormatter()
        f.dateFormat = "MM.yyyy"
        return f.string(from: self)
    }
}

// MARK: - FitnessPredictorView

struct FitnessPredictorView: View {
    @EnvironmentObject private var healthKitManager: HealthKitManager
    @Environment(VitalManager.self) private var vitalManager
    @Bindable var trainingViewModel: TrainingPlanViewModel
    @State private var predictor = FitnessPredictorService()

    var body: some View {
        ZStack {
            Color.drip.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {

                    // ── Plate strip ──────────────────────────────────────
                    DripPlateStrip(
                        leadingTop: "FITNESS PREDICTOR",
                        leadingBottom: "FORWARD READ",
                        trailingTop: "FIG. 29",
                        trailingBottom: "TRENDS · " + Date().editorialMonthYearString
                    )

                    // ── Refresh affordance ───────────────────────────────
                    HStack {
                        Spacer()
                        Button(action: predict) {
                            HStack(spacing: 4) {
                                Text(predictor.isAnalyzing ? "REFRESHING" : "REFRESH")
                                    .font(.dripCaption(10))
                                    .tracking(1.4)
                                Image(systemName: predictor.isAnalyzing
                                      ? "arrow.triangle.2.circlepath"
                                      : "arrow.clockwise")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .foregroundStyle(Color.drip.coral)
                        }
                        .buttonStyle(.plain)
                        .disabled(predictor.isAnalyzing)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 10)

                    // ── Top hairline ─────────────────────────────────────
                    DripHairline().padding(.horizontal, 24).padding(.top, 14)

                    // ── Network error (quiet, italic, between hairlines) ─
                    if let error = predictor.errorMessage {
                        offlineNotice(error)
                    }

                    if let predictions = predictor.predictions {
                        // ── Dateline ─────────────────────────────────────
                        dateline

                        // ── Anchor ───────────────────────────────────────
                        if let anchor = predictions.raceAnchor {
                            anchorStrip(anchor)
                                .padding(.horizontal, 24)
                                .padding(.top, 22)
                        }

                        editorialRule()

                        // ── 5 predicted times ────────────────────────────
                        racePredictions(predictions.races)

                        // Range/definition footnote
                        Text("Range is where the time lives ~80% of the time, off today's fitness. Marathon and half round to the minute — seconds at that distance are math, not signal.")
                            .font(.dripBody(11).italic())
                            .foregroundStyle(Color.drip.textTertiary)
                            .lineSpacing(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 24)
                            .padding(.top, 10)

                        editorialRule()

                        // ── Training paces / stimulus tabs ───────────────
                        if predictions.trainingPaces != nil || predictions.trainingStimulus != nil {
                            TrainingSection(
                                paces: predictions.trainingPaces,
                                stimulus: predictions.trainingStimulus
                            )
                            .padding(.horizontal, 24)
                            .padding(.top, 22)

                            editorialRule()
                        }

                        // ── Training volume by zone (keeps its canvas) ──
                        TrainingEffortChart(
                            workouts: vitalManager.recentWorkouts,
                            equivalentPaces: EquivalentPaces(
                                raceDistance: .tenK,
                                goalTimeSeconds: Int(predictions.estimated10kPaceSeconds * 6.21371)
                            )
                        )
                        .padding(.horizontal, 24)
                        .padding(.top, 22)

                        // ── Fitness trend (keep canvas, drop card) ──────
                        if predictor.snapshotHistory.count >= 2 {
                            editorialRule()
                            FitnessTrendSection(
                                snapshots: predictor.snapshotHistory,
                                changeFromPrevious: predictor.tenKChangeFromPrevious,
                                previousDate: predictor.previousSnapshotDate
                            )
                            .padding(.horizontal, 24)
                            .padding(.top, 22)
                        }

                        // ── Fitness summary (italic, between hairlines) ─
                        if let summary = predictions.fitnessSummary {
                            editorialRule()
                            fitnessSummary(summary)
                        }

                        // ── Data sources (mono row, no chips) ───────────
                        editorialRule()
                        dataSourcesRow(predictions.dataSources)
                            .padding(.horizontal, 24)
                            .padding(.top, 18)

                    } else if predictor.isAnalyzing {
                        analyzingState
                    } else {
                        emptyState
                    }

                    Spacer().frame(height: 64)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.drip.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task {
            async let historyTask: () = predictor.fetchHistory()
            async let predictTask: () = loadPredictions()
            _ = await (historyTask, predictTask)
        }
    }

    private func predict() {
        Task { await loadPredictions() }
    }

    private func loadPredictions() async {
        _ = await healthKitManager.requestAuthorization()
        await predictor.predictFitness(plan: trainingViewModel.activePlan)
    }

    // MARK: Section builders

    private var dateline: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                DripEyebrow(text: "TODAY · " + Date().editorialTodayString, coral: true)
                Spacer()
                DripEyebrow(text: "READING ⟶ TRENDS")
            }
            Text("Predicted times.")
                .font(.dripDisplay(32))
                .foregroundStyle(Color.drip.textPrimary)
                .padding(.top, 2)
            Text("Off today's fitness — what the next five distances look like, give or take a few seconds.")
                .font(.dripBody(14).italic())
                .foregroundStyle(Color.drip.textSecondary)
                .lineSpacing(2)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 22)
    }

    private func anchorStrip(_ a: RaceAnchorInfo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                DripEyebrow(text: "ANCHORED ON")
                Spacer()
                Text("\(a.weeksAgo)W AGO")
                    .font(.dripCaption(9))
                    .tracking(1.2)
                    .foregroundStyle(Color.drip.textTertiary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(a.raceType.uppercased())
                    .font(.dripCaption(10))
                    .tracking(1.4)
                    .foregroundStyle(Color.drip.coral)
                Text(a.time)
                    .font(.dripCaption(26))
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(Color.drip.textPrimary)
            }
            .padding(.top, 4)
            Text(a.date + " — your most recent timed effort. The forward read is rooted here.")
                .font(.dripBody(13).italic())
                .foregroundStyle(Color.drip.textSecondary)
                .lineSpacing(2)
                .padding(.top, 2)
        }
    }

    private func racePredictions(_ races: [RacePredictionItem]) -> some View {
        VStack(spacing: 0) {
            DripHairline()
            ForEach(Array(races.enumerated()), id: \.element.id) { idx, race in
                raceRow(race, isLast: idx == races.count - 1)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
    }

    private func raceRow(_ race: RacePredictionItem, isLast: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(race.distance.uppercased())
                        .font(.dripCaption(10))
                        .tracking(1.4)
                        .foregroundStyle(Color.drip.coral)
                    Text(RacePredictionFormatting.headline(for: race))
                        .font(.dripCaption(isMarathonOrHalf(race) ? 30 : 28))
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .foregroundStyle(Color.drip.textPrimary)
                }
                Spacer()
                if let range = RacePredictionFormatting.range(for: race) {
                    Text(range)
                        .font(.dripCaption(11))
                        .monospacedDigit()
                        .foregroundStyle(Color.drip.textTertiary)
                }
            }
            // Single per-mile pace (model only carries one). Marquee coral.
            HStack {
                Spacer()
                Text(race.pace)
                    .font(.dripCaption(13))
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(Color.drip.coral)
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            if !isLast { DripHairline() }
        }
    }

    private func isMarathonOrHalf(_ r: RacePredictionItem) -> Bool {
        let d = r.distance.uppercased()
        return d == "MARATHON" || d == "HALF"
    }

    private func offlineNotice(_ message: String) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                DripEyebrow(text: "NETWORK · OFFLINE", coral: true)
                Text(message)
                    .font(.dripBody(13).italic())
                    .foregroundStyle(Color.drip.textSecondary)
                    .lineSpacing(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 24)
            .overlay(alignment: .top) {
                DripHairline().padding(.horizontal, 24)
            }
            .overlay(alignment: .bottom) {
                DripHairline().padding(.horizontal, 24)
            }
        }
        .padding(.top, 10)
    }

    private func fitnessSummary(_ summary: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            DripEyebrow(text: "AI ANALYSIS")
            Text(summary)
                .font(.dripBody(14).italic())
                .foregroundStyle(Color.drip.textPrimary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 22)
    }

    private func dataSourcesRow(_ s: DataSources) -> some View {
        HStack(spacing: 0) {
            dataSourceCell("\(s.workoutCount)", "WORKOUTS")
            dataSourceCell("\(s.voiceLogCount)", "VOICE LOGS")
            dataSourceCell("\(s.hardEffortCount)", "HARD EFFORTS")
            dataSourceCell(s.confidence.uppercased(), "CONFIDENCE")
        }
        .overlay(alignment: .top) { DripHairline() }
        .overlay(alignment: .bottom) { DripHairline() }
    }

    private func dataSourceCell(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.dripCaption(13))
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(Color.drip.textPrimary)
            Text(label)
                .font(.dripCaption(9))
                .tracking(1.2)
                .foregroundStyle(Color.drip.textTertiary)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
    }

    private var analyzingState: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(Color.drip.coral)
            Text("Analyzing your training…")
                .font(.dripBody(14).italic())
                .foregroundStyle(Color.drip.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            DripEyebrow(text: "FORWARD READ · NOT YET RUN", coral: true)
            Text("No prediction yet.")
                .font(.dripDisplay(28))
                .foregroundStyle(Color.drip.textPrimary)
            Text("Log a few runs and a voice note — the model needs something to work with before it'll project forward.")
                .font(.dripBody(14).italic())
                .foregroundStyle(Color.drip.textSecondary)
                .lineSpacing(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                Spacer()
                DripTextLink(title: "Run the read →", action: predict)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 32)
    }
}

// MARK: - Editorial rule helper

private func editorialRule() -> some View {
    DripHairline()
        .padding(.horizontal, 24)
        .padding(.top, 24)
}

// MARK: - Date helper for dateline

private extension Date {
    var editorialTodayString: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: self).uppercased()
    }
}

// MARK: - Race prediction formatting
//
// CLAUDE.md hard rule #7: predictions ship with range + confidence, never a
// single point. For marathon and half we round to whole minutes (seconds are
// math artifact, not signal). For shorter distances we keep MM:SS — at 5K /
// 10K / mile, seconds carry real fitness information.

enum RacePredictionFormatting {
    static func headline(for race: RacePredictionItem) -> String {
        let d = race.distance.uppercased()
        if d == "MARATHON" || d == "HALF" {
            return roundedToMinutes(race.pointSeconds)
        }
        return race.time
    }

    static func range(for race: RacePredictionItem) -> String? {
        guard race.rangeSeconds > 0, race.pointSeconds > 0 else { return nil }
        let low = max(0, race.pointSeconds - race.rangeSeconds)
        let high = race.pointSeconds + race.rangeSeconds
        let d = race.distance.uppercased()
        if d == "MARATHON" || d == "HALF" {
            return "\(roundedToMinutes(low)) – \(roundedToMinutes(high))"
        }
        return "\(formatMMSS(low)) – \(formatMMSS(high))"
    }

    private static func roundedToMinutes(_ seconds: Int) -> String {
        let totalMinutes = Int(((Double(seconds) + 30) / 60.0).rounded(.down))
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        if h > 0 {
            return "\(h):\(String(format: "%02d", m))"
        }
        return "\(m)"
    }

    private static func formatMMSS(_ seconds: Int) -> String {
        let h = seconds / 3600
        let rem = seconds % 3600
        let m = rem / 60
        let s = rem % 60
        if h > 0 {
            return "\(h):\(String(format: "%02d", m)):\(String(format: "%02d", s))"
        }
        return "\(m):\(String(format: "%02d", s))"
    }
}

// MARK: - Training section (paces / stimulus tabs, no card shell)

private struct TrainingSection: View {
    let paces: TrainingPacesSummary?
    let stimulus: TrainingStimulusInfo?

    @State private var tab: TrainingTab = .paces

    enum TrainingTab: String, CaseIterable {
        case paces = "PACES"
        case stimulus = "STIMULUS"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Eyebrow row: tab toggle + status pill
            HStack(spacing: 14) {
                ForEach(TrainingTab.allCases, id: \.rawValue) { t in
                    let available = (t == .paces && paces != nil) || (t == .stimulus && stimulus != nil)
                    if available {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { tab = t }
                        } label: {
                            Text(t.rawValue)
                                .font(.dripCaption(10))
                                .tracking(1.4)
                                .foregroundStyle(tab == t ? Color.drip.textPrimary : Color.drip.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Spacer()
                if let stimulus = stimulus {
                    Text(trainingStatus(stimulus).uppercased())
                        .font(.dripCaption(10))
                        .tracking(1.4)
                        .foregroundStyle(Color.drip.coral)
                }
            }

            switch tab {
            case .paces:
                if let paces = paces { pacesContent(paces) }
            case .stimulus:
                if let stimulus = stimulus { stimulusContent(stimulus) }
            }
        }
        .onAppear {
            if paces != nil { tab = .paces }
            else if stimulus != nil { tab = .stimulus }
        }
    }

    private func pacesContent(_ paces: TrainingPacesSummary) -> some View {
        VStack(spacing: 0) {
            DripHairline()
            paceRow("Easy",      paces.easyPace,      Color.drip.energized)
            DripHairline()
            paceRow("Long Run",  paces.longRunPace,   Color.drip.positive)
            DripHairline()
            paceRow("Marathon",  paces.marathonPace,  Color.drip.coral.opacity(0.7))
            DripHairline()
            paceRow("Threshold", paces.thresholdPace, Color.drip.coral)
            DripHairline()
            paceRow("Interval",  paces.intervalPace,  Color.drip.tired)
            DripHairline()
        }
        .padding(.top, 4)
    }

    private func paceRow(_ label: String, _ pace: String, _ marker: Color) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 1)
                .fill(marker)
                .frame(width: 3, height: 18)
            Text(label)
                .font(.dripBody(14))
                .foregroundStyle(Color.drip.textPrimary)
            Spacer()
            Text(pace)
                .font(.dripCaption(12))
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(Color.drip.textPrimary)
        }
        .padding(.vertical, 12)
    }

    private func stimulusContent(_ s: TrainingStimulusInfo) -> some View {
        HStack(spacing: 0) {
            stimulusCell(String(format: "%.0f", s.weeklyMiles),       unit: "mi",  label: "PER WEEK",  trend: s.volumeTrend)
            stimulusCell(String(format: "%.0f", s.runsPerWeek),       unit: "ct",  label: "RUNS / WK", trend: nil)
            stimulusCell(String(format: "%.0f", s.stimulusMinutes),   unit: "min", label: "HARD MIN",  trend: s.stimulusTrend)
            stimulusCell("\(s.structuredSessions)",                   unit: "ct",  label: "QUALITY",   trend: nil)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .top) { DripHairline() }
        .overlay(alignment: .bottom) { DripHairline() }
    }

    private func stimulusCell(_ value: String, unit: String, label: String, trend: Double?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.dripCaption(22))
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(Color.drip.textPrimary)
                Text(unit)
                    .font(.dripCaption(10))
                    .foregroundStyle(Color.drip.textSecondary)
                if let trend = trend, trend != 0 {
                    Text(trendArrow(trend))
                        .font(.dripCaption(10))
                        .fontWeight(.semibold)
                        .foregroundStyle(trendColor(trend))
                }
            }
            Text(label)
                .font(.dripCaption(9))
                .tracking(1.2)
                .foregroundStyle(Color.drip.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func trainingStatus(_ s: TrainingStimulusInfo) -> String {
        if s.stimulusTrend > 1.2 && s.volumeTrend > 1.0 { return "Building" }
        if s.stimulusMinutes > 10 && s.volumeTrend >= 0.8 { return "Maintaining" }
        if s.stimulusMinutes > 0 || s.runsPerWeek >= 2 { return "Light" }
        return "Detraining"
    }

    private func trendArrow(_ t: Double) -> String {
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

// MARK: - Fitness trend (keep sparkline canvas, drop card)

private struct FitnessTrendSection: View {
    let snapshots: [FitnessSnapshot]
    let changeFromPrevious: Int?
    let previousDate: Date?
    @State private var showAllDistances = false

    private var chronological: [FitnessSnapshot] { snapshots.reversed() }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                DripEyebrow(text: "FITNESS TREND")
                Spacer()
                if let change = changeFromPrevious, let date = previousDate {
                    InlineChangeReadout(changeSeconds: change, comparedTo: date)
                }
            }

            TrendSparkline(
                snapshots: chronological,
                keyPath: \.predicted10kSeconds,
                label: "10K",
                height: 72
            )

            Button {
                withAnimation(.easeInOut(duration: 0.25)) { showAllDistances.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text(showAllDistances ? "HIDE DISTANCES" : "ALL DISTANCES")
                        .font(.dripCaption(10))
                        .tracking(1.4)
                        .foregroundStyle(Color.drip.coral)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.drip.coral)
                        .rotationEffect(.degrees(showAllDistances ? 180 : 0))
                }
            }
            .buttonStyle(.plain)

            if showAllDistances {
                VStack(spacing: 10) {
                    TrendSparkline(snapshots: chronological, keyPath: \.predictedMileSeconds,     label: "MILE",     height: 44)
                    TrendSparkline(snapshots: chronological, keyPath: \.predicted5kSeconds,       label: "5K",       height: 44)
                    TrendSparkline(snapshots: chronological, keyPath: \.predictedHalfSeconds,     label: "HALF",     height: 44)
                    TrendSparkline(snapshots: chronological, keyPath: \.predictedMarathonSeconds, label: "MARATHON", height: 44)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

private struct InlineChangeReadout: View {
    let changeSeconds: Int
    let comparedTo: Date

    private var isImproving: Bool { changeSeconds < 0 }
    private var absChange: Int { abs(changeSeconds) }

    private var changeText: String {
        let mins = absChange / 60
        let secs = absChange % 60
        let arrow = isImproving ? "↓" : "↑"
        if mins > 0 { return "\(arrow) \(mins)m \(secs)s" }
        return "\(arrow) \(secs)s"
    }

    private var relativeDate: String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: comparedTo, relativeTo: Date()).uppercased()
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(changeText)
                .font(.dripCaption(11))
                .fontWeight(.semibold)
                .monospacedDigit()
            Text("FROM " + relativeDate)
                .font(.dripCaption(9))
                .tracking(1.2)
                .foregroundStyle(Color.drip.textTertiary)
        }
        .foregroundStyle(isImproving ? Color.drip.energized : Color.drip.coral)
    }
}

// MARK: - Sparkline (canvas kept; spec said "keep canvas, drop card shell")

private struct TrendSparkline: View {
    let snapshots: [FitnessSnapshot]
    let keyPath: KeyPath<FitnessSnapshot, Int>
    let label: String
    var height: CGFloat = 80

    private var latestValue: Int { snapshots.last.map { $0[keyPath: keyPath] } ?? 0 }

    private var formattedTime: String {
        let total = latestValue
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.dripCaption(10))
                    .tracking(1.4)
                    .foregroundStyle(Color.drip.textTertiary)
                Text(formattedTime)
                    .font(.dripCaption(height > 60 ? 16 : 13))
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(Color.drip.textPrimary)
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
                            colors: [Color.drip.coral.opacity(0.22), Color.drip.coral.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    Path { path in
                        guard values.count >= 2 else { return }
                        let stepX = geo.size.width / CGFloat(values.count - 1)
                        for (i, val) in values.enumerated() {
                            let y = (val - minVal) / range * Double(geo.size.height)
                            if i == 0 { path.move(to: CGPoint(x: 0, y: y)) }
                            else { path.addLine(to: CGPoint(x: CGFloat(i) * stepX, y: y)) }
                        }
                    }
                    .stroke(Color.drip.coral, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

                    if let last = values.last {
                        let x = geo.size.width
                        let y = (last - minVal) / range * Double(geo.size.height)
                        Circle()
                            .fill(Color.drip.coral)
                            .frame(width: 5, height: 5)
                            .position(x: x, y: y)
                    }
                }
            }
            .frame(height: height)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        FitnessPredictorView(trainingViewModel: TrainingPlanViewModel())
    }
}
