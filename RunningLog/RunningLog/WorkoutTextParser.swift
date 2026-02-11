//
//  WorkoutTextParser.swift
//  RunningLog
//
//  Extracts structured workout data from natural language text.
//  Handles voice transcriptions like "ran 12 x 400m at 67 seconds with 90s rest"
//

import Foundation

// MARK: - Extracted Workout Models

/// Structured representation of an interval set extracted from text
struct ExtractedIntervalSet: Codable, Equatable {
    let repetitions: Int
    let distance: ExtractedDistance
    let targetTime: ExtractedTime?      // e.g., "67 seconds" per rep
    let targetPace: ExtractedPace?      // e.g., "6:15/mi" pace
    let restDuration: ExtractedTime?    // e.g., "90 seconds" rest
    let restType: RestType?             // jog, walk, standing

    enum RestType: String, Codable {
        case jog
        case walk
        case standing
        case unknown
    }

    /// Total work volume in meters
    var totalVolumeMeters: Double {
        Double(repetitions) * distance.meters
    }

    /// Total work volume in miles
    var totalVolumeMiles: Double {
        totalVolumeMeters / 1609.34
    }

    /// Formatted description
    var description: String {
        var parts = ["\(repetitions)x\(distance.description)"]
        if let time = targetTime {
            parts.append("@ \(time.description)")
        } else if let pace = targetPace {
            parts.append("@ \(pace.description)")
        }
        if let rest = restDuration {
            parts.append("w/ \(rest.description) rest")
        }
        return parts.joined(separator: " ")
    }
}

/// Distance with unit
struct ExtractedDistance: Codable, Equatable {
    let value: Double
    let unit: DistanceUnit

    enum DistanceUnit: String, Codable {
        case meters = "m"
        case kilometers = "km"
        case miles = "mi"
    }

    var meters: Double {
        switch unit {
        case .meters: return value
        case .kilometers: return value * 1000
        case .miles: return value * 1609.34
        }
    }

    var description: String {
        if unit == .meters && value >= 1000 {
            return "\(Int(value / 1000))K"
        }
        return "\(value.cleanString)\(unit.rawValue)"
    }
}

/// Time duration
struct ExtractedTime: Codable, Equatable {
    let seconds: Double

    init(seconds: Double) {
        self.seconds = seconds
    }

    init(minutes: Int, seconds: Int) {
        self.seconds = Double(minutes * 60 + seconds)
    }

    var description: String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        if mins > 0 {
            return "\(mins):\(String(format: "%02d", secs))"
        }
        return "\(Int(seconds))s"
    }
}

/// Running pace
struct ExtractedPace: Codable, Equatable {
    let secondsPerMile: Double

    var description: String {
        let mins = Int(secondsPerMile) / 60
        let secs = Int(secondsPerMile) % 60
        return "\(mins):\(String(format: "%02d", secs))/mi"
    }
}

/// Continuous effort (tempo, threshold, etc.)
struct ExtractedContinuousEffort: Codable, Equatable {
    let distance: ExtractedDistance?
    let duration: ExtractedTime?
    let targetPace: ExtractedPace?
    let effortType: EffortType

    enum EffortType: String, Codable {
        case tempo
        case threshold
        case steady
        case race
        case easy
        case marathon
        case halfMarathon
    }

    var description: String {
        var parts: [String] = [effortType.rawValue]
        if let dist = distance {
            parts.append(dist.description)
        } else if let dur = duration {
            parts.append(dur.description)
        }
        if let pace = targetPace {
            parts.append("@ \(pace.description)")
        }
        return parts.joined(separator: " ")
    }
}

/// Complete extracted workout data
struct ExtractedWorkoutData: Codable, Equatable {
    var intervalSets: [ExtractedIntervalSet] = []
    var continuousEfforts: [ExtractedContinuousEffort] = []
    var warmupDistance: ExtractedDistance?
    var cooldownDistance: ExtractedDistance?
    var rawText: String?

    var hasStructuredData: Bool {
        !intervalSets.isEmpty || !continuousEfforts.isEmpty
    }

