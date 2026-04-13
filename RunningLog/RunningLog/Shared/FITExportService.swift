//
//  FITExportService.swift
//  RunningLog
//
//  Service for exporting planned workouts to Garmin FIT file format.
//

import Foundation
import os

// MARK: - FITExportService

/// Service for exporting workouts to Garmin-compatible .FIT files
///
/// Note: For full FIT SDK support, add the package dependency:
/// `github.com/garmin/fit-swift-sdk` (v21.0+)
///
/// This implementation provides a fallback that creates a workout file
/// that can be imported into Garmin Connect via the web interface.
final class FITExportService {
    // MARK: - Constants

    private let fileManager = FileManager.default

    // MARK: - Export Workout

    /// Exports a PlannedWorkout to a FIT file and returns the file URL
    /// - Parameters:
    ///   - workout: The workout to export
    ///   - racePaceSeconds: The user's marathon race pace in seconds per mile
    /// - Returns: URL to the exported file
    func exportWorkout(_ workout: PlannedWorkout, racePaceSeconds: Double) async throws -> URL {
        // Create filename with timestamp
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let sanitizedName = workout.name.replacingOccurrences(of: " ", with: "_")
        let filename = "\(sanitizedName)_\(timestamp).fit"

        // Get documents directory
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsPath.appendingPathComponent(filename)

        // Generate FIT file data
        let fitData = try generateFITData(for: workout, racePaceSeconds: racePaceSeconds)

        // Write to file
        try fitData.write(to: fileURL)

        Log.coach.info("Exported workout to: \(fileURL.path)")
        return fileURL
    }

    // MARK: - Generate FIT Data

    /// Generates FIT file binary data for a workout
    private func generateFITData(for workout: PlannedWorkout, racePaceSeconds: Double) throws -> Data {
        var data = Data()

        // FIT file header (14 bytes)
        data.append(contentsOf: createFITHeader())

        // File ID message
        data.append(contentsOf: createFileIDMessage())

        // Workout message
        data.append(contentsOf: createWorkoutMessage(workout))

        // Workout steps
        for (index, step) in workout.steps.enumerated() {
            data.append(contentsOf: createWorkoutStepMessage(step, index: index, racePaceSeconds: racePaceSeconds))
        }

        // Calculate and append CRC
        let crc = calculateCRC(data)
        data.append(UInt8(crc & 0xFF))
        data.append(UInt8((crc >> 8) & 0xFF))

        // Update header with data size
        let dataSize = UInt32(data.count - 14) // Exclude header
        data.replaceSubrange(4 ..< 8, with: withUnsafeBytes(of: dataSize.littleEndian) { Data($0) })

        return data
    }

    // MARK: - FIT Header

    private func createFITHeader() -> [UInt8] {
        var header = [UInt8]()

        // Header size (14 bytes for FIT 2.0)
        header.append(14)

        // Protocol version (2.0)
        header.append(0x20)

        // Profile version (21.60)
        header.append(contentsOf: [0x54, 0x08]) // Little endian: 2132

        // Data size placeholder (will be updated later)
        header.append(contentsOf: [0x00, 0x00, 0x00, 0x00])

        // Data type ".FIT"
        header.append(contentsOf: [0x2E, 0x46, 0x49, 0x54]) // ".FIT"

        // CRC of header (optional, set to 0)
        header.append(contentsOf: [0x00, 0x00])

        return header
    }

    // MARK: - File ID Message

    private func createFileIDMessage() -> [UInt8] {
        var message = [UInt8]()

        // Definition message for file_id (local message 0)
        message.append(0x40) // Definition message, local 0
        message.append(0x00) // Reserved
        message.append(0x00) // Architecture (little endian)
        message.append(contentsOf: [0x00, 0x00]) // Global message number: file_id (0)
        message.append(0x04) // Number of fields

        // Field 0: type (enum, 1 byte)
        message.append(contentsOf: [0x00, 0x01, 0x00])
        // Field 1: manufacturer (uint16, 2 bytes)
        message.append(contentsOf: [0x01, 0x02, 0x84])
        // Field 2: product (uint16, 2 bytes)
        message.append(contentsOf: [0x02, 0x02, 0x84])
        // Field 3: serial_number (uint32z, 4 bytes)
        message.append(contentsOf: [0x03, 0x04, 0x8C])

        // Data message for file_id
        message.append(0x00) // Data message, local 0
        message.append(0x05) // type: workout
        message.append(contentsOf: [0x01, 0x00]) // manufacturer: Garmin (1)
        message.append(contentsOf: [0x01, 0x00]) // product: 1
        message.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // serial_number: 0

        return message
    }

    // MARK: - Workout Message

    private func createWorkoutMessage(_ workout: PlannedWorkout) -> [UInt8] {
        var message = [UInt8]()

        // Definition message for workout (local message 1)
        message.append(0x41) // Definition message, local 1
        message.append(0x00) // Reserved
        message.append(0x00) // Architecture (little endian)
        message.append(contentsOf: [0x1A, 0x00]) // Global message number: workout (26)
        message.append(0x02) // Number of fields

        // Field 0: sport (enum, 1 byte)
        message.append(contentsOf: [0x04, 0x01, 0x00])
        // Field 1: num_valid_steps (uint16, 2 bytes)
        message.append(contentsOf: [0x06, 0x02, 0x84])

        // Data message for workout
        message.append(0x01) // Data message, local 1
        message.append(0x01) // sport: running
        let stepCount = UInt16(workout.steps.count)
        message.append(contentsOf: withUnsafeBytes(of: stepCount.littleEndian) { Array($0) })

        return message
    }

    // MARK: - Workout Step Message

