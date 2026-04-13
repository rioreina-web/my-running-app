//
//  PaceConfigManager.swift
//  RunningLog
//
//  Manages per-plan pace overrides, disabled paces, and phase overrides,
//  all persisted to UserDefaults keyed by plan ID.
//

import Foundation
import Observation

// MARK: - PaceConfigManager

@Observable
final class PaceConfigManager {
    // MARK: - Private State

    private var activePlanId: UUID?
    private var activePlan: TrainingPlan?

    /// Incremented whenever a phase override changes, to drive SwiftUI reactivity.
    private(set) var phaseOverrideVersion: Int = 0

    // MARK: - Configuration

    func configure(for plan: TrainingPlan?) {
        activePlan = plan
        activePlanId = plan?.id
    }

    // MARK: - Pace Overrides

    /// Per-zone pace overrides in seconds/mile (persisted per plan ID).
    var paceOverrides: [NamedPace: Double] {
        get {
            guard let plan = activePlan else { return [:] }
            let key = "paceOverrides_\(plan.id.uuidString)"
            guard let dict = UserDefaults.standard.dictionary(forKey: key) as? [String: Double] else { return [:] }
            var result: [NamedPace: Double] = [:]
            for (rawName, value) in dict {
                if let pace = NamedPace(rawValue: rawName) {
                    result[pace] = value
                }
            }
            return result
        }
        set {
            guard let plan = activePlan else { return }
            let key = "paceOverrides_\(plan.id.uuidString)"
            let dict = Dictionary(uniqueKeysWithValues: newValue.map { ($0.key.rawValue, $0.value) })
            UserDefaults.standard.set(dict, forKey: key)
        }
    }

    // MARK: - Disabled Paces

    /// Named paces disabled for the active plan (persisted per plan ID).
    var disabledPaces: Set<NamedPace> {
        get {
            guard let plan = activePlan else { return [] }
            let key = "disabledPaces_\(plan.id.uuidString)"
            guard let raw = UserDefaults.standard.stringArray(forKey: key) else { return [] }
            return Set(raw.compactMap { NamedPace(rawValue: $0) })
        }
        set {
            guard let plan = activePlan else { return }
            let key = "disabledPaces_\(plan.id.uuidString)"
            UserDefaults.standard.set(newValue.map(\.rawValue), forKey: key)
        }
    }

    // MARK: - Phase Overrides

    /// Get the phase override for a specific week, if one has been set by the user.
    func phaseOverride(for week: Int) -> TrainingPhase? {
        guard let plan = activePlan else { return nil }
        let key = "phaseOverrides_\(plan.id.uuidString)"
        guard let dict = UserDefaults.standard.dictionary(forKey: key) as? [String: String],
              let raw = dict["\(week)"]
        else { return nil }
        return TrainingPhase(rawValue: raw)
    }

    /// Set or clear the phase override for a specific week.
    func setPhaseOverride(_ phase: TrainingPhase?, for week: Int) {
        guard let plan = activePlan else { return }
        let key = "phaseOverrides_\(plan.id.uuidString)"
        var dict = (UserDefaults.standard.dictionary(forKey: key) as? [String: String]) ?? [:]
        if let phase = phase {
            dict["\(week)"] = phase.rawValue
        } else {
            dict.removeValue(forKey: "\(week)")
        }
        UserDefaults.standard.set(dict, forKey: key)
        phaseOverrideVersion += 1
    }
}
