//
//  VolumeDetailSheet.swift
//  RunningLog
//
//  Full-screen expansion of a Training-tab volume chart. Opened from the
//  EXPAND ↗ affordance on each chart header. Gives the chart room for a
//  proper y-axis (miles), gridlines, and per-bar value labels — then a
//  tappable value table where each row is a bar/zone/pace-bin: tap it to
//  see the exact miles and the runs that built it, each deep-linking into
//  the full per-workout analysis.
//
//  Data comes entirely from `TrainingAnalyticsViewModel` (detailBars,
//  sessions(forKey:)) so the expanded view stays consistent with the
//  inline charts and the rest of the tab.
//

import SwiftUI

struct VolumeDetailSheet: View {
    let vm: TrainingAnalyticsViewModel
    let kind: VolumeChartKind

    @Environment(\.dismiss) private var dismiss
    @State private var expandedBarId: UUID?
    @State private var analysisTarget: WorkoutAnalysisTarget?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    DetailBarChart(bars: bars,
                                   isPaceAxis: kind.isPaceAxis,
                                   selectedId: expandedBarId,
                                   onTap: toggle)
                        .padding(.top, 8)

                    EditorialRule().padding(.vertical, 22)

                    HStack {
                        Text(kind.isPaceAxis ? "BY PACE BAND" : "BY \(kind == .easyHard ? "ZONE" : "PERIOD")")
                            .font(.dripEyebrow(10.5)).tracking(1.3)
                            .foregroundStyle(Color.drip.textSecondary)
                        Spacer()
                        Text("TAP A ROW FOR RUNS")
                            .font(.dripEyebrow(9)).tracking(1.1)
                            .foregroundStyle(Color.drip.textTertiary)
                    }
                    .padding(.bottom, 6)

                    valueTable

                    if kind == .easyHard, let mp = vm.marathonPaceSec {
                        Text("Pace bands anchored to current fitness · MP \(TrainingAnalyticsViewModel.formatPaceMMSS(mp)) /MI. Easy keeps the aerobic base; threshold+ is the sharp end.")
                            .font(.system(size: 13, design: .serif).italic())
                            .foregroundStyle(Color.drip.textTertiary)
                            .padding(.top, 16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 40)
            }
            .background(Color.drip.background.ignoresSafeArea())
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .workoutAnalysisSheet($analysisTarget)
        }
    }

    // MARK: Data

    private var bars: [TrainingAnalyticsViewModel.VolumeDetailBar] {
        vm.detailBars(for: kind)
    }
    private var total: Double { max(0.001, bars.reduce(0) { $0 + $1.miles }) }

    private func toggle(_ bar: TrainingAnalyticsViewModel.VolumeDetailBar) {
        withAnimation(.easeInOut(duration: 0.18)) {
            expandedBarId = expandedBarId == bar.id ? nil : bar.id
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(vm.scopeDateline())
                .font(.dripEyebrow(10.5)).tracking(1.6)
                .foregroundStyle(Color.drip.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(TrainingAnalyticsViewModel.fmtMiles(vm.scopedTotalMiles()))
                    .font(.dripDisplay(34))
                    .foregroundStyle(Color.drip.textPrimary)
                Text("MILES TOTAL")
                    .font(.dripEyebrow(10)).tracking(1.3)
                    .foregroundStyle(Color.drip.textTertiary)
            }
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Value table

    private var valueTable: some View {
        // Pace bins are mostly empty — only list bands with miles. Other
        // kinds list every bar so a zero week/zone still reads.
        let rows = kind.isPaceAxis ? bars.filter { $0.miles > 0 } : bars
        return VStack(spacing: 0) {
            ForEach(rows) { bar in
                VStack(spacing: 0) {
                    Button { toggle(bar) } label: { barRow(bar) }
                        .buttonStyle(.plain)
                    if expandedBarId == bar.id {
                        runList(for: bar)
                    }
                }
                Hairline()
            }
        }
    }

    private func barRow(_ bar: TrainingAnalyticsViewModel.VolumeDetailBar) -> some View {
        let pct = Int((bar.miles / total * 100).rounded())
        return HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2).fill(bar.color).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 3) {
                Text(bar.label + (kind.isPaceAxis ? " /MI" : ""))
                    .font(.dripEyebrow(10.5)).tracking(1.0)
                    .foregroundStyle(Color.drip.textPrimary)
                if let sub = bar.subLabel {
                    Text(sub + " /MI")
                        .font(.dripEyebrow(8.5)).tracking(0.8)
                        .foregroundStyle(Color.drip.textTertiary)
                }
            }
            Spacer()
            Text("\(pct)%")
                .font(.dripEyebrow(10)).tracking(0.8)
                .foregroundStyle(Color.drip.textTertiary)
            Text("\(TrainingAnalyticsViewModel.fmtMiles(bar.miles)) MI")
                .font(.dripStat(13))
                .foregroundStyle(Color.drip.textPrimary)
                .frame(width: 64, alignment: .trailing)
        }
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func runList(for bar: TrainingAnalyticsViewModel.VolumeDetailBar) -> some View {
        let runs = vm.sessions(forKey: bar.key)
        if runs.isEmpty {
            Text("No runs in this band for the current window.")
                .font(.system(size: 13, design: .serif).italic())
                .foregroundStyle(Color.drip.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 14)
        } else {
            VStack(spacing: 0) {
                ForEach(runs) { run in
                    runRow(run)
                    if run.id != runs.last?.id { Hairline().opacity(0.5) }
                }
            }
            .padding(.leading, 22)
            .padding(.bottom, 8)
        }
    }

    private func runRow(_ run: SessionDetail) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(TrainingAnalyticsViewModel.monthDayLabel(run.date)) · \(run.typeLabel) · \(TrainingAnalyticsViewModel.fmtMiles(run.miles)) MI")
                    .font(.dripEyebrow(10)).tracking(0.9)
                    .foregroundStyle(Color.drip.textPrimary)
                if let pace = run.pace {
                    Text("\(pace) /MI")
                        .font(.dripEyebrow(9)).tracking(0.8)
                        .foregroundStyle(Color.drip.textSecondary)
                }
            }
            Spacer()
            if run.canOpenAnalysis {
                Button {
                    if let w = vm.runningWorkout(forSessionId: run.id) {
                        analysisTarget = WorkoutAnalysisTarget(id: run.id, workout: w)
                    }
                } label: {
                    Text("ANALYSIS ↗")
                        .font(.dripEyebrow(9)).tracking(1.0)
                        .foregroundStyle(Color.drip.coral)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 11)
    }
}

