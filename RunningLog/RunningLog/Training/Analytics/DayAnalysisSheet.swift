//
//  DayAnalysisSheet.swift
//  RunningLog · Training › Analytics
//
//  (Renamed from DayDetailSheet to avoid colliding with the existing
//  scheduled-workout editor Training/DayDetailSheet.swift — same filename and
//  same `struct DayDetailSheet: View` would otherwise clash.)
//
//  The full-screen day analysis opened by tapping a day in the mileage
//  skyline (Plate 22 · day detail). Gives the day real depth instead of
//  the old flat inline card:
//
//    • Day summary — total volume, moving time, combined avg pace, run count.
//    • Pace-zone / effort breakdown — miles per zone for the day.
//    • Each session — type · miles · pace · avg HR, a splits table
//      (distance · pace · HR, with a per-split pace bar), and a deep link
//      into the full stream analysis (WorkoutAnalystView).
//
//  Multi-run days (AM/PM) render every session under one day summary.
//  Splits come from laps when present, else per-mile pace_segments.
//

import SwiftUI

struct DayAnalysisSheet: View {
    let vm: TrainingAnalyticsViewModel
    let day: Date

    @Environment(\.dismiss) private var dismiss
    @State private var splitsBySession: [UUID: [DaySplit]] = [:]
    @State private var analysisTarget: WorkoutAnalysisTarget?

