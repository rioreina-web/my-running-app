//
//  RouteMapView.swift
//  RunningLog
//
//  The single, canonical GPS route map for the whole app.
//
//  Hybrid treatment (2026-07):
//
//    • INLINE — an editorial "ink-line" drawing: the route is rendered as a
//      pace-colored vector path on warm paper, with NO map tiles underneath.
//      This keeps the route on-brand with the Post Run Drip editorial system
//      ("no images as background, ever") and renders far cheaper than a live
//      MapKit basemap.
//    • ON TAP — expands to the real, pannable/zoomable Apple map
//      (`RouteMapFullscreen`) for street context when the athlete wants it.
//
//  Shared across both:
//    • A path COLORED BY PACE, computed from the route's own timestamps, so it
//      works identically for HealthKit and Strava-synced runs (blue ramp —
//      PaceSpectrum; single coral accent when there's no pace variation).
//    • Start / finish markers, plus optional numbered rep pins and mile ticks.
//
//  All heavy geometry (cleaning, downsampling, pace, segments, mile markers,
//  bounding box) is computed once in `init` so SwiftUI re-renders (toggles,
//  sheet animation) stay cheap.
//

import CoreLocation
import MapKit
import SwiftUI

// MARK: - Marker model

/// A labelled pin placed on the route (an interval rep, or a mile split).
struct RouteMarker: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let label: String
    let kind: Kind
    enum Kind { case rep, mile }
}

// MARK: - RouteMapView

struct RouteMapView: View {
    // Precomputed, immutable render data.
    private let clean: [CLLocation]
    private let segments: [RouteSegment]
    private let downsampledCoords: [CLLocationCoordinate2D]
    private let repMarkers: [RouteMarker]
    private let mileMarkers: [RouteMarker]
    private let region: MKCoordinateRegion
    private let bbox: RouteBBox
    private let hasPaceColor: Bool
    private let scrubTrack: RouteScrubTrack

    private let height: CGFloat

    @State private var showFullscreen = false

    /// - Parameters:
    ///   - route: cleaned-or-raw GPS points (sanitized again internally).
    ///   - repMarkers: optional numbered interval pins.
    ///   - showMileMarkers: place a tick every whole mile.
    ///   - height: inline map height.
    ///   - hrTimes: heart-rate stream sample times, seconds from workout start.
    ///     Optional — without it the expanded map still scrubs, just with pace
    ///     only. Pace comes from the route's own timestamps.
    ///   - hrValues: heart-rate values in BPM, parallel to `hrTimes`.
    init(
        route: [CLLocation],
        repMarkers: [RouteMarker] = [],
        showMileMarkers: Bool = true,
        height: CGFloat = 240,
        hrTimes: [Double] = [],
        hrValues: [Double] = []
    ) {
        let cleaned = RouteSanitizer.clean(route)
        self.clean = cleaned
        self.height = height

        // Downsample to keep the segment count (and annotation count) sane on
        // long runs — a 20-miler can be 10k+ points. ~240 points is plenty for
        // a smooth-looking line at any zoom we show inline.
        let ds = RouteMapView.downsample(cleaned, maxPoints: 240)
        self.downsampledCoords = ds.map(\.coordinate)

        let paces = RouteMapView.segmentPaces(ds)
        let (lo, hi) = RouteMapView.paceBounds(paces)
        self.hasPaceColor = hi > lo && ds.count > 2

        self.segments = RouteMapView.buildSegments(ds, paces: paces, lo: lo, hi: hi, colored: hi > lo)
        self.repMarkers = repMarkers
        self.mileMarkers = showMileMarkers ? RouteMapView.buildMileMarkers(cleaned) : []
        self.region = RouteMapView.boundingRegion(cleaned)
        self.bbox = RouteMapView.boundingBox(cleaned)

        // Scrub data is built off the FULL cleaned track (not the 240-point
        // render downsample) so the readout is as precise as the GPS allows,
        // then capped at 600 points for a fast hit test.
        self.scrubTrack = RouteScrubTrack(route: cleaned, hrTimes: hrTimes, hrValues: hrValues)
    }

    var body: some View {
        Group {
            if clean.count > 1 {
                mapBody
            } else {
                emptyState
            }
        }
    }

