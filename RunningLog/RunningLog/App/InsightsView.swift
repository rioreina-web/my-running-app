//
//  InsightsView.swift
//  RunningLog
//
//  The Insights tab — consolidated analytics. Replaces the old
//  Training dashboard tab + scattered sidebar destinations
//  (Analysis, Pace Chart, Fitness Predictor) with one surface that
//  answers: "where am I trending, and why?"
//
//  This is the "analytics" job from the four-job mission. Editorial
//  style mirrors Today and Log so the three-tab app reads as one
//  product, not three.
//
//  Today's content is a curated set of sections. Each is currently
//  a stub or links into existing deeper views; subsequent passes
//  port the SwiftUI Charts visuals from the web `/analysis` page.
//

import SwiftUI

struct InsightsView: View {
    @State private var rows: [TodayLogRow] = []
    @State private var loaded = false

    private let cal = Calendar.current

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                EditorialRule()
                volumeSection
                EditorialRule()
                pacesSection
                EditorialRule()
                moodSection
                EditorialRule()
                deepLinks
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .background(Color.drip.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let fetched = await TodayLogRow.fetchRecent(days: 90)
            await MainActor.run {
                rows = fetched
                loaded = true
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("INSIGHTS")
                .font(.dripCaption(11))
                .tracking(1.5)
                .foregroundStyle(Color.drip.textTertiary)
            Text("Where you're trending.")
                .font(.dripDisplay(28))
                .foregroundStyle(Color.drip.textPrimary)
        }
    }

    // MARK: - Volume

    private var volumeSection: some View {
        let buckets = computeWeeklyBuckets()
        let total90 = rows.compactMap(\.miles).reduce(0, +)
        let runs90 = rows.filter { ($0.miles ?? 0) > 0 }.count
        let nonZero = buckets.filter { $0.miles > 0 }.map(\.miles)
        let peak = nonZero.max() ?? 0
        let avg = nonZero.isEmpty ? 0 : nonZero.reduce(0, +) / Double(nonZero.count)

        return VStack(alignment: .leading, spacing: 12) {
            label("VOLUME · 12 WEEKS")

            HStack(alignment: .firstTextBaseline, spacing: 20) {
                stat(
                    value: String(format: "%.0f", total90),
                    suffix: "mi",
                    sub: "90-day total · \(runs90) runs",
                    accent: true
                )
                stat(
                    value: String(format: "%.0f", avg),
                    suffix: "mi",
                    sub: "weekly average",
                    accent: false
                )
                stat(
                    value: String(format: "%.0f", peak),
                    suffix: "mi",
                    sub: "peak week",
                    accent: false
                )
                Spacer(minLength: 0)
            }

            volumeChart(buckets)
        }
    }

    private func volumeChart(_ buckets: [WeekBucket]) -> some View {
        let max = Swift.max(1.0, buckets.map(\.miles).max() ?? 1.0)
        return HStack(alignment: .bottom, spacing: 4) {
            ForEach(buckets, id: \.weekStart) { bucket in
                Rectangle()
                    .fill(bucket.isCurrent ? Color.drip.coral : Color.drip.coral.opacity(0.3))
                    .frame(height: bucket.miles == 0 ? 4 : Swift.max(8, CGFloat((bucket.miles / max) * 96)))
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
            }
        }
        .frame(height: 96)
    }

    // MARK: - Paces

