//
//  PaceSignalView.swift
//  RunningLog
//
//  "The Signal" — a prototype Trends surface (from the approved HTML mock
//  `trends-pace-signal-prototype.html`). Added as an ADDITIONAL tab (see
//  DripTab.signal) so it can be evaluated alongside the existing Trends tab.
//
//  Data is REAL:
//   • Pace scale (Easy/MP/LT/5K anchors, slow→fast bounds) from
//     `PaceZonesService` (current-fitness, race-anchored).
//   • Daily bars, pace distribution, ACWR and mood from `SignalService`,
//     which buckets the athlete's `training_logs` runs into pace zones.
//   • Over Time is DAILY: one bar per day = that day's miles stacked by
//     pace zone; rest days are gaps; horizontally scrollable.
//
//  Not wired yet: niggles (next, from `body_mentions`). Runs without
//  per-mile splits are classified at their whole-run average pace.
//
//  Palette (2026-07-03): blue = pace, warm = mood, coral = alert.
//

import SwiftUI

private let axisDateFormatter: DateFormatter = {
    let f = DateFormatter(); f.dateFormat = "MMM d"; return f
}()

// MARK: - Time range

private enum SignalRange: String, CaseIterable, Identifiable {
    case week = "Weekly", month = "Monthly", threeMonth = "3M", sixMonth = "6M", year = "1Y", custom = "Custom"
    var id: String { rawValue }

    var nominalDays: Int {
        switch self {
        case .week: return 7
        case .month: return 30
        case .threeMonth: return 90
        case .sixMonth: return 180
        case .year: return 365
        case .custom: return 90
        }
    }
    var distributionLabel: String {
        switch self {
        case .week: return "THIS WEEK"
        case .month: return "30 DAYS"
        case .threeMonth: return "3 MONTHS"
        case .sixMonth: return "6 MONTHS"
        case .year: return "12 MONTHS"
        case .custom: return "CUSTOM RANGE"
        }
    }
}

// MARK: - Helpers

private func moodColor(_ mood: String) -> Color {
    switch mood.lowercased() {
    case "energized": return Color.drip.energized
    case "positive":  return Color.drip.positive
    case "neutral":   return Color.drip.neutral
    case "tired":     return Color.drip.tired
    case "struggling":return Color.drip.struggling
    case "injured":   return Color.drip.injured
    default:          return Color.drip.neutral
    }
}

private func paceString(_ sec: Double) -> String {
    // Route through the canonical round-first formatter. The old inline
    // version took minutes from an UNROUNDED floor but seconds from the
    // rounded value, so 419.6s rendered "6:00" — a full minute off.
    PaceCalculator.formatPace(sec)
}

private enum SignalTab { case spectrum, overTime }

/// Anchors derived from the athlete's live pace zones (for the histogram).
private struct PaceScale {
    let slow: Double
    let fast: Double
    let anchors: [AnchorMark]
    /// label, pace, and whether it was pinned to the fast edge because it sits
    /// beyond the fitted range.
    let axisMarks: [(String, Double, Bool)]

    /// Built from the histogram's FITTED bounds (the same slow/fast the bars
    /// are bucketed with), so labels can never drift from the bars. Fast-end
    /// anchors that fall outside the fitted range are dropped rather than
    /// clamped to a lie; EASY always shows to anchor the slow end.
    init?(zones z: PaceZonesEngine, slow: Double, fast: Double) {
        guard slow > fast, let easyMid = z.easyMidpoint else { return nil }
        self.slow = slow
        self.fast = fast

        func inRange(_ p: Double) -> Bool { p <= slow && p >= fast }

        var a: [AnchorMark] = [AnchorMark(label: "EASY", pace: easyMid, color: PaceSpectrum.easyText)]
        if let mp = z.marathon?.pace, inRange(mp) { a.append(AnchorMark(label: "MP", pace: mp, color: PaceSpectrum.stops[3])) }
        if let lt = z.thresholdPace,  inRange(lt) { a.append(AnchorMark(label: "LT", pace: lt, color: PaceSpectrum.stops[5])) }
        if let fk = z.fiveK?.pace,    inRange(fk) { a.append(AnchorMark(label: "5K", pace: fk, color: PaceSpectrum.stops[7])) }
        self.anchors = a

        // Legend marks — REAL paces only, ordered slow → fast, so each one can
        // be drawn at its true position on the same scale as the bars.
        //
        // These used to open with a synthetic ("EASY", slow - 3) and close with
        // ("FAST", fast + 2) — edge markers wearing zone names — and the legend
        // then spaced the whole list evenly by array index. With four marks that
        // put MP at exactly 1/3 across, which for a 5:34 marathon pace landed it
        // on 7:05–7:15: the athlete's EASY pace. (Rio, 2026-07-27.)
        // The full ladder, slow → fast. `beyond` flags an anchor that sits off
        // the fast end of the fitted range: the athlete has a mile pace even in
        // a month where they ran nothing at it, and hiding it makes the legend
        // look like the spectrum stops at 5K. Those get pinned to the edge and
        // drawn in tertiary ink so the position reads as "past here", not "here".
        var m: [(String, Double, Bool)] = []
        func add(_ label: String, _ pace: Double?) {
            guard let p = pace else { return }
            if inRange(p) { m.append((label, p, false)) }
            else if p < fast { m.append((label, fast, true)) }   // faster than the axis
        }
        add("EASY", easyMid)
        add("STEADY", z.steadyMidpoint)
        add("MP", z.marathon?.pace)
        add("LT", z.thresholdPace)
        add("5K", z.fiveK?.pace)
        add("MILE", z.mile?.pace)
        self.axisMarks = m
    }
}