    // MARK: Inline map

    private var mapBody: some View {
        editorialRoute
        .frame(height: height)
        .background(Color.drip.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .topTrailing) { expandButton }
        .overlay(alignment: .bottomLeading) { if hasPaceColor { paceLegend } }
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.drip.divider, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture { showFullscreen = true }
        .accessibilityElement()
        .accessibilityLabel("Run route map. Double tap to expand.")
        .fullScreenCover(isPresented: $showFullscreen) {
            RouteMapFullscreen(
                region: region,
                segments: segments,
                downsampledCoords: downsampledCoords,
                clean: clean,
                repMarkers: repMarkers,
                mileMarkers: mileMarkers,
                track: scrubTrack
            )
        }
    }

    // MARK: Editorial inline route (no basemap)

    /// The inline, on-paper route drawing. Pace-colored path + markers,
    /// projected from GPS coordinates into the view's own pixel space so the
    /// route shape is preserved without any map tiles.
    private var editorialRoute: some View {
        GeometryReader { geo in
            let proj = RouteProjection(bbox: bbox, size: geo.size, inset: 20)
            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in
                    for seg in segments where seg.coords.count > 1 {
                        var path = Path()
                        path.move(to: proj.point(seg.coords[0]))
                        for c in seg.coords.dropFirst() { path.addLine(to: proj.point(c)) }
                        ctx.stroke(
                            path,
                            with: .color(seg.color),
                            style: StrokeStyle(lineWidth: 3.8, lineCap: .round, lineJoin: .round)
                        )
                    }
                }

                ForEach(mileMarkers) { m in
                    MileTick(label: m.label).position(proj.point(m.coordinate))
                }
                ForEach(repMarkers) { r in
                    RepPin(label: r.label).position(proj.point(r.coordinate))
                }
                if let start = clean.first {
                    EndpointDot(fill: Color.drip.positive).position(proj.point(start.coordinate))
                }
                if let finish = clean.last {
                    EndpointDot(fill: Color.drip.coral).position(proj.point(finish.coordinate))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    /// Shared map overlay content (line + markers), reused by the fullscreen map.
    @MapContentBuilder
    private var routeContent: some MapContent {
        RouteMapContent(
            segments: segments,
            downsampledCoords: downsampledCoords,
            clean: clean,
            repMarkers: repMarkers,
            mileMarkers: mileMarkers
        )
    }

    // MARK: Chrome

    private var expandButton: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(Color.drip.textSecondary)
            .padding(8)
            .background(Color.drip.cardBackground.opacity(0.92), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.drip.divider, lineWidth: 1))
            .padding(10)
    }

    /// Pace legend — the universal pace ramp (PaceSpectrum): pale sky (slow)
    /// deepening to navy (fast). Same color language as the pace charts, and
    /// the direction matches the route line's own coloring. Solid warm surface,
    /// no blur — the design system uses no glass on paper.
    private var paceLegend: some View {
        HStack(spacing: 6) {
            Text("SLOW").font(.dripStat(8)).foregroundStyle(PaceSpectrum.easyText)
            LinearGradient(
                colors: PaceSpectrum.stops,
                startPoint: .leading, endPoint: .trailing
            )
            .frame(width: 44, height: 4)
            .clipShape(Capsule())
            Text("FAST").font(.dripStat(8)).foregroundStyle(Color.drip.paceFast)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.drip.cardBackground.opacity(0.92), in: Capsule())
        .overlay(Capsule().stroke(Color.drip.divider, lineWidth: 1))
        .padding(10)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "mappin.slash")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(Color.drip.textTertiary)
            Text("No GPS for this run")
                .font(.dripLabel(13))
                .foregroundStyle(Color.drip.textSecondary)
            Text("Treadmill and indoor runs won't have a map.")
                .font(.dripCaption(11))
                .foregroundStyle(Color.drip.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(Color.drip.cardBackgroundElevated)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.drip.divider, lineWidth: 1)
        )
    }
}

// MARK: - Shared map content

/// The line + markers, factored out so the inline and fullscreen maps draw
/// exactly the same thing.
struct RouteMapContent: MapContent {
    let segments: [RouteSegment]
    let downsampledCoords: [CLLocationCoordinate2D]
    let clean: [CLLocation]
    let repMarkers: [RouteMarker]
    let mileMarkers: [RouteMarker]

