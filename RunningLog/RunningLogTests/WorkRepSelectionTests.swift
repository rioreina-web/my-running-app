import Foundation
import Testing
@testable import RunningLog

/// Tests for `WorkoutLapsService.workReps` — which segments of a workout count
/// as work reps, and therefore what REP AVG, SPREAD and the numbered rows in the
/// splits table are computed over.
///
/// The 2026-09-07 report: "it still makes up its workout splits, and I can't
/// change the structure with Fix reps — it does nothing." A hand-correction was
/// being stored correctly and read back correctly, then flattened on the way to
/// the screen: `parsed_structure.blocks` collapse to a single `is_rest` bit, so
/// only `recovery` survived as not-work and the athlete's warm-up and cool-down
/// came back as work reps. A corrected 3 × 1k read as five reps with the warm-up
/// pace in the average — indistinguishable, from the athlete's side, from the
/// correction being thrown away.
@Suite("Work-rep selection")
struct WorkRepSelectionTests {

    private func lap(
        _ i: Int, m: Double, s: Int, pace: Double,
        rest: Bool = false, role: String? = nil
    ) -> WorkoutLapRow {
        WorkoutLapRow(
            lap_index: i,
            distance_meters: m,
            moving_time_seconds: s,
            avg_pace_sec_per_mile: pace,
            avg_heart_rate: 160,
            is_rest: rest,
            role: role
        )
    }

    /// The corrected session: warm-up, 3 × 1k with jog recoveries, cool-down.
    /// Exactly three reps — not five.
    private var correctedSession: [WorkoutLapRow] {
        [
            lap(0, m: 2400, s: 780, pace: 523, role: "warmup"),
            lap(1, m: 1000, s: 190, pace: 306, role: "work_rep"),
            lap(2, m: 200,  s: 80,  pace: 640, rest: true, role: "recovery"),
            lap(3, m: 1000, s: 193, pace: 311, role: "work_rep"),
            lap(4, m: 200,  s: 82,  pace: 650, rest: true, role: "recovery"),
            lap(5, m: 1000, s: 188, pace: 303, role: "work_rep"),
            lap(6, m: 1600, s: 540, pace: 543, role: "cooldown"),
        ]
    }

    @Test func handCorrectionCountsOnlyWorkReps() {
        let reps = WorkoutLapsService.workReps(
            correctedSession, isContinuous: false, trustRestTags: true)
        #expect(reps.count == 3)
        #expect(reps.allSatisfy { $0.role == "work_rep" })
    }

    /// The warm-up is not a rep, so its pace must not reach REP AVG or SPREAD.
    /// With it counted, the spread on this session was 240s instead of 8s.
    @Test func warmupAndCooldownStayOutOfTheSpread() {
        let paces = WorkoutLapsService
            .workReps(correctedSession, isContinuous: false, trustRestTags: true)
            .compactMap(\.avg_pace_sec_per_mile)
        #expect(paces.max()! - paces.min()! == 8)
    }

    /// The athlete's verdict outranks the length heuristics: 100m strides they
    /// entered by hand are reps, even though a raw 100m lap would be discarded
    /// as too short to be one.
    @Test func aHandEnteredShortRepIsKept() {
        let strides = (0..<4).map { lap($0, m: 100, s: 19, pace: 306, role: "work_rep") }
        let reps = WorkoutLapsService.workReps(strides, isContinuous: false, trustRestTags: true)
        #expect(reps.count == 4)
    }

    /// A named block with no measurable geometry is still dropped — a rep with
    /// no distance or time has no pace to show.
    @Test func anEmptyNamedBlockIsStillDropped() {
        let rows = [
            lap(0, m: 1000, s: 190, pace: 306, role: "work_rep"),
            lap(1, m: 0,    s: 0,   pace: 0,   role: "work_rep"),
        ]
        #expect(WorkoutLapsService.workReps(rows, isContinuous: false, trustRestTags: true).count == 1)
    }

    /// Raw watch laps carry no role, so the existing behaviour is untouched: a
    /// tagged rest is out, a tagged work lap is in however slow it ran.
    @Test func untaggedLapsKeepTheOldRules() {
        let rows = [
            lap(0, m: 1000, s: 190, pace: 306),
            lap(1, m: 200,  s: 80,  pace: 640, rest: true),
            lap(2, m: 1609, s: 705, pace: 705),   // an 11:45 mile — a faded rep
        ]
        #expect(WorkoutLapsService.workReps(rows, isContinuous: false, trustRestTags: true).count == 2)
        // Without trustworthy tags the pace cap is all we have, so the faded
        // mile reads as a jog.
        #expect(WorkoutLapsService.workReps(rows, isContinuous: false, trustRestTags: false).count == 1)
    }

