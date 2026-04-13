//
//  BackupService.swift
//  RunningLog
//
//  Exports all user data from Supabase as a single JSON file.
//

import Foundation
import os
import Supabase

// MARK: - FullBackup

struct FullBackup: Codable {
    let exportedAt: Date
    let appVersion: String
    let trainingLogs: [TrainingLog]
    let trainingPlans: [TrainingPlan]
    let scheduledWorkouts: [ScheduledWorkout]
    let userGoals: [UserGoal]
    let injuries: [Injury]
    let fitnessSnapshots: [FitnessSnapshot]
    let biomechanicsAnalyses: [BiomechanicsAnalysis]
    let formChecks: [FormCheck]
}

// MARK: - BackupService

@Observable
final class BackupService {
    var isExporting = false
    var exportError: String?
    var progress: String = ""
    var tablesCompleted: Int = 0

    static let totalTables = 8

    @MainActor
    func exportAllData() async throws -> URL {
        isExporting = true
        exportError = nil
        tablesCompleted = 0

        defer { isExporting = false }

        do {
            let backup = try await fetchAllTables()
            let url = try writeJSON(backup)
            return url
        } catch {
            Log.app.error("Backup failed: \(error)")
            exportError = error.localizedDescription
            throw error
        }
    }

    // MARK: - Fetch

    private static let pageSize = 1000

    /// Fetches all rows from a table in pages of 1000 to avoid OOM on large datasets.
    private func fetchPaginated<T: Decodable>(
        table: String,
        orderBy: String = "created_at",
        ascending: Bool = false
    ) async throws -> [T] {
        var allRows: [T] = []
        var offset = 0

        while true {
            let page: [T] = try await supabase
                .from(table)
                .select()
                .order(orderBy, ascending: ascending)
                .range(from: offset, to: offset + Self.pageSize - 1)
                .execute()
                .value

            allRows.append(contentsOf: page)

            if page.count < Self.pageSize { break }
            offset += Self.pageSize
        }

        return allRows
    }

    @MainActor
    private func fetchAllTables() async throws -> FullBackup {
        progress = "Fetching training logs..."
        let logs: [TrainingLog] = try await fetchPaginated(table: "training_logs")
        tablesCompleted = 1

        progress = "Fetching training plans..."
        let plans: [TrainingPlan] = try await fetchPaginated(table: "training_plans")
        tablesCompleted = 2

        progress = "Fetching scheduled workouts..."
        let workouts: [ScheduledWorkout] = try await fetchPaginated(table: "scheduled_workouts", orderBy: "date", ascending: true)
        tablesCompleted = 3

        progress = "Fetching goals..."
        let goals: [UserGoal] = try await fetchPaginated(table: "user_goals")
        tablesCompleted = 4

        progress = "Fetching injuries..."
        let injuries: [Injury] = try await fetchPaginated(table: "injuries")
        tablesCompleted = 5

        progress = "Fetching fitness snapshots..."
        let snapshots: [FitnessSnapshot] = try await fetchPaginated(table: "fitness_snapshots")
        tablesCompleted = 6

        progress = "Fetching biomechanics analyses..."
        let biomechanics: [BiomechanicsAnalysis] = try await fetchPaginated(table: "biomechanics_analyses")
        tablesCompleted = 7

        progress = "Fetching form checks..."
        let formChecks: [FormCheck] = try await fetchPaginated(table: "form_checks")
        tablesCompleted = 8

        progress = "Building backup..."

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

        return FullBackup(
            exportedAt: Date(),
            appVersion: version,
            trainingLogs: logs,
            trainingPlans: plans,
            scheduledWorkouts: workouts,
            userGoals: goals,
            injuries: injuries,
            fitnessSnapshots: snapshots,
            biomechanicsAnalyses: biomechanics,
            formChecks: formChecks
        )
    }

    // MARK: - Write

    private func writeJSON(_ backup: FullBackup) throws -> URL {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(backup)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: Date())

        let fileName = "RunningLog_Backup_\(dateString).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try data.write(to: url, options: .atomic)

        Log.app.info("Backup written: \(url.lastPathComponent) (\(data.count) bytes)")
        return url
    }
}