    @MapContentBuilder
    var body: some MapContent {
        // White casing underneath for contrast against varied map tiles.
        if downsampledCoords.count > 1 {
            MapPolyline(coordinates: downsampledCoords)
                .stroke(
                    Color.white.opacity(0.95),
                    style: StrokeStyle(lineWidth: 6.5, lineCap: .round, lineJoin: .round)
                )
        }

        // Colored pace runs on top. Each `seg` is now a MERGED multi-point
        // run of one color (see buildSegments), so this is a few dozen
        // overlays instead of ~240 — the fix for the MapKit allocation churn.
        ForEach(segments) { seg in
            MapPolyline(coordinates: seg.coords)
                .stroke(seg.color, style: StrokeStyle(lineWidth: 3.6, lineCap: .round, lineJoin: .round))
        }

        // Mile ticks (drawn below rep pins / start / finish).
        ForEach(mileMarkers) { m in
            Annotation(m.label, coordinate: m.coordinate, anchor: .center) {
                MileTick(label: m.label)
            }
            .annotationTitles(.hidden)
        }

        // Interval rep pins.
        ForEach(repMarkers) { r in
            Annotation(r.label, coordinate: r.coordinate, anchor: .center) {
                RepPin(label: r.label)
            }
            .annotationTitles(.hidden)
        }

        // Start (green) and finish (coral).
        if let start = clean.first?.coordinate {
            Annotation("Start", coordinate: start, anchor: .center) {
                EndpointDot(fill: Color.drip.positive)
            }
            .annotationTitles(.hidden)
        }
        if let finish = clean.last?.coordinate {
            Annotation("Finish", coordinate: finish, anchor: .center) {
                EndpointDot(fill: Color.drip.coral)
            }
            .annotationTitles(.hidden)
        }
    }
}

// MARK: - Fullscreen

private struct RouteMapFullscreen: View {
    let region: MKCoordinateRegion
    let segments: [RouteSegment]
    let downsampledCoords: [CLLocationCoordinate2D]
    let clean: [CLLocation]
    let repMarkers: [RouteMarker]
    let mileMarkers: [RouteMarker]
    var track: RouteScrubTrack = RouteScrubTrack(route: [])

    @Environment(\.dismiss) private var dismiss
    @AppStorage("unit_use_km") private var km = false

    /// MOVE = normal map. TRACE = drag along the route to read pace/HR.
    @State private var scrubbing = false
    @State private var scrubIndex: Int?

