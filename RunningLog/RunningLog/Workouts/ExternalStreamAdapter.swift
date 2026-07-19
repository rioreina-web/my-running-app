//
//  ExternalStreamAdapter.swift
//  RunningLog
//
//  Source-agnostic loader for workout streams stored in training_logs.external_streams.
//  Currently supports Strava shape (rows that arrived via the now-removed
//  strava-test-pull dev function plus any future ingestion path emitting the
//  same shape). HealthKit bundles can be added by producing the same format.
//
//  Output reuses VitalWorkoutStream so the existing chart + map views work untouched.
//

import CoreLocation
import Foundation
import Supabase
import os

/// Everything a workout detail view needs beyond the TrainingLog row itself.
struct ExternalStreamBundle {
    let stream: VitalWorkoutStream?      // time-series data for charts
    let route: [CLLocation]              // GPS route for map
    let meta: StreamMeta                 // workout-level stats (avg HR, calories, etc.)
}

struct StreamMeta {
    var averageHr: Int?
    var maxHr: Int?
    var averageCadence: Double?
    var averageWatts: Double?
    var maxWatts: Double?
    var averageTemp: Double?
    var calories: Double?
    var totalElevationGain: Double?
    var sufferScore: Double?
    var perceivedExertion: Double?
    var deviceName: String?
    var description: String?
}

/// One lap/split/rep, distilled from `external_streams.laps` for the
/// day-detail pace-bar strip. Strava records laps per auto-lap (often 1km
/// or 1mi) or per manually-pressed rep, so this is the rep-level split
/// structure when it exists.
struct WorkoutLap {
    let distanceMiles: Double
    let paceSeconds: Double      // sec/mi
    let avgHeartRate: Int?
}

// NOTE: intentionally NOT @MainActor. This adapter pulls the full
// `external_streams` blob (several thousand GPS/HR/pace points) and decodes +
// parses it through SupabaseJSON — multi-MB, multi-second work. Running it on
// the main actor froze the whole UI (a ~20s gesture-gate stall while opening a
// workout). All callers already `await` these methods and hop to the main
// actor themselves for state updates, so this work belongs off the main thread.
enum ExternalStreamAdapter {
    /// Load external_streams JSONB for a given training_logs row and convert to the
    /// same shape VitalWorkoutDetailView already consumes.
    nonisolated static func load(forTrainingLogId id: UUID) async -> ExternalStreamBundle? {
        struct Row: Decodable {
            let external_streams: SupabaseJSON?
        }

        do {
            let rows: [Row] = try await supabase
                .from("training_logs")
                .select("external_streams")
                .eq("id", value: id.uuidString)
                .limit(1)
                .execute()
                .value

            guard let raw = rows.first?.external_streams?.value else {
                return nil
            }
            return parse(raw)
        } catch {
            Log.app.error("ExternalStreamAdapter load failed: \(error)")
            return nil
        }
    }

    /// Load just the lap/split/rep list for a row, distilled to the fields
    /// the pace-bar strip needs. Returns nil when the row has no laps.
    ///
    /// Selects ONLY the `laps` JSON path, not the whole `external_streams`
    /// blob — the streams arrays (heartrate/velocity/latlng) run to several
    /// thousand points each and would otherwise be transferred and decoded
    /// on the main actor just to read ~20 laps.
    nonisolated static func loadLaps(forTrainingLogId id: UUID) async -> [WorkoutLap]? {
        struct Row: Decodable {
            let laps: SupabaseJSON?
        }
        do {
            let rows: [Row] = try await supabase
                .from("training_logs")
                .select("laps:external_streams->laps")
                .eq("id", value: id.uuidString)
                .limit(1)
                .execute()
                .value
            guard let laps = rows.first?.laps?.value as? [Any] else {
                return nil
            }
            let out: [WorkoutLap] = laps.compactMap { item in
                guard let lap = item as? [String: Any] else { return nil }
                let distMeters = asDouble(lap["distance"]) ?? 0
                // Prefer average_speed; fall back to distance / moving_time.
                let speed = asDouble(lap["average_speed"]) ?? 0
                let movingTime = asDouble(lap["moving_time"]) ?? 0
                let paceSec: Double
                if speed > 0 {
                    paceSec = 1609.34 / speed
                } else if distMeters > 0, movingTime > 0 {
                    paceSec = movingTime / (distMeters / 1609.34)
                } else {
                    return nil
                }
                guard distMeters > 0, paceSec > 0 else { return nil }
                let hr = asDouble(lap["average_heartrate"]).map { Int($0.rounded()) }
                return WorkoutLap(distanceMiles: distMeters / 1609.34,
                                  paceSeconds: paceSec,
                                  avgHeartRate: hr)
            }
            return out.isEmpty ? nil : out
        } catch {
            Log.app.error("ExternalStreamAdapter loadLaps failed: \(error)")
            return nil
        }
    }

