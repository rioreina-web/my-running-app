//
//  VitalWorkoutCharts.swift
//  RunningLog
//
//  Chart and data visualization components for VitalWorkoutDetailView.
//  Includes ElevationProfileCard, PaceChartCard, and supporting types.
//

import SwiftUI

// MARK: - Elevation Profile Card

struct ElevationProfileCard: View {
    let altitudes: [Double]
    let distances: [Double]
    let totalElevationGain: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "mountain.2.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.green)
                Text("ELEVATION")
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textSecondary)
                    .tracking(1.2)

                Spacer()

                if let gain = totalElevationGain {
                    Text("↑ \(Int(gain * 3.28084)) ft")
                        .font(.dripLabel(12))
                        .foregroundStyle(.green)
                }
            }

            // Elevation chart
            GeometryReader { geometry in
                let width = geometry.size.width
                let height: CGFloat = 100

                // Sample altitudes for smooth rendering
                let sampled = sampleData(altitudes, count: Int(width / 2))
                let minAlt = sampled.min() ?? 0
                let maxAlt = sampled.max() ?? 100
                let altRange = max(maxAlt - minAlt, 5)

                ZStack(alignment: .bottomLeading) {
                    // Fill
                    Path { path in
                        let stepWidth = width / CGFloat(sampled.count - 1)
                        path.move(to: CGPoint(x: 0, y: height))
                        for (i, alt) in sampled.enumerated() {
                            let x = CGFloat(i) * stepWidth
                            let y = height - CGFloat((alt - minAlt) / altRange) * height * 0.85
                            if i == 0 { path.addLine(to: CGPoint(x: x, y: y)) }
                            else { path.addLine(to: CGPoint(x: x, y: y)) }
                        }
                        path.addLine(to: CGPoint(x: width, y: height))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [Color.green.opacity(0.3), Color.green.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    // Line
                    Path { path in
                        let stepWidth = width / CGFloat(sampled.count - 1)
                        for (i, alt) in sampled.enumerated() {
                            let x = CGFloat(i) * stepWidth
                            let y = height - CGFloat((alt - minAlt) / altRange) * height * 0.85
                            if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                            else { path.addLine(to: CGPoint(x: x, y: y)) }
                        }
                    }
                    .stroke(Color.green, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
                .frame(height: height)
            }
            .frame(height: 100)

            // Min/Max labels
            HStack {
                let minAlt = altitudes.min() ?? 0
                let maxAlt = altitudes.max() ?? 0
                Text("\(Int(minAlt * 3.28084)) ft")
                    .font(.dripCaption(10))
                    .foregroundStyle(Color.drip.textTertiary)
                Spacer()
                Text("\(Int(maxAlt * 3.28084)) ft")
                    .font(.dripCaption(10))
                    .foregroundStyle(Color.drip.textTertiary)
            }
        }
        .padding(20)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.drip.divider, lineWidth: 1)
        )
    }

    private func sampleData(_ data: [Double], count: Int) -> [Double] {
        guard data.count > count, count > 1 else { return data }
        let step = Double(data.count - 1) / Double(count - 1)
        return (0..<count).map { i in
            let index = min(Int(Double(i) * step), data.count - 1)
            return data[index]
        }
    }
}

// MARK: - Chart Overlay Options

enum ChartOverlay: String, CaseIterable {
    case paceZones = "Zones"
    case heartRate = "HR"
    case cadence = "Cadence"
    case gap = "GAP"
    case elevation = "Elev"

    var icon: String {
        switch self {
        case .paceZones: return "chart.bar.fill"
        case .heartRate: return "heart.fill"
        case .cadence: return "metronome.fill"
        case .gap: return "mountain.2.fill"
        case .elevation: return "arrow.up.right"
        }
    }

    var color: Color {
        switch self {
        case .paceZones: return Color.drip.coral.opacity(0.3)
        case .heartRate: return .red
        case .cadence: return .cyan
        case .gap: return .orange
        case .elevation: return Color.drip.positive
        }
    }
}

