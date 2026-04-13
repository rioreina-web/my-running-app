import Combine
import PostgREST
import Supabase
import SwiftUI

// MARK: - ExportOptions

struct ExportOptions {
    var dateRange: DateRange = .last30Days
    var includeWorkouts: Bool = true
    var includeTranscriptions: Bool = true

    enum DateRange: String, CaseIterable {
        case last7Days = "Last 7 Days"
        case last30Days = "Last 30 Days"
        case allTime = "All Time"

        var startDate: Date? {
            let calendar = Calendar.current
            switch self {
            case .last7Days:
                return calendar.date(byAdding: .day, value: -7, to: Date())
            case .last30Days:
                return calendar.date(byAdding: .day, value: -30, to: Date())
            case .allTime:
                return nil
            }
        }
    }
}

// MARK: - ExportService

class ExportService: ObservableObject {
    @Published var isExporting = false
    @Published var exportError: String?

    func exportTrainingLogs(options: ExportOptions) async throws -> URL {
        await MainActor.run { isExporting = true }

        defer {
            Task { @MainActor in
                isExporting = false
            }
        }

        // Fetch logs from Supabase
        let logs = try await fetchLogs(options: options)

        // Generate CSV
        return try generateCSV(logs: logs, options: options)
    }

    private func fetchLogs(options: ExportOptions) async throws -> [TrainingLog] {
        let response: [TrainingLog] = try await supabase
            .from("training_logs")
            .select()
            .order("created_at", ascending: false)
            .limit(5000)
            .execute()
            .value

        if let startDate = options.dateRange.startDate {
            return response.filter { $0.createdAt >= startDate }
        }

        return response
    }

    private func generateCSV(logs: [TrainingLog], options: ExportOptions) throws -> URL {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"

        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEEE"

        // CSV Header
        var csvContent = "Date,Day,Time,Mood,Distance (mi),Duration (min),Pace (/mi),Notes,AI Summary\n"

        for log in logs {
            let date = dateFormatter.string(from: log.createdAt)
            let day = dayFormatter.string(from: log.createdAt)
            let time = timeFormatter.string(from: log.createdAt)
            let mood = log.mood ?? ""

            // Workout data
            let distance = log.workoutDistanceMiles.map { String(format: "%.2f", $0) } ?? ""
            let duration = log.workoutDurationMinutes.map { String(format: "%.1f", $0) } ?? ""
            let pace = log.formattedWorkoutPace ?? ""

            // Notes - escape quotes and newlines for CSV
            let notes = escapeCSV(log.notes ?? "")
            let aiSummary = escapeCSV(log.cleanedNotes ?? "")

            let row = "\(date),\(day),\(time),\(mood),\(distance),\(duration),\(pace),\(notes),\(aiSummary)\n"
            csvContent += row
        }

        // Save to temp file
        let exportDate = dateFormatter.string(from: Date())
        let fileName = "TrainingLog_\(exportDate).csv"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        try csvContent.write(to: tempURL, atomically: true, encoding: .utf8)

        return tempURL
    }

    private func escapeCSV(_ text: String) -> String {
        var escaped = text
        // Replace newlines with spaces
        escaped = escaped.replacingOccurrences(of: "\n", with: " ")
        escaped = escaped.replacingOccurrences(of: "\r", with: " ")
        // Escape quotes by doubling them
        escaped = escaped.replacingOccurrences(of: "\"", with: "\"\"")
        // Wrap in quotes if contains comma, quote, or spaces
        if escaped.contains(",") || escaped.contains("\"") || escaped.contains(" ") {
            escaped = "\"\(escaped)\""
        }
        return escaped
    }
}
