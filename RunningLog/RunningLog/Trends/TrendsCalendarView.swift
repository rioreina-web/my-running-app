//
//  TrendsCalendarView.swift
//  RunningLog · Trends
//
//  The Trends-v2 primary chart: the block as a calendar. A calendar grid,
//  NOT a time series — the one thing a time axis structurally can't show is
//  which weekday, and weekday rhythm is where a self-coached runner's habits
//  live (Mon off, Tue quality, Sun long). Consumes `TrendsService.days`
//  (`buildDailyTimeline`), so bars, mood and niggles can't drift from the
//  weekly rollup.
//
//  Encoding (from `trends-v2-spec-2026-07-30.md` §4, adopted from
//  `calendar-month-prototype`):
//    • Volume     — bar height, bottom-anchored, FIXED 0–20 mi scale so
//                   months compare. A cell IS a bar-chart bar.
//    • Session    — bar fill: coral = key · dark grey = long · light grey =
//                   easy. One coral; intensity is the only accent.
//    • Mood       — a strip on the bottom edge, full width, rest days too
//                   (mood isn't a property of a run).
//    • Niggle     — a bar on the left edge, opacity by the athlete's own
//                   severity word (never a number).
//  Plus: date numeral top-left, coral dot top-right on key days, coral ring
//  on today, and a week-total rail as an eighth column inside the grid.
//
//  Month/Block only (the day cell needs room). Season is a separate dense
//  heatmap — a later slice.
//

import SwiftUI

// MARK: - Scale

/// The Trends-v2 time scale. Month/Block render the full day-cell grid;
/// Season (a dense year heatmap) is a separate view, added later.
enum TrendsCalendarScale: Int, CaseIterable, Identifiable {
    case month = 28
    case block = 84

    var id: Int { rawValue }
    var label: String { self == .month ? "Month" : "Block" }
    /// Row height for the day cell — Month gets the full bar, Block is denser.
    var cellHeight: CGFloat { self == .month ? 62 : 48 }
}

// MARK: - Calendar view

struct TrendsCalendarView: View {
    /// Dense daily substrate, oldest → newest (one entry per day through today).
    let days: [TrendsDay]
    let scale: TrendsCalendarScale
    /// Tapping a day with runs drills into that day's workouts.
    var onSelectDay: ((TrendsDay) -> Void)? = nil

    /// Fixed volume scale — a day's miles map to bar height against this, so a
    /// light month and a heavy month are drawn on one ruler. Spec §4.
    private let fixedMilesMax: Double = 20

    private static let weekdaySymbols = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        let rows = Self.weekRows(days.suffix(scale.rawValue))
        let maxWeekMiles = max(rows.map { $0.totalMiles }.max() ?? 1, 1)

