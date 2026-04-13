import Foundation
import Testing
@testable import RunningLog

// MARK: - Mock Data Sources

struct MockWorkoutDataSource: WorkoutDataSource {
    var workouts: [RunningWorkout] = []

    func fetchRunningWorkouts(startDate: Date, endDate: Date) async -> [RunningWorkout] {
        workouts
    }

    func fetchRunningMilesByDate(startDate: Date, endDate: Date) async -> [String: Double] {
        [:]
    }
}

struct MockAuthProvider: AuthProvider {
    var currentUserId: String? = "test-user"
    var userEmail: String? = "test@test.com"
    var isAuthenticated: Bool = true
}

// MARK: - Tests

@Suite("Workout Classification")
struct ClassificationTests {
    let predictor = FitnessPredictorService(
        workoutSources: [MockWorkoutDataSource()],
        auth: MockAuthProvider()
    )

    @Test("Long run: 10+ miles")
    func longRun() {
        #expect(predictor.classifyWorkout(distance: 12.0, pace: 520) == "Long Run")
        #expect(predictor.classifyWorkout(distance: 10.0, pace: 480) == "Long Run")
    }

    @Test("Speed work: pace under 7:00/mi")
    func speedWork() {
        #expect(predictor.classifyWorkout(distance: 5.0, pace: 390) == "Speed Work")
        #expect(predictor.classifyWorkout(distance: 3.0, pace: 350) == "Speed Work")
    }

    @Test("Tempo: pace 7:00-8:00/mi")
    func tempo() {
        #expect(predictor.classifyWorkout(distance: 6.0, pace: 450) == "Tempo")
    }

    @Test("Recovery: short and slow")
    func recovery() {
        #expect(predictor.classifyWorkout(distance: 3.0, pace: 540) == "Recovery")
    }

    @Test("Easy run: moderate distance, easy pace")
    func easyRun() {
        #expect(predictor.classifyWorkout(distance: 6.0, pace: 520) == "Easy Run")
    }
}

@Suite("Pace Conversion (Jack Daniels equivalents)")
struct PaceConversionTests {
    let predictor = FitnessPredictorService(
        workoutSources: [MockWorkoutDataSource()],
        auth: MockAuthProvider()
    )

    @Test("5K to 10K: ~4% slower")
    func fiveKToTenK() {
        let fiveKPace = 360.0 // 6:00/mi
        let tenKPace = predictor.convert(racePace: fiveKPace, from: .fiveK, to: .tenK)
        // 360 / 0.96 * 1.0 = 375 (6:15/mi)
        #expect(tenKPace > 370 && tenKPace < 380)
    }

    @Test("10K to half: slower pace")
    func tenKToHalf() {
        let tenKPace = 375.0 // 6:15/mi
        let halfPace = predictor.convert(racePace: tenKPace, from: .tenK, to: .half)
        // Half should be slower than 10K
        #expect(halfPace > tenKPace)
        // Should be roughly 4-6% slower (based on ratio table: 2.204167 / 1.0 applied to time)
        #expect(halfPace > 388 && halfPace < 396)
    }

    @Test("Marathon to 10K: faster")
    func marathonToTenK() {
        let marathonPace = 420.0 // 7:00/mi
        let tenKPace = predictor.convert(racePace: marathonPace, from: .marathon, to: .tenK)
        // 420 / 1.105 * 1.0 = 380.1 (6:20/mi)
        #expect(tenKPace < marathonPace)
        #expect(tenKPace > 375 && tenKPace < 385)
    }

    @Test("Identity conversion: same distance returns same pace")
    func identity() {
        let pace = 400.0
        let result = predictor.convert(racePace: pace, from: .tenK, to: .tenK)
        // With double precision, identity should be exact (ratio / ratio = 1.0)
        #expect(abs(result - pace) < 0.001)
    }

    @Test("Mile to marathon: significant slowdown")
    func mileToMarathon() {
        let milePace = 300.0 // 5:00/mi
        let marathonPace = predictor.convert(racePace: milePace, from: .mile, to: .marathon)
        // 300 / 0.88 * 1.105 = 376.7 (6:16/mi)
        #expect(marathonPace > milePace * 1.2)
    }
}

