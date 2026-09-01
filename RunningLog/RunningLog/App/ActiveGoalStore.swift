import Foundation
import Observation
import os
import Supabase
import SwiftUI

// ============================================================================
// ActiveGoalStore
//
// The soonest active `user_goals` row, loaded once and shared by every plate
// that prints a TrainingDateline. GOAL-IA-APPLY.md §6 step 1 — without this,
// each of the ~6 PlateStrip call sites would need its own `user_goals` fetch
// just to print one countdown string.
//
// "Soonest" is the rule for multiple active goals (GOAL-IA-APPLY.md §8.2):
// nearest target_date wins, not query order.
// ============================================================================

@MainActor
@Observable
final class ActiveGoalStore {
    static let shared = ActiveGoalStore()

    private(set) var soonestActiveGoal: UserGoal?
    private var hasLoaded = false

    private init() {}

    /// Fetch once per app session; later calls are a no-op. Views should
    /// call this from `.task`, not `reload()` — see `reload()` for the
    /// after-save path.
    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await fetch()
    }

    /// Re-fetch after a goal is saved (EditGoalSheet's `onSaved`), since
    /// `loadIfNeeded()` will otherwise keep serving the stale value for the
    /// rest of the session.
    func reload() async {
        await fetch()
    }

    private func fetch() async {
        do {
            let response: [UserGoal] = try await supabase
                .from("user_goals")
                .select()
                .eq("status", value: "active")
                .order("target_date", ascending: true)
                .limit(1)
                .execute()
                .value
            soonestActiveGoal = response.first
        } catch {
            Log.goals.error("Failed to fetch active goal: \(error)")
        }
    }
}

// MARK: - Environment door

// The tap target for every dateline in the app (GOAL-IA-APPLY.md §3, position
// 2: "the dateline becomes the door"). Injected once at the app root as
// `{ activeDestination = .goals }` so any plate, anywhere in the tab tree,
// can open the same goal screen without its own sheet state or a reference
// to `AppDestination`.
private struct OpenGoalEditorKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var openGoalEditor: () -> Void {
        get { self[OpenGoalEditorKey.self] }
        set { self[OpenGoalEditorKey.self] = newValue }
    }
}
