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
                PlateStrip(surface: "TRAINING · ANALYSIS", fig: "FIG. 1")
                    .padding(.bottom, 20)

                if vm.isLoading && !vm.hasLoaded {
                    loadingState
                } else {
                    header
                    WorkoutsAndRepsSection()
                    summary
                    scopeToggle
                    volumeByIntensity
                    mileageByDay
                    EditorialRule().padding(.vertical, 22)
                    easyHard
                    volumeByPace
                    feltVsPlanned
                    goals
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(vm.scopeDateline())
                .font(.dripEyebrow(10.5)).tracking(1.6)
                .foregroundStyle(Color.drip.textSecondary)
            Text("Your training.")
                .font(.dripDisplay(34))
                .foregroundStyle(Color.drip.textPrimary)
                .padding(.top, 2)
            Text(vm.headlineInsight())
                .font(.system(size: 16.5, design: .serif).italic())
                .foregroundStyle(Color.drip.textPrimary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 2 · Summary stats

    private var summary: some View {
        let s = vm.summary()
        return HStack(spacing: 0) {
            statCell(vm.formatMiles(s.miles), "Miles")
            statDivider
            statCell("\(s.runs)", "Runs")
            statDivider
            statCell(TrainingAnalyticsViewModel.formatDurationHours(s.durationMinutes), "Hours")
            statDivider
            statCell("\(s.easyPercent)%", "Easy")
        }
        .overlay(Rectangle().fill(Color.drip.divider).frame(height: 1), alignment: .top)
        .overlay(Rectangle().fill(Color.drip.divider).frame(height: 1), alignment: .bottom)
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
                if let delta = vm.easyPaceDelta(), delta.hasPrefix("▼") {
                    Text("Same effort, faster per mile than at the start of the window. That's fitness.")
                        .font(.system(size: 15, design: .serif).italic())
                        .foregroundStyle(Color.drip.textPrimary)
                        .padding(.top, 12)
                }
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
                    .padding(.top, 34)
                rampStrip
                if let insight = paceInsight(bins: bins, markers: markers) {
                    Text(insight)
                        .font(.system(size: 15, design: .serif).italic())
                        .foregroundStyle(Color.drip.textPrimary)
                        .padding(.top, 14)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                progressPlaceholder("Pace distribution needs logged runs with GPS pace data in this window.")
            }
        }
    }

    private func paceInsight(bins: [PaceBin], markers: [PaceMarker]) -> String? {
        guard let peak = bins.max(by: { $0.miles < $1.miles }), peak.miles > 0 else { return nil }
        let step = (vm.axisSlowSeconds - vm.axisFastSeconds) / Double(bins.count)
        let peakPace = vm.axisSlowSeconds - (Double(peak.index) + 0.5) * step
        return "Your miles pile up around \(TrainingAnalyticsViewModel.formatPaceMMSS(peakPace)) — easy work carrying the volume, with the spikes sitting on your current workout paces."
    }

    private var rampStrip: some View {
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                ForEach(Array(IntensityRamp.colors.enumerated()), id: \.offset) { _, c in
                    Rectangle().fill(c).frame(maxWidth: .infinity)
                }
            }
            .frame(height: 13)
            .clipShape(RoundedRectangle(cornerRadius: 2))
            HStack {
                rampLabel("EASY"); Spacer(); rampLabel("MP"); Spacer()
                rampLabel("LT"); Spacer(); rampLabel("MILE")
            }
        }
        .padding(.top, 16)
    }
    private func rampLabel(_ t: String) -> some View {
        Text(t).font(.dripEyebrow(9)).tracking(1.0).foregroundStyle(Color.drip.textTertiary)
    }

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
                if let insight = vm.feltInsight() {
                    Text(insight)
                        .font(.system(size: 15, design: .serif).italic())
                        .foregroundStyle(Color.drip.textPrimary)
                        .padding(.top, 16)
                        .fixedSize(horizontal: false, vertical: true)
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
                            RoundedRectangle(cornerRadius: 1)
                                .fill(bin.miles > 0 ? bin.color : Color.clear)
                                .frame(height: max(bin.miles > 0 ? 2 : 0, CGFloat(bin.miles / axisTop) * plotH))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: plotH)
                    // markers overlay bars, labels reaching up into the gutter
                    GeometryReader { geo in
                        ForEach(markers) { m in
                            let x = geo.size.width * CGFloat(m.fraction(slow: slow, fast: fast))
                            marker(m, x: x, height: geo.size.height)
                        }
                    }
                }
                .frame(height: plotH)
                .overlay(Rectangle().fill(Color.drip.divider).frame(height: 1), alignment: .bottom)
                HStack {
                    ForEach(["8:00","7:00","6:00","5:00","4:30"], id: \.self) { t in
                        Text(t).font(.dripEyebrow(9)).foregroundStyle(Color.drip.textTertiary)
                        if t != "4:30" { Spacer() }
                    }
                }
            }
        }
    }

    private func yTick(_ text: String) -> some View {
        Text(text)
            .font(.dripEyebrow(8.5)).tracking(0.5)
            .monospacedDigit()
            .foregroundStyle(Color.drip.textTertiary)
    }

    private func marker(_ m: PaceMarker, x: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .top) {
            Rectangle().fill(Color.drip.divider).frame(width: 1).frame(height: height)
            VStack(spacing: 1) {
                Text(m.label).font(.dripEyebrow(9).weight(.bold)).foregroundStyle(m.color)
                Text(TrainingAnalyticsViewModel.formatPaceMMSS(m.paceSeconds))
                    .font(.dripEyebrow(8.5)).foregroundStyle(Color.drip.textTertiary)
            }
            .fixedSize()
            .offset(y: -30)
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
