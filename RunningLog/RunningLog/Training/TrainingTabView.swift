//
//  TrainingTabView.swift
//  RunningLog
//
//  Train tab — redesigned per `outputs/train-redesign/training-redesign-handoff.md`.
//
//  Lands on this week. Today's session reads as an editorial headline,
//  not a card. The longer-arc analytics (block totals, pace × volume,
//  recent log) sit one tap away behind a WEEK / BLOCK segmenter.
//
//      PlateStrip · TRAINING · MARATHON BLOCK · FIG. 6
//      TrainingHeader
//      WeekBlockSegmenter
//      ├── WEEK → TrainingTodayHero · CoachNoteSection · CoachPlanWeekStrip · WeeklyMileageQuietRow
//      └── BLOCK → BlockTotalsStrip · PaceVolumeSpectrumChart · TrainingLogPreviewRow ×5
//
//  Replaces the previous pace-zones / ACWR / heatmap surface that lived
//  here, and retires TrainingDashboardView. The pace-zones / heatmap
//  analytics belong on a dedicated Analysis screen — not on top of
//  today's session.
//

import Supabase
import SwiftUI

/// Zoom modes for the BLOCK view's pace × volume chart.
///
/// `all` shows the full distribution — easy work dominates the visual
/// because that's where most miles live, which can drown out the
/// shape of workout-paced work.
///
/// `workouts` tightens the x-axis to MP-and-faster paces and filters
/// easy samples out of the KDE so threshold and 5K work re-normalize
/// against just the workout distribution and become legible shapes.
enum PaceZoom: String, CaseIterable {
    case all      = "all"
    case workouts = "workouts"

    var label: String {
        switch self {
        case .all:      return "ALL"
        case .workouts: return "WORKOUTS"
        }
    }
}

struct TrainingTabView: View {

    // MARK: - State

    @State private var trainingPlanVM = TrainingPlanViewModel()
    @State private var recentWorkouts: [RunningWorkout] = []
    @State private var trainingLogs: [TrainingLog] = []
    @State private var loaded = false

    /// Segment persisted across tab switches. Deep-linking back to
    /// Train returns the user to wherever they left off.
    @AppStorage("training.tab.segment") private var segmentRaw: String = TrainingTabSegment.current.rawValue
    private var segment: TrainingTabSegment {
        TrainingTabSegment(rawValue: segmentRaw) ?? .current
    }
    private var segmentBinding: Binding<TrainingTabSegment> {
        Binding(
            get: { segment },
            set: { segmentRaw = $0.rawValue }
        )
    }

    /// Selected log entry (opens HistoryDetailSheet) on BLOCK view.
    @State private var selectedLogEntry: TrainingLog?

    /// Today's workout shown in the DayDetailSheet (Mark complete flow).
    @State private var selectedScheduledWorkout: ScheduledWorkout?

    /// Navigation flag for the links that push TrainingPlanView: the
    /// week strip's "VIEW PLAN ↗" on CURRENT and the no-plan nudge's
    /// "BROWSE PLANS ↗" on CALENDAR. Those two never render at the
    /// same time, so a single flag keeps SwiftUI's destination
    /// resolution unambiguous. The header used to carry a third link
    /// to the same destination; it was cut as duplication.
    @State private var showPlan = false

    /// Navigation flag for the BLOCK view's "VIEW ALL ↗" link.
    @State private var showHistory = false