private struct AnchorMark: Identifiable {
    let id = UUID(); let label: String; let pace: Double; let color: Color
}

// MARK: - Root

struct PaceSignalView: View {
    /// Inline inside the Trends tab: drop the own-scroll, the page header and
    /// the background, so it composes into the parent's scroll instead of
    /// nesting one. Pushed full-screen when false.
    var embedded = false

    /// The window, in days, imposed by the host. When set, this view stops
    /// owning a time range: its own WEEKLY/MONTHLY/3M/… bar is hidden and the
    /// window comes from the host's control instead.
    ///
    /// The Trends tab used to show three independent time controls stacked in
    /// one viewport — the tab's 4WK/12WK/6MO, this view's six-chip range bar,
    /// and the SPECTRUM/OVER TIME toggle — with nothing reconciling the first
    /// two. The tab could read "6 MO" while the spectrum below it summed a
    /// single week. One range now wins; this is how it gets down here.
    /// (Rio, 2026-08-03.)
    var fixedWindowDays: Int? = nil
    /// What to call `fixedWindowDays` in the section title ("12 WK"). Ignored
    /// when the view owns its own range.
    var fixedWindowLabel: String? = nil

    @State private var zonesService = PaceZonesService.shared
    @State private var service: SignalService
    @State private var tab: SignalTab = .spectrum
    @State private var range: SignalRange = .threeMonth
    @State private var showCustom = false
    @State private var customStart = Calendar.current.date(byAdding: .month, value: -3, to: .now) ?? .now
    @State private var customEnd = Date.now

    init(
        embedded: Bool = false,
        fixedWindowDays: Int? = nil,
        fixedWindowLabel: String? = nil,
        service: SignalService = .shared
    ) {
        self.embedded = embedded
        self.fixedWindowDays = fixedWindowDays
        self.fixedWindowLabel = fixedWindowLabel
        _service = State(initialValue: service)
    }

    /// True when the host owns the range — the tab-embedded case.
    private var hostControlsRange: Bool { fixedWindowDays != nil }

    private var zones: PaceZonesEngine? { zonesService.zones }
    private var scale: PaceScale? {
        guard let z = zones else { return nil }
        return PaceScale(zones: z, slow: service.distSlow, fast: service.distFast)
    }
    private var hasRuns: Bool { service.days.contains { !$0.comp.isEmpty } }

    private var windowDays: Int {
        let raw: Int
        if let fixed = fixedWindowDays {
            raw = fixed
        } else if range == .custom {
            raw = max(1, Calendar.current.dateComponents([.day], from: customStart, to: customEnd).day ?? 7)
        } else {
            raw = range.nominalDays
        }
        return min(max(raw, 1), max(service.days.count, 1))
    }

    /// Title over the spectrum histogram. Names the host's window when the
    /// host owns it, so the label can't claim a range the bars didn't sum.
    private var distributionTitle: String {
        if hostControlsRange { return (fixedWindowLabel ?? "\(windowDays) days").uppercased() }
        return range.distributionLabel
    }

    /// Share of the window's miles run in the Easy zone. The one number the
    /// histogram's shape doesn't state outright, so it survives as a caption
    /// after the VOLUME/WORKLOAD/MOOD tiles come out of the embedded surface.
    private var easyPct: Int? {
        let total = window.reduce(0.0) { $0 + $1.miles }
        guard total > 0 else { return nil }
        let easy = window.reduce(0.0) { acc, d in
            acc + d.comp.filter { $0.zone == 0 }.reduce(0.0) { $0 + $1.mi }
        }
        return Int((easy / total * 100).rounded())
    }
    private var window: [SignalDay] { Array(service.days.suffix(windowDays)) }
    private var windowAcwr: [Double] { Array(service.acwr.suffix(windowDays)) }

