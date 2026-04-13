import Foundation
import os
import Supabase

@Observable
final class HistoryViewModel {
    var entries: [TrainingLog] = []
    var isLoading = false
    var errorMessage: String?

    @MainActor
    func fetchEntries() async {
        isLoading = true
        errorMessage = nil

        do {
            let userId = AuthManager.shared.userId
            let response: [TrainingLog] = try await supabase
                .from("training_logs")
                .select()
                .eq("user_id", value: userId)
                .order("workout_date", ascending: false, nullsFirst: false)
                .limit(50)
                .execute()
                .value

            entries = response.sorted { $0.displayDate > $1.displayDate }
        } catch {
            Log.database.error("Failed to fetch entries: \(error)")
            errorMessage = "Could not load training logs. Pull down to try again."
            ErrorReporter.shared.report(error, context: "load training logs")
        }

        isLoading = false
    }

    @MainActor
    func deleteEntry(id: UUID) async -> Bool {
        do {
            try await supabase
                .from("training_logs")
                .delete()
                .eq("id", value: id.uuidString)
                .execute()
            entries.removeAll { $0.id == id }
            return true
        } catch {
            Log.database.error("Failed to delete entry: \(error)")
            errorMessage = "Could not delete entry."
            ErrorReporter.shared.report(error, context: "delete entry")
            return false
        }
    }

    @MainActor
    func updateEntry(id: UUID, data: [String: AnyEncodable]) async -> Bool {
        do {
            try await supabase
                .from("training_logs")
                .update(data)
                .eq("id", value: id.uuidString)
                .execute()

            // Refresh to get latest data
            await fetchEntries()
            return true
        } catch {
            Log.database.error("Failed to update entry: \(error)")
            errorMessage = "Could not save changes."
            ErrorReporter.shared.report(error, context: "save changes")
            return false
        }
    }
}

/// Type-erased Encodable wrapper for dynamic update dictionaries.
struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void

    init<T: Encodable>(_ value: T) {
        _encode = { encoder in try value.encode(to: encoder) }
    }

    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}
