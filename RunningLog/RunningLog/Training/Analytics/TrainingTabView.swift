//
//  TrainingTabView.swift
//  RunningLog
//
//  The analytical **Training** tab. Replaces the old Train + Trends tabs
//  with a single aggregate-only analysis surface driven by one scope
//  toggle (WEEK · MONTH · BLOCK). Built from `training-tab-spec.md` and
//  `training-tab-mockup.html`.
//
//  Section order (top → bottom):
//    1. Header        — dateline · "Your training." · one data-derived insight
//    2. Summary       — MILES · RUNS · HOURS · % EASY (scope-aware)
//    3. Scope toggle  — WEEK | MONTH | BLOCK
//    4. Volume · By Intensity — per-day (week) / per-week + rolling avg
//                       (month) / block stat-strip + weekly rows (block);
//                       month also gets the Easy-Pace trend line
//    5. Mileage · By Day — calendar grid, tap a day to expand its sessions
//    6. Easy / Hard   — split bar with an 80/20 target tick
//    7. Volume × Pace — 18-bin histogram, ramp-coloured, current-fitness markers
//    8. Effort · Felt vs Planned — hard sessions only, only when felt exists
//    9. Goals & Targets — collapsed; the only place goal paces appear
//
//  All values are real and current-fitness-anchored — see
//  `TrainingAnalyticsViewModel`. This view owns layout only.
//

import Foundation
import SwiftUI

struct TrainingTabView: View {
    @State private var vm = TrainingAnalyticsViewModel()

    // Goal editing. The analytics VM is read-only; goal mutations go
    // through TrainingPlanViewModel → EditGoalSheet → update-plan-goal,
    // mirroring the Plan tab's path. AI never invokes this; the athlete
    // owns the goal (see feedback_ai_advises_never_acts.md).
    @State private var planVM = TrainingPlanViewModel()

    // Every Training-tab modal routes through one enum, so only a single
    // sheet is ever live (avoids stacked-`.sheet` fragility). The
    // editGoal → recompute hand-off is sequenced in the sheet content and
    // the `onChange(of: route)` below.
    @State private var route: TrainingRoute?

    /// Train's three modes (beta 4-tab IA — Train is the detail surface, and
    /// Plan folds into CALENDAR). CURRENT = today + this week · CALENDAR = grid
    /// + plan/goal · HISTORY = workouts & reps archive + analytics.
    @State private var mode: TrainMode = .current
    enum TrainMode: String, CaseIterable {
        case current = "Current", calendar = "Calendar", history = "History"
    }

    enum TrainingRoute: Identifiable, Equatable {
        case editGoal
        case recompute
        case day(Date)
        case volume(VolumeChartKind)

