//
//  TrainingTabTwoView.swift
//  RunningLog · Training › Analytics
//
//  "Train 2" — an EVALUATION tab that sits alongside the existing
//  TrainingTabView (both are wired into MainTabView; neither replaces the
//  other). It reframes training as an editorial CALENDAR of every session,
//  not a receipts feed:
//
//    • WEEK  — the current week as stacked day rows (date · pace chip ·
//              session · mood · ↗), most detail per day.
//    • MONTH — a 7-column calendar grid, one cell per day, colored by
//              intensity, with a weekly mileage total in the right rail.
//    • BLOCK — the same grid across the whole block.
//
//  Every day drills into the SAME `DayAnalysisSheet` the old tab uses, so
//  the detail surface is shared, not forked.
//
//  Mood is AMBIENT here (per the 2026-07 decision to let mood be a quiet
//  layer on Training rather than living only on The Read): a small warm
//  dot on each day, derived from the day's logged feeling. Numbers stay
//  the hero. Blue = pace, warm = mood, coral = alert — the palettes never
//  mix (design-system three-palette rule).
//
//  Data + detail are 100% reused from `TrainingAnalyticsViewModel`
//  (gridWeeks / sessions(on:) / summary) and existing components
//  (WorkoutsAndRepsSection = key workouts, DayAnalysisSheet = drilldown).
//  This view adds layout only — no new fetch, no schema, no VM edits.
//
//  Source design: training-redesign-v2.html (the interactive mock).
//

import SwiftUI

struct TrainingTabTwoView: View {

    @State private var vm = TrainingAnalyticsViewModel()
    @State private var dayRoute: DayRoute?

    private struct DayRoute: Identifiable {
        let id = UUID()
        let day: Date
    }

    // Mood vocabulary (closed set) → the six editorial mood colors.
    private static let moodWords = ["energized", "positive", "neutral", "tired", "struggling", "injured"]

    private static let dowFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "EEE"
        return f
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PlateStrip(surface: "TRAINING · V2 · CALENDAR")
                    .padding(.bottom, 24)

                if vm.isLoading && !vm.hasLoaded {
                    loadingState
                } else if vm.loadFailed && !vm.hasLoaded {
                    EmptyStateView(
                        variant: .error,
                        eyebrow: "Couldn't load",
                        title: "Your training didn't load. Check your connection and try again.",
                        cta: .init(label: "Retry") { Task { await vm.load() } }
                    )
                    .padding(.vertical, 40)
                } else {
                    header
                    scopeToggle
                    summary
                    EditorialRule().padding(.vertical, 20)
                    content
                    keyWorkouts
                    legend
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .background(Color.drip.background.ignoresSafeArea())
        .task { if !vm.hasLoaded { await vm.load() } }
        .sheet(item: $dayRoute) { r in DayAnalysisSheet(vm: vm, day: r.day) }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(vm.scopeDateline())
                .font(.dripEyebrow(10.5)).tracking(1.6)
                .foregroundStyle(Color.drip.textSecondary)
            Text("Your training.")
                .font(.dripDisplay(34))
                .foregroundStyle(Color.drip.textPrimary)
            Text("Every session, week by week. Tap any day to open it.")
                .font(.dripBody(13.5).italic())
                .foregroundStyle(Color.drip.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    // MARK: Scope toggle

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
        .padding(.top, 22)
        .padding(.bottom, 4)
    }

    // MARK: Summary ribbon (workout-first — no voice-memo count here)

    private var summary: some View {
        let s = vm.summary()
        return HStack(spacing: 0) {
            statCell("\(s.runs)", "Runs")
            statDivider
            statCell(vm.formatMiles(s.miles), "Miles")
            statDivider
            statCell("\(TrainingAnalyticsViewModel.formatDurationHours(s.durationMinutes))", "Hrs")
            statDivider
            statCell("\(s.easyPercent)%", "Easy")
        }
        .overlay(Rectangle().fill(Color.drip.divider).frame(height: 1), alignment: .top)
        .overlay(Rectangle().fill(Color.drip.divider).frame(height: 1), alignment: .bottom)
        .padding(.top, 18)
    }

    private func statCell(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.dripStat(20)).foregroundStyle(Color.drip.textPrimary)
            Text(label.uppercased()).font(.dripEyebrow(8.5)).tracking(1.2)
                .foregroundStyle(Color.drip.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
    }

    private var statDivider: some View {
        Rectangle().fill(Color.drip.divider).frame(width: 1, height: 32)
    }

    // MARK: Content — scope switch

    @ViewBuilder
    private var content: some View {
        let weeks = vm.gridWeeks()
        if weeks.isEmpty {
            Text("No training in this window yet. Your logged runs land here.")
                .font(.dripBody(14).italic())
                .foregroundStyle(Color.drip.textSecondary)
                .padding(.vertical, 24)
        } else {
            switch vm.scope {
            case .week:
                weekView(weeks.last!)
            case .month, .block:
                monthView(weeks)
            }
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
        .padding(.top, 4)
    }

    private func dayRow(_ c: DayCell) -> some View {
        let ss = vm.sessions(on: c.date)
        let mood = moodWord(c.date)
        return Button { openDay(c) } label: {
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

    // MARK: MONTH — calendar grid

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
        .padding(.top, 4)
    }

    private func monthCell(_ c: DayCell) -> some View {
        Button { openDay(c) } label: {
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

    // MARK: Week intensity bar

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

    // MARK: Key workouts (reuse the existing receipts section)

    private var keyWorkouts: some View {
        VStack(alignment: .leading, spacing: 0) {
            EditorialRule().padding(.vertical, 22)
            WorkoutsAndRepsSection()
        }
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
        .padding(.top, 24)
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

    private func openDay(_ c: DayCell) {
        // Only open days that have something to show.
        guard !(c.isFuture && c.miles == 0) else { return }
        dayRoute = DayRoute(day: c.date)
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

    // Was a byte-identical copy of the calendar's old Rule 1. This whole view
    // is RETIRED as a tab (RunningLogApp.swift:194) and is dead code that
    // should be deleted outright — it is rewired rather than left alone only so
    // that no fifth key-session rule survives anywhere in the codebase.
    private func isKey(_ c: DayCell) -> Bool { KeySessionStore.shared.isKey(on: c.date) }

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
