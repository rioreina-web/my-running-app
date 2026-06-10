//
//  TrendsTabView.swift
//  RunningLog
//
//  Trends — "the 5-second view." Built from the App.jsx TrendsPlaceholder
//  mockup (design-system/ui_kits/ios_app/App.jsx).
//
//      PlateStrip · TRENDS · v1 ANALYTICS SURFACE · FIG. 1
//      OPENING FIGURE
//      The 5-second view.
//
//      ┌────────────────────┬────────────────────┐
//      │ VOLUME · 7D        │ FITNESS            │
//      │ 47.2 MI            │ 3:08 — 3:14        │
//      │ +8% vs 4-wk avg    │ HIGH CONFIDENCE    │
//      ├────────────────────┼────────────────────┤
//      │ LOAD · ACWR        │ ACTIVE ACHES       │
//      │ 1.18 ratio         │ 2 tracking         │
//      │ PRODUCTIVE         │ —                  │
//      └────────────────────┴────────────────────┘
//
//      FITNESS · 12-WEEK PROGRESSION       VIEW DETAIL ↗
//      <line chart of weekly mileage>
//                                        GOAL  3:10
//
//      LOAD · WEEKLY VOLUME × ACWR
//      <13 bars, current week ink, others ink-3>
//                                        ACWR 1.18
//
//      DRILL DOWN
//      ↗ Open last workout — May 7 · 5.01 mi
//      ↗ Active aches — 2 tracking
//
//  Two intentional deviations from the placeholder JSX, called out in
//  README of the redesign:
//
//   1. FITNESS tile shows a RANGE + confidence (`3:08 — 3:14 · HIGH
//      CONFIDENCE`) not a single point estimate. Hard rule #7 in
//      `CLAUDE.md` — *"Predictions ship with range + confidence, never a
//      single point."* The JSX placeholder shows `3:14 FULL` which
//      violates the rule; we honor the rule.
//
//   2. The "INJURY RISK 2.4 / 10" tile becomes an "ACTIVE ACHES" count
//      tile. Per the Niggles rules in CLAUDE.md — *"Surface, never
//      interpret. The system reports what was said and where. It never
//      says what that means … never assess severity itself."* A 0-10
//      risk score is severity assessment. The honest surface is a count
//      of currently-tracked aches, deferring interpretation to the
//      coach.
//

import Supabase
import os
import SwiftUI

struct TrendsTabView: View {

    // MARK: - State

    @State private var fitnessService = FitnessPredictorService()
    @State private var injuryService = InjuryService()
    @State private var trainingPlanVM = TrainingPlanViewModel()
    @State private var recentWorkouts: [RunningWorkout] = []
    @State private var athleteState: TrendsAthleteState?

    @State private var selectedLogEntry: TrainingLog?
    @State private var showInjuries = false

    /// Pushes the reconstructed load/intensity audit (pace zones, ACWR
    /// gauge, 28-day heatmap, weekly bars, load split). Fires from the
    /// fitness section's "VIEW DETAIL ↗". The existing AnalysisView
    /// (monthly LLM narrative) is a separate surface, sidebar-reachable.
    @State private var showAnalysis = false

    /// Pushes the existing FitnessPredictorView for the full race-time
    /// breakdown. Fires from a tap on the FITNESS stat tile.
    @State private var showFitnessPredictor = false

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PlateStrip(surface: "TRENDS  ·  v1 ANALYTICS SURFACE", fig: "FIG. 1")

                Spacer().frame(height: 24)

                openingFigure
                Spacer().frame(height: 18)

                statTileGrid
                Spacer().frame(height: 28)

                EditorialRule()
                Spacer().frame(height: 16)

                fitnessProgressionSection
                Spacer().frame(height: 28)

                EditorialRule()
                Spacer().frame(height: 16)

                weeklyVolumeAcwrSection
                Spacer().frame(height: 28)

                EditorialRule()
                Spacer().frame(height: 16)

                drillDownSection

