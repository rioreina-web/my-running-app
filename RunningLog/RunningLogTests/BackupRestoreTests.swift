import Foundation
import Testing
@testable import RunningLog

// MARK: - FullBackup JSON Round-Trip Tests

@Suite("Backup JSON Encoding")
struct BackupEncodingTests {

    private func makeBackup(logs: Int = 2, plans: Int = 1) -> FullBackup {
        let trainingLogs = (0..<logs).map { i in
            TrainingLog(
                id: UUID(),
                createdAt: Date(),
                audioUrl: nil,
                notes: "Run \(i)",
                cleanedNotes: "Run \(i) cleaned",
                mood: "energized",
                workoutDate: Date(),
                workoutDistanceMiles: 5.0 + Double(i),
                workoutDurationMinutes: 40.0 + Double(i * 5),
                processingStatus: "completed",
                processingError: nil,
                processingAttempts: nil,
                transcriptUrl: nil,
                coachInsight: nil,
                workoutNotes: nil,
                workoutPacePerMile: nil,
                workoutType: "easy",
                source: nil,
                vitalWorkoutId: nil,
                paceSegments: nil
            )
        }

        return FullBackup(
            exportedAt: Date(),
            appVersion: "1.0",
            trainingLogs: trainingLogs,
            trainingPlans: [],
            scheduledWorkouts: [],
            userGoals: [],
            injuries: [],
            fitnessSnapshots: [],
            biomechanicsAnalyses: [],
            formChecks: []
        )
    }

    @Test("FullBackup encodes to JSON")
    func encodesToJSON() throws {
        let backup = makeBackup()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(backup)
        #expect(data.count > 0)
    }

    @Test("FullBackup round-trips through JSON")
    func roundTripsJSON() throws {
        let backup = makeBackup(logs: 3)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(backup)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(FullBackup.self, from: data)

        #expect(restored.trainingLogs.count == 3)
        #expect(restored.appVersion == "1.0")
        #expect(restored.trainingPlans.isEmpty)
        #expect(restored.scheduledWorkouts.isEmpty)
        #expect(restored.userGoals.isEmpty)
        #expect(restored.injuries.isEmpty)
        #expect(restored.fitnessSnapshots.isEmpty)
        #expect(restored.biomechanicsAnalyses.isEmpty)
        #expect(restored.formChecks.isEmpty)
    }

    @Test("FullBackup preserves training log fields")
    func preservesLogFields() throws {
        let backup = makeBackup(logs: 1)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(backup)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(FullBackup.self, from: data)
        let log = restored.trainingLogs[0]

        #expect(log.cleanedNotes == "Run 0 cleaned")
        #expect(log.mood == "energized")
        #expect(log.workoutDistanceMiles == 5.0)
        #expect(log.workoutDurationMinutes == 40.0)
        #expect(log.workoutType == "easy")
    }

    @Test("Empty backup encodes correctly")
    func emptyBackup() throws {
        let backup = FullBackup(
            exportedAt: Date(),
            appVersion: "1.0",
            trainingLogs: [],
            trainingPlans: [],
            scheduledWorkouts: [],
            userGoals: [],
            injuries: [],
            fitnessSnapshots: [],
            biomechanicsAnalyses: [],
            formChecks: []
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(backup)
        let json = String(data: data, encoding: .utf8)!
        #expect(json.contains("\"trainingLogs\""))
        #expect(json.contains("\"appVersion\""))
    }
}

// MARK: - RestoreSummary Tests

@Suite("Restore Summary")
struct RestoreSummaryTests {

    @Test("Total records sums all tables")
    func totalRecords() {
        var summary = RestoreSummary()
        summary.trainingLogs = 10
        summary.trainingPlans = 2
        summary.scheduledWorkouts = 50
        summary.userGoals = 3
        summary.injuries = 1
        summary.fitnessSnapshots = 5
        summary.biomechanicsAnalyses = 2
        summary.formChecks = 4
        #expect(summary.totalRecords == 77)
    }

    @Test("Breakdown filters empty tables")
    func breakdownFilters() {
        var summary = RestoreSummary()
        summary.trainingLogs = 10
        summary.trainingPlans = 0
        summary.userGoals = 3
        // Only non-zero entries
        #expect(summary.breakdown.count == 2)
        #expect(summary.breakdown[0].label == "Training logs")
        #expect(summary.breakdown[0].count == 10)
        #expect(summary.breakdown[1].label == "Goals")
        #expect(summary.breakdown[1].count == 3)
    }

