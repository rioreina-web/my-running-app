//
//  RacePredictionViews.swift
//  RunningLog
//
//  The race-prediction track + drill-down for Trends. The overview card
//  shows the current race-anchored prediction (range + confidence) with a
//  midpoint sparkline; tapping opens the detail with a 5K/10K/HM/Marathon
//  selector and the full trend.
//
//  Data: ONE source — `fitness_snapshots`. The trend line and today's
//  headline/range/confidence both come from the same table, and today's
//  values come from the newest row in the very series being plotted.
//
//  This used to read the line from `fitness_snapshots` and today's range from
//  `athlete_state.fitness_prediction`. `athlete_state` is a COPY of the
//  snapshot, refreshed by a separate 04:00 cron half an hour after the 03:30
//  snapshot job — so between those two runs, or any time the rebuild failed,
//  the screen showed a stale number while the chart underneath it showed the
//  current one. On 2026-08-17 that gap put 2:37 on screen against a snapshot
//  of 2:29:13, sourced from a poisoned row that had already been deleted.
//
//  The old code hid exactly this by SNAPPING the line's final point onto the
//  athlete_state midpoint, so the two sources could never be seen disagreeing.
//  Reading one source removes both the drift and the need to paper over it.
//
//  Hard rule #7: predictions ship as a RANGE + CONFIDENCE, never a single
//  point. The headline is always the range; the line is explicitly the
//  midpoint trajectory, paired with today's range band. No bare projected
//  finish time is ever presented as "your time".
//
//  Follow-up: a goal reference line (needs the goal race time wired in).
//

import SwiftUI
import Supabase
import os

// MARK: - Distance

enum RaceDistanceSel: String, CaseIterable, Identifiable {
    case fiveK, tenK, half, marathon
    var id: String { rawValue }
    var label: String {
        switch self {
        case .fiveK: "5K"
        case .tenK: "10K"
        case .half: "HM"
        case .marathon: "Marathon"
        }
    }
    /// Key into `athlete_state.fitness_prediction.ranges`.
    var rangeKey: String {
        switch self {
        case .fiveK: "5K"
        case .tenK: "10K"
        case .half: "half"
        case .marathon: "marathon"
        }
    }
}

// MARK: - Snapshot point

struct FitnessSnapshotPoint: Decodable, Identifiable {
    let id = UUID()
    let created_at: String
    let predicted_5k_seconds: Double?
    let predicted_10k_seconds: Double?
    let predicted_half_seconds: Double?
    let predicted_marathon_seconds: Double?
    // Half-window in seconds, and the tier/among-how-many that go with it.
    // Present on every row, so today's headline is just the newest point.
    let range_5k_seconds: Double?
    let range_10k_seconds: Double?
    let range_half_seconds: Double?
    let range_marathon_seconds: Double?
    let confidence_tier: String?
    let workout_count: Int?

    enum CodingKeys: String, CodingKey {
        case created_at
        case predicted_5k_seconds, predicted_10k_seconds
        case predicted_half_seconds, predicted_marathon_seconds
        case range_5k_seconds, range_10k_seconds
        case range_half_seconds, range_marathon_seconds
        case confidence_tier, workout_count
    }

    func seconds(_ d: RaceDistanceSel) -> Double? {
        switch d {
        case .fiveK: predicted_5k_seconds
        case .tenK: predicted_10k_seconds
        case .half: predicted_half_seconds
        case .marathon: predicted_marathon_seconds
        }
    }

    /// The stored half-window for this distance.
    func halfWindow(_ d: RaceDistanceSel) -> Double? {
        switch d {
        case .fiveK: range_5k_seconds
        case .tenK: range_10k_seconds
        case .half: range_half_seconds
        case .marathon: range_marathon_seconds
        }
    }