    nonisolated private static func asDouble(_ v: Any?) -> Double? {
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        return nil
    }

    /// Coerce a JSON array (decoded by `SupabaseJSON` into a mixed `[Any]` of
    /// `Int`/`Double`) into `[Double]`, element by element. Returns nil only
    /// when the value isn't an array or carries no numeric elements — never
    /// because of Int/Double mixing.
    nonisolated private static func doubleArray(_ v: Any?) -> [Double]? {
        if let d = v as? [Double] { return d }
        guard let arr = v as? [Any] else { return nil }
        let out = arr.compactMap { asDouble($0) }
        return out.isEmpty ? nil : out
    }

    /// Coerce a JSON array into `[Int]`, element by element (rounding any
    /// Double members). Same rationale as `doubleArray`.
    nonisolated private static func intArray(_ v: Any?) -> [Int]? {
        if let i = v as? [Int] { return i }
        guard let arr = v as? [Any] else { return nil }
        let out: [Int] = arr.compactMap { el in
            if let i = el as? Int { return i }
            if let d = el as? Double { return Int(d.rounded()) }
            return nil
        }
        return out.isEmpty ? nil : out
    }

    // MARK: - Parser

    /// Parse a Strava-shaped stream payload. Shape:
    /// {
    ///   source: "strava",
    ///   activity_id: Int,
    ///   streams: { time: [Int], heartrate: [Int], latlng: [[lat, lng]], altitude: [Double],
    ///              velocity_smooth: [Double], cadence: [Double], distance: [Double],
    ///              grade_smooth: [Double], temp: [Double] },
    ///   laps: [...],
    ///   meta: { ... }
    /// }
    nonisolated private static func parse(_ raw: Any) -> ExternalStreamBundle? {
        guard let dict = raw as? [String: Any] else { return nil }

        let streamsDict = dict["streams"] as? [String: Any]
        let metaDict = dict["meta"] as? [String: Any] ?? [:]

        let stream = streamsDict.flatMap(buildVitalStream)
        let route = RouteSanitizer.clean(streamsDict.flatMap(buildRoute) ?? [])
        let meta = buildMeta(metaDict)

        return ExternalStreamBundle(stream: stream, route: route, meta: meta)
    }

    nonisolated private static func buildVitalStream(from streams: [String: Any]) -> VitalWorkoutStream? {
        // IMPORTANT: `SupabaseJSON` decodes every whole-number JSON value as
        // `Int` (it tries Int before Double). So a numeric stream like
        // `[0, 3.2, 5.1, …]` comes back as a *mixed* `[Int, Double, …]`, and a
        // blanket `as? [Double]` cast on a mixed array returns nil — silently
        // dropping distance / velocity / cadence (which all contain zeros and
        // whole numbers) while heartrate (pure Int) survived. That was the
        // root cause of "0 SPLITS" + empty pace/cadence on Strava workouts.
        // Coerce element-wise instead of casting the whole array.
        let time = intArray(streams["time"])
        let heartrate = intArray(streams["heartrate"])
        let altitude = doubleArray(streams["altitude"])
        let distance = doubleArray(streams["distance"])
        let velocity = doubleArray(streams["velocity_smooth"])
        let cadence = doubleArray(streams["cadence"])
        // Strava `temp` is integer °C; `watts` (power) may be Int or Double.
        let temp = doubleArray(streams["temp"])
        let power = doubleArray(streams["watts"])

        // latlng stream is [[lat, lng], [lat, lng], ...] — split into two parallel arrays
        var lat: [Double]? = nil
        var lng: [Double]? = nil
        if let pairs = streams["latlng"] as? [Any] {
            let coords: [(Double, Double)] = pairs.compactMap { pair in
                guard let p = pair as? [Any], p.count >= 2,
                      let a = asDouble(p[0]), let b = asDouble(p[1]) else { return nil }
                return (a, b)
            }
            if !coords.isEmpty {
                lat = coords.map(\.0)
                lng = coords.map(\.1)
            }
        }

        // Nothing usable? Return nil so callers can show an empty state.
        let anyPresent = time != nil || heartrate != nil || altitude != nil
            || velocity != nil || cadence != nil || lat != nil
        guard anyPresent else { return nil }

        return VitalWorkoutStream(
            time: time,
            heartrate: heartrate,
            lat: lat,
            lng: lng,
            altitude: altitude,
            distance: distance,
            velocitySmooth: velocity,
            cadence: cadence,
            temp: temp,
            rawPower: power?.map { Double?.some($0) }
        )
    }