    @Test("Empty summary has zero total")
    func emptySummary() {
        let summary = RestoreSummary()
        #expect(summary.totalRecords == 0)
        #expect(summary.breakdown.isEmpty)
    }
}

// MARK: - AthleteProfileData Decoding Tests

@Suite("Athlete Profile Decoding")
struct AthleteProfileDecodingTests {

    @Test("Decodes minimal profile response")
    func decodesMinimalProfile() throws {
        let json = """
        {
            "profile": {
                "built_at": "2026-03-16T12:00:00Z",
                "data_span_months": 6,
                "total_logs": 100,
                "volume": [],
                "volume_summary": {
                    "current_weekly_avg": 25.0,
                    "peak_weekly_ever": 45.0,
                    "longest_run_ever": 18.5,
                    "total_lifetime_miles": 1200.0,
                    "consistency_score": 0.85
                },
                "pace": [],
                "performance_trajectory": [],
                "injury_history": [],
                "recovery": {
                    "avg_mood_positive_pct": 0.7,
                    "fatigue_after_high_volume_weeks": false,
                    "typical_easy_day_frequency": 2.5
                },
                "preferences": {
                    "most_common_workout_types": ["easy", "long_run"],
                    "avg_long_run_distance": 14.0,
                    "preferred_run_days": ["Monday", "Wednesday", "Saturday"],
                    "trains_consecutively": true
                },
                "goal_history": {
                    "completed": 2,
                    "active": 1,
                    "race_distances_targeted": ["marathon", "half_marathon"]
                }
            },
            "cached": false,
            "processing_time": 450
        }
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(AthleteProfileResponse.self, from: data)

        #expect(response.cached == false)
        #expect(response.processingTime == 450)
        #expect(response.profile.totalLogs == 100)
        #expect(response.profile.volumeSummary.currentWeeklyAvg == 25.0)
        #expect(response.profile.volumeSummary.consistencyScore == 0.85)
        #expect(response.profile.preferences.mostCommonWorkoutTypes.count == 2)
        #expect(response.profile.preferences.trainsConsecutively == true)
        #expect(response.profile.goalHistory.completed == 2)
        #expect(response.profile.goalHistory.raceDistancesTargeted.contains("marathon"))
    }

    @Test("Decodes profile with volume tiers")
    func decodesVolumeTiers() throws {
        let json = """
        {
            "profile": {
                "built_at": "2026-03-16T12:00:00Z",
                "data_span_months": 12,
                "total_logs": 200,
                "volume": [
                    {
                        "tier": "last_6_months",
                        "weight": 1.0,
                        "total_runs": 120,
                        "total_miles": 650.0,
                        "avg_weekly_miles": 25.0,
                        "peak_weekly_miles": 42.0,
                        "avg_runs_per_week": 4.6,
                        "avg_run_distance": 5.4
                    },
                    {
                        "tier": "6_to_12_months",
                        "weight": 0.6,
                        "total_runs": 80,
                        "total_miles": 400.0,
                        "avg_weekly_miles": 15.4,
                        "peak_weekly_miles": 30.0,
                        "avg_runs_per_week": 3.1,
                        "avg_run_distance": 5.0
                    }
                ],
                "volume_summary": {
                    "current_weekly_avg": 25.0,
                    "peak_weekly_ever": 42.0,
                    "longest_run_ever": 20.0,
                    "total_lifetime_miles": 1050.0,
                    "consistency_score": 0.9
                },
                "pace": [
                    {
                        "tier": "last_6_months",
                        "avg_pace_seconds_per_mile": 510,
                        "easy_pace": 550,
                        "fastest_pace": 420
                    }
                ],
                "performance_trajectory": [],
                "injury_history": [
                    {
                        "body_area": "calf",
                        "side": "left",
                        "occurrences": 3,
                        "most_recent": "2026-02-15",
                        "avg_severity": 4.5,
                        "is_recurring": true
                    }
                ],
                "recovery": {
                    "avg_mood_positive_pct": 0.65,
                    "fatigue_after_high_volume_weeks": false,
                    "typical_easy_day_frequency": 2.0
                },
                "preferences": {
                    "most_common_workout_types": [],
                    "avg_long_run_distance": 0,
                    "preferred_run_days": [],
                    "trains_consecutively": false
                },
                "goal_history": {
                    "completed": 0,
                    "active": 0,
                    "race_distances_targeted": []
                }
            },
            "cached": true
        }
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(AthleteProfileResponse.self, from: data)

        #expect(response.cached == true)
        #expect(response.profile.volume.count == 2)
        #expect(response.profile.volume[0].tier == "last_6_months")
        #expect(response.profile.volume[0].weight == 1.0)
        #expect(response.profile.volume[0].avgWeeklyMiles == 25.0)
        #expect(response.profile.volume[1].weight == 0.6)

        #expect(response.profile.pace.count == 1)
        #expect(response.profile.pace[0].avgPaceSecondsPerMile == 510)

        #expect(response.profile.injuryHistory.count == 1)
        #expect(response.profile.injuryHistory[0].bodyArea == "calf")
        #expect(response.profile.injuryHistory[0].isRecurring == true)
        #expect(response.profile.injuryHistory[0].occurrences == 3)
    }