    /// Total interval volume in miles
    var totalIntervalVolumeMiles: Double {
        intervalSets.reduce(0) { $0 + $1.totalVolumeMiles }
    }

    /// Summary description
    var summary: String {
        var parts: [String] = []
        for interval in intervalSets {
            parts.append(interval.description)
        }
        for effort in continuousEfforts {
            parts.append(effort.description)
        }
        return parts.isEmpty ? "No structured data" : parts.joined(separator: "; ")
    }
}

// MARK: - WorkoutTextParser

/// Parses natural language text to extract structured workout data
class WorkoutTextParser {

    static let shared = WorkoutTextParser()

    private init() {}

    // MARK: - Main Parse Function

    func parse(_ text: String) -> ExtractedWorkoutData {
        var result = ExtractedWorkoutData()
        result.rawText = text

        let lowercased = text.lowercased()

        // Extract interval sets
        result.intervalSets = extractIntervalSets(from: lowercased)

        // Extract continuous efforts (tempo, threshold, etc.)
        result.continuousEfforts = extractContinuousEfforts(from: lowercased)

        // Extract warmup/cooldown
        result.warmupDistance = extractWarmup(from: lowercased)
        result.cooldownDistance = extractCooldown(from: lowercased)

        return result
    }

    // MARK: - Interval Extraction

    private func extractIntervalSets(from text: String) -> [ExtractedIntervalSet] {
        var sets: [ExtractedIntervalSet] = []

        // Pattern 1: "12 x 400m at 67 seconds with 90s rest"
        // Pattern 2: "12x400m @ 67s w/ 90s rest"
        // Pattern 3: "5 x 1K at 3:20 with 2 min jog"
        // Pattern 4: "8 x 200m in 32-34 seconds"
        // Pattern 5: "4x1mi at 5:45 with 3min rest"

        // Main interval pattern: [reps] x [distance] [optional: at/in/@ time/pace] [optional: with/w/ rest]
        let intervalPattern = #"(\d+)\s*[x×]\s*(\d+(?:\.\d+)?)\s*(m(?:eters?)?|k(?:m)?|mi(?:les?)?|meters?)\s*(?:(?:at|in|@)\s*([0-9:]+)\s*(seconds?|s|mins?|minutes?|/mi(?:le)?)?)?(?:\s*(?:with|w/)\s*(\d+(?:\.\d+)?)\s*(s(?:ec(?:onds?)?)?|m(?:in(?:utes?)?)?)\s*(jog|walk|rest|standing)?)?"#

        if let regex = try? NSRegularExpression(pattern: intervalPattern, options: [.caseInsensitive]) {
            let range = NSRange(text.startIndex..., in: text)
            let matches = regex.matches(in: text, range: range)

            for match in matches {
                if let intervalSet = parseIntervalMatch(match, in: text) {
                    sets.append(intervalSet)
                }
            }
        }

        // Pattern for shorthand: "12x400" or "12 x 400"
        if sets.isEmpty {
            let shortPattern = #"(\d+)\s*[x×]\s*(\d+)"#
            if let regex = try? NSRegularExpression(pattern: shortPattern, options: []) {
                let range = NSRange(text.startIndex..., in: text)
                let matches = regex.matches(in: text, range: range)

                for match in matches {
                    if let repsRange = Range(match.range(at: 1), in: text),
                       let distRange = Range(match.range(at: 2), in: text),
                       let reps = Int(text[repsRange]),
                       let dist = Double(text[distRange]) {
                        // Infer unit from distance value
                        let unit: ExtractedDistance.DistanceUnit = dist >= 100 ? .meters : (dist <= 10 ? .kilometers : .meters)
                        let distance = ExtractedDistance(value: dist, unit: unit)
                        sets.append(ExtractedIntervalSet(
                            repetitions: reps,
                            distance: distance,
                            targetTime: nil,
                            targetPace: nil,
                            restDuration: nil,
                            restType: nil
                        ))
                    }
                }
            }
        }

        return sets
    }