    /// Key sessions. Shared store, so a tap here moves the star in the
    /// calendar and the journal at the same time.
    @State private var keySessions = KeySessionStore.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    summaryHeader
                    keySessionRow
                    zoneBreakdown
                    EditorialRule().padding(.vertical, 22)
                    ForEach(Array(sessions.enumerated()), id: \.element.id) { idx, s in
                        if idx > 0 { EditorialRule().padding(.vertical, 20) }
                        sessionBlock(s)
                    }
                    if sessions.isEmpty {
                        Text("No runs logged on this day.")
                            .font(.system(size: 14, design: .serif).italic())
                            .foregroundStyle(Color.drip.textTertiary)
                            .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 40)
            }
            .background(Color.drip.background.ignoresSafeArea())
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
            .task {
                // Late sign-in safety net: the launch refresh runs before auth
                // settles for a first-run athlete, leaving the store empty and
                // every day reading AUTO. Cheap, and only when it didn't load.
                if !keySessions.hasLoaded { await keySessions.loadOverrides() }

                var map: [UUID: [DaySplit]] = [:]
                for s in sessions { map[s.id] = await vm.splits(forSessionId: s.id) }
                splitsBySession = map
            }
            .workoutAnalysisSheet($analysisTarget)
        }
    }

    // MARK: Data

    private var sessions: [SessionDetail] { vm.sessions(on: day) }
    private var summary: DaySummary { vm.daySummary(day) }

    private var navTitle: String {
        let f = DateFormatter(); f.dateFormat = "EEE · MMM d"
        return f.string(from: day)
    }

    // MARK: Summary header

    private var summaryHeader: some View {
        let s = summary
        return VStack(alignment: .leading, spacing: 6) {
            Text("DAY · ANALYSIS")
                .font(.dripEyebrow(10.5)).tracking(1.6)
                .foregroundStyle(Color.drip.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(TrainingAnalyticsViewModel.fmtMiles(s.totalMiles))
                    .font(.dripDisplay(34)).foregroundStyle(Color.drip.textPrimary)
                Text("MILES").font(.dripEyebrow(10)).tracking(1.3)
                    .foregroundStyle(Color.drip.textTertiary)
            }
            Text(metaLine(s))
                .font(.dripEyebrow(10)).tracking(1.0)
                .foregroundStyle(Color.drip.textSecondary)
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metaLine(_ s: DaySummary) -> String {
        var parts: [String] = ["\(s.runCount) RUN\(s.runCount == 1 ? "" : "S")"]
        if s.totalMinutes > 0 {
            parts.append("\(TrainingAnalyticsViewModel.formatDurationHours(s.totalMinutes)) MOVING")
        }
        if let p = s.avgPaceSeconds {
            parts.append("\(TrainingAnalyticsViewModel.formatPaceMMSS(p)) /MI AVG")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Key session — the athlete's declaration
    //
    // The one place a key session gets ASSIGNED. Everything else in the app
    // only displays the result (KEY-SESSION-APPLY.md §8A).
    //
    // Tapping cycles: AUTO → YOURS ★ → YOURS (not key) → AUTO. Three taps
    // and you're back where you started, so it's safe to explore.
    //
    // "MARKS FRI AUG 7" is not decoration. The override is keyed by DAY, not
    // by run — on a doubles day this sheet lists two sessions, and without
    // that line the row reads as marking the one run you happened to open.

    private var keySessionRow: some View {
        Button {
            Task { await keySessions.cycle(on: day) }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("KEY SESSION")
                        .font(.dripEyebrow(10.5)).tracking(1.3)
                        .foregroundStyle(Color.drip.textSecondary)
                    Spacer(minLength: 12)
                    Text(keyStateLabel)
                        .font(.dripEyebrow(9.5)).tracking(1.1)
                        .foregroundStyle(keyIsSet ? Color.drip.textPrimary
                                                  : Color.drip.textTertiary)
                    KeySessionStar(provenance: keyProvenance, isKey: keyIsSet)
                        .frame(width: 11, height: 11)
                }
                Text(marksLine)
                    .font(.dripEyebrow(8.5)).tracking(0.9)
                    .foregroundStyle(Color.drip.textTertiary)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 14)
    }

    /// The athlete's stored answer for this day. nil = they've said nothing.
    private var keyOverride: Bool? { keySessions.override(on: day) }

    private var keyIsSet: Bool { keySessions.isKey(on: day) }

    private var keyProvenance: KeySessionMark.Provenance { keySessions.provenance(on: day) }

    /// Never an em-dash placeholder: a day with nothing set reads AUTO, which
    /// is a real value, not an empty one.
    private var keyStateLabel: String {
        switch keyOverride {
        case .some(true):  return "YOURS"
        case .some(false): return "YOURS · NOT KEY"
        case nil:          return "AUTO"
        }
    }

    /// "MARKS FRI AUG 7" — says out loud that this marks the day.
    private var marksLine: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE MMM d"
        let d = f.string(from: day).uppercased()
        switch keyOverride {
        case .some(true):  return "MARKS \(d) · TAP TO SAY NOT KEY"
        case .some(false): return "MARKS \(d) · TAP TO GO BACK TO AUTO"
        case nil:          return "MARKS \(d) · TAP TO MARK IT KEY"
        }
    }

    // MARK: Zone breakdown (pace-zone / effort + volume)

    private var zoneBreakdown: some View {
        let z = summary.zone
        let total = max(0.001, z.total)
        return VStack(alignment: .leading, spacing: 8) {
            Text("BY PACE ZONE").font(.dripEyebrow(10.5)).tracking(1.3)
                .foregroundStyle(Color.drip.textSecondary)
                .padding(.top, 18)
            GeometryReader { geo in
                HStack(spacing: 0) {
                    seg(width: geo.size.width * CGFloat(z.easy / total), color: IntensityRamp.easy)
                    seg(width: geo.size.width * CGFloat(z.aerobic / total), color: IntensityRamp.aerobic)
                    seg(width: geo.size.width * CGFloat(z.threshold / total), color: IntensityRamp.threshold)
                }
                .clipShape(RoundedRectangle(cornerRadius: 2))
            }
            .frame(height: 14)
            HStack(spacing: 14) {
                zoneTag("EASY", z.easy, IntensityRamp.easy)
                zoneTag("AEROBIC", z.aerobic, IntensityRamp.aerobic)
                zoneTag("THRESHOLD+", z.threshold, IntensityRamp.threshold)
                Spacer()
            }
        }
    }

    private func seg(width: CGFloat, color: Color) -> some View {
        Rectangle().fill(color).frame(width: max(0, width))
    }

    private func zoneTag(_ label: String, _ miles: Double, _ color: Color) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 8, height: 8)
            Text("\(label) \(TrainingAnalyticsViewModel.fmtMiles(miles))")
                .font(.dripEyebrow(8.5)).tracking(0.6)
                .foregroundStyle(Color.drip.textTertiary)
        }
    }

    // MARK: Session block

    private func sessionBlock(_ s: SessionDetail) -> some View {
        let splits = splitsBySession[s.id] ?? []
        let hrs = splits.compactMap(\.hr)
        let avgHR = hrs.isEmpty ? nil : Int((Double(hrs.reduce(0, +)) / Double(hrs.count)).rounded())
        return VStack(alignment: .leading, spacing: 10) {
            // Session header
            HStack(alignment: .firstTextBaseline) {
                Text("\(s.typeLabel) · \(TrainingAnalyticsViewModel.fmtMiles(s.miles)) MI")
                    .font(.dripEyebrow(11)).tracking(1.2)
                    .foregroundStyle(Color.drip.textPrimary)
                Spacer()
                if let pace = s.pace {
                    Text("\(pace) /MI").font(.dripEyebrow(10)).tracking(0.9)
                        .foregroundStyle(Color.drip.textSecondary)
                }
                if let hr = avgHR {
                    Text("· \(hr) BPM").font(.dripEyebrow(10)).tracking(0.9)
                        .foregroundStyle(Color.drip.coral)
                }
            }
            if let quote = s.pullQuote, !quote.isEmpty {
                Text("\u{201C}\(quote)\u{201D}")
                    .font(.system(size: 15, design: .serif).italic())
                    .foregroundStyle(Color.drip.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if splits.count >= 1 {
                splitsTable(splits)
            } else if s.canOpenAnalysis {
                Text("Loading splits…")
                    .font(.dripEyebrow(9)).tracking(1.0)
                    .foregroundStyle(Color.drip.textTertiary)
            } else {
                Text("No GPS splits for this entry.")
                    .font(.system(size: 13, design: .serif).italic())
                    .foregroundStyle(Color.drip.textTertiary)
            }

            if s.canOpenAnalysis {
                Button {
                    if let w = vm.runningWorkout(forSessionId: s.id) {
                        analysisTarget = WorkoutAnalysisTarget(id: s.id, workout: w)
                    }
                } label: {
                    Text("FULL ANALYSIS ↗")
                        .font(.dripEyebrow(10)).tracking(1.2)
                        .foregroundStyle(Color.drip.coral)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Splits table

    private func splitsTable(_ splits: [DaySplit]) -> some View {
        // Bars are sized off the clock, not the pace, so the bar agrees with
        // the number printed beside it: a rep draws a long bar, the jog
        // between reps a short one, and the table reads as a timeline of the
        // session. Intensity has not been dropped - it is still in the colour.
        let longest = splits.map(\.elapsedSeconds).max() ?? 1
        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("#").frame(width: 22, alignment: .leading)
                Text("DIST").frame(width: 52, alignment: .leading)
                Text("TIME").frame(maxWidth: .infinity, alignment: .leading)
                Text("HR").frame(width: 44, alignment: .trailing)
            }
            .font(.dripEyebrow(8.5)).tracking(1.0)
            .foregroundStyle(Color.drip.textTertiary)
            .padding(.vertical, 5)
            .overlay(Rectangle().fill(Color.drip.divider).frame(height: 1), alignment: .bottom)

            ForEach(splits) { sp in
                HStack(spacing: 10) {
                    Text("\(sp.index)")
                        .font(.dripEyebrow(9.5)).foregroundStyle(Color.drip.textTertiary)
                        .frame(width: 22, alignment: .leading)
                    Text(String(format: "%.2f", sp.distanceMiles))
                        .font(.dripStat(11)).foregroundStyle(Color.drip.textSecondary)
                        .frame(width: 52, alignment: .leading)
                    // Time + bar: longer splits draw a longer bar.
                    HStack(spacing: 8) {
                        Text(TrainingAnalyticsViewModel.formatClock(sp.elapsedSeconds))
                            .font(.dripStat(12)).foregroundStyle(Color.drip.textPrimary)
                            .frame(width: 48, alignment: .leading)
                        GeometryReader { geo in
                            let frac = 0.06 + 0.94 * (sp.elapsedSeconds / max(1, longest))
                            RoundedRectangle(cornerRadius: 1)
                                .fill(sp.color)
                                .frame(width: max(3, geo.size.width * CGFloat(frac)), height: 7)
                                .frame(maxHeight: .infinity, alignment: .center)
                        }
                        .frame(height: 14)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(sp.hr.map { "\($0)" } ?? "—")
                        .font(.dripStat(11)).foregroundStyle(Color.drip.textSecondary)
                        .frame(width: 44, alignment: .trailing)
                }
                .padding(.vertical, 7)
                .overlay(Rectangle().fill(Color.drip.divider).opacity(0.5).frame(height: 1), alignment: .bottom)
            }
        }
        .padding(.top, 2)
    }
}
