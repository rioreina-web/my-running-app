//
//  GoalPaceGridPlot.swift
//  RunningLog · Trends
//
//  The actual grid renderer, shared by GoalPaceGridCard (compact glance) and
//  GoalPaceGridDetailView (full-screen, larger cells + a session list).
//  ONE renderer at two sizes — the pattern `KeyPaceChart`/`KeyPaceCard`/
//  `KeyPaceDetailView` already established in this app — so the card and its
//  detail can never disagree about the same sessions. Card and detail differ
//  only in `cellWidth` / `rowHeight` / `leftGutter`.
//

import SwiftUI

struct GoalPaceGridPlot: View {
    let data: GoalPaceGridData
    let filter: GoalPaceGridFilter
    let heatAdjusted: Bool
    @Binding var selected: GoalPaceGridDeposit?

    var cellWidth: CGFloat = 7
    var rowHeight: CGFloat = 24
    var leftGutter: CGFloat = 40

    /// DAY columns, not weeks (2026-09-01). `weeks` is kept as the name here
    /// only where the surrounding code still reads as "columns"; every bucket
    /// below is one calendar day.
    private var weeks: [Date] { data.days() }

    // Bucket through the SAME `mondayOfWeek` function `weeks`/`grid` use —
    // never `Calendar`'s `.weekOfYear` granularity match against a
    // differently-configured calendar. Those disagreeing is exactly what made
    // an earlier build default-scroll to the race week: `Calendar.current`'s
    // locale first-weekday (often Sunday) doesn't line up with the
    // Monday-anchored `weeks` array, the granularity match silently found
    // nothing, and the `?? weeks.count - 1` fallback landed on the LAST
    // column — race week — every time.
    // The real bug behind "there's no volume in here": this used the DEVICE'S
    // raw system clock to find "today"'s column. If that clock doesn't fall
    // inside the week range this athlete's data actually spans, the lookup
    // finds nothing and fell through to `weeks.count - 1` — the LAST column,
    // which is the race week, empty by construction (nobody has run it yet).
    // The grid was opening scrolled onto blank space, not actually missing
    // any training. Anchoring to the last week that HAS deposits instead of
    // the calendar's idea of "today" means this can never open empty as long
    // as the athlete has logged anything, regardless of what the device clock
    // says relative to the data.
    var todayIndex: Int {
        let today = Calendar.current.startOfDay(for: Date())
        if let idx = weeks.firstIndex(of: today) { return idx }
        let daysWithData = Set(data.deposits.map { Calendar.current.startOfDay(for: $0.date) })
        return weeks.lastIndex(where: daysWithData.contains) ?? max(weeks.count - 1, 0)
    }
    private var raceIndex: Int? {
        guard let race = data.goal.raceDate else { return nil }
        return weeks.firstIndex(of: Calendar.current.startOfDay(for: race))
    }