    /// Pace-distribution histogram summed over the SELECTED range window, so
    /// the SPECTRUM bars respond to Weekly / Monthly / 3M / … the same way the
    /// tiles and the OVER TIME chart already do. Falls back to the service-
    /// level histogram for preview / legacy days that carry no per-day buckets.
    private var windowDist: [Double] {
        let n = SignalService.bucketCount
        var out = Array(repeating: 0.0, count: n)
        var haveBuckets = false
        for d in window where d.paceBuckets.count == n {
            haveBuckets = true
            for i in 0..<n { out[i] += d.paceBuckets[i] }
        }
        return haveBuckets ? out : service.dist
    }

    var body: some View {
        Group {
            if embedded {
                stack
            } else {
                ScrollView {
                    stack
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 40)
                }
                .background(Color.drip.background.ignoresSafeArea())
            }
        }
        .sheet(isPresented: $showCustom) { customSheet }
        .task(id: zones) { await service.refresh(zones: zones) }
    }

    private var stack: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !embedded { header }
            if !hostControlsRange {
                rangeBar.padding(.top, embedded ? 0 : 14)
                segmenter.padding(.top, 14)
            } else {
                segmenter
            }
            content.padding(.top, 16)
        }
    }

    // MARK: State router

    @ViewBuilder private var content: some View {
        if scale == nil {
            zonesEmptyState
        } else if !service.loaded {
            loadingState
        } else if !hasRuns {
            noRunsState
        } else {
            VStack(alignment: .leading, spacing: 16) {
                // The tiles restate what the host already says. VOLUME is the
                // load section's "This wk / 4-wk avg / Peak", WORKLOAD is the
                // acute:chronic band directly above, MOOD is the mood ribbon
                // below — and because each was computed over a different window
                // they contradicted their twins on screen (60 mi vs 67,
                // TIRED vs struggling). They stay on the standalone surface,
                // which has no host to duplicate. (Rio, 2026-08-03.)
                if !hostControlsRange { tiles }
                if tab == .spectrum { spectrumSection } else { overTimeSection }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TRENDS").font(.dripEyebrow(10.5)).tracking(1.3).foregroundStyle(Color.drip.coral)
            Text("Where your\nmiles live.").font(.dripDisplay(27)).foregroundStyle(Color.drip.textPrimary).lineSpacing(1)
        }
    }

    private var rangeBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(SignalRange.allCases) { r in
                    let selected = (range == r)
                    Button {
                        if r == .custom { showCustom = true }
                        else { withAnimation(.easeOut(duration: 0.15)) { range = r } }
                    } label: {
                        Text(r.rawValue.uppercased()).font(.dripEyebrow(10)).tracking(0.6)
                            .fontWeight(selected ? .semibold : .regular)
                            .foregroundStyle(selected ? Color.drip.textPrimary : Color.drip.textSecondary)
                            .padding(.horizontal, 11).padding(.vertical, 6)
                            .background(Capsule().fill(selected ? Color.drip.cardBackground : Color.drip.paperDeep))
                            .overlay(Capsule().stroke(selected ? Color.drip.coral.opacity(0.5) : Color.clear, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 1)
        }
    }

    private var segmenter: some View {
        HStack(spacing: 2) {
            segButton("Spectrum", .spectrum)
            segButton("Over Time", .overTime)
        }
        .padding(3).background(Color.drip.paperDeep).clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func segButton(_ title: String, _ value: SignalTab) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) { tab = value }
        } label: {
            Text(title.uppercased()).font(.dripEyebrow(10.5)).tracking(0.8)
                .fontWeight(tab == value ? .semibold : .regular)
                .foregroundStyle(tab == value ? Color.drip.textPrimary : Color.drip.textSecondary)
                .frame(maxWidth: .infinity).padding(.vertical, 8)
                .background(tab == value ? Color.drip.cardBackground : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    // MARK: Tiles

    private var tiles: some View {
        let totalMi = window.reduce(0.0) { $0 + $1.miles }
        let easyMi = window.reduce(0.0) { acc, d in acc + d.comp.filter { $0.zone == 0 }.reduce(0.0) { $0 + $1.mi } }
        let easyPct = totalMi > 0 ? Int((easyMi / totalMi * 100).rounded()) : 0
        let latestMood = window.reversed().first(where: { $0.mood != nil })?.mood ?? "neutral"
        return HStack(spacing: 8) {
            SignalTile(label: "VOLUME", value: "\(Int(totalMi))", sub: "\(easyPct)% easy")
            SignalTile(label: "WORKLOAD", value: String(format: "%.2f", windowAcwr.last ?? 0), sub: acwrSubtitle(windowAcwr.last ?? 0))
            SignalTile(label: "MOOD", moodValue: latestMood)
        }
    }

    private func acwrSubtitle(_ v: Double) -> String {
        if v == 0 { return " " }
        return (v >= 0.8 && v <= 1.3) ? "safe zone" : "outside"
    }

    // MARK: Sections

    private var spectrumSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(distributionTitle)
                    .font(.dripEyebrow(13)).tracking(1.6)
                    .foregroundStyle(Color.drip.textSecondary)
                Spacer()
                if let p = easyPct {
                    Text("\(p)% EASY")
                        .font(.dripEyebrow(10)).tracking(0.8)
                        .foregroundStyle(Color.drip.textTertiary)
                }
            }
            if let scale {
                SpectrumDistribution(scale: scale, buckets: windowDist).frame(height: 208)
            }
        }
    }

    private var overTimeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("OVER TIME · \(windowDays) DAYS").font(.dripEyebrow(13)).tracking(1.6).foregroundStyle(Color.drip.textSecondary)
            DailyOverTimeChart(days: window, acwr: windowAcwr).frame(height: 300)
            SpectrumKey()
            Text("One bar per day. Tap for detail.")
                .font(.dripCaption(11)).foregroundStyle(Color.drip.textTertiary)
        }
    }

    // MARK: States

    private var zonesEmptyState: some View {
        infoCard(title: "NO PACE ZONES YET",
                 body: "Log a few runs or add a recent race and your pace spectrum builds itself from your real fitness. Nothing here is a fixed number.")
    }
    private var noRunsState: some View {
        infoCard(title: "NO RUNS IN RANGE",
                 body: "Once your runs sync, each day appears as a bar colored by the paces you actually ran. Pick a wider range or log a run to see it fill in.")
    }
    private var loadingState: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Reading your runs…").font(.dripBody(14)).foregroundStyle(Color.drip.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 60)
    }
    private func infoCard(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.dripEyebrow(10.5)).tracking(1.2).foregroundStyle(Color.drip.textSecondary)
            Text(body).font(.dripBody(13)).foregroundStyle(Color.drip.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.drip.cardBackgroundElevated))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.drip.divider, lineWidth: 1))
    }

    private var customSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("CUSTOM RANGE").font(.dripEyebrow(11)).tracking(1.2).foregroundStyle(Color.drip.coral)
            DatePicker("From", selection: $customStart, in: ...customEnd, displayedComponents: .date).font(.dripBody(15))
            DatePicker("To", selection: $customEnd, in: customStart...Date.now, displayedComponents: .date).font(.dripBody(15))
            Button {
                withAnimation(.easeOut(duration: 0.15)) { range = .custom }
                showCustom = false
            } label: {
                Text("APPLY").font(.dripEyebrow(12)).tracking(1)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(Color.drip.coral).foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(22).presentationDetents([.medium]).background(Color.drip.background)
    }
}

