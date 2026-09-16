import Foundation
import Testing
@testable import RunningLog

/// Tests for `WorkoutLapsService.isContinuousAutoLap` — the guard that keeps a
/// continuous run (uniform watch auto-laps) from being sliced into fake "reps".
/// See the 2026-07-12 fix: a long run with a couple of pauses was rendered as a
/// 3-rep interval session. These lock in the correct behavior AND protect the
/// June interval-parsing fix from regressing.
@Suite("Continuous auto-lap detection")
struct ContinuousAutoLapTests {

    private func lap(_ i: Int, m: Double, s: Int, pace: Double, rest: Bool = false) -> WorkoutLapRow {
        WorkoutLapRow(
            lap_index: i,
            distance_meters: m,
            moving_time_seconds: s,
            avg_pace_sec_per_mile: pace,
            avg_heart_rate: 150,
            is_rest: rest
        )
    }

    /// The real bug: a 24 km long run auto-lapped every km, with a 7:24 regroup
    /// and a 0:49 water break recorded as rest laps. Must read continuous.
    @Test func longRunWithPausesIsContinuous() {
        var laps: [WorkoutLapRow] = []
        var idx = 0
        for k in 0..<24 {
            laps.append(lap(idx, m: 1000, s: 270, pace: 435)); idx += 1
            if k == 1 { laps.append(lap(idx, m: 8, s: 444, pace: 0, rest: true)); idx += 1 }   // 7:24 regroup
            if k == 15 { laps.append(lap(idx, m: 16, s: 49, pace: 0, rest: true)); idx += 1 }   // 0:49 water
        }
        #expect(WorkoutLapsService.isContinuousAutoLap(laps) == true)
    }

    /// 6×1k with a jog recovery after every rep — a real interval session.
    /// Must NOT be treated as continuous (the June segmentation must survive).
    @Test func intervalSessionIsNotContinuous() {
        var laps: [WorkoutLapRow] = []
        var idx = 0
        for _ in 0..<6 {
            laps.append(lap(idx, m: 1000, s: 190, pace: 306)); idx += 1          // hard 1k
            laps.append(lap(idx, m: 200, s: 80, pace: 640, rest: true)); idx += 1 // jog
        }
        #expect(WorkoutLapsService.isContinuousAutoLap(laps) == false)
    }

    /// Even when the watch fails to flag the recoveries (Maya's case), the short
    /// jog laps drag the uniformity ratio below threshold — still not continuous.
    @Test func intervalWithUnflaggedRecoveriesIsNotContinuous() {
        var laps: [WorkoutLapRow] = []
        var idx = 0
        for _ in 0..<6 {
            laps.append(lap(idx, m: 1000, s: 190, pace: 306)); idx += 1
            laps.append(lap(idx, m: 200, s: 80, pace: 640, rest: false)); idx += 1 // unflagged jog
        }
        #expect(WorkoutLapsService.isContinuousAutoLap(laps) == false)
    }

    /// A 10-miler lapped every mile with one water pause — continuous.
    @Test func mileLappedLongRunIsContinuous() {
        var laps: [WorkoutLapRow] = []
        var idx = 0
        for k in 0..<10 {
            laps.append(lap(idx, m: 1609, s: 450, pace: 450)); idx += 1
            if k == 5 { laps.append(lap(idx, m: 10, s: 40, pace: 0, rest: true)); idx += 1 }
        }
        #expect(WorkoutLapsService.isContinuousAutoLap(laps) == true)
    }

    /// A short quality session (only a couple laps) is not a uniform-split run.
    @Test func shortSessionIsNotContinuous() {
        let laps = [lap(0, m: 1600, s: 300, pace: 300),
                    lap(1, m: 1600, s: 302, pace: 302)]
        #expect(WorkoutLapsService.isContinuousAutoLap(laps) == false)
    }

    /// The already-merged 3-bout shape (2 km · 14 km · 8 km) must not be
    /// mistaken for uniform auto-laps either — too few, wildly uneven.
    @Test func mergedBoutsAreNotContinuous() {
        let laps = [lap(0, m: 2000, s: 540, pace: 434),
                    lap(1, m: 14000, s: 3818, pace: 439),
                    lap(2, m: 8000, s: 2088, pace: 420)]
        #expect(WorkoutLapsService.isContinuousAutoLap(laps) == false)
    }
}
