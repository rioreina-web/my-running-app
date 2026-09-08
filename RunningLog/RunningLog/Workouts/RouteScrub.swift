//
//  RouteScrub.swift
//  RunningLog
//
//  The data behind "drag your finger along the route and see what you were
//  doing right there."
//
//  `RouteScrubTrack` takes the same cleaned GPS track the map already draws,
//  and precomputes — ONCE, at init — everything the readout needs at any point
//  on the line:
//
//    • elapsed seconds from the start of the run
//    • cumulative distance (meters)
//    • instantaneous pace (sec/mile), smoothed, derived from the route's own
//      timestamps so it works for HealthKit and Strava runs alike
//    • heart rate, sampled from the workout's HR stream and aligned to the
//      route by elapsed time (nil when the run has no HR)
//
//  Nothing here allocates during a drag. `nearestIndex(to:)` is a plain linear
//  scan over a few hundred points using squared planar distance (no sqrt, no
//  CLLocation objects) — cheap enough to run on every touch-moved event at
//  60fps, which is what makes the scrub feel glued to your finger.
//

import CoreLocation
import Foundation

// MARK: - One point on the scrubbable track

/// A single scrub stop: where you were, when, and what you were doing.
struct RouteScrubPoint {
    let coordinate: CLLocationCoordinate2D
    /// Seconds since the first GPS point of this run.
    let elapsed: Double
    /// Cumulative distance from the start, in meters.
    let distanceMeters: Double
    /// Instantaneous pace in seconds per mile. `nil` when the athlete was
    /// stopped or the GPS was too noisy to trust at this point.
    let paceSec: Double?
    /// Heart rate in BPM at this moment, or `nil` if the run has no HR data.
    let hr: Double?
}

// MARK: - The track

/// Precomputed scrub data for one run's route.
///
/// Built once per run (in `RouteMapView.init`, alongside the segments and mile
/// markers) and then read-only forever, so panning, zooming and scrubbing
/// never trigger recomputation.
struct RouteScrubTrack {

    let points: [RouteScrubPoint]

    /// True when at least one point has a heart rate — used to decide whether
    /// the readout shows an HR cell at all, rather than an empty dash.
    let hasHR: Bool

    var isEmpty: Bool { points.count < 2 }

    /// Total distance of the scrubbable track, in miles.
    var totalMiles: Double { (points.last?.distanceMeters ?? 0) / 1609.344 }

    // Flat coordinate arrays kept alongside `points` purely for the hit test —
    // scanning two `[Double]` is markedly faster than reaching through structs
    // on every touch event.
    private let lats: [Double]
    private let lons: [Double]
    /// Longitude degrees are narrower than latitude degrees away from the
    /// equator; squaring without this makes the hit test biased east-west.
    private let lonScale: Double

    // MARK: Build

    /// - Parameters:
    ///   - route: the cleaned GPS track (already sanitized by `RouteSanitizer`).
    ///   - hrTimes: HR stream sample times, in seconds from the workout start.
    ///   - hrValues: HR stream values in BPM, parallel to `hrTimes`.
    ///   - maxPoints: cap on scrub resolution. ~600 gives a point every few
    ///     seconds on a long run — finer than a fingertip can resolve, and
    ///     still a trivially fast linear scan.
    init(
        route: [CLLocation],
        hrTimes: [Double] = [],
        hrValues: [Double] = [],
        maxPoints: Int = 600
    ) {
        let src = RouteScrubTrack.downsample(route, maxPoints: maxPoints)

        guard src.count > 1, let t0 = src.first?.timestamp else {
            points = []
            hasHR = false
            lats = []
            lons = []
            lonScale = 1
            return
        }

        // Elapsed + cumulative distance in one pass.
        var elapsed = [Double](repeating: 0, count: src.count)
        var cumDist = [Double](repeating: 0, count: src.count)
        var rawPace = [Double?](repeating: nil, count: src.count)

        for i in 1 ..< src.count {
            elapsed[i] = src[i].timestamp.timeIntervalSince(t0)
            let meters = src[i].distance(from: src[i - 1])
            cumDist[i] = cumDist[i - 1] + meters
            let dt = elapsed[i] - elapsed[i - 1]
            // Below ~0.3 m of movement the fix is noise, not running; above
            // 20:00/mi the athlete has effectively stopped (light, water
            // fountain) and a "pace" there would be a lie.
            if meters > 0.3, dt > 0 {
                let speed = meters / dt                       // m/s
                let pace = 1609.344 / speed                    // sec/mile
                rawPace[i] = pace <= 1200 ? pace : nil
            }
        }
        rawPace[0] = rawPace.count > 1 ? rawPace[1] : nil

        // Smooth the pace over a ±2-sample window. Raw GPS pace is jumpy
        // enough that an unsmoothed readout flickers by 30s/mi while your
        // finger sits still — the smoothing is what makes the number readable.
        let smoothPace = RouteScrubTrack.smooth(rawPace, half: 2)

        // Align HR to the route by elapsed time. Both clocks start at the
        // workout start, so a straight lookup works; `hrAt` interpolates
        // between the two nearest samples for a continuous readout.
        let cleanHRTimes: [Double]
        let cleanHRValues: [Double]
        if hrTimes.count == hrValues.count, hrTimes.count > 1 {
            cleanHRTimes = hrTimes
            cleanHRValues = hrValues
        } else {
            cleanHRTimes = []
            cleanHRValues = []
        }

        var built: [RouteScrubPoint] = []
        built.reserveCapacity(src.count)
        var sawHR = false
        var cursor = 0                    // HR lookup walks forward, never rescans

        for i in 0 ..< src.count {
            var bpm: Double?
            if !cleanHRTimes.isEmpty {
                let (v, next) = RouteScrubTrack.hrAt(
                    elapsed[i], times: cleanHRTimes, values: cleanHRValues, from: cursor
                )
                cursor = next
                if let v, v > 20, v < 250 {   // guard against sensor dropouts
                    bpm = v
                    sawHR = true
                }
            }
            built.append(
                RouteScrubPoint(
                    coordinate: src[i].coordinate,
                    elapsed: elapsed[i],
                    distanceMeters: cumDist[i],
                    paceSec: smoothPace[i],
                    hr: bpm
                )
            )
        }

        points = built
        hasHR = sawHR
        lats = src.map(\.coordinate.latitude)
        lons = src.map(\.coordinate.longitude)
        let midLat = ((lats.min() ?? 0) + (lats.max() ?? 0)) / 2
        lonScale = cos(midLat * .pi / 180)
    }

