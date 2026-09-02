//
//  StressRecoveryView.swift
//  RunningLog
//
//  Step 2 of the stress/recovery-scores work (drip-scores): the 90-day
//  graph screen, pushed from the Train tab's CURRENT mode.
//
//  Reads `daily_scores` directly (RLS: athlete reads own rows). The table
//  keys on (user_id, score_date, score_version) and old score versions are
//  never recomputed in place, so a day can carry several rows — this
//  screen keeps only the LATEST version present in the window, matching
//  the coaching-daily-read consumer.
//
//  Design notes:
//  - The reference mockup asked for a rust stress line and a green
//    recovery line. Both collide with the three-palette rule (warm = mood,
//    green = mood, coral = alert), so the chart is monochrome editorial:
//    ink for stress, dashed secondary for recovery, neutral sRPE bars
//    behind, coral reserved for the selected-day marker only.
//  - Recovery is null on days with no recovery inputs; the line breaks
//    into a real gap there — never interpolated, never drawn as 0
//    (TrendsMoodRead convention).
//  - Scrubbing READS; it never navigates (TrendsSignalLanes rule). The
//    component breakdown renders inline below the chart.
//  - Deliberately absent: ACWR and anything phrased as injury risk or
//    readiness. The components carry their own reason sentences instead.
//

import Combine
import PostgREST
import Supabase
import SwiftUI

// MARK: - Models

struct ScoreComponent: Decodable, Identifiable, Equatable {
    let name: String
    let points: Int
    let detail: String
    var id: String { name }
}

/// One scored day, already collapsed to the latest score_version.
struct DailyScoreDay: Identifiable, Equatable {
    let dateString: String        // "2026-09-01" (score_date, a DATE column)
    let date: Date
    let stress: Int?
    let recovery: Int?
    let recoveryConfidence: String
    let srpe: Double
    let stressComponents: [ScoreComponent]
    let recoveryComponents: [ScoreComponent]
    var id: String { dateString }
}

// MARK: - Service

enum StressRecoveryService {
    /// Raw row. `score_date` is a DATE column — decoded as String and parsed
    /// by hand, never through the SDK's `.value` date path (see
    /// feedback_supabase_swift_date_decoder / DailyReadService).
    private struct Row: Decodable {
        let score_date: String
        let score_version: String
        let stress: Int?
        let recovery: Int?
        let recovery_confidence: String?
        let srpe: Double?
        let stress_components: [ScoreComponent]?
        let recovery_components: [ScoreComponent]?
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func fetchWindow(days: Int = 90) async throws -> [DailyScoreDay] {
        guard let userId = AuthManager.shared.currentUserId else { return [] }
        let start = Calendar.current.date(byAdding: .day, value: -(days - 1), to: Date()) ?? Date()
        let startString = dayFormatter.string(from: start)

        let response = try await supabase
            .from("daily_scores")
            .select("score_date, score_version, stress, recovery, recovery_confidence, srpe, stress_components, recovery_components")
            .eq("user_id", value: userId)
            .gte("score_date", value: startString)
            .order("score_date", ascending: true)
            .limit(Int(days) * 4)
            .execute()
        let rows = try JSONDecoder().decode([Row].self, from: response.data)

        // Latest score_version wins ('1.2' > '1.1' lexically, by design).
        guard let latest = rows.map({ $0.score_version }).max() else { return [] }
        return rows
            .filter { $0.score_version == latest }
            .compactMap { row in
                guard let d = dayFormatter.date(from: row.score_date) else { return nil }
                return DailyScoreDay(
                    dateString: row.score_date,
                    date: d,
                    stress: row.stress,
                    recovery: row.recovery,
                    recoveryConfidence: row.recovery_confidence ?? "none",
                    srpe: row.srpe ?? 0,
                    stressComponents: row.stress_components ?? [],
                    recoveryComponents: row.recovery_components ?? []
                )
            }
    }
}

// MARK: - View model

@MainActor
final class StressRecoveryViewModel: ObservableObject {
    enum Phase: Equatable { case loading, loaded, empty, error(String) }

    @Published var phase: Phase = .loading
    @Published var days: [DailyScoreDay] = []
    @Published var selectedIndex: Int? = nil

