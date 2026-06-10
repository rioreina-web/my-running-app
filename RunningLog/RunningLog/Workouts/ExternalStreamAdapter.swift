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

@MainActor
enum ExternalStreamAdapter {
    /// Load external_streams JSONB for a given training_logs row and convert to the
    /// same shape VitalWorkoutDetailView already consumes.
    static func load(forTrainingLogId id: UUID) async -> ExternalStreamBundle? {
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
    private static func parse(_ raw: Any) -> ExternalStreamBundle? {
        guard let dict = raw as? [String: Any] else { return nil }

        let streamsDict = dict["streams"] as? [String: Any]
        let metaDict = dict["meta"] as? [String: Any] ?? [:]

        let stream = streamsDict.flatMap(buildVitalStream)
        let route = streamsDict.flatMap(buildRoute) ?? []
        let meta = buildMeta(metaDict)

        return ExternalStreamBundle(stream: stream, route: route, meta: meta)
    }

    private static func buildVitalStream(from streams: [String: Any]) -> VitalWorkoutStream? {
        let time = streams["time"] as? [Int]
        let heartrate = streams["heartrate"] as? [Int]
        let altitude = streams["altitude"] as? [Double]
        let distance = streams["distance"] as? [Double]
        let velocity = streams["velocity_smooth"] as? [Double]
        let cadence = streams["cadence"] as? [Double]
        // Strava `temp` is integer °C; `watts` (power) may be Int or Double.
        let temp = (streams["temp"] as? [Double]) ?? (streams["temp"] as? [Int])?.map(Double.init)
        let power = (streams["watts"] as? [Double]) ?? (streams["watts"] as? [Int])?.map(Double.init)

        // latlng stream is [[lat, lng], [lat, lng], ...] — split into two parallel arrays
        var lat: [Double]? = nil
        var lng: [Double]? = nil
        if let pairs = streams["latlng"] as? [[Double]] {
            lat = pairs.compactMap { $0.count >= 2 ? $0[0] : nil }
            lng = pairs.compactMap { $0.count >= 2 ? $0[1] : nil }
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

    private static func buildRoute(from streams: [String: Any]) -> [CLLocation]? {
        guard let pairs = streams["latlng"] as? [[Double]], !pairs.isEmpty else {
            return nil
        }
        let altitudes = streams["altitude"] as? [Double]
        let times = streams["time"] as? [Int]
        let baseDate = Date()
        return pairs.enumerated().compactMap { (idx, pair) -> CLLocation? in
            guard pair.count >= 2 else { return nil }
            let alt = (altitudes != nil && idx < altitudes!.count) ? altitudes![idx] : 0
            let offset = (times != nil && idx < times!.count) ? TimeInterval(times![idx]) : TimeInterval(idx)
            return CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: pair[0], longitude: pair[1]),
                altitude: alt,
                horizontalAccuracy: 5,
                verticalAccuracy: 5,
                timestamp: baseDate.addingTimeInterval(offset)
            )
        }
    }

    private static func buildMeta(_ meta: [String: Any]) -> StreamMeta {
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
private struct SupabaseJSON: Decodable {
    let value: Any?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.value = Self.decodeAny(from: container)
    }

    private static func decodeAny(from c: SingleValueDecodingContainer) -> Any? {
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