    var body: some View {
        let contentWidth = leftGutter + CGFloat(weeks.count) * cellWidth
        let contentHeight = CGFloat(data.rowLabels.count) * rowHeight + 18

        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    rowGrounds
                    goalLine
                    weekTicks
                    todayMarker
                    raceMarker
                    mileDots
                    weekAnchors
                }
                .frame(width: contentWidth, height: contentHeight, alignment: .topLeading)
            }
            .frame(height: contentHeight)
            .onAppear {
                // Opens on today, not the race — the empty runway ahead is
                // information, not a default to scroll past.
                //
                // Target a dedicated, uniquely-keyed anchor (String
                // "week-N"), never a bare Int. `rowGrounds` and `cells` both
                // tag their content with plain Int ids (0..<rowLabels.count)
                // for row identity — the same untyped Int space `todayIndex`
                // lives in. `scrollTo(todayIndex)` was matching a same-
                // numbered ROW strip instead of the intended week column;
                // those strips span the grid's full width, so `anchor:
                // .trailing` scrolled to THEIR trailing edge — the grid's
                // trailing edge — i.e. the race week, every time. That's the
                // actual mechanism behind "opens on the projected race date",
                // not a missing `.id()` or a `defaultScrollAnchor` leaking in
                // from elsewhere.
                //
                // scrollTo fired directly from onAppear is also a known
                // SwiftUI trap independent of the above: the horizontal
                // ScrollView frequently hasn't finished laying out its
                // content on the same run-loop turn this fires, so deferring
                // one turn is still needed for the offset to actually apply.
                DispatchQueue.main.async {
                    proxy.scrollTo("week-\(todayIndex)", anchor: .trailing)
                }
            }
        }
    }

    /// Zero-size markers, one per week, keyed by a String ("week-N") so they
    /// can never collide with the bare-Int row ids `rowGrounds`/`cells` use.
    /// Positioned at each week's actual x — unlike a full-width row strip,
    /// scrolling one of these to `.trailing` lands on that week specifically.
    private var weekAnchors: some View {
        ForEach(Array(weeks.enumerated()), id: \.offset) { i, _ in
            Color.clear
                .frame(width: 1, height: 1)
                .id("week-\(i)")
                .offset(x: leftGutter + CGFloat(i) * cellWidth + cellWidth / 2)
        }
    }

    private var rowGrounds: some View {
        VStack(spacing: 0) {
            ForEach(0..<data.rowLabels.count, id: \.self) { row in
                HStack(spacing: 0) {
                    // The PaceSpectrum swatch is where "colour == pace" lives
                    // on this chart. The cells encode miles in neutral ink, so
                    // without this the pace ramp would have no presence at all
                    // and the rows would read as anonymous bands.
                    HStack(spacing: 3) {
                        Text(data.rowLabels[row])
                            .font(.dripEyebrow(min(7.5, rowHeight / 3.2)))
                            .foregroundStyle(row == 3 ? Color.drip.textSecondary : Color.drip.textTertiary)
                        RoundedRectangle(cornerRadius: 1)
                            .fill(rowColor(row))
                            .frame(width: 3, height: max(rowHeight - 6, 4))
                    }
                        .frame(width: leftGutter, alignment: .trailing)
                        .padding(.trailing, 4)
                    Rectangle()
                        .fill(row == 3 ? Color(hex: "3F7CB5").opacity(0.08) : Color.clear)
                        .overlay(alignment: .top) {
                            if row > 0 {
                                Rectangle().fill(Color.drip.divider.opacity(0.5)).frame(height: 0.5)
                            }
                        }
                }
                .frame(height: rowHeight)
            }
        }
        .frame(width: leftGutter + CGFloat(weeks.count) * cellWidth, alignment: .leading)
    }

    /// The true 100% boundary sits between row 3 (100–105) and row 4 (95–100).
    private var goalLine: some View {
        Rectangle()
            .fill(Color.drip.textPrimary.opacity(0.6))
            .frame(width: leftGutter + CGFloat(weeks.count) * cellWidth, height: 1)
            .offset(y: 4 * rowHeight)
    }

    private var weekTicks: some View {
        ForEach(Array(weeks.enumerated()), id: \.offset) { i, w in
            if isFirstOfMonth(w) {
                Text(monthLabel(w))
                    .font(.dripEyebrow(7))
                    .foregroundStyle(Color.drip.textTertiary)
                    .position(
                        x: leftGutter + CGFloat(i) * cellWidth + cellWidth / 2,
                        y: CGFloat(data.rowLabels.count) * rowHeight + 9
                    )
            }
        }
    }

    private var todayMarker: some View {
        Rectangle()
            .fill(Color.drip.textTertiary)
            .frame(width: 1, height: CGFloat(data.rowLabels.count) * rowHeight)
            .offset(x: leftGutter + CGFloat(todayIndex) * cellWidth + cellWidth / 2)
    }

    @ViewBuilder
    private var raceMarker: some View {
        if let ri = raceIndex {
            VStack(spacing: 2) {
                Text("RACE")
                    .font(.dripEyebrow(7))
                    .foregroundStyle(Color.drip.textPrimary)
                Rectangle()
                    .fill(Color.drip.textPrimary)
                    .frame(width: 1.2, height: CGFloat(data.rowLabels.count) * rowHeight - 10)
            }
            .offset(x: leftGutter + CGFloat(ri) * cellWidth + cellWidth / 2 - 15, y: -12)
        }
    }

    /// EVERY SPLIT IS A MARK, SIZED BY ITS REAL DISTANCE (Rio, 2026-09-01:
    /// "splits will be less than a mile like track intervals, make them
    /// smaller and if there's a lot of paces in the same range, make it
    /// bigger").
    ///
    /// So a 400m rep is a small mark and a 19-mile easy day is a large one,
    /// because the mark's AREA is the miles it stands for. Splits that land
    /// on the same day at the same pace band merge into one mark and grow —
    /// six 1k reps at the same pace read as one substantial mark rather than
    /// six identical specks.
    ///
    /// Area, not edge length, carries the value: side = sqrt(miles) × scale,
    /// so a 4-mile mark is twice the width of a 1-mile mark and four times
    /// the ink, which is what the eye actually compares.
    ///
    /// `PaceSpectrum` colours each mark by ITS OWN pace, which is what that
    /// ramp means everywhere else in the product. Height says the same thing,
    /// so colour and position agree instead of competing.
    private var mileDots: some View {
        let dayIndex: [Date: Int] = Dictionary(
            uniqueKeysWithValues: weeks.enumerated().map { ($1, $0) }
        )
        // Merge splits that share a day AND a pace band, weighting the pace
        // by distance so the mark sits at the true centre of the work it
        // represents rather than at whichever split happened to be first.
        var groups: [String: (day: Int, row: Int, miles: Double, paceWeighted: Double)] = [:]
        for d in data.deposits(for: filter) {
            let day = Calendar.current.startOfDay(for: d.date)
            guard let di = dayIndex[day] else { continue }
            let pct = heatAdjusted ? d.pctOfGoalHeatAdj : d.pctOfGoal
            let row = heatAdjusted ? d.paceRowHeatAdj : d.paceRow
            let key = "\(di)-\(row)"
            let prev = groups[key] ?? (di, row, 0, 0)
            groups[key] = (di, row, prev.miles + d.miles,
                           prev.paceWeighted + pct * d.miles)
        }
        let marks = groups.values.map {
            SplitMark(day: $0.day, row: $0.row, miles: $0.miles,
                      pct: $0.miles > 0 ? $0.paceWeighted / $0.miles : 100)
        }
        let scale = markScale(marks)
        return ForEach(marks) { m in
            let side = max(CGFloat(sqrt(m.miles)) * scale, minMarkSide)
            Rectangle()
                .fill(rowColor(m.row))
                .frame(width: side, height: side)
                .cornerRadius(min(1.5, side / 4))
                .position(
                    x: leftGutter + CGFloat(m.day) * cellWidth + cellWidth / 2,
                    y: y(forPct: m.pct)
                )
                .onTapGesture { selected = deposit(atRow: m.row, week: m.day) }
        }
    }

    private struct SplitMark: Identifiable {
        var id: String { "\(day)-\(row)" }
        let day: Int
        let row: Int
        let miles: Double
        let pct: Double
    }

    /// A sub-mile rep must stay visibly small, so the floor is deliberately
    /// tiny — but not zero-width, or a 400m rep would vanish entirely.
    private let minMarkSide: CGFloat = 2

    /// Scale chosen so the biggest single mark fits its row band. Pinned to
    /// the UNFILTERED set so switching to "Key sessions" shrinks the picture
    /// rather than silently rescaling it back to full size.
    private func markScale(_ marks: [SplitMark]) -> CGFloat {
        let dayIndex: [Date: Int] = Dictionary(
            uniqueKeysWithValues: weeks.enumerated().map { ($1, $0) }
        )
        var totals: [String: Double] = [:]
        for d in data.deposits {
            let day = Calendar.current.startOfDay(for: d.date)
            guard let di = dayIndex[day] else { continue }
            let row = heatAdjusted ? d.paceRowHeatAdj : d.paceRow
            totals["\(di)-\(row)", default: 0] += d.miles
        }
        let maxMiles = totals.values.max() ?? 1
        guard maxMiles > 0 else { return 1 }
        return (rowHeight * 1.6) / CGFloat(sqrt(maxMiles))
    }

    /// Continuous pace → y, across the same span the ten labelled bands
    /// cover, so a mark sits at its real pace and the row labels still read
    /// correctly as reference. 115%+ pins to the top, <75% to the bottom.
    private func y(forPct pct: Double) -> CGFloat {
        let top = 115.0, bottom = 75.0
        let clamped = min(max(pct, bottom), top)
        let t = (top - clamped) / (top - bottom)
        let usable = CGFloat(data.rowLabels.count) * rowHeight
        return CGFloat(t) * usable
    }

    private func deposit(atRow row: Int, week wi: Int) -> GoalPaceGridDeposit? {
        guard wi < weeks.count else { return nil }
        let day = weeks[wi]
        return data.deposits(for: filter).first {
            let r = heatAdjusted ? $0.paceRowHeatAdj : $0.paceRow
            return r == row && Calendar.current.startOfDay(for: $0.date) == day
        }
    }

    /// Row 0 (115%+, fastest) → Mile navy. Row 9 (<75%, slowest) → Easy pale.
    /// `PaceSpectrum.stops` runs slow→fast, so this reverses it to match row order.
    private func rowColor(_ row: Int) -> Color {
        let arr = Array(PaceSpectrum.stops.reversed())
        guard row >= 0, row < arr.count else { return Color.drip.textTertiary }
        return arr[row]
    }

    private func isFirstOfMonth(_ d: Date) -> Bool {
        Calendar.current.component(.day, from: d) == 1
    }
    private func monthLabel(_ d: Date) -> String {
        d.formatted(.dateTime.month(.abbreviated)).uppercased()
    }
}