    /// A continuous run has no reps at all, whatever the segments say.
    @Test func continuousRunHasNoReps() {
        #expect(WorkoutLapsService.workReps(
            correctedSession, isContinuous: true, trustRestTags: true).isEmpty)
    }
}

/// The rule that decides whether a run has REPS at all, and where its splits
/// come from.
///
/// The 2026-09-07 report, twice: "it still makes up its workout splits" and
/// "it needs to just look at the splits." A real 3 × 30 min session was recorded
/// by the watch as 29 uniform 1 km auto-laps with ZERO rest laps. Two separate
/// mechanisms then invented a rep structure on top of it — the parser's
/// `lap_roles` overwriting each lap's `is_rest`, and `mergeWorkBouts` joining
/// consecutive non-rest laps into a bout. Both are gone. The splits are the
/// laps, and the only rest signal left is `running_workout_laps.is_rest`, a
/// generated column over the lap's own measurements.
@Suite("Splits come from the recording")
struct RecordedSplitsTests {

    private func lap(_ i: Int, m: Double, s: Int, pace: Double, rest: Bool = false) -> WorkoutLapRow {
        WorkoutLapRow(lap_index: i, distance_meters: m, moving_time_seconds: s,
                      avg_pace_sec_per_mile: pace, avg_heart_rate: 160, is_rest: rest)
    }

    /// The reported run as the watch recorded it: 29 kilometre auto-laps, no
    /// rests. A slower warm-up, a steady middle, a slower end — nothing but the
    /// pace distinguishes it from an interval day, which is exactly why the app
    /// must not try.
    private var reportedRun: [WorkoutLapRow] {
        let paces: [Double] = [465, 431, 365, 377, 375, 370, 373, 373, 365, 362,
                               430, 372, 354, 367, 377, 378, 375, 370, 365, 435,
                               386, 362, 396, 380, 373, 372, 407, 430, 481]
        return paces.enumerated().map { i, p in
            lap(i + 1, m: i == 28 ? 611 : 1000, s: Int(p * (i == 28 ? 0.38 : 0.62)), pace: p)
        }
    }

    @Test func theWatchLappedItContinuously() {
        #expect(WorkoutLapsService.isContinuousAutoLap(reportedRun) == true)
    }

    /// The load rule: nothing in the recording trips the rest column, so the run
    /// is splits and carries no reps. Three of those laps ran under 6:10/mi and
    /// would each have passed the work-rep pace cap on their own — the point is
    /// that no rep boundary exists to put them behind.
    @Test func aRunWithNoRecordedRestHasNoReps() {
        #expect(reportedRun.contains { $0.is_rest == true } == false)
        #expect(WorkoutLapsService.workReps(
            reportedRun, isContinuous: true, trustRestTags: false).isEmpty)
    }

    /// And when the recording DOES mark rests, the reps are the laps between
    /// them — at the watch's own granularity, nothing joined. A 2 km rep the
    /// watch auto-split at the kilometre is two rows, because that is what was
    /// written down; "Fix reps" is where it becomes one.
    @Test func recordedRestsGiveRepsAtLapGranularity() {
        let session = [
            lap(0, m: 1000, s: 190, pace: 306),
            lap(1, m: 1000, s: 193, pace: 311),
            lap(2, m: 120,  s: 90,  pace: 724, rest: true),   // under 200m → rest
            lap(3, m: 1000, s: 195, pace: 314),
            lap(4, m: 1000, s: 198, pace: 319),
        ]
        let reps = WorkoutLapsService.workReps(session, isContinuous: false, trustRestTags: true)
        #expect(reps.count == 4)
        #expect(reps.map { $0.distance_meters } == [1000, 1000, 1000, 1000])
    }

    /// Where the recording marks rests, the tags are measured rather than
    /// inferred, so the pace cap is skipped and a rep that faded stays a rep.
    @Test func aFadedRepSurvivesWhenTheRestTagsAreMeasured() {
        let session = [
            lap(0, m: 1609, s: 400, pace: 400),   // slower than the 370 cap
            lap(1, m: 120,  s: 90,  pace: 724, rest: true),
            lap(2, m: 1609, s: 705, pace: 705),   // an 11:45 mile — faded, still a rep
        ]
        #expect(WorkoutLapsService.workReps(
            session, isContinuous: false, trustRestTags: true).count == 2)
    }
}
