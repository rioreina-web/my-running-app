//
//  TrainingCalendarSection.swift
//  RunningLog · Training › Analytics
//
//  The editorial "week as a calendar" section — a single per-day view of a
//  training week/month/block that REPLACES the old pair of per-day bar
//  charts (Volume·by·intensity + Mileage·by·day), which showed the same
//  week two other ways. Each day carries mileage, an intensity-colored
//  pace chip, its session label, an ambient mood dot/pill, and taps into
//  the shared DayAnalysisSheet. The within-day easy/aerobic/threshold
//  split survives as the thin summary strip (week scope) and in full on
//  the day sheet's "BY PACE ZONE" breakdown.
//
//  Shared by TrainingTabView (the canonical tab) and TrainingTabTwoView
//  (the eval tab) so the two can't drift. Host owns day-tap presentation
//  via `onTapDay`; the section owns layout only. No fetch, no VM edits —
//  reads `vm.gridWeeks()` / `sessions(on:)` exactly like the old charts.
//
//  Design: training-redesign-v2.html.
//

import SwiftUI

struct TrainingCalendarSection: View {

    let vm: TrainingAnalyticsViewModel
    /// Host presents the day detail (e.g. `route = .day($0)`).
    var onTapDay: (Date) -> Void

    private static let moodWords = ["energized", "positive", "neutral", "tired", "struggling", "injured"]

