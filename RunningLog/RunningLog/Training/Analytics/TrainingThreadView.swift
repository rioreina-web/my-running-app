//
//  TrainingThreadView.swift
//  RunningLog · Training / Analytics
//
//  THE THREAD — 90 days of load, body and voice on one date axis, pushed
//  from the Train tab's CURRENT mode. (Was `StressRecoveryView`; renamed
//  2026-09-08 when the screen stopped being about two scores.)
//
//  THREE REGISTERS, READ STRAIGHT DOWN. The Tuesday that felt bad sits
//  directly above the Tuesday's load and the Tuesday's resting HR. The
//  measured densities behind that choice, and why the qualitative signals
//  are ONE register rather than three lanes, are in TrainingThreadModels.
//
//  NO COMPOSITE, ANYWHERE. `daily_scores.stress` / `.recovery` are not
//  fetched and have no field on `ThreadDay`. The 0-100 pair was cut on
//  2026-09-08 for the second time — a 214-day replay put it in a 37-point
//  strip with no relationship to felt_rpe, and the recovery half was
//  100-minus-deductions over signals that are usually silent, so silence
//  scored as health. Do not re-add a dial, a summed bar, a stacked area, a
//  header strip or a "days in the red" count: anything readable as one
//  number IS the cut thing. See project_recovery_score_model's guard list.
//
//  The rule that replaces it: **co-present, never compose.** A single
//  number cancels opposing signals — "sleep fine + load enormous" and
//  "sleep terrible + load tiny" collapse to the same value. Stacked
//  registers preserve the disagreement, which is the informative part.
//
//  ABSENCE IS DRAWN. HRV has zero rows and sleep check-ins five in ninety
//  days. Those channels get a rail with their reason printed on it rather
//  than being quietly omitted — an empty channel you can see is
//  information, an empty channel that vanishes is how a recovery score
//  reads 100 on a day nobody said anything.
//
//  PALETTE (three-palette rule). Mood owns the warm/green ramp via
//  `TrendsMoodColor`. Coral is the niggle alert and the scrub marker,
//  never a fill. Load bars and curves are ink and graphite. No pace blue
//  on this screen — nothing here is a pace signal.
//
//  Scrubbing READS; it never navigates (TrendsSignalLanes rule).
//

import Combine
import SwiftUI

// MARK: - Shared component model

struct ScoreComponent: Decodable, Identifiable, Equatable {
    let name: String
    /// Scorer-internal weight. Used ONLY to decide whether a row is saying
    /// something (emphasis); never rendered as a number. See file header.
    let points: Int
    let detail: String
    var id: String { name }

    var isSpeaking: Bool { points != 0 }
}

// MARK: - View model

@MainActor
final class TrainingThreadViewModel: ObservableObject {
    enum Phase: Equatable { case loading, loaded, empty, error(String) }

    @Published var phase: Phase = .loading
    @Published var window = ThreadWindow()
    @Published var selectedIndex: Int?
    /// When set, the chart dims everything outside the episode.
    @Published var focusedEpisode: NiggleEpisode?

    /// DEBUG fixture injection for `-threadPreview`; nil in every real build
    /// path, where the service is the only source.
    var injected: ThreadWindow?

    var days: [ThreadDay] { window.days }

    var selected: ThreadDay? {
        guard let i = selectedIndex, days.indices.contains(i) else { return nil }
        return days[i]
    }