    private var canScrub: Bool { !track.isEmpty }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Real, pannable street map — on the custom Stadia basemap when a
            // key is configured, otherwise Apple's standard map.
            StreetRouteMapView(
                region: region,
                segments: segments,
                downsampledCoords: downsampledCoords,
                clean: clean,
                repMarkers: repMarkers,
                mileMarkers: mileMarkers,
                track: track,
                scrubEnabled: scrubbing,
                scrubIndex: $scrubIndex
            )
            .ignoresSafeArea()

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.drip.textPrimary)
                    .padding(12)
                    .background(.regularMaterial, in: Circle())
            }
            .padding(16)

            if canScrub {
                modeToggle
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }

            if canScrub {
                VStack {
                    Spacer()
                    RouteScrubReadout(
                        point: scrubIndex.flatMap { track.point(at: $0) },
                        hasHR: track.hasHR,
                        armed: scrubbing,
                        km: km
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
            }
        }
    }

    /// Two words, one tap. Scrub has to be an explicit mode because a drag on
    /// a map already means "pan" — there's no way to have both on one finger
    /// without one of them feeling broken.
    private var modeToggle: some View {
        HStack(spacing: 0) {
            modeButton(title: "MOVE", active: !scrubbing) {
                scrubbing = false
                scrubIndex = nil
            }
            modeButton(title: "TRACE", active: scrubbing) {
                scrubbing = true
            }
        }
        .background(Color.drip.cardBackground.opacity(0.94), in: Capsule())
        .overlay(Capsule().stroke(Color.drip.divider, lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
    }

    private func modeButton(title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.dripStat(10))
                .foregroundStyle(active ? Color.drip.cardBackground : Color.drip.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(active ? Color.drip.textPrimary : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Scrub readout

/// The pace / HR card under the expanded map. Three states, in order of how
/// often the athlete will see them:
///   • scrubbing on a point  → the numbers at that moment
///   • TRACE on, nothing yet → a one-line prompt
///   • MOVE mode             → hidden entirely
private struct RouteScrubReadout: View {
    let point: RouteScrubPoint?
    let hasHR: Bool
    let armed: Bool
    let km: Bool

    var body: some View {
        Group {
            if let p = point {
                filled(p)
            } else if armed {
                prompt
            }
        }
        .animation(.easeOut(duration: 0.15), value: point?.elapsed)
    }

    private var prompt: some View {
        Text("DRAG ALONG THE ROUTE")
            .font(.dripStat(10))
            .foregroundStyle(Color.drip.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.drip.cardBackground.opacity(0.94), in: Capsule())
            .overlay(Capsule().stroke(Color.drip.divider, lineWidth: 1))
    }

    private func filled(_ p: RouteScrubPoint) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                cell(
                    label: "PACE",
                    value: p.paceSec.map { rr_pace($0, km: km) } ?? "—",
                    unit: km ? "/km" : "/mi",
                    tint: Color.drip.paceFast
                )
                if hasHR {
                    divider
                    cell(
                        label: "HR",
                        value: p.hr.map { "\(Int($0.rounded()))" } ?? "—",
                        unit: "bpm",
                        tint: Color.drip.coral
                    )
                }
            }
            // Where you are on the run. Without this the numbers float free —
            // a pace with no position doesn't tell you anything.
            Text("\(rr_dist(p.distanceMeters / 1609.344, km: km)) IN · \(rr_clock(p.elapsed)) ELAPSED")
                .font(.dripStat(9))
                .foregroundStyle(Color.drip.textTertiary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(Color.drip.cardBackground.opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.drip.divider, lineWidth: 1))
        .shadow(color: .black.opacity(0.14), radius: 10, y: 3)
    }

    private func cell(label: String, value: String, unit: String, tint: Color) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.dripStat(9))
                .foregroundStyle(Color.drip.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.dripStat(26))
                    .foregroundStyle(tint)
                    .monospacedDigit()
                Text(unit)
                    .font(.dripStat(10))
                    .foregroundStyle(Color.drip.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.drip.divider)
            .frame(width: 1, height: 34)
    }
}

// MARK: - Marker glyphs

private struct EndpointDot: View {
    let fill: Color
    var body: some View {
        Circle()
            .fill(fill)
            .frame(width: 14, height: 14)
            .overlay(Circle().stroke(.white, lineWidth: 2.5))
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
    }
}

private struct RepPin: View {
    let label: String
    var body: some View {
        Text(label)
            .font(.dripStat(9))
            .foregroundStyle(Color.drip.textPrimary)
            .frame(width: 18, height: 18)
            .background(Color.white, in: Circle())
            .overlay(Circle().stroke(Color.drip.textPrimary, lineWidth: 1.4))
            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
    }
}

private struct MileTick: View {
    let label: String
    var body: some View {
        Text(label)
            .font(.dripStat(8))
            .foregroundStyle(Color.drip.textSecondary)
            .frame(width: 14, height: 14)
            .background(Color.drip.cardBackgroundElevated, in: Circle())
            .overlay(Circle().stroke(Color.drip.divider, lineWidth: 1))
    }
}

// MARK: - Pace segment

/// One short colored stretch of the route. Built once, never recomputed.
struct RouteSegment: Identifiable {
    let id: Int
    let coords: [CLLocationCoordinate2D]
    let color: Color
}

// MARK: - Editorial projection

/// Raw geographic bounds of a route.
struct RouteBBox {
    let minLat: Double
    let maxLat: Double
    let minLon: Double
    let maxLon: Double
    var midLat: Double { (minLat + maxLat) / 2 }
}

/// Projects GPS coordinates into a view's pixel space for the inline,
/// tile-free route drawing. Aspect-preserving (longitude compressed by
/// cos(latitude)), centered, and y-flipped so north is up. Rebuilt per
/// layout pass from the current view size — cheap, keeps no allocations.
struct RouteProjection {
    private let minLat: Double
    private let minLon: Double
    private let lonScale: Double
    private let geoH: Double
    private let scale: Double
    private let offX: Double
    private let offY: Double