// MARK: - Chart Data Point (pre-computed for rendering)

struct ChartPoint {
    let distanceMiles: Double
    let pace: Double        // min/mi
    let heartrate: Double?  // bpm
    let altitude: Double?   // meters
    let cadence: Double?    // spm
    let gap: Double?        // grade-adjusted pace min/mi
    let velocity: Double    // m/s (raw)
}

// MARK: - PaceChartCard (Zoomable with Overlays)

struct PaceChartCard: View {
    let velocities: [Double]
    let distances: [Double]
    let times: [Int]
    let heartrates: [Int]?
    var altitudes: [Double]? = nil
    var cadences: [Double]? = nil
    var equivalentPaces: EquivalentPaces? = nil

    private let mileInMeters = 1609.34
    private let chartHeight: CGFloat = 180

    @State private var activeOverlays: Set<ChartOverlay> = []
    @State private var zoom: CGFloat = 1.0
    @State private var panOffset: CGFloat = 0
    @State private var lastZoom: CGFloat = 1.0
    @State private var lastPan: CGFloat = 0
    @State private var touchLocation: CGFloat? = nil

    // Pre-computed chart data (smoothed, sampled)
    private var chartPoints: [ChartPoint] {
        computeChartPoints()
    }

    private var avgPace: Double {
        let paces = chartPoints.map(\.pace)
        guard !paces.isEmpty else { return 0 }
        return paces.reduce(0, +) / Double(paces.count)
    }

    private var paceMin: Double { // fastest (lowest number)
        max((chartPoints.map(\.pace).min() ?? 5) - 0.5, 3)
    }

    private var paceMax: Double { // slowest (highest number)
        min((chartPoints.map(\.pace).max() ?? 10) + 0.5, 15)
    }

