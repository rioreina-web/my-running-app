//
//  LogView.swift
//  RunningLog
//
//  The Log tab — the full training log. Every run, newest first.
//  Editorial style matches the web coach roster's athlete deep-dive
//  and the iOS Today home: hushed dates, serif numerals, mood pills,
//  optional injury flag inline.
//
//  This is the "log" job from the four-job mission: AI-assisted
//  training log with good insight and great data analytics to guide
//  a runner. The log is the foundation; everything else reads from
//  the rows here.
//

import SwiftUI

struct LogView: View {
    @State private var rows: [TodayLogRow] = []
    @State private var loaded = false
    @State private var loadFailed = false
    @State private var showVoiceSheet = false

    private let cal = Calendar.current

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                if !loaded {
                    Text("Loading…")
                        .font(.dripBody(13))
                        .foregroundStyle(Color.drip.textTertiary)
                } else if loadFailed {
                    EmptyStateView(
                        variant: .error,
                        eyebrow: "Couldn't load",
                        title: "Your log didn't load. Check your connection and try again.",
                        cta: .init(label: "Retry") {
                            Task { await load() }
                        }
                    )
                } else if rows.isEmpty {
                    emptyState
                } else {
                    // Week-grouped feed with sticky headers (pinnedViews) + a
                    // per-week mileage subtotal — "THIS WEEK · 32 MI".
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(weekGroups) { week in
                            Section {
                                ForEach(week.rows, id: \.id) { row in
                                    LogRowView(row: row)
                                        .padding(.vertical, 9)
                                }
                            } header: {
                                weekHeader(week)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .background(Color.drip.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .sheet(isPresented: $showVoiceSheet) {
            NavigationStack { VoiceLogView() }
        }
    }

    private func load() async {
        loadFailed = false
        do {
            let fetched = try await TodayLogRow.fetchRecentThrowing(days: 180)
            await MainActor.run {
                rows = fetched
                loaded = true
            }
        } catch {
            await MainActor.run {
                loadFailed = true
                loaded = true
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LOG")
                .font(.dripEyebrow(11))
                .tracking(1.5)
                .foregroundStyle(Color.drip.textTertiary)
            HStack(alignment: .firstTextBaseline) {
                Text("All runs")
                    .font(.dripDisplay(28))
                    .foregroundStyle(Color.drip.textPrimary)
                Spacer()
                Button {
                    showVoiceSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 11))
                        Text("Log a run")
                            .font(.dripLabel(13))
                    }
                    .foregroundStyle(Color.drip.coral)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.drip.coral.opacity(0.12))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Text("\(rows.count) runs · last 180 days")
                .font(.dripCaption(11))
                .foregroundStyle(Color.drip.textTertiary)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No runs logged yet.")
                .font(.dripBody(15))
                .foregroundStyle(Color.drip.textSecondary)
            Text("Tap Log a run to record one — voice notes, HealthKit imports, and direct entries all land here.")
                .font(.dripBody(14))
                .foregroundStyle(Color.drip.textTertiary)
        }
        .padding(.top, 24)
    }

    // MARK: - Week grouping

    /// Monday 00:00 of the week containing `d` (weeks are Monday-start, matching
    /// the dashboard / Trends convention).
    private func weekStartMonday(_ d: Date) -> Date {
        let startOfDay = cal.startOfDay(for: d)
        let weekday = cal.component(.weekday, from: startOfDay) // 1=Sun … 7=Sat
        let daysFromMonday = (weekday + 5) % 7                  // Mon=0 … Sun=6
        return cal.date(byAdding: .day, value: -daysFromMonday, to: startOfDay) ?? startOfDay
    }

    /// Rows grouped into Monday-start weeks, newest first, each with a label
    /// (This week / Last week / Week of Jun 30) + mileage subtotal + run count.
    /// A check-in carries no distance, so it's an entry but not a run.
    private var weekGroups: [LogWeek] {
        let thisWeek = weekStartMonday(Date())
        let grouped = Dictionary(grouping: rows) { weekStartMonday($0.date) }
        return grouped.keys.sorted(by: >).map { ws in
            let weekRows = grouped[ws] ?? []
            let weeksAgo = Int((thisWeek.timeIntervalSince(ws) / (7 * 86400)).rounded())
            let label: String
            switch weeksAgo {
            case 0: label = "This week"
            case 1: label = "Last week"
            default: label = "Week of \(ws.formatted(.dateTime.month(.abbreviated).day()))"
            }
            let miles = weekRows.reduce(0) { $0 + ($1.miles ?? 0) }
            let runs = weekRows.filter { $0.source != "check_in" }.count
            return LogWeek(id: ISO8601DateFormatter().string(from: ws),
                           label: label, miles: miles, runs: runs, rows: weekRows)
        }
    }

    private func weekHeader(_ week: LogWeek) -> some View {
        HStack(spacing: 12) {
            Rectangle().fill(Color.drip.divider).frame(width: 16, height: 1)
            Text(headerText(week))
                .font(.dripEyebrow(10)).tracking(1.4)
                .foregroundStyle(Color.drip.textSecondary)
                .fixedSize()
            Rectangle().fill(Color.drip.divider).frame(height: 1)
        }
        .padding(.vertical, 10)
        // Opaque so rows scroll cleanly under the pinned header.
        .background(Color.drip.background)
    }

    private func headerText(_ week: LogWeek) -> String {
        var s = "\(week.label.uppercased()) · \(Int(week.miles.rounded())) MI"
        if week.runs > 0 { s += " · \(week.runs) \(week.runs == 1 ? "RUN" : "RUNS")" }
        return s
    }
}

private struct LogWeek: Identifiable {
    let id: String
    let label: String
    let miles: Double
    let runs: Int
    let rows: [TodayLogRow]
}

// MARK: - Single row

private struct LogRowView: View {
    let row: TodayLogRow

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Date rail
            VStack(spacing: 2) {
                Text("\(Calendar.current.component(.day, from: row.date))")
                    .font(.dripDisplay(22))
                    .foregroundStyle(Color.drip.textPrimary)
                    .monospacedDigit()
                Text(row.date.formatted(.dateTime.month(.abbreviated).weekday(.abbreviated)).uppercased())
                    .font(.dripEyebrow(9))
                    .tracking(1.0)
                    .foregroundStyle(Color.drip.textTertiary)
            }
            .frame(width: 56, alignment: .trailing)

            // Body
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(typeLabel)
                        .font(.dripDisplay(17))
                        .foregroundStyle(Color.drip.textPrimary)
                    if let miles = row.miles {
                        Text(String(format: "%.1f mi", miles))
                            .font(.dripStat(15))
                            .foregroundStyle(Color.drip.coral)
                            .monospacedDigit()
                    }
                    if let pace = row.pace {
                        Text("\(pace)/mi")
                            .font(.dripCaption(12))
                            .foregroundStyle(Color.drip.textSecondary)
                            .monospacedDigit()
                    }
                    if let mood = row.mood {
                        MoodLabel(mood: mood)
                    }
                    Spacer(minLength: 0)
                }
                if let insight = trimmedInsight {
                    Text(insight)
                        .font(.dripCaption(12))
                        .foregroundStyle(Color.drip.textSecondary)
                        .lineSpacing(2)
                        .padding(.leading, 8)
                        .overlay(alignment: .leading) {
                            Rectangle()
                                .fill(Color.drip.coral.opacity(0.4))
                                .frame(width: 2)
                        }
                }
            }
        }
    }

    private var typeLabel: String {
        WorkoutLabel.display(row.typeKey)
    }

    private var trimmedInsight: String? {
        guard let raw = row.coachInsight?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        for terminator in [". ", "? ", "! "] {
            if let r = raw.range(of: terminator) {
                return String(raw[..<r.upperBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return raw
    }
}
