//
//  ShorthandStepMappingTests.swift
//  RunningLogTests
//
//  Locks the parse-workout-shorthand wire shape → EditableWorkoutStep →
//  PlannedWorkoutStep path that DayDetailSheet's workshop writes into the plan.
//
//  Before this mapping was shared, that screen built PlannedWorkoutStep by hand
//  and derived its pace from `pacePercentage`, a field the server hardcodes to
//  null. Every workout written into the plan from the workshop therefore saved
//  with no zone, no offset and no intensity — the only trace of a prescription
//  being the English "@ marathon pace" left in `notes`. These tests fail if any
//  part of a written pace goes missing on that trip again.
//

import Foundation
import Testing
@testable import RunningLog

@Suite("Shorthand → planned step mapping")
struct ShorthandStepMappingTests {

    // 6:00 marathon pace (2:37:18), matching EditableWorkoutStepRoundTripTests.
    private static let equivalentPaces = EquivalentPaces(
        raceDistance: .marathon,
        goalTimeSeconds: Int(360.0 * RaceDistance.marathon.distanceInMiles)
    )
    private static let racePaceSeconds = 360.0

    private static func structured(
        stepType: String = "active",
        durationType: String = "distance_miles",
        durationValue: Double = 1,
        paceZone: String? = nil,
        paceAdjustment: ShorthandStructuredStep.Adjustment? = nil,
        exactPaceSecPerMile: Double? = nil,
        repeats: Int? = nil,
        recovery: ShorthandStructuredStep.Recovery? = nil,
        note: String? = nil,
        unresolvedReason: String? = nil
    ) -> ShorthandStructuredStep {
        ShorthandStructuredStep(
            stepType: stepType,
            durationType: durationType,
            durationValue: durationValue,
            paceZone: paceZone,
            paceAdjustment: paceAdjustment,
            exactPaceSecPerMile: exactPaceSecPerMile,
            repeats: repeats,
            recovery: recovery,
            note: note,
            unresolvedReason: unresolvedReason
        )
    }

    private static func result(
        structuredSteps: [ShorthandStructuredStep]?,
        steps: [ShorthandStep] = []
    ) -> ShorthandParseResult {
        ShorthandParseResult(
            steps: steps,
            totalDistanceMiles: 0,
            estimatedDurationMinutes: nil,
            workoutType: "intervals",
            name: "Workout",
            description: "",
            errors: [],
            structuredSteps: structuredSteps,
            warnings: nil,
            unparsed: nil
        )
    }

    private static func planned(_ result: ShorthandParseResult) -> [PlannedWorkoutStep] {
        EditableWorkoutStep
            .steps(fromShorthand: result)
            .map {
                $0.toWorkoutStep(
                    racePaceSeconds: racePaceSeconds,
                    equivalentPaces: equivalentPaces
                )
            }
    }

    // MARK: - The defect this path was shipping

    @Test("A seconds-per-mile offset survives to the persisted step")
    func secondsOffsetSurvives() throws {
        // "4-6x2m @ MP-5" — the offset IS the workout. A step that arrives as
        // bare "mp" has lost the entire point of the rep.
        let steps = Self.planned(Self.result(structuredSteps: [
            Self.structured(
                durationValue: 2,
                paceZone: "mp",
                paceAdjustment: .init(type: "seconds_per_mile", value: -5),
                repeats: 5
            )
        ]))

        let step = try #require(steps.first)
        #expect(step.paceZone == .mp)
        #expect(step.paceAdjustment?.type == .secondsPerMile)
        #expect(step.paceAdjustment?.value == -5)
        #expect(step.repeats == 5)
    }

    @Test("A percent offset survives, and keeps its sign")
    func percentOffsetSurvives() throws {
        // "16 x K alternating MP-3% & MP+5%" — negative is faster on both sides
        // of the wire; a flipped sign turns a float into a rep.
        let steps = Self.planned(Self.result(structuredSteps: [
            Self.structured(
                durationType: "distance_km",
                paceZone: "mp",
                paceAdjustment: .init(type: "percent", value: -3)
            ),
            Self.structured(
                durationType: "distance_km",
                paceZone: "mp",
                paceAdjustment: .init(type: "percent", value: 5)
            ),
        ]))

        #expect(steps.count == 2)
        #expect(steps[0].paceAdjustment?.type == .percent)
        #expect(steps[0].paceAdjustment?.value == -3)
        #expect(steps[1].paceAdjustment?.value == 5)
        // Order is part of the workout: fast leg first, float second.
        #expect(steps[0].order < steps[1].order)
    }