    nonisolated private static func buildRoute(from streams: [String: Any]) -> [CLLocation]? {
        guard let rawPairs = streams["latlng"] as? [Any], !rawPairs.isEmpty else {
            return nil
        }
        let altitudes = doubleArray(streams["altitude"])
        let times = intArray(streams["time"])
        let baseDate = Date()
        return rawPairs.enumerated().compactMap { (idx, pair) -> CLLocation? in
            guard let p = pair as? [Any], p.count >= 2,
                  let lat = asDouble(p[0]), let lng = asDouble(p[1]) else { return nil }
            let alt = (altitudes != nil && idx < altitudes!.count) ? altitudes![idx] : 0
            let offset = (times != nil && idx < times!.count) ? TimeInterval(times![idx]) : TimeInterval(idx)
            return CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                altitude: alt,
                horizontalAccuracy: 5,
                verticalAccuracy: 5,
                timestamp: baseDate.addingTimeInterval(offset)
            )
        }
    }

    nonisolated private static func buildMeta(_ meta: [String: Any]) -> StreamMeta {
        func asDouble(_ v: Any?) -> Double? {
            if let d = v as? Double { return d }
            if let i = v as? Int { return Double(i) }
            return nil
        }
        func asInt(_ v: Any?) -> Int? {
            if let i = v as? Int { return i }
            if let d = v as? Double { return Int(d.rounded()) }
            return nil
        }

        return StreamMeta(
            averageHr: asInt(meta["average_heartrate"]),
            maxHr: asInt(meta["max_heartrate"]),
            averageCadence: asDouble(meta["average_cadence"]),
            averageWatts: asDouble(meta["average_watts"]),
            maxWatts: asDouble(meta["max_watts"]),
            averageTemp: asDouble(meta["average_temp"]),
            calories: asDouble(meta["calories"]),
            totalElevationGain: asDouble(meta["total_elevation_gain"]),
            sufferScore: asDouble(meta["suffer_score"]),
            perceivedExertion: asDouble(meta["perceived_exertion"]),
            deviceName: meta["device_name"] as? String,
            description: meta["description"] as? String
        )
    }
}

// Supabase Swift SDK represents JSONB as a `JSONValue`-ish type that decodes into
// common Foundation types. We wrap it so we can pull out the raw dictionary.
private nonisolated struct SupabaseJSON: Decodable {
    let value: Any?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.value = Self.decodeAny(from: container)
    }

    nonisolated private static func decodeAny(from c: SingleValueDecodingContainer) -> Any? {
        if c.decodeNil() { return nil }
        if let b = try? c.decode(Bool.self) { return b }
        if let i = try? c.decode(Int.self) { return i }
        if let d = try? c.decode(Double.self) { return d }
        if let s = try? c.decode(String.self) { return s }
        if let arr = try? c.decode([SupabaseJSON].self) { return arr.compactMap(\.value) }
        if let obj = try? c.decode([String: SupabaseJSON].self) {
            return obj.mapValues { $0.value as Any }
        }
        return nil
    }
}
