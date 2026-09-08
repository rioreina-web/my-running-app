//
//  WorkoutReceiptCharts.swift
//  RunningLog
//
//  Hand-drawn (GeometryReader / Path) chart kit for the dense "Rep Receipt"
//  workout detail (Direction A of the Workout Detail Redesign). No chart
//  dependency. All charts read the Post Run Drip tokens (Color.drip / Font.drip)
//  and the per-second Strava streams already loaded via ExternalStreamAdapter.
//
//  Charts here:
//    • RRRepBars         — hero rep chart: width ∝ distance, height ∝ speed,
//                          avg-HR line riding the tops, target dashed refs,
//                          rest gaps to scale.
//    • RRZoneTimeline    — HR over the full session, zone bands, rep windows.
//    • RRPaceTrace       — smoothed pace/velocity trace, rep windows shaded.
//    • RRCadenceStrip    — cadence over time + avg line.
//    • RRElevationGrade  — elevation area, grade-tinted columns.
//    • RRRecoveryRow     — small-multiples HR drop in each post-rep rest.
//    • RRZoneBar         — stacked time-in-HR-zone bar + legend grid.
//    • RRRouteShape      — route line colored by work/easy (or HR zone) + rep pins.
//
//  Shared models + helpers (rr_*) at the bottom are used by both this file
//  and WorkoutRepReceiptView.swift.
//

import SwiftUI
import CoreLocation

// MARK: - Shared models

/// One work rep distilled for the receipt charts.
struct RRRep: Identifiable {
    let id: Int          // rep number (1-based)
    let label: String    // "2K" / "1K" / "1mi"
    let distMi: Double
    let paceSec: Double   // sec/mi
    let hr: Int?
    let cad: Int?
    let restSec: Int?     // rest that FOLLOWS this rep (nil for last)
    let adjPaceSec: Double? // heat-adjusted pace, sec/mi (nil if none)
}

/// A work-rep time window inside the stream, for shading the timelines.
struct RRWindow: Identifiable { let id: Int; let start: Double; let end: Double }

/// HR drop in the rest after one rep.
struct RRRecovery: Identifiable { let id: Int; let drop: Int; let endHR: Int; let pts: [Int] }

/// An HR zone band.
struct RRZone: Identifiable { let id: String; let lo: Int; let hi: Int; let color: Color }

// MARK: - 1 · Hero rep bars

struct RRRepBars: View {
    let reps: [RRRep]
    let targetSec: Double
    let colorByZone: Bool
    let heatOn: Bool
    let km: Bool
    let zones: [RRZone]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let padL: CGFloat = 30, padR: CGFloat = 8, padT: CGFloat = 28, padB: CGFloat = 34
            let plotW = w - padL - padR, plotH = h - padT - padB

            // lay reps + rests along x by duration so widths read as distance/time
            let items = rr_layItems(reps: reps)
            let totalDur = max(items.reduce(0) { $0 + $1.dur }, 1)

            // pace scale (faster → taller); clamp to a tight work window
            let paces = reps.map { $0.paceSec }
            let pMin = (paces.min() ?? 300) - 8
            let pMax = (paces.max() ?? 340) + 8
            let barH: (Double) -> CGFloat = { p in
                let f = (pMax - p) / max(pMax - pMin, 1)
                return CGFloat(f) * (plotH - 26) + 22
            }
            // HR scale (upper band)
            let hrs = reps.compactMap { $0.hr }.map(Double.init)
            let hMin = (hrs.min() ?? 150) - 6
            let hMax = (hrs.max() ?? 180) + 6
            let yHR: (Double) -> CGFloat = { v in
                padT + (1 - CGFloat((v - hMin) / max(hMax - hMin, 1))) * (plotH * 0.7)
            }
            let fastest = paces.min() ?? 0