        VStack(alignment: .leading, spacing: 0) {
            headerRow
            ForEach(rows) { row in
                weekRow(row, maxWeekMiles: maxWeekMiles)
            }
        }
    }

    // MARK: Header (weekday letters + WEEK rail label)

    private var headerRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(Self.weekdaySymbols.enumerated()), id: \.offset) { _, sym in
                Text(sym)
                    .font(.dripCaption(9))
                    .foregroundStyle(Color.drip.textTertiary)
                    .frame(maxWidth: .infinity)
            }
            Text("WEEK")
                .font(.dripCaption(9))
                .foregroundStyle(Color.drip.textTertiary)
                .frame(width: 40, alignment: .trailing)
        }
        .padding(.bottom, 5)
    }

    // MARK: One week (7 day cells + the rail)

    private func weekRow(_ row: WeekRow, maxWeekMiles: Double) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { col in
                if let day = row.days[col] {
                    dayCell(day)
                        .frame(maxWidth: .infinity)
                        .frame(height: scale.cellHeight)
                        .contentShape(Rectangle())
                        .onTapGesture { if day.miles > 0 { onSelectDay?(day) } }
                } else {
                    // A day outside the window edge (partial first/last week).
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(height: scale.cellHeight)
                }
            }
            weekRail(row, maxWeekMiles: maxWeekMiles)
                .frame(width: 40, height: scale.cellHeight)
        }
    }

    // MARK: The day cell — a bar-chart bar with four channels

    private func dayCell(_ day: TrendsDay) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let barTop: CGFloat = 15                 // below the date numeral
            let moodStrip: CGFloat = 3.5
            let barArea = h - barTop - moodStrip - 4
            let barH = day.miles > 0
                ? max(3, min(1, day.miles / fixedMilesMax) * barArea)
                : 0
            let barWidth = min(20, w * 0.5)

            ZStack(alignment: .topLeading) {
                // Cell ground.
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(Color.drip.background)

                // Date numeral, top-left.
                Text("\(day.dayOfMonth)")
                    .font(.system(size: 7.5, design: .monospaced))
                    .foregroundStyle(Color.drip.textTertiary)
                    .padding(.leading, 4)
                    .padding(.top, 2)

                // Volume bar, bottom-anchored (above the mood strip).
                if barH > 0 {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(fill(for: day.type))
                        .frame(width: barWidth, height: barH)
                        .position(x: w / 2, y: barTop + barArea - barH / 2)
                }

                // Key-session dot, top-right.
                if day.type == .key {
                    Circle()
                        .fill(Color.drip.coral)
                        .frame(width: 4, height: 4)
                        .position(x: w - 6, y: 8)
                }

                // Mood: full-width strip on the bottom edge — rest days too.
                if let mood = day.mood, !mood.isEmpty {
                    RoundedRectangle(cornerRadius: 1.4)
                        .fill(TrendsMoodColor.color(mood).opacity(0.85))
                        .frame(height: moodStrip)
                        .padding(.horizontal, 1)
                        .position(x: w / 2, y: h - moodStrip / 2 - 1)
                }

                // Niggle: left edge, opacity by the athlete's own severity word.
                if let n = day.niggles.first {
                    RoundedRectangle(cornerRadius: 1.2)
                        .fill(Color.drip.injured.opacity(Self.severityOpacity(n.severity)))
                        .frame(width: 2.5)
                        .padding(.vertical, 1)
                        .position(x: 1.75, y: h / 2)
                }

                // Today — coral inset ring.
                if day.isToday {
                    RoundedRectangle(cornerRadius: 2.5)
                        .stroke(Color.drip.coral, lineWidth: 1.5)
                        .padding(1)
                }
            }
        }
        .padding(1)
    }

    // MARK: The week rail (eighth column, inside the grid)

    private func weekRail(_ row: WeekRow, maxWeekMiles: Double) -> some View {
        let partial = row.days.compactMap { $0 }.count < 7
        return VStack(alignment: .trailing, spacing: 3) {
            Text("\(Int(row.totalMiles.rounded()))")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(partial ? Color.drip.textTertiary : Color.drip.textPrimary)
            Text(partial ? "PART" : "MI")
                .font(.system(size: 6, design: .monospaced))
                .foregroundStyle(Color.drip.textTertiary)
            // Rail bar — scaled to the window's biggest week. Neutral ink, never
            // ACWR-keyed (spec §9.1 killed the ratio).
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.drip.paperDeep)
                    Capsule()
                        .fill(partial ? Color.drip.textTertiary : Color.drip.textSecondary)
                        .frame(width: geo.size.width * CGFloat(row.totalMiles / maxWeekMiles))
                }
            }
            .frame(height: 3)
            .padding(.top, 1)
        }
        .padding(.trailing, 2)
        .padding(.top, 2)
    }

    // MARK: Channel fill — session type, NOT pace zone (spec §4)

    private func fill(for type: TrendsDay.SessionChannel) -> Color {
        switch type {
        case .key:  Color.drip.coral
        case .long: Color.drip.textSecondary          // dark warm grey
        case .easy: Color.drip.textTertiary.opacity(0.55) // light warm grey
        case .rest: Color.clear
        }
    }

    /// Severity word → opacity, from the athlete's own vocabulary (never a
    /// number). Unknown words land mid-ramp rather than invisible.
    private static func severityOpacity(_ severity: String?) -> Double {
        switch (severity ?? "").lowercased() {
        case "slight", "sore":            0.4
        case "tight", "a bit ropey":      0.65
        case "grumbling", "pain":         0.85
        case "noticeable", "sharp":       1.0
        default:                          0.7
        }
    }
}