// MARK: - Detail bar chart (enlarged, axed)

/// Vertical bar chart with a miles y-axis, gridlines, and value labels.
/// `isPaceAxis` swaps the per-bar x labels for fixed pace anchors (the
/// 18-bin histogram is too dense to label each bar).
private struct DetailBarChart: View {
    let bars: [TrainingAnalyticsViewModel.VolumeDetailBar]
    let isPaceAxis: Bool
    let selectedId: UUID?
    let onTap: (TrainingAnalyticsViewModel.VolumeDetailBar) -> Void

    private let plotH: CGFloat = 210

    var body: some View {
        let maxMi = max(0.1, bars.map(\.miles).max() ?? 0.1)
        let top = TrainingAnalyticsViewModel.niceMilesTop(maxMi)
        let labelEach = !isPaceAxis && bars.count <= 12
        let spacing: CGFloat = bars.count > 12 ? 2 : 6

        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .trailing, spacing: 0) {
                yTick("\(TrainingAnalyticsViewModel.fmtMiles(top)) MI")
                Spacer(minLength: 0)
                yTick(TrainingAnalyticsViewModel.fmtMiles(top / 2))
                Spacer(minLength: 0)
                yTick("0")
            }
            .frame(width: 34, height: plotH)

            VStack(spacing: 7) {
                ZStack(alignment: .bottom) {
                    Rectangle().fill(Color.drip.divider.opacity(0.5)).frame(height: 1)
                        .frame(maxHeight: .infinity, alignment: .top)
                    Rectangle().fill(Color.drip.divider.opacity(0.5)).frame(height: 1)
                        .frame(maxHeight: .infinity, alignment: .center)

                    HStack(alignment: .bottom, spacing: spacing) {
                        ForEach(bars) { bar in
                            barColumn(bar, top: top, labelEach: labelEach)
                                .onTapGesture { onTap(bar) }
                        }
                    }
                    .frame(height: plotH)
                }
                .frame(height: plotH)
                .overlay(Rectangle().fill(Color.drip.divider).frame(height: 1), alignment: .bottom)

                xAxis(labelEach: labelEach, spacing: spacing)
            }
        }
    }

    private func barColumn(_ bar: TrainingAnalyticsViewModel.VolumeDetailBar,
                           top: Double, labelEach: Bool) -> some View {
        let selected = selectedId == bar.id
        return VStack(spacing: 4) {
            if labelEach && bar.miles > 0 {
                Text(TrainingAnalyticsViewModel.fmtMiles(bar.miles))
                    .font(.dripEyebrow(8)).foregroundStyle(Color.drip.textTertiary)
            }
            Spacer(minLength: 0)
            RoundedRectangle(cornerRadius: 1)
                .fill(bar.miles > 0 ? bar.color : Color.clear)
                .frame(height: max(bar.miles > 0 ? 2 : 0, CGFloat(bar.miles / top) * (plotH - 18)))
                .overlay(
                    RoundedRectangle(cornerRadius: 1)
                        .stroke(Color.drip.textPrimary, lineWidth: selected ? 1.5 : 0)
                )
        }
        .frame(maxWidth: .infinity, maxHeight: plotH, alignment: .bottom)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func xAxis(labelEach: Bool, spacing: CGFloat) -> some View {
        if isPaceAxis {
            HStack {
                ForEach(["8:00","7:00","6:00","5:00","4:30"], id: \.self) { t in
                    Text(t).font(.dripEyebrow(9)).foregroundStyle(Color.drip.textTertiary)
                    if t != "4:30" { Spacer() }
                }
            }
        } else if labelEach {
            HStack(spacing: spacing) {
                ForEach(bars) { bar in
                    VStack(spacing: 2) {
                        Text(bar.label)
                            .font(.dripEyebrow(8.5)).tracking(0.4)
                            .foregroundStyle(Color.drip.textTertiary)
                        if let sub = bar.subLabel {
                            Text(sub)
                                .font(.dripEyebrow(7.5)).tracking(0.2)
                                .foregroundStyle(Color.drip.textTertiary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func yTick(_ text: String) -> some View {
        Text(text)
            .font(.dripEyebrow(8.5)).tracking(0.5).monospacedDigit()
            .foregroundStyle(Color.drip.textTertiary)
    }
}
