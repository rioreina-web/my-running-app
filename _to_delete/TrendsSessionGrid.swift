//
//  TrendsSessionGrid.swift
//  RunningLog
//
//  The Trends hero: a session grid.
//
//      y = day of week, Mon at top → Sun at bottom
//      x = week, oldest → newest (the same columns as UnifiedTrainingChart)
//      one dot per quality session, on the day it happened
//      SIZE   = effort (quality load)
//      COLOUR = the pace of its fast segments, on the canonical blue ramp
//
//  WHY DAY-OF-WEEK IS THE Y-AXIS
//  -----------------------------
//  Earlier passes plotted sessions by pace, which reads as a scatter the
//  athlete has to decode. Day-of-week is a *categorical* axis she already
//  carries in her head — she knows Tuesday is threshold day — so nothing
//  needs decoding, and it surfaces something no weekly-total chart can: the
//  weekly rhythm, and the weeks it breaks. On real prod data the Tuesday row
//  holds 10 of 19 sessions, Wednesday is a genuine second band, and Friday
//  is where the strides live.
//
//  Pace moves from position to colour. That costs precision and buys
//  legibility; exact paces belong in the readout, stated rather than
//  estimated off an axis. It also means nothing here ever draws a line
//  between sessions of different zones, so `keySessions.ts`' invariant —
//  "compare like with like: a dot is a single zone's work-bout pace" — holds
//  by construction rather than by care.
//
//  HONEST DEGRADATION
//  ------------------
//  • A session whose date won't parse is omitted, never defaulted onto Monday.
//  • A session below the effort floor draws an open ring, not a filled dot:
//    real work, not a key session. (Today `deriveKeySession` returns a
//    session for ANY work bout, so a single MP mile inside an easy run gets
//    the same visual weight as a 6×1mi. The floor is what fixes that.)
//  • No sessions at all → the empty-state component, never an em-dash
//    (hard rule #8).
//
//  Drawn with `Canvas`, matching `UnifiedTrainingChart`'s approach, and
//  sharing its `scrubIndex` binding so the grid and the tracks below it
//  scrub together.
//

import SwiftUI

// MARK: - Zone → colour

/// The work zones the backend classifier emits, mapped onto the canonical
/// pace ramp. Source of truth for the ramp is `PaceSpectrum.swift`; this is
/// only the token → stop mapping. Blue is pace, per the three-palette rule —
/// coral never appears here.
enum TrendsSessionZoneColor {
    static func color(_ zone: String) -> Color {
        switch zone.lowercased() {
        case "mile":     PaceSpectrum.mile
        case "3k":       PaceSpectrum.threeK
        case "5k":       PaceSpectrum.fiveK
        case "10k":      PaceSpectrum.tenK
        case "hmp":      PaceSpectrum.hmp
        case "mp":       PaceSpectrum.mp
        // Aerobic end of the same ramp — long runs live here. Still blue,
        // still pace; a long run is not an alert and not a mood.
        case "steady":   PaceSpectrum.steady
        case "moderate": PaceSpectrum.moderate
        default:         PaceSpectrum.easy
        }
    }

    /// Fast → slow, matching `KeyZone.order`.
    static let order = ["mile", "3k", "5k", "10k", "hmp", "mp"]
}

// MARK: - Grid

struct TrendsSessionGrid: View {
    /// The week columns. Must be the same array the tracks below render, so
    /// the columns line up. Requires `weekStart` to be populated.
    let weeks: [TrendsWeek]
    /// Every quality session in range, gated here rather than server-side so
    /// the floor is tunable without a deploy.
    let sessions: [KeySession]
    @Binding var scrubIndex: Int?

    // Geometry
    private let rowHeight: CGFloat = 19
    private let headerHeight: CGFloat = 16
    private let padL: CGFloat = 17   // gutter for the Mon→Sun labels
    private let padR: CGFloat = 8

    private var gridHeight: CGFloat { rowHeight * 7 }
    private var chartHeight: CGFloat { headerHeight + gridHeight + 4 }

    // MARK: marks

    /// One drawable mark. `qualifies` drives filled-vs-open.
    private struct Mark {
        let column: Int
        let row: Int
        let zone: String
        let load: Double
        let qualifies: Bool
        let isLongRun: Bool
    }

    /// Week-start → column. Weeks with no `weekStart` (e.g. sample data that
    /// predates the field) simply can't host a mark; the grid stays empty
    /// rather than guessing a column.
    private var columnForWeekStart: [String: Int] {
        var map: [String: Int] = [:]
        for (i, week) in weeks.enumerated() where !week.weekStart.isEmpty {
            map[week.weekStart] = i
        }
        return map
    }