    @Test("Decodes profile with optional biomechanics")
    func decodesBiomechanics() throws {
        let json = """
        {
            "profile": {
                "built_at": "2026-03-16T12:00:00Z",
                "data_span_months": 3,
                "total_logs": 50,
                "volume": [],
                "volume_summary": {
                    "current_weekly_avg": 20.0,
                    "peak_weekly_ever": 30.0,
                    "longest_run_ever": 13.0,
                    "total_lifetime_miles": 500.0,
                    "consistency_score": 0.75
                },
                "pace": [],
                "performance_trajectory": [],
                "injury_history": [],
                "recovery": {
                    "avg_mood_positive_pct": 0.8,
                    "fatigue_after_high_volume_weeks": false,
                    "typical_easy_day_frequency": 3.0
                },
                "preferences": {
                    "most_common_workout_types": [],
                    "avg_long_run_distance": 0,
                    "preferred_run_days": [],
                    "trains_consecutively": false
                },
                "biomechanics": {
                    "latest_score": 7.5,
                    "trend": "improving",
                    "key_findings": ["Good hip drive", "Slight overstriding"]
                },
                "goal_history": {
                    "completed": 1,
                    "active": 0,
                    "race_distances_targeted": ["5k"]
                }
            },
            "cached": false
        }
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(AthleteProfileResponse.self, from: data)

        #expect(response.profile.biomechanics != nil)
        #expect(response.profile.biomechanics?.latestScore == 7.5)
        #expect(response.profile.biomechanics?.trend == "improving")
        #expect(response.profile.biomechanics?.keyFindings.count == 2)
    }
}

// MARK: - AthleteProfileService Context Tests

@Suite("Athlete Profile Context")
struct AthleteProfileContextTests {

    @Test("profileContextForAI returns nil when no profile")
    func nilWhenNoProfile() {
        let service = AthleteProfileService()
        #expect(service.profileContextForAI == nil)
    }

    @Test("profileContextForAI formats volume data")
    func formatsVolumeData() throws {
        let json = """
        {
            "profile": {
                "built_at": "2026-03-16T12:00:00Z",
                "data_span_months": 6,
                "total_logs": 100,
                "volume": [],
                "volume_summary": {
                    "current_weekly_avg": 30.0,
                    "peak_weekly_ever": 50.0,
                    "longest_run_ever": 22.0,
                    "total_lifetime_miles": 2000.0,
                    "consistency_score": 0.9
                },
                "pace": [
                    {
                        "tier": "last_6_months",
                        "avg_pace_seconds_per_mile": 500,
                        "easy_pace": 540,
                        "fastest_pace": 400
                    }
                ],
                "performance_trajectory": [],
                "injury_history": [
                    {
                        "body_area": "knee",
                        "side": "right",
                        "occurrences": 2,
                        "most_recent": "2026-01-10",
                        "avg_severity": 5.0,
                        "is_recurring": true
                    }
                ],
                "recovery": {
                    "avg_mood_positive_pct": 0.7,
                    "fatigue_after_high_volume_weeks": false,
                    "typical_easy_day_frequency": 2.5
                },
                "preferences": {
                    "most_common_workout_types": ["easy", "tempo"],
                    "avg_long_run_distance": 15.0,
                    "preferred_run_days": ["Tuesday", "Saturday"],
                    "trains_consecutively": false
                },
                "goal_history": {
                    "completed": 0,
                    "active": 0,
                    "race_distances_targeted": []
                }
            },
            "cached": false
        }
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(AthleteProfileResponse.self, from: data)

        let service = AthleteProfileService()
        service.profile = response.profile

        let context = service.profileContextForAI
        #expect(context != nil)
        #expect(context!.contains("30.0 mi/wk"))
        #expect(context!.contains("peak 50.0"))
        #expect(context!.contains("knee (2x)"))
        #expect(context!.contains("easy, tempo"))
    }
}
