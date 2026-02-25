import Foundation
import os

// MARK: - App Logger

/// Centralized logging using os.Logger for better debugging and performance
enum Log {
    /// Logger for HealthKit operations
    static let health = Logger(subsystem: Bundle.main.bundleIdentifier ?? "PostRunDrip", category: "HealthKit")

    /// Logger for video playback and downloads
    static let video = Logger(subsystem: Bundle.main.bundleIdentifier ?? "PostRunDrip", category: "Video")

    /// Logger for weather service
    static let weather = Logger(subsystem: Bundle.main.bundleIdentifier ?? "PostRunDrip", category: "Weather")

    /// Logger for coaching/AI features
    static let coach = Logger(subsystem: Bundle.main.bundleIdentifier ?? "PostRunDrip", category: "Coach")

    /// Logger for goals and analysis
    static let goals = Logger(subsystem: Bundle.main.bundleIdentifier ?? "PostRunDrip", category: "Goals")

    /// Logger for content library
    static let content = Logger(subsystem: Bundle.main.bundleIdentifier ?? "PostRunDrip", category: "Content")

    /// Logger for database operations
    static let database = Logger(subsystem: Bundle.main.bundleIdentifier ?? "PostRunDrip", category: "Database")

    /// Logger for biomechanics analysis
    static let biomechanics = Logger(subsystem: Bundle.main.bundleIdentifier ?? "PostRunDrip", category: "Biomechanics")

    /// General app logger
    static let app = Logger(subsystem: Bundle.main.bundleIdentifier ?? "PostRunDrip", category: "App")
}