    private var marks: [Mark] {
        let columns = columnForWeekStart
        guard !columns.isEmpty else { return [] }
        return sessions.compactMap { session -> Mark? in
            guard let start = TrendsWeekday.weekStart(from: session.date),
                  let column = columns[start],
                  let row = TrendsWeekday.index(from: session.date)
            else { return nil }
            let load = session.qualityLoad ?? 0
            return Mark(
                column: column,
                row: row,
                zone: session.zone,
                load: load,
                // Filled-vs-open follows the ONE definition, so this grid and
                // the Train calendar can never show a different set of key
                // days (KEY-SESSION-APPLY.md §Verify 7). A day the athlete
                // declared not-key draws open here even if it scored well;
                // a day they declared key draws filled even if it didn't.
                qualifies: KeySessionStore.shared.isKey(onDayKey: session.date),
                isLongRun: session.isLongRun
            )
        }
    }

    // MARK: body

    var body: some View {
        let all = marks
        if all.isEmpty {
            EmptyStateView(
                variant: .dataPending,
                eyebrow: "No key sessions yet",
                title: "Quality sessions land here on the day you ran them. Log a workout with laps and the grid fills in."
            )
            .padding(.vertical, 8)
        } else {
            GeometryReader { geo in
                let w = geo.size.width
                Canvas { ctx, size in
                    draw(ctx: ctx, w: size.width, marks: all)
                }
                .frame(width: w, height: chartHeight)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            scrubIndex = index(forX: value.location.x, width: w)
                        }
                )
                .accessibilityLabel(accessibilityText(all))
            }
            .frame(height: chartHeight)
        }
    }

    private func accessibilityText(_ all: [Mark]) -> String {
        let kept = all.filter(\.qualifies).count
        return "Key sessions grid. \(kept) qualifying sessions across \(weeks.count) weeks, "
             + "plotted by day of week. Dot size is effort, colour is pace zone."
    }

    // MARK: x mapping

    private func slot(_ w: CGFloat) -> CGFloat {
        guard !weeks.isEmpty else { return 0 }
        return (w - padL - padR) / CGFloat(weeks.count)
    }

    private func x(_ i: Int, _ w: CGFloat) -> CGFloat {
        padL + slot(w) * (CGFloat(i) + 0.5)
    }

    private func index(forX xPos: CGFloat, width w: CGFloat) -> Int {
        guard !weeks.isEmpty, slot(w) > 0 else { return 0 }
        let raw = Int((xPos - padL) / slot(w))
        return min(max(raw, 0), weeks.count - 1)
    }

    private func y(row: Int) -> CGFloat {
        headerHeight + CGFloat(row) * rowHeight + rowHeight / 2
    }

    // MARK: drawing

    private func draw(ctx: GraphicsContext, w: CGFloat, marks all: [Mark]) {
        label(ctx, "KEY SESSIONS", at: CGPoint(x: padL, y: headerHeight - 8), anchor: .leading)
        drawZoneLegend(ctx: ctx, w: w, marks: all)

        // ---- day rows ----
        for row in 0..<7 {
            let top = headerHeight + CGFloat(row) * rowHeight
            // Weekend wash, so the week reads as a shape not seven stripes.
            if row >= 5 {
                ctx.fill(
                    Path(CGRect(x: padL, y: top, width: w - padL - padR, height: rowHeight)),
                    with: .color(Color.drip.paperDeep.opacity(0.45))
                )
            }
            var rule = Path()
            rule.move(to: CGPoint(x: padL, y: top + rowHeight))
            rule.addLine(to: CGPoint(x: w - padR, y: top + rowHeight))
            ctx.stroke(rule, with: .color(Color.drip.divider.opacity(0.55)), lineWidth: 1)

            label(
                ctx, TrendsWeekday.initials[row],
                at: CGPoint(x: padL - 6, y: y(row: row)),
                anchor: .trailing,
                color: row >= 5 ? Color.drip.textTertiary : Color.drip.textSecondary
            )
        }

        // ---- scrub column ---- (drawn under the marks)
        if let s = scrubIndex, s >= 0, s < weeks.count {
            let cw = min(slot(w) * 0.9, 22)
            let rect = CGRect(x: x(s, w) - cw / 2, y: headerHeight, width: cw, height: gridHeight)
            ctx.fill(
                Path(roundedRect: rect, cornerRadius: 3),
                with: .color(Color.drip.coral.opacity(0.07))
            )
        }

        // ---- marks ----
        let qualifying = all.filter(\.qualifies)
        let loads = qualifying.map(\.load)
        let lo = loads.min() ?? 0
        let hi = loads.max() ?? 1
        let rCap = min(rowHeight / 2 - 1.5, slot(w) * 0.44, 8)
        func radius(_ load: Double) -> CGFloat {
            guard hi > lo else { return max(2.6, rCap * 0.75) }
            let t = (load - lo) / (hi - lo)
            return 2.6 + CGFloat(t.squareRoot()) * max(rCap - 2.6, 0)
        }

        // Below the floor first, so a qualifying session in the same cell
        // always draws on top of it.
        for mark in all where !mark.qualifies {
            let c = CGPoint(x: x(mark.column, w), y: y(row: mark.row))
            let r: CGFloat = 2.4
            ctx.stroke(
                Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                with: .color(Color.drip.textTertiary),
                lineWidth: 1.1
            )
        }

        for mark in qualifying {
            let c = CGPoint(x: x(mark.column, w), y: y(row: mark.row))
            let r = radius(mark.load)
            // Paper ring keeps two marks in adjacent columns separable.
            let halo = r + 1.2
            ctx.fill(
                Path(ellipseIn: CGRect(x: c.x - halo, y: c.y - halo, width: halo * 2, height: halo * 2)),
                with: .color(Color.drip.background)
            )
            ctx.fill(
                Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                with: .color(TrendsSessionZoneColor.color(mark.zone))
            )
        }
    }

    /// Zone identity is never colour-alone — the ramp's adjacent steps sit
    /// close together by design, so the zones present get an inline key.
    private func drawZoneLegend(ctx: GraphicsContext, w: CGFloat, marks all: [Mark]) {
        let kept = all.filter(\.qualifies)
        var present = Set(kept.filter { !$0.isLongRun }.map { $0.zone.lowercased() })
            .sorted { a, b in
                let ia = TrendsSessionZoneColor.order.firstIndex(of: a) ?? 99
                let ib = TrendsSessionZoneColor.order.firstIndex(of: b) ?? 99
                return ia < ib
            }
        // Long runs collapse to one entry rather than listing every aerobic
        // zone they happened to land in — the session type is the useful
        // distinction, not whether a given Saturday drifted to steady.
        let anyLong = kept.contains(where: \.isLongRun)
        if anyLong { present.append("long") }
        guard !present.isEmpty else { return }

        var cursor = w - padR
        for zone in present.reversed() {
            let text = zone == "long" ? "Long" : KeyZone.label(zone)
            label(
                ctx, text,
                at: CGPoint(x: cursor, y: headerHeight - 8),
                anchor: .trailing,
                color: Color.drip.textSecondary
            )
            cursor -= CGFloat(text.count) * 5.0 + 5
            let swatch = CGRect(x: cursor, y: headerHeight - 12, width: 5, height: 5)
            ctx.fill(
                Path(roundedRect: swatch, cornerRadius: 1),
                with: .color(zone == "long"
                    ? PaceSpectrum.easy
                    : TrendsSessionZoneColor.color(zone))
            )
            cursor -= 9
        }
    }

    // MARK: text helper

    private func label(
        _ ctx: GraphicsContext,
        _ string: String,
        at point: CGPoint,
        anchor: UnitPoint,
        color: Color = Color.drip.textTertiary
    ) {
        let text = Text(string)
            .font(.system(size: 8.5, weight: .medium, design: .monospaced))
            .foregroundColor(color)
        ctx.draw(text, at: point, anchor: anchor)
    }
}