// MARK: - Tile

private struct SignalTile: View {
    let label: String
    var value: String? = nil
    var sub: String? = nil
    var moodValue: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.dripEyebrow(8.5)).tracking(0.7).foregroundStyle(Color.drip.textSecondary)
            if let moodValue {
                HStack(spacing: 4) {
                    Circle().fill(moodColor(moodValue)).frame(width: 7, height: 7)
                    Text(moodValue).font(.dripStat(13)).foregroundStyle(moodColor(moodValue))
                }
            } else {
                Text(value ?? "").font(.dripStat(18)).foregroundStyle(Color.drip.textPrimary)
            }
            Text(sub ?? " ").font(.dripCaption(10)).foregroundStyle(Color.drip.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 11).fill(Color.drip.cardBackground))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.drip.divider, lineWidth: 1))
    }
}

// MARK: - Spectrum distribution (real buckets, real pace scale)

private struct SpectrumDistribution: View {
    let scale: PaceScale
    let buckets: [Double]
    @State private var scrubIndex: Int? = nil

    private var miMax: Double {
        let m = buckets.max() ?? 0
        return max(10, (m / 10).rounded(.up) * 10)
    }
    private func fraction(_ pace: Double) -> CGFloat {
        let denom = scale.slow - scale.fast
        guard denom > 0 else { return 0 }
        return CGFloat((scale.slow - pace) / denom)
    }

    private var bucketN: Int { max(buckets.count, 1) }
    private var bucketTotal: Double { max(buckets.reduce(0, +), 0.0001) }

    /// Scrubbed-bucket read-out (pace range + miles + share). Always ordered
    /// fast→slow so the range never reads backwards.
    private func scrubReadout(_ si: Int) -> (range: String, detail: String)? {
        guard buckets.indices.contains(si) else { return nil }
        let step = (scale.slow - scale.fast) / Double(bucketN)
        let a = scale.slow - Double(si) * step
        let b = scale.slow - Double(si + 1) * step
        let lo = min(a, b), hi = max(a, b)
        let mi = buckets[si]
        let pct = Int((mi / bucketTotal * 100).rounded())
        return ("\(paceString(lo))–\(paceString(hi)) /mi",
                "\(String(format: "%.1f", mi)) mi · \(pct)%")
    }