    // MARK: Hit test

    /// Index of the route point closest to a tapped/dragged coordinate.
    ///
    /// Squared planar distance in degree space (longitude compressed by
    /// cos(lat)) — no sqrt, no allocation. Over a few hundred points this is
    /// microseconds, so it can run on every touch-moved event.
    func nearestIndex(to coord: CLLocationCoordinate2D) -> Int? {
        guard !lats.isEmpty else { return nil }
        var bestIdx = 0
        var bestDist = Double.greatestFiniteMagnitude
        for i in lats.indices {
            let dLat = lats[i] - coord.latitude
            let dLon = (lons[i] - coord.longitude) * lonScale
            let d = dLat * dLat + dLon * dLon
            if d < bestDist {
                bestDist = d
                bestIdx = i
            }
        }
        return bestIdx
    }

    /// Safe indexed access for the readout.
    func point(at index: Int) -> RouteScrubPoint? {
        guard index >= 0, index < points.count else { return nil }
        return points[index]
    }

    // MARK: Helpers

    /// Even-stride downsample that always keeps the first and last fix, so the
    /// scrub track starts and ends exactly where the drawn route does.
    private static func downsample(_ locs: [CLLocation], maxPoints: Int) -> [CLLocation] {
        guard locs.count > maxPoints, maxPoints > 2 else { return locs }
        let stride = Double(locs.count - 1) / Double(maxPoints - 1)
        var out: [CLLocation] = []
        out.reserveCapacity(maxPoints)
        for i in 0 ..< maxPoints {
            out.append(locs[min(Int((Double(i) * stride).rounded()), locs.count - 1)])
        }
        return out
    }

    /// Moving average that skips `nil` (stopped) samples rather than treating
    /// them as zero, which would drag the neighbouring paces toward nonsense.
    private static func smooth(_ xs: [Double?], half: Int) -> [Double?] {
        guard xs.count > 2 * half + 1 else { return xs }
        return xs.indices.map { i in
            let lo = max(0, i - half), hi = min(xs.count - 1, i + half)
            var sum = 0.0, n = 0
            for j in lo ... hi {
                if let v = xs[j] { sum += v; n += 1 }
            }
            return n > 0 ? sum / Double(n) : nil
        }
    }

    /// Linearly interpolated HR at `t` seconds, resuming the search from
    /// `start` so a full forward sweep of the route stays O(n + m) overall
    /// rather than O(n · m).
    private static func hrAt(
        _ t: Double,
        times: [Double],
        values: [Double],
        from start: Int
    ) -> (value: Double?, cursor: Int) {
        guard !times.isEmpty else { return (nil, start) }
        if t <= times[0] { return (values[0], 0) }
        if t >= times[times.count - 1] { return (values[values.count - 1], times.count - 1) }

        var i = min(max(start, 0), times.count - 1)
        // The route is walked forward, so the cursor almost always advances by
        // a step or two. Rewind only if a caller jumps backwards.
        while i > 0, times[i] > t { i -= 1 }
        while i + 1 < times.count, times[i + 1] < t { i += 1 }

        guard i + 1 < times.count else { return (values[i], i) }
        let span = times[i + 1] - times[i]
        guard span > 0 else { return (values[i], i) }
        let f = (t - times[i]) / span
        return (values[i] + (values[i + 1] - values[i]) * f, i)
    }
}
