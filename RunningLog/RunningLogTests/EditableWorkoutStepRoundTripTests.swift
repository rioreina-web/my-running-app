//
//  EditableWorkoutStepRoundTripTests.swift
//  RunningLogTests
//
//  Locks the EditableWorkoutStep ↔ PlannedWorkoutStep round-trip. Before
//  May 2026 the editor silently dropped `repeats` and `recovery` on every
//  load and wiped them on every save — a workout authored as "7 × mile at
//  threshold with 90s recovery" would persist as a single 1mi step the
//  next time the iOS template editor opened it. These tests guard the
//  fix and the related PaceSelection ↔ paceZone+adjustment converters.
//

import Foundation
import Testing
@testable import RunningLog

@Suite("EditableWorkoutStep round-trip")
struct EditableWorkoutStepRoundTripTests {

    // Shared paces — pinned to a stable goal so the test isn't sensitive
    // to ratio-table tuning. 6:00 marathon (2:37:18).
    private static let goalSec = 360.0 // 6:00/mi marathon pace
    private static let equivalentPaces = EquivalentPaces(
        raceDistance: .marathon,
        goalTimeSeconds: Int(goalSec * RaceDistance.marathon.distanceInMiles)
    )

    // MARK: - The bug we just fixed

    @Test("Repeats and recovery survive a full round-trip")
    func repeatsAndRecoverySurvive() {
        // "7 × 1mi at threshold, 90s @ recovery". The exact workout from
        // the May 2026 regression screenshot.
        let recovery = PlannedWorkoutRecovery(
            durationType: .timeSeconds,
            durationValue: 90,
            paceZone: .recovery,
            paceAdjustment: nil
        )
        let original = PlannedWorkoutStep(
            id: UUID(),
            stepType: .active,
            durationType: .distanceMiles,
            durationValue: 1.0,
            targetPaceIntensity: nil,
            notes: "build effort mile 4",
            order: 1,
            paceZone: .threshold,
            paceAdjustment: nil,
            repeats: 7,
            recovery: recovery
        )

        // Round-trip: planned → editable → planned
        let editable = EditableWorkoutStep(
            from: original,
            equivalentPaces: Self.equivalentPaces,
            racePaceSeconds: Self.goalSec
        )
        let restored = editable.toWorkoutStep(
            racePaceSeconds: Self.goalSec,
            equivalentPaces: Self.equivalentPaces
        )

        // Structural fields must survive byte-identical
        #expect(restored.repeats == 7)
        #expect(restored.recovery?.durationType == .timeSeconds)
        #expect(restored.recovery?.durationValue == 90)
        #expect(restored.recovery?.paceZone == .recovery)
        #expect(restored.recovery?.paceAdjustment == nil)
        #expect(restored.stepType == .active)
        #expect(restored.durationType == .distanceMiles)
        #expect(restored.durationValue == 1.0)
        #expect(restored.notes == "build effort mile 4")
        #expect(restored.order == 1)
        #expect(restored.paceZone == .threshold)
    }

    // MARK: - Negative case: no-reps stays no-reps

    @Test("A single-rep step never gains a phantom repeats:1")
    func singleRepStaysSingle() {
        let original = PlannedWorkoutStep(
            id: UUID(),
            stepType: .active,
            durationType: .distanceMiles,
            durationValue: 4.0,
            targetPaceIntensity: nil,
            notes: nil,
            order: 0,
            paceZone: .mp,
            paceAdjustment: nil,
            repeats: nil,
            recovery: nil
        )
        var editable = EditableWorkoutStep(
            from: original,
            equivalentPaces: Self.equivalentPaces,
            racePaceSeconds: Self.goalSec
        )
        // The editor's local state may even briefly hold repeats=1 (e.g., a
        // UI mistake). The serializer should still emit `repeats: nil` —
        // `repeats: 1` is meaningless and pollutes the JSON.
        editable.repeats = 1
        let restored = editable.toWorkoutStep(
            racePaceSeconds: Self.goalSec,
            equivalentPaces: Self.equivalentPaces
        )
        #expect(restored.repeats == nil)
        #expect(restored.recovery == nil)
    }

    // MARK: - Adjustment conversion: seconds_per_km → seconds_per_mile

    @Test("seconds_per_km adjustment maps into the editor's seconds_per_mile space")
    func secondsPerKmConvertsToSecondsPerMile() {
        // Web/server adjustments can arrive as seconds_per_km. The editor
        // canonicalizes everything to seconds_per_mile by multiplying by
        // 1.609344 — the same conversion adjustedPaceSecPerMile applies.
        let adj = WorkoutPaceAdjustment(type: .secondsPerKm, value: -10)
        let selection = EditableWorkoutStep.paceSelection(from: .threshold, adjustment: adj)
        guard case let .namedPaceOffset(zone, offsetSec) = selection else {
            Issue.record("Expected .namedPaceOffset, got \(selection)")
            return
        }
        #expect(zone == .threshold)
        // -10 s/km × 1.609344 km/mi = -16.09344 s/mi. Allow a tight tolerance.
        #expect(abs(offsetSec - (-16.09344)) < 0.001)
    }