                Spacer().frame(height: 40)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .background(Color.drip.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showInjuries) { InjuryListView() }
        .navigationDestination(isPresented: $showAnalysis) { TrainingAnalysisView() }
        .navigationDestination(isPresented: $showFitnessPredictor) {
            FitnessPredictorView(trainingViewModel: trainingPlanVM)
        }
        .sheet(item: $selectedLogEntry) { entry in
            HistoryDetailSheet(entry: entry) {
                Task { await loadAll() }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .task { await loadAll() }
        .refreshable { await loadAll() }
    }

    // MARK: - Opening figure

    private var openingFigure: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("OPENING FIGURE")
                .font(.dripEyebrow(11))
                .tracking(1.3)
                .foregroundStyle(Color.drip.coral)
            Text("The 5-second view.")
                .font(.dripDisplay(32))
                .foregroundStyle(Color.drip.textPrimary)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Stat tile grid (2 × 2)

    private var statTileGrid: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                TrendStatTile(
                    label: "VOLUME · 7D",
                    value: volumeValue,
                    unit: "MI",
                    delta: volumeDelta,
                    deltaColor: volumeDeltaColor
                )
                TrendStatTile(
                    label: "FITNESS",
                    value: fitnessRangeValue,
                    unit: fitnessRangeUnit,
                    delta: fitnessConfidence,
                    deltaColor: fitnessConfidenceColor,
                    action: { showFitnessPredictor = true }
                )
            }
            HStack(spacing: 10) {
                TrendStatTile(
                    label: "LOAD · ACWR",
                    value: acwrValue,
                    unit: "RATIO",
                    delta: acwrVerdict,
                    deltaColor: acwrVerdictColor
                )
                TrendStatTile(
                    label: "ACTIVE ACHES",
                    value: achesValue,
                    unit: achesUnit,
                    delta: achesSecondary,
                    deltaColor: Color.drip.textSecondary
                )
            }
        }
    }

    // MARK: - Section 2: Fitness · 12-week progression

    /// Line chart of the last 12 weeks' mileage. The placeholder JSX
    /// uses a synthetic fitness curve; we ship weekly mileage as the
    /// honest proxy until a true fitness time-series lands in
    /// `fitness_snapshots`. Right-aligned `GOAL <time>` annotation when
    /// a goal is set, mirroring the JSX.
    private var fitnessProgressionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("FITNESS  ·  12-WEEK PROGRESSION")
                    .font(.dripEyebrow(11))
                    .tracking(1.3)
                    .foregroundStyle(Color.drip.textSecondary)
                Spacer()
                Button { showAnalysis = true } label: {
                    Text("VIEW DETAIL ↗")
                        .font(.dripEyebrow(11))
                        .tracking(1.3)
                        .foregroundStyle(Color.drip.textSecondary)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 0) {
                if let goal = goalAnnotation {
                    HStack {
                        Spacer()
                        Text(goal)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .tracking(1.0)
                            .foregroundStyle(Color.drip.textTertiary)
                    }
                    .padding(.bottom, 6)
                }
                TrendsLineChart(values: weeklyMilesTrend12)
                    .frame(height: 78)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(Color.drip.cardBackgroundElevated)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }

    // MARK: - Section 3: Load · weekly volume × ACWR

    private var weeklyVolumeAcwrSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("LOAD  ·  WEEKLY VOLUME  ×  ACWR")
                .font(.dripEyebrow(11))
                .tracking(1.3)
                .foregroundStyle(Color.drip.textSecondary)

            VStack(spacing: 6) {
                TrendsVolumeBars(values: weeklyMilesTrend13)
                    .frame(height: 64)
                HStack {
                    Spacer()
                    Text(acwrAnnotation)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .tracking(1.0)
                        .foregroundStyle(Color.drip.coral)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(Color.drip.cardBackgroundElevated)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }

    // MARK: - Section 4: Drill down

    private var drillDownSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("DRILL DOWN")
                .font(.dripEyebrow(11))
                .tracking(1.3)
                .foregroundStyle(Color.drip.textSecondary)
                .padding(.bottom, 6)

            Hairline()

            // Last workout — opens HistoryDetailSheet for the most recent log
            if let last = lastLoggedEntry {
                drillRow(label: "Open last workout — \(formatLastEntry(last))") {
                    selectedLogEntry = last
                }
                Hairline()
            }

            // Active aches — opens the existing Injuries list
            drillRow(label: "Active aches — \(injuryService.activeInjuries.count) tracking") {
                showInjuries = true
            }
        }
    }

    @ViewBuilder
    private func drillRow(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text("↗")
                    .font(.system(size: 14, design: .serif))
                    .foregroundStyle(Color.drip.textPrimary)
                Text(label)
                    .font(.system(size: 14, design: .serif))
                    .foregroundStyle(Color.drip.textPrimary)
                Spacer()
            }
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Derived: VOLUME · 7D

    private var volumeValue: String {
        last7DayMiles > 0 ? String(format: "%.1f", last7DayMiles) : "—"
    }

    private var volumeDelta: String {
        guard fourWeekAvgMiles > 0 else { return "— vs 4-wk avg" }
        let deltaPct = (last7DayMiles - fourWeekAvgMiles) / fourWeekAvgMiles * 100
        let sign = deltaPct >= 0 ? "+" : ""
        return "\(sign)\(Int(deltaPct.rounded()))% VS 4-WK AVG"
    }

    private var volumeDeltaColor: Color {
        guard fourWeekAvgMiles > 0 else { return Color.drip.textSecondary }
        let delta = last7DayMiles - fourWeekAvgMiles
        if delta > 0 { return Color.drip.energized }
        if delta < 0 { return Color.drip.coral }
        return Color.drip.textSecondary
    }

    // MARK: - Derived: FITNESS · range + confidence

    /// Marathon prediction shown as `MIN — MAX` from
    /// `point ± rangeSeconds`, rounded to whole minutes per hard rule #7.
    private var fitnessRangeValue: String {
        guard let race = marathonRace else { return "—" }
        let low  = race.pointSeconds - race.rangeSeconds
        let high = race.pointSeconds + race.rangeSeconds
        return "\(formatHmsToMinute(low)) — \(formatHmsToMinute(high))"
    }

    private var fitnessRangeUnit: String { "MARATHON" }

    private var fitnessConfidence: String {
        fitnessService.predictions?.dataSources.confidenceTier.displayLabel ?? "—"
    }

    private var fitnessConfidenceColor: Color {
        guard let tier = fitnessService.predictions?.dataSources.confidenceTier else {
            return Color.drip.textSecondary
        }
        switch tier {
        case .high:   return Color.drip.energized
        case .medium: return Color.drip.tired
        case .low:    return Color.drip.textSecondary
        }
    }

    private var marathonRace: RacePredictionItem? {
        fitnessService.predictions?.races.first { $0.distance.lowercased() == "marathon" }
    }

    // MARK: - Derived: LOAD · ACWR

    private var acwrValue: String {
        guard let a = athleteState?.acwr else { return "—" }
        return String(format: "%.2f", a)
    }

    private var acwrVerdict: String {
        guard let a = athleteState?.acwr else { return "NO DATA" }
        if a < 0.8  { return "UNDERTRAINING" }
        if a <= 1.3 { return "PRODUCTIVE" }
        if a <= 1.5 { return "HIGH BUT SAFE" }
        return "SPIKE RISK"
    }

    private var acwrVerdictColor: Color {
        guard let a = athleteState?.acwr else { return Color.drip.textTertiary }
        if a < 0.8  { return Color.drip.tired }
        if a <= 1.3 { return Color.drip.energized }
        if a <= 1.5 { return Color.drip.tired }
        return Color.drip.injured
    }

    private var acwrAnnotation: String {
        guard let a = athleteState?.acwr else { return "ACWR —" }
        return "ACWR \(String(format: "%.2f", a))"
    }

    // MARK: - Derived: ACTIVE ACHES (per niggles surface-don't-interpret rule)

    private var achesValue: String {
        "\(injuryService.activeInjuries.count)"
    }

    private var achesUnit: String {
        injuryService.activeInjuries.count == 1 ? "TRACKING" : "TRACKING"
    }

    /// Quiet secondary line — date of the most recent first-reported
    /// ache, or "—" when none. NEVER a severity score; that would
    /// violate the Niggles rule.
    private var achesSecondary: String {
        let active = injuryService.activeInjuries
        guard !active.isEmpty else { return "—" }
        if active.count == 1 { return "1 BODY AREA" }
        return "\(active.count) BODY AREAS"
    }

    // MARK: - Derived: mileage windows

    private var last7DayMiles: Double {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) else {
            return 0
        }
        return recentWorkouts
            .filter { $0.startDate >= cutoff }
            .reduce(0) { $0 + $1.distanceMiles }
    }

    private var fourWeekAvgMiles: Double {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -28, to: Date()) else {
            return 0
        }
        let total = recentWorkouts
            .filter { $0.startDate >= cutoff }
            .reduce(0) { $0 + $1.distanceMiles }
        return total / 4.0
    }

    /// 12-week mileage trend, oldest first. Used as the fitness-curve
    /// proxy in section 2. Mirrors the Dashboard's `weeklyMilesTrend`
    /// helper, expanded to 12 weeks.
    private var weeklyMilesTrend12: [Double] { weeklyMilesTrend(weeks: 12) }

    /// 13-week trend for the volume bars in section 3 (matches the
    /// JSX placeholder's bar count).
    private var weeklyMilesTrend13: [Double] { weeklyMilesTrend(weeks: 13) }

    private func weeklyMilesTrend(weeks: Int) -> [Double] {
        let cal = Calendar.iso8601MondayTrends
        let thisWeekStart = cal.startOfWeek(for: Date())
        var totals: [Double] = []
        for i in (0..<weeks).reversed() {
            guard let start = cal.date(byAdding: .day, value: -7 * i, to: thisWeekStart),
                  let end   = cal.date(byAdding: .day, value: 7, to: start) else {
                totals.append(0); continue
            }
            let total = recentWorkouts
                .filter { $0.startDate >= start && $0.startDate < end }
                .reduce(0) { $0 + $1.distanceMiles }
            totals.append(total)
        }
        return totals
    }

    // MARK: - Derived: drill-down

    @State private var trainingLogs: [TrainingLog] = []

    /// Latest training log that actually has a workout linked (so
    /// tapping the row opens something useful). Falls back to the
    /// freshest log when no log has a linked workout.
    private var lastLoggedEntry: TrainingLog? {
        let withLinked = trainingLogs.first { $0.hasLinkedWorkout && $0.isCompleted }
        if let withLinked { return withLinked }
        return trainingLogs.first { $0.isCompleted }
    }

    private func formatLastEntry(_ entry: TrainingLog) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        let date = f.string(from: entry.displayDate)
        let miles = entry.formattedWorkoutDistance.map { "\($0) mi" } ?? "—"
        return "\(date)  ·  \(miles)"
    }

    // MARK: - Goal annotation

    private var goalAnnotation: String? {
        guard let plan = trainingPlanVM.activePlan else { return nil }
        return "GOAL  \(plan.formattedGoalTime)"
    }

    // MARK: - Formatting

    /// Rounds seconds to the nearest minute and renders as "H:MM".
    /// Per hard rule #7: never display seconds-precision projections.
    private func formatHmsToMinute(_ seconds: Int) -> String {
        let rounded = Int((Double(seconds) / 60).rounded()) * 60
        let h = rounded / 3600
        let m = (rounded % 3600) / 60
        if h > 0 { return String(format: "%d:%02d", h, m) }
        return String(format: "%d:%02d", m, rounded % 60)
    }

    // MARK: - Loading

    private func loadAll() async {
        // Plan first so the predictor can use it as input.
        await trainingPlanVM.loadActivePlan()

        async let workouts: () = loadRecentWorkouts()
        async let logs:     () = loadTrainingLogs()
        async let state:    TrendsAthleteState? = TrendsAthleteState.fetch()
        async let injuries: () = injuryService.fetchInjuries()
        async let predict:  () = fitnessService.predictFitness(plan: trainingPlanVM.activePlan)

        let athlete = await state
        _ = await (workouts, logs, injuries, predict)

        await MainActor.run {
            self.athleteState = athlete
        }
    }

    /// Same merge pattern as the rewritten TrainingTabView — HealthKit
    /// + Strava-mirrored training_logs, dedupe by start time + duration.
    private func loadRecentWorkouts() async {
        async let hk     = HealthKitManager.shared.fetchRecentRunningWorkouts(limit: 200)
        async let strava = Self.fetchStravaRunningWorkouts(limit: 200)

        var merged: [RunningWorkout] = []
        let appendIfUnique: (RunningWorkout) -> Void = { w in
            let isDup = merged.contains { existing in
                abs(existing.startDate.timeIntervalSince(w.startDate)) < 300
                    && abs(existing.durationMinutes - w.durationMinutes) < 2.0
            }
            if !isDup { merged.append(w) }
        }
        for w in await strava { appendIfUnique(w) }
        for w in await hk { appendIfUnique(w) }
        merged.sort { $0.startDate > $1.startDate }

        await MainActor.run { self.recentWorkouts = merged }
    }

    private func loadTrainingLogs() async {
        do {
            let userId = AuthManager.shared.userId
            let rows: [TrainingLog] = try await supabase
                .from("training_logs")
                .select()
                .eq("user_id", value: userId)
                .order("workout_date", ascending: false, nullsFirst: false)
                .limit(40)
                .execute()
                .value
            await MainActor.run {
                self.trainingLogs = rows.sorted { $0.displayDate > $1.displayDate }
            }
        } catch {
            await MainActor.run { self.trainingLogs = [] }
        }
    }

    private static func fetchStravaRunningWorkouts(limit: Int) async -> [RunningWorkout] {
        struct Row: Decodable {
            let id: String
            let workout_date: Date?
            let workout_distance_miles: Double?
            let workout_duration_minutes: Double?
            let vital_workout_id: String?
        }
        do {
            let userId = AuthManager.shared.userId
            let rows: [Row] = try await supabase
                .from("training_logs")
                .select("id, workout_date, workout_distance_miles, workout_duration_minutes, vital_workout_id")
                .eq("user_id", value: userId)
                .eq("source", value: "strava")
                .order("workout_date", ascending: false, nullsFirst: false)
                .limit(limit)
                .execute()
                .value
            return rows.compactMap { r -> RunningWorkout? in
                guard let start = r.workout_date,
                      let dist = r.workout_distance_miles, dist > 0,
                      let dur = r.workout_duration_minutes, dur > 0,
                      let uuid = UUID(uuidString: r.id) else { return nil }
                return RunningWorkout(
                    id: uuid,
                    startDate: start,
                    endDate: start.addingTimeInterval(dur * 60),
                    distanceMiles: dist,
                    durationMinutes: dur,
                    pacePerMile: dur / dist,
                    calories: 0,
                    sourceApp: "Strava",
                    vitalWorkoutId: r.vital_workout_id
                )
            }
        } catch {
            return []
        }
    }
}