    init(bbox: RouteBBox, size: CGSize, inset: CGFloat) {
        minLat = bbox.minLat
        minLon = bbox.minLon
        lonScale = cos(bbox.midLat * .pi / 180)

        let geoW = max((bbox.maxLon - bbox.minLon) * lonScale, 1e-9)
        geoH = max(bbox.maxLat - bbox.minLat, 1e-9)

        let availW = max(Double(size.width) - Double(inset) * 2, 1)
        let availH = max(Double(size.height) - Double(inset) * 2, 1)

        // Degenerate span (indoor GPS jitter that slipped past the point-count
        // guard): collapse everything to the center rather than exploding the
        // scale toward infinity.
        let tiny = (bbox.maxLat - bbox.minLat) < 1e-6 && (bbox.maxLon - bbox.minLon) < 1e-6
        if tiny {
            scale = 0
            offX = Double(inset) + availW / 2
            offY = Double(inset) + availH / 2
        } else {
            let sc = min(availW / geoW, availH / geoH)
            scale = sc
            offX = Double(inset) + (availW - geoW * sc) / 2
            offY = Double(inset) + (availH - geoH * sc) / 2
        }
    }

    func point(_ c: CLLocationCoordinate2D) -> CGPoint {
        let gx = (c.longitude - minLon) * lonScale
        let gy = (c.latitude - minLat)
        return CGPoint(
            x: offX + gx * scale,
            y: offY + (geoH - gy) * scale
        )
    }
}

// MARK: - Geometry & pace helpers

private extension RouteMapView {

    /// Even-stride downsample that always keeps the first and last point.
    static func downsample(_ locs: [CLLocation], maxPoints: Int) -> [CLLocation] {
        guard locs.count > maxPoints, maxPoints > 2 else { return locs }
        let stride = Double(locs.count - 1) / Double(maxPoints - 1)
        var out: [CLLocation] = []
        out.reserveCapacity(maxPoints)
        for i in 0..<maxPoints {
            out.append(locs[min(Int((Double(i) * stride).rounded()), locs.count - 1)])
        }
        return out
    }

    /// Pace (sec/mile) for the segment ending at each index, smoothed.
    /// Element 0 mirrors element 1. Uses distance/time so it is source-agnostic.
    static func segmentPaces(_ locs: [CLLocation]) -> [Double] {
        guard locs.count > 1 else { return [] }
        var raw = [Double](repeating: 0, count: locs.count)
        for i in 1..<locs.count {
            let meters = locs[i].distance(from: locs[i - 1])
            let dt = locs[i].timestamp.timeIntervalSince(locs[i - 1].timestamp)
            if meters > 0.3, dt > 0 {
                let speed = meters / dt                       // m/s
                raw[i] = min(1609.344 / speed, 1200)          // cap 20:00/mi
            } else {
                raw[i] = raw[i - 1]
            }
        }
        raw[0] = raw.count > 1 ? raw[1] : 0
        return movingAverage(raw, window: 5)
    }

    static func movingAverage(_ xs: [Double], window: Int) -> [Double] {
        guard window > 1, xs.count > window else { return xs }
        let half = window / 2
        return xs.indices.map { i in
            let lo = max(0, i - half), hi = min(xs.count - 1, i + half)
            var sum = 0.0
            for j in lo...hi { sum += xs[j] }
            return sum / Double(hi - lo + 1)
        }
    }

    /// 10th / 90th percentile bounds so a couple of outliers don't wash out
    /// the whole color scale.
    static func paceBounds(_ paces: [Double]) -> (lo: Double, hi: Double) {
        let valid = paces.filter { $0 > 0 }.sorted()
        guard valid.count > 4 else { return (0, 0) }
        let lo = valid[Int(Double(valid.count) * 0.10)]
        let hi = valid[Int(Double(valid.count) * 0.90)]
        return hi > lo ? (lo, hi) : (valid.first ?? 0, valid.last ?? 0)
    }