    /// Nudge label x-positions apart so close paces don't overlap (fast end).
    /// `xs` must be ascending.
    private func spread(_ xs: [CGFloat], minGap: CGFloat, minX: CGFloat, maxX: CGFloat) -> [CGFloat] {
        var out = xs
        guard out.count > 1 else { return out }
        for i in 1..<out.count where out[i] - out[i - 1] < minGap { out[i] = out[i - 1] + minGap }
        if let last = out.last, last > maxX { let s = last - maxX; for i in out.indices { out[i] -= s } }
        if let first = out.first, first < minX { let s = minX - first; for i in out.indices { out[i] += s } }
        return out
    }

    var body: some View {
        VStack(spacing: 10) {
            // A single reserved line. Empty by default (the shape is the point);
            // scrubbing fills it with the touched bucket's pace + miles. No
            // permanent labels float over the bars — the pace axis lives once,
            // along the bottom.
            ZStack {
                if let si = scrubIndex, let r = scrubReadout(si) {
                    HStack(spacing: 8) {
                        Text(r.range).font(.dripEyebrow(11)).tracking(0.4)
                            .foregroundStyle(Color.drip.textPrimary)
                        Text(r.detail).font(.dripStat(11)).foregroundStyle(Color.drip.textSecondary)
                    }
                } else {
                    Text("Drag to read any pace")
                        .font(.dripEyebrow(9)).tracking(0.8)
                        .foregroundStyle(Color.drip.textTertiary)
                }
            }
            .frame(height: 16)
            .animation(.easeOut(duration: 0.12), value: scrubIndex)

            // Bars — the distribution, full-bleed. No gridlines, no Y axis:
            // depth (blue ramp) encodes pace, height encodes miles, and the
            // exact number is a scrub away. The shape reads at a glance.
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                let n = max(buckets.count, 1)
                let cw = w / CGFloat(n)
                let vmax = miMax
                ZStack(alignment: .topLeading) {
                    ForEach(0..<n, id: \.self) { i in
                        let mi = buckets[i]
                        let bh = CGFloat(mi / vmax) * h
                        let f = (Double(i) + 0.5) / Double(n)
                        RoundedRectangle(cornerRadius: 1.5).fill(PaceSpectrum.color(at: f))
                            .opacity(scrubIndex == nil || scrubIndex == i ? 1 : 0.4)
                            .frame(width: cw * 0.76, height: max(bh, 0))
                            .position(x: cw * (CGFloat(i) + 0.5), y: h - bh / 2)
                    }
                    if let si = scrubIndex, si < n {
                        let x = cw * (CGFloat(si) + 0.5)
                        let mi = buckets[si]
                        let bh = CGFloat(mi / vmax) * h
                        Path { p in p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: h)) }
                            .stroke(Color.drip.textPrimary.opacity(0.25), lineWidth: 1)
                        RoundedRectangle(cornerRadius: 1.5).stroke(Color.drip.textPrimary, lineWidth: 1.5)
                            .frame(width: cw * 0.76, height: max(bh, 3))
                            .position(x: x, y: h - bh / 2)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            let idx = Int(v.location.x / cw)
                            scrubIndex = min(max(idx, 0), n - 1)
                        }
                )
            }

            // The one pace axis: the blue ramp itself, with zone ticks at their
            // true pace positions. It's the colour key and the x-axis in a single
            // strip — no second label row, no legend.
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 6).fill(PaceSpectrum.gradient).frame(height: 10)
                GeometryReader { geo in
                    let base = scale.axisMarks.map { fraction($0.1) * geo.size.width }
                    let xs = spread(base, minGap: 34, minX: 16, maxX: geo.size.width - 16)
                    ForEach(Array(scale.axisMarks.enumerated()), id: \.offset) { idx, m in
                        // EASY carries a taller tick — it anchors the slow end
                        // and it's where most of the volume lives.
                        let tall = (m.0 == "EASY")
                        VStack(spacing: 2) {
                            Rectangle()
                                .fill(m.2 ? Color.drip.textTertiary : Color.drip.textSecondary)
                                .frame(width: tall ? 1.4 : 1, height: tall ? 8 : 5)
                            Text(m.0).font(.dripEyebrow(tall ? 9.5 : 8.5))
                                .foregroundStyle(m.2 ? Color.drip.textTertiary : Color.drip.textSecondary)
                                .fixedSize()
                        }
                        .position(x: xs[idx], y: 10)
                    }
                }
                .frame(height: 22)
            }
        }
    }
}

