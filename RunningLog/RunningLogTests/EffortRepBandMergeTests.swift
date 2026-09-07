import Foundation
import Testing
@testable import RunningLog

/// The Effort chart's band count for a lapped-by-the-mile workout.
///
/// Real case (2026-08-29, the 21-mile 4×3mi long-run workout): the watch laid
/// down 23 laps — 7 warmup miles, then 4 × (three 1-mile work laps back to
/// back) with a half-mile float between reps, and a cooldown. The parser's
/// `lap_roles` tag the 12 work miles as "rep" and the floats as "recovery".
///
/// The rep is the unit: those 12 work miles must band as FOUR reps, one per
/// 3-mile bout, with the mile detail carried by the bout's members (and the
/// SPLITS overlay) — never as twelve rep bands. That regression shipped on
/// 2026-08-30 (un-merge, `22d37f1`) and was reverted the same night
/// (`59dabe0`); this pins the pipeline on the run that exposed it.
@Suite("Effort rep-band merge (4×3mi)")
struct EffortRepBandMergeTests {

    private func lap(_ i: Int, m: Double, mov: Int, elap: Int, pace: Double, hr: Int) -> WorkoutLapRow {
        WorkoutLapRow(
            lap_index: i,
            distance_meters: m,
            moving_time_seconds: mov,
            elapsed_time_seconds: elap,
            avg_pace_sec_per_mile: pace,
            avg_heart_rate: hr,
            is_rest: false           // as stored: the DB flagged nothing as rest
        )
    }

    /// The 23 laps as recorded (distances/times from the live row).
    private var rawLaps: [WorkoutLapRow] {
        [
            lap(1, m: 1609, mov: 464, elap: 464, pace: 464, hr: 133),
            lap(2, m: 1609, mov: 433, elap: 433, pace: 433, hr: 138),
            lap(3, m: 1609, mov: 432, elap: 432, pace: 432, hr: 138),
            lap(4, m: 1609, mov: 435, elap: 512, pace: 435, hr: 141),
            lap(5, m: 1609, mov: 417, elap: 417, pace: 417, hr: 143),
            lap(6, m: 1609, mov: 411, elap: 411, pace: 411, hr: 145),
            lap(7, m: 1609, mov: 622, elap: 683, pace: 622, hr: 141),
            lap(8, m: 1609, mov: 370, elap: 521, pace: 370, hr: 152),
            lap(9, m: 1609, mov: 369, elap: 369, pace: 369, hr: 154),
            lap(10, m: 1609, mov: 368, elap: 368, pace: 368, hr: 155),
            lap(11, m: 805, mov: 228, elap: 281, pace: 456, hr: 142),
            lap(12, m: 1609, mov: 368, elap: 368, pace: 368, hr: 154),
            lap(13, m: 1609, mov: 367, elap: 367, pace: 367, hr: 154),
            lap(14, m: 1609, mov: 364, elap: 364, pace: 364, hr: 157),
            lap(15, m: 761, mov: 221, elap: 322, pace: 468, hr: 144),
            lap(16, m: 1609, mov: 362, elap: 362, pace: 362, hr: 157),
            lap(17, m: 1609, mov: 361, elap: 361, pace: 361, hr: 160),
            lap(18, m: 1609, mov: 358, elap: 358, pace: 358, hr: 162),
            lap(19, m: 820, mov: 245, elap: 331, pace: 481, hr: 146),
            lap(20, m: 1609, mov: 349, elap: 349, pace: 349, hr: 162),
            lap(21, m: 1609, mov: 332, elap: 332, pace: 332, hr: 172),
            lap(22, m: 1609, mov: 330, elap: 330, pace: 330, hr: 175),
            lap(23, m: 846, mov: 257, elap: 326, pace: 489, hr: 147),
        ]
    }

    /// `parsed_structure.lap_roles` for the run, verbatim.
    private var roles: [Int: String] {
        var map: [Int: String] = [:]
        for i in 1...7 { map[i] = "warmup" }
        for i in [8, 9, 10, 12, 13, 14, 16, 17, 18, 20, 21, 22] { map[i] = "rep" }
        for i in [11, 15, 19] { map[i] = "recovery" }
        map[23] = "cooldown"
        return map
    }

    /// The receipt's role override, verbatim: only a "rep" is work.
    private var roleOverriddenLaps: [WorkoutLapRow] {
        rawLaps.map { row in
            guard let idx = row.lap_index, let role = roles[idx] else { return row }
            var r = row
            r.is_rest = role != "rep"
            return r
        }
    }

    /// With warmup/floats/cooldown marked rest, the run must not read as a
    /// continuous auto-lap run — that path would band ZERO reps.
    @Test func roleOverriddenRunIsNotContinuous() {
        #expect(WorkoutLapsService.isContinuousAutoLap(roleOverriddenLaps) == false)
    }

    /// The merge must band the 12 work miles as exactly 4 reps of ~3 miles,
    /// each keeping its 3 recorded mile laps as members for the drill-down.
    @Test func fourByThreeMileBandsAsFourReps() {
        let merged = WorkoutLapsService.mergeWorkBoutsDetailed(roleOverriddenLaps)
        let work = merged.filter { $0.lap.is_rest != true }

        #expect(work.count == 4)
        for bout in work {
            #expect(bout.members.count == 3)
            let meters = bout.lap.distance_meters ?? 0
            #expect(abs(meters - 3 * 1609.344) < 25)
        }

        // Rest rows pass through untouched: 7 warmup + 3 floats + 1 cooldown.
        let rests = merged.filter { $0.lap.is_rest == true }
        #expect(rests.count == 11)

        // The merged bout keeps a wall clock (all members carried elapsed), so
        // the chart can locate it on the stream's elapsed axis.
        #expect(work.allSatisfy { ($0.lap.elapsed_time_seconds ?? 0) > 0 })
    }

    /// Rep paces of the four bouts — the numbers the bands print. Moving-time
    /// per merged mile: ≈6:09 / 6:06 / 6:00 / 5:37.
    @Test func mergedRepPacesMatchTheSession() {
        let merged = WorkoutLapsService.mergeWorkBoutsDetailed(roleOverriddenLaps)
        let paces = merged.filter { $0.lap.is_rest != true }
            .compactMap { $0.lap.avg_pace_sec_per_mile }
        let expected: [Double] = [369, 366.33, 360.33, 337]   // sec/mi
        #expect(paces.count == expected.count)
        for (got, want) in zip(paces, expected) {
            #expect(abs(got - want) < 2)
        }
    }
}