            ZStack(alignment: .topLeading) {
                // target reference lines
                ForEach([targetSec - 6, targetSec, targetSec + 6], id: \.self) { p in
                    let y = padT + plotH - barH(p)
                    Path { pa in pa.move(to: .init(x: padL, y: y)); pa.addLine(to: .init(x: padL + plotW, y: y)) }
                        .stroke(Color.drip.divider, style: StrokeStyle(lineWidth: 0.6, dash: [2, 3]))
                    Text(rr_pace(p, km: km))
                        .font(.dripStat(7.5)).foregroundStyle(Color.drip.textTertiary)
                        .position(x: padL - 13, y: y)
                }
                // baseline
                Path { p in p.move(to: .init(x: padL, y: padT + plotH)); p.addLine(to: .init(x: padL + plotW, y: padT + plotH)) }
                    .stroke(Color.drip.divider, lineWidth: 0.8)

                // rest gaps
                ForEach(Array(items.enumerated()), id: \.offset) { _, it in
                    if it.isRest {
                        let x = padL + CGFloat(it.x0 / totalDur) * plotW
                        let bw = CGFloat(it.dur / totalDur) * plotW
                        Rectangle().fill(Color.drip.textTertiary.opacity(0.06))
                            .frame(width: bw, height: plotH).position(x: x + bw / 2, y: padT + plotH / 2)
                        Text("\(Int(it.dur))s").font(.dripStat(7)).foregroundStyle(Color.drip.textTertiary)
                            .position(x: x + bw / 2, y: padT + plotH + 10)
                    }
                }
                // rep bars
                ForEach(reps) { r in
                    let it = items.first { !$0.isRest && $0.rep == r.id }!
                    let x = padL + CGFloat(it.x0 / totalDur) * plotW
                    let bw = CGFloat(it.dur / totalDur) * plotW
                    let bh = barH(heatOn ? (r.adjPaceSec ?? r.paceSec) : r.paceSec)
                    let isFast = r.paceSec == fastest
                    let col = colorByZone ? rr_zoneColor(r.hr, zones) : (isFast ? Color.drip.coral : Color.drip.textSecondary)
                    Rectangle().fill(col).opacity(colorByZone ? 0.9 : (isFast ? 1 : 0.82))
                        .frame(width: max(bw - 3, 1), height: bh)
                        .position(x: x + bw / 2, y: padT + plotH - bh / 2)
                    Text(rr_pace(heatOn ? (r.adjPaceSec ?? r.paceSec) : r.paceSec, km: km))
                        .font(.dripStat(10)).foregroundStyle(colorByZone ? Color.drip.textPrimary : col)
                        .position(x: x + bw / 2, y: padT + plotH - bh - 7)
                    Text(r.label).font(.dripStat(8)).foregroundStyle(Color.drip.textPrimary)
                        .position(x: x + bw / 2, y: padT + plotH + 11)
                    Text(rr_dist(r.distMi, km: km)).font(.dripStat(7)).foregroundStyle(Color.drip.textTertiary)
                        .position(x: x + bw / 2, y: padT + plotH + 21)
                }
                // HR line riding the bars
                if hrs.count >= 2 {
                    Path { path in
                        var started = false
                        for r in reps {
                            guard let hr = r.hr else { continue }
                            let it = items.first { !$0.isRest && $0.rep == r.id }!
                            let x = padL + CGFloat((it.x0 + it.dur / 2) / totalDur) * plotW
                            let pt = CGPoint(x: x, y: yHR(Double(hr)))
                            if !started { path.move(to: pt); started = true } else { path.addLine(to: pt) }
                        }
                    }
                    .stroke(Color.drip.textPrimary.opacity(0.85), lineWidth: 1.4)
                    ForEach(reps) { r in
                        if let hr = r.hr {
                            let it = items.first { !$0.isRest && $0.rep == r.id }!
                            let x = padL + CGFloat((it.x0 + it.dur / 2) / totalDur) * plotW
                            Circle().fill(Color.drip.background).overlay(Circle().stroke(Color.drip.textPrimary, lineWidth: 1.2))
                                .frame(width: 5.5, height: 5.5).position(x: x, y: yHR(Double(hr)))
                            Text("\(hr)").font(.dripStat(7)).foregroundStyle(Color.drip.textSecondary)
                                .position(x: x, y: yHR(Double(hr)) - 8)
                        }
                    }
                }
                // legend
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 1).fill(Color.drip.coral).frame(width: 9, height: 9)
                    Text("REP PACE · TALLER = FASTER").font(.dripStat(8)).foregroundStyle(Color.drip.textSecondary)
                    Circle().stroke(Color.drip.textPrimary, lineWidth: 1.2).frame(width: 6, height: 6).padding(.leading, 4)
                    Text("AVG HR").font(.dripStat(8)).foregroundStyle(Color.drip.textSecondary)
                }
                .position(x: padL + 110, y: 8)
            }
        }
        .frame(height: 236)
    }
}

