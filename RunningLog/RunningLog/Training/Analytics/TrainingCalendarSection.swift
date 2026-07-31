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

    /// Distance/pace units — reads the app-wide Settings preference so this
    /// section re-renders the instant the athlete flips Miles ↔ Kilometers.
    @AppStorage("distanceUnit") private var distanceUnitRaw = DistanceUnit.miles.rawValue
    private var unit: DistanceUnit { DistanceUnit(rawValue: distanceUnitRaw) ?? .miles }

    private static let moodWords = ["energized", "positive", "neutral", "tired", "struggling", "injured"]

    /// Planned/estimated sessions use plum — a fourth semantic distinct from
    /// pace (blue), mood (warm), and today (coral). Matches `--mood-speed` in
    /// the design system. Change here to restyle every planned marker at once.
    private static let plannedColor = Color(hex: "6B4A8A")

    private static let dowFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "EEE"
        return f
    }()

    var body: some View {
        let weeks = vm.gridWeeks()
        let hasData = weeks.contains { wk in
            wk.cells.contains { $0.miles > 0 || $0.plannedMiles > 0 }
        }
        VStack(alignment: .leading, spacing: 0) {
            periodNav

            if !hasData {
                Text("No training logged in this window. Page back to find earlier weeks.")
                    .font(.dripBody(14).italic())
                    .foregroundStyle(Color.drip.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 24)
            } else {
                switch vm.scope {
                case .week:
                    weekView(weeks.last!)
                case .month, .block:
                    monthView(weeks)
                }
                legend.padding(.top, 20)
            }
        }
        .padding(.top, 4)
    }

    // MARK: Period navigation — page the calendar window through history
    //
    // Backward steps one whole window into the past (a week, a 5-week month,
    // or a block); forward returns toward now and never pages past the
    // current period, mirroring the This-Week pager. "Return to now" appears
    // only when the athlete has scrolled off the current period.

    private var periodNav: some View {
        HStack(spacing: 12) {
            Button { withAnimation(.easeInOut(duration: 0.2)) { vm.calendarGoBack() } } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.drip.coral)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            VStack(spacing: 2) {
                Text(vm.calendarRangeLabel)
                    .font(.dripEyebrow(11)).tracking(1.3)
                    .foregroundStyle(Color.drip.textPrimary)
                if !vm.calendarIsCurrent {
                    Button { withAnimation(.easeInOut(duration: 0.2)) { vm.calendarGoToCurrent() } } label: {
                        Text("RETURN TO NOW")
                            .font(.dripEyebrow(8.5)).tracking(1.0)
                            .foregroundStyle(Color.drip.coral)
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer(minLength: 8)

            Button { withAnimation(.easeInOut(duration: 0.2)) { vm.calendarGoForward() } } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(vm.calendarIsCurrent ? Color.drip.textTertiary : Color.drip.coral)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(vm.calendarIsCurrent)
        }
        .padding(.bottom, 16)
    }

    // MARK: WEEK — stacked day rows

    private func weekView(_ wk: GridWeek) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // The period nav names the week; this row carries just the total.
            HStack(alignment: .firstTextBaseline) {
                Text("TOTAL")
                    .font(.dripEyebrow(10.5)).tracking(1.2)
                    .foregroundStyle(Color.drip.textTertiary)
                Spacer()
                Text("\(DistanceFormat.value(miles: weekMiles(wk), unit: unit)) \(unit.label)")
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
                Text(DistanceFormat.value(miles: c.miles, unit: unit))
                    .font(.dripStat(14)).foregroundStyle(chipText(c))
            }
        }
        .frame(width: 40, height: 40)
    }

    // MARK: MONTH / BLOCK — calendar grid

    private func monthView(_ weeks: [GridWeek]) -> some View {
        // Scales: day-block size rides the biggest single day; the weekly
        // well's fill rides the biggest week — both within the visible window.
        let maxDay = max(0.001, weeks.flatMap { $0.cells }.map { max($0.miles, $0.plannedMiles) }.max() ?? 0)
        let maxWeek = max(0.001, weeks.map(weekMiles).max() ?? 0)
        return VStack(spacing: 5) {
            HStack(spacing: 5) {
                ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { item in
                    Text(item.element).font(.dripEyebrow(9)).foregroundStyle(Color.drip.textTertiary)
                        .frame(maxWidth: .infinity)
                }
                Text(unit.label).font(.dripEyebrow(9)).foregroundStyle(Color.drip.textSecondary)
                    .frame(width: 40)
            }
            ForEach(weeks) { wk in
                HStack(spacing: 5) {
                    ForEach(wk.cells) { c in monthCell(c, maxDay: maxDay) }
                    weeklyMileageWell(wk, maxWeek: maxWeek)
                }
            }
        }
    }

    /// The right-hand weekly total: a roomier well whose neutral fill scales
    /// to the block's biggest week, so volume reads at a glance. Gray fill
    /// keeps it out of the pace (blue) / mood (warm) / alert (coral) palettes.
    private func weeklyMileageWell(_ wk: GridWeek, maxWeek: Double) -> some View {
        let logged = weekMiles(wk)                                   // logged only
        let planned = wk.cells.reduce(0) { $0 + $1.plannedMiles }    // plan estimate
        let frac = min(1, CGFloat(logged / maxWeek))                 // fill = logged
        return ZStack {
            RoundedRectangle(cornerRadius: 8).fill(Color.drip.paperDeep)
            GeometryReader { geo in
                Rectangle()
                    .fill(Color.drip.textTertiary.opacity(0.30))
                    .frame(height: geo.size.height * frac)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
            VStack(spacing: 2) {
                if logged > 0 {
                    Text(DistanceFormat.value(miles: logged, unit: unit))
                        .font(.dripStat(13)).foregroundStyle(Color.drip.textPrimary)
                    Text(unit.label).font(.dripEyebrow(7)).tracking(0.9)
                        .foregroundStyle(Color.drip.textSecondary)
                    if planned > 0 {   // partly-logged week that still has plan ahead
                        Text("+\(DistanceFormat.value(miles: planned, unit: unit))")
                            .font(.dripEyebrow(7)).foregroundStyle(Self.plannedColor)
                    }
                } else if planned > 0 {   // fully upcoming week — show the estimate
                    Text(DistanceFormat.value(miles: planned, unit: unit))
                        .font(.dripStat(13)).foregroundStyle(Self.plannedColor)
                    Text("EST").font(.dripEyebrow(7)).tracking(0.9)
                        .foregroundStyle(Self.plannedColor)
                } else {
                    Text(DistanceFormat.value(miles: logged, unit: unit))
                        .font(.dripStat(13)).foregroundStyle(Color.drip.textPrimary)
                    Text(unit.label).font(.dripEyebrow(7)).tracking(0.9)
                        .foregroundStyle(Color.drip.textSecondary)
                }
            }
        }
        .frame(width: 40, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func monthCell(_ c: DayCell, maxDay: Double) -> some View {
        let mood = moodWord(c.date)
        return Button { tap(c) } label: {
            VStack(spacing: 3) {
                Text("\(dayNum(c.date))")
                    .font(.dripEyebrow(8.5))
                    .foregroundStyle(c.isFuture ? Color.drip.textTertiary : Color.drip.textSecondary)

                Spacer(minLength: 0)
                dayBlock(c, maxDay: maxDay)
                Spacer(minLength: 0)

                // Mood ribbon — its own channel, in the band beneath the block.
                if let mood {
                    RoundedRectangle(cornerRadius: 2).fill(moodColor(mood))
                        .frame(width: 22, height: 4)
                } else {
                    Color.clear.frame(height: 4)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 72)
            .padding(.vertical, 5)
            .background(cellBackground(c))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(alignment: .topLeading) {
                if isKey(c) {
                    FiveStar().fill(Color.drip.textPrimary)
                        .frame(width: 9, height: 9).padding(4)
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

    /// The day tile: SIZE encodes distance, COLOR encodes pace. The mileage
    /// number rides inside larger tiles and drops off the smallest ones —
    /// short days stay clean and are a tap away.
    private func dayBlock(_ c: DayCell, maxDay: Double) -> some View {
        let side = tileSide(c.isPlanned ? c.plannedMiles : c.miles, maxDay: maxDay)
        return ZStack {
            if c.isPlanned {
                // Planned/upcoming session: plum, sized by its estimate, so it
                // reads as distinct from a solid-blue logged run.
                RoundedRectangle(cornerRadius: 5).fill(Self.plannedColor)
                    .frame(width: side, height: side)
                Text(DistanceFormat.value(miles: c.plannedMiles, unit: unit))
                    .font(.dripStat(tileFont(side)))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.7)
            } else if c.isFuture && c.miles == 0 {
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(Color.drip.textTertiary, style: StrokeStyle(lineWidth: 1.2, dash: [2.5]))
                    .frame(width: 22, height: 22)
                Text("—").font(.dripEyebrow(9)).foregroundStyle(Color.drip.textTertiary)
            } else if c.isRest {
                RoundedRectangle(cornerRadius: 5).fill(Color.drip.paperDeep)
                    .frame(width: 20, height: 20)
                Text("REST").font(.dripEyebrow(6.5)).foregroundStyle(Color.drip.textTertiary)
            } else if c.miles > 0 {
                RoundedRectangle(cornerRadius: 5).fill(dayColor(c))
                    .frame(width: side, height: side)
                // Every run shows its distance; the numeral scales with the tile.
                Text(DistanceFormat.value(miles: c.miles, unit: unit))
                    .font(.dripStat(tileFont(side)))
                    .foregroundStyle(chipText(c))
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(height: 38)
    }

    /// Map a day's distance to a tile side length, 22…38 pt. The floor is
    /// tall enough that even a short run's distance still fits inside.
    private func tileSide(_ miles: Double, maxDay: Double) -> CGFloat {
        guard miles > 0 else { return 22 }
        let t = min(1, CGFloat(miles / maxDay))
        return 22 + 16 * t
    }

    /// Numeral scales with the tile so every run stays labelled.
    private func tileFont(_ side: CGFloat) -> CGFloat {
        side >= 32 ? 10 : side >= 27 ? 9 : 8
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
        VStack(alignment: .leading, spacing: 14) {
            // Pace — color
            VStack(alignment: .leading, spacing: 8) {
                Text("PACE · EASY TO HARD").font(.dripEyebrow(9.5)).tracking(1.1)
                    .foregroundStyle(Color.drip.textSecondary)
                HStack(spacing: 2) {
                    Rectangle().fill(IntensityRamp.easy)
                    Rectangle().fill(IntensityRamp.aerobic)
                    Rectangle().fill(IntensityRamp.threshold)
                }
                .frame(height: 10)
                .clipShape(RoundedRectangle(cornerRadius: 3))
            }

            // Size — distance
            HStack(spacing: 12) {
                Text("SIZE · \(unit.short.uppercased()) RUN").font(.dripEyebrow(9.5)).tracking(1.1)
                    .foregroundStyle(Color.drip.textSecondary)
                Spacer()
                sizeSwatch(12); sizeSwatch(17); sizeSwatch(22)
            }

            // Markers
            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    FiveStar().fill(Color.drip.textPrimary).frame(width: 9, height: 9)
                    Text("KEY SESSION").font(.dripEyebrow(8.5)).tracking(0.6)
                        .foregroundStyle(Color.drip.textTertiary)
                }
                HStack(spacing: 6) {
                    Circle().strokeBorder(Color.drip.coral, lineWidth: 1.5).frame(width: 9, height: 9)
                    Text("TODAY").font(.dripEyebrow(8.5)).tracking(0.6)
                        .foregroundStyle(Color.drip.textTertiary)
                }
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2).fill(Self.plannedColor).frame(width: 9, height: 9)
                    Text("PLANNED").font(.dripEyebrow(8.5)).tracking(0.6)
                        .foregroundStyle(Color.drip.textTertiary)
                }
                Spacer()
            }

            // Mood — warm ribbon, its own channel
            VStack(alignment: .leading, spacing: 8) {
                Text("MOOD").font(.dripEyebrow(9.5)).tracking(1.1)
                    .foregroundStyle(Color.drip.textSecondary)
                HStack(spacing: 12) {
                    moodLegendItem("energized"); moodLegendItem("positive"); moodLegendItem("neutral")
                    Spacer()
                }
                HStack(spacing: 12) {
                    moodLegendItem("tired"); moodLegendItem("struggling"); moodLegendItem("injured")
                    Spacer()
                }
            }
        }
    }

    private func sizeSwatch(_ s: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 3).fill(IntensityRamp.aerobic)
            .frame(width: s, height: s)
    }

    private func moodLegendItem(_ word: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(moodColor(word))
                .frame(width: 14, height: 4)
            Text(word.uppercased()).font(.dripEyebrow(8)).tracking(0.5)
                .foregroundStyle(Color.drip.textTertiary)
        }
        .frame(width: 96, alignment: .leading)
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
        // Label the day by its KEY run (hardest), not the first (often easy) leg
        // of a doubles day — otherwise a track session reads as "Recovery".
        if let dom = vm.dominantSession(on: c.date) { return dom.typeLabel }
        if let first = ss.first { return first.typeLabel }
        return "Run"
    }

    private func sessionSub(_ c: DayCell, _ ss: [SessionDetail]) -> String {
        if c.isRest { return "Nothing logged" }
        if c.isFuture && c.miles == 0 { return "Upcoming" }
        var parts: [String] = []
        if c.miles > 0 { parts.append("\(DistanceFormat.value(miles: c.miles, unit: unit)) \(unit.short)") }   // whole-day total
        if let p = vm.dominantSession(on: c.date)?.pace {
            parts.append("\(DistanceFormat.convertPaceString(p, to: unit)) / \(unit.short)")
        }
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

// MARK: - Key-session star
//
// A filled five-point star marking a key session, drawn as a vector so it
// stays faithful to the design system (SF Symbols are flagged as an
// emoji-rule violation — see `MoodBadge` in DesignSystem.swift).

private struct FiveStar: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * 0.42
        var path = Path()
        for i in 0..<10 {
            let angle = -Double.pi / 2 + Double(i) * Double.pi / 5
            let r = i.isMultiple(of: 2) ? outer : inner
            let pt = CGPoint(x: center.x + CGFloat(cos(angle)) * r,
                             y: center.y + CGFloat(sin(angle)) * r)
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        path.closeSubpath()
        return path
    }
}
