//
//  TrendsWeekSheet.swift
//  RunningLog · Trends
//
//  The week drill-down. Above 120 days the signal lanes bucket weekly, and
//  until now a weekly column was a dead end: you could scrub it, read its
//  summary, and go no further — "rather than offering a dead tap", as the
//  lanes' own comment put it. Honest, but the athlete's next question after
//  "that week was heavy" is *show me that week*.
//
//  Everything here is already on device. The sheet reads `TrendsService.days`
//  — the same dense daily series the chart is built from — sliced to the
//  tapped week, and fires no network call of its own. Only opening a day
//  fetches, through the same `TrendsService.resolveDay` the day-grain tap
//  uses, so a day opens on the same session either way.
//
//  Nothing is invented. A day with no logged mood renders no mood; a day with
//  no run renders no distance. Absence is a fact about the week, not a gap to
//  fill.
//

import SwiftUI

// MARK: - Payload

/// One ISO week, resolved from the timeline the tab already holds.
struct TrendsWeekDrill: Identifiable {
    /// The week's Monday — stable, so re-tapping the same column doesn't
    /// rebuild the sheet.
    var id: String { startISO }
    let startISO: String
    /// The column's own label, so the sheet's title matches what was tapped.
    let label: String
    let rows: [Row]

    /// A day of the week, with the channel the chart would have drawn it in.
    struct Row: Identifiable {
        var id: String { day.date }
        let day: TrendsDay
        let channel: TrendsSessionChannel

        var hasRun: Bool { day.miles > 0 }
    }

    /// Build from `TrendsService.days`. Days are matched by week-start rather
    /// than by counting seven forward, which is the same grouping
    /// `weekBuckets` uses — a partial current week yields the days that exist
    /// rather than six blanks.
    static func make(
        weekStartISO: String,
        label: String,
        days: [TrendsDay],
        keySessions: [KeySession]
    ) -> TrendsWeekDrill {
        let weekDays = days.filter {
            TrendsWeekday.weekStart(from: $0.date) == weekStartISO
        }
        let channels = TrendsSignalBuilder.channels(for: weekDays, keySessions: keySessions)
        return TrendsWeekDrill(
            startISO: weekStartISO,
            label: label,
            rows: weekDays.map { Row(day: $0, channel: channels[$0.date] ?? .rest) }
        )
    }

    var totalMiles: Double { rows.reduce(0) { $0 + $1.day.miles } }
    var keyCount: Int { rows.filter { $0.channel.isKey }.count }
    var isAllRest: Bool { rows.allSatisfy { !$0.hasRun } }
}

// MARK: - Sheet

struct TrendsWeekSheet: View {
    let drill: TrendsWeekDrill
    let service: TrendsService

    @Environment(\.dismiss) private var dismiss
    /// The pager stacks on top of this sheet rather than replacing it, so
    /// dismissing a workout returns to the week it was opened from.
    @State private var dayWorkouts: DayWorkouts?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                headerBlock

                if drill.isAllRest {
                    EmptyStateView(
                        variant: .optionalEmpty,
                        eyebrow: "A week off",
                        title: "No runs logged this week. Rest weeks are part of the arc — the lanes still count it."
                    )
                    .padding(.top, 32)
                } else {
                    ForEach(Array(drill.rows.enumerated()), id: \.element.id) { index, row in
                        dayRow(row)
                        if index < drill.rows.count - 1 {
                            Divider().overlay(Color.drip.divider)
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 40)
        }
        .background(Color.drip.background)
        .presentationDetents([.medium, .large])
        .sheet(item: $dayWorkouts) { dw in
            HistoryDetailPager(entries: dw.entries, initial: dw.initial, onUpdate: {})
        }
    }

    // MARK: Header

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            DripEyebrow(text: "Week of \(drill.label)")
            Text(summary.uppercased())
                .font(.dripEyebrow(9))
                .tracking(1.1)
                .foregroundStyle(Color.drip.textTertiary)
            Divider().overlay(Color.drip.divider).padding(.top, 10)
        }
    }

    /// Counted from the rows on screen, never from the bucket — the sheet and
    /// its own list cannot disagree.
    private var summary: String {
        let miles = String(format: "%.1f mi", drill.totalMiles)
        let key = drill.keyCount == 1 ? "1 key session" : "\(drill.keyCount) key sessions"
        return "\(miles) · \(key) · \(drill.rows.count) days"
    }

    // MARK: Rows

    /// The log-feed register: date rail, then what happened. A day with no run
    /// keeps its rail and says so plainly rather than going blank.
    @ViewBuilder
    private func dayRow(_ row: TrendsWeekDrill.Row) -> some View {
        let content = HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 2) {
                Text(dayNumber(row.day.date))
                    .font(.dripDisplay(22))
                    .foregroundStyle(row.hasRun ? Color.drip.textPrimary : Color.drip.textTertiary)
                    .monospacedDigit()
                Text(weekdayName(row.day.date).uppercased())
                    .font(.dripEyebrow(9))
                    .tracking(1.0)
                    .foregroundStyle(Color.drip.textTertiary)
            }
            .frame(width: 56, alignment: .trailing)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(row.hasRun ? row.channel.readoutLabel.capitalized : "Rest")
                        .font(.dripDisplay(17))
                        .foregroundStyle(row.hasRun ? Color.drip.textPrimary : Color.drip.textSecondary)
                    if row.hasRun {
                        Text(String(format: "%.1f mi", row.day.miles))
                            .font(.dripStat(15))
                            .foregroundStyle(Color.drip.coral)
                            .monospacedDigit()
                    }
                    // No mood logged means no mood shown. Never a placeholder.
                    if let mood = row.day.mood, !mood.isEmpty {
                        MoodLabel(mood: mood)
                    }
                    Spacer(minLength: 0)
                    if row.hasRun {
                        Text("›")
                            .font(.dripLabel(14))
                            .foregroundStyle(Color.drip.textTertiary)
                    }
                }
                if !row.day.niggles.isEmpty {
                    Text(niggleLine(row.day.niggles).uppercased())
                        .font(.dripEyebrow(8.5))
                        .tracking(0.7)
                        .foregroundStyle(Color.drip.injured)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())

        if row.hasRun {
            Button { open(row.day.date) } label: { content }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Opens this day's workouts")
        } else {
            content
                .accessibilityElement(children: .combine)
        }
    }

    /// Areas only, comma-separated. The verbatim quote lives in the log and in
    /// the chart readout; repeating it here would put the athlete's words in a
    /// third register.
    private func niggleLine(_ niggles: [TrendsDay.DayNiggle]) -> String {
        let areas = niggles.map(\.area)
        var seen = Set<String>()
        let unique = areas.filter { seen.insert($0.lowercased()).inserted }
        return unique.joined(separator: ", ")
    }

    private func open(_ dayISO: String) {
        Task {
            if let dw = await service.resolveDay(dayISO: dayISO) {
                dayWorkouts = dw
            }
        }
    }

    // MARK: Labels

    private func dayNumber(_ iso: String) -> String {
        let parts = iso.prefix(10).split(separator: "-")
        guard parts.count == 3, let d = Int(parts[2]) else { return iso }
        return "\(d)"
    }

    private func weekdayName(_ iso: String) -> String {
        guard let i = TrendsWeekday.index(from: iso) else { return "" }
        return TrendsWeekday.names[i]
    }
}