// MARK: - 2 · HR zone timeline

struct RRZoneTimeline: View {
    let times: [Double]
    let hr: [Double]
    let windows: [RRWindow]
    let zones: [RRZone]
    var height: CGFloat = 150

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let padL: CGFloat = 26, padR: CGFloat = 6, padT: CGFloat = 8, padB: CGFloat = 14
            let plotW = w - padL - padR, plotH = h - padT - padB
            let total = max(times.last ?? 1, 1)
            let yMin = 90.0, yMax = 185.0
            let x: (Double) -> CGFloat = { padL + CGFloat($0 / total) * plotW }
            let y: (Double) -> CGFloat = { padT + plotH - CGFloat(($0 - yMin) / (yMax - yMin)) * plotH }

            ZStack(alignment: .topLeading) {
                ForEach(zones) { z in
                    let top = y(min(Double(z.hi), yMax)), bot = y(max(Double(z.lo), yMin))
                    if bot > top {
                        Rectangle().fill(z.color.opacity(0.09))
                            .frame(width: plotW, height: bot - top).position(x: padL + plotW / 2, y: (top + bot) / 2)
                    }
                }
                ForEach(windows) { win in
                    let x0 = x(win.start), x1 = x(win.end)
                    Rectangle().fill(Color.drip.coral.opacity(0.07))
                        .frame(width: max(x1 - x0, 1), height: plotH).position(x: (x0 + x1) / 2, y: padT + plotH / 2)
                }
                ForEach([120, 150, 175], id: \.self) { v in
                    Text("\(v)").font(.dripStat(7.5)).foregroundStyle(Color.drip.textTertiary)
                        .position(x: padL - 11, y: y(Double(v)))
                }
                Path { p in
                    for (i, t) in times.enumerated() where i < hr.count {
                        let pt = CGPoint(x: x(t), y: y(hr[i]))
                        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                    }
                }
                .stroke(Color.drip.textPrimary.opacity(0.85), lineWidth: 1.1)
            }
        }
        .frame(height: height)
    }
}

// MARK: - 3 · Pace trace

struct RRPaceTrace: View {
    let times: [Double]
    let paceSec: [Double]   // sec/mi
    let windows: [RRWindow]
    let km: Bool
    var height: CGFloat = 120

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let padL: CGFloat = 30, padR: CGFloat = 6, padT: CGFloat = 8, padB: CGFloat = 14
            let plotW = w - padL - padR, plotH = h - padT - padB
            let total = max(times.last ?? 1, 1)
            let pmin = 280.0, pmax = 640.0
            let x: (Double) -> CGFloat = { padL + CGFloat($0 / total) * plotW }
            let y: (Double) -> CGFloat = { padT + CGFloat(($0 - pmin) / (pmax - pmin)) * plotH }
            // light smoothing
            let sm = rr_smooth(paceSec, win: 3)

            ZStack(alignment: .topLeading) {
                ForEach([330.0, 420.0, 540.0], id: \.self) { v in
                    Path { p in p.move(to: .init(x: padL, y: y(v))); p.addLine(to: .init(x: padL + plotW, y: y(v))) }
                        .stroke(Color.drip.divider, lineWidth: 0.4)
                    Text(rr_pace(v, km: km)).font(.dripStat(7.5)).foregroundStyle(Color.drip.textTertiary)
                        .position(x: padL - 12, y: y(v))
                }
                ForEach(windows) { win in
                    let x0 = x(win.start), x1 = x(win.end)
                    Rectangle().fill(Color.drip.coral.opacity(0.07))
                        .frame(width: max(x1 - x0, 1), height: plotH).position(x: (x0 + x1) / 2, y: padT + plotH / 2)
                }
                Path { p in
                    for (i, t) in times.enumerated() where i < sm.count {
                        let pt = CGPoint(x: x(t), y: y(sm[i]))
                        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                    }
                }
                .stroke(Color.drip.coral, lineWidth: 1.2)
            }
        }
        .frame(height: height)
    }
}