@Suite("Pace Extraction from Text")
struct PaceExtractionTests {
    let predictor = FitnessPredictorService(
        workoutSources: [MockWorkoutDataSource()],
        auth: MockAuthProvider()
    )

    @Test("Extracts valid pace from text")
    func extractValidPace() {
        let paces = predictor.extractPaces(from: "Did 4 miles at 7:30 pace today")
        #expect(paces.contains("7:30/mi"))
    }

    @Test("Extracts multiple paces")
    func extractMultiplePaces() {
        let paces = predictor.extractPaces(from: "Intervals: 6:00 then 5:45 recovery at 8:30")
        #expect(paces.count == 3)
    }

    @Test("Ignores unreasonable paces")
    func ignoreUnreasonable() {
        // 3:00 is too fast, 16:00 is too slow
        let paces = predictor.extractPaces(from: "Time was 3:00 and also 16:00")
        #expect(paces.isEmpty)
    }

    @Test("Handles edge cases")
    func edgeCases() {
        let paces = predictor.extractPaces(from: "No paces mentioned here")
        #expect(paces.isEmpty)
    }
}

@Suite("Workout Merge Deduplication")
struct MergeTests {
    let predictor = FitnessPredictorService(
        workoutSources: [MockWorkoutDataSource()],
        auth: MockAuthProvider()
    )

    @Test("Deduplicates workouts with same date and similar distance")
    func deduplicates() {
        let base = [
            WorkoutData(date: "2026-03-10", distanceMiles: 6.2, durationMinutes: 50, paceSecondsPerMile: 484, heartRateAvg: nil, type: "Easy Run")
        ]
        let additions = [
            WorkoutData(date: "2026-03-10", distanceMiles: 6.3, durationMinutes: 51, paceSecondsPerMile: 486, heartRateAvg: nil, type: "Easy Run")
        ]
        let merged = predictor.mergeWorkouts(base, additions)
        #expect(merged.count == 1) // duplicate removed
    }

    @Test("Keeps workouts on different dates")
    func keepsDifferentDates() {
        let base = [
            WorkoutData(date: "2026-03-10", distanceMiles: 6.0, durationMinutes: 48, paceSecondsPerMile: 480, heartRateAvg: nil, type: "Easy Run")
        ]
        let additions = [
            WorkoutData(date: "2026-03-11", distanceMiles: 6.0, durationMinutes: 48, paceSecondsPerMile: 480, heartRateAvg: nil, type: "Easy Run")
        ]
        let merged = predictor.mergeWorkouts(base, additions)
        #expect(merged.count == 2)
    }

    @Test("Keeps workouts with different distances on same date")
    func keepsDifferentDistances() {
        let base = [
            WorkoutData(date: "2026-03-10", distanceMiles: 6.0, durationMinutes: 48, paceSecondsPerMile: 480, heartRateAvg: nil, type: "Easy Run")
        ]
        let additions = [
            WorkoutData(date: "2026-03-10", distanceMiles: 3.0, durationMinutes: 24, paceSecondsPerMile: 480, heartRateAvg: nil, type: "Recovery")
        ]
        let merged = predictor.mergeWorkouts(base, additions)
        #expect(merged.count == 2) // different distances = different workouts
    }
}

@Suite("Race Type Properties")
struct RaceTypeTests {
    @Test("Distance miles are correct")
    func distanceMiles() {
        #expect(abs(FitnessPredictorService.RaceType.mile.distanceMiles - 1.0) < 0.01)
        #expect(abs(FitnessPredictorService.RaceType.fiveK.distanceMiles - 3.107) < 0.01)
        #expect(abs(FitnessPredictorService.RaceType.tenK.distanceMiles - 6.214) < 0.01)
        #expect(abs(FitnessPredictorService.RaceType.half.distanceMiles - 13.109) < 0.01)
        #expect(abs(FitnessPredictorService.RaceType.marathon.distanceMiles - 26.219) < 0.01)
    }

    @Test("Tolerance values make sense")
    func tolerances() {
        // Tolerance should be proportional to distance
        let types: [FitnessPredictorService.RaceType] = [.mile, .fiveK, .tenK, .half, .marathon]
        for raceType in types {
            let pct = raceType.tolerance / raceType.distanceMiles
            #expect(pct > 0.03 && pct < 0.10, "Tolerance for \(raceType.rawValue) should be 3-10%")
        }
    }
}