// MARK: - Daily over-time chart (one bar per day, scrollable) + computed ACWR

private struct DailyOverTimeChart: View {
    let days: [SignalDay]
    let acwr: [Double]
    @State private var selIndex: Int? = nil
    @State private var detailDay: SignalDay? = nil
    private let leftPad: CGFloat = 26
    private let rightPad: CGFloat = 22
    private let minColWidth: CGFloat = 13
    private let barsH: CGFloat = 150
    private let loadH: CGFloat = 56
    private let moodH: CGFloat = 50
    private let dayVolMax = 20.0

    private func colX(_ i: Int, _ w: CGFloat) -> CGFloat {
        let plotW = w - leftPad - rightPad
        let cw = plotW / CGFloat(max(days.count, 1))
        return leftPad + cw * (CGFloat(i) + 0.5)
    }
    private func colW(_ w: CGFloat) -> CGFloat {
        (w - leftPad - rightPad) / CGFloat(max(days.count, 1))
    }
    private var labelIndices: [Int] {
        let n = days.count
        guard n > 0 else { return [] }
        if n <= 8 { return Array(0..<n) }
        let step = max(1, n / 6)
        var idx = Array(stride(from: 0, to: n, by: step))
        if idx.last != n - 1 { idx.append(n - 1) }
        return idx
    }

