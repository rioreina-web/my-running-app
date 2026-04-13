import Foundation
import os

// MARK: - App Logger

/// Centralized logging using os.Logger for better debugging and performance
enum Log {
    private static let subsystem = "PostRunDrip"

    /// Logger for HealthKit operations
    static let health = Logger(subsystem: subsystem, category: "HealthKit")

    /// Logger for video playback and downloads
    static let video = Logger(subsystem: subsystem, category: "Video")

    /// Logger for weather service
    static let weather = Logger(subsystem: subsystem, category: "Weather")

    /// Logger for coaching/AI features
    static let coach = Logger(subsystem: subsystem, category: "Coach")

    /// Logger for goals and analysis
    static let goals = Logger(subsystem: subsystem, category: "Goals")

    /// Logger for content library
    static let content = Logger(subsystem: subsystem, category: "Content")

    /// Logger for database operations
    static let database = Logger(subsystem: subsystem, category: "Database")

    /// Logger for biomechanics analysis
    static let biomechanics = Logger(subsystem: subsystem, category: "Biomechanics")

    /// General app logger
    static let app = Logger(subsystem: subsystem, category: "App")
}
