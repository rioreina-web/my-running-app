//
//  AthletePaceProfile.swift
//  RunningLog
//
//  Mirrors one row of athlete_pace_profiles. Owns the six reference paces
//  (easy, marathon, half, 10K, 5K, mile) that plan generation resolves against
//  so every scheduled step ships with a concrete seconds/mile target.
//  Fetched and cached in memory by AthletePaceProfileService — never
//  persisted to SwiftData.
//

import Foundation

struct AthletePaceProfile: Codable, Equatable {
    let id: UUID
    let userId: UUID

    let goalRaceDistance: String?
    let goalTimeSeconds: Int?

    let easy: Pace?
    let marathon: Pace?
    let half: Pace?
    let tenK: Pace?
    let fiveK: Pace?
    let mile: Pace?

    let basedOnSnapshotId: UUID?
    let generatedAt: Date
    let updatedAt: Date

    // MARK: - Nested types

    struct Pace: Codable, Equatable {
        let secondsPerMile: Double
        let confidence: Confidence
        let sourceDate: Date
    }

    enum Confidence: String, Codable {
        case high
        case medium
        case low
    }

    // MARK: - Lookup

    /// Returns the pace for a named reference distance. Case-insensitive.
    /// Accepts: "easy", "mile", "5K", "10K", "half", "marathon".
    func pace(for distance: String) -> Pace? {
        switch distance.lowercased() {
        case "easy":     return easy
        case "mile":     return mile
        case "5k":       return fiveK
        case "10k":      return tenK
        case "half":     return half
        case "marathon": return marathon
        default:         return nil
        }
    }

    // MARK: - Codable (flat column layout)

    private enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case goalRaceDistance = "goal_race_distance"
        case goalTimeSeconds = "goal_time_seconds"

        case easyPaceSeconds = "easy_pace_seconds"
        case easyPaceConfidence = "easy_pace_confidence"
        case easyPaceSourceDate = "easy_pace_source_date"

        case marathonPaceSeconds = "marathon_pace_seconds"
        case marathonPaceConfidence = "marathon_pace_confidence"
        case marathonPaceSourceDate = "marathon_pace_source_date"

        case halfPaceSeconds = "half_pace_seconds"
        case halfPaceConfidence = "half_pace_confidence"
        case halfPaceSourceDate = "half_pace_source_date"

        case tenKPaceSeconds = "ten_k_pace_seconds"
        case tenKPaceConfidence = "ten_k_pace_confidence"
        case tenKPaceSourceDate = "ten_k_pace_source_date"

        case fiveKPaceSeconds = "five_k_pace_seconds"
        case fiveKPaceConfidence = "five_k_pace_confidence"
        case fiveKPaceSourceDate = "five_k_pace_source_date"

        case milePaceSeconds = "mile_pace_seconds"
        case milePaceConfidence = "mile_pace_confidence"
        case milePaceSourceDate = "mile_pace_source_date"

        case basedOnSnapshotId = "based_on_snapshot_id"
        case generatedAt = "generated_at"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.userId = try c.decode(UUID.self, forKey: .userId)
        self.goalRaceDistance = try c.decodeIfPresent(String.self, forKey: .goalRaceDistance)
        self.goalTimeSeconds = try c.decodeIfPresent(Int.self, forKey: .goalTimeSeconds)
        self.basedOnSnapshotId = try c.decodeIfPresent(UUID.self, forKey: .basedOnSnapshotId)
        self.generatedAt = try c.decode(Date.self, forKey: .generatedAt)
        self.updatedAt = try c.decode(Date.self, forKey: .updatedAt)

        self.easy = try Self.decodePace(c, .easyPaceSeconds, .easyPaceConfidence, .easyPaceSourceDate)
        self.marathon = try Self.decodePace(c, .marathonPaceSeconds, .marathonPaceConfidence, .marathonPaceSourceDate)
        self.half = try Self.decodePace(c, .halfPaceSeconds, .halfPaceConfidence, .halfPaceSourceDate)
        self.tenK = try Self.decodePace(c, .tenKPaceSeconds, .tenKPaceConfidence, .tenKPaceSourceDate)
        self.fiveK = try Self.decodePace(c, .fiveKPaceSeconds, .fiveKPaceConfidence, .fiveKPaceSourceDate)
        self.mile = try Self.decodePace(c, .milePaceSeconds, .milePaceConfidence, .milePaceSourceDate)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(userId, forKey: .userId)
        try c.encodeIfPresent(goalRaceDistance, forKey: .goalRaceDistance)
        try c.encodeIfPresent(goalTimeSeconds, forKey: .goalTimeSeconds)
        try c.encodeIfPresent(basedOnSnapshotId, forKey: .basedOnSnapshotId)
        try c.encode(generatedAt, forKey: .generatedAt)
        try c.encode(updatedAt, forKey: .updatedAt)

        try Self.encodePace(easy, &c, .easyPaceSeconds, .easyPaceConfidence, .easyPaceSourceDate)
        try Self.encodePace(marathon, &c, .marathonPaceSeconds, .marathonPaceConfidence, .marathonPaceSourceDate)
        try Self.encodePace(half, &c, .halfPaceSeconds, .halfPaceConfidence, .halfPaceSourceDate)
        try Self.encodePace(tenK, &c, .tenKPaceSeconds, .tenKPaceConfidence, .tenKPaceSourceDate)
        try Self.encodePace(fiveK, &c, .fiveKPaceSeconds, .fiveKPaceConfidence, .fiveKPaceSourceDate)
        try Self.encodePace(mile, &c, .milePaceSeconds, .milePaceConfidence, .milePaceSourceDate)
    }

    private static func decodePace(
        _ c: KeyedDecodingContainer<CodingKeys>,
        _ seconds: CodingKeys,
        _ confidence: CodingKeys,
        _ sourceDate: CodingKeys
    ) throws -> Pace? {
        guard let s = try c.decodeIfPresent(Double.self, forKey: seconds) else { return nil }
        let conf = try c.decodeIfPresent(Confidence.self, forKey: confidence) ?? .low
        let date = try c.decodeIfPresent(Date.self, forKey: sourceDate) ?? Date()
        return Pace(secondsPerMile: s, confidence: conf, sourceDate: date)
    }

    private static func encodePace(
        _ pace: Pace?,
        _ c: inout KeyedEncodingContainer<CodingKeys>,
        _ seconds: CodingKeys,
        _ confidence: CodingKeys,
        _ sourceDate: CodingKeys
    ) throws {
        try c.encodeIfPresent(pace?.secondsPerMile, forKey: seconds)
        try c.encodeIfPresent(pace?.confidence, forKey: confidence)
        try c.encodeIfPresent(pace?.sourceDate, forKey: sourceDate)
    }
}