    private func parseIntervalMatch(_ match: NSTextCheckingResult, in text: String) -> ExtractedIntervalSet? {
        guard match.numberOfRanges >= 4 else { return nil }

        // Reps
        guard let repsRange = Range(match.range(at: 1), in: text),
              let reps = Int(text[repsRange]) else { return nil }

        // Distance value
        guard let distValueRange = Range(match.range(at: 2), in: text),
              let distValue = Double(text[distValueRange]) else { return nil }

        // Distance unit
        guard let distUnitRange = Range(match.range(at: 3), in: text) else { return nil }
        let distUnitStr = String(text[distUnitRange]).lowercased()
        let distUnit = parseDistanceUnit(distUnitStr)
        let distance = ExtractedDistance(value: distValue, unit: distUnit)

        // Target time/pace (optional)
        var targetTime: ExtractedTime?
        var targetPace: ExtractedPace?

        if match.range(at: 4).location != NSNotFound,
           let timeRange = Range(match.range(at: 4), in: text) {
            let timeStr = String(text[timeRange])
            let unitStr = match.range(at: 5).location != NSNotFound
                ? (Range(match.range(at: 5), in: text).map { String(text[$0]) } ?? "")
                : ""

            if unitStr.contains("/mi") || unitStr.contains("mile") {
                // It's a pace
                if let pace = parseTimeString(timeStr) {
                    targetPace = ExtractedPace(secondsPerMile: pace)
                }
            } else {
                // It's a time per rep
                if let time = parseTimeString(timeStr) {
                    targetTime = ExtractedTime(seconds: time)
                }
            }
        }

        // Rest duration (optional)
        var restDuration: ExtractedTime?
        var restType: ExtractedIntervalSet.RestType?

        if match.range(at: 6).location != NSNotFound,
           let restValueRange = Range(match.range(at: 6), in: text),
           let restValue = Double(text[restValueRange]) {

            var restSeconds = restValue
            if match.range(at: 7).location != NSNotFound,
               let restUnitRange = Range(match.range(at: 7), in: text) {
                let restUnitStr = String(text[restUnitRange]).lowercased()
                if restUnitStr.starts(with: "m") {
                    restSeconds = restValue * 60
                }
            }
            restDuration = ExtractedTime(seconds: restSeconds)

            // Rest type
            if match.range(at: 8).location != NSNotFound,
               let restTypeRange = Range(match.range(at: 8), in: text) {
                let restTypeStr = String(text[restTypeRange]).lowercased()
                restType = parseRestType(restTypeStr)
            }
        }

        return ExtractedIntervalSet(
            repetitions: reps,
            distance: distance,
            targetTime: targetTime,
            targetPace: targetPace,
            restDuration: restDuration,
            restType: restType
        )
    }

    // MARK: - Continuous Effort Extraction