    private static let dowFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "EEE"
        return f
    }()

    var body: some View {
        let weeks = vm.gridWeeks()
        if weeks.isEmpty {
            Text("No training in this window yet. Your logged runs land here.")
                .font(.dripBody(14).italic())
                .foregroundStyle(Color.drip.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 24)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                switch vm.scope {
                case .week:
                    weekView(weeks.last!)
                case .month, .block:
                    monthView(weeks)
                }
                legend.padding(.top, 20)
            }
            .padding(.top, 4)
        }
    }

    // MARK: WEEK — stacked day rows

    private func weekView(_ wk: GridWeek) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("WEEK OF \(wk.label.uppercased())")
                    .font(.dripEyebrow(10.5)).tracking(1.2)
                    .foregroundStyle(Color.drip.textPrimary)
                Spacer()
                Text("\(vm.formatMiles(weekMiles(wk))) MI")
                    .font(.dripEyebrow(10.5)).tracking(0.8)
                    .foregroundStyle(Color.drip.textSecondary)
            }
            .padding(.bottom, 4)

            ForEach(wk.cells) { c in dayRow(c) }

            intensityBar(wk).padding(.top, 14)
        }
    }

    private func dayRow(_ c: DayCell) -> some View {
        let ss = vm.sessions(on: c.date)
        let mood = moodWord(c.date)
        return Button { tap(c) } label: {
            HStack(spacing: 12) {
                VStack(spacing: 1) {
                    Text(Self.dowFmt.string(from: c.date).uppercased())
                        .font(.dripEyebrow(8.5)).foregroundStyle(Color.drip.textTertiary)
                    Text("\(dayNum(c.date))")
                        .font(.dripStat(15)).foregroundStyle(Color.drip.textPrimary)
                }
                .frame(width: 34)

                chip(c)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(sessionTitle(c, ss))
                            .font(.dripBody(15)).foregroundStyle(Color.drip.textPrimary)
                            .lineLimit(1)
                        if isKey(c) { keyTag }
                    }
                    Text(sessionSub(c, ss))
                        .font(.dripEyebrow(9.5)).tracking(0.5)
                        .foregroundStyle(Color.drip.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)

                if let mood { moodPill(mood) }
                Text("↗").font(.dripEyebrow(12)).foregroundStyle(Color.drip.textTertiary)
            }
            .padding(.vertical, 11)
            .contentShape(Rectangle())
            .overlay(Rectangle().fill(Color.drip.divider).frame(height: 1), alignment: .bottom)
        }
        .buttonStyle(.plain)
        .opacity(c.isFuture ? 0.72 : 1)
    }

    private func chip(_ c: DayCell) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9)
                .fill(dayColor(c))
                .overlay {
                    if c.isFuture && c.miles == 0 {
                        RoundedRectangle(cornerRadius: 9)
                            .strokeBorder(Color.drip.textTertiary, style: StrokeStyle(lineWidth: 1.5, dash: [3]))
                    }
                }
            if c.isRest {
                Text("REST").font(.dripEyebrow(8)).foregroundStyle(Color.drip.textTertiary)
            } else if c.miles > 0 {
                Text(vm.formatMiles(c.miles))
                    .font(.dripStat(14)).foregroundStyle(chipText(c))
            }
        }
        .frame(width: 40, height: 40)
    }

    // MARK: MONTH / BLOCK — calendar grid

    private func monthView(_ weeks: [GridWeek]) -> some View {
        VStack(spacing: 5) {
            HStack(spacing: 5) {
                ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { item in
                    Text(item.element).font(.dripEyebrow(9)).foregroundStyle(Color.drip.textTertiary)
                        .frame(maxWidth: .infinity)
                }
                Text("MI").font(.dripEyebrow(9)).foregroundStyle(Color.drip.textSecondary)
                    .frame(width: 30)
            }
            ForEach(weeks) { wk in
                HStack(spacing: 5) {
                    ForEach(wk.cells) { c in monthCell(c) }
                    VStack(spacing: 2) {
                        Text(vm.formatMiles(weekMiles(wk)))
                            .font(.dripStat(12)).foregroundStyle(Color.drip.textPrimary)
                        Text("MI").font(.dripEyebrow(6.5)).foregroundStyle(Color.drip.textTertiary)
                    }
                    .frame(width: 30, height: 64)
                    .background(Color.drip.paperDeep)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }
            }
        }
    }

    private func monthCell(_ c: DayCell) -> some View {
        Button { tap(c) } label: {
            VStack(spacing: 3) {
                Text("\(dayNum(c.date))")
                    .font(.dripEyebrow(8.5))
                    .foregroundStyle(c.isFuture ? Color.drip.textTertiary : Color.drip.textSecondary)
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(c.miles > 0 ? dayColor(c) : Color.clear)
                        .frame(width: 26, height: 26)
                        .overlay {
                            if c.isFuture && c.miles == 0 {
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(Color.drip.textTertiary, style: StrokeStyle(lineWidth: 1.2, dash: [2.5]))
                            } else if c.isRest {
                                RoundedRectangle(cornerRadius: 6).fill(Color.drip.paperDeep)
                            }
                        }
                    if c.miles > 0 {
                        Text(vm.formatMiles(c.miles))
                            .font(.dripStat(10)).foregroundStyle(chipText(c))
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .padding(.top, 5)
            .background(cellBackground(c))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(alignment: .topLeading) {
                if isKey(c) {
                    RoundedRectangle(cornerRadius: 1).fill(Color.drip.textPrimary)
                        .frame(width: 7, height: 7).padding(4)
                }
            }
            .overlay(alignment: .topTrailing) {
                if let mood = moodWord(c.date) {
                    Circle().fill(moodColor(mood)).frame(width: 7, height: 7).padding(4)
                }
            }
            .overlay {
                if isToday(c.date) {
                    RoundedRectangle(cornerRadius: 7).strokeBorder(Color.drip.coral, lineWidth: 1.5)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func cellBackground(_ c: DayCell) -> Color {
        c.isFuture ? Color.drip.cardBackgroundElevated : Color.drip.cardBackground
    }

    // MARK: Week intensity strip (the surviving easy/aerobic/threshold split)

    private func intensityBar(_ wk: GridWeek) -> some View {
        let easy = wk.cells.reduce(0.0) { $0 + $1.split.easy }
        let aero = wk.cells.reduce(0.0) { $0 + $1.split.aerobic }
        let thr  = wk.cells.reduce(0.0) { $0 + $1.split.threshold }
        let total = max(0.001, easy + aero + thr)
        return VStack(alignment: .leading, spacing: 8) {
            Text("BY INTENSITY").font(.dripEyebrow(9.5)).tracking(1.1)
                .foregroundStyle(Color.drip.textSecondary)
            GeometryReader { geo in
                HStack(spacing: 2) {
                    Rectangle().fill(IntensityRamp.easy)
                        .frame(width: geo.size.width * CGFloat(easy / total))
                    Rectangle().fill(IntensityRamp.aerobic)
                        .frame(width: geo.size.width * CGFloat(aero / total))
                    Rectangle().fill(IntensityRamp.threshold)
                        .frame(width: geo.size.width * CGFloat(thr / total))
                }
                .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .frame(height: 12)
        }
        .padding(.top, 12)
        .overlay(Rectangle().fill(Color.drip.divider).frame(height: 1), alignment: .top)
    }

    // MARK: Legend

    private var legend: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PACE · EASY TO HARD").font(.dripEyebrow(9.5)).tracking(1.1)
                .foregroundStyle(Color.drip.textSecondary)
            HStack(spacing: 2) {
                Rectangle().fill(IntensityRamp.easy)
                Rectangle().fill(IntensityRamp.aerobic)
                Rectangle().fill(IntensityRamp.threshold)
            }
            .frame(height: 10)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            HStack(spacing: 14) {
                legendKey(square: true, color: Color.drip.textPrimary, "Key session")
                legendKey(square: false, color: Color.drip.positive, "Mood")
                legendKey(square: false, color: Color.drip.coral, "Today")
                Spacer()
            }
        }
    }

    private func legendKey(square: Bool, color: Color, _ label: String) -> some View {
        HStack(spacing: 6) {
            Group {
                if square {
                    RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 9, height: 9)
                } else {
                    Circle().fill(color).frame(width: 9, height: 9)
                }
            }
            Text(label.uppercased()).font(.dripEyebrow(8.5)).tracking(0.6)
                .foregroundStyle(Color.drip.textTertiary)
        }
    }

    private var keyTag: some View {
        Text("KEY").font(.dripEyebrow(7.5)).tracking(1.0)
            .foregroundStyle(Color.drip.background)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Color.drip.textPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private func moodPill(_ word: String) -> some View {
        Text(word.uppercased()).font(.dripEyebrow(8.5)).tracking(0.8)
            .foregroundStyle(moodColor(word))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(moodColor(word).opacity(0.13))
            .clipShape(Capsule())
    }

    // MARK: Helpers

    private func tap(_ c: DayCell) {
        guard !(c.isFuture && c.miles == 0) else { return }
        onTapDay(c.date)
    }

    private func weekMiles(_ w: GridWeek) -> Double { w.cells.reduce(0) { $0 + $1.miles } }

    private func dayNum(_ d: Date) -> Int { Calendar.current.component(.day, from: d) }

    private func isToday(_ d: Date) -> Bool { Calendar.current.isDateInToday(d) }

    private func dayColor(_ c: DayCell) -> Color {
        if c.isRest { return Color.drip.paperDeep }
        if c.split.threshold > 0 { return IntensityRamp.threshold }
        if c.split.aerobic > 0 { return IntensityRamp.aerobic }
        return IntensityRamp.easy
    }

    private func chipText(_ c: DayCell) -> Color {
        if c.isRest { return Color.drip.textTertiary }
        if c.split.threshold > 0 || c.split.aerobic > 0 { return .white }
        return Color.drip.textPrimary
    }

    private func isKey(_ c: DayCell) -> Bool { !c.isFuture && c.split.threshold > 0 }

    private func sessionTitle(_ c: DayCell, _ ss: [SessionDetail]) -> String {
        if c.isRest { return "Rest" }
        if c.isFuture && c.miles == 0 { return "Planned" }
        if let first = ss.first { return first.typeLabel }
        return "Run"
    }

    private func sessionSub(_ c: DayCell, _ ss: [SessionDetail]) -> String {
        if c.isRest { return "Nothing logged" }
        if c.isFuture && c.miles == 0 { return "Upcoming" }
        var parts: [String] = []
        if c.miles > 0 { parts.append("\(vm.formatMiles(c.miles)) mi") }
        if let p = ss.first?.pace { parts.append("\(p) / mi") }
        if ss.count > 1 { parts.append("\(ss.count) runs") }
        return parts.joined(separator: " · ")
    }

    private func moodWord(_ day: Date) -> String? {
        for s in vm.sessions(on: day) {
            let hay = ((s.feltLine ?? "") + " " + (s.pullQuote ?? "")).lowercased()
            for w in Self.moodWords where hay.contains(w) { return w }
        }
        return nil
    }

    private func moodColor(_ w: String) -> Color {
        switch w {
        case "energized":  return Color.drip.energized
        case "positive":   return Color.drip.positive
        case "neutral":    return Color.drip.neutral
        case "tired":      return Color.drip.tired
        case "struggling": return Color.drip.struggling
        case "injured":    return Color.drip.injured
        default:           return Color.drip.neutral
        }
    }
}
