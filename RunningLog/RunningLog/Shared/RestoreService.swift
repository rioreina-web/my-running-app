//
//  RestoreService.swift
//  RunningLog
//
//  Imports a JSON backup file (produced by BackupService) back into Supabase.
//  Uses upsert to avoid duplicates — safe to run multiple times on the same file.
//

import Foundation
import os
import Supabase

@Observable
final class RestoreService {
    var isImporting = false
    var importError: String?
    var progress: String = ""
    var tablesCompleted: Int = 0

    static let totalTables = 8

    @MainActor
    func importBackup(from url: URL) async throws -> RestoreSummary {
        isImporting = true
        importError = nil
        tablesCompleted = 0
        progress = "Reading backup file..."

        defer { isImporting = false }

        do {
            let data = try readFile(at: url)
            let backup = try decodeBackup(data)
            let summary = try await uploadAll(backup)
            return summary
        } catch {
            Log.app.error("Restore failed: \(error)")
            importError = error.localizedDescription
            throw error
        }
    }

    // MARK: - Read & Decode

    private func readFile(at url: URL) throws -> Data {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }
        return try Data(contentsOf: url)
    }

    private func decodeBackup(_ data: Data) throws -> FullBackup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(FullBackup.self, from: data)
    }

    // MARK: - Upload

    @MainActor
    private func uploadAll(_ backup: FullBackup) async throws -> RestoreSummary {
        var summary = RestoreSummary()
        var failedTables: [String] = []

        // Restore each table independently — failures don't block remaining tables
        let tables: [(String, String, () async throws -> Int)] = [
            ("Restoring training logs...", "training_logs", { try await self.upsertBatch("training_logs", items: backup.trainingLogs) }),
            ("Restoring training plans...", "training_plans", { try await self.upsertBatch("training_plans", items: backup.trainingPlans) }),
            ("Restoring scheduled workouts...", "scheduled_workouts", { try await self.upsertBatch("scheduled_workouts", items: backup.scheduledWorkouts) }),
            ("Restoring goals...", "user_goals", { try await self.upsertBatch("user_goals", items: backup.userGoals) }),
            ("Restoring injuries...", "injuries", { try await self.upsertBatch("injuries", items: backup.injuries) }),
            ("Restoring fitness snapshots...", "fitness_snapshots", { try await self.upsertBatch("fitness_snapshots", items: backup.fitnessSnapshots) }),
        ]

        for (index, (label, tableName, restore)) in tables.enumerated() {
            progress = label
            do {
                let count = try await restore()
                switch index {
                case 0: summary.trainingLogs = count
                case 1: summary.trainingPlans = count
                case 2: summary.scheduledWorkouts = count
                case 3: summary.userGoals = count
                case 4: summary.injuries = count
                case 5: summary.fitnessSnapshots = count
                default: break
                }
            } catch {
                Log.app.error("Failed to restore \(tableName): \(error)")
                failedTables.append(tableName)
            }
            tablesCompleted = index + 1
        }

        if failedTables.isEmpty {
            progress = "Restore complete!"
        } else {
            progress = "Restore partial — failed: \(failedTables.joined(separator: ", "))"
            importError = "Some tables failed to restore: \(failedTables.joined(separator: ", ")). Successfully restored \(summary.totalRecords) records."
        }

        Log.app.info("Restore done: \(summary.totalRecords) records, \(failedTables.count) tables failed")
        return summary
    }

    private func upsertBatch<T: Encodable>(_ table: String, items: [T]) async throws -> Int {
        guard !items.isEmpty else { return 0 }

        // Upsert in chunks of 100 to avoid payload limits
        let chunkSize = 100
        for start in stride(from: 0, to: items.count, by: chunkSize) {
            let end = min(start + chunkSize, items.count)
            let chunk = Array(items[start..<end])
            try await supabase
                .from(table)
                .upsert(chunk, onConflict: "id")
                .execute()
        }
        return items.count
    }
}

// MARK: - RestoreSummary

struct RestoreSummary {
    var trainingLogs: Int = 0
    var trainingPlans: Int = 0
    var scheduledWorkouts: Int = 0
    var userGoals: Int = 0
    var injuries: Int = 0
    var fitnessSnapshots: Int = 0

    var totalRecords: Int {
        trainingLogs + trainingPlans + scheduledWorkouts + userGoals +
        injuries + fitnessSnapshots
    }

    var breakdown: [(label: String, count: Int)] {
        [
            ("Training logs", trainingLogs),
            ("Training plans", trainingPlans),
            ("Scheduled workouts", scheduledWorkouts),
            ("Goals", userGoals),
            ("Injuries", injuries),
            ("Fitness snapshots", fitnessSnapshots),
        ].filter { $0.count > 0 }
    }
}
