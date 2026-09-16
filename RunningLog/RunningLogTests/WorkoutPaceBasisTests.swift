//
//  WorkoutPaceBasisTests.swift
//  RunningLogTests
//
//  Locks the three pace bases the workout builder switches between: zones off
//  the GOAL race, zones off CURRENT fitness, and FIXED typed paces.
//
//  Two things are worth guarding here. First, that goal and current genuinely
//  disagree — if the current-fitness table quietly fell back to the goal one,
//  the switch would look like it worked while changing nothing. Second, that
//  crossing into and out of Fixed is lossless: freezing a zone into a number
//  and rebasing it back has to land on the same pace, or the athlete's workout
//  drifts a second at a time every time they toggle.
//

import Foundation
import Testing
@testable import RunningLog

@Suite("Workout pace basis")
struct WorkoutPaceBasisTests {

    // MARK: - Fixtures

    /// Goal: a 3:00 marathon (6:52/mi). Aspiration.
    private static let goalTable = EquivalentPaces(
        raceDistance: .marathon,
        goalTimeSeconds: 3 * 3600
    )

    private static let goalRacePace = goalTable.mpPace

    /// A pace profile as the build-pace-profile edge function returns it.
    /// Decoded rather than constructed — `AthletePaceProfile` has no memberwise
    /// init, and going through JSON exercises the wire contract too.
    private static func profile(
        marathon: Double? = nil,
        half: Double? = nil,
        tenK: Double? = nil,
        fiveK: Double? = nil,
        mile: Double? = nil
    ) -> AthletePaceProfile {
        var fields: [String] = [
            "\"id\":\"\(UUID().uuidString)\"",
            "\"user_id\":\"\(UUID().uuidString)\"",
            "\"generated_at\":\"2026-08-20T12:00:00Z\"",
            "\"updated_at\":\"2026-08-20T12:00:00Z\"",
        ]
        func add(_ key: String, _ value: Double?) {
            guard let value else { return }
            fields.append("\"\(key)_pace_seconds\":\(value)")
            fields.append("\"\(key)_pace_confidence\":\"medium\"")
            fields.append("\"\(key)_pace_source_date\":\"2026-08-01T00:00:00Z\"")
        }
        add("marathon", marathon)
        add("half", half)
        add("ten_k", tenK)
        add("five_k", fiveK)
        add("mile", mile)

        let json = "{\(fields.joined(separator: ","))}"
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // A fixture that will not decode is a broken test, not a passing one.
        return try! decoder.decode(AthletePaceProfile.self, from: Data(json.utf8))
    }

    // MARK: - Current fitness table

