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

/// Tests for `WorkoutLapsService.mergeWorkBouts` — the deterministic re-join of
/// consecutive work laps into one rep, which is what the splits table and the
/// rep bars are drawn from.
@Suite("Work-bout merge")
struct WorkBoutMergeTests {

    private func lap(
        _ i: Int, m: Double?, s: Int?, pace: Double?, rest: Bool = false
    ) -> WorkoutLapRow {
        WorkoutLapRow(
            lap_index: i,
            distance_meters: m,
            moving_time_seconds: s,
            avg_pace_sec_per_mile: pace,
            avg_heart_rate: 160,
            is_rest: rest
        )
    }

    /// Two auto-split kilometres re-joined into one 2k rep, at the pace the
    /// athlete actually ran.
    @Test func consecutiveWorkLapsJoinAtTheirRealPace() {
        let merged = WorkoutLapsService.mergeWorkBouts([
            lap(0, m: 1000, s: 268, pace: 431),
            lap(1, m: 1000, s: 262, pace: 422),
            lap(2, m: 200,  s: 90,  pace: 724, rest: true),
        ])
        #expect(merged.count == 2)
        #expect(merged[0].distance_meters == 2000)
        #expect(merged[0].moving_time_seconds == 530)
        // 530s over 1.2427 mi = 426.4 s/mi — between the two laps, as it must be.
        let pace = merged[0].avg_pace_sec_per_mile ?? 0
        #expect(pace > 422 && pace < 431)
    }

    /// A merged bout can never be faster than the fastest lap inside it. A lap
    /// whose duration didn't come through used to add its distance for free,
    /// which is how a bout of 7:11 kilometres reported 6:13/mi.
    @Test func aLapMissingItsDurationCannotSpeedUpTheBout() {
        let merged = WorkoutLapsService.mergeWorkBouts([
            lap(0, m: 1000, s: 268, pace: 431),
            lap(1, m: 1000, s: nil, pace: nil),   // duration never ingested
        ])
        #expect(merged.count == 1)
        let pace = merged[0].avg_pace_sec_per_mile ?? 0
        #expect(pace >= 431)
        // The bout states only the geometry it can actually account for.
        #expect(merged[0].distance_meters == 1000)
        #expect(merged[0].moving_time_seconds == 268)
    }
}

/// Why `WorkoutRepReceiptView.load()` asks `isContinuousAutoLap` about the
/// WATCH's laps and never about the parser-relabelled copy.
///
/// The 2026-09-07 report, "it still makes up its own splits": a real 3 × 30 min
/// session was recorded by the watch as 29 uniform 1 km auto-laps with ZERO rest
/// laps — a continuous run, by the watch's own account. The parser's `lap_roles`
/// then marked a handful of them warmup / recovery / cooldown, `load()` fed those
/// relabelled rows to the continuity check, the extra "rests" pushed it over the
/// sparse-rest threshold, and the run fell through to `mergeWorkBouts`, which
/// published three rep boundaries nothing had recorded. 11 of the athlete's runs
/// carried invented boundaries this way.
@Suite("Continuity is the watch's call")
struct ContinuityProvenanceTests {

    private func lap(_ i: Int, m: Double, s: Int, pace: Double, rest: Bool = false) -> WorkoutLapRow {
        WorkoutLapRow(lap_index: i, distance_meters: m, moving_time_seconds: s,
                      avg_pace_sec_per_mile: pace, avg_heart_rate: 160, is_rest: rest)
    }

    /// The reported run, as the watch recorded it: 29 kilometre auto-laps, no
    /// rests. Paces are the real ones — a slower warm-up, steady middle, slower
    /// end — so nothing but the lap tags distinguishes it from an interval day.
    private var watchLaps: [WorkoutLapRow] {
        let paces: [Double] = [465, 431, 365, 377, 375, 370, 373, 373, 365, 362,
                               430, 372, 354, 367, 377, 378, 375, 370, 365, 435,
                               386, 362, 396, 380, 373, 372, 407, 430, 481]
        return paces.enumerated().map { i, p in
            lap(i + 1, m: i == 28 ? 611 : 1000, s: Int(p * (i == 28 ? 0.38 : 0.62)), pace: p)
        }
    }

    @Test func theWatchSaysContinuous() {
        #expect(WorkoutLapsService.isContinuousAutoLap(watchLaps) == true)
    }

    /// The same run once the parser has had its say. This is the input `load()`
    /// used to pass, and it answers the opposite way — which is the whole bug.
    @Test func theParsersRelabelledCopyDoesNot() {
        let inventedRests: Set<Int> = [1, 2, 11, 20, 27, 28, 29]
        let relabelled = watchLaps.map { row -> WorkoutLapRow in
            var r = row
            if let i = r.lap_index, inventedRests.contains(i) { r.is_rest = true }
            return r
        }
        #expect(WorkoutLapsService.isContinuousAutoLap(relabelled) == false)
    }

    /// And it is the merge of that relabelled copy that manufactures the reps:
    /// three bouts the watch never recorded a boundary for.
    @Test func mergingTheRelabelledCopyManufacturesReps() {
        let inventedRests: Set<Int> = [1, 2, 11, 20, 27, 28, 29]
        let relabelled = watchLaps.map { row -> WorkoutLapRow in
            var r = row
            if let i = r.lap_index, inventedRests.contains(i) { r.is_rest = true }
            return r
        }
        let merged = WorkoutLapsService.mergeWorkBouts(relabelled)
        let reps = WorkoutLapsService.workReps(merged, isContinuous: false, trustRestTags: true)
        #expect(reps.count == 3)
        // Whereas the watch's own record yields no reps at all, which is the
        // honest answer and what the screen now shows.
        #expect(WorkoutLapsService.workReps(
            watchLaps, isContinuous: true, trustRestTags: false).isEmpty)
    }
}