    func load() async {
        phase = .loading
        do {
            let fetched: ThreadWindow
            if let injected {
                fetched = injected
            } else {
                fetched = try await TrainingThreadService.fetchWindow()
            }
            window = fetched
            // Open on the most recent day that actually said something —
            // landing on a silent day makes the screen look empty.
            selectedIndex = fetched.days.lastIndex(where: \.hasVoice)
                ?? fetched.days.indices.last
            phase = fetched.days.isEmpty ? .empty : .loaded
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    func focus(_ episode: NiggleEpisode) {
        if focusedEpisode == episode {
            focusedEpisode = nil
        } else {
            focusedEpisode = episode
            selectedIndex = episode.startIndex
        }
    }
}

// MARK: - Screen

struct TrainingThreadView: View {
    @StateObject private var vm = TrainingThreadViewModel()

    /// DEBUG only — see `TrainingThreadViewModel.injected`.
    var preview: ThreadWindow?

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
                        title: "The thread builds from your logged runs — it'll appear after the next nightly pass.",
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
                    ThreadChart(
                        window: vm.window,
                        selectedIndex: $vm.selectedIndex,
                        focused: vm.focusedEpisode
                    )
                    .frame(height: 322)
                    .padding(.top, 16)
                    coverageLine.padding(.top, 10)
                    if let day = vm.selected {
                        DayCard(
                            day: day,
                            band: vm.window.restingHRBand,
                            sleepMedian: vm.window.sleepMedian)
                            .padding(.top, 18)
                    }
                    if !vm.window.episodes.isEmpty {
                        episodeSection.padding(.top, 22)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .background(Color.drip.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task {
            vm.injected = preview
            await vm.load()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LAST 90 DAYS")
                .font(.dripEyebrow(10.5)).tracking(1.3)
                .foregroundStyle(Color.drip.textTertiary)
            Text("The thread")
                .font(.dripDisplay(28))
                .foregroundStyle(Color.drip.textPrimary)
            Text("What the training asked, what the body measured, and what you said about it — on one axis. Tap a day to read it.")
                .font(.dripCaption(13))
                .foregroundStyle(Color.drip.textSecondary)
                .padding(.top, 2)
        }
        .padding(.top, 8)
    }

    private var loading: some View {
        VStack(spacing: 10) {
            ProgressView().tint(Color.drip.coral)
            Text("READING NINETY DAYS")
                .font(.dripEyebrow(10)).tracking(1.4)
                .foregroundStyle(Color.drip.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 64)
    }

    /// Says how much of the window the voice register actually covers.
    /// Coverage, never a grade.
    private var coverageLine: some View {
        Text("You wrote something on \(vm.window.voiceDays) of the last \(vm.days.count) days. The gaps in the voice register are days nobody said anything — not days that went well.")
            .font(.dripCaption(11))
            .foregroundStyle(Color.drip.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var episodeSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("NIGGLE EPISODES")
                .font(.dripEyebrow(9.5)).tracking(1.2)
                .foregroundStyle(Color.drip.textTertiary)
                .padding(.bottom, 8)
            ForEach(vm.window.episodes) { ep in
                Button { vm.focus(ep) } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Rectangle()
                            .fill(Color.drip.coral)
                            .frame(width: 3, height: 12)
                        Text(episodeRange(ep))
                            .font(.dripCaption(12))
                            .foregroundStyle(Color.drip.textPrimary)
                            .frame(width: 106, alignment: .leading)
                        Text(ep.parts.joined(separator: ", "))
                            .font(.dripCaption(12))
                            .foregroundStyle(Color.drip.textSecondary)
                        Spacer(minLength: 0)
                        if vm.focusedEpisode == ep {
                            Text("SHOWN")
                                .font(.dripEyebrow(8.5)).tracking(1.0)
                                .foregroundStyle(Color.drip.coral)
                        }
                    }
                    .padding(.vertical, 7)
                }
                .buttonStyle(.plain)
                if ep.id != vm.window.episodes.last?.id {
                    Divider().overlay(Color.drip.divider)
                }
            }
            Text("Tapping an episode dims the days around it, so you can see what the load and the resting HR were doing while it ran.")
                .font(.dripCaption(11))
                .foregroundStyle(Color.drip.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
        }
    }

    private func episodeRange(_ ep: NiggleEpisode) -> String {
        let f = Date.FormatStyle.dateTime.month(.abbreviated).day()
        if Calendar.current.isDate(ep.startDate, inSameDayAs: ep.endDate) {
            return ep.startDate.formatted(f)
        }
        return "\(ep.startDate.formatted(f)) – \(ep.endDate.formatted(f))"
    }
}

// MARK: - Day card

private struct DayCard: View {
    let day: ThreadDay
    let band: ThreadBand?
    let sleepMedian: Double?

    private var sleepLine: String {
        guard let mins = day.sleepMinutes else { return "not recorded" }
        let text = hoursLabel(Double(mins))
        guard let med = sleepMedian else { return text }
        let delta = Double(mins) - med
        if abs(delta) < 20 { return "\(text) — about your usual \(hoursLabel(med))" }
        return "\(text) — \(hoursLabel(abs(delta))) \(delta > 0 ? "more" : "less") than your usual \(hoursLabel(med))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(day.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()).uppercased())
                .font(.dripEyebrow(10)).tracking(1.2)
                .foregroundStyle(Color.drip.textTertiary)

            // ── LOAD ────────────────────────────────────────────────────
            sectionTitle("WHAT THE TRAINING ASKED").padding(.top, 12)
            HStack(alignment: .firstTextBaseline, spacing: 22) {
                stat("FITNESS", day.fitness)
                stat("FATIGUE", day.fatigue)
                Spacer()
            }
            .padding(.top, 6)
            Text("42- and 7-day averages of session load (RPE × minutes).")
                .font(.dripCaption(11))
                .foregroundStyle(Color.drip.textTertiary)
                .padding(.top, 3)
            reasons(day.loadComponents).padding(.top, 8)

            // ── BODY ────────────────────────────────────────────────────
            sectionTitle("WHAT THE BODY MEASURED").padding(.top, 18)
            bodyLine.padding(.top, 6)

            // ── VOICE ───────────────────────────────────────────────────
            sectionTitle("WHAT YOU SAID").padding(.top, 18)
            voiceBlock.padding(.top, 6)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.drip.cardBackgroundElevated)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.drip.divider, lineWidth: 1))
        )
    }

    private func sectionTitle(_ s: String) -> some View {
        Text(s)
            .font(.dripEyebrow(9.5)).tracking(1.2)
            .foregroundStyle(Color.drip.textTertiary)
    }

    private func stat(_ label: String, _ value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.dripEyebrow(9)).tracking(1.1)
                .foregroundStyle(Color.drip.textTertiary)
            Text(value.map { String(Int($0.rounded())) } ?? "—")
                .font(.dripStat(24))
                .foregroundStyle(Color.drip.textPrimary)
        }
    }

    @ViewBuilder
    private var bodyLine: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let hr = day.restingHR {
                let verdict: String = {
                    guard let band else { return "no baseline yet" }
                    if hr > band.upper { return "above your usual \(Int(band.mean.rounded())) bpm" }
                    if hr < band.lower { return "below your usual \(Int(band.mean.rounded())) bpm" }
                    return "within your usual band (\(Int(band.mean.rounded())) bpm)"
                }()
                channel("RESTING HR", "\(Int(hr.rounded())) bpm — \(verdict)", present: true)
            } else {
                channel("RESTING HR", "not recorded", present: false)
            }
            channel("SLEEP", sleepLine, present: day.sleepMinutes != nil)
            channel("HRV", day.hrv.map { String(format: "%.0f ms", $0) } ?? "no data on this account", present: day.hrv != nil)
        }
    }

    private func channel(_ name: String, _ value: String, present: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(name)
                .font(.dripEyebrow(9)).tracking(1.0)
                .foregroundStyle(present ? Color.drip.textPrimary : Color.drip.textTertiary)
                .frame(width: 84, alignment: .leading)
            Text(value)
                .font(.dripCaption(12))
                .foregroundStyle(present ? Color.drip.textSecondary : Color.drip.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var voiceBlock: some View {
        if !day.hasVoice {
            Text("Nothing recorded for this day.")
                .font(.dripCaption(12))
                .foregroundStyle(Color.drip.textTertiary)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                if day.mood != nil || day.feltRPE != nil {
                    HStack(spacing: 14) {
                        if let mood = day.mood {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(TrendsMoodColor.color(mood))
                                    .frame(width: 8, height: 8)
                                Text(mood.uppercased())
                                    .font(.dripEyebrow(9.5)).tracking(1.1)
                                    .foregroundStyle(Color.drip.textPrimary)
                            }
                        }
                        if let rpe = day.feltRPE {
                            Text("RPE \(rpe == rpe.rounded() ? String(Int(rpe)) : String(format: "%.1f", rpe))")
                                .font(.dripEyebrow(9.5)).tracking(1.1)
                                .foregroundStyle(Color.drip.textPrimary)
                        }
                        Spacer(minLength: 0)
                    }
                }
                // The memo, verbatim. This is the payload of the whole
                // screen — the curves are context for it. Neutral left rule:
                // a coloured one would mean mood (the left-rule rule).
                if let memo = day.memo {
                    Text(memo)
                        .font(.dripBody(14))
                        .foregroundStyle(Color.drip.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 10)
                        .overlay(alignment: .leading) {
                            Rectangle()
                                .fill(Color.drip.divider)
                                .frame(width: 2)
                        }
                }
                if let quote = day.pullQuote, quote != day.memo {
                    Text("“\(quote)”")
                        .font(.dripCaption(12))
                        .italic()
                        .foregroundStyle(Color.drip.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(day.niggles) { n in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Rectangle().fill(Color.drip.coral).frame(width: 3, height: 11)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(n.label.uppercased() + (n.severityHint.map { " · \($0)" } ?? ""))
                                .font(.dripEyebrow(9)).tracking(1.0)
                                .foregroundStyle(Color.drip.textPrimary)
                            if let q = n.quote(besides: day.memo) {
                                Text("“\(q)”")
                                    .font(.dripCaption(12))
                                    .foregroundStyle(Color.drip.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    /// `form` is dropped on purpose: it restates the fitness/fatigue pair
    /// printed directly above it, and the scorer's rounding and the stat
    /// row's can disagree by a unit ("fatigue 329" under a FATIGUE of 330),
    /// which reads as a bug in the numbers rather than in the rounding.
    @ViewBuilder
    private func reasons(_ components: [ScoreComponent]) -> some View {
        let speaking = components.filter { $0.isSpeaking && $0.name != "form" }
        if speaking.isEmpty {
            Text("Nothing notable.")
                .font(.dripCaption(12))
                .foregroundStyle(Color.drip.textTertiary)
        } else {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(speaking) { c in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(c.name.replacingOccurrences(of: "_", with: " ").uppercased())
                            .font(.dripEyebrow(9)).tracking(1.0)
                            .foregroundStyle(Color.drip.textPrimary)
                            .frame(width: 84, alignment: .leading)
                        Text(c.detail)
                            .font(.dripCaption(12))
                            .foregroundStyle(Color.drip.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }
}

func hoursLabel(_ minutes: Double) -> String {
    let m = Int(minutes.rounded())
    return "\(m / 60)h\(String(format: "%02d", m % 60))"
}

// MARK: - Chart

/// Three registers, one x-axis, hand-rolled per house convention (there is
/// no BarMark anywhere in this app).
///
/// The registers are stacked and NEVER combined: a reader draws the
/// conclusion by looking down a column, the product only supplies the
/// alignment. Niggle episodes are the one mark that crosses all three,
/// because "what was the load doing while the knee hurt" is the question
/// co-presence exists to answer.
private struct ThreadChart: View {
    let window: ThreadWindow
    @Binding var selectedIndex: Int?
    let focused: NiggleEpisode?

    private var days: [ThreadDay] { window.days }

    // Register geometry. Fixed rather than proportional: these are three
    // different kinds of thing, and the load register earns the most room
    // because it is the only one with a continuous numeric scale.
    private let leftPad: CGFloat = 34
    private let topPad: CGFloat = 4
    private let loadH: CGFloat = 130
    private let bodyH: CGFloat = 98
    private let voiceH: CGFloat = 48
    private let gap: CGFloat = 12
    private let bottomPad: CGFloat = 18

    private var loadTop: CGFloat { topPad }
    private var loadBottom: CGFloat { loadTop + loadH }
    private var bodyTop: CGFloat { loadBottom + gap }
    private var bodyBottom: CGFloat { bodyTop + bodyH }
    /// BODY carries three channels of very different health: resting HR
    /// (90/90 nights), sleep duration (79/90) and HRV (0). The first two get
    /// a real sub-lane each; HRV gets a rail saying so.
    private var hrTop: CGFloat { bodyTop + 12 }
    private var hrH: CGFloat { 34 }
    private var sleepTop: CGFloat { hrTop + hrH + 10 }
    private var sleepH: CGFloat { 28 }
    private var hrvRailY: CGFloat { sleepTop + sleepH + 12 }

    private var voiceTop: CGFloat { bodyBottom + gap }
    private var voiceBottom: CGFloat { voiceTop + voiceH }

    /// Axis top for the load register: the largest curve value in the
    /// window rounded up to a readable step. Never a fixed 100 — these are
    /// load units, not a score.
    private var loadMax: Double {
        let peak = days.compactMap { max($0.fitness ?? 0, $0.fatigue ?? 0) }.max() ?? 0
        guard peak > 0 else { return 100 }
        let step: Double = peak > 400 ? 100 : (peak > 150 ? 50 : 20)
        return (peak / step).rounded(.up) * step
    }

    /// Resting HR is drawn against the athlete's own baseline, ±2.5 SD of
    /// headroom so the ±0.5 SD band reads as a band and not as the whole
    /// register. Falls back to the window's own range when there is no
    /// baseline yet.
    private var hrRange: (lo: Double, hi: Double)? {
        let vals = days.compactMap(\.restingHR)
        guard !vals.isEmpty else { return nil }
        if let b = window.restingHRBand {
            let lo = min(b.mean - 2.5 * b.sd, vals.min() ?? b.mean)
            let hi = max(b.mean + 2.5 * b.sd, vals.max() ?? b.mean)
            return lo < hi ? (lo, hi) : nil
        }
        let lo = (vals.min() ?? 0) - 1, hi = (vals.max() ?? 1) + 1
        return lo < hi ? (lo, hi) : nil
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .topLeading) {
                episodeBands(w: w)
                loadRegister(w: w)
                bodyRegister(w: w)
                voiceRegister(w: w)
                if let focused { dimming(w: w, episode: focused) }
                if let i = selectedIndex, days.indices.contains(i) {
                    scrubMark(i: i, w: w)
                }
                monthLabels(w: w)
                registerLabels(w: w)
            }
            .contentShape(Rectangle())
            // Horizontal drags scrub, vertical drags scroll the page
            // (TrendsSignalLanes rule). Scrubbing reads; it never navigates.
            .gesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { value in
                        guard abs(value.translation.width) >= abs(value.translation.height) else { return }
                        selectedIndex = index(atX: value.location.x, width: w)
                    }
            )
            .simultaneousGesture(
                SpatialTapGesture().onEnded { value in
                    selectedIndex = index(atX: value.location.x, width: w)
                }
            )
        }
    }

    // MARK: geometry

    private func colWidth(_ w: CGFloat) -> CGFloat {
        (w - leftPad) / CGFloat(max(days.count, 1))
    }

    private func colX(_ i: Int, _ w: CGFloat) -> CGFloat {
        leftPad + colWidth(w) * (CGFloat(i) + 0.5)
    }

    private func index(atX x: CGFloat, width: CGFloat) -> Int {
        let i = Int((x - leftPad) / max(colWidth(width), 1))
        return min(max(i, 0), days.count - 1)
    }

    private func yLoad(_ v: Double) -> CGFloat {
        let plotTop = loadTop + 12
        let plotH = loadBottom - plotTop
        return plotTop + plotH * CGFloat(1 - v / max(loadMax, 1))
    }

    private func yHR(_ v: Double, _ range: (lo: Double, hi: Double)) -> CGFloat {
        let t = (v - range.lo) / max(range.hi - range.lo, 0.0001)
        return hrTop + hrH * CGFloat(1 - t)
    }

    /// Sleep bars hang from the bottom of their sub-lane, scaled to the
    /// window's longest night. Bars rather than a line: a night is a
    /// quantity, and a line here would read as a second physiological
    /// trace alongside resting HR.
    private var sleepMax: Double {
        Double(days.compactMap(\.sleepMinutes).max() ?? 0)
    }

    // MARK: LOAD

    @ViewBuilder
    private func loadRegister(w: CGFloat) -> some View {
        let plotTop = loadTop + 12
        ZStack(alignment: .topLeading) {
            // Gridlines: 0 / half / top, in load units.
            ForEach([0.0, loadMax / 2, loadMax], id: \.self) { v in
                let y = yLoad(v)
                Path { p in
                    p.move(to: CGPoint(x: leftPad, y: y))
                    p.addLine(to: CGPoint(x: w, y: y))
                }
                .stroke(Color.drip.divider, style: StrokeStyle(lineWidth: 1, dash: v == 0 ? [] : [2, 3]))
                Text("\(Int(v))")
                    .font(.dripCaption(9)).monospacedDigit()
                    .foregroundStyle(Color.drip.textTertiary)
                    .position(x: leftPad / 2 - 1, y: y)
            }
            // Session-load bars, a backdrop at 55% of the register.
            let maxSrpe = max(days.map(\.srpe).max() ?? 1, 1)
            ForEach(Array(days.enumerated()), id: \.element.id) { i, day in
                if day.srpe > 0 {
                    let bh = (loadBottom - plotTop) * 0.55 * CGFloat(day.srpe / maxSrpe)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.drip.paperDeep)
                        .frame(width: max(colWidth(w) * 0.7, 1), height: max(bh, 1))
                        .position(x: colX(i, w), y: loadBottom - bh / 2)
                }
            }
            curve(w: w) { $0.fitness }
                .stroke(Color.drip.textSecondary,
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round, dash: [3, 3]))
            curve(w: w) { $0.fatigue }
                .stroke(Color.drip.textPrimary,
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
    }

    /// One curve, breaking into a real gap wherever the day has no value —
    /// never interpolated, never drawn as 0 (TrendsMoodRead convention).
    private func curve(w: CGFloat, value: (ThreadDay) -> Double?) -> Path {
        Path { p in
            var started = false
            for i in days.indices {
                guard let v = value(days[i]) else { started = false; continue }
                let pt = CGPoint(x: colX(i, w), y: yLoad(v))
                if !started { p.move(to: pt); started = true } else { p.addLine(to: pt) }
            }
        }
    }

    // MARK: BODY

    @ViewBuilder
    private func bodyRegister(w: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            hrLane(w: w)
            sleepLane(w: w)
            // HRV is the one genuinely empty channel. It stays on the axis
            // rather than being omitted — see the file header.
            emptyRail(
                w: w, y: hrvRailY, label: "HRV",
                reason: window.hasHRV ? nil : "no data on this account")
        }
    }

    @ViewBuilder
    private func hrLane(w: CGFloat) -> some View {
        if let range = hrRange {
            // The athlete's own ±0.5 SD band, shaded. Same window and
            // threshold as the nightly lanes in Trends.
            if let b = window.restingHRBand {
                let top = yHR(b.upper, range), bottom = yHR(b.lower, range)
                Rectangle()
                    .fill(Color.drip.paperDeep)
                    .frame(width: w - leftPad, height: max(bottom - top, 1))
                    .position(x: leftPad + (w - leftPad) / 2, y: (top + bottom) / 2)
                Text("\(Int(b.mean.rounded()))")
                    .font(.dripCaption(9)).monospacedDigit()
                    .foregroundStyle(Color.drip.textTertiary)
                    .position(x: leftPad / 2 - 1, y: yHR(b.mean, range))
            }
            Path { p in
                var started = false
                for i in days.indices {
                    guard let v = days[i].restingHR else { started = false; continue }
                    let pt = CGPoint(x: colX(i, w), y: yHR(v, range))
                    if !started { p.move(to: pt); started = true } else { p.addLine(to: pt) }
                }
            }
            .stroke(Color.drip.textPrimary,
                    style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
            channelTag("RESTING HR", y: hrTop + 4, w: w)
        } else {
            emptyRail(w: w, y: hrTop + hrH / 2, label: "RESTING HR", reason: "no readings in this window")
        }
    }

    @ViewBuilder
    private func sleepLane(w: CGFloat) -> some View {
        let peak = sleepMax
        if peak > 0 {
            let base = sleepTop + sleepH
            ForEach(Array(days.enumerated()), id: \.element.id) { i, day in
                if let mins = day.sleepMinutes {
                    let bh = sleepH * CGFloat(Double(mins) / peak)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.drip.paperDeep)
                        .frame(width: max(colWidth(w) * 0.7, 1), height: max(bh, 1))
                        .position(x: colX(i, w), y: base - bh / 2)
                }
            }
            // The athlete's own median, not a 7-hour norm.
            if let med = window.sleepMedian {
                let y = base - sleepH * CGFloat(med / peak)
                Path { p in
                    p.move(to: CGPoint(x: leftPad, y: y))
                    p.addLine(to: CGPoint(x: w, y: y))
                }
                .stroke(Color.drip.textTertiary, style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                Text(hoursLabel(med))
                    .font(.dripCaption(9)).monospacedDigit()
                    .foregroundStyle(Color.drip.textTertiary)
                    .position(x: leftPad / 2 - 1, y: y)
            }
            channelTag("SLEEP", y: sleepTop + 2, w: w)
        } else {
            emptyRail(w: w, y: sleepTop + sleepH / 2, label: "SLEEP", reason: "not recorded on these nights")
        }
    }

    private func channelTag(_ s: String, y: CGFloat, w: CGFloat) -> some View {
        Text(s)
            .font(.dripEyebrow(7.5)).tracking(0.9)
            .foregroundStyle(Color.drip.textTertiary)
            .padding(.horizontal, 3)
            .background(Color.drip.background.opacity(0.85))
            .position(x: leftPad + 30, y: y)
    }

    /// A channel that exists in the model and has nothing to say. The dotted
    /// rail keeps it on the axis so the reader can see the hole.
    @ViewBuilder
    private func emptyRail(w: CGFloat, y: CGFloat, label: String, reason: String?) -> some View {
        if let reason {
            Path { p in
                p.move(to: CGPoint(x: leftPad, y: y))
                p.addLine(to: CGPoint(x: w, y: y))
            }
            .stroke(Color.drip.divider, style: StrokeStyle(lineWidth: 1, dash: [1, 4]))
            HStack(spacing: 6) {
                Text(label)
                    .font(.dripEyebrow(8)).tracking(1.0)
                    .foregroundStyle(Color.drip.textTertiary)
                Text(reason)
                    .font(.dripCaption(9))
                    .foregroundStyle(Color.drip.textTertiary)
            }
            .padding(.horizontal, 4)
            .background(Color.drip.background)
            .position(x: leftPad + 78, y: y)
        }
    }

    // MARK: VOICE

    @ViewBuilder
    private func voiceRegister(w: CGFloat) -> some View {
        let swatchTop = voiceTop + 12
        let cw = colWidth(w)
        ZStack(alignment: .topLeading) {
            Path { p in
                p.move(to: CGPoint(x: leftPad, y: swatchTop + 17))
                p.addLine(to: CGPoint(x: w, y: swatchTop + 17))
            }
            .stroke(Color.drip.divider, lineWidth: 1)

            ForEach(Array(days.enumerated()), id: \.element.id) { i, day in
                // Mood is colour only, one swatch per day, all the same
                // height (TrendsSignalLanes 2026-08-06). A day with words
                // but no mood still shows — hollow, so "he said something"
                // and "he said he felt tired" stay distinguishable.
                if let mood = day.mood {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(TrendsMoodColor.color(mood))
                        .frame(width: max(cw * 0.72, 2), height: 16)
                        .position(x: colX(i, w), y: swatchTop + 8)
                } else if day.hasVoice {
                    RoundedRectangle(cornerRadius: 1)
                        .stroke(Color.drip.textTertiary, lineWidth: 1)
                        .frame(width: max(cw * 0.72, 2), height: 16)
                        .position(x: colX(i, w), y: swatchTop + 8)
                }
                if !day.niggles.isEmpty {
                    Circle()
                        .fill(Color.drip.coral)
                        .frame(width: 4, height: 4)
                        .position(x: colX(i, w), y: swatchTop + 26)
                }
            }
        }
    }

    // MARK: crossing marks

    /// Niggle episodes, the one mark that spans every register.
    @ViewBuilder
    private func episodeBands(w: CGFloat) -> some View {
        let cw = colWidth(w)
        ForEach(window.episodes) { ep in
            let x0 = leftPad + cw * CGFloat(ep.startIndex)
            let x1 = leftPad + cw * CGFloat(ep.endIndex + 1)
            Rectangle()
                .fill(Color.drip.coral.opacity(0.07))
                .frame(width: max(x1 - x0, 2), height: voiceBottom - topPad)
                .position(x: (x0 + x1) / 2, y: topPad + (voiceBottom - topPad) / 2)
        }
    }

    /// Focus mode: everything outside the chosen episode is washed back so
    /// the columns inside it can be read against the registers.
    @ViewBuilder
    private func dimming(w: CGFloat, episode: NiggleEpisode) -> some View {
        let cw = colWidth(w)
        let x0 = leftPad + cw * CGFloat(episode.startIndex)
        let x1 = leftPad + cw * CGFloat(episode.endIndex + 1)
        let wash = Color.drip.background.opacity(0.66)
        Rectangle().fill(wash)
            .frame(width: max(x0 - leftPad, 0), height: voiceBottom - topPad)
            .position(x: leftPad + max(x0 - leftPad, 0) / 2, y: topPad + (voiceBottom - topPad) / 2)
        Rectangle().fill(wash)
            .frame(width: max(w - x1, 0), height: voiceBottom - topPad)
            .position(x: x1 + max(w - x1, 0) / 2, y: topPad + (voiceBottom - topPad) / 2)
    }

    @ViewBuilder
    private func scrubMark(i: Int, w: CGFloat) -> some View {
        let x = colX(i, w)
        Path { p in
            p.move(to: CGPoint(x: x, y: topPad))
            p.addLine(to: CGPoint(x: x, y: voiceBottom))
        }
        .stroke(Color.drip.coral.opacity(0.55), lineWidth: 1)
        if let f = days[i].fatigue {
            Circle().fill(Color.drip.coral)
                .frame(width: 5, height: 5)
                .position(x: x, y: yLoad(f))
        }
    }

    // MARK: labels

    /// Register names sit INSIDE their register rather than in a left
    /// gutter. `TrendsMoodLanes` puts them in a 34pt gutter, where they
    /// clip to `\IGGLE` and `VK VOL`; there is no width here that both
    /// fits the names and leaves the plot room.
    @ViewBuilder
    private func registerLabels(w: CGFloat) -> some View {
        label("LOAD", y: loadTop + 5)
        label("BODY", y: bodyTop + 5)
        label("VOICE", y: voiceTop + 5)
    }

    private func label(_ s: String, y: CGFloat) -> some View {
        Text(s)
            .font(.dripEyebrow(8.5)).tracking(1.2)
            .foregroundStyle(Color.drip.textTertiary)
            .position(x: leftPad + 16, y: y)
    }

    @ViewBuilder
    private func monthLabels(w: CGFloat) -> some View {
        let boundaries: [(Int, String)] = days.enumerated().compactMap { i, day in
            let comps = Calendar.current.dateComponents([.day], from: day.date)
            guard comps.day == 1 || i == 0 else { return nil }
            return (i, day.date.formatted(.dateTime.month(.abbreviated)).uppercased())
        }
        ForEach(boundaries, id: \.0) { i, labelText in
            Text(labelText)
                .font(.dripCaption(9))
                .foregroundStyle(Color.drip.textTertiary)
                .position(x: colX(i, w), y: voiceBottom + 9)
        }
    }
}