    static func buildSegments(
        _ locs: [CLLocation],
        paces: [Double],
        lo: Double,
        hi: Double,
        colored: Bool
    ) -> [RouteSegment] {
        guard locs.count > 1 else { return [] }

        // Quantize each segment's pace into a few color buckets, then MERGE
        // consecutive same-bucket segments into one multi-point polyline. This
        // keeps the pace gradient but collapses ~240 separate map overlays
        // (each its own MKOverlay → ~1000+ live allocations, the GeoGL /
        // CAMetalLayer churn) down to a few dozen — the single biggest cost of
        // rendering the route map. Uncolored routes become one polyline.
        let buckets = 8
        func bucket(_ i: Int) -> Int {
            guard colored, hi > lo else { return 0 }
            let t = min(max((paces[i] - lo) / (hi - lo), 0), 1)
            return min(Int(t * Double(buckets)), buckets)
        }
        func colorOf(_ i: Int) -> Color {
            colored ? paceColor(paces[i], lo: lo, hi: hi) : Color.drip.coral
        }

        var out: [RouteSegment] = []
        var runStart = 1
        var runBucket = bucket(1)
        var nextId = 0
        // A run spans segments [runStart ... end] → points [runStart-1 ... end].
        func flush(_ end: Int) {
            let coords = (runStart - 1...end).map { locs[$0].coordinate }
            out.append(RouteSegment(id: nextId, coords: coords, color: colorOf(runStart)))
            nextId += 1
        }
        if locs.count > 2 {
            for i in 2..<locs.count {
                let b = bucket(i)
                if b != runBucket {
                    flush(i - 1)
                    runStart = i
                    runBucket = b
                }
            }
        }
        flush(locs.count - 1)
        return out
    }

    /// Route trace rides the universal pace ramp (PaceSpectrum):
    /// slow (high sec/mi) → pale sky, fast (low sec/mi) → navy. Same color
    /// language as the pace charts — and blue holds up well against map
    /// greenery, unlike the old green end.
    static func paceColor(_ pace: Double, lo: Double, hi: Double) -> Color {
        guard hi > lo else { return Color.drip.coral }
        return PaceSpectrum.color(forPaceSec: pace, slowSec: hi, fastSec: lo)
    }

    /// A pin every whole mile, found by walking cumulative distance over the
    /// full-resolution cleaned track (not the downsampled one).
    static func buildMileMarkers(_ locs: [CLLocation]) -> [RouteMarker] {
        guard locs.count > 1 else { return [] }
        let mile = 1609.344
        var markers: [RouteMarker] = []
        var accum = 0.0
        var nextMile = 1
        for i in 1..<locs.count {
            accum += locs[i].distance(from: locs[i - 1])
            while accum >= Double(nextMile) * mile {
                markers.append(
                    RouteMarker(coordinate: locs[i].coordinate, label: "\(nextMile)", kind: .mile)
                )
                nextMile += 1
                if nextMile > 99 { return markers } // safety
            }
        }
        return markers
    }

    /// Raw lat/lon bounding box (mid-latitude derived on `RouteBBox`), used by
    /// the inline editorial projection.
    static func boundingBox(_ locs: [CLLocation]) -> RouteBBox {
        guard !locs.isEmpty else {
            return RouteBBox(minLat: 0, maxLat: 0, minLon: 0, maxLon: 0)
        }
        let lats = locs.map(\.coordinate.latitude)
        let lons = locs.map(\.coordinate.longitude)
        return RouteBBox(
            minLat: lats.min() ?? 0,
            maxLat: lats.max() ?? 0,
            minLon: lons.min() ?? 0,
            maxLon: lons.max() ?? 0
        )
    }

    static func boundingRegion(_ locs: [CLLocation]) -> MKCoordinateRegion {
        guard !locs.isEmpty else { return MKCoordinateRegion() }
        let lats = locs.map(\.coordinate.latitude)
        let lngs = locs.map(\.coordinate.longitude)
        let minLat = lats.min() ?? 0, maxLat = lats.max() ?? 0
        let minLng = lngs.min() ?? 0, maxLng = lngs.max() ?? 0
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLng + maxLng) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: (maxLat - minLat) * 1.35 + 0.0025,
            longitudeDelta: (maxLng - minLng) * 1.35 + 0.0025
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}
