//
//  ModelOfYouView.swift
//  RunningLog
//
//  WS6 — the redesigned Coach surface: a legible, evidence-backed model of
//  the runner. Opens to the cards; each card is a "trapdoor" that expands to
//  its evidence (design: outputs/model-of-you-mock.html). Post Run Drip.
//
//  To screenshot without running the whole app: open this file in Xcode and
//  use the canvas — the #Preview at the bottom injects sample data.
//

import SwiftUI

struct ModelOfYouView: View {
    @Environment(\.coachAsk) private var coachAsk
    @State private var state: ModelOfYouState?
    @State private var loaded = false

    /// Injected for previews; when nil the view fetches live athlete_state.
    private let injected: ModelOfYouState?
    init(state: ModelOfYouState? = nil) { self.injected = state }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if let s = state {
                    loadCard(s)
                    fitnessCard(s)
                    WorkoutsAndRepsSection()   // tappable → per-workout rep chart
                    watchingCard(s)
                    MemoriesCard()             // long-term memory: view + forget
                    cantSeeCard(s)
                } else if loaded {
                    Text("No read yet — log a few runs and check back.")
                        .font(.dripBody(15))
                        .foregroundStyle(Color.drip.textSecondary)
                        .padding(.top, 40)
                } else {
                    ProgressView().padding(.top, 60)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .background(Color.drip.background.ignoresSafeArea())
        .task {
            if let injected { state = injected; loaded = true; return }
            state = await ModelOfYouState.fetch()
            loaded = true
        }
        // Composer presented when another surface (e.g. the Trends ask
        // bar) stages a question via CoachAskContext.
        .sheet(isPresented: askBinding) {
            CoachAskSheet(
                question: coachAsk.pendingQuestion ?? "",
                focus: coachAsk.focusLabel
            )
        }
    }