// MARK: - Readout helper

extension TrendsSessionGrid {
    /// The scrubbed week's sessions, in the order they happened, as
    /// "Tue HMP 6:44 · Thu 3K 5:51". Minutes and paces are real numbers the
    /// athlete can check; the load score drives dot size and is never printed.
    static func sessionSummary(for week: TrendsWeek, sessions: [KeySession]) -> [String] {
        guard !week.weekStart.isEmpty else { return [] }
        return sessions
            .filter { TrendsWeekday.weekStart(from: $0.date) == week.weekStart }
            .sorted { ($0.date) < ($1.date) }
            .map { session in
                let day = TrendsWeekday.index(from: session.date)
                    .map { TrendsWeekday.names[$0] } ?? ""
                // A long run reports its distance, not a pace zone: its pace is
                // the whole run's mean and isn't comparable to a work-bout pace.
                let base: String
                if session.isLongRun {
                    let miles = session.distanceMi.map { "\(($0 * 10).rounded() / 10) mi" } ?? ""
                    base = "\(day) Long \(miles)".trimmingCharacters(in: .whitespaces)
                } else {
                    base = "\(day) \(KeyZone.label(session.zone)) \(TrendsFormat.pace(session.workPaceSec))"
                }
                return KeySessionStore.shared.isKey(onDayKey: session.date)
                    ? base
                    : base + " (below floor)"
            }
    }
}