// MARK: - Week bucketing (Monday-first rows)

/// One Monday-first calendar row: 7 slots, `nil` where the window doesn't cover
/// that weekday (partial first/last week).
private struct WeekRow: Identifiable {
    let id: String              // the row's Monday date
    let days: [TrendsDay?]      // exactly 7, Monday…Sunday
    var totalMiles: Double { days.compactMap { $0?.miles }.reduce(0, +) }
}

private extension TrendsCalendarView {
    /// Group a dense daily slice into Monday-first rows. A new row starts on
    /// each Monday (weekday col 0), matching the prototype's `calGrid`.
    static func weekRows(_ slice: ArraySlice<TrendsDay>) -> [WeekRow] {
        var rows: [WeekRow] = []
        var current: [TrendsDay?] = []
        var rowKey = ""
        for day in slice {
            let col = day.mondayFirstWeekday
            if current.isEmpty || col == 0 {
                if !current.isEmpty {
                    while current.count < 7 { current.append(nil) }
                    rows.append(WeekRow(id: rowKey, days: current))
                }
                current = Array(repeating: nil, count: 7)
                rowKey = day.date
            }
            if col < 7 { current[col] = day }
        }
        if !current.isEmpty {
            while current.count < 7 { current.append(nil) }
            rows.append(WeekRow(id: rowKey, days: current))
        }
        return rows
    }
}

// MARK: - Day date helpers (UTC, matching the endpoint's day keys)

extension TrendsDay {
    /// "yyyy-MM-dd" → the components, parsed in UTC to match `buildDailyTimeline`.
    private var utcComponents: DateComponents? {
        let parts = date.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        return DateComponents(year: y, month: m, day: d)
    }

    private var utcDate: Date? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return utcComponents.flatMap { cal.date(from: $0) }
    }

    /// Day-of-month numeral for the cell (0 if unparseable).
    var dayOfMonth: Int { utcComponents?.day ?? 0 }

    /// Monday-first weekday index: Mon = 0 … Sun = 6.
    var mondayFirstWeekday: Int {
        guard let d = utcDate else { return 0 }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let w = cal.component(.weekday, from: d) // 1=Sun … 7=Sat
        return (w + 5) % 7
    }

    /// True when this is the most recent day in the window (today).
    var isToday: Bool {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let today = cal.startOfDay(for: Date())
        guard let d = utcDate else { return false }
        return cal.isDate(d, inSameDayAs: today)
    }
}

// MARK: - Preview

#Preview("Calendar · Month") {
    TrendsCalendarView(days: TrendsDay.previewMonth, scale: .month)
        .padding()
        .background(Color.drip.background)
}

extension TrendsDay {
    /// A "good data, hard block" arc — 12 weeks of a watch-worn athlete
    /// building volume into a heavy final week, with a fortnight of tired days
    /// and three right-achilles mentions in the recent big weeks. Long enough
    /// (84 days) to feed the calendar (Month/Block), the verdict, and the
    /// recovery day/week reads. Demo data for reviewing the populated surface.
    static var previewMonthRich: [TrendsDay] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let today = cal.startOfDay(for: Date())
        let fmt = DateFormatter()
        fmt.timeZone = TimeZone(identifier: "UTC")!
        fmt.dateFormat = "yyyy-MM-dd"