    var selected: DailyScoreDay? {
        guard let i = selectedIndex, days.indices.contains(i) else { return nil }
        return days[i]
    }

    func load() async {
        phase = .loading
        do {
            let fetched = try await StressRecoveryService.fetchWindow()
            days = fetched
            selectedIndex = fetched.indices.last
            phase = fetched.isEmpty ? .empty : .loaded
        } catch {
            phase = .error(error.localizedDescription)
        }
    }
}

// MARK: - Screen

struct StressRecoveryView: View {
    @StateObject private var vm = StressRecoveryViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                switch vm.phase {
                case .loading:
                    loading
                case .empty:
                    EmptyStateView(
                        variant: .dataPending,
                        eyebrow: "No scores yet",
                        title: "Scores build from your logged runs — they'll appear after the next nightly pass.",
                        icon: nil,
                        cta: nil
                    )
                    .padding(.top, 32)
                case .error(let message):
                    EmptyStateView(
                        variant: .error,
                        eyebrow: "Couldn't load",
                        title: message,
                        icon: nil,
                        cta: .init(label: "Retry") { Task { await vm.load() } }
                    )
                    .padding(.top, 32)
                case .loaded:
                    legend.padding(.top, 18)
                    StressRecoveryChart(days: vm.days, selectedIndex: $vm.selectedIndex)
                        .frame(height: 220)
                        .padding(.top, 10)
                    if let day = vm.selected {
                        dayDetail(day).padding(.top, 18)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .background(Color.drip.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LAST 90 DAYS")
                .font(.dripEyebrow(10.5)).tracking(1.3)
                .foregroundStyle(Color.drip.textTertiary)
            Text("Stress & recovery")
                .font(.dripDisplay(28))
                .foregroundStyle(Color.drip.textPrimary)
            Text("What the training is costing, and how the body is answering. Every number carries its reasons — tap a day to read them.")
                .font(.dripCaption(13))
                .foregroundStyle(Color.drip.textSecondary)
                .padding(.top, 2)
        }
        .padding(.top, 8)
    }

    private var loading: some View {
        VStack(spacing: 10) {
            ProgressView().tint(Color.drip.coral)
            Text("READING SCORES")
                .font(.dripEyebrow(10)).tracking(1.4)
                .foregroundStyle(Color.drip.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 64)
    }

    private var legend: some View {
        HStack(spacing: 16) {
            legendItem(label: "STRESS") {
                Rectangle().fill(Color.drip.textPrimary).frame(width: 16, height: 2)
            }
            legendItem(label: "RECOVERY") {
                DashSwatch().stroke(Color.drip.textSecondary, style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
                    .frame(width: 16, height: 2)
            }
            legendItem(label: "SESSION LOAD") {
                RoundedRectangle(cornerRadius: 1).fill(Color.drip.paperDeep).frame(width: 16, height: 8)
            }
            Spacer()
        }
    }

    private func legendItem(label: String, @ViewBuilder swatch: () -> some View) -> some View {
        HStack(spacing: 6) {
            swatch()
            Text(label)
                .font(.dripEyebrow(9)).tracking(1.1)
                .foregroundStyle(Color.drip.textTertiary)
        }
    }

    // MARK: Day detail

    private func dayDetail(_ day: DailyScoreDay) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(day.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()).uppercased())
                    .font(.dripEyebrow(10)).tracking(1.2)
                    .foregroundStyle(Color.drip.textTertiary)
                Spacer()
            }
            HStack(alignment: .firstTextBaseline, spacing: 18) {
                scoreStat(label: "STRESS", value: day.stress.map(String.init) ?? "—")
                scoreStat(label: "RECOVERY", value: day.recovery.map(String.init) ?? "—")
                if day.recovery != nil {
                    Text(confidenceLine(day.recoveryConfidence))
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.textTertiary)
                        .padding(.bottom, 3)
                }
                Spacer()
            }
            .padding(.top, 8)

