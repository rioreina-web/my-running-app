//
//  ExternalStreamsPayload.swift
//  RunningLog
//
//  Codable representation of the `training_logs.external_streams` JSONB
//  column. This is the *write* side of the same shape `ExternalStreamAdapter`
//  parses on read — i.e. `{ "streams": { time, heartrate, altitude,
//  distance, velocity_smooth, cadence, latlng }, "meta": { ... } }`.
//
//  Until now `external_streams` was only ever written by the `strava-test-pull`
//  edge function, so normally-synced runs had no sensor data and every
//  workout-detail surface (VitalWorkoutDetailView / WorkoutAnalysisView /
//  WorkoutAnalystView) fell back to its empty state. WorkoutSyncService now
//  populates this on insert so new syncs carry their telemetry.
//
//  Keys mirror ExternalStreamAdapter.buildVitalStream / buildMeta exactly —
//  if you rename one, rename it there too.
//

import Foundation

struct ExternalStreamsPayload: Codable {

    struct Streams: Codable {
        var time: [Int]?              // seconds from workout start
        var heartrate: [Int]?         // bpm
        var altitude: [Double]?       // meters
        var distance: [Double]?       // cumulative meters
        var velocitySmooth: [Double]? // m/s
        var cadence: [Double]?        // spm
        var temp: [Double]? = nil     // °C (Strava only)
        var power: [Double]? = nil    // watts
        var latlng: [[Double]]?       // [[lat, lng], ...]

        // `power` encodes as `watts` to match the Strava stream key the
        // reader (ExternalStreamAdapter.buildVitalStream) parses.
        enum CodingKeys: String, CodingKey {
            case time, heartrate, altitude, distance, cadence, temp, latlng
            case velocitySmooth = "velocity_smooth"
            case power = "watts"
        }
    }

    struct Meta: Codable {
        var averageHeartrate: Int?
        var maxHeartrate: Int?
        var totalElevationGain: Double?
        var calories: Double?
        var deviceName: String?

        enum CodingKeys: String, CodingKey {
            case averageHeartrate = "average_heartrate"
            case maxHeartrate = "max_heartrate"
            case totalElevationGain = "total_elevation_gain"
            case calories
            case deviceName = "device_name"
        }
    }

    var streams: Streams
    var meta: Meta

    /// True when at least one series carries usable data. Used to avoid
    /// writing an empty payload (which would still trip the "has data" UI).
    var hasUsableData: Bool {
        (streams.time?.isEmpty == false)
            || (streams.heartrate?.isEmpty == false)
            || (streams.distance?.isEmpty == false)
            || (streams.altitude?.isEmpty == false)
            || (streams.latlng?.isEmpty == false)
    }

    /// Build a payload directly from an already-fetched Vital stream
    /// (WorkoutSyncService fetches this when the workout has a vital id).
    /// Returns nil when the stream has nothing chartable.
    static func from(vitalStream s: VitalWorkoutStream, calories: Double?) -> ExternalStreamsPayload? {
        var latlng: [[Double]]? = nil
        if let lat = s.lat, let lng = s.lng, lat.count == lng.count, !lat.isEmpty {
            latlng = zip(lat, lng).map { [$0, $1] }
        }

        let streams = Streams(
            time: s.time,
            heartrate: s.heartrate,
            altitude: s.altitude,
            distance: s.distance,
            velocitySmooth: s.velocitySmooth,
            cadence: s.cadence,
            temp: s.temp,
            power: s.power,
            latlng: latlng
        )

        let hr = (s.heartrate ?? []).map(Double.init)
        let meta = Meta(
            averageHeartrate: hr.isEmpty ? nil : Int((hr.reduce(0, +) / Double(hr.count)).rounded()),
            maxHeartrate: hr.max().map { Int($0) },
            totalElevationGain: nil,
            calories: calories,
            deviceName: nil
        )

        let payload = ExternalStreamsPayload(streams: streams, meta: meta)
        return payload.hasUsableData ? payload : nil
    }
}