        var id: String {
            switch self {
            case .editGoal:      return "editGoal"
            case .recompute:     return "recompute"
            case .day(let d):    return "day-\(d.timeIntervalSince1970)"
            case .volume(let k): return "volume-\(k.id)"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PlateStrip(surface: "TRAINING · ANALYSIS")
                    .padding(.bottom, 24)

                if vm.isLoading && !vm.hasLoaded {
                    loadingState
                } else if vm.loadFailed && !vm.hasLoaded {
                    EmptyStateView(
                        variant: .error,
                        eyebrow: "Couldn't load",
                        title: "Your training analytics didn't load. Check your connection and try again.",
                        cta: .init(label: "Retry") {
                            Task { await vm.load() }
                        }
                    )
                    .padding(.vertical, 40)
                } else {
                    header
                    trainModeNav
                        .padding(.top, 4)

                    switch mode {
                    case .current:
                        summary
                        todaySection
                        currentWeekSection
                        feltVsPlanned
                    case .calendar:
                        scopeToggle
                        // The editorial day-by-day calendar replaces the old
                        // per-day bar charts (volumeByIntensity + mileageByDay),
                        // which showed the same week two other ways. The
                        // within-day intensity split survives as the section's
                        // summary strip and in full on the day sheet.
                        TrainingCalendarSection(vm: vm) { route = .day($0) }
                            .padding(.top, 8)
                        EditorialRule().padding(.vertical, 22)
                        // Phase A: the Plan tab folded in here — the plan is
                        // a subset of training, not its own destination.
                        planSection
                        EditorialRule().padding(.vertical, 22)
                        goals
                    case .history:
                        WorkoutsAndRepsSection()
                            .padding(.top, 20)
                        EditorialRule().padding(.vertical, 22)
                        easyHard
                        volumeByPace
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .background(Color.drip.background.ignoresSafeArea())
        .task {
            if !vm.hasLoaded { await vm.load() }
            // Load the plan so EditGoalSheet opens against the current
            // goal and the recompute soft-ask can find the active plan.
            await planVM.loadActivePlan()
        }
        // Re-derive when scope flips. Closes any open modal.
        .onChange(of: vm.scope) { _, _ in route = nil }
        .sheet(item: $route) { r in
            switch r {
            case .editGoal:
                // Plan present → on save, chain the recompute soft-ask
                // (EditGoalSheet fires onSaved only when a plan exists, and
                // defers it past its own dismiss). Plan nil (self-coached)
                // → sets an athlete goal with no chain; the onChange below
                // refreshes the Goals block once it closes.
                EditGoalSheet(viewModel: planVM, plan: planVM.activePlan, onSaved: {
                    route = .recompute
                })
                .presentationDetents([.large])
            case .recompute:
                if let plan = planVM.activePlan {
                    RecomputePacesSheet(plan: plan, onComplete: {
                        await planVM.loadActivePlan()
                        await vm.load()
                    })
                }
            case .day(let day):
                DayAnalysisSheet(vm: vm, day: day)
            case .volume(let kind):
                VolumeDetailSheet(vm: vm, kind: kind)
            }
        }
        .onChange(of: route) { old, new in
            // editGoal closed without entering the recompute chain (cancel,
            // or a no-plan save) → refresh the Goals block.
            if old == .editGoal, new == nil, planVM.activePlan == nil {
                Task { await vm.load() }
            }
        }
    }

    private var loadingState: some View {
        VStack(spacing: 14) {
            ProgressView().tint(Color.drip.coral)
            Text("READING YOUR TRAINING")
                .font(.dripEyebrow(10)).tracking(1.4)
                .foregroundStyle(Color.drip.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }

    // MARK: 1 · Header

    // Neutral headline only — it *names* the screen, it never grades the
    // month. Any data-derived verdict ("hard share is creeping…") is coach
    // voice and lives on The Read, not here. Training stays factual.
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(vm.scopeDateline())
                .font(.dripEyebrow(10.5)).tracking(1.6)
                .foregroundStyle(Color.drip.textSecondary)
            Text("Your training.")
                .font(.dripDisplay(34))
                .foregroundStyle(Color.drip.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 2 · Summary stats

    // Three input streams as plain counts — workouts, voice memos, volume —
    // with hours + easy% as a quiet sub-strip. No narration; the counts are
    // the summary. Voice memos surface the qualitative stream we log.
    private var summary: some View {
        let s = vm.summary()
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                statCell("\(s.runs)", "Runs")
                statDivider
                statCell("\(s.voiceMemos)", "Voice memos")
                statDivider
                statCell(vm.formatMiles(s.miles), "Miles")
            }
            .overlay(Rectangle().fill(Color.drip.divider).frame(height: 1), alignment: .top)
            .overlay(Rectangle().fill(Color.drip.divider).frame(height: 1), alignment: .bottom)

            HStack(spacing: 16) {
                Text("\(TrainingAnalyticsViewModel.formatDurationHours(s.durationMinutes)) HRS")
                    .font(.dripEyebrow(10)).tracking(1.1)
                    .foregroundStyle(Color.drip.textSecondary)
                Text("\(s.easyPercent)% EASY")
                    .font(.dripEyebrow(10)).tracking(1.1)
                    .foregroundStyle(Color.drip.textSecondary)
                Spacer()
            }
            .padding(.top, 13)
        }
        .padding(.top, 22)
    }

    private func statCell(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.dripStat(21))
                .foregroundStyle(Color.drip.textPrimary)
            Text(label.uppercased())
                .font(.dripEyebrow(9)).tracking(1.35)
                .foregroundStyle(Color.drip.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
    }

    private var statDivider: some View {
        Rectangle().fill(Color.drip.divider).frame(width: 1, height: 34)
    }

    // MARK: 3 · Scope toggle

    private var scopeToggle: some View {
        HStack(spacing: 0) {
            ForEach(TrainingScope.allCases) { s in
                let on = vm.scope == s
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { vm.scope = s }
                } label: {
                    Text(s.label.uppercased())
                        .font(.dripEyebrow(11.5)).tracking(2.0)
                        .foregroundStyle(on ? Color.drip.coral : Color.drip.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(on ? Color.drip.coral : Color.drip.divider)
                                .frame(height: 2)
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 26)
        .padding(.bottom, 4)
    }

    // MARK: Mode nav — Current · Calendar · History

    private var trainModeNav: some View {
        HStack(spacing: 0) {
            ForEach(TrainMode.allCases, id: \.self) { m in
                let on = mode == m
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { mode = m }
                } label: {
                    Text(m.rawValue.uppercased())
                        .font(.dripEyebrow(11.5)).tracking(2.0)
                        .foregroundStyle(on ? Color.drip.coral : Color.drip.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(on ? Color.drip.coral : Color.drip.divider)
                                .frame(height: 2)
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: 4 · Volume by intensity

    @ViewBuilder
    private var volumeByIntensity: some View {
        switch vm.scope {
        case .week:  weekVolumeSection
        case .month: monthVolumeSection
        case .block: blockVolumeSection
        }
    }

    private var weekVolumeSection: some View {
        let days = vm.dayVolumes()
        let maxMi = max(1, days.map { $0.split.total }.max() ?? 1)
        return section {
            sectionHead("VOLUME · BY INTENSITY", trailing: "MI",
                        onExpand: { route = .volume(.intensity) })
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(days) { d in
                    VolumeBar(split: d.split, maxMiles: maxMi,
                              isRest: d.isRest, isFuture: d.isFuture, height: 120)
                }
            }
            .frame(height: 120)
            .padding(.top, 4)
            HStack(spacing: 8) {
                ForEach(days) { d in
                    Text(d.label).font(.dripEyebrow(9)).tracking(0.6)
                        .foregroundStyle(Color.drip.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 7)
            intensityLegend(showUpcoming: true)
        }
    }

    private var monthVolumeSection: some View {
        let weeks = vm.weekVolumes()
        let avg = vm.rollingFourWeekAverage()
        let maxMi = max(1, weeks.map { $0.split.total }.max() ?? 1)
        return Group {
            section {
                sectionHead("VOLUME · BY INTENSITY", trailing: "MI",
                            onExpand: { route = .volume(.intensity) })
                ZStack(alignment: .bottom) {
                    HStack(alignment: .bottom, spacing: 10) {
                        ForEach(weeks) { w in
                            VolumeBar(split: w.split, maxMiles: maxMi,
                                      isRest: false, isFuture: false,
                                      hatched: w.inProgress, height: 120)
                        }
                    }
                    RollingAverageLine(values: avg, maxMiles: maxMi)
                        .frame(height: 120)
                }
                .frame(height: 120)
                .padding(.top, 4)
                HStack(spacing: 10) {
                    ForEach(weeks) { w in
                        Text(w.label + (w.inProgress ? "*" : ""))
                            .font(.dripEyebrow(8.5)).tracking(0.4)
                            .foregroundStyle(Color.drip.textTertiary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, 7)
                intensityLegend(showUpcoming: false, showAvg: true)
            }
            easyPaceTrendSection
        }
    }

    @ViewBuilder
    private var easyPaceTrendSection: some View {
        let pts = vm.easyPaceTrend()
        if pts.count >= 2 {
            section {
                sectionHead("EASY PACE · TREND", trailing: vm.easyPaceDelta() ?? "", trailingAccent: true)
                EasyPaceTrendChart(points: pts)
                    .frame(height: 110)
                    .padding(.top, 4)
            }
        }
    }

    private var blockVolumeSection: some View {
        let stats = vm.blockStats()
        let weeks = vm.weekVolumes()
        let maxMi = max(1, weeks.map { $0.split.total }.max() ?? 1)
        return section {
            sectionHead(stats.label, trailing: "", onExpand: { route = .volume(.intensity) })
            HStack(spacing: 0) {
                blockStat(vm.formatMiles(stats.blockMiles), "Block MI")
                statDivider
                blockStat(vm.formatMiles(stats.avgWeek), "Avg Week")
                statDivider
                blockStat(vm.formatMiles(stats.peakWeek), "Peak Week")
                statDivider
                blockStat(vm.formatMiles(stats.longRun), "Long Run")
            }
            .overlay(Rectangle().fill(Color.drip.divider).frame(height: 1), alignment: .top)
            .overlay(Rectangle().fill(Color.drip.divider).frame(height: 1), alignment: .bottom)
            .padding(.vertical, 4)

            sectionHead("WEEKLY MILEAGE", trailing: "MI · % HARD").padding(.top, 10)
            ForEach(weeks) { w in
                WeeklyMileageRow(week: w, maxMiles: maxMi, formatMiles: vm.formatMiles)
            }
        }
    }

    private func blockStat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.dripStat(20)).foregroundStyle(Color.drip.textPrimary)
            Text(label.uppercased()).font(.dripEyebrow(8.5)).tracking(1.2)
                .foregroundStyle(Color.drip.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    // MARK: 5 · Mileage by day grid

    private var mileageByDay: some View {
        let weeks = vm.gridWeeks()
        // Shared bar scale across all weeks so a 14-mi long run reads tall
        // everywhere and weeks are comparable to each other.
        let maxMiles = max(1, weeks.flatMap { $0.cells }.map(\.miles).max() ?? 1)
        return section {
            sectionHead("MILEAGE · BY DAY", trailing: "TAP A DAY")
            // Column header M T W T F S S
            HStack(spacing: 3) {
                Color.clear.frame(width: 54)
                ForEach(Array(["M","T","W","T","F","S","S"].enumerated()), id: \.offset) { _, d in
                    Text(d).font(.dripEyebrow(8.5)).tracking(0.5)
                        .foregroundStyle(Color.drip.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 4)
            ForEach(weeks) { week in
                MileageSkylineRow(
                    week: week,
                    maxMiles: maxMiles,
                    expandedDay: Binding(
                        get: { if case .day(let d)? = route { return d } else { return nil } },
                        set: { route = $0.map { .day($0) } }
                    )
                ) { day in
                    route = .day(day)   // tap → open the Day analysis sheet
                }
            }
        }
    }

    // MARK: 6 · Easy / Hard

    private var easyHard: some View {
        let split = vm.easyHardSplit()
        return section {
            sectionHead("EASY / HARD · \(scopeLabelUpper)", trailing: "TARGET 80/20",
                        onExpand: { route = .volume(.easyHard) })
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    HStack(spacing: 0) {
                        Rectangle().fill(IntensityRamp.easy)
                            .frame(width: geo.size.width * CGFloat(split.easyPercent) / 100)
                        Rectangle().fill(IntensityRamp.threshold)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                    Rectangle().fill(Color.drip.textPrimary)
                        .frame(width: 2)
                        .offset(x: geo.size.width * 0.8 - 1)
                        .padding(.vertical, -5)
                }
            }
            .frame(height: 14)
            .padding(.top, 6)
            HStack {
                Text("\(split.easyPercent)% EASY").font(.dripEyebrow(10)).tracking(1.2)
                    .foregroundStyle(Color.drip.positive)
                Spacer()
                Text("\(split.hardPercent)% HARD").font(.dripEyebrow(10)).tracking(1.2)
                    .foregroundStyle(Color.drip.coral)
            }
            .padding(.top, 9)
        }
    }

    // MARK: 7 · Volume × Pace

    private var volumeByPace: some View {
        let bins = vm.paceHistogram()
        let markers = vm.paceMarkers()
        let hasData = bins.contains { $0.miles > 0 }
        return section {
            sectionHead("VOLUME × PACE · \(scopeLabelUpper)", trailing: "CURRENT FITNESS",
                        onExpand: { route = .volume(.pace) })
            if hasData {
                PaceHistogram(bins: bins, markers: markers,
                              slow: vm.axisSlowSeconds, fast: vm.axisFastSeconds)
                    .padding(.top, 54)   // gutter room for up to two stacked marker-label rows
                rampStrip
            } else {
                progressPlaceholder("Pace distribution needs logged runs with GPS pace data in this window.")
            }
        }
    }

    /// Universal blue pace ramp with the zone labels placed *within*
    /// the spectrum at their true (warped) axis positions — EASY on the
    /// pale end, MP at center, LT / MILE in the deep blues, FASTEST at
    /// the navy terminal. Positions mirror `PaceZoneScale`'s warp anchors.
    private var rampStrip: some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Self.paceAxisGradient)
                .frame(height: 13)
                .frame(maxWidth: .infinity)
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .topLeading) {
                    rampLabel("EASY")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    rampLabel("MP").position(x: w * 0.50, y: 6)
                    rampLabel("LT").position(x: w * 0.625, y: 6)
                    rampLabel("MILE").position(x: w * 0.75, y: 6)
                    rampLabel("FASTEST")
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .frame(height: 12)
        }
        .padding(.top, 16)
    }
    private func rampLabel(_ t: String) -> some View {
        Text(t).font(.dripEyebrow(9)).tracking(1.0).foregroundStyle(Color.drip.textTertiary)
    }

    /// The histogram x-axis is linear pace (8:00 → 4:30); this samples the
    /// shared `PaceZoneScale` along it so the legend's colours line up with the
    /// bars and match the workout rep charts.
    private static let paceAxisGradient: LinearGradient = {
        let slow = 480.0, fast = 270.0
        let stops = stride(from: 0.0, through: 1.0, by: 0.1).map { f -> Gradient.Stop in
            Gradient.Stop(color: PaceZoneScale.color(forPaceSec: slow - f * (slow - fast)), location: f)
        }
        return LinearGradient(gradient: Gradient(stops: stops), startPoint: .leading, endPoint: .trailing)
    }()

    // MARK: 8 · Felt vs Planned

    @ViewBuilder
    private var feltVsPlanned: some View {
        let rows = vm.feltVsPlanned()
        if !rows.isEmpty {
            section {
                sectionHead("EFFORT · FELT VS PLANNED", trailing: "HARD SESSIONS")
                ForEach(rows) { r in
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Text("\(TrainingAnalyticsViewModel.monthDayLabel(r.date)) · \(r.typeLabel)")
                                .font(.dripEyebrow(10)).tracking(1.0)
                                .foregroundStyle(Color.drip.textPrimary)
                            Spacer()
                            Text("FELT \(r.felt) · PLANNED \(r.planned)")
                                .font(.dripEyebrow(10)).tracking(1.0)
                                .foregroundStyle(r.matched ? Color.drip.positive : Color.drip.coral)
                        }
                        FeltScale(felt: r.felt, planned: r.planned, matched: r.matched)
                    }
                    .padding(.vertical, 13)
                    Hairline()
                }
            }
        }
    }

    // MARK: 9 · Goals (collapsed)

    @ViewBuilder
    private var goals: some View {
        if let g = vm.goals {
            DisclosureGroup {
                VStack(spacing: 0) {
                    goalRow("RACE GOAL", g.raceGoal)
                    goalRow("CURRENT FITNESS", g.currentFitness)
                    goalRow("GAP", g.gap, accent: true)
                    if let target = g.weeklyTarget { goalRow("WEEKLY TARGET", target) }
                    Text("Targets stay out of the way until you want them. The only place goal paces appear.")
                        .font(.system(size: 14, design: .serif).italic())
                        .foregroundStyle(Color.drip.textTertiary)
                        .padding(.top, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button { route = .editGoal } label: {
                        Text("ADJUST GOAL & TIME ↗")
                            .font(.dripEyebrow(10.5)).tracking(1.3)
                            .foregroundStyle(Color.drip.coral)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.top, 16)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 4)
                .padding(.bottom, 16)
            } label: {
                Text("GOALS & TARGETS · OPTIONAL")
                    .font(.dripEyebrow(10.5)).tracking(1.3)
                    .foregroundStyle(Color.drip.textPrimary)
            }
            .tint(Color.drip.textSecondary)
            .padding(.vertical, 16)
            .overlay(Rectangle().fill(Color.drip.divider).frame(height: 1), alignment: .top)
            .overlay(Rectangle().fill(Color.drip.divider).frame(height: 1), alignment: .bottom)
            .padding(.top, 34)
        } else {
            setGoalRow
        }
    }

    /// Empty state — no goal set yet (self-coached, no plan). Gives the
    /// athlete a way *in* to set a race + time. Eyebrow + plain-prose
    /// nudge + CTA, per the empty-state rule (no em-dash placeholders).
    private var setGoalRow: some View {
        Button { route = .editGoal } label: {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("GOALS & TARGETS · OPTIONAL")
                        .font(.dripEyebrow(10.5)).tracking(1.3)
                        .foregroundStyle(Color.drip.textPrimary)
                    Text("Set a race and goal time to anchor your paces.")
                        .font(.system(size: 14, design: .serif).italic())
                        .foregroundStyle(Color.drip.textTertiary)
                }
                Spacer()
                Text("SET GOAL ↗")
                    .font(.dripEyebrow(10.5)).tracking(1.3)
                    .foregroundStyle(Color.drip.coral)
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 16)
        .overlay(Rectangle().fill(Color.drip.divider).frame(height: 1), alignment: .top)
        .overlay(Rectangle().fill(Color.drip.divider).frame(height: 1), alignment: .bottom)
        .padding(.top, 34)
    }

    private func goalRow(_ label: String, _ value: String, accent: Bool = false) -> some View {
        HStack {
            Text(label).font(.dripEyebrow(10)).tracking(1.2)
                .foregroundStyle(Color.drip.textSecondary)
            Spacer()
            Text(value).font(.dripStat(13))
                .foregroundStyle(accent ? Color.drip.coral : Color.drip.textPrimary)
        }
        .padding(.vertical, 9)
    }

    // MARK: CURRENT · Today

    /// Today's session — plan-aware when the plan has something scheduled,
    /// a factual completed row once the run lands, and an honest empty
    /// state otherwise (hard rule #8: state the absence, say what fills it).
    @ViewBuilder private var todaySection: some View {
        let scheduled = planVM.allScheduledWorkouts.first {
            Calendar.current.isDateInToday($0.date)
        }
        let todayRun = vm.sessions(on: Date())
            .filter { $0.miles > 0 }
            .max(by: { $0.miles < $1.miles })

        section {
            sectionHead("TODAY · \(Self.weekdayFull(Date()))",
                        trailing: planVM.activePlan?.name.uppercased() ?? "")

            if let run = todayRun {
                completedRunLine(run, conditions: vm.conditions(on: Date()))
            } else if let s = scheduled, s.workoutType != .rest {
                plannedTodayCard(s)
            } else if scheduled?.workoutType == .rest {
                Text("Rest day on the plan.")
                    .font(.system(size: 14, design: .serif).italic())
                    .foregroundStyle(Color.drip.textTertiary)
            } else {
                Text("Nothing planned, nothing logged yet. Today's run lands here when it does.")
                    .font(.system(size: 14, design: .serif).italic())
                    .foregroundStyle(Color.drip.textTertiary)
            }
        }
    }

    /// The planned-workout card: type chip + distance in display serif,
    /// then the plan's own description, then the forecast when the daily
    /// weather cron has populated one. Facts only — no verdicts.
    private func plannedTodayCard(_ s: ScheduledWorkout) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                typeChip(for: s.workoutType)
                if let mi = s.workout?.totalDistanceMiles, mi > 0 {
                    Text("\(vm.formatMiles(mi)) mi")
                        .font(.dripDisplay(22))
                        .foregroundStyle(Color.drip.textPrimary)
                } else {
                    Text(s.workoutType.displayName)
                        .font(.dripDisplay(22))
                        .foregroundStyle(Color.drip.textPrimary)
                }
            }
            if let desc = s.workout?.description, !desc.isEmpty {
                Text(desc)
                    .font(.system(size: 13, design: .serif))
                    .foregroundStyle(Color.drip.textSecondary)
                    .lineLimit(3)
            }
            if let wx = s.weatherForecast {
                Text(forecastLine(wx))
                    .font(.dripEyebrow(9.5)).tracking(1.0)
                    .foregroundStyle(Color.drip.textTertiary)
            }
        }
    }

    private func forecastLine(_ wx: WorkoutForecast) -> String {
        var parts = ["FORECAST \(Int(wx.temperatureF.rounded()))°"]
        if let d = wx.dewPointF { parts.append("DP \(Int(d.rounded()))°") }
        if let c = wx.condition, !c.isEmpty { parts.append(c.uppercased()) }
        return parts.joined(separator: " · ")
    }

    // MARK: CURRENT · This week

    /// The week as day rows — every completed run with its conditions
    /// readout inline, planned days ahead when a plan exists, rest days
    /// named. Closes with the athlete's own fatigue words, verbatim.
    private var currentWeekSection: some View {
        let days = vm.dayVolumes()
        let hot = vm.hotRunCount()
        return section {
            sectionHead("THIS WEEK",
                        trailing: hot > 0 ? "\(hot) HOT RUN\(hot == 1 ? "" : "S")" : "")
            VStack(spacing: 0) {
                ForEach(days) { d in
                    dayRow(d)
                }
            }
            if let note = vm.weekMoodObservation() {
                Text(note)
                    .font(.system(size: 13, design: .serif).italic())
                    .foregroundStyle(Color.drip.textSecondary)
                    .padding(.top, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder private func dayRow(_ d: DayVolume) -> some View {
        let all = vm.sessions(on: d.date)
        let run = all.filter { $0.miles > 0 }.max(by: { $0.miles < $1.miles })
        let memo = all.first { $0.miles == 0 && ($0.pullQuote?.isEmpty == false) }
        let planned = planVM.allScheduledWorkouts.first {
            Calendar.current.isDate($0.date, inSameDayAs: d.date) && $0.workoutType != .rest
        }
        let isToday = Calendar.current.isDateInToday(d.date)

        if let run {
            Button { route = .day(d.date) } label: {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 10) {
                        dayLabel(d.label, accent: isToday)
                        typeChip(run.typeLabel, bucket: run.bucket)
                        Text("\(vm.formatMiles(run.miles)) mi")
                            .font(.dripDisplay(16))
                            .foregroundStyle(Color.drip.textPrimary)
                        Spacer()
                        if let pace = run.pace, !pace.isEmpty {
                            Text(pace)
                                .font(.dripStat(13))
                                .foregroundStyle(Color.drip.textPrimary)
                        }
                    }
                    let mood = vm.mood(on: d.date)
                    let readout = vm.conditions(on: d.date)?.readout
                    if mood != nil || readout != nil {
                        HStack(spacing: 8) {
                            if let mood { MoodBadge(mood: mood) }
                            if let readout {
                                Text(readout)
                                    .font(.dripEyebrow(9)).tracking(0.8)
                                    .foregroundStyle(Color.drip.textTertiary)
                            }
                        }
                        .padding(.leading, 42)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 12)
            Hairline()
        } else if let memo {
            // Voice memo with no run — the qualitative stream, verbatim.
            HStack(alignment: .center, spacing: 10) {
                dayLabel(d.label, accent: isToday)
                Text("\u{201C}\(memo.pullQuote ?? "")\u{201D}")
                    .font(.system(size: 13, design: .serif).italic())
                    .foregroundStyle(Color.drip.textSecondary)
                    .lineLimit(2)
                Spacer()
                if let mood = vm.mood(on: d.date) { MoodBadge(mood: mood) }
            }
            .padding(.vertical, 12)
            Hairline()
        } else if d.isFuture, let planned {
            // Upcoming planned day — dimmed, factual.
            HStack(spacing: 10) {
                dayLabel(d.label, accent: false)
                Text(plannedShortLine(planned))
                    .font(.dripEyebrow(10)).tracking(1.0)
                    .foregroundStyle(Color.drip.textTertiary)
                Spacer()
            }
            .padding(.vertical, 12)
            .opacity(0.7)
            Hairline()
        } else if !d.isFuture {
            HStack(spacing: 10) {
                dayLabel(d.label, accent: isToday)
                Text("Rest")
                    .font(.system(size: 14, design: .serif).italic())
                    .foregroundStyle(Color.drip.textTertiary)
                Spacer()
                // A rest-day check-in still carries how they felt.
                if let mood = vm.mood(on: d.date) { MoodBadge(mood: mood) }
            }
            .padding(.vertical, 12)
            Hairline()
        }
        // Future day with nothing planned renders nothing — no placeholder.
    }

    private func dayLabel(_ label: String, accent: Bool) -> some View {
        Text(label)
            .font(.dripEyebrow(9.5)).tracking(0.8)
            .foregroundStyle(accent ? Color.drip.coral : Color.drip.textTertiary)
            .frame(width: 32, alignment: .leading)
    }

    private func plannedShortLine(_ s: ScheduledWorkout) -> String {
        var line = s.workoutType.displayName.uppercased()
        if let mi = s.workout?.totalDistanceMiles, mi > 0 {
            line += " · \(vm.formatMiles(mi)) MI"
        }
        return line
    }

    // MARK: CALENDAR · plan (folded in from the old Plan tab, Phase A)

    /// The plan block: this week's planned sessions when a plan is active,
    /// with the full plan surface (and its import / join-coach actions)
    /// one push away. No plan → empty state with a way in (hard rule #8).
    /// `activePlan == nil` is a first-class state, not a failure mode.
    @ViewBuilder private var planSection: some View {
        if let plan = planVM.activePlan {
            VStack(alignment: .leading, spacing: 0) {
                sectionHead("THE PLAN · \(plan.name.uppercased())", trailing: "")
                ForEach(thisWeeksPlanned) { s in
                    HStack(spacing: 10) {
                        dayLabel(TrainingAnalyticsViewModel.weekdayLabel(s.date),
                                 accent: Calendar.current.isDateInToday(s.date))
                        if s.workoutType == .rest {
                            Text("Rest")
                                .font(.system(size: 14, design: .serif).italic())
                                .foregroundStyle(Color.drip.textTertiary)
                        } else {
                            Text(plannedShortLine(s))
                                .font(.dripEyebrow(10)).tracking(1.0)
                                .foregroundStyle(Color.drip.textSecondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 10)
                    Hairline()
                }
                NavigationLink {
                    TrainingPlanView()
                } label: {
                    Text("OPEN FULL PLAN ↗")
                        .font(.dripEyebrow(10.5)).tracking(1.3)
                        .foregroundStyle(Color.drip.coral)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.top, 14)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
        } else {
            NavigationLink {
                TrainingPlanView()
            } label: {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("THE PLAN · OPTIONAL")
                            .font(.dripEyebrow(10.5)).tracking(1.3)
                            .foregroundStyle(Color.drip.textPrimary)
                        Text("No plan yet. Import one, or join your coach's — planned days land on this calendar.")
                            .font(.system(size: 14, design: .serif).italic())
                            .foregroundStyle(Color.drip.textTertiary)
                    }
                    Spacer()
                    Text("SET UP ↗")
                        .font(.dripEyebrow(10.5)).tracking(1.3)
                        .foregroundStyle(Color.drip.coral)
                }
            }
            .buttonStyle(.plain)
        }
    }

    /// Planned sessions in the current calendar week, in date order.
    private var thisWeeksPlanned: [ScheduledWorkout] {
        let cal = Calendar.current
        return planVM.allScheduledWorkouts
            .filter { cal.isDate($0.date, equalTo: Date(), toGranularity: .weekOfYear) }
            .sorted { $0.date == $1.date ? $0.session < $1.session : $0.date < $1.date }
    }

    // MARK: CURRENT · chips

    /// Completed-run chip — rides the intensity bucket's ramp color.
    /// Blue is pace-only (three-palette rule); the pale Easy stop takes
    /// ink text for contrast, deeper stops take paper.
    private func typeChip(_ label: String, bucket: IntensityBucket) -> some View {
        zoneChip(label, color: bucket.color, darkText: bucket == .easy)
    }

    /// Planned-workout chip. Running types map onto the pace ramp;
    /// non-running work (strength, cross-training) stays off the pace
    /// palette entirely — neutral well, ink text.
    @ViewBuilder private func typeChip(for type: ScheduledWorkoutType) -> some View {
        switch type {
        case .easy, .recovery, .strides, .longRun:
            zoneChip(type.displayName.uppercased(), color: IntensityRamp.easy, darkText: true)
        case .progression:
            zoneChip(type.displayName.uppercased(), color: IntensityRamp.aerobic, darkText: false)
        case .tempo:
            zoneChip(type.displayName.uppercased(), color: IntensityRamp.threshold, darkText: false)
        case .intervals:
            zoneChip(type.displayName.uppercased(), color: IntensityRamp.colors[7], darkText: false)
        case .race:
            zoneChip(type.displayName.uppercased(), color: IntensityRamp.colors[9], darkText: false)
        case .strength, .crossTraining, .rest:
            zoneChip(type.displayName.uppercased(), color: Color.drip.divider, darkText: true)
        }
    }

    private func zoneChip(_ label: String, color: Color, darkText: Bool) -> some View {
        Text(label)
            .font(.dripEyebrow(9)).tracking(0.8)
            .foregroundStyle(darkText ? Color.drip.textPrimary : Color.drip.background)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 4).fill(color))
    }

    /// Completed run line used by the Today section — same anatomy as a
    /// week day-row, minus the day label.
    private func completedRunLine(_ run: SessionDetail, conditions: RunConditions?) -> some View {
        Button { route = .day(Date()) } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    typeChip(run.typeLabel, bucket: run.bucket)
                    Text("\(vm.formatMiles(run.miles)) mi")
                        .font(.dripDisplay(22))
                        .foregroundStyle(Color.drip.textPrimary)
                    Spacer()
                    if let pace = run.pace, !pace.isEmpty {
                        Text(pace)
                            .font(.dripStat(14))
                            .foregroundStyle(Color.drip.textPrimary)
                    }
                }
                let mood = vm.mood(on: Date())
                if mood != nil || conditions?.readout != nil {
                    HStack(spacing: 8) {
                        if let mood { MoodBadge(mood: mood) }
                        if let readout = conditions?.readout {
                            Text(readout)
                                .font(.dripEyebrow(9.5)).tracking(1.0)
                                .foregroundStyle(Color.drip.textTertiary)
                        }
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private static func weekdayFull(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "EEEE"
        return f.string(from: date).uppercased()
    }

    // MARK: Shared chrome

    private var scopeLabelUpper: String {
        switch vm.scope {
        case .week:  return "THIS WEEK"
        case .month: return "LAST 30 DAYS"
        case .block: return "THIS BLOCK"
        }
    }

    private func section<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(.top, 30)
    }

    private func sectionHead(_ title: String, trailing: String, trailingAccent: Bool = false,
                             onExpand: (() -> Void)? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.dripEyebrow(11)).tracking(1.3)
                .foregroundStyle(Color.drip.textSecondary)
            Spacer()
            if !trailing.isEmpty {
                Text(trailing).font(.dripEyebrow(10)).tracking(1.2)
                    .foregroundStyle(trailingAccent ? Color.drip.coral : Color.drip.textTertiary)
            }
            if let onExpand {
                Button(action: onExpand) {
                    Text("EXPAND ↗").font(.dripEyebrow(9.5)).tracking(1.1)
                        .foregroundStyle(Color.drip.coral)
                }
                .buttonStyle(.plain)
                .padding(.leading, 12)
            }
        }
        .padding(.bottom, 14)
    }

    private func intensityLegend(showUpcoming: Bool, showAvg: Bool = false) -> some View {
        HStack(spacing: 16) {
            legendSwatch(IntensityRamp.easy, "EASY")
            legendSwatch(IntensityRamp.aerobic, "AEROBIC")
            legendSwatch(IntensityRamp.threshold, "THRESHOLD+")
            if showUpcoming {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 1)
                        .stroke(Color.drip.textTertiary, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                        .frame(width: 9, height: 9)
                    Text("UPCOMING").font(.dripEyebrow(8.5)).tracking(0.8)
                        .foregroundStyle(Color.drip.textTertiary)
                }
            }
            if showAvg {
                Text("— 4-WK AVG").font(.dripEyebrow(8.5)).tracking(0.8)
                    .foregroundStyle(Color.drip.textTertiary)
            }
            Spacer()
        }
        .padding(.top, 14)
    }

    private func legendSwatch(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 9, height: 9)
            Text(label).font(.dripEyebrow(8.5)).tracking(0.8)
                .foregroundStyle(Color.drip.textTertiary)
        }
    }

    private func progressPlaceholder(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, design: .serif).italic())
            .foregroundStyle(Color.drip.textTertiary)
            .padding(.top, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Volume bar (stacked easy/aerobic/threshold)

private struct VolumeBar: View {
    let split: ZoneSplit
    let maxMiles: Double
    var isRest: Bool = false
    var isFuture: Bool = false
    var hatched: Bool = false
    let height: CGFloat

    var body: some View {
        VStack(spacing: 5) {
            if !isRest && !isFuture && split.total > 0 {
                Text(String(format: "%.1f", split.total))
                    .font(.dripEyebrow(9)).foregroundStyle(Color.drip.textTertiary)
            } else {
                Text(isRest ? "—" : " ").font(.dripEyebrow(9))
                    .foregroundStyle(Color.drip.textTertiary)
            }
            Spacer(minLength: 0)
            barBody
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }

    @ViewBuilder
    private var barBody: some View {
        if isFuture {
            RoundedRectangle(cornerRadius: 1)
                .stroke(Color.drip.textTertiary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .frame(height: 34)
        } else if isRest {
            Rectangle().fill(Color.drip.textTertiary).frame(height: 3)
        } else {
            let barH = max(3, CGFloat(split.total / maxMiles) * (height - 20))
            VStack(spacing: 0) {
                segment(split.threshold, IntensityRamp.threshold, barH)
                segment(split.aerobic, IntensityRamp.aerobic, barH)
                segment(split.easy, IntensityRamp.easy, barH)
            }
            .frame(height: barH)
            .clipShape(RoundedRectangle(cornerRadius: 1))
            .overlay {
                if hatched {
                    HatchOverlay().clipShape(RoundedRectangle(cornerRadius: 1))
                }
            }
        }
    }

    /// Proportional stacked segment — explicit height = barH × (miles / total).
    @ViewBuilder
    private func segment(_ miles: Double, _ color: Color, _ barH: CGFloat) -> some View {
        if miles > 0, split.total > 0 {
            color.frame(height: barH * CGFloat(miles / split.total))
        }
    }
}

private struct HatchOverlay: View {
    var body: some View {
        GeometryReader { geo in
            Path { p in
                let step: CGFloat = 5
                var x: CGFloat = -geo.size.height
                while x < geo.size.width {
                    p.move(to: CGPoint(x: x, y: geo.size.height))
                    p.addLine(to: CGPoint(x: x + geo.size.height, y: 0))
                    x += step
                }
            }
            .stroke(Color.drip.background.opacity(0.7), lineWidth: 1.5)
        }
    }
}

// MARK: - Rolling average line (month)

private struct RollingAverageLine: View {
    let values: [Double?]
    let maxMiles: Double

    var body: some View {
        GeometryReader { geo in
            let pts = points(in: geo.size)
            Path { p in
                guard let first = pts.first else { return }
                p.move(to: first)
                for pt in pts.dropFirst() { p.addLine(to: pt) }
            }
            .stroke(Color.drip.textPrimary, style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
            ForEach(Array(pts.enumerated()), id: \.offset) { _, pt in
                Circle().fill(Color.drip.textPrimary).frame(width: 4, height: 4).position(pt)
            }
        }
    }

    private func points(in size: CGSize) -> [CGPoint] {
        let n = values.count
        guard n > 0 else { return [] }
        let usable = size.height - 20
        return values.enumerated().compactMap { (i, v) in
            guard let v else { return nil }
            let x = size.width * (CGFloat(i) + 0.5) / CGFloat(n)
            let y = (size.height - 3) - CGFloat(v / maxMiles) * usable
            return CGPoint(x: x, y: y)
        }
    }
}

// MARK: - Easy pace trend chart

private struct EasyPaceTrendChart: View {
    let points: [EasyPacePoint]

    var body: some View {
        GeometryReader { geo in
            let paces = points.map { $0.avgPaceSeconds }
            let lo = (paces.min() ?? 0) - 8
            let hi = (paces.max() ?? 1) + 8
            let pts = coords(in: geo.size, lo: lo, hi: hi)
            ZStack {
                Path { p in
                    guard let first = pts.first else { return }
                    p.move(to: first)
                    for pt in pts.dropFirst() { p.addLine(to: pt) }
                }
                .stroke(Color.drip.textPrimary, lineWidth: 2)
                ForEach(Array(pts.enumerated()), id: \.offset) { i, pt in
                    Circle().fill(Color.drip.textPrimary).frame(width: 7, height: 7).position(pt)
                    Text(TrainingAnalyticsViewModel.formatPaceMMSS(points[i].avgPaceSeconds))
                        .font(.dripEyebrow(8.5))
                        .foregroundStyle(i == pts.count - 1 ? Color.drip.textPrimary : Color.drip.textTertiary)
                        .position(x: pt.x, y: geo.size.height - 6)
                }
            }
        }
    }

    // Faster pace (lower seconds) plots higher.
    private func coords(in size: CGSize, lo: Double, hi: Double) -> [CGPoint] {
        let span = max(1, hi - lo)
        let usable = size.height - 24
        return points.enumerated().map { (i, pt) in
            let x = size.width * (CGFloat(i) + 0.5) / CGFloat(points.count)
            let frac = (pt.avgPaceSeconds - lo) / span     // 0 fast(top) … 1 slow(bottom)
            let y = 8 + CGFloat(frac) * usable
            return CGPoint(x: x, y: y)
        }
    }
}

// MARK: - Weekly mileage row (block)

private struct WeeklyMileageRow: View {
    let week: WeekVolume
    let maxMiles: Double
    let formatMiles: (Double) -> String

    var body: some View {
        let total = week.split.total
        let hardPct = total > 0 ? Int((week.split.hardMiles / total * 100).rounded()) : 0
        return HStack(spacing: 14) {
            Text(week.label).font(.dripEyebrow(10)).tracking(1.0)
                .foregroundStyle(Color.drip.textTertiary)
                .frame(width: 64, alignment: .leading)
            GeometryReader { geo in
                HStack(spacing: 0) {
                    Rectangle().fill(week.inProgress ? IntensityRamp.easy.opacity(0.5) : IntensityRamp.easy)
                        .frame(width: geo.size.width * CGFloat(week.split.easy / maxMiles))
                    Rectangle().fill(IntensityRamp.threshold)
                        .frame(width: geo.size.width * CGFloat(week.split.hardMiles / maxMiles))
                    Spacer(minLength: 0)
                }
                .frame(height: 10)
                .background(Color.drip.paperDeep)
                .clipShape(RoundedRectangle(cornerRadius: 1))
            }
            .frame(height: 10)
            Text(formatMiles(total)).font(.dripStat(12))
                .foregroundStyle(Color.drip.textPrimary)
                .frame(width: 54, alignment: .trailing)
            Text(week.inProgress ? "TO DATE" : "\(hardPct)% HARD")
                .font(.dripEyebrow(9.5))
                .foregroundStyle(hardPct >= 20 && !week.inProgress ? Color.drip.coral : Color.drip.textTertiary)
                .frame(width: 64, alignment: .trailing)
        }
        .padding(.vertical, 14)
        .overlay(Rectangle().fill(Color.drip.divider).frame(height: 1), alignment: .bottom)
    }
}

// MARK: - Pace histogram

private struct PaceHistogram: View {
    let bins: [PaceBin]
    let markers: [PaceMarker]
    let slow: Double
    let fast: Double

    private let plotH: CGFloat = 110

    var body: some View {
        let maxMi = max(0.1, bins.map { $0.miles }.max() ?? 0.1)
        let axisTop = TrainingAnalyticsViewModel.niceMilesTop(maxMi)
        HStack(alignment: .top, spacing: 8) {
            // Y axis — miles. Three ticks (top / mid / 0) aligned to the
            // gridlines in the plot; unit called out on the top tick.
            VStack(alignment: .trailing, spacing: 0) {
                yTick("\(TrainingAnalyticsViewModel.fmtMiles(axisTop)) MI")
                Spacer(minLength: 0)
                yTick(TrainingAnalyticsViewModel.fmtMiles(axisTop / 2))
                Spacer(minLength: 0)
                yTick("0")
            }
            .frame(width: 30, height: plotH)

            VStack(spacing: 7) {
                ZStack(alignment: .bottom) {
                    // Gridlines at the top tick and the midpoint; the
                    // baseline is the divider overlay below.
                    Rectangle().fill(Color.drip.divider.opacity(0.5)).frame(height: 1)
                        .frame(maxHeight: .infinity, alignment: .top)
                    Rectangle().fill(Color.drip.divider.opacity(0.5)).frame(height: 1)
                        .frame(maxHeight: .infinity, alignment: .center)

                    HStack(alignment: .bottom, spacing: 3) {
                        ForEach(bins) { bin in
                            // Colour each bar by its pace through the shared
                            // PaceZoneScale, so a given pace reads the same
                            // colour here as on the workout rep charts.
                            let step = (slow - fast) / Double(max(bins.count, 1))
                            let centerPace = slow - (Double(bin.index) + 0.5) * step
                            RoundedRectangle(cornerRadius: 1)
                                .fill(bin.miles > 0 ? PaceZoneScale.color(forPaceSec: centerPace) : Color.clear)
                                .frame(height: max(bin.miles > 0 ? 2 : 0, CGFloat(bin.miles / axisTop) * plotH))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: plotH)
                    // markers overlay bars, labels reaching up into the gutter.
                    // Close paces (e.g. MP 5:45 / LT 5:30) would collide on a
                    // single label row, so each label is assigned to one of two
                    // stacked rows via greedy first-fit — the lower row tucks
                    // just above the chart, the upper row lifts higher into the
                    // gutter. Mirrors the anchor-row logic in
                    // PaceVolumeSpectrumChart.
                    GeometryReader { geo in
                        let rows = markerRows(width: geo.size.width)
                        ForEach(Array(markers.enumerated()), id: \.element.id) { idx, m in
                            let x = geo.size.width * CGFloat(m.fraction(slow: slow, fast: fast))
                            marker(m, x: x, height: geo.size.height, row: rows[idx])
                        }
                    }
                }
                .frame(height: plotH)
                .overlay(Rectangle().fill(Color.drip.divider).frame(height: 1), alignment: .bottom)
                // Numeric pace axis removed — the gradient ramp strip below
                // the chart is the single x-axis + legend (zone names align
                // with the bar colours). On-chart MP/LT/5K markers give the
                // absolute pace anchors.
            }
        }
    }

    private func yTick(_ text: String) -> some View {
        Text(text)
            .font(.dripEyebrow(8.5)).tracking(0.5)
            .monospacedDigit()
            .foregroundStyle(Color.drip.textTertiary)
    }

    // Approximate rendered width of one marker label block. Two marker
    // labels closer than this on the x axis are pushed onto different rows.
    private let markerLabelWidth: CGFloat = 40
    // Vertical lift per stacked row. Row 0 sits at the base offset; each
    // higher row lifts one step further into the gutter.
    private let markerRowStep: CGFloat = 20
    private let markerBaseOffset: CGFloat = -30

    /// Greedy first-fit row assignment for the pace markers. Walking the
    /// markers in axis order, each label takes the lowest row whose last
    /// placed label is at least `markerLabelWidth` away; if every row is
    /// crowded (very tight cluster) it falls back to the row furthest from
    /// its last placement. Two rows are enough for the realistic MP/LT/5K
    /// case; the section reserves gutter room for both (see `.padding(.top)`
    /// on the histogram in `volumeByPace`).
    private func markerRows(width: CGFloat) -> [Int] {
        var lastX: [CGFloat?] = [nil, nil]   // two stacked rows
        var out: [Int] = []
        out.reserveCapacity(markers.count)
        for m in markers {
            let x = width * CGFloat(m.fraction(slow: slow, fast: fast))
            var assigned = -1
            for row in 0..<lastX.count {
                if let lx = lastX[row] {
                    if abs(x - lx) >= markerLabelWidth { assigned = row; break }
                } else {
                    assigned = row; break
                }
            }
            if assigned < 0 {
                var best = 0
                var bestDist: CGFloat = -1
                for row in 0..<lastX.count {
                    let d = abs(x - (lastX[row] ?? -1000))
                    if d > bestDist { bestDist = d; best = row }
                }
                assigned = best
            }
            lastX[assigned] = x
            out.append(assigned)
        }
        return out
    }

    private func marker(_ m: PaceMarker, x: CGFloat, height: CGFloat, row: Int) -> some View {
        ZStack(alignment: .top) {
            Rectangle().fill(Color.drip.divider).frame(width: 1).frame(height: height)
            VStack(spacing: 1) {
                Text(m.label).font(.dripEyebrow(9).weight(.bold)).foregroundStyle(m.color)
                Text(TrainingAnalyticsViewModel.formatPaceMMSS(m.paceSeconds))
                    .font(.dripEyebrow(8.5)).foregroundStyle(Color.drip.textTertiary)
            }
            .fixedSize()
            .offset(y: markerBaseOffset - CGFloat(row) * markerRowStep)
        }
        .frame(width: 40)
        .position(x: x, y: height / 2)
    }
}

// MARK: - Felt scale

private struct FeltScale: View {
    let felt: Int
    let planned: Int
    let matched: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.drip.divider).frame(height: 4)
                Rectangle().fill(Color.drip.textTertiary)
                    .frame(width: 2, height: 12)
                    .offset(x: geo.size.width * CGFloat(planned) / 10 - 1, y: 0)
                Circle().fill(matched ? Color.drip.positive : Color.drip.coral)
                    .frame(width: 12, height: 12)
                    .offset(x: geo.size.width * CGFloat(felt) / 10 - 6, y: 0)
            }
            .frame(height: 12)
        }
        .frame(height: 12)
    }
}