// MARK: - Helper view: stat tile

private struct TrendStatTile: View {
    let label: String
    let value: String
    let unit: String
    let delta: String
    let deltaColor: Color
    /// Optional tap action. When non-nil, the tile renders a chevron
    /// affordance in the label row and the whole surface becomes a
    /// Button. Wired by the FITNESS tile to push FitnessPredictorView.
    var action: (() -> Void)? = nil

    var body: some View {
        if let action {
            Button(action: action) { tileContent }
                .buttonStyle(.plain)
        } else {
            tileContent
        }
    }

    private var tileContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.dripEyebrow(10))
                    .tracking(1.2)
                    .foregroundStyle(Color.drip.textSecondary)
                Spacer(minLength: 4)
                if action != nil {
                    Text("↗")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.drip.textTertiary)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value)
                    .font(.dripStat(24))
                    .foregroundStyle(Color.drip.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(unit)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.drip.textSecondary)
            }
            Text(delta)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(deltaColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.drip.cardBackgroundElevated)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
    }
}

// MARK: - Helper view: 12-week line chart

private struct TrendsLineChart: View {
    let values: [Double]

    var body: some View {
        GeometryReader { geo in
            let maxV = max(values.max() ?? 1, 1)
            Canvas { ctx, size in
                guard values.count > 1 else { return }
                // Filled area under the line.
                var area = Path()
                let step = size.width / CGFloat(values.count - 1)
                let firstY = pointY(0, max: maxV, height: size.height)
                area.move(to: CGPoint(x: 0, y: size.height))
                area.addLine(to: CGPoint(x: 0, y: firstY))
                for i in 1..<values.count {
                    let x = CGFloat(i) * step
                    let y = pointY(i, max: maxV, height: size.height)
                    area.addLine(to: CGPoint(x: x, y: y))
                }
                area.addLine(to: CGPoint(x: size.width, y: size.height))
                area.closeSubpath()
                ctx.fill(area, with: .color(Color.drip.textTertiary.opacity(0.18)))

                // Ink line on top.
                var line = Path()
                line.move(to: CGPoint(x: 0, y: firstY))
                for i in 1..<values.count {
                    let x = CGFloat(i) * step
                    let y = pointY(i, max: maxV, height: size.height)
                    line.addLine(to: CGPoint(x: x, y: y))
                }
                ctx.stroke(line, with: .color(Color.drip.textPrimary), lineWidth: 1.5)

                // Current week dot.
                if let last = values.indices.last {
                    let x = CGFloat(last) * step
                    let y = pointY(last, max: maxV, height: size.height)
                    let r: CGFloat = 4
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                        with: .color(Color.drip.coral)
                    )
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private func pointY(_ i: Int, max: Double, height: CGFloat) -> CGFloat {
        let v = values[i]
        let frac = max > 0 ? CGFloat(v / max) : 0
        return height - (height * frac)
    }
}

// MARK: - Helper view: weekly volume bars

private struct TrendsVolumeBars: View {
    let values: [Double]

    var body: some View {
        GeometryReader { geo in
            let maxV = max(values.max() ?? 1, 1)
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(values.indices, id: \.self) { i in
                    let frac = CGFloat(values[i] / maxV)
                    let h = max(2, geo.size.height * frac)
                    let isCurrent = i == values.count - 1
                    RoundedRectangle(cornerRadius: 1)
                        .fill(isCurrent ? Color.drip.textPrimary
                                        : Color.drip.textTertiary.opacity(0.6))
                        .frame(height: h)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

// MARK: - athlete_state slim row

/// Minimal projection of `athlete_state` for the Trends ACWR tile.
/// Same shape the retired TrainingTabView pulled — just rebranded so
/// it doesn't collide with `TrainingTabState` if both files compile.
struct TrendsAthleteState: Decodable {
    let acwr: Double?
    let rolling_7d_miles: Double?
    let rolling_28d_miles: Double?

    static func fetch() async -> TrendsAthleteState? {
        do {
            let rows: [TrendsAthleteState] = try await supabase
                .from("athlete_state")
                .select("acwr, rolling_7d_miles, rolling_28d_miles")
                .limit(1)
                .execute()
                .value
            return rows.first
        } catch {
            Log.coach.error("TrendsAthleteState fetch failed: \(error)")
            return nil
        }
    }
}

// MARK: - Calendar helpers

fileprivate extension Calendar {
    /// ISO 8601 Monday-first week, scoped to this file so the
    /// declaration doesn't collide with the fileprivate copy in
    /// `TrainingTabView.swift` / `PlanMonthSummaryView.swift`.
    static var iso8601MondayTrends: Calendar {
        var cal = Calendar(identifier: .iso8601)
        cal.firstWeekday = 2
        return cal
    }

    func startOfWeek(for date: Date) -> Date {
        let comps = self.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return self.date(from: comps) ?? self.startOfDay(for: date)
    }
}