    var body: some View {
        GeometryReader { geo in
            let viewportW = geo.size.width
            let contentW = max(viewportW, leftPad + rightPad + CGFloat(days.count) * minColWidth)
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(spacing: 10) {
                    barsLane(width: contentW).frame(width: contentW, height: barsH)
                    workloadLane(width: contentW).frame(width: contentW, height: loadH)
                    moodLane(width: contentW).frame(width: contentW, height: moodH)
                }
                .contentShape(Rectangle())
                // Tap (not drag) so horizontal scrolling still works. Selects
                // the day + opens its detail sheet.
                .gesture(
                    SpatialTapGesture().onEnded { value in
                        let cw = (contentW - leftPad - rightPad) / CGFloat(max(days.count, 1))
                        let idx = Int((value.location.x - leftPad) / cw)
                        let clamped = min(max(idx, 0), max(days.count - 1, 0))
                        selIndex = clamped
                        if days.indices.contains(clamped) { detailDay = days[clamped] }
                    }
                )
            }
            .defaultScrollAnchor(.trailing)
        }
        .sheet(item: $detailDay) { day in
            SignalDaySheet(day: day)
                .presentationDetents([.medium, .large])
        }
    }

    private func barsLane(width w: CGFloat) -> some View {
        let h = barsH
        let cw = colW(w)
        let vmax = dayVolMax
        return ZStack(alignment: .topLeading) {
            ForEach([10, 20], id: \.self) { v in
                let y = h - CGFloat(Double(v) / vmax) * h
                Path { p in p.move(to: CGPoint(x: leftPad, y: y)); p.addLine(to: CGPoint(x: w - rightPad, y: y)) }
                    .stroke(Color.drip.divider.opacity(0.6), lineWidth: 1)
                Text("\(v)").font(.dripEyebrow(7.5)).foregroundStyle(Color.drip.textTertiary)
                    .position(x: leftPad - 12, y: y)
            }
            ForEach(days.indices, id: \.self) { i in
                let comp = days[i].comp.sorted { $0.zone < $1.zone }
                ForEach(comp.indices, id: \.self) { k in
                    let below = comp.prefix(k).reduce(0.0) { $0 + $1.mi }
                    let mi = comp[k].mi
                    let segH = CGFloat(min(mi, vmax) / vmax) * h
                    let yTop = h - CGFloat(min(below + mi, vmax) / vmax) * h
                    Rectangle().fill(PaceSpectrum.stops[min(max(comp[k].zone, 0), 9)])
                        .opacity(selIndex == nil || selIndex == i ? 1 : 0.35)
                        .frame(width: max(cw * 0.7, 2), height: segH)
                        .position(x: colX(i, w), y: yTop + segH / 2)
                }
            }
            if let s = selIndex, days.indices.contains(s) {
                let x = colX(s, w)
                let total = days[s].miles
                let ch = CGFloat(min(total, vmax) / vmax) * h
                Path { p in p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: h)) }
                    .stroke(Color.drip.textPrimary.opacity(0.2), lineWidth: 1)
                if ch > 0 {
                    RoundedRectangle(cornerRadius: 1).stroke(Color.drip.textPrimary, lineWidth: 1.5)
                        .frame(width: max(cw * 0.7, 2), height: ch)
                        .position(x: x, y: h - ch / 2)
                }
            }
        }
    }

    private func workloadLane(width w: CGFloat) -> some View {
        let h = loadH
        let aMin = 0.6, aMax = 1.5
        let yA: (Double) -> CGFloat = { v in h - CGFloat((min(max(v, aMin), aMax) - aMin) / (aMax - aMin)) * h }
        let plotW = w - leftPad - rightPad
        return ZStack(alignment: .topLeading) {
            Rectangle().fill(Color.drip.neutral.opacity(0.12))
                .frame(width: plotW, height: yA(0.8) - yA(1.3))
                .position(x: leftPad + plotW / 2, y: (yA(0.8) + yA(1.3)) / 2)
            ForEach([0.8, 1.3], id: \.self) { v in
                Path { p in p.move(to: CGPoint(x: leftPad, y: yA(v))); p.addLine(to: CGPoint(x: w - rightPad, y: yA(v))) }
                    .stroke(Color.drip.neutral.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                Text(String(format: "%.1f", v)).font(.dripEyebrow(7)).foregroundStyle(Color.drip.textSecondary)
                    .position(x: w - rightPad + 9, y: yA(v))
            }
            Path { p in
                var started = false
                for i in days.indices where acwr.indices.contains(i) && acwr[i] > 0 {
                    let pt = CGPoint(x: colX(i, w), y: yA(acwr[i]))
                    if !started { p.move(to: pt); started = true } else { p.addLine(to: pt) }
                }
            }
            .stroke(Color.drip.textPrimary, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            if let s = selIndex, acwr.indices.contains(s), acwr[s] > 0 {
                Circle().stroke(Color.drip.textPrimary, lineWidth: 1.5)
                    .frame(width: 9, height: 9)
                    .position(x: colX(s, w), y: yA(acwr[s]))
            }
            Text("WORKLOAD").font(.dripEyebrow(7.5)).tracking(0.6).foregroundStyle(Color.drip.textTertiary)
                .position(x: leftPad + 26, y: 6)
        }
    }

    private func moodLane(width w: CGFloat) -> some View {
        let cw = colW(w)
        return ZStack(alignment: .topLeading) {
            ForEach(days.indices, id: \.self) { i in
                if let mood = days[i].mood {
                    RoundedRectangle(cornerRadius: 2).fill(moodColor(mood))
                        .opacity(selIndex == nil || selIndex == i ? 1 : 0.4)
                        .frame(width: max(cw * 0.7, 2), height: 13)
                        .position(x: colX(i, w), y: 8)
                }
                if days[i].niggles > 0 {
                    ZStack {
                        Circle().fill(Color.drip.coral).frame(width: 13, height: 13)
                        Text("\(days[i].niggles)").font(.dripStat(7)).foregroundStyle(.white)
                    }
                    .position(x: colX(i, w), y: 26)
                }
            }
            if let s = selIndex, days.indices.contains(s), days[s].mood != nil {
                RoundedRectangle(cornerRadius: 2).stroke(Color.drip.textPrimary, lineWidth: 1.5)
                    .frame(width: max(cw * 0.7, 2) + 2, height: 15)
                    .position(x: colX(s, w), y: 8)
            }
            ForEach(labelIndices, id: \.self) { i in
                Text(axisDateFormatter.string(from: days[i].date))
                    .font(.dripEyebrow(7)).foregroundStyle(Color.drip.textTertiary)
                    .position(x: colX(i, w), y: 44)
            }
        }
    }
}

// MARK: - Day detail sheet (the "workout detail" for a tapped day)

private let signalZoneNames = ["Easy", "Moderate", "Steady", "MP", "HMP", "LT", "10K", "5K", "3K", "Mile"]

private let fullDateFormatter: DateFormatter = {
    let f = DateFormatter(); f.dateFormat = "EEEE · MMM d"; return f
}()

private struct SignalDaySheet: View {
    let day: SignalDay
    /// The day's actual rows — the workout and the log. The chart holds only
    /// the shape of the day (miles per zone, mood, niggle count); the session
    /// itself and the athlete's words are fetched here (SignalDayDetail.swift).
    @State private var detail = SignalDayDetailModel()
    private func fmt(_ x: Double) -> String { String(format: "%.1f", x) }

    var body: some View {
        // Scrolls now: the sheet carries the workout receipt and the memo
        // below the fold, which a fixed VStack clipped at the .medium detent.
        ScrollView {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
        }
        .background(Color.drip.background)
        .task { await detail.load(day: day.date) }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(fullDateFormatter.string(from: day.date).uppercased())
                .font(.dripEyebrow(11)).tracking(1.2).foregroundStyle(Color.drip.coral)

            if day.comp.isEmpty {
                Text("Rest day").font(.dripDisplay(24)).foregroundStyle(Color.drip.textPrimary)
                Text("No runs logged.").font(.dripBody(14)).foregroundStyle(Color.drip.textSecondary)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(fmt(day.miles)).font(.dripDisplay(30)).foregroundStyle(Color.drip.textPrimary)
                    Text("mi").font(.dripBody(15)).foregroundStyle(Color.drip.textTertiary)
                }
                VStack(spacing: 8) {
                    ForEach(day.comp.sorted { $0.zone < $1.zone }.indices, id: \.self) { k in
                        let entry = day.comp.sorted { $0.zone < $1.zone }[k]
                        let z = min(max(entry.zone, 0), 9)
                        let pct = day.miles > 0 ? entry.mi / day.miles : 0
                        HStack(spacing: 8) {
                            Circle().fill(PaceSpectrum.stops[z]).frame(width: 9, height: 9)
                            Text(signalZoneNames[z]).font(.dripEyebrow(11)).tracking(0.6).foregroundStyle(Color.drip.textPrimary)
                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: 2).fill(Color.drip.paperDeep)
                                    .overlay(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 2).fill(PaceSpectrum.stops[z])
                                            .frame(width: geo.size.width * CGFloat(pct))
                                    }
                            }
                            .frame(height: 6)
                            Text("\(fmt(entry.mi)) mi").font(.dripStat(12)).foregroundStyle(Color.drip.textSecondary)
                        }
                    }
                }
            }

            if let mood = day.mood {
                HStack(spacing: 7) {
                    Circle().fill(moodColor(mood)).frame(width: 9, height: 9)
                    Text(mood.uppercased()).font(.dripEyebrow(11)).tracking(0.8).foregroundStyle(moodColor(mood))
                }
            }

            if day.niggles > 0 {
                VStack(alignment: .leading, spacing: 3) {
                    Text("▲ \(day.niggleLabel ?? "niggle")").font(.dripEyebrow(11)).tracking(0.6).foregroundStyle(Color.drip.coral)
                    Text("In your words — noticed, not diagnosed.").font(.dripCaption(11)).foregroundStyle(Color.drip.textTertiary)
                }
            }

            // The workout sheet and the training log for this day.
            SignalDayDetailSections(date: day.date, model: detail)
        }
    }
}