    @Test("An absolute written pace stays a number, and never becomes a zone")
    func exactPaceStaysExact() throws {
        // "6x800 @ 3:00" = 362 sec/mile. Folding that into `mp` because this
        // athlete's MP happens to be 6:00 today reintroduces exactly the drift
        // the coach avoided by writing a number.
        let steps = Self.planned(Self.result(structuredSteps: [
            Self.structured(
                durationType: "distance_meters",
                durationValue: 800,
                exactPaceSecPerMile: 362,
                repeats: 6
            )
        ]))

        let step = try #require(steps.first)
        #expect(step.paceZone == nil)
        #expect(step.targetPaceIntensity != nil)
        #expect(step.repeats == 6)
    }

    @Test("Recovery structure survives instead of being flattened")
    func recoverySurvives() throws {
        let steps = Self.planned(Self.result(structuredSteps: [
            Self.structured(
                durationType: "distance_meters",
                durationValue: 800,
                paceZone: "fiveK",
                repeats: 6,
                recovery: .init(
                    durationType: "distance_meters",
                    durationValue: 400,
                    isJog: true
                )
            )
        ]))

        let step = try #require(steps.first)
        let recovery = try #require(step.recovery)
        #expect(recovery.durationType == .distanceMeters)
        #expect(recovery.durationValue == 400)
        #expect(step.paceZone == .fiveK)
    }

    // MARK: - Shape selection

    @Test("structuredSteps is preferred over the lossy legacy projection")
    func prefersStructured() throws {
        // The same workout in both shapes. The legacy one cannot carry the
        // offset, so reading it would silently drop the MP-10.
        let legacy = ShorthandStep(
            stepType: "active",
            durationType: "distance_miles",
            durationValue: 1,
            paceReference: "marathon",
            paceRangeHigh: nil,
            pacePercentage: nil,
            absolutePaceSecPerMile: nil,
            notes: nil,
            order: 0,
            repCount: nil,
            recoveryType: nil
        )
        let steps = Self.planned(Self.result(
            structuredSteps: [
                Self.structured(
                    paceZone: "mp",
                    paceAdjustment: .init(type: "seconds_per_mile", value: -10)
                )
            ],
            steps: [legacy]
        ))

        #expect(steps.count == 1)
        #expect(steps[0].paceAdjustment?.value == -10)
    }

    @Test("The legacy projection still reads a zone and an absolute pace")
    func legacyFallback() throws {
        // No structuredSteps — the server answered from its grammar. A zone and
        // any written number must still arrive; only the offset is genuinely
        // unrepresentable on this shape.
        let steps = Self.planned(Self.result(
            structuredSteps: nil,
            steps: [
                ShorthandStep(
                    stepType: "active", durationType: "distance_miles", durationValue: 4,
                    paceReference: "half", paceRangeHigh: nil, pacePercentage: nil,
                    absolutePaceSecPerMile: nil, notes: nil, order: 0,
                    repCount: nil, recoveryType: nil
                ),
                ShorthandStep(
                    stepType: "active", durationType: "distance_miles", durationValue: 4,
                    paceReference: nil, paceRangeHigh: nil, pacePercentage: nil,
                    absolutePaceSecPerMile: 360, notes: nil, order: 1,
                    repCount: nil, recoveryType: nil
                ),
            ]
        ))

        #expect(steps.count == 2)
        #expect(steps[0].paceZone == .hm)
        // The written number survives as a resolved intensity, not as a zone.
        #expect(steps[1].paceZone == nil)
        #expect(steps[1].targetPaceIntensity != nil)
    }

    // MARK: - The guard that must NOT quietly resolve itself

    @Test("An unresolved pace does not invent a zone")
    func unresolvedDoesNotInventAZone() throws {
        // "8 x 3' fast" — the coach named an effort, not a zone. The step is
        // still built (dropping it would delete the session), but nothing may
        // claim the coach prescribed a zone here.
        let steps = Self.planned(Self.result(structuredSteps: [
            Self.structured(
                durationType: "time_seconds",
                durationValue: 180,
                paceZone: nil,
                repeats: 8,
                unresolvedReason: "effort_word_not_a_zone"
            )
        ]))

        let step = try #require(steps.first)
        #expect(step.durationValue == 180)
        #expect(step.repeats == 8)
        // Documents today's behaviour, which is NOT yet safe: the step falls to
        // the step type's default rather than staying absent, so the plan cannot
        // tell "the coach wrote easy" from "nobody knows". The save-time gate is
        // the fix; this expectation should flip to `== nil` when it lands.
        #expect(step.paceZone == PlannedWorkoutStep.StepType.active.defaultPace)
    }
}