    /// The point of the switch. A 3:00 goal and a body that currently runs
    /// 7:30 marathon pace must not produce the same MP, or Current is theatre.
    @Test("current fitness disagrees with the goal")
    func currentDiffersFromGoal() throws {
        let current = try #require(
            EquivalentPaces.fromCurrentFitness(Self.profile(marathon: 450))
        )
        #expect(current.mpPace == 450)
        #expect(abs(current.mpPace - Self.goalTable.mpPace) > 30)
        // Every derived zone moves with it, not just the anchor.
        #expect(current.easyPace > Self.goalTable.easyPace)
        #expect(current.fiveKPace > Self.goalTable.fiveKPace)
    }

    /// Measured paces are used verbatim. Re-deriving one the profile already
    /// knows would throw away the only real evidence in the table.
    @Test("measured paces are used verbatim, gaps are projected")
    func measuredWins() throws {
        let current = try #require(
            EquivalentPaces.fromCurrentFitness(Self.profile(half: 400, fiveK: 355))
        )
        #expect(current.hmPace == 400)
        #expect(current.fiveKPace == 355)
        // Marathon was never measured, so it is projected off the half anchor —
        // present, and slower than the half.
        #expect(current.mpPace > 400)
        #expect(current.threeKPace > 0)
    }

    /// One anchor is enough to build the whole table.
    @Test("a single anchor fills every zone")
    func singleAnchorFillsTable() throws {
        let current = try #require(
            EquivalentPaces.fromCurrentFitness(Self.profile(fiveK: 360))
        )
        for (_, pace) in current.allPaces {
            #expect(pace > 0)
            #expect(pace.isFinite)
        }
        // Slow → fast ordering has to survive the projection.
        #expect(current.easyPace > current.mpPace)
        #expect(current.mpPace > current.tenKPace)
        #expect(current.tenKPace > current.fiveKPace)
        #expect(current.fiveKPace > current.milePace)
    }

    /// No fitness read means the caller says so in prose — it does not get an
    /// invented table that looks measured.
    @Test("no profile and no anchors yield no table")
    func noAnchorNoTable() {
        #expect(EquivalentPaces.fromCurrentFitness(nil) == nil)
        #expect(EquivalentPaces.fromCurrentFitness(Self.profile()) == nil)
    }

    /// Hidden zones are a display preference and follow the athlete across
    /// bases; goal-pace overrides are corrections to the goal and must not.
    @Test("disabled zones carry into the current table")
    func disabledZonesCarry() throws {
        let current = try #require(
            EquivalentPaces.fromCurrentFitness(
                Self.profile(marathon: 450),
                disabledPaces: [.threeK]
            )
        )
        #expect(current.disabledPaces.contains(.threeK))
        #expect(!current.allPaces.contains { $0.0 == .threeK })
    }

    // MARK: - Freezing and rebasing

    @Test("freezing a zone writes down the pace it currently resolves to")
    func freezeResolves() {
        let selection = EditableWorkoutStep.PaceSelection.namedPace(.tenK)
        let frozen = selection.frozen(with: Self.goalTable, racePaceSeconds: Self.goalRacePace)
        #expect(frozen == .fixed(Self.goalTable.tenKPace))
    }

    /// The round-trip that would otherwise bleed seconds every toggle.
    @Test("freeze then rebase returns the same pace")
    func freezeRebaseIsLossless() {
        for zone in [NamedPace.easy, .mp, .threshold, .fiveK, .mile] {
            let original = EditableWorkoutStep.PaceSelection.namedPace(zone)
            let frozen = original.frozen(with: Self.goalTable, racePaceSeconds: Self.goalRacePace)
            let rebased = frozen.rebased(onto: Self.goalTable)

            let before = original.resolvedPaceSeconds(
                equivalentPaces: Self.goalTable, racePaceSeconds: Self.goalRacePace
            )
            let after = rebased.resolvedPaceSeconds(
                equivalentPaces: Self.goalTable, racePaceSeconds: Self.goalRacePace
            )
            #expect(before != nil)
            #expect(abs((after ?? 0) - (before ?? 0)) < 1)
        }
    }

    /// A number that sits between two zones keeps its remainder as an offset
    /// rather than being rounded into the nearest zone and losing seconds.
    ///
    /// Deliberately not asserting *which* zone it lands on: the spectrum is
    /// dense (LT sits barely a dozen seconds off 10K), so pinning the zone
    /// would be a test of the ratio table, not of the rebase. What has to hold
    /// is that a zone-plus-offset comes back and resolves to the same pace.
    @Test("a pace between zones rebases with an offset")
    func offBandRebaseKeepsRemainder() {
        // Squarely between easy and moderate — the widest gap on the table, so
        // this is unambiguously not sitting on a zone.
        let offBand = (Self.goalTable.easyPace + Self.goalTable.moderatePace) / 2
        let rebased = EditableWorkoutStep.PaceSelection.fixed(offBand).rebased(onto: Self.goalTable)

        guard case .namedPaceOffset(let zone, let offset) = rebased else {
            Issue.record("expected a zone plus offset, got \(rebased)")
            return
        }
        #expect(offset != 0)
        #expect(abs(offset) > 5) // a real remainder, not a rounding crumb
        #expect(Self.goalTable.paceSeconds(for: zone) + offset == offBand.rounded()
            || abs(Self.goalTable.paceSeconds(for: zone) + offset - offBand) < 1)

        let resolved = rebased.resolvedPaceSeconds(
            equivalentPaces: Self.goalTable, racePaceSeconds: Self.goalRacePace
        )
        #expect(abs((resolved ?? 0) - offBand) < 1)
    }

    /// A pace that does sit on a zone comes back as the bare zone, not as a
    /// zone carrying a pointless "+0s".
    @Test("a pace sitting on a zone rebases to the bare zone")
    func onBandRebaseDropsTheOffset() {
        let rebased = EditableWorkoutStep.PaceSelection
            .fixed(Self.goalTable.fiveKPace)
            .rebased(onto: Self.goalTable)
        #expect(rebased == .namedPace(.fiveK))
    }

    /// Legs with no pace target don't acquire one by changing basis.
    @Test("untargeted steps are untouched by a basis change")
    func untargetedUnchanged() {
        let none = EditableWorkoutStep.PaceSelection.none
        #expect(none.frozen(with: Self.goalTable, racePaceSeconds: Self.goalRacePace) == .none)
        #expect(none.rebased(onto: Self.goalTable) == .none)

        let timed = EditableWorkoutStep.PaceSelection.targetTime(305)
        #expect(timed.frozen(with: Self.goalTable, racePaceSeconds: Self.goalRacePace) == .targetTime(305))
    }

    // MARK: - Basis change across a whole step

    /// The recovery leg has to move with its parent, or an interval set ends up
    /// half pinned and half floating.
    @Test("a basis change reaches the recovery leg")
    func recoveryFollowsTheStep() {
        var step = EditableWorkoutStep(order: 0, stepType: .active)
        step.paceSelection = .namedPace(.fiveK)
        step.repeats = 6
        step.recovery = EditableWorkoutStep.EditableRecovery(
            durationType: .timeSeconds,
            durationValue: 90,
            paceSelection: .namedPace(.recovery)
        )

        let fixed = step.switchingBasis(
            from: .goal, to: .fixed,
            outgoing: Self.goalTable, incoming: Self.goalTable,
            racePaceSeconds: Self.goalRacePace
        )

        #expect(fixed.paceSelection == .fixed(Self.goalTable.fiveKPace))
        #expect(fixed.recovery?.paceSelection == .fixed(Self.goalTable.recoveryPace))
        #expect(fixed.repeats == 6)
    }

    /// Goal ↔ current changes the table, never the words. The step keeps saying
    /// "5K" and simply means a different clock number.
    @Test("goal to current leaves the zones alone")
    func goalToCurrentKeepsZones() throws {
        let current = try #require(
            EquivalentPaces.fromCurrentFitness(Self.profile(marathon: 450))
        )
        var step = EditableWorkoutStep(order: 0, stepType: .active)
        step.paceSelection = .namedPace(.fiveK)

        let moved = step.switchingBasis(
            from: .goal, to: .current,
            outgoing: Self.goalTable, incoming: current,
            racePaceSeconds: Self.goalRacePace
        )
        #expect(moved.paceSelection == .namedPace(.fiveK))

        // Same words, different number — which is the entire point.
        let goalPace = moved.paceSelection.resolvedPaceSeconds(
            equivalentPaces: Self.goalTable, racePaceSeconds: Self.goalRacePace
        )
        let currentPace = moved.paceSelection.resolvedPaceSeconds(
            equivalentPaces: current, racePaceSeconds: Self.goalRacePace
        )
        #expect(abs((currentPace ?? 0) - (goalPace ?? 0)) > 10)
    }

    // MARK: - Persistence

    /// A fixed pace has to survive the save. Before this, `toPaceIntensity`
    /// wrote only a percentage of race pace, so a workout pinned to 6:30 came
    /// back meaning "94% of whatever MP is today".
    @Test("a fixed pace survives a save and reload")
    func fixedSurvivesRoundTrip() {
        var step = EditableWorkoutStep(order: 0, stepType: .active)
        step.durationType = .distanceMiles
        step.durationValue = 4
        step.paceSelection = .fixed(390) // 6:30/mi

        let saved = step.toWorkoutStep(
            racePaceSeconds: Self.goalRacePace,
            equivalentPaces: Self.goalTable
        )
        // No zone: a fixed pace is not a zone, and writing one would let the
        // next reader re-derive it.
        #expect(saved.paceZone == nil)
        #expect(saved.targetPaceIntensity?.concreteSecondsPerMile != nil)

        let reloaded = EditableWorkoutStep(
            from: saved,
            equivalentPaces: Self.goalTable,
            racePaceSeconds: Self.goalRacePace
        )
        guard case .fixed(let seconds) = reloaded.paceSelection else {
            Issue.record("expected a fixed pace, got \(reloaded.paceSelection)")
            return
        }
        #expect(abs(seconds - 390) < 1)
    }

    /// And a fixed pace must stay put when the goal moves underneath it —
    /// the one guarantee the fixed basis makes.
    @Test("a fixed pace ignores a change of goal")
    func fixedIgnoresGoalChange() {
        var step = EditableWorkoutStep(order: 0, stepType: .active)
        step.paceSelection = .fixed(390)

        let saved = step.toWorkoutStep(
            racePaceSeconds: Self.goalRacePace,
            equivalentPaces: Self.goalTable
        )

        // Athlete drops their goal to a 3:30 marathon and reopens the workout.
        let slowerGoal = EquivalentPaces(raceDistance: .marathon, goalTimeSeconds: 3 * 3600 + 1800)
        let reloaded = EditableWorkoutStep(
            from: saved,
            equivalentPaces: slowerGoal,
            racePaceSeconds: slowerGoal.mpPace
        )
        guard case .fixed(let seconds) = reloaded.paceSelection else {
            Issue.record("expected a fixed pace, got \(reloaded.paceSelection)")
            return
        }
        #expect(abs(seconds - 390) < 1)
    }

    /// A zone step still reloads as a zone. The concrete pace now written
    /// alongside it is a resolution, not a replacement.
    @Test("a zone step still reloads as a zone")
    func zoneStepStaysZoned() {
        var step = EditableWorkoutStep(order: 0, stepType: .active)
        step.paceSelection = .namedPaceOffset(.threshold, 5)

        let saved = step.toWorkoutStep(
            racePaceSeconds: Self.goalRacePace,
            equivalentPaces: Self.goalTable
        )
        #expect(saved.paceZone == .threshold)

        let reloaded = EditableWorkoutStep(
            from: saved,
            equivalentPaces: Self.goalTable,
            racePaceSeconds: Self.goalRacePace
        )
        #expect(reloaded.paceSelection == .namedPaceOffset(.threshold, 5))
    }

    /// The coach-authored shape: a literal "M:SS" with no zone beside it.
    /// It used to be read through the percentage path, divide by a zero
    /// percentage, and land on `.custom(0)`.
    @Test("a coach-written literal pace loads as fixed")
    func coachLiteralLoadsFixed() throws {
        let json = """
        {
          "stepType": "active",
          "durationType": "distance_miles",
          "durationValue": 4,
          "order": 0,
          "target_pace": "6:30"
        }
        """
        let planned = try JSONDecoder().decode(PlannedWorkoutStep.self, from: Data(json.utf8))
        let editable = EditableWorkoutStep(
            from: planned,
            equivalentPaces: Self.goalTable,
            racePaceSeconds: Self.goalRacePace
        )
        guard case .fixed(let seconds) = editable.paceSelection else {
            Issue.record("expected a fixed pace, got \(editable.paceSelection)")
            return
        }
        #expect(abs(seconds - 390) < 1)
    }

    // MARK: - Writing a fixed pace in the rep's own units

    /// The case this was built for: "10 x K @ 10k" flipped to a number has to
    /// read "3:30", not "5:38/mi". A coach writing kilometre reps thinks in rep
    /// times, and a conversion-per-rep is enough friction to make the absolute
    /// path not worth using.
    @Test("a kilometre rep is written as its rep time")
    func kilometreRepReadsAsRepTime() {
        let oneKInMiles = 1.0 / RaceDistanceConstants.kmPerMile
        let secPerMile = FixedPaceUnit.perRep.secPerMile(fromDisplay: 210, repMiles: oneKInMiles)

        // 3:30 per K is 5:38/mi.
        #expect(abs(secPerMile - 337.96) < 0.5)
        #expect(PaceCalculator.formatPace(secPerMile) == "5:38")

        // And back again, unchanged.
        let shown = FixedPaceUnit.perRep.display(fromSecPerMile: secPerMile, repMiles: oneKInMiles)
        #expect(abs(shown - 210) < 0.01)
    }

    /// For a 1 km rep the rep time and the per-km pace are the same number.
    /// If these ever disagree, one of the two conversions is wrong.
    @Test("a 1K rep time equals the per-kilometre pace")
    func repTimeAgreesWithPerKm() {
        let oneKInMiles = 1.0 / RaceDistanceConstants.kmPerMile
        let fromRep = FixedPaceUnit.perRep.secPerMile(fromDisplay: 210, repMiles: oneKInMiles)
        let fromKm = FixedPaceUnit.perKm.secPerMile(fromDisplay: 210, repMiles: oneKInMiles)
        #expect(abs(fromRep - fromKm) < 0.01)
    }

    @Test("every unit round-trips without drift")
    func unitsRoundTrip() {
        let reps: [Double?] = [
            nil,                                  // time-based step
            1.0,                                  // 1 mile
            1.0 / RaceDistanceConstants.kmPerMile, // 1 km
            800 / RaceDistanceConstants.meterPerMile,
            4.0,
        ]
        for unit in FixedPaceUnit.allCases {
            for repMiles in reps {
                for secPerMile in [300.0, 362.0, 420.0, 540.0] {
                    let shown = unit.display(fromSecPerMile: secPerMile, repMiles: repMiles)
                    let back = unit.secPerMile(fromDisplay: shown, repMiles: repMiles)
                    #expect(abs(back - secPerMile) < 0.01)
                }
            }
        }
    }

    /// An 800 in 2:48 is 5:38/mi — the same pace as the K in 3:30 above,
    /// which is the arithmetic a coach is doing in their head today.
    @Test("an 800 rep time converts on the real distance")
    func eightHundredRepTime() {
        let eightHundred = 800 / RaceDistanceConstants.meterPerMile
        let secPerMile = FixedPaceUnit.perRep.secPerMile(fromDisplay: 168, repMiles: eightHundred)
        #expect(PaceCalculator.formatPace(secPerMile) == "5:38")
    }

    /// A rep time for a long rep is legitimately far outside a per-mile pace
    /// band — 4 miles at 6:00/mi is 24:00 — so the field's sanity check has to
    /// scale with the unit or it would refuse every valid entry.
    @Test("plausible bounds scale with the unit")
    func boundsScaleWithUnit() {
        let fourMiles = 4.0
        let repBounds = FixedPaceUnit.perRep.plausibleBounds(repMiles: fourMiles)
        #expect(repBounds.contains(24 * 60))       // 4mi at 6:00/mi
        #expect(!repBounds.contains(6 * 60))       // 6:00 for 4 miles is not running

        let mileBounds = FixedPaceUnit.perMile.plausibleBounds(repMiles: fourMiles)
        #expect(mileBounds.contains(6 * 60))
        #expect(!mileBounds.contains(24 * 60))
    }

    /// A rep time needs a rep. Time-based steps have none, and the conversion
    /// must not divide by zero and hand back an infinite pace.
    @Test("a rep time with no rep distance is inert")
    func repTimeWithoutARep() {
        let value = FixedPaceUnit.perRep.secPerMile(fromDisplay: 360, repMiles: nil)
        #expect(value == 360)
        #expect(value.isFinite)
        let zero = FixedPaceUnit.perRep.secPerMile(fromDisplay: 360, repMiles: 0)
        #expect(zero.isFinite)
    }

    // MARK: - Labelling

    /// A workout pinned to numbers still needs a name. Without the table to
    /// ask, "LT 5×1mi" degrades to "Workout 5×1mi" and that is what gets saved.
    @Test("a fixed workout keeps a real name")
    func fixedWorkoutKeepsItsLabel() {
        var step = EditableWorkoutStep(order: 0, stepType: .active)
        step.durationType = .distanceMiles
        step.durationValue = 1
        step.repeats = 5
        step.paceSelection = .fixed(Self.goalTable.thresholdPace)

        let named = WorkoutLabelGrammar.summaryLine(
            steps: [step], equivalentPaces: Self.goalTable
        )
        #expect(named?.contains("Workout") == false)
        #expect(named?.contains("5×1mi") == true)

        // Without a table there is nothing to resolve against, and the grammar
        // says so rather than guessing.
        let unnamed = WorkoutLabelGrammar.summaryLine(steps: [step])
        #expect(unnamed == "Workout 5×1mi")
    }
}
