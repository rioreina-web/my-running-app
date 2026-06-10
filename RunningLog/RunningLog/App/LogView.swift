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
                } else if rows.isEmpty {
                    emptyState
                } else {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(rows, id: \.id) { row in
                            LogRowView(row: row)
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
        .task {
            let fetched = await TodayLogRow.fetchRecent(days: 180)
            await MainActor.run {
                rows = fetched
                loaded = true
            }
        }
        .sheet(isPresented: $showVoiceSheet) {
            NavigationStack { VoiceLogView() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LOG")
                .font(.dripCaption(11))
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
                    .font(.dripCaption(9))
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
        switch (row.typeKey ?? "").lowercased() {
        case "easy": return "Easy run"
        case "recovery": return "Recovery"
        case "tempo": return "Tempo"
        case "intervals": return "Intervals"
        case "long_run": return "Long run"
        case "race": return "Race"
        case "progression": return "Progression"
        case "strides": return "Strides"
        default: return "Run"
        }
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