// MARK: - 4 · Cadence strip

struct RRCadenceStrip: View {
    let times: [Double]
    let cadence: [Double]   // spm
    var height: CGFloat = 70

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let padL: CGFloat = 26, padR: CGFloat = 6, pad: CGFloat = 8
            let plotW = w - padL - padR, plotH = h - pad * 2
            let total = max(times.last ?? 1, 1)
            let lo = 150.0, hi = 200.0
            let x: (Double) -> CGFloat = { padL + CGFloat($0 / total) * plotW }
            let y: (Double) -> CGFloat = { pad + plotH - CGFloat(($0 - lo) / (hi - lo)) * plotH }
            let avg = cadence.isEmpty ? 0 : cadence.reduce(0, +) / Double(cadence.count)
            ZStack(alignment: .topLeading) {
                Path { p in p.move(to: .init(x: padL, y: y(avg))); p.addLine(to: .init(x: padL + plotW, y: y(avg))) }
                    .stroke(Color.drip.textSecondary.opacity(0.5), style: StrokeStyle(lineWidth: 0.6, dash: [3, 3]))
                Path { p in
                    for (i, t) in times.enumerated() where i < cadence.count {
                        let pt = CGPoint(x: x(t), y: y(cadence[i]))
                        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                    }
                }
                .stroke(Color.drip.textSecondary.opacity(0.8), lineWidth: 1)
                Text("AVG \(Int(avg)) SPM").font(.dripStat(7.5)).foregroundStyle(Color.drip.textSecondary)
                    .position(x: padL + plotW - 34, y: pad + 6)
            }
        }
        .frame(height: height)
    }
}

// MARK: - 5 · Elevation + grade

struct RRElevationGrade: View {
    let times: [Double]
    let altFt: [Double]
    let grade: [Double]   // %
    var height: CGFloat = 88

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let padL: CGFloat = 26, padR: CGFloat = 6, padT: CGFloat = 8, padB: CGFloat = 8
            let plotW = w - padL - padR, plotH = h - padT - padB
            let total = max(times.last ?? 1, 1)
            let lo = altFt.min() ?? 0, hi = altFt.max() ?? 1
            let x: (Double) -> CGFloat = { padL + CGFloat($0 / total) * plotW }
            let y: (Double) -> CGFloat = { padT + plotH - CGFloat(($0 - lo) / max(hi - lo, 1)) * plotH }
            ZStack(alignment: .topLeading) {
                // grade-tinted columns
                ForEach(Array(times.enumerated()), id: \.offset) { i, t in
                    if i > 0, i < grade.count {
                        let g = grade[i]
                        let col: Color = g > 1.5 ? Color.drip.coral : (g < -1.5 ? Color.drip.positive : Color.drip.textTertiary)
                        let op = min(0.5, abs(g) / 8 + 0.06)
                        let x0 = x(times[i - 1]), x1 = x(t)
                        Rectangle().fill(col.opacity(op))
                            .frame(width: max(x1 - x0 + 0.5, 0.5), height: plotH).position(x: (x0 + x1) / 2, y: padT + plotH / 2)
                    }
                }
                // area + line
                Path { p in
                    p.move(to: .init(x: x(times.first ?? 0), y: padT + plotH))
                    for (i, t) in times.enumerated() where i < altFt.count { p.addLine(to: .init(x: x(t), y: y(altFt[i]))) }
                    p.addLine(to: .init(x: x(times.last ?? 0), y: padT + plotH))
                    p.closeSubpath()
                }
                .fill(Color.drip.textPrimary.opacity(0.06))
                Path { p in
                    for (i, t) in times.enumerated() where i < altFt.count {
                        let pt = CGPoint(x: x(t), y: y(altFt[i]))
                        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                    }
                }
                .stroke(Color.drip.textPrimary.opacity(0.55), lineWidth: 0.9)
            }
        }
        .frame(height: height)
    }
}

