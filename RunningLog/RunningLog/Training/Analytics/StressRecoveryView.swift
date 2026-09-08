//
//  StressRecoveryView.swift
//  RunningLog
//
//  The 90-day training-load screen, pushed from the Train tab's CURRENT mode.
//
//  Reads `daily_scores` directly (RLS: athlete reads own rows). The table
//  keys on (user_id, score_date, score_version) and old score versions are
//  never recomputed in place, so a day can carry several rows — this
//  screen keeps only the LATEST version present in the window, matching
//  the coaching-daily-read consumer.
//
//  2026-09-08 — THE 0-100 COMPOSITES ARE GONE FROM THIS SCREEN.
//  `daily_scores.stress` and `.recovery` are deliberately NOT selected and
//  have no field on `DailyScoreDay`, so no view here can render one and the
//  model layer cannot fabricate one. This repeats the 2026-08-24 decision
//  that deleted `TrendsRecoveryLedger`: a 214-day replay found the composite
//  never left a 37-point strip, had no relationship with felt_rpe, and did
//  not move ahead of the one injury in the window. A single figure also
//  CANCELS opposing signals — "sleep fine + load enormous" and "sleep
//  terrible + load tiny" collapse to the same value — and the recovery half
//  is 100-minus-deductions, so silence scored identically to health.
//
//  What survives is what validated: the per-component reason sentences, and
//  the two quantities that are actually modelled rather than assigned —
//  fitness (42-day EWMA of sRPE) and fatigue (7-day EWMA), plotted in their
//  own load units. Component `points` are read ONLY as an internal "is this
//  notable" flag for emphasis; they are never drawn as a figure. Do not
//  re-add a dial, a summed bar, a stacked area, a header strip, or a
//  "days in the red" count — anything readable as one number IS the cut
//  thing (see project_recovery_score_model's guard list).
//
//  Design notes:
//  - Monochrome editorial: ink for fatigue, dashed secondary for fitness,
//    neutral sRPE bars behind, coral reserved for the selected-day marker.
//  - Scrubbing READS; it never navigates (TrendsSignalLanes rule). The
//    component breakdown renders inline below the chart.
//  - Deliberately absent: ACWR and anything phrased as injury risk or
//    readiness.
//

import Combine
import PostgREST
import Supabase
import SwiftUI

// MARK: - Models

struct ScoreComponent: Decodable, Identifiable, Equatable {
    let name: String
    /// Scorer-internal weight. Used ONLY to decide whether a row is saying
    /// something (emphasis); never rendered as a number. See file header.
    let points: Int
    let detail: String
    var id: String { name }

    var isSpeaking: Bool { points != 0 }
}

/// One scored day, already collapsed to the latest score_version.
///
/// No `stress` / `recovery` field by design — see the file header.
struct DailyScoreDay: Identifiable, Equatable {
    let dateString: String        // "2026-09-01" (score_date, a DATE column)
    let date: Date
    let fitness: Double?          // 42-day EWMA of sRPE, load units
    let fatigue: Double?          // 7-day EWMA of sRPE, load units
    let recoveryConfidence: String
    let srpe: Double
    let loadComponents: [ScoreComponent]
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
        let fitness: Double?
        let fatigue: Double?
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