    /// Pace × volume chart zoom — ALL shows the full pace distribution
    /// (easy work dominates the visual); WORKOUTS clips to MP-and-faster
    /// so threshold and 5K-pace work become legible shapes instead of
    /// 5%-tall slivers next to the easy peak. Persisted across tab
    /// switches.
    @AppStorage("training.paceZoom") private var paceZoomRaw: String = "all"
    private var paceZoom: PaceZoom {
        PaceZoom(rawValue: paceZoomRaw) ?? .all
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PlateStrip(
                    surface: "TRAINING  ·  \(blockSurfaceLabel)",
                    fig: "FIG. 6"
                )

                Spacer().frame(height: 24)

                TrainingHeader(
                    weekText: weekText,
                    dateText: todayLabel,
                    headline: headlineText,
                    goalLine: goalLine
                )

                Spacer().frame(height: 18)

                WeekBlockSegmenter(segment: segmentBinding)

                switch segment {
                case .current:  weekView
                case .calendar: calendarView
                case .history:  blockView
                }

                Spacer().frame(height: 32)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .background(Color.drip.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showPlan)    { TrainingPlanView() }
        .navigationDestination(isPresented: $showHistory) { HistoryView() }
        .sheet(item: $selectedLogEntry) { entry in
            HistoryDetailSheet(entry: entry) {
                Task { await loadTrainingLogs() }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedScheduledWorkout) { workout in
            DayDetailSheet(
                viewModel: trainingPlanVM,
                scheduledWorkout: workout,
                racePaceSeconds: trainingPlanVM.racePaceSecondsPerMile ?? 480
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .task { await loadAll() }
        .refreshable { await loadAll() }
    }

    // MARK: - CURRENT view

    @ViewBuilder
    private var weekView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 24)

            TrainingTodayHero(
                workout: todayWorkout,
                onMarkComplete: { selectedScheduledWorkout = todayWorkout }
            )

            // Coach note — only when we have something honest to say.
            if let quote = coachQuote {
                Spacer().frame(height: 26)
                EditorialRule()
                Spacer().frame(height: 18)

                CoachNoteSection(quote: quote)
            }

            Spacer().frame(height: 28)
            EditorialRule()
            Spacer().frame(height: 16)

            // Week strip. No section eyebrow: the segmenter a few points
            // above is already reading "THIS WEEK" in coral, and a
            // "THE WEEK" label under it was the same word twice. The
            // "VIEW PLAN ↗" link keeps the row and sits right-aligned.
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Spacer()
                    Button { showPlan = true } label: {
                        Text("VIEW PLAN ↗")
                            .font(.dripEyebrow(11))
                            .tracking(1.3)
                            .foregroundStyle(Color.drip.textSecondary)
                    }
                    .buttonStyle(.plain)
                }

                if !currentWeekWorkouts.isEmpty {
                    CoachPlanWeekStrip(workouts: currentWeekWorkouts)
                } else {
                    Text("No plan loaded yet.")
                        .font(.system(size: 14, design: .serif).italic())
                        .foregroundStyle(Color.drip.textSecondary)
                }
            }

            Spacer().frame(height: 22)