    private func extractContinuousEfforts(from text: String) -> [ExtractedContinuousEffort] {
        var efforts: [ExtractedContinuousEffort] = []

        // Pattern: "[distance] tempo/threshold at [pace]"
        // Pattern: "tempo [distance] at [pace]"
        // Pattern: "[duration] at marathon pace"

        let effortTypes = ["tempo", "threshold", "steady", "race", "marathon pace", "half marathon pace", "easy"]

        for effortType in effortTypes {
            // Pattern: "[distance] [type]" or "[type] [distance]"
            let patterns = [
                "(\(effortType))\\s+(\\d+(?:\\.\\d+)?)\\s*(mi(?:les?)?|k(?:m)?|m(?:eters?)?)?(?:\\s*(?:at|@)\\s*([0-9:]+)(?:/mi)?)?",
                "(\\d+(?:\\.\\d+)?)\\s*(mi(?:les?)?|k(?:m)?|m(?:eters?)?)?\\s*(\(effortType))(?:\\s*(?:at|@)\\s*([0-9:]+)(?:/mi)?)?"
            ]

            for pattern in patterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                    let range = NSRange(text.startIndex..., in: text)
                    let matches = regex.matches(in: text, range: range)

                    for match in matches {
                        if let effort = parseContinuousEffortMatch(match, in: text, type: effortType) {
                            efforts.append(effort)
                        }
                    }
                }
            }
        }

        return efforts
    }

    private func parseContinuousEffortMatch(_ match: NSTextCheckingResult, in text: String, type: String) -> ExtractedContinuousEffort? {
        var distanceValue: Double?
        var distanceUnit: ExtractedDistance.DistanceUnit = .miles
        var pace: ExtractedPace?

        // Extract groups
        for i in 1..<match.numberOfRanges {
            guard match.range(at: i).location != NSNotFound,
                  let range = Range(match.range(at: i), in: text) else { continue }

            let captured = String(text[range])

            if let dv = Double(captured) {
                distanceValue = dv
            } else if captured.contains(":") {
                if let paceSeconds = parseTimeString(captured) {
                    pace = ExtractedPace(secondsPerMile: paceSeconds)
                }
            } else if let unit = parseDistanceUnitOptional(captured) {
                distanceUnit = unit
            }
        }

        let effortType: ExtractedContinuousEffort.EffortType
        switch type.lowercased() {
        case "tempo": effortType = .tempo
        case "threshold": effortType = .threshold
        case "steady": effortType = .steady
        case "race": effortType = .race
        case "marathon pace": effortType = .marathon
        case "half marathon pace": effortType = .halfMarathon
        case "easy": effortType = .easy
        default: effortType = .tempo
        }

        let distance = distanceValue.map { ExtractedDistance(value: $0, unit: distanceUnit) }

        return ExtractedContinuousEffort(
            distance: distance,
            duration: nil,
            targetPace: pace,
            effortType: effortType
        )
    }

    // MARK: - Warmup/Cooldown Extraction

    private func extractWarmup(from text: String) -> ExtractedDistance? {
        let pattern = #"(?:warm(?:ed)?\s*up|wu)\s*(\d+(?:\.\d+)?)\s*(mi(?:les?)?|k(?:m)?|m(?:eters?)?)?"#
        return extractDistanceWithPattern(pattern, from: text)
    }

    private func extractCooldown(from text: String) -> ExtractedDistance? {
        let pattern = #"(?:cool(?:ed)?\s*down|cd)\s*(\d+(?:\.\d+)?)\s*(mi(?:les?)?|k(?:m)?|m(?:eters?)?)?"#
        return extractDistanceWithPattern(pattern, from: text)
    }

    private func extractDistanceWithPattern(_ pattern: String, from text: String) -> ExtractedDistance? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)

        guard let match = regex.firstMatch(in: text, range: range),
              let valueRange = Range(match.range(at: 1), in: text),
              let value = Double(text[valueRange]) else { return nil }

        var unit: ExtractedDistance.DistanceUnit = .miles
        if match.range(at: 2).location != NSNotFound,
           let unitRange = Range(match.range(at: 2), in: text) {
            unit = parseDistanceUnit(String(text[unitRange]))
        }

        return ExtractedDistance(value: value, unit: unit)
    }

    // MARK: - Helpers

    private func parseDistanceUnit(_ str: String) -> ExtractedDistance.DistanceUnit {
        let lower = str.lowercased()
        if lower.starts(with: "k") {
            return .kilometers
        } else if lower.starts(with: "mi") {
            return .miles
        }
        return .meters
    }

    private func parseDistanceUnitOptional(_ str: String) -> ExtractedDistance.DistanceUnit? {
        let lower = str.lowercased()
        if lower.starts(with: "k") {
            return .kilometers
        } else if lower.starts(with: "mi") {
            return .miles
        } else if lower.starts(with: "m") {
            return .meters
        }
        return nil
    }

    private func parseTimeString(_ str: String) -> Double? {
        // Handle "M:SS" or "MM:SS" format
        if str.contains(":") {
            let parts = str.split(separator: ":")
            if parts.count == 2,
               let mins = Int(parts[0]),
               let secs = Int(parts[1]) {
                return Double(mins * 60 + secs)
            }
        }
        // Handle plain seconds
        if let secs = Double(str) {
            return secs
        }
        return nil
    }

    private func parseRestType(_ str: String) -> ExtractedIntervalSet.RestType {
        switch str {
        case "jog": return .jog
        case "walk": return .walk
        case "standing": return .standing
        default: return .unknown
        }
    }
}

// MARK: - Double Extension

private extension Double {
    var cleanString: String {
        truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", self) : String(format: "%.1f", self)
    }
}