    /// This row's prediction for `d` as a range. `point` is the stored
    /// prediction itself, so the band is always centred on the plotted line —
    /// they are the same number, not two derivations of it.
    func range(_ d: RaceDistanceSel) -> ModelOfYouState.RaceRange? {
        guard let point = seconds(d), point > 0 else { return nil }
        let half = max(halfWindow(d) ?? 0, 0)
        return ModelOfYouState.RaceRange(low: point - half, high: point + half, point: point)
    }

    /// "Jun 12" from the leading yyyy-MM-dd of the timestamp.
    var shortDate: String {
        let day = String(created_at.prefix(10))
        let inF = DateFormatter(); inF.locale = Locale(identifier: "en_US_POSIX"); inF.dateFormat = "yyyy-MM-dd"
        guard let d = inF.date(from: day) else { return day }
        let outF = DateFormatter(); outF.locale = Locale(identifier: "en_US_POSIX"); outF.dateFormat = "MMM d"
        return outF.string(from: d)
    }
}

// MARK: - Service

@Observable
final class RacePredictionService {
    static let shared = RacePredictionService()

    private(set) var points: [FitnessSnapshotPoint] = []
    private(set) var current: ModelOfYouState.FitnessPrediction?
    private(set) var loaded = false
    private(set) var isLoading = false

    private init() {}
    init(previewPoints: [FitnessSnapshotPoint], current: ModelOfYouState.FitnessPrediction?) {
        self.points = previewPoints
        self.current = current
        self.loaded = true
    }

    @MainActor
    func refresh(force: Bool = false) async {
        if loaded && !force { return }
        isLoading = true
        defer { isLoading = false }
        points = (await fetchSnapshots()).sorted { $0.created_at < $1.created_at }
        // Today's headline IS the newest plotted point — no second fetch, so
        // no second opinion. `athlete_state.fitness_prediction` used to supply
        // this; it is a copy on a later cron and could be hours stale.
        current = points.last.map { newest in
            ModelOfYouState.FitnessPrediction(
                ranges: Dictionary(uniqueKeysWithValues: RaceDistanceSel.allCases.compactMap { d in
                    newest.range(d).map { (d.rangeKey, $0) }
                }),
                confidence_tier: newest.confidence_tier,
                workout_count: newest.workout_count
            )
        }
        loaded = true
    }

    private func fetchSnapshots() async -> [FitnessSnapshotPoint] {
        do {
            return try await supabase
                .from("fitness_snapshots")
                .select(
                    """
                    created_at,\
                    predicted_5k_seconds,predicted_10k_seconds,\
                    predicted_half_seconds,predicted_marathon_seconds,\
                    range_5k_seconds,range_10k_seconds,\
                    range_half_seconds,range_marathon_seconds,\
                    confidence_tier,workout_count
                    """
                )
                .order("created_at", ascending: true)
                .limit(60)
                .execute().value
        } catch {
            Log.coach.error("RacePredictionService snapshots fetch failed: \(error)")
            return []
        }
    }

    // Range + confidence for a distance, from the newest snapshot.
    func range(_ d: RaceDistanceSel) -> ModelOfYouState.RaceRange? { current?.ranges?[d.rangeKey] }
    var confidenceTier: String? { current?.confidence_tier }
}

// MARK: - Time format

enum RaceTime {
    static func clock(_ seconds: Double) -> String { ModelOfYouState.RaceRange.hms(seconds) }

    /// Display time: hour+ races round to whole minutes (h:mm) — the seconds
    /// are a math artifact, not signal (marathon-prediction-honesty). Sub-hour
    /// races keep m:ss.
    static func headline(_ seconds: Double) -> String {
        if seconds >= 3600 {
            let t = Int((seconds / 60).rounded()) * 60
            return "\(t / 3600):\(String(format: "%02d", (t % 3600) / 60))"
        }
        return ModelOfYouState.RaceRange.hms(seconds)
    }

    /// "2:28–2:31" using the headline formatter; nil when there's no low bound.
    static func rangeText(_ r: ModelOfYouState.RaceRange?) -> String? {
        guard let r, let lo = r.low, lo > 0 else { return nil }
        let hi = r.high ?? lo
        let loS = headline(lo), hiS = headline(hi)
        return loS == hiS ? loS : "\(loS)–\(hiS)"
    }

