//
//  RacePredictionViews.swift
//  RunningLog
//
//  The race-prediction track + drill-down for Trends. The overview card
//  shows the current race-anchored prediction (range + confidence) with a
//  midpoint sparkline; tapping opens the detail with a 5K/10K/HM/Marathon
//  selector and the full trend.
//
//  Data:
//    • trend (midpoint over time)  → `fitness_snapshots.predicted_*_seconds`
//    • today's range + confidence  → `athlete_state.fitness_prediction`
//      (reused via ModelOfYouState so the range math has one home)
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

    enum CodingKeys: String, CodingKey {
        case created_at
        case predicted_5k_seconds, predicted_10k_seconds
        case predicted_half_seconds, predicted_marathon_seconds
    }

    func seconds(_ d: RaceDistanceSel) -> Double? {
        switch d {
        case .fiveK: predicted_5k_seconds
        case .tenK: predicted_10k_seconds
        case .half: predicted_half_seconds
        case .marathon: predicted_marathon_seconds
        }
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
        async let snaps = fetchSnapshots()
        async let state = ModelOfYouState.fetch()
        points = (await snaps).sorted { $0.created_at < $1.created_at }
        current = (await state)?.fitness_prediction
        loaded = true
    }

    private func fetchSnapshots() async -> [FitnessSnapshotPoint] {
        do {
            return try await supabase
                .from("fitness_snapshots")
                .select("created_at,predicted_5k_seconds,predicted_10k_seconds,predicted_half_seconds,predicted_marathon_seconds")
                .order("created_at", ascending: true)
                .limit(60)
                .execute().value
        } catch {
            Log.coach.error("RacePredictionService snapshots fetch failed: \(error)")
            return []
        }
    }

    // Range + confidence for a distance (today's race-anchored prediction).
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
        let rangeStr = RaceTime.rangeText(r)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("FITNESS · RACE-ANCHORED")
                    .font(.dripEyebrow(10)).tracking(1.2)
                    .foregroundStyle(Color.drip.textSecondary)
                Spacer()
                if let tier = service.confidenceTier, rangeStr != nil {
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

            if let rangeStr {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text("~\(rangeStr)")
                        .font(.dripStat(26))
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
        var parts: [String] = []
        if let m = RaceTime.midpoint(r) { parts.append("MIDPOINT \(m)") }
        if let n = service.current?.workout_count { parts.append("\(n) SESSIONS") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
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

    // Range + confidence headline (never a bare point).
    private var headline: some View {
        let r = service.range(dist)
        let rangeStr = RaceTime.rangeText(r)
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(rangeStr.map { "~\($0)" } ?? "Not enough data yet")
                .font(.dripDisplay(rangeStr != nil ? 30 : 18))
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

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height

            // valid points, keeping original index for x positioning
            let raw = points.enumerated().compactMap { (i, p) -> (Int, Double)? in
                if let s = p.seconds(dist), s > 0 { return (i, s) } else { return nil }
            }
            guard !raw.isEmpty else {
                drawText(ctx, "Not enough snapshots yet", CGPoint(x: w / 2, y: h / 2), .center, 11, Color.drip.textTertiary)
                return
            }

            // Drop outlier snapshots (a single bad prediction otherwise crushes
            // the scale). Keep points within ±20% of the median.
            let sortedV = raw.map(\.1).sorted()
            let median = sortedV[sortedV.count / 2]
            let kept = raw.filter { $0.1 >= median * 0.80 && $0.1 <= median * 1.20 }
            let plot = kept.count >= 2 ? kept : raw

            let padL: CGFloat = 48, padR: CGFloat = 14
            let top: CGFloat = 14, bot = h - 22

            // y domain from kept points + today's range, padded
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

            // ---- Y axis: fastest (top) · mid · slowest (bottom) ----
            for v in [dMin, (dMin + dMax) / 2, dMax] {
                let yy = y(v)
                var g = Path(); g.move(to: CGPoint(x: padL, y: yy)); g.addLine(to: CGPoint(x: w - padR, y: yy))
                ctx.stroke(g, with: .color(Color.drip.divider.opacity(0.55)), lineWidth: 1)
                drawText(ctx, RaceTime.headline(v), CGPoint(x: padL - 6, y: yy), .trailing, 8.5, Color.drip.textTertiary)
            }

            // ---- today's range as a horizontal reference band ----
            if let lo = range?.low, let hi = range?.high, lo > 0, hi >= lo {
                let yTop = y(hi)   // slower bound is lower visually? hi=slower=larger sec=lower y... wait
                // lo (faster, smaller sec) -> higher (smaller y); hi (slower) -> lower (larger y)
                let bandTop = y(lo), bandBot = y(hi)
                ctx.fill(Path(CGRect(x: padL, y: bandTop, width: (w - padR) - padL, height: max(bandBot - bandTop, 2))),
                         with: .color(Color.drip.coral.opacity(0.12)))
                drawText(ctx, "TODAY", CGPoint(x: w - padR - 4, y: (bandTop + bandBot) / 2), .trailing, 8, Color.drip.coral)
                _ = yTop
            }

            // ---- midpoint line + endpoint dot ----
            var line = Path(); var started = false
            for (i, v) in plot {
                let pt = CGPoint(x: x(i), y: yc(v))
                if started { line.addLine(to: pt) } else { line.move(to: pt); started = true }
            }
            ctx.stroke(line, with: .color(Color.drip.textPrimary.opacity(0.6)), lineWidth: 1.6)
            if let last = plot.last {
                let e = CGPoint(x: x(last.0), y: yc(last.1))
                ctx.fill(Path(ellipseIn: CGRect(x: e.x - 3.4, y: e.y - 3.4, width: 6.8, height: 6.8)), with: .color(Color.drip.coral))
            }

            // ---- X axis: baseline + first / mid / last date ----
            var base = Path(); base.move(to: CGPoint(x: padL, y: bot)); base.addLine(to: CGPoint(x: w - padR, y: bot))
            ctx.stroke(base, with: .color(Color.drip.divider), lineWidth: 1)
            if let f = plot.first { drawText(ctx, points[f.0].shortDate.uppercased(), CGPoint(x: x(f.0), y: h - 4), .leading, 8.5, Color.drip.textTertiary) }
            if plot.count > 2 {
                let mIdx = plot[plot.count / 2].0
                drawText(ctx, points[mIdx].shortDate.uppercased(), CGPoint(x: x(mIdx), y: h - 4), .center, 8.5, Color.drip.textTertiary)
            }
            if let l = plot.last, plot.count > 1 { drawText(ctx, points[l.0].shortDate.uppercased(), CGPoint(x: x(l.0), y: h - 4), .trailing, 8.5, Color.drip.textTertiary) }
        }
    }

    private func drawText(_ ctx: GraphicsContext, _ s: String, _ p: CGPoint, _ anchor: UnitPoint, _ size: CGFloat, _ color: Color) {
        ctx.draw(Text(s).font(.system(size: size, weight: .medium, design: .monospaced)).foregroundColor(color), at: p, anchor: anchor)
    }
}