            componentSection(title: "STRESS CONTRIBUTORS", components: day.stressComponents, signed: false)
                .padding(.top, 18)
            componentSection(title: "RECOVERY SIGNALS", components: day.recoveryComponents, signed: true)
                .padding(.top, 16)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.drip.cardBackgroundElevated)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.drip.divider, lineWidth: 1))
        )
    }

    private func scoreStat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.dripEyebrow(9)).tracking(1.1)
                .foregroundStyle(Color.drip.textTertiary)
            Text(value)
                .font(.dripStat(24))
                .foregroundStyle(Color.drip.textPrimary)
        }
    }

    private func confidenceLine(_ confidence: String) -> String {
        switch confidence {
        case "low": return "low confidence — one signal"
        case "ok": return "two or more signals"
        default: return ""
        }
    }

    private func componentSection(title: String, components: [ScoreComponent], signed: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.dripEyebrow(9.5)).tracking(1.2)
                .foregroundStyle(Color.drip.textTertiary)
                .padding(.bottom, 6)
            if components.isEmpty {
                Text("Nothing recorded for this day.")
                    .font(.dripCaption(12))
                    .foregroundStyle(Color.drip.textTertiary)
            } else {
                ForEach(components) { c in
                    componentRow(c, signed: signed)
                    if c.id != components.last?.id {
                        Divider().overlay(Color.drip.divider)
                    }
                }
            }
        }
    }

    private func componentRow(_ c: ScoreComponent, signed: Bool) -> some View {
        let active = c.points != 0
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(c.name.replacingOccurrences(of: "_", with: " ").uppercased())
                .font(.dripEyebrow(9)).tracking(1.0)
                .foregroundStyle(active ? Color.drip.textPrimary : Color.drip.textTertiary)
                .frame(width: 84, alignment: .leading)
            Text(pointsLabel(c.points, signed: signed))
                .font(.dripStat(12))
                .foregroundStyle(active ? Color.drip.textPrimary : Color.drip.textTertiary)
                .frame(width: 34, alignment: .trailing)
            Text(c.detail)
                .font(.dripCaption(12))
                .foregroundStyle(active ? Color.drip.textSecondary : Color.drip.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 7)
    }

    private func pointsLabel(_ points: Int, signed: Bool) -> String {
        if points == 0 { return "0" }
        if signed { return String(points) }          // recovery deductions arrive negative
        return "+\(points)"                          // stress contributors are additive
    }
}

/// Tiny shape for the dashed legend swatch.
private struct DashSwatch: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}

// MARK: - Chart

/// Hand-rolled per house convention (there is no BarMark anywhere in this
/// app): sRPE bars behind, stress line in ink, recovery line dashed with
/// true gaps where recovery is null, coral rule on the selected day.
private struct StressRecoveryChart: View {
    let days: [DailyScoreDay]
    @Binding var selectedIndex: Int?

    private let topPad: CGFloat = 6
    private let bottomPad: CGFloat = 18   // room for month labels
    private let leftPad: CGFloat = 26     // y labels

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let plotH = h - topPad - bottomPad
            let maxSrpe = max(days.map(\.srpe).max() ?? 1, 1)