    static func midpoint(_ r: ModelOfYouState.RaceRange?) -> String? {
        guard let r, let lo = r.low, lo > 0 else { return nil }
        let hi = r.high ?? lo
        return headline(r.point ?? (lo + hi) / 2)
    }

    /// Absolute gap as "M:SS" (for the trend delta).
    static func gap(_ seconds: Double) -> String {
        let t = Int(abs(seconds).rounded())
        return "\(t / 60):\(String(format: "%02d", t % 60))"
    }
}

// MARK: - Overview track card

struct RacePredictionTrack: View {
    @State private var service = RacePredictionService.shared

    var body: some View {
        NavigationLink {
            RacePredictionDetailView(service: service)
        } label: {
            card
        }
        .buttonStyle(.plain)
        .task { await service.refresh() }
    }

    private var card: some View {
        let r = service.range(.marathon)
        let raw = service.points.compactMap { $0.seconds(.marathon) }
        let clean = RaceSparkline.cleaned(raw)
        // One number, not a range (2026-07-18): the confidence-scaled band read
        // as "too wide / inaccurate" — worse than a single honest estimate. We
        // show the midpoint as the projection; the confidence tag carries the
        // certainty, and the modal still shows each distance's lifetime PR for
        // the demonstrated mark next to the modeled one.
        let midStr = RaceTime.midpoint(r)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("FITNESS · RACE-ANCHORED")
                    .font(.dripEyebrow(10)).tracking(1.2)
                    .foregroundStyle(Color.drip.textSecondary)
                Spacer()
                if let tier = service.confidenceTier, midStr != nil {
                    Text("\(tier.uppercased()) CONF")
                        .font(.dripEyebrow(8.5)).tracking(0.6)
                        .foregroundStyle(Color.drip.energized)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.drip.energized.opacity(0.12))
                        .clipShape(Capsule())
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.drip.textTertiary)
            }

            if let midStr {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(midStr)
                        .font(.dripStat(30))
                        .foregroundStyle(Color.drip.textPrimary)
                    Text("marathon").font(.dripBody(13)).foregroundStyle(Color.drip.textSecondary)
                }
                if let cap = captionLine(r) {
                    Text(cap).font(.dripEyebrow(9)).tracking(0.6)
                        .foregroundStyle(Color.drip.textTertiary)
                }
                RaceSparkline(values: raw).frame(height: 34)
                HStack {
                    if clean.count >= 2 {
                        Text("LAST \(clean.count) READS")
                            .font(.dripEyebrow(9)).tracking(0.8)
                            .foregroundStyle(Color.drip.textTertiary)
                    }
                    Spacer()
                    if let d = deltaLine(clean) {
                        Text(d).font(.dripEyebrow(9)).tracking(0.6)
                            .foregroundStyle(Color.drip.textSecondary)
                    }
                }
            } else {
                Text("Not enough race history yet — a few more quality sessions and this fills in.")
                    .font(.dripBody(14)).foregroundStyle(Color.drip.textSecondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
    }

    private func captionLine(_ r: ModelOfYouState.RaceRange?) -> String? {
        // Midpoint is now the headline, so it's dropped from the caption.
        guard let n = service.current?.workout_count else { return nil }
        return "\(n) SESSIONS"
    }

    private func deltaLine(_ vals: [Double]) -> String? {
        guard let f = vals.first, let l = vals.last, vals.count >= 2 else { return nil }
        let d = l - f
        if abs(d) < 2 { return "HOLDING STEADY" }
        return d < 0 ? "↓ \(RaceTime.gap(d)) FASTER" : "↑ \(RaceTime.gap(d)) SLOWER"
    }
}

private struct RaceSparkline: View {
    let values: [Double]