    /// True while a coach question is staged; clearing it dismisses + resets.
    private var askBinding: Binding<Bool> {
        Binding(
            get: { coachAsk.pendingQuestion != nil },
            set: { presented in if !presented { coachAsk.clear() } }
        )
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("THE READ · \(Self.todayString())")
                .font(.dripStat(10)).tracking(1.4)
                .foregroundStyle(Color.drip.coral)
            Text("Where things stand")
                .font(.dripDisplay(30))
                .foregroundStyle(Color.drip.textPrimary)
            if let line = subhead {
                Text(line)
                    .font(.dripBody(13))
                    .foregroundStyle(Color.drip.textSecondary)
            }
        }
        .padding(.bottom, 2)
    }

    private static func todayString() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE · MMM d"
        return f.string(from: Date()).uppercased()
    }

    private var subhead: String? {
        guard let s = state else { return nil }
        var parts: [String] = []
        if let lvl = s.experience_level { parts.append(lvl.capitalized) }
        if let ph = s.current_phase { parts.append("\(ph) phase") }
        if let t = s.fitness_trend { parts.append("fitness \(t)") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - Cards

    @ViewBuilder
    private func fitnessCard(_ s: ModelOfYouState) -> some View {
        let fp = s.fitness_prediction
        let tenK = fp?.ranges?["10K"]?.formattedRange
        MOYCard(
            label: "Fitness · race-anchored",
            value: tenK.map { "~\($0)" } ?? "—",
            valueSuffix: tenK != nil ? "10K" : nil,
            tag: fp?.confidence_tier.map { "\($0) conf" },
            tagColor: .drip.success,
            observation: fitnessObs(s)
        ) {
            evidenceRows([
                ("5K", fp?.ranges?["5K"]?.formattedRange),
                ("10K", tenK),
                ("Half", fp?.ranges?["half"]?.formattedRange),
                ("Marathon", fp?.ranges?["marathon"]?.formattedRange),
            ])
            if let n = fp?.workout_count {
                evidenceNote("\(n) sessions behind the estimate\(s.fitness_trend.map { " · trend \($0)" } ?? "")")
            }
        }
    }

    private func fitnessObs(_ s: ModelOfYouState) -> String {
        if let t = s.fitness_trend { return "Fitness is \(t), anchored to your real race history." }
        return "Anchored to your real race history."
    }

    @ViewBuilder
    private func loadCard(_ s: ModelOfYouState) -> some View {
        let ld = s.load_distribution
        let mpw = s.weekly_avg_miles.map { String(format: "%.0f", $0) } ?? "—"
        MOYCard(
            label: "Load & balance · volume × intensity",
            value: mpw,
            valueSuffix: "mpw avg",
            tag: ld?.load_trend?.replacingOccurrences(of: "_", with: " "),
            tagColor: trendColor(ld?.load_trend),
            observation: loadObs(ld)
        ) {
            if let z = ld?.zone_pct_7d {
                evidenceNote("Time in zone (7d): easy \(pct(z.easy)) · moderate \(pct(z.moderate)) · threshold \(pct(z.threshold)) · hard \(pct(z.hard))")
            }
            if let v = ld?.volume_x_intensity_28d {
                evidenceNote("Volume × intensity (28d): \(Int(v)) weighted-min — a hard mile ≈ 5× an easy mile")
            }
            if let m = ld?.monotony_7d {
                evidenceNote("Monotony \(String(format: "%.2f", m))" + (ld?.strain_7d.map { " · strain \(Int($0))" } ?? ""))
            }
            if let r = ld?.recovery_read, let n = r.hard_sessions_28d {
                let spacing = r.avg_days_between_hard.map { ", ~\(Int($0.rounded())) days apart" } ?? ""
                let dw = (r.down_week == true) ? " · down week" : ""
                evidenceNote("\(n) hard session\(n == 1 ? "" : "s") in 28d\(spacing)\(dw)")
            }
        }
    }

    private func loadObs(_ ld: ModelOfYouState.LoadDistribution?) -> String {
        if let pctv = ld?.load_vs_chronic_pct {
            let dir = pctv >= 0 ? "+" : ""
            return "Load is \(dir)\(Int(pctv))% vs your 8-week norm."
        }
        return "Your intensity-weighted load, read against your own baseline."
    }

    @ViewBuilder
    private func workoutsCard(_ s: ModelOfYouState) -> some View {
        let sessions = (s.execution ?? []).prefix(6)
        MOYCard(
            label: "Workouts & reps · read split-by-split",
            value: "\(s.execution?.count ?? 0)",
            valueSuffix: "recent sessions",
            tag: sessions.isEmpty ? nil : "now seen",
            tagColor: .drip.success,
            observation: sessions.isEmpty
                ? "No structured sessions detected recently."
                : "Detected from your laps — intervals, threshold, tempo, not just averages."
        ) {
            ForEach(Array(sessions.enumerated()), id: \.offset) { _, e in
                HStack(alignment: .top, spacing: 8) {
                    Text(shortDate(e.date))
                        .font(.dripStat(11))
                        .foregroundStyle(Color.drip.textTertiary)
                        .frame(width: 52, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text((e.type ?? "workout").capitalized + (e.structure.map { " · \($0)" } ?? ""))
                            .font(.dripBody(13))
                            .foregroundStyle(Color.drip.textPrimary)
                        if let paces = e.rep_paces, !paces.isEmpty {
                            Text(paces.prefix(10).joined(separator: " · "))
                                .font(.dripStat(10))
                                .foregroundStyle(Color.drip.textSecondary)
                        }
                    }
                }
                .padding(.vertical, 3)
            }
        }
    }

    @ViewBuilder
    private func watchingCard(_ s: ModelOfYouState) -> some View {
        let niggles = s.niggle_recurrence ?? []
        let active = s.active_injuries ?? []
        let possible = s.possible_injuries ?? []
        let count = max(active.count, niggles.count) + (possible.isEmpty ? 0 : 0)
        MOYCard(
            label: "Watching · wear & tear",
            value: count > 0 ? "\(active.count + niggles.count) flagged" : "Clear",
            valueSuffix: nil,
            tag: "surface, don't diagnose",
            tagColor: .drip.tired,
            observation: (active.isEmpty && niggles.isEmpty && possible.isEmpty)
                ? "Nothing stacking right now."
                : "Body-part mentions surfaced in your own words — never diagnosed."
        ) {
            ForEach(Array(active.enumerated()), id: \.offset) { _, i in
                evidenceNote("\(cap(i.body_area)) — active" + (i.severity.map { " (severity \($0))" } ?? ""))
            }
            ForEach(Array(niggles.enumerated()), id: \.offset) { _, n in
                evidenceNote("\(cap(n.body_area)) — \(n.occurrences ?? 0)× (\(shortDate(n.first_seen)) → \(shortDate(n.last_seen)))")
            }
            ForEach(Array(possible.prefix(3).enumerated()), id: \.offset) { _, p in
                if let ex = p.excerpt { evidenceNote("\(cap(p.body_area)): “\(ex)”") }
            }
        }
    }

    @ViewBuilder
    private func cantSeeCard(_ s: ModelOfYouState) -> some View {
        let gaps = s.data_gaps ?? []
        MOYCard(
            label: "What I can't see",
            value: gaps.isEmpty ? "All caught up" : "\(gaps.count) gaps",
            valueSuffix: nil,
            tag: nil,
            tagColor: .drip.textTertiary,
            observation: "I'd rather tell you what I'm missing than pretend I know."
        ) {
            ForEach(Array(gaps.enumerated()), id: \.offset) { _, g in
                evidenceNote("\(g.gap ?? "Gap") — \(g.detail ?? "")")
            }
        }
    }

    // MARK: - Small helpers

    @ViewBuilder
    private func evidenceRows(_ rows: [(String, String?)]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                if let v = row.1 {
                    HStack {
                        Text(row.0)
                            .font(.dripStat(11))
                            .foregroundStyle(Color.drip.textTertiary)
                        Spacer()
                        Text(v)
                            .font(.dripBody(13))
                            .foregroundStyle(Color.drip.textPrimary)
                    }
                }
            }
        }
    }

    private func evidenceNote(_ s: String) -> some View {
        Text(s)
            .font(.dripStat(11))
            .foregroundStyle(Color.drip.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pct(_ d: Double?) -> String { d.map { "\(Int($0))%" } ?? "0%" }
    private func cap(_ s: String?) -> String { (s ?? "—").capitalized }
    private func trendColor(_ t: String?) -> Color {
        switch t {
        case "spiking": return .drip.injured
        case "backing_off": return .drip.tired
        case "building": return .drip.success
        default: return .drip.coral
        }
    }
    private func shortDate(_ s: String?) -> String {
        guard let s, s.count >= 10 else { return s ?? "" }
        return String(s.prefix(10).suffix(5)) // MM-DD
    }
}

// MARK: - Trapdoor card

private struct MOYCard<Content: View>: View {
    let label: String
    let value: String
    var valueSuffix: String? = nil
    var tag: String? = nil
    var tagColor: Color = .drip.coral
    let observation: String
    @ViewBuilder var evidence: () -> Content

    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.22)) { expanded.toggle() }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(label.uppercased())
                            .font(.dripStat(9)).tracking(1.1)
                            .foregroundStyle(Color.drip.textSecondary)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(value)
                                .font(.dripDisplay(21))
                                .foregroundStyle(Color.drip.textPrimary)
                            if let suffix = valueSuffix {
                                Text(suffix)
                                    .font(.dripBody(12))
                                    .foregroundStyle(Color.drip.textSecondary)
                            }
                            if let tag {
                                Text(tag.uppercased())
                                    .font(.dripStat(8)).tracking(0.6)
                                    .foregroundStyle(tagColor)
                                    .padding(.horizontal, 7).padding(.vertical, 3)
                                    .background(tagColor.opacity(0.14))
                                    .clipShape(Capsule())
                            }
                        }
                        Text(observation)
                            .font(.dripBody(13))
                            .foregroundStyle(Color.drip.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.drip.textTertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .padding(.top, 2)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 6) {
                    evidence()
                }
                .padding(.top, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.drip.divider, lineWidth: 1)
        )
    }
}