    private var totalDistanceMiles: Double {
        (distances.last ?? 0) / mileInMeters
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            chartHeader
            overlayToggles
            chartArea
            xAxisLabel
        }
        .padding(20)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.drip.divider, lineWidth: 1)
        )
    }

    // MARK: - Header

    private var chartHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "speedometer")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.drip.coral)
            Text("PACE")
                .font(.dripCaption(11))
                .foregroundStyle(Color.drip.textSecondary)
                .tracking(1.2)
            Spacer()
            Text("avg \(formatPace(avgPace)) /mi")
                .font(.dripLabel(12))
                .foregroundStyle(Color.drip.coral)
        }
    }

    // MARK: - Overlay Toggles

    private var overlayToggles: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ChartOverlay.allCases, id: \.rawValue) { overlay in
                    overlayButton(overlay)
                }
            }
        }
    }

    private func overlayButton(_ overlay: ChartOverlay) -> some View {
        let isOn = activeOverlays.contains(overlay)
        let available = overlayAvailable(overlay)
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                if isOn { activeOverlays.remove(overlay) } else { activeOverlays.insert(overlay) }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: overlay.icon)
                    .font(.system(size: 9, weight: .semibold))
                Text(overlay.rawValue)
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(isOn ? Color.drip.background : overlay.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(isOn ? overlay.color : overlay.color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .opacity(available ? 1 : 0.35)
        }
        .disabled(!available)
    }

    private func overlayAvailable(_ overlay: ChartOverlay) -> Bool {
        switch overlay {
        case .paceZones: return true
        case .heartRate: return heartrates != nil && !(heartrates?.isEmpty ?? true)
        case .cadence: return cadences != nil && !(cadences?.isEmpty ?? true)
        case .gap: return altitudes != nil && !(altitudes?.isEmpty ?? true)
        case .elevation: return altitudes != nil && !(altitudes?.isEmpty ?? true)
        }
    }

    // MARK: - Chart Area (Zoomable)

    private var chartArea: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let totalWidth = width * zoom
            let clampedOffset = clampPan(panOffset, chartWidth: totalWidth, viewWidth: width)

            ZStack(alignment: .topLeading) {
                // Clipped chart content
                chartContent(viewWidth: width, totalWidth: totalWidth)
                    .offset(x: clampedOffset)
                    .clipped()

                // Y-axis labels (always visible, left side)
                paceYAxisLabels
                    .frame(width: 32)

                // Touch crosshair
                if let loc = touchLocation {
                    crosshairOverlay(at: loc, viewWidth: width, totalWidth: totalWidth, offset: clampedOffset)
                }
            }
            .frame(height: chartHeight + 20)
            .contentShape(Rectangle())
            .gesture(zoomGesture())
            .simultaneousGesture(panGesture(viewWidth: width, totalWidth: totalWidth))
            .simultaneousGesture(touchGesture(viewWidth: width, totalWidth: totalWidth, offset: clampedOffset))
        }
        .frame(height: chartHeight + 20)
    }

    // MARK: - Chart Content

    private func chartContent(viewWidth: CGFloat, totalWidth: CGFloat) -> some View {
        let paceRange = max(paceMax - paceMin, 1)

        return ZStack(alignment: .bottomLeading) {
            // Pace zone bands
            if activeOverlays.contains(.paceZones) {
                paceZoneBands(width: totalWidth, height: chartHeight, paceRange: paceRange)
            }

            // Grid lines
            paceGridOverlay(width: totalWidth, height: chartHeight, paceRange: paceRange)

            // Elevation fill
            if activeOverlays.contains(.elevation) {
                elevationFill(width: totalWidth, height: chartHeight)
            }

            // Pace gradient fill
            paceFill(width: totalWidth, height: chartHeight, paceRange: paceRange)

            // Pace line
            paceLine(width: totalWidth, height: chartHeight, paceRange: paceRange)

            // GAP line
            if activeOverlays.contains(.gap) {
                gapLine(width: totalWidth, height: chartHeight, paceRange: paceRange)
            }

            // HR overlay
            if activeOverlays.contains(.heartRate) {
                hrLine(width: totalWidth, height: chartHeight)
            }

            // Cadence overlay
            if activeOverlays.contains(.cadence) {
                cadenceLine(width: totalWidth, height: chartHeight)
            }

            // Average pace dashed line
            avgPaceLine(width: totalWidth, height: chartHeight, paceRange: paceRange)

            // Mile markers
            mileMarkers(width: totalWidth, height: chartHeight)
        }
        .frame(width: totalWidth, height: chartHeight + 16)
    }

    // MARK: - Pace Zone Bands

    private func paceZoneBands(width: CGFloat, height: CGFloat, paceRange: Double) -> some View {
        let zones: [(label: String, color: Color, topPace: Double, bottomPace: Double)] = buildZoneBands()
        return ZStack {
            ForEach(Array(zones.enumerated()), id: \.offset) { _, zone in
                let top = max(0, height - CGFloat((paceMax - zone.topPace) / paceRange) * height)
                let bottom = min(height, height - CGFloat((paceMax - zone.bottomPace) / paceRange) * height)
                let bandHeight = max(bottom - top, 0)
                if bandHeight > 0 {
                    Rectangle()
                        .fill(zone.color.opacity(0.08))
                        .frame(width: width, height: bandHeight)
                        .offset(y: top - height / 2 + bandHeight / 2)
                }
            }
        }
        .frame(width: width, height: height)
    }

    private func buildZoneBands() -> [(label: String, color: Color, topPace: Double, bottomPace: Double)] {
        // Pace in min/mi — lower number = faster = top of chart
        let zones: [(String, Color, Double, Double)]
        if let p = equivalentPaces {
            let toMin = { (sec: Double) in sec / 60.0 }
            zones = [
                ("Easy", PaceZone.easy.color, toMin(p.easyPace), paceMax),
                ("Mod", PaceZone.moderate.color, toMin(p.moderatePace), toMin(p.easyPace)),
                ("Steady", PaceZone.steady.color, toMin(p.steadyPace), toMin(p.moderatePace)),
                ("MP", PaceZone.mp.color, toMin(p.mpPace), toMin(p.steadyPace)),
                ("HMP", PaceZone.hmp.color, toMin(p.hmPace), toMin(p.mpPace)),
                ("10K", PaceZone.tenK.color, toMin(p.tenKPace), toMin(p.hmPace)),
                ("5K", PaceZone.fiveK.color, toMin(p.fiveKPace), toMin(p.tenKPace)),
                ("3K", PaceZone.threeK.color, toMin(p.threeKPace), toMin(p.fiveKPace)),
                ("Mile", PaceZone.mile.color, paceMin, toMin(p.threeKPace)),
            ]
        } else {
            // No pace data — don't draw zone bands
            zones = []
        }
        return zones.map { ($0.0, $0.1, $0.2, $0.3) }
    }

    // MARK: - Pace Line & Fill

    private func paceFill(width: CGFloat, height: CGFloat, paceRange: Double) -> some View {
        Path { path in
            guard !chartPoints.isEmpty else { return }
            let xScale = totalDistanceMiles > 0 ? width / CGFloat(totalDistanceMiles) : 0
            path.move(to: CGPoint(x: CGFloat(chartPoints[0].distanceMiles) * xScale, y: height))
            for pt in chartPoints {
                let x = CGFloat(pt.distanceMiles) * xScale
                let y = height - CGFloat((paceMax - pt.pace) / paceRange) * height
                path.addLine(to: CGPoint(x: x, y: y))
            }
            if let last = chartPoints.last {
                path.addLine(to: CGPoint(x: CGFloat(last.distanceMiles) * xScale, y: height))
            }
            path.closeSubpath()
        }
        .fill(LinearGradient(
            colors: [Color.drip.coral.opacity(0.25), Color.drip.coral.opacity(0.03)],
            startPoint: .top, endPoint: .bottom
        ))
    }

    private func paceLine(width: CGFloat, height: CGFloat, paceRange: Double) -> some View {
        Path { path in
            guard !chartPoints.isEmpty else { return }
            let xScale = totalDistanceMiles > 0 ? width / CGFloat(totalDistanceMiles) : 0
            let firstY = height - CGFloat((paceMax - chartPoints[0].pace) / paceRange) * height
            path.move(to: CGPoint(x: CGFloat(chartPoints[0].distanceMiles) * xScale, y: firstY))
            for pt in chartPoints.dropFirst() {
                let x = CGFloat(pt.distanceMiles) * xScale
                let y = height - CGFloat((paceMax - pt.pace) / paceRange) * height
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        .stroke(Color.drip.coral, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
    }

    // MARK: - GAP Line

    private func gapLine(width: CGFloat, height: CGFloat, paceRange: Double) -> some View {
        Path { path in
            let pts = chartPoints.filter { $0.gap != nil }
            guard !pts.isEmpty else { return }
            let xScale = totalDistanceMiles > 0 ? width / CGFloat(totalDistanceMiles) : 0
            let firstY = height - CGFloat((paceMax - (pts[0].gap ?? pts[0].pace)) / paceRange) * height
            path.move(to: CGPoint(x: CGFloat(pts[0].distanceMiles) * xScale, y: firstY))
            for pt in pts.dropFirst() {
                let x = CGFloat(pt.distanceMiles) * xScale
                let y = height - CGFloat((paceMax - (pt.gap ?? pt.pace)) / paceRange) * height
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        .stroke(Color.orange, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round, dash: [6, 3]))
    }

    // MARK: - Heart Rate Line (secondary Y-axis)

    private func hrLine(width: CGFloat, height: CGFloat) -> some View {
        let hrs = chartPoints.compactMap { $0.heartrate }
        let minHR = max((hrs.min() ?? 100) - 10, 60)
        let maxHR = min((hrs.max() ?? 180) + 10, 220)
        let hrRange = max(maxHR - minHR, 1)

        return ZStack {
            Path { path in
                let pts = chartPoints.filter { $0.heartrate != nil }
                guard !pts.isEmpty else { return }
                let xScale = totalDistanceMiles > 0 ? width / CGFloat(totalDistanceMiles) : 0
                let firstY = height - CGFloat((pts[0].heartrate! - minHR) / hrRange) * height
                path.move(to: CGPoint(x: CGFloat(pts[0].distanceMiles) * xScale, y: firstY))
                for pt in pts.dropFirst() {
                    let x = CGFloat(pt.distanceMiles) * xScale
                    let y = height - CGFloat((pt.heartrate! - minHR) / hrRange) * height
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            .stroke(Color.red.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

            // HR axis labels (right side)
            hrAxisLabels(height: height, minHR: minHR, maxHR: maxHR, hrRange: hrRange, width: width)
        }
    }

    private func hrAxisLabels(height: CGFloat, minHR: Double, maxHR: Double, hrRange: Double, width: CGFloat) -> some View {
        let step = hrRange > 60 ? 30.0 : 20.0
        let labels = stride(from: (minHR / step).rounded(.up) * step, through: maxHR, by: step)
        return ForEach(Array(labels.enumerated()), id: \.offset) { _, hr in
            let y = height - CGFloat((hr - minHR) / hrRange) * height
            Text("\(Int(hr))")
                .font(.system(size: 7, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.red.opacity(0.6))
                .position(x: width - 14, y: y)
        }
    }

    // MARK: - Cadence Line

    private func cadenceLine(width: CGFloat, height: CGFloat) -> some View {
        let cads = chartPoints.compactMap { $0.cadence }
        let minCad = max((cads.min() ?? 150) - 10, 120)
        let maxCad = min((cads.max() ?? 200) + 10, 230)
        let cadRange = max(maxCad - minCad, 1)

        return Path { path in
            let pts = chartPoints.filter { $0.cadence != nil }
            guard !pts.isEmpty else { return }
            let xScale = totalDistanceMiles > 0 ? width / CGFloat(totalDistanceMiles) : 0
            let firstY = height - CGFloat((pts[0].cadence! - minCad) / cadRange) * height
            path.move(to: CGPoint(x: CGFloat(pts[0].distanceMiles) * xScale, y: firstY))
            for pt in pts.dropFirst() {
                let x = CGFloat(pt.distanceMiles) * xScale
                let y = height - CGFloat((pt.cadence! - minCad) / cadRange) * height
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        .stroke(Color.cyan.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
    }

    // MARK: - Elevation Fill

    private func elevationFill(width: CGFloat, height: CGFloat) -> some View {
        let alts = chartPoints.compactMap { $0.altitude }
        let minAlt = (alts.min() ?? 0) - 5
        let maxAlt = (alts.max() ?? 100) + 5
        let altRange = max(maxAlt - minAlt, 1)
        let elevHeight = height * 0.3 // elevation occupies bottom 30%

        return Path { path in
            let pts = chartPoints.filter { $0.altitude != nil }
            guard !pts.isEmpty else { return }
            let xScale = totalDistanceMiles > 0 ? width / CGFloat(totalDistanceMiles) : 0
            path.move(to: CGPoint(x: CGFloat(pts[0].distanceMiles) * xScale, y: height))
            for pt in pts {
                let x = CGFloat(pt.distanceMiles) * xScale
                let y = height - CGFloat((pt.altitude! - minAlt) / altRange) * elevHeight
                path.addLine(to: CGPoint(x: x, y: y))
            }
            if let last = pts.last {
                path.addLine(to: CGPoint(x: CGFloat(last.distanceMiles) * xScale, y: height))
            }
            path.closeSubpath()
        }
        .fill(Color.drip.positive.opacity(0.15))
    }

    // MARK: - Grid & Markers

    private func paceGridOverlay(width: CGFloat, height: CGFloat, paceRange: Double) -> some View {
        let lines = paceGridLines()
        return ForEach(Array(lines.enumerated()), id: \.offset) { _, pace in
            let y = height - CGFloat((paceMax - pace) / paceRange) * height
            Path { path in
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: width, y: y))
            }
            .stroke(Color.drip.divider.opacity(0.4), style: StrokeStyle(lineWidth: 0.5))
        }
    }

    private var paceYAxisLabels: some View {
        let paceRange = max(paceMax - paceMin, 1)
        let lines = paceGridLines()
        return ZStack {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, pace in
                let y = chartHeight - CGFloat((paceMax - pace) / paceRange) * chartHeight
                Text(formatPace(pace))
                    .font(.system(size: 7, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.drip.textTertiary)
                    .position(x: 16, y: y)
            }
        }
        .frame(height: chartHeight)
    }

    private func avgPaceLine(width: CGFloat, height: CGFloat, paceRange: Double) -> some View {
        let avgY = height - CGFloat((paceMax - avgPace) / paceRange) * height
        return Path { path in
            path.move(to: CGPoint(x: 0, y: avgY))
            path.addLine(to: CGPoint(x: width, y: avgY))
        }
        .stroke(Color.drip.coral.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
    }

    private func mileMarkers(width: CGFloat, height: CGFloat) -> some View {
        let count = Int(totalDistanceMiles)
        let xScale = totalDistanceMiles > 0 ? width / CGFloat(totalDistanceMiles) : 0
        return ForEach(1...max(count, 1), id: \.self) { mile in
            if mile <= count {
                let x = CGFloat(mile) * xScale
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.drip.textTertiary.opacity(0.2))
                        .frame(width: 0.5, height: height)
                    Text("\(mile)")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(Color.drip.textTertiary)
                }
                .position(x: x, y: height / 2 + 8)
            }
        }
    }

    // MARK: - Touch Crosshair

    private func crosshairOverlay(at loc: CGFloat, viewWidth: CGFloat, totalWidth: CGFloat, offset: CGFloat) -> some View {
        let chartX = loc - offset
        let fraction = totalWidth > 0 ? chartX / totalWidth : 0
        let distAtTouch = Double(fraction) * totalDistanceMiles
        let closest = chartPoints.min(by: { abs($0.distanceMiles - distAtTouch) < abs($1.distanceMiles - distAtTouch) })
        let paceRange = max(paceMax - paceMin, 1)

        return ZStack {
            // Vertical line
            Rectangle()
                .fill(Color.drip.textSecondary.opacity(0.4))
                .frame(width: 1, height: chartHeight)
                .position(x: loc, y: chartHeight / 2)

            // Tooltip
            if let pt = closest {
                let y = chartHeight - CGFloat((paceMax - pt.pace) / paceRange) * chartHeight
                Circle()
                    .fill(Color.drip.coral)
                    .frame(width: 6, height: 6)
                    .position(x: loc, y: y)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(formatPace(pt.pace))/mi")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.drip.coral)
                    Text(String(format: "%.2f mi", pt.distanceMiles))
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(Color.drip.textSecondary)
                    if let hr = pt.heartrate {
                        Text("\(Int(hr)) bpm")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(Color.red.opacity(0.8))
                    }
                    if let elev = pt.altitude {
                        Text("\(Int(elev * 3.28084)) ft")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(Color.drip.positive)
                    }
                }
                .padding(6)
                .background(Color.drip.cardBackground.opacity(0.95))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.drip.divider, lineWidth: 0.5))
                .position(x: min(max(loc, 50), viewWidth - 50), y: max(y - 40, 30))
            }
        }
    }

    // MARK: - Gestures

    private func zoomGesture() -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                zoom = max(1, min(lastZoom * value, 8))
            }
            .onEnded { value in
                lastZoom = zoom
            }
    }

    private func panGesture(viewWidth: CGFloat, totalWidth: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let newOffset = lastPan + value.translation.width
                panOffset = clampPan(newOffset, chartWidth: totalWidth, viewWidth: viewWidth)
            }
            .onEnded { _ in
                lastPan = panOffset
            }
    }

    private func touchGesture(viewWidth: CGFloat, totalWidth: CGFloat, offset: CGFloat) -> some Gesture {
        LongPressGesture(minimumDuration: 0.15)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                switch value {
                case .second(true, let drag):
                    if let drag = drag {
                        touchLocation = drag.location.x
                    }
                default: break
                }
            }
            .onEnded { _ in
                touchLocation = nil
            }
    }

    private func clampPan(_ offset: CGFloat, chartWidth: CGFloat, viewWidth: CGFloat) -> CGFloat {
        let maxPan: CGFloat = 0
        let minPan = viewWidth - chartWidth
        return max(min(offset, maxPan), min(minPan, 0))
    }

    // MARK: - X-axis Label

    private var xAxisLabel: some View {
        HStack {
            if zoom > 1.2 {
                Text("Pinch to zoom out")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(Color.drip.textTertiary)
            }
            Spacer()
            Text("DISTANCE (MI)")
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(Color.drip.textTertiary)
                .tracking(0.8)
            Spacer()
            if zoom > 1.2 {
                Button {
                    withAnimation(.spring(duration: 0.3)) {
                        zoom = 1; lastZoom = 1; panOffset = 0; lastPan = 0
                    }
                } label: {
                    Text("Reset")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Color.drip.coral)
                }
            }
        }
    }

    // MARK: - Data Computation

    private func computeChartPoints() -> [ChartPoint] {
        guard velocities.count >= 10 else { return [] }
        let window = 30
        let step = max(1, velocities.count / 400)
        var points: [ChartPoint] = []

        let hasHR = heartrates != nil && heartrates!.count == velocities.count
        let hasAlt = altitudes != nil && altitudes!.count == velocities.count
        let hasCad = cadences != nil && cadences!.count == velocities.count

        for i in stride(from: 0, to: velocities.count, by: step) {
            let lo = max(0, i - window / 2)
            let hi = min(velocities.count - 1, i + window / 2)

            // Smoothed velocity
            let velSlice = velocities[lo...hi]
            let avgVel = velSlice.reduce(0, +) / Double(velSlice.count)
            let pace = avgVel > 0.5 ? (mileInMeters / avgVel) / 60.0 : 0
            let dist = distances[i] / mileInMeters

            guard pace > 0 && pace < 20 else { continue }

            // Heart rate (smoothed)
            var hr: Double? = nil
            if hasHR {
                let hrSlice = heartrates![lo...hi]
                hr = Double(hrSlice.reduce(0, +)) / Double(hrSlice.count)
            }

            // Altitude
            var alt: Double? = nil
            if hasAlt { alt = altitudes![i] }

            // Cadence (smoothed)
            var cad: Double? = nil
            if hasCad {
                let cadSlice = cadences![lo...hi]
                cad = cadSlice.reduce(0, +) / Double(cadSlice.count)
            }

            // Grade Adjusted Pace
            var gap: Double? = nil
            if hasAlt && i > 0 {
                let prevI = max(0, i - step)
                let altDiff = altitudes![i] - altitudes![prevI]
                let distDiff = distances[i] - distances[prevI]
                if distDiff > 0 {
                    let grade = altDiff / distDiff // rise/run
                    // Minetti formula approximation: cost factor
                    let costFactor = 1.0 + 3.5 * grade // ~3.5% per 1% grade
                    let adjustedVel = avgVel * costFactor
                    let gapPace = adjustedVel > 0.5 ? (mileInMeters / adjustedVel) / 60.0 : pace
                    if gapPace > 0 && gapPace < 20 { gap = gapPace }
                }
            }

            points.append(ChartPoint(
                distanceMiles: dist, pace: pace, heartrate: hr,
                altitude: alt, cadence: cad, gap: gap, velocity: avgVel
            ))
        }
        return points
    }

    // MARK: - Helpers

    private func paceGridLines() -> [Double] {
        let range = paceMax - paceMin
        let interval: Double
        if range > 6 { interval = 2.0 }
        else if range > 3 { interval = 1.0 }
        else { interval = 0.5 }
        var lines: [Double] = []
        var pace = (paceMin / interval).rounded(.up) * interval
        while pace <= paceMax {
            lines.append(pace)
            pace += interval
        }
        return lines
    }

    private func formatPace(_ paceMinPerMile: Double) -> String {
        PaceCalculator.formatPaceFromMinutes(paceMinPerMile)
    }
}