    /// Positive values with ±20%-of-median outliers removed, so one bad
    /// fitness snapshot doesn't spike the sparkline.
    static func cleaned(_ v: [Double]) -> [Double] {
        let pos = v.filter { $0 > 0 }
        guard pos.count >= 3 else { return pos }
        let s = pos.sorted(); let med = s[s.count / 2]
        return pos.filter { $0 >= med * 0.80 && $0 <= med * 1.20 }
    }

    var body: some View {
        Canvas { ctx, size in
            let vals = RaceSparkline.cleaned(values)
            guard vals.count >= 2 else { return }
            let w = size.width, h = size.height
            let mn = vals.min()!, mx = vals.max()!
            let span = max(mx - mn, 1)
            func pt(_ i: Int) -> CGPoint {
                let x = CGFloat(i) / CGFloat(vals.count - 1) * w
                let y = h - CGFloat((mx - vals[i]) / span) * (h - 8) - 4 // faster(low)=higher
                return CGPoint(x: x, y: y)
            }
            // faint coral-wash area
            var area = Path(); area.move(to: CGPoint(x: 0, y: h))
            for i in 0..<vals.count { area.addLine(to: pt(i)) }
            area.addLine(to: CGPoint(x: w, y: h)); area.closeSubpath()
            ctx.fill(area, with: .color(Color.drip.coral.opacity(0.10)))
            // line + endpoint dot
            var p = Path(); p.move(to: pt(0)); for i in 1..<vals.count { p.addLine(to: pt(i)) }
            ctx.stroke(p, with: .color(Color.drip.coral.opacity(0.8)), lineWidth: 1.6)
            let e = pt(vals.count - 1)
            ctx.fill(Path(ellipseIn: CGRect(x: e.x - 3, y: e.y - 3, width: 6, height: 6)), with: .color(Color.drip.coral))
        }
    }
}

// MARK: - Detail

struct RacePredictionDetailView: View {
    @State var service: RacePredictionService
    @State private var dist: RaceDistanceSel = .marathon

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("FITNESS · RACE-ANCHORED")
                        .font(.dripEyebrow(11)).tracking(1.3)
                        .foregroundStyle(Color.drip.coral)
                    Text("Where the fitness points.")
                        .font(.dripDisplay(26))
                        .foregroundStyle(Color.drip.textPrimary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                selector.padding(.top, 14)

                headline.padding(.top, 16)

                RacePredictionChart(points: service.points, dist: dist, range: service.range(dist))
                    .frame(height: 180)
                    .padding(.top, 10)

                Text("The line is your predicted \(dist.label) midpoint over time; the coral band is today's range. Anchored to your real race history, not your goal.")
                    .font(.dripBody(14)).lineSpacing(3)
                    .foregroundStyle(Color.drip.textSecondary)
                    .padding(.top, 14)

                if let n = service.current?.workout_count {
                    Text("\(n) sessions behind the estimate")
                        .font(.dripEyebrow(10)).tracking(0.8)
                        .foregroundStyle(Color.drip.textTertiary)
                        .padding(.top, 10)
                }
            }
            .padding(20)
        }
        .background(Color.drip.background.ignoresSafeArea())
        .navigationTitle("Trends")
        .navigationBarTitleDisplayMode(.inline)
        .task { await service.refresh() }
    }

    private var selector: some View {
        HStack(spacing: 2) {
            ForEach(RaceDistanceSel.allCases) { d in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { dist = d }
                } label: {
                    Text(d.label.uppercased())
                        .font(.dripEyebrow(10)).tracking(0.6)
                        .fontWeight(dist == d ? .semibold : .regular)
                        .foregroundStyle(dist == d ? Color.drip.textPrimary : Color.drip.textSecondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 7)
                        .background(dist == d ? Color.drip.cardBackground : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.drip.paperDeep)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // Single projected time + confidence tag (2026-07-18: ranges retired —
    // one honest number reads better than a wide band).
    private var headline: some View {
        let r = service.range(dist)
        let midStr = RaceTime.midpoint(r)
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(midStr ?? "Not enough data yet")
                .font(.dripDisplay(midStr != nil ? 30 : 18))
                .foregroundStyle(Color.drip.textPrimary)
            Text(dist.label).font(.dripBody(13)).foregroundStyle(Color.drip.textSecondary)
            Spacer()
            if let tier = service.confidenceTier {
                Text("\(tier.uppercased()) CONF")
                    .font(.dripEyebrow(9)).tracking(0.6)
                    .foregroundStyle(Color.drip.energized)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.drip.energized.opacity(0.14))
                    .clipShape(Capsule())
            }
        }
    }
}