        // Monday-align the start so weekly targets map cleanly to Mon–Sun weeks
        // (the recovery week model groups by ISO Monday). The final week is the
        // current, partial one (Mon…today).
        let todayDow = (cal.component(.weekday, from: today) + 5) % 7   // Mon=0
        let thisMonday = cal.date(byAdding: .day, value: -todayDow, to: today)!
        let startMonday = cal.date(byAdding: .day, value: -11 * 7, to: thisMonday)!
        let n = (cal.dateComponents([.day], from: startMonday, to: today).day ?? 0) + 1
        // Weekly mileage arc; the spike (60) is week 10 — the last COMPLETE
        // week — so the overload read fires on a full week, and week 11 is the
        // current partial week.
        let targets: [Double] = [34, 38, 36, 42, 45, 40, 47, 49, 44, 51, 60, 40]
        let share: [Double] = [0, 0.17, 0.13, 0.15, 0.10, 0.13, 0.30]   // Mon…Sun
        let warm = ["energized", "positive", "neutral", "positive", "energized"]
        let heavy = ["tired", "struggling", "tired", "neutral", "tired"]

        return (0..<n).map { i in
            let d = cal.date(byAdding: .day, value: i, to: startMonday)!
            let back = n - 1 - i
            let dow = i % 7                                   // Mon=0 (start is a Monday)
            let target = targets[min(targets.count - 1, i / 7)]
            let type: SessionChannel = dow == 0 ? .rest : dow == 1 ? .key : dow == 6 ? .long : .easy
            let miles = type == .rest ? 0 : (target * share[dow] * 10).rounded() / 10
            let recent = back < 14   // last fortnight reads tired
            let mood = type == .rest
                ? (recent ? "tired" : "positive")
                : (recent ? heavy[dow % heavy.count] : warm[dow % warm.count])
            // Achilles mentions on Sundays of the recent, bigger weeks.
            let niggles: [DayNiggle] = (dow == 6 && (i / 7) >= 6 && (i / 7) % 2 == 0)
                ? [DayNiggle(area: "achilles", side: "right", severity: "grumbling",
                             quote: "same right achilles — noticeable on the stairs after")]
                : []
            return TrendsDay(date: fmt.string(from: d), miles: miles, type: type, mood: mood, niggles: niggles)
        }
    }
}

extension TrendsDay {
    /// 28 days of synthetic data for previews — a build with a key Tuesday,
    /// a long Sunday, a rest Monday, and one achilles niggle.
    static var previewMonth: [TrendsDay] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let today = cal.startOfDay(for: Date())
        let fmt = DateFormatter()
        fmt.timeZone = TimeZone(identifier: "UTC")!
        fmt.dateFormat = "yyyy-MM-dd"
        return (0..<28).reversed().map { back in
            let d = cal.date(byAdding: .day, value: -back, to: today)!
            let wd = (cal.component(.weekday, from: d) + 5) % 7   // Mon=0
            let (type, miles): (SessionChannel, Double) = {
                switch wd {
                case 0: return (.rest, 0)
                case 1: return (.key, 7)
                case 6: return (.long, 15)
                default: return (.easy, Double.random(in: 4...8))
                }
            }()
            let moods = ["energized", "positive", "neutral", "tired", "positive"]
            // Two right-achilles mentions in the recent Sundays — enough for
            // the recovery card's niggle signal to read a repeat area.
            let niggles: [DayNiggle] = (wd == 6 && back < 18)
                ? [DayNiggle(area: "achilles", side: "right", severity: "tight",
                             quote: "tight right achilles on the last two miles")]
                : []
            return TrendsDay(
                date: fmt.string(from: d),
                miles: miles,
                type: type,
                mood: type == .rest && Bool.random() ? nil : moods[wd % moods.count],
                niggles: niggles
            )
        }
    }
}