            ZStack(alignment: .topLeading) {
                gridlines(w: w, h: h)
                bars(w: w, plotH: plotH, maxSrpe: maxSrpe)
                recoveryPath(w: w, plotH: plotH)
                    .stroke(Color.drip.textSecondary,
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round, dash: [3, 3]))
                stressPath(w: w, plotH: plotH)
                    .stroke(Color.drip.textPrimary,
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                if let i = selectedIndex, days.indices.contains(i) {
                    selectionMark(i: i, w: w, h: h, plotH: plotH)
                }
                monthLabels(w: w, h: h)
            }
            .contentShape(Rectangle())
            // Scrubbing READS; it never navigates. Horizontal drags scrub,
            // vertical drags scroll the page (TrendsSignalLanes rule).
            .gesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { value in
                        guard abs(value.translation.width) >= abs(value.translation.height) else { return }
                        selectedIndex = index(atX: value.location.x, width: w)
                    }
            )
            .simultaneousGesture(
                SpatialTapGesture()
                    .onEnded { value in
                        selectedIndex = index(atX: value.location.x, width: w)
                    }
            )
        }
    }

    // MARK: geometry

    private func colX(_ i: Int, _ w: CGFloat) -> CGFloat {
        let plotW = w - leftPad
        let cw = plotW / CGFloat(max(days.count, 1))
        return leftPad + cw * (CGFloat(i) + 0.5)
    }

    private func yScore(_ v: Double, plotH: CGFloat) -> CGFloat {
        topPad + plotH * CGFloat(1 - v / 100)
    }

    private func index(atX x: CGFloat, width: CGFloat) -> Int {
        let plotW = width - leftPad
        let cw = plotW / CGFloat(max(days.count, 1))
        let i = Int((x - leftPad) / max(cw, 1))
        return min(max(i, 0), days.count - 1)
    }

    // MARK: layers

    private func gridlines(w: CGFloat, h: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach([0.0, 50.0, 100.0], id: \.self) { v in
                let y = yScore(v, plotH: h - topPad - bottomPad)
                Path { p in
                    p.move(to: CGPoint(x: leftPad, y: y))
                    p.addLine(to: CGPoint(x: w, y: y))
                }
                .stroke(Color.drip.divider, style: StrokeStyle(lineWidth: 1, dash: v == 0 ? [] : [2, 3]))
                Text("\(Int(v))")
                    .font(.dripCaption(9)).monospacedDigit()
                    .foregroundStyle(Color.drip.textTertiary)
                    .position(x: leftPad / 2 - 2, y: y)
            }
        }
    }

    private func bars(w: CGFloat, plotH: CGFloat, maxSrpe: Double) -> some View {
        let plotW = w - leftPad
        let cw = plotW / CGFloat(max(days.count, 1))
        // Session-load bars stay a backdrop: cap at 60% of plot height.
        return ForEach(Array(days.enumerated()), id: \.element.id) { i, day in
            if day.srpe > 0 {
                let bh = plotH * 0.6 * CGFloat(day.srpe / maxSrpe)
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.drip.paperDeep)
                    .frame(width: max(cw * 0.7, 1), height: max(bh, 1))
                    .position(x: colX(i, w), y: topPad + plotH - bh / 2)
            }
        }
    }

    private func stressPath(w: CGFloat, plotH: CGFloat) -> Path {
        Path { p in
            var started = false
            for i in days.indices {
                guard let s = days[i].stress else { started = false; continue }
                let pt = CGPoint(x: colX(i, w), y: yScore(Double(s), plotH: plotH))
                if !started { p.move(to: pt); started = true } else { p.addLine(to: pt) }
            }
        }
    }

    /// Recovery breaks into a real gap wherever the day had no recovery
    /// inputs — never interpolated, never drawn as 0.
    private func recoveryPath(w: CGFloat, plotH: CGFloat) -> Path {
        Path { p in
            var started = false
            for i in days.indices {
                guard let r = days[i].recovery else { started = false; continue }
                let pt = CGPoint(x: colX(i, w), y: yScore(Double(r), plotH: plotH))
                if !started { p.move(to: pt); started = true } else { p.addLine(to: pt) }
            }
        }
    }

    private func selectionMark(i: Int, w: CGFloat, h: CGFloat, plotH: CGFloat) -> some View {
        let x = colX(i, w)
        return ZStack {
            Path { p in
                p.move(to: CGPoint(x: x, y: topPad))
                p.addLine(to: CGPoint(x: x, y: topPad + plotH))
            }
            .stroke(Color.drip.coral.opacity(0.55), lineWidth: 1)
            if let s = days[i].stress {
                Circle().fill(Color.drip.coral)
                    .frame(width: 5, height: 5)
                    .position(x: x, y: yScore(Double(s), plotH: plotH))
            }
        }
    }

    private func monthLabels(w: CGFloat, h: CGFloat) -> some View {
        // A label at each month boundary inside the window.
        let boundaries: [(Int, String)] = days.enumerated().compactMap { i, day in
            let comps = Calendar.current.dateComponents([.day], from: day.date)
            guard comps.day == 1 || i == 0 else { return nil }
            return (i, day.date.formatted(.dateTime.month(.abbreviated)).uppercased())
        }
        return ForEach(boundaries, id: \.0) { i, label in
            Text(label)
                .font(.dripCaption(9))
                .foregroundStyle(Color.drip.textTertiary)
                .position(x: colX(i, w), y: h - bottomPad / 2)
        }
    }
}