private struct RacePredictionChart: View {
    let points: [FitnessSnapshotPoint]
    let dist: RaceDistanceSel
    let range: ModelOfYouState.RaceRange?

    /// Index into `Geo.plotted` currently under the athlete's finger, or nil
    /// when the chart isn't being scrubbed.
    @State private var scrubIndex: Int?

    var body: some View {
        GeometryReader { geo in
            let g = geometry(in: geo.size)
            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in draw(ctx, g, scrub: scrubIndex) }
                if let i = scrubIndex, g.plotted.indices.contains(i) {
                    callout(g.plotted[i], topY: g.top, width: geo.size.width)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in scrubIndex = g.nearestIndex(toX: v.location.x) }
                    .onEnded { _ in scrubIndex = nil }
            )
        }
        // Clear the scrubber when the athlete switches distance so the
        // callout doesn't read a stale point from the previous series.
        .onChange(of: dist) { _, _ in scrubIndex = nil }
    }

    // MARK: - Geometry

    /// Everything both the Canvas draw pass and the scrub gesture need,
    /// computed once per layout from `size`.
    ///
    /// The final ("today") trajectory point is snapped to today's official
    /// range midpoint. The line comes from `fitness_snapshots` while the
    /// coral band comes from `athlete_state` — two different sources — so a
    /// divergent last snapshot would otherwise float the endpoint outside
    /// the band. Snapping keeps the line, endpoint dot, and band in agreement
    /// (and honours hard rule #7: the band, a range, stays the honest signal).
    private func geometry(in size: CGSize) -> Geo {
        let w = size.width, h = size.height
        let padL: CGFloat = 48, padR: CGFloat = 14
        let top: CGFloat = 14, bot = h - 22

        // valid points, keeping original index for x positioning
        let raw = points.enumerated().compactMap { (i, p) -> (Int, Double)? in
            if let s = p.seconds(dist), s > 0 { return (i, s) } else { return nil }
        }
        guard !raw.isEmpty else {
            return Geo(w: w, h: h, padL: padL, padR: padR, top: top, bot: bot,
                       plotted: [], band: nil, yTicks: [], xLabels: [], empty: true)
        }

        // Drop outlier snapshots (a single bad prediction otherwise crushes
        // the scale). Keep points within ±20% of the median — but ALWAYS keep
        // the newest, because it is the number in the headline and the centre
        // of the band. Exempting it is what lets the snap-to-midpoint hack go:
        // the endpoint lands in the band because it IS the band's centre, not
        // because it was moved there.
        let sortedV = raw.map(\.1).sorted()
        let median = sortedV[sortedV.count / 2]
        let newestIndex = raw.last!.0
        let kept = raw.filter {
            $0.0 == newestIndex || ($0.1 >= median * 0.80 && $0.1 <= median * 1.20)
        }
        let plot = kept.count >= 2 ? kept : raw

        // y domain from plotted points + today's range, padded
        var vals = plot.map(\.1)
        if let lo = range?.low, lo > 0 { vals.append(lo) }
        if let hi = range?.high, hi > 0 { vals.append(hi) }
        let dMin = vals.min()!, dMax = vals.max()!
        let pad = max((dMax - dMin) * 0.12, 4)
        let mn = dMin - pad, mx = dMax + pad
        let span = max(mx - mn, 1)
        func y(_ v: Double) -> CGFloat { top + CGFloat((v - mn) / span) * (bot - top) } // faster(low)=top
        func yc(_ v: Double) -> CGFloat { y(min(max(v, mn), mx)) }
        let n = max(points.count, 1)
        func x(_ i: Int) -> CGFloat { padL + (w - padL - padR) * CGFloat(i) / CGFloat(max(n - 1, 1)) }

        let plotted: [Geo.Plotted] = plot.map { (i, v) in
            Geo.Plotted(
                x: x(i), y: yc(v), seconds: v,
                dateLabel: i == newestIndex ? "TODAY" : points[i].shortDate.uppercased(),
                isToday: i == newestIndex
            )
        }

        var band: Geo.Band?
        if let lo = range?.low, let hi = range?.high, lo > 0, hi >= lo {
            // lo (faster, smaller sec) -> higher (smaller y); hi (slower) -> lower.
            band = Geo.Band(top: y(lo), bot: y(hi))
        }

        let yTicks: [(CGFloat, String)] = [dMin, (dMin + dMax) / 2, dMax].map { (y($0), RaceTime.headline($0)) }

        var xLabels: [(CGFloat, String, UnitPoint)] = []
        if let f = plot.first { xLabels.append((x(f.0), points[f.0].shortDate.uppercased(), .leading)) }
        if plot.count > 2 {
            let mIdx = plot[plot.count / 2].0
            xLabels.append((x(mIdx), points[mIdx].shortDate.uppercased(), .center))
        }
        if let l = plot.last, plot.count > 1 { xLabels.append((x(l.0), points[l.0].shortDate.uppercased(), .trailing)) }

        return Geo(w: w, h: h, padL: padL, padR: padR, top: top, bot: bot,
                   plotted: plotted, band: band, yTicks: yTicks, xLabels: xLabels, empty: false)
    }

    // MARK: - Draw

    private func draw(_ ctx: GraphicsContext, _ g: Geo, scrub: Int?) {
        guard !g.empty else {
            drawText(ctx, "Not enough snapshots yet", CGPoint(x: g.w / 2, y: g.h / 2), .center, 11, Color.drip.textTertiary)
            return
        }

        // ---- Y axis: fastest (top) · mid · slowest (bottom) ----
        for (yy, label) in g.yTicks {
            var grid = Path(); grid.move(to: CGPoint(x: g.padL, y: yy)); grid.addLine(to: CGPoint(x: g.w - g.padR, y: yy))
            ctx.stroke(grid, with: .color(Color.drip.divider.opacity(0.55)), lineWidth: 1)
            drawText(ctx, label, CGPoint(x: g.padL - 6, y: yy), .trailing, 8.5, Color.drip.textTertiary)
        }

        // ---- today's range as a horizontal reference band ----
        if let band = g.band {
            ctx.fill(
                Path(CGRect(x: g.padL, y: band.top, width: (g.w - g.padR) - g.padL, height: max(band.bot - band.top, 2))),
                with: .color(Color.drip.coral.opacity(0.12))
            )
            drawText(ctx, "TODAY", CGPoint(x: g.w - g.padR - 4, y: (band.top + band.bot) / 2), .trailing, 8, Color.drip.coral)
        }

        // ---- midpoint line + endpoint dot ----
        var line = Path(); var started = false
        for p in g.plotted {
            let pt = CGPoint(x: p.x, y: p.y)
            if started { line.addLine(to: pt) } else { line.move(to: pt); started = true }
        }
        ctx.stroke(line, with: .color(Color.drip.textPrimary.opacity(0.6)), lineWidth: 1.6)
        if let e = g.plotted.last {
            ctx.fill(Path(ellipseIn: CGRect(x: e.x - 3.4, y: e.y - 3.4, width: 6.8, height: 6.8)), with: .color(Color.drip.coral))
        }

        // ---- X axis: baseline + first / mid / last date ----
        var base = Path(); base.move(to: CGPoint(x: g.padL, y: g.bot)); base.addLine(to: CGPoint(x: g.w - g.padR, y: g.bot))
        ctx.stroke(base, with: .color(Color.drip.divider), lineWidth: 1)
        for (xx, label, anchor) in g.xLabels {
            drawText(ctx, label, CGPoint(x: xx, y: g.h - 4), anchor, 8.5, Color.drip.textTertiary)
        }

        // ---- scrubber: dashed guide + haloed point (on top) ----
        if let si = scrub, g.plotted.indices.contains(si) {
            let p = g.plotted[si]
            var guide = Path(); guide.move(to: CGPoint(x: p.x, y: g.top)); guide.addLine(to: CGPoint(x: p.x, y: g.bot))
            ctx.stroke(guide, with: .color(Color.drip.textTertiary.opacity(0.45)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - 7, y: p.y - 7, width: 14, height: 14)), with: .color(Color.drip.background))
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - 4.5, y: p.y - 4.5, width: 9, height: 9)), with: .color(Color.drip.coral))
        }
    }

    private func drawText(_ ctx: GraphicsContext, _ s: String, _ p: CGPoint, _ anchor: UnitPoint, _ size: CGFloat, _ color: Color) {
        ctx.draw(Text(s).font(.system(size: size, weight: .medium, design: .monospaced)).foregroundColor(color), at: p, anchor: anchor)
    }

    // MARK: - Scrubber callout

    /// Floating read-out pinned near the top of the chart, tracking the scrub
    /// x. Historical points show their midpoint time; the snapped "today"
    /// point shows the full range (never a bare point — hard rule #7).
    @ViewBuilder
    private func callout(_ p: Geo.Plotted, topY: CGFloat, width: CGFloat) -> some View {
        let calloutW: CGFloat = 132
        let clampedX = min(max(p.x, calloutW / 2 + 2), width - calloutW / 2 - 2)
        VStack(spacing: 3) {
            Text(p.dateLabel)
                .font(.dripEyebrow(8.5)).tracking(0.8)
                .foregroundStyle(p.isToday ? Color.drip.coral : Color.drip.textTertiary)
            Text(calloutTime(p))
                .font(.dripStat(15))
                .foregroundStyle(Color.drip.textPrimary)
            Text(p.isToday ? "\(dist.label) · today's range" : "\(dist.label) midpoint")
                .font(.dripEyebrow(7.5)).tracking(0.4)
                .foregroundStyle(Color.drip.textTertiary)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .frame(width: calloutW)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color.drip.cardBackground)
                .shadow(color: .black.opacity(0.14), radius: 6, x: 0, y: 2)
        )
        .position(x: clampedX, y: topY + 20)
    }

    private func calloutTime(_ p: Geo.Plotted) -> String {
        if p.isToday, let rt = RaceTime.rangeText(range) { return "~\(rt)" }
        return RaceTime.headline(p.seconds)
    }

    // MARK: - Geometry model

    private struct Geo {
        let w: CGFloat, h: CGFloat
        let padL: CGFloat, padR: CGFloat
        let top: CGFloat, bot: CGFloat
        let plotted: [Plotted]
        let band: Band?
        let yTicks: [(CGFloat, String)]
        let xLabels: [(CGFloat, String, UnitPoint)]
        let empty: Bool

        struct Plotted {
            let x: CGFloat
            let y: CGFloat
            let seconds: Double
            let dateLabel: String
            let isToday: Bool
        }

        struct Band { let top: CGFloat; let bot: CGFloat }

        /// Plotted-array index whose x is closest to a touch x.
        func nearestIndex(toX xt: CGFloat) -> Int? {
            guard !plotted.isEmpty else { return nil }
            var best = 0
            var bestD = CGFloat.greatestFiniteMagnitude
            for (i, p) in plotted.enumerated() {
                let d = abs(p.x - xt)
                if d < bestD { bestD = d; best = i }
            }
            return best
        }
    }
}