// MARK: - 6 · Rep recovery small-multiples

struct RRRecoveryRow: View {
    let recoveries: [RRRecovery]
    var body: some View {
        HStack(spacing: 6) {
            ForEach(recoveries) { r in
                VStack(spacing: 3) {
                    Text("R\(r.id)").font(.dripStat(8)).foregroundStyle(Color.drip.textTertiary)
                    GeometryReader { geo in
                        let w = geo.size.width, h = geo.size.height
                        let lo = 130.0, hi = 185.0
                        Path { p in
                            for (i, v) in r.pts.enumerated() {
                                let x = CGFloat(i) / CGFloat(max(r.pts.count - 1, 1)) * w
                                let y = h - CGFloat((Double(v) - lo) / (hi - lo)) * h
                                if i == 0 { p.move(to: .init(x: x, y: y)) } else { p.addLine(to: .init(x: x, y: y)) }
                            }
                        }
                        .stroke(r.drop >= 36 ? Color.drip.coral : Color.drip.textSecondary, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                    }
                    .frame(height: 26)
                    Text("−\(r.drop)").font(.dripStat(11)).foregroundStyle(r.drop >= 36 ? Color.drip.coral : Color.drip.textPrimary)
                    Text("bpm/60s").font(.dripStat(7)).foregroundStyle(Color.drip.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .overlay(Rectangle().fill(Color.drip.divider).frame(height: 1), alignment: .bottom)
            }
        }
    }
}

// MARK: - 7 · Time in zone bar

struct RRZoneBar: View {
    let seconds: [String: Double]   // zone id → seconds
    let zones: [RRZone]
    let mainZone: String

    var body: some View {
        let total = max(seconds.values.reduce(0, +), 1)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 0) {
                ForEach(zones) { z in
                    let pct = (seconds[z.id] ?? 0) / total
                    if pct > 0.004 {
                        Rectangle().fill(z.color).opacity(z.id == mainZone ? 1 : 0.5)
                            .frame(maxWidth: .infinity).frame(width: nil)
                            .overlay(Rectangle().fill(Color.drip.background).frame(width: 1), alignment: .trailing)
                            .layoutPriority(pct)
                    }
                }
            }
            .frame(height: 20)
            .overlay(Rectangle().stroke(Color.drip.divider, lineWidth: 1))
            HStack(alignment: .top, spacing: 6) {
                ForEach(zones) { z in
                    let sec = seconds[z.id] ?? 0
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Rectangle().fill(z.color).opacity(z.id == mainZone ? 1 : 0.5).frame(width: 6, height: 6)
                            Text(z.id).font(.dripStat(8)).foregroundStyle(z.id == mainZone ? Color.drip.textPrimary : Color.drip.textTertiary)
                        }
                        Text(rr_clock(sec)).font(.dripStat(12)).foregroundStyle(z.id == mainZone ? Color.drip.coral : Color.drip.textSecondary)
                        Text("\(Int((sec / total * 100).rounded()))%").font(.dripStat(8)).foregroundStyle(Color.drip.textTertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

// MARK: - 8 · Route shape

struct RRRouteShape: View {
    let coords: [CLLocationCoordinate2D]
    let hr: [Int]            // parallel to coords (may be empty)
    let colorByZone: Bool
    let zones: [RRZone]
    let repStartIdx: [(idx: Int, rep: Int)]
    var height: CGFloat = 150

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let pad: CGFloat = 16
            guard coords.count > 1 else { return AnyView(EmptyView()) }
            let lats = coords.map(\.latitude), lngs = coords.map(\.longitude)
            let minLat = lats.min()!, maxLat = lats.max()!, minLng = lngs.min()!, maxLng = lngs.max()!
            let spanLat = max(maxLat - minLat, 1e-5), spanLng = max(maxLng - minLng, 1e-5)
            let scale = min((w - pad * 2) / spanLng, (h - pad * 2) / spanLat)
            let ox = (w - spanLng * scale) / 2, oy = (h - spanLat * scale) / 2
            let pt: (Int) -> CGPoint = { i in
                CGPoint(x: ox + (coords[i].longitude - minLng) * scale,
                        y: h - (oy + (coords[i].latitude - minLat) * scale))
            }
            return AnyView(
                ZStack {
                    ForEach(1..<coords.count, id: \.self) { i in
                        let col: Color = {
                            if colorByZone, i < hr.count { return rr_zoneColor(hr[i], zones) }
                            // coral when fast (proxy: inside a rep window via hr high), else gray
                            if i < hr.count, hr[i] >= 160 { return Color.drip.coral }
                            return Color.drip.textTertiary
                        }()
                        Path { p in p.move(to: pt(i - 1)); p.addLine(to: pt(i)) }
                            .stroke(col.opacity(0.9), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                    }
                    ForEach(Array(repStartIdx.enumerated()), id: \.offset) { _, rs in
                        let p = pt(rs.idx)
                        Circle().fill(Color.drip.background).overlay(Circle().stroke(Color.drip.textPrimary, lineWidth: 1.2))
                            .frame(width: 13, height: 13).position(p)
                        Text("\(rs.rep)").font(.dripStat(8)).foregroundStyle(Color.drip.textPrimary).position(p)
                    }
                    Circle().fill(Color.drip.textPrimary).frame(width: 7, height: 7).position(pt(0))
                    Circle().fill(Color.drip.coral).frame(width: 7, height: 7).position(pt(coords.count - 1))
                }
            )
        }
        .frame(height: height)
        .background(Color.drip.cardBackgroundElevated)
        .overlay(Rectangle().stroke(Color.drip.divider, lineWidth: 1))
    }
}

// MARK: - Shared helpers (rr_*)

private struct RRItem { let isRest: Bool; let rep: Int; let dur: Double; let x0: Double }

private func rr_layItems(reps: [RRRep]) -> [RRItem] {
    var out: [RRItem] = []
    var cursor = 0.0
    for r in reps {
        let dur = r.distMi * r.paceSec
        out.append(RRItem(isRest: false, rep: r.id, dur: dur, x0: cursor)); cursor += dur
        if let rest = r.restSec { out.append(RRItem(isRest: true, rep: r.id, dur: Double(rest), x0: cursor)); cursor += Double(rest) }
    }
    return out
}

func rr_smooth(_ a: [Double], win: Int) -> [Double] {
    guard !a.isEmpty else { return a }
    return a.indices.map { i in
        let lo = max(0, i - win), hi = min(a.count - 1, i + win)
        return a[lo...hi].reduce(0, +) / Double(hi - lo + 1)
    }
}

func rr_zoneColor(_ hr: Int?, _ zones: [RRZone]) -> Color {
    guard let hr else { return Color.drip.textSecondary }
    return zones.first { hr >= $0.lo && hr < $0.hi }?.color ?? zones.last?.color ?? Color.drip.coral
}

/// Format sec/mi as m:ss, optionally per-km.
func rr_pace(_ secPerMile: Double, km: Bool) -> String {
    let v = km ? secPerMile / 1.60934 : secPerMile
    let t = Int(v.rounded()); return "\(t / 60):\(String(format: "%02d", t % 60))"
}
func rr_clock(_ sec: Double) -> String {
    let t = Int(sec.rounded()); return "\(t / 60):\(String(format: "%02d", t % 60))"
}
func rr_dist(_ mi: Double, km: Bool) -> String {
    String(format: "%.2f%@", km ? mi * 1.60934 : mi, km ? "km" : "mi")
}

/// Standard 5-band HR zones from a max HR.
func rr_zones(maxHR: Int) -> [RRZone] {
    let m = Double(max(maxHR, 150))
    func b(_ f: Double) -> Int { Int((m * f).rounded()) }
    return [
        RRZone(id: "Z1", lo: 0,       hi: b(0.70), color: Color.drip.neutral),
        RRZone(id: "Z2", lo: b(0.70), hi: b(0.80), color: Color.drip.positive),
        RRZone(id: "Z3", lo: b(0.80), hi: b(0.88), color: Color.drip.tired),
        RRZone(id: "Z4", lo: b(0.88), hi: b(0.95), color: Color.drip.coral),
        RRZone(id: "Z5", lo: b(0.95), hi: 240,     color: Color.drip.struggling),
    ]
}