// MARK: - Spectrum key

private struct SpectrumKey: View {
    private let marks: [(String, Int)] = [("EASY", 0), ("MP", 3), ("LT", 5), ("5K", 7), ("MILE", 9)]

    var body: some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 6).fill(PaceSpectrum.gradient).frame(height: 12)
            GeometryReader { geo in
                ForEach(marks, id: \.0) { m in
                    let f = CGFloat(m.1) / 9.0
                    Text(m.0).font(.dripEyebrow(8.5)).foregroundStyle(Color.drip.textSecondary)
                        .position(x: min(max(f * geo.size.width, 14), geo.size.width - 14), y: 6)
                }
            }
            .frame(height: 13)
        }
    }
}

// MARK: - Preview (seeded, no network)

#Preview("Pace Signal") {
    let cal = Calendar.current
    let today = cal.startOfDay(for: Date())
    let sample: [SignalDay] = (0..<90).map { k in
        let d = cal.date(byAdding: .day, value: k - 89, to: today) ?? today
        let dow = k % 7
        var comp: [(zone: Int, mi: Double)] = []
        switch dow {
        case 1: comp = [(0, 2), (3, 5)]
        case 3: comp = [(0, 8)]
        case 5: comp = [(1, 13)]
        case 4: comp = []
        default: comp = [(0, 6)]
        }
        let mood = (dow == 5) ? "positive" : (dow == 1 ? "tired" : nil)
        let hasNiggle = (dow == 3 && k % 21 == 3)
        return SignalDay(date: d, comp: comp, mood: mood, niggles: hasNiggle ? 1 : 0, niggleLabel: hasNiggle ? "left calf" : nil)
    }
    let miles = sample.map { $0.miles }
    let acwr = miles.indices.map { j -> Double in
        let acute = miles[max(0, j - 6)...j].reduce(0, +)
        let cs = miles[max(0, j - 27)...j]
        let span = Double(cs.count) / 7.0
        let chronic = span > 0 ? cs.reduce(0, +) / span : 0
        return chronic > 0 ? acute / chronic : 0
    }
    var dist = Array(repeating: 0.0, count: SignalService.bucketCount)
    for (i, v) in [8, 44, 52, 40, 20, 9, 7, 12, 5, 13, 4, 6, 9, 3, 5, 3, 2, 2].enumerated() { dist[i] = Double(v) }
    return PaceSignalView(service: SignalService(previewDays: sample, acwr: acwr, dist: dist, slow: 540, fast: 360))
}