        // `stress` and `recovery` are intentionally absent from this select.
        let response = try await supabase
            .from("daily_scores")
            .select("score_date, score_version, fitness, fatigue, recovery_confidence, srpe, stress_components, recovery_components")
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
                    fitness: row.fitness,
                    fatigue: row.fatigue,
                    recoveryConfidence: row.recovery_confidence ?? "none",
                    srpe: row.srpe ?? 0,
                    loadComponents: row.stress_components ?? [],
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
                        eyebrow: "Nothing plotted yet",
                        title: "Load builds from your logged runs — it'll appear after the next nightly pass.",
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
                    TrainingLoadChart(days: vm.days, selectedIndex: $vm.selectedIndex)
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
            Text("Training load")
                .font(.dripDisplay(28))
                .foregroundStyle(Color.drip.textPrimary)
            Text("Fatigue rides above fitness when you're absorbing work and settles under it when you're not. Tap a day to read what the signals said.")
                .font(.dripCaption(13))
                .foregroundStyle(Color.drip.textSecondary)
                .padding(.top, 2)
        }
        .padding(.top, 8)
    }

    private var loading: some View {
        VStack(spacing: 10) {
            ProgressView().tint(Color.drip.coral)
            Text("READING LOAD")
                .font(.dripEyebrow(10)).tracking(1.4)
                .foregroundStyle(Color.drip.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 64)
    }

    private var legend: some View {
        HStack(spacing: 16) {
            legendItem(label: "FATIGUE") {
                Rectangle().fill(Color.drip.textPrimary).frame(width: 16, height: 2)
            }
            legendItem(label: "FITNESS") {
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
            HStack(alignment: .firstTextBaseline, spacing: 22) {
                loadStat(label: "FITNESS", value: day.fitness)
                loadStat(label: "FATIGUE", value: day.fatigue)
                Spacer()
            }
            .padding(.top, 8)
            Text("42- and 7-day averages of session load (RPE × minutes).")
                .font(.dripCaption(11))
                .foregroundStyle(Color.drip.textTertiary)
                .padding(.top, 4)

            componentSection(
                title: "WHAT THE TRAINING IS ASKING",
                components: day.loadComponents,
                emptyLine: "Nothing recorded for this day."
            )
            .padding(.top, 18)
            componentSection(
                title: "WHAT THE BODY SAID",
                components: day.recoveryComponents,
                emptyLine: "Nothing recorded for this day.",
                footnote: coverageLine(day.recoveryConfidence)
            )
            .padding(.top, 16)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.drip.cardBackgroundElevated)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.drip.divider, lineWidth: 1))
        )
    }

    private func loadStat(label: String, value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.dripEyebrow(9)).tracking(1.1)
                .foregroundStyle(Color.drip.textTertiary)
            Text(value.map { String(Int($0.rounded())) } ?? "—")
                .font(.dripStat(24))
                .foregroundStyle(Color.drip.textPrimary)
        }
    }

    /// How much of the body side actually spoke. Coverage, not a grade —
    /// the point is that silence is visible as silence.
    private func coverageLine(_ confidence: String) -> String {
        switch confidence {
        case "low": return "One signal reported. The rest were silent."
        case "ok": return "Two or more signals reported."
        default: return "No signals reported for this day."
        }
    }

    private func componentSection(
        title: String,
        components: [ScoreComponent],
        emptyLine: String,
        footnote: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.dripEyebrow(9.5)).tracking(1.2)
                .foregroundStyle(Color.drip.textTertiary)
                .padding(.bottom, 6)
            if components.isEmpty {
                Text(emptyLine)
                    .font(.dripCaption(12))
                    .foregroundStyle(Color.drip.textTertiary)
            } else {
                ForEach(components) { c in
                    componentRow(c)
                    if c.id != components.last?.id {
                        Divider().overlay(Color.drip.divider)
                    }
                }
            }
            if let footnote {
                Text(footnote)
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textTertiary)
                    .padding(.top, 8)
            }
        }
    }

    /// Name + its own reason sentence. No points column: the arithmetic was
    /// the part that failed validation, the sentences were the part that
    /// didn't (see file header).
    private func componentRow(_ c: ScoreComponent) -> some View {
        let speaking = c.isSpeaking
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(c.name.replacingOccurrences(of: "_", with: " ").uppercased())
                .font(.dripEyebrow(9)).tracking(1.0)
                .foregroundStyle(speaking ? Color.drip.textPrimary : Color.drip.textTertiary)
                .frame(width: 84, alignment: .leading)
            Text(c.detail)
                .font(.dripCaption(12))
                .foregroundStyle(speaking ? Color.drip.textSecondary : Color.drip.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 7)
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
/// app): sRPE bars behind, fatigue in ink, fitness dashed, coral rule on the
/// selected day. Both lines share one axis in load units — they are the same
/// quantity at two time constants, which is the whole point of the picture.
private struct TrainingLoadChart: View {
    let days: [DailyScoreDay]
    @Binding var selectedIndex: Int?

    private let topPad: CGFloat = 6
    private let bottomPad: CGFloat = 18   // room for month labels
    private let leftPad: CGFloat = 34     // y labels (load units run to 3-4 digits)

    /// Axis top: the largest curve value in the window, rounded up to a
    /// readable step. Never a fixed 100 — these are load units, not a score.
    private var axisMax: Double {
        let peak = days.compactMap { max($0.fitness ?? 0, $0.fatigue ?? 0) }.max() ?? 0
        guard peak > 0 else { return 100 }
        let step: Double = peak > 400 ? 100 : (peak > 150 ? 50 : 20)
        return (peak / step).rounded(.up) * step
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let plotH = h - topPad - bottomPad
            let maxSrpe = max(days.map(\.srpe).max() ?? 1, 1)
            let top = axisMax

            ZStack(alignment: .topLeading) {
                gridlines(w: w, h: h, top: top)
                bars(w: w, plotH: plotH, maxSrpe: maxSrpe)
                curve(w: w, plotH: plotH, top: top) { $0.fitness }
                    .stroke(Color.drip.textSecondary,
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round, dash: [3, 3]))
                curve(w: w, plotH: plotH, top: top) { $0.fatigue }
                    .stroke(Color.drip.textPrimary,
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                if let i = selectedIndex, days.indices.contains(i) {
                    selectionMark(i: i, w: w, h: h, plotH: plotH, top: top)
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

    private func yLoad(_ v: Double, plotH: CGFloat, top: Double) -> CGFloat {
        topPad + plotH * CGFloat(1 - v / max(top, 1))
    }

    private func index(atX x: CGFloat, width: CGFloat) -> Int {
        let plotW = width - leftPad
        let cw = plotW / CGFloat(max(days.count, 1))
        let i = Int((x - leftPad) / max(cw, 1))
        return min(max(i, 0), days.count - 1)
    }

    // MARK: layers

    private func gridlines(w: CGFloat, h: CGFloat, top: Double) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach([0.0, top / 2, top], id: \.self) { v in
                let y = yLoad(v, plotH: h - topPad - bottomPad, top: top)
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

    /// One curve, breaking into a real gap wherever the day has no value —
    /// never interpolated, never drawn as 0 (TrendsMoodRead convention).
    private func curve(
        w: CGFloat,
        plotH: CGFloat,
        top: Double,
        value: (DailyScoreDay) -> Double?
    ) -> Path {
        Path { p in
            var started = false
            for i in days.indices {
                guard let v = value(days[i]) else { started = false; continue }
                let pt = CGPoint(x: colX(i, w), y: yLoad(v, plotH: plotH, top: top))
                if !started { p.move(to: pt); started = true } else { p.addLine(to: pt) }
            }
        }
    }

    private func selectionMark(i: Int, w: CGFloat, h: CGFloat, plotH: CGFloat, top: Double) -> some View {
        let x = colX(i, w)
        return ZStack {
            Path { p in
                p.move(to: CGPoint(x: x, y: topPad))
                p.addLine(to: CGPoint(x: x, y: topPad + plotH))
            }
            .stroke(Color.drip.coral.opacity(0.55), lineWidth: 1)
            if let f = days[i].fatigue {
                Circle().fill(Color.drip.coral)
                    .frame(width: 5, height: 5)
                    .position(x: x, y: yLoad(f, plotH: plotH, top: top))
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