    private var pacesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("PACES · 30 DAYS")
            paceRow(zone: "Easy",      keys: ["easy"],                     color: Color.drip.positive)
            paceRow(zone: "Long run",  keys: ["long_run"],                 color: Color.drip.positive)
            paceRow(zone: "Tempo",     keys: ["tempo", "progression"],     color: Color.drip.coral)
            paceRow(zone: "Threshold", keys: ["threshold", "intervals"],   color: Color.drip.injured)
        }
    }

    private func paceRow(zone: String, keys: [String], color: Color) -> some View {
        let pace = avgPace(keys: keys, days: 30)
        return HStack {
            Text(zone)
                .font(.dripBody(14))
                .foregroundStyle(color)
            Spacer()
            if let pace {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(pace)
                        .font(.dripDisplay(16))
                        .foregroundStyle(Color.drip.textPrimary)
                        .monospacedDigit()
                    Text("/mi")
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.textTertiary)
                }
            } else {
                Text("—")
                    .font(.dripBody(14))
                    .foregroundStyle(Color.drip.textTertiary)
            }
        }
        .padding(.vertical, 4)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.drip.divider.opacity(0.6))
                .frame(height: 0.5)
        }
    }

    // MARK: - Mood

    private var moodSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            label("MOOD · LAST 30 DAYS")
            let counts = moodCounts()
            if counts.isEmpty {
                Text("Tag your runs to see the pattern emerge.")
                    .font(.dripBody(14))
                    .foregroundStyle(Color.drip.textSecondary)
            } else {
                HStack(spacing: 10) {
                    ForEach(counts, id: \.mood) { item in
                        HStack(spacing: 4) {
                            MoodLabel(mood: item.mood)
                            Text("×\(item.count)")
                                .font(.dripCaption(11))
                                .foregroundStyle(Color.drip.textTertiary)
                                .monospacedDigit()
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: - Deep links

    /// Quiet links into the existing deeper analytics surfaces. Keeps
    /// power-user destinations reachable without putting them in the
    /// tab bar. Each link drops them into the existing screen — those
    /// screens get incrementally folded in here over time.
    private var deepLinks: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("DEEPER")
            NavigationLink {
                AnalysisView()
            } label: {
                deepRow(title: "Full analysis", sub: "All charts, weekly AI report")
            }
            .buttonStyle(.plain)
            NavigationLink {
                PaceChartView()
            } label: {
                deepRow(title: "Pace chart", sub: "Heat-adjusted zones")
            }
            .buttonStyle(.plain)
            NavigationLink {
                FitnessPredictorView(trainingViewModel: TrainingPlanViewModel())
            } label: {
                deepRow(title: "Race predictions", sub: "What your training projects to")
            }
            .buttonStyle(.plain)
        }
    }

    private func deepRow(title: String, sub: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.dripBody(15))
                    .foregroundStyle(Color.drip.textPrimary)
                Text(sub)
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textTertiary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.drip.textTertiary)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Reusable bits

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.dripCaption(11))
            .tracking(1.5)
            .foregroundStyle(Color.drip.textTertiary)
    }

    private func stat(value: String, suffix: String, sub: String, accent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.dripDisplay(22))
                    .foregroundStyle(accent ? Color.drip.coral : Color.drip.textPrimary)
                    .monospacedDigit()
                Text(suffix)
                    .font(.dripBody(13))
                    .foregroundStyle(Color.drip.textSecondary)
            }
            Text(sub)
                .font(.dripCaption(11))
                .foregroundStyle(Color.drip.textTertiary)
        }
    }

    // MARK: - Computations (mirrors the home's helpers)

    private struct WeekBucket {
        let weekStart: Date
        let miles: Double
        let isCurrent: Bool
    }

    private func computeWeeklyBuckets() -> [WeekBucket] {
        let today = Date()
        let weekday = cal.component(.weekday, from: today)
        let daysBackToMonday = (weekday + 5) % 7
        guard let thisMonday = cal.date(byAdding: .day, value: -daysBackToMonday, to: today) else {
            return []
        }
        let thisMondayStart = cal.startOfDay(for: thisMonday)
        var buckets: [WeekBucket] = []
        for i in (0..<12).reversed() {
            guard let weekStart = cal.date(byAdding: .day, value: -i * 7, to: thisMondayStart),
                  let weekEnd = cal.date(byAdding: .day, value: 7, to: weekStart)
            else { continue }
            let weekMiles = rows
                .filter { $0.date >= weekStart && $0.date < weekEnd }
                .compactMap { $0.miles }
                .reduce(0, +)
            buckets.append(WeekBucket(
                weekStart: weekStart,
                miles: weekMiles,
                isCurrent: i == 0
            ))
        }
        return buckets
    }

    private func avgPace(keys: [String], days: Int) -> String? {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
        let lower = Set(keys.map { $0.lowercased() })
        let values: [Double] = rows
            .filter { $0.date >= cutoff }
            .filter { lower.contains(($0.typeKey ?? "").lowercased()) }
            .compactMap { $0.pace.flatMap(InsightsView.paceToSeconds) }
        guard !values.isEmpty else { return nil }
        let avg = values.reduce(0, +) / Double(values.count)
        return InsightsView.formatPace(avg)
    }

    nonisolated private static func paceToSeconds(_ s: String) -> Double? {
        let parts = s.split(separator: ":").compactMap { Double($0) }
        guard parts.count == 2 else { return nil }
        return parts[0] * 60 + parts[1]
    }

    private static func formatPace(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func moodCounts() -> [(mood: String, count: Int)] {
        let cutoff = Date().addingTimeInterval(-30 * 86400)
        var counts: [String: Int] = [:]
        for r in rows where r.date >= cutoff {
            guard let m = r.mood?.lowercased(), !m.isEmpty else { continue }
            counts[m, default: 0] += 1
        }
        return counts
            .map { (mood: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }
}

// MARK: - Editorial rule
//
// Now lives in DesignSystem.swift as a shared primitive. The "local copy"
// comment that used to be here was a workaround for the old private
// duplicates; no longer needed.