            WeeklyMileageQuietRow(
                thisWeekMiles: thisWeekMiles,
                lastWeekMiles: lastWeekMiles
            )
        }
    }

    // MARK: - CALENDAR view

    /// The month grid — what happened and what's planned, together.
    ///
    /// This is where the old Plan tab went. `MonthCalendarView` already
    /// draws logged days (mood + distance) alongside scheduled ones and
    /// keeps its plan-range shading and summary bar behind
    /// `activePlan != nil`, so the grid reads correctly for a
    /// self-coached athlete with no plan at all — `activePlan == nil`
    /// is a state here, not a failure.
    ///
    /// Taps route into the two sheets this view already owns: a
    /// scheduled day opens `DayDetailSheet`, a logged day opens
    /// `HistoryDetailSheet`.
    @ViewBuilder
    private var calendarView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 22)

            // MonthCalendarView carries its own 20pt gutter, so cancel
            // the parent's 24pt to keep the grid on the design's margin
            // instead of double-padding it to 44pt.
            MonthCalendarView(
                viewModel: trainingPlanVM,
                onDayTap: { workout in
                    selectedScheduledWorkout = workout
                },
                onLogDayTap: { day in
                    openLogEntry(forDayOfMonth: day)
                }
            )
            .padding(.horizontal, -24)

            if trainingPlanVM.activePlan == nil {
                Spacer().frame(height: 22)
                EditorialRule()
                Spacer().frame(height: 16)

                VStack(alignment: .leading, spacing: 8) {
                    Text("NO PLAN")
                        .font(.dripEyebrow(11))
                        .tracking(1.3)
                        .foregroundStyle(Color.drip.textSecondary)

                    Text("The month still fills in from what you run. Add a plan when you want the week laid out ahead of you.")
                        .font(.system(size: 14, design: .serif).italic())
                        .foregroundStyle(Color.drip.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button { showPlan = true } label: {
                        Text("BROWSE PLANS ↗")
                            .font(.dripEyebrow(11))
                            .tracking(1.3)
                            .foregroundStyle(Color.drip.coral)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }
        }
    }

    /// Resolve a tapped calendar day to its log entry and open the
    /// history sheet. Goes back to the service rather than filtering
    /// `trainingLogs`, which only holds the 40 most recent rows and so
    /// misses older months once the athlete pages back.
    private func openLogEntry(forDayOfMonth day: Int) {
        var components = DateComponents()
        components.year = trainingPlanVM.selectedYear
        components.month = trainingPlanVM.selectedMonth
        components.day = day
        guard let date = Calendar.current.date(from: components) else { return }

        Task {
            let entries = await trainingPlanVM.loadLogEntries(for: date)
            guard let first = entries.first else { return }
            await MainActor.run { selectedLogEntry = first }
        }
    }

    // MARK: - HISTORY view

    @ViewBuilder
    private var blockView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 22)

            BlockTotalsStrip(totals: blockTotals)

            Spacer().frame(height: 26)
            paceVolumeSpectrumSection

            Spacer().frame(height: 22)
            recentLogSection
        }
    }

    // MARK: - Pace × volume (lifted from TrainingDashboardView)

    /// Eyebrow + the existing density chart. Anchors come from
    /// `trainingPlanVM.equivalentPaces`; samples are last-7-day workouts
    /// keyed by their average pace. The redesign moves this section from
    /// the old Dashboard onto BLOCK without changing how it draws.
    @ViewBuilder
    private var paceVolumeSpectrumSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("PACE  &  VOLUME  ·  9 WEEKS")
                    .font(.dripEyebrow(11))
                    .tracking(1.3)
                    .foregroundStyle(Color.drip.textSecondary)
                Spacer()
                paceZoomToggle
            }
            .padding(.bottom, 10)

            Hairline()
                .padding(.bottom, 16)

            if let paces = trainingPlanVM.equivalentPaces, !recentWorkouts.isEmpty {
                paceVolumeChart(paces: paces)
            } else {
                Text("No runs logged yet. Log one and the picture will fill in.")
                    .font(.system(size: 14, design: .serif).italic())
                    .foregroundStyle(Color.drip.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            }
        }
    }

    /// ALL · WORKOUTS toggle — small mono pills with a coral underline on
    /// the active state. Sits inline with the section eyebrow.
    @ViewBuilder
    private var paceZoomToggle: some View {
        HStack(spacing: 14) {
            ForEach(PaceZoom.allCases, id: \.rawValue) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        paceZoomRaw = mode.rawValue
                    }
                } label: {
                    Text(mode.label)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .tracking(1.1)
                        .foregroundStyle(paceZoom == mode
                                         ? Color.drip.textPrimary
                                         : Color.drip.textTertiary)
                        .padding(.bottom, 3)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(paceZoom == mode
                                      ? Color.drip.coral
                                      : Color.clear)
                                .frame(height: 1)
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Renders the pace × volume chart in the current zoom mode. WORKOUTS
    /// mode tightens the slow side to ~30s past the LT anchor and filters
    /// out easy samples, so the KDE re-normalizes against just the
    /// workout distribution — threshold and 5K work become readable
    /// shapes instead of 5% slivers next to the easy peak.
    @ViewBuilder
    private func paceVolumeChart(paces: EquivalentPaces) -> some View {
        let weekWorkouts = workoutsInLast(days: 63)
        let allSamples = weekWorkouts.map {
            PaceVolumeSample(
                paceSeconds: $0.pacePerMile * 60,
                miles: $0.distanceMiles
            )
        }
        let anchors = PaceVolumeSpectrumChart.defaultAnchors(
            easyPace:      paces.easyPace,
            marathonPace:  paces.mpPace,
            thresholdPace: paces.thresholdPace,
            fiveKPace:     paces.fiveKPace
        )

        switch paceZoom {
        case .all:
            PaceVolumeSpectrumChart(samples: allSamples, anchors: anchors)
        case .workouts:
            // Slow bound: 30s past LT (between MP and LT). Samples slower
            // than that are filtered so the KDE doesn't carry a tail from
            // easy volume. Fast bound: 30s past the fastest sample or 5K
            // anchor, whichever is faster, clamped at 180s/mi.
            let slowBound = paces.thresholdPace + 30
            let fastBound = max(
                min(allSamples.map(\.paceSeconds).min() ?? paces.fiveKPace,
                    paces.fiveKPace) - 30,
                180
            )
            let workoutSamples = allSamples.filter { $0.paceSeconds <= slowBound }
            PaceVolumeSpectrumChart(
                samples: workoutSamples,
                anchors: anchors,
                paceSlow: slowBound,
                paceFast: fastBound,
                bandwidth: 10        // tighter kernel for the tighter range
            )
        }
    }

    // MARK: - Recent log (lifted from TrainingDashboardView, slimmed)

    @ViewBuilder
    private var recentLogSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("TRAINING LOG  ·  RECENT")
                    .font(.dripEyebrow(11))
                    .tracking(1.3)
                    .foregroundStyle(Color.drip.textSecondary)
                Spacer()
                Button { showHistory = true } label: {
                    Text("VIEW ALL ↗")
                        .font(.dripEyebrow(11))
                        .tracking(1.3)
                        .foregroundStyle(Color.drip.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 10)

            Hairline()

            // Same slice as the retired Dashboard's preview block.
            let previews = trainingLogs
                .filter { $0.isCompleted && $0.source != "auto_sync" }
                .sorted { $0.displayDate > $1.displayDate }
                .prefix(5)

            if previews.isEmpty {
                Text("No voice memos or training notes yet.")
                    .font(.system(size: 14, design: .serif).italic())
                    .foregroundStyle(Color.drip.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 14)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(previews.enumerated()), id: \.element.id) { idx, entry in
                        Button {
                            selectedLogEntry = entry
                        } label: {
                            TrainingLogPreviewRow(entry: entry)
                        }
                        .buttonStyle(.plain)
                        if idx < previews.count - 1 {
                            Hairline()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Derived: header

    private var blockSurfaceLabel: String {
        guard let plan = trainingPlanVM.activePlan else {
            return "MARATHON BLOCK"
        }
        // Strip the snake_case underscore that comes from raw race-distance
        // fields (e.g. "half_marathon" → "HALF MARATHON BLOCK").
        let race = plan.targetRaceDistance
            .replacingOccurrences(of: "_", with: " ")
            .uppercased()
        return "\(race) BLOCK"
    }

    /// Week counter only. The "TRAINING · " prefix this used to carry
    /// was the third restatement of the same fact on one screen — the
    /// PlateStrip above says TRAINING, the tab bar says TRAIN. Empty
    /// with no active plan, which hides the line entirely.
    private var weekText: String {
        guard let plan = trainingPlanVM.activePlan else { return "" }
        let week = String(format: "%02d", plan.currentWeek)
        return "WEEK \(week) OF \(plan.totalWeeks)"
    }

    private var todayLabel: String {
        let f = DateFormatter()
        f.dateFormat = "EEE  ·  MMM d"
        return f.string(from: Date()).uppercased()
    }

    private var headlineText: String {
        guard let plan = trainingPlanVM.activePlan else {
            return "No active plan."
        }
        // Strip the snake_case underscore before sentence-casing so
        // "half_marathon" renders as "Half marathon block." not
        // "Half_marathon block." — the underscore was leaking through.
        let race = plan.targetRaceDistance
            .replacingOccurrences(of: "_", with: " ")
        let cap = race.prefix(1).uppercased() + race.dropFirst()
        return "\(cap) block."
    }

    private var goalLine: String? {
        guard let plan = trainingPlanVM.activePlan else { return nil }
        let goal = "Sub-\(plan.formattedGoalTime)"
        let raceF = DateFormatter()
        raceF.dateFormat = "MMM d"
        let raceDay = raceF.string(from: plan.endDate)
        let days = max(0, plan.daysRemaining)
        return "\(goal)  ·  \(raceDay)  ·  \(days) days out."
    }

    // MARK: - Derived: today & current week

    private var currentWeekWorkouts: [ScheduledWorkout] {
        trainingPlanVM.currentWeekWorkouts
    }

    private var todayWorkout: ScheduledWorkout? {
        currentWeekWorkouts.first(where: { $0.isToday })
    }

    // MARK: - Derived: WEEK · coach quote
    //
    // Lifted from the retired TrainingDashboardView. V1 narrative is
    // assembled locally from week mileage, mood trend, and the upcoming
    // long run. When `weekly_coaching_reports.coaching_narrative` is
    // wired up, swap to that — leaving this in place as the fallback.

    /// Returns the coach quote text to display, or nil when there's
    /// nothing honest to say yet (e.g. fresh install with no logs).
    private var coachQuote: String? {
        let trendPart: String = {
            guard lastWeekMiles > 0 else { return "" }
            let delta = (thisWeekMiles - lastWeekMiles) / lastWeekMiles * 100
            if delta > 5  { return "Up \(Int(delta.rounded()))% on volume." }
            if delta < -5 { return "Down \(Int(abs(delta).rounded()))% on volume." }
            return "Volume holding steady."
        }()
        let moodPart: String = {
            switch moodTrend {
            case .up:    return " Mood trending up."
            case .down:  return " Mood trending down — easy on yourself."
            case .flat:  return ""
            }
        }()
        let marqueePart: String = {
            guard let m = upcomingLongRun else { return "" }
            return " \(m) is the marquee."
        }()
        let summary = (trendPart + moodPart + marqueePart)
            .trimmingCharacters(in: .whitespaces)
        return summary.isEmpty ? nil : summary
    }

    // MARK: - Derived: mileage & helpers (lifted from Dashboard)

    private var thisWeekMiles: Double {
        let weekStart = Calendar.iso8601Monday.startOfWeek(for: Date())
        return recentWorkouts
            .filter { $0.startDate >= weekStart }
            .reduce(0) { $0 + $1.distanceMiles }
    }

    private var lastWeekMiles: Double {
        let cal = Calendar.iso8601Monday
        let thisWeekStart = cal.startOfWeek(for: Date())
        guard let lastWeekStart = cal.date(byAdding: .day, value: -7, to: thisWeekStart) else { return 0 }
        return recentWorkouts
            .filter { $0.startDate >= lastWeekStart && $0.startDate < thisWeekStart }
            .reduce(0) { $0 + $1.distanceMiles }
    }

    private enum MoodTrend { case up, down, flat }
    private var moodTrend: MoodTrend {
        let recent = trainingLogs
            .compactMap { $0.mood?.lowercased() }
            .prefix(14)
        guard !recent.isEmpty else { return .flat }
        let positive = recent.filter { ["energized", "positive"].contains($0) }.count
        let negative = recent.filter { ["tired", "struggling", "injured"].contains($0) }.count
        if positive >= negative + 2 { return .up }
        if negative >= positive + 2 { return .down }
        return .flat
    }

    private var upcomingLongRun: String? {
        let cal = Calendar.current
        let weekEnd = cal.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        let longRun = trainingPlanVM.allScheduledWorkouts
            .filter { $0.workoutType == .longRun
                && $0.date >= cal.startOfDay(for: Date())
                && $0.date < weekEnd }
            .sorted { $0.date < $1.date }
            .first
        guard let lr = longRun, let miles = lr.workout?.totalDistanceMiles else { return nil }
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        let day = f.string(from: lr.date)
        return "\(day)'s \(Int(miles.rounded()))-miler"
    }

    // MARK: - Derived: BLOCK totals

    private var blockTotals: BlockTotals {
        guard let plan = trainingPlanVM.activePlan else {
            return BlockTotals(blockTotal: 0, avgWeek: 0, longTops: 0)
        }
        let runsInBlock = recentWorkouts.filter {
            $0.startDate >= plan.startDate && $0.startDate <= Date()
        }
        let total = runsInBlock.reduce(0.0) { $0 + $1.distanceMiles }
        let weeks = max(1, plan.currentWeek)
        let avg = total / Double(weeks)
        let long = runsInBlock.map(\.distanceMiles).max() ?? 0
        return BlockTotals(blockTotal: total, avgWeek: avg, longTops: long)
    }

    // MARK: - Sample window helper

    private func workoutsInLast(days: Int) -> [RunningWorkout] {
        guard let cutoff = Calendar.current.date(
            byAdding: .day, value: -days, to: Date()
        ) else { return recentWorkouts }
        return recentWorkouts.filter { $0.startDate >= cutoff }
    }

    // MARK: - Loading

    private func loadAll() async {
        async let workouts: () = loadRecentWorkouts()
        async let logs:     () = loadTrainingLogs()
        async let plan:     () = trainingPlanVM.loadActivePlan()
        _ = await (workouts, logs, plan)
        await MainActor.run { loaded = true }
    }

    /// Mirror of the retired Dashboard's workout-merge: pull from
    /// HealthKit + Vital (stubbed) + Strava-mirrored training_logs and
    /// dedupe by start time + duration.
    private func loadRecentWorkouts() async {
        async let hk     = HealthKitManager.shared.fetchRecentRunningWorkouts(limit: 60)
        async let strava = Self.fetchStravaRunningWorkouts(limit: 60)

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
            // Surface as empty state rather than an error toast; the
            // recent-log section already handles the empty case.
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

// MARK: - Calendar helpers (lifted from the retired TrainingDashboardView)

/// ISO 8601 week (Monday-first) — matches the convention used by
/// `PlanMonthSummaryView` and the plan service. Kept fileprivate so
/// other files in the module can declare their own without collision.
fileprivate extension Calendar {
    static var iso8601Monday: Calendar {
        var cal = Calendar(identifier: .iso8601)
        cal.firstWeekday = 2
        return cal
    }

    /// Start of the calendar's week containing `date`.
    func startOfWeek(for date: Date) -> Date {
        let comps = self.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return self.date(from: comps) ?? self.startOfDay(for: date)
    }
}