    private func createWorkoutStepMessage(_ step: PlannedWorkoutStep, index: Int, racePaceSeconds: Double) -> [UInt8] {
        var message = [UInt8]()

        // Only add definition once (for first step)
        if index == 0 {
            // Definition message for workout_step (local message 2)
            message.append(0x42) // Definition message, local 2
            message.append(0x00) // Reserved
            message.append(0x00) // Architecture (little endian)
            message.append(contentsOf: [0x1B, 0x00]) // Global message number: workout_step (27)
            message.append(0x06) // Number of fields

            // Field 0: message_index (uint16, 2 bytes)
            message.append(contentsOf: [0xFE, 0x02, 0x84])
            // Field 1: duration_type (enum, 1 byte)
            message.append(contentsOf: [0x01, 0x01, 0x00])
            // Field 2: duration_value (uint32, 4 bytes)
            message.append(contentsOf: [0x02, 0x04, 0x86])
            // Field 3: target_type (enum, 1 byte)
            message.append(contentsOf: [0x03, 0x01, 0x00])
            // Field 4: target_value (uint32, 4 bytes)
            message.append(contentsOf: [0x04, 0x04, 0x86])
            // Field 5: intensity (enum, 1 byte)
            message.append(contentsOf: [0x05, 0x01, 0x00])
        }

        // Data message for workout_step
        message.append(0x02) // Data message, local 2

        // message_index
        let stepIndex = UInt16(index)
        message.append(contentsOf: withUnsafeBytes(of: stepIndex.littleEndian) { Array($0) })

        // duration_type and duration_value
        let (durationType, durationValue) = mapDuration(step)
        message.append(durationType)
        message.append(contentsOf: withUnsafeBytes(of: durationValue.littleEndian) { Array($0) })

        // target_type and target_value (pace target)
        let (targetType, targetValue) = mapTarget(step, racePaceSeconds: racePaceSeconds)
        message.append(targetType)
        message.append(contentsOf: withUnsafeBytes(of: targetValue.littleEndian) { Array($0) })

        // intensity
        let intensity = mapIntensity(step.stepType)
        message.append(intensity)

        return message
    }

    // MARK: - Helper Methods

    private func mapDuration(_ step: PlannedWorkoutStep) -> (UInt8, UInt32) {
        switch step.durationType {
        case .distanceKm:
            // distance type = 0, value in meters * 100
            let meters = step.durationValue * 1000
            return (0, UInt32(meters * 100))
        case .distanceMiles:
            // distance type = 0, value in meters * 100
            let meters = step.durationValue * 1609.34
            return (0, UInt32(meters * 100))
        case .distanceMeters:
            // distance type = 0, value in meters * 100
            return (0, UInt32(step.durationValue * 100))
        case .timeSeconds:
            // time type = 1, value in milliseconds
            return (1, UInt32(step.durationValue * 1000))
        case .open:
            // open type = 2, no value
            return (2, 0)
        }
    }

    private func mapTarget(_ step: PlannedWorkoutStep, racePaceSeconds: Double) -> (UInt8, UInt32) {
        // HR target takes priority over pace
        if let hr = step.targetHR {
            switch hr.mode {
            case .zone:
                if let zone = hr.zone {
                    // target_type = 3 (heart_rate_zone), value = zone number (1–5)
                    return (3, UInt32(zone))
                }
            case .bpmRange:
                // target_type = 1 (heart_rate), encode low in low 16 bits, high in upper 16 bits
                let low = UInt32(hr.bpmLow ?? 0)
                let high = UInt32(hr.bpmHigh ?? 255)
                return (1, (high << 16) | low)
            }
        }

        guard let intensity = step.targetPaceIntensity else {
            // No target, type = 0 (open)
            return (0, 0)
        }

        // Target type = 4 (speed), value in mm/s * 1000
        let paceSeconds = intensity.paceSeconds(forRacePace: racePaceSeconds)
        // Convert pace (sec/mile) to speed (m/s)
        let speedMps = 1609.34 / paceSeconds
        let speedValue = UInt32(speedMps * 1000)

        return (4, speedValue)
    }

    private func mapIntensity(_ stepType: PlannedWorkoutStep.StepType) -> UInt8 {
        switch stepType {
        case .warmup: return 1 // warmup
        case .active: return 0 // active
        case .rest: return 3 // rest
        case .recovery: return 2 // recovery
        case .cooldown: return 4 // cooldown
        }
    }

    // MARK: - CRC Calculation

    private func calculateCRC(_ data: Data) -> UInt16 {
        let crcTable: [UInt16] = [
            0x0000, 0xCC01, 0xD801, 0x1400, 0xF001, 0x3C00, 0x2800, 0xE401,
            0xA001, 0x6C00, 0x7800, 0xB401, 0x5000, 0x9C01, 0x8801, 0x4400,
        ]

        var crc: UInt16 = 0

        for byte in data {
            // Process low nibble
            var tmp = crcTable[Int(crc & 0xF)]
            crc = (crc >> 4) & 0x0FFF
            crc = crc ^ tmp ^ crcTable[Int(byte & 0xF)]

            // Process high nibble
            tmp = crcTable[Int(crc & 0xF)]
            crc = (crc >> 4) & 0x0FFF
            crc = crc ^ tmp ^ crcTable[Int((byte >> 4) & 0xF)]
        }

        return crc
    }
}

// MARK: - FIT Export Error

enum FITExportError: LocalizedError {
    case encodingFailed
    case fileWriteFailed
    case invalidWorkout

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode workout data"
        case .fileWriteFailed:
            return "Failed to write workout file"
        case .invalidWorkout:
            return "Invalid workout data"
        }
    }
}