// MARK: - Preview (sample data — renders in Xcode canvas, no app run needed)

#Preview {
    let sample = ModelOfYouState(
        experience_level: "advanced",
        current_phase: "base",
        fitness_trend: "improving",
        last_mood: "tired",
        last_readiness_score: 4,
        rolling_7d_miles: 39.3,
        rolling_28d_miles: 203.1,
        weekly_avg_miles: 50.8,
        load_distribution: .init(
            volume_x_intensity_7d: 497, volume_x_intensity_28d: 2002,
            zone_pct_7d: .init(easy: 82, moderate: 10, threshold: 5, hard: 3),
            monotony_7d: 0.92, strain_7d: 67, effort_distribution: "mixed",
            load_trend: "backing_off", load_vs_chronic_pct: -17,
            recovery_read: .init(down_week: false, hard_sessions_28d: 3, avg_days_between_hard: 10)
        ),
        fitness_prediction: .init(
            ranges: [
                "5K": .init(low: 928, high: 946, point: 937),
                "10K": .init(low: 1930, high: 1968, point: 1949),
                "half": .init(low: 4255, high: 4335, point: 4295),
                "marathon": .init(low: 8905, high: 9085, point: 8995),
            ],
            confidence_tier: "High", workout_count: 58
        ),
        execution: [
            .init(date: "2026-05-20", type: "intervals", structure: "9×1K @ 5:08 (5K)",
                  shape: "even", rep_count: 9,
                  rep_paces: ["5:07","5:09","5:06","5:07","5:09","5:07","5:09","5:07","5:06"],
                  fade_pct: -0.5, hr_drift_pct: 4.3),
            .init(date: "2026-05-15", type: "threshold", structure: "4×1K @ 5:32",
                  shape: "even", rep_count: 4, rep_paces: ["5:34","5:32","5:31","5:32"],
                  fade_pct: -0.4, hr_drift_pct: 3.1),
            .init(date: "2026-05-05", type: "threshold", structure: "5×1mi @ 5:17 (cruise)",
                  shape: "even", rep_count: 5, rep_paces: ["5:19","5:17","5:18","5:16","5:17"],
                  fade_pct: -0.3, hr_drift_pct: 5.0),
        ],
        patterns: [.init(statement: "Strong pacing control — negative-splitting your quality work.",
                         confidence: "medium", evidence: "3 of 4 sessions got faster")],
        niggle_recurrence: [.init(body_area: "knee", occurrences: 2,
                                  first_seen: "2026-05-08", last_seen: "2026-05-24",
                                  worst_severity: "tight")],
        active_injuries: [.init(body_area: "achilles", status: "active", severity: 3)],
        possible_injuries: [.init(date: "2026-05-24", body_area: "knee",
                                  severity_hint: "tight",
                                  excerpt: "noticed some light tightness in my left knee")],
        data_gaps: [
            .init(gap: "NO RECENT MOOD", detail: "Haven't heard how you're feeling in over a week."),
            .init(gap: "ONE DATA POINT", detail: "knee has come up once — not enough to call a pattern."),
        ]
    )
    return ModelOfYouView(state: sample)
}