    // MARK: - Adjustment conversion: percent

    @Test("Percent adjustment round-trips through PaceSelection")
    func percentAdjustmentRoundTrips() {
        let adj = WorkoutPaceAdjustment(type: .percent, value: 2)
        let selection = EditableWorkoutStep.paceSelection(from: .mp, adjustment: adj)
        guard case let .namedPacePercentOffset(zone, pct) = selection else {
            Issue.record("Expected .namedPacePercentOffset, got \(selection)")
            return
        }
        #expect(zone == .mp)
        #expect(pct == 2)

        // Lower back to (zone, adjustment) — should be identical.
        let (downZone, downAdj) = EditableWorkoutStep.zoneAndAdjustment(from: selection)
        #expect(downZone == .mp)
        #expect(downAdj?.type == .percent)
        #expect(downAdj?.value == 2)
    }

    // MARK: - Adjustment conversion: seconds_per_mile passthrough

    @Test("seconds_per_mile adjustment is the canonical editor representation")
    func secondsPerMilePassthrough() {
        let adj = WorkoutPaceAdjustment(type: .secondsPerMile, value: -10)
        let selection = EditableWorkoutStep.paceSelection(from: .hm, adjustment: adj)
        guard case let .namedPaceOffset(zone, offsetSec) = selection else {
            Issue.record("Expected .namedPaceOffset, got \(selection)")
            return
        }
        #expect(zone == .hm)
        #expect(offsetSec == -10)
    }

    // MARK: - PaceSelection.none → no zone

    @Test("Editor PaceSelection.none / .custom / .targetTime lower to (nil, nil)")
    func customSelectionsCollapseToNoZone() {
        for selection: EditableWorkoutStep.PaceSelection in [
            .none,
            .custom(95),
            .targetTime(305),
        ] {
            let (zone, adj) = EditableWorkoutStep.zoneAndAdjustment(from: selection)
            #expect(zone == nil)
            #expect(adj == nil)
        }
    }

    // MARK: - Recovery's own pace adjustment survives

    @Test("Recovery sub-segment's paceAdjustment survives round-trip")
    func recoveryAdjustmentSurvives() {
        // Recovery at "Easy +30s/mi" — testing that the editor doesn't
        // collapse the recovery's adjustment when serializing back.
        let recovery = PlannedWorkoutRecovery(
            durationType: .distanceMiles,
            durationValue: 0.25,
            paceZone: .easy,
            paceAdjustment: WorkoutPaceAdjustment(type: .secondsPerMile, value: 30)
        )
        let original = PlannedWorkoutStep(
            id: UUID(),
            stepType: .active,
            durationType: .distanceMeters,
            durationValue: 800,
            targetPaceIntensity: nil,
            notes: nil,
            order: 0,
            paceZone: .fiveK,
            paceAdjustment: nil,
            repeats: 6,
            recovery: recovery
        )
        let editable = EditableWorkoutStep(
            from: original,
            equivalentPaces: Self.equivalentPaces,
            racePaceSeconds: Self.goalSec
        )
        let restored = editable.toWorkoutStep(
            racePaceSeconds: Self.goalSec,
            equivalentPaces: Self.equivalentPaces
        )

        #expect(restored.repeats == 6)
        #expect(restored.recovery?.paceZone == .easy)
        #expect(restored.recovery?.paceAdjustment?.type == .secondsPerMile)
        #expect(restored.recovery?.paceAdjustment?.value == 30)
        #expect(restored.recovery?.durationType == .distanceMiles)
        #expect(restored.recovery?.durationValue == 0.25)
    }

    // MARK: - Codable round-trip (the actual persistence path)

    @Test("PlannedWorkoutStep with repeats+recovery survives JSON encode/decode")
    func codableRoundTrip() throws {
        let recovery = PlannedWorkoutRecovery(
            durationType: .timeSeconds,
            durationValue: 90,
            paceZone: .recovery,
            paceAdjustment: nil
        )
        let original = PlannedWorkoutStep(
            id: UUID(),
            stepType: .active,
            durationType: .distanceMiles,
            durationValue: 1.0,
            targetPaceIntensity: nil,
            notes: nil,
            order: 1,
            paceZone: .threshold,
            paceAdjustment: WorkoutPaceAdjustment(type: .secondsPerMile, value: -10),
            repeats: 7,
            recovery: recovery
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(PlannedWorkoutStep.self, from: data)

        #expect(decoded.repeats == 7)
        #expect(decoded.recovery?.durationValue == 90)
        #expect(decoded.recovery?.paceZone == .recovery)
        #expect(decoded.paceZone == .threshold)
        #expect(decoded.paceAdjustment?.type == .secondsPerMile)
        #expect(decoded.paceAdjustment?.value == -10)
    }
}
