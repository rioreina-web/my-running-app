//
//  LogRowPreviewScene.swift
//  RunningLog
//
//  DEBUG-only visual-iteration harness for the redesigned `JournalLogRow`
//  (2026-09-01 stat-strip pass), seeded with a representative week so the
//  row can be screenshotted without auth/HealthKit/network. Reached via
//  the `-logRowPreview` launch argument (see RunningLogApp). Not compiled
//  in release. Delete with the rest of the dev scaffolding once the
//  redesign is confirmed and committed.
//

#if DEBUG
import SwiftUI

struct LogRowPreviewScene: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Atoms showcase — the pieces going into the detail sheet's
                // statusRow, which needs real auth to screenshot for real
                // (body_mentions + day_overrides both require a signed-in
                // user). Rendered here instead so the actual new visual —
                // JournalNiggleChip has never been on screen before, unlike
                // the row below which reused an existing chip style.
                Text("DETAIL-SHEET ATOMS")
                    .font(.dripEyebrow(11))
                    .tracking(1.0)
                    .foregroundStyle(Color.drip.textTertiary)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                Divider().overlay(Color.drip.divider)
                HStack(spacing: 6) {
                    JournalNiggleChip(label: "left calf")
                    JournalNiggleChip(label: "right knee")
                    Text("+1").font(.dripEyebrow(9)).foregroundStyle(Color.drip.textTertiary)
                }
                .padding(20)
                HStack(spacing: 18) {
                    ForEach(["auto", "planned", "athlete"], id: \.self) { label in
                        let p: KeySessionMark.Provenance = label == "auto" ? .auto : (label == "planned" ? .planned : .athlete)
                        VStack(spacing: 6) {
                            KeySessionStar(provenance: p, isKey: true).frame(width: 16, height: 16)
                            Text(label.uppercased())
                                .font(.dripEyebrow(8))
                                .foregroundStyle(Color.drip.textTertiary)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)

                Text("THIS WEEK · 31.7 MI")
                    .font(.dripEyebrow(11))
                    .tracking(1.0)
                    .foregroundStyle(Color.drip.textTertiary)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 4)

                ForEach(Array(LogRowPreviewFixture.entries.enumerated()), id: \.offset) { _, item in
                    Divider().overlay(Color.drip.divider)
                    JournalLogRow(entry: item.entry, niggles: item.niggles)
                        .padding(.horizontal, 20)
                }
            }
        }
        .background(Color.drip.background.ignoresSafeArea())
    }
}

enum LogRowPreviewFixture {
    private static func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d))!
    }

    static let entries: [(entry: TrainingLog, niggles: [JournalNiggle])] = [
        (
            TrainingLog(
                id: UUID(), createdAt: date(2026, 4, 13),
                audioUrl: "https://example.com/a.m4a", notes: nil,
                cleanedNotes: "Legs felt fresh right from the first mile, kept it relaxed the whole way.",
                mood: "energized", workoutDate: date(2026, 4, 13),
                workoutDistanceMiles: 6.2, workoutDurationMinutes: 54.15,
                processingStatus: "completed", processingError: nil, processingAttempts: 1,
                transcriptUrl: nil, coachInsight: nil, workoutNotes: nil,
                workoutPacePerMile: "8:45", workoutType: "easy", source: "voice_memo",
                vitalWorkoutId: nil, paceSegments: nil, parsedStructure: nil,
                title: nil, feltRpe: 3
            ),
            []
        ),
        (
            TrainingLog(
                id: UUID(), createdAt: date(2026, 4, 15),
                audioUrl: "https://example.com/b.m4a", notes: nil,
                cleanedNotes: "Left calf got tight around mile four, backed off the last two reps a little.",
                mood: "tired", workoutDate: date(2026, 4, 15),
                workoutDistanceMiles: 8.0, workoutDurationMinutes: 57.6,
                processingStatus: "completed", processingError: nil, processingAttempts: 1,
                transcriptUrl: nil, coachInsight: nil, workoutNotes: nil,
                workoutPacePerMile: "7:12", workoutType: "threshold", source: "voice_memo",
                vitalWorkoutId: nil, paceSegments: nil, parsedStructure: nil,
                title: nil, feltRpe: 7
            ),
            [JournalNiggle(id: UUID(), trainingLogId: nil, bodyArea: "calf", side: "left", verbatimQuote: "left calf got tight")]
        ),
        (
            TrainingLog(
                id: UUID(), createdAt: date(2026, 4, 18),
                audioUrl: nil, notes: "Windy the whole way out, easier coming back. Nutrition felt dialed in for once.",
                cleanedNotes: nil,
                mood: "positive", workoutDate: date(2026, 4, 18),
                workoutDistanceMiles: 14.0, workoutDurationMinutes: 125.53,
                processingStatus: "completed", processingError: nil, processingAttempts: 1,
                transcriptUrl: nil, coachInsight: nil, workoutNotes: nil,
                workoutPacePerMile: "8:58", workoutType: "long_run", source: "text",
                vitalWorkoutId: nil, paceSegments: nil, parsedStructure: nil,
                title: nil, feltRpe: 6
            ),
            []
        ),
        (
            TrainingLog(
                id: UUID(), createdAt: date(2026, 4, 19),
                audioUrl: nil, notes: nil,
                cleanedNotes: "Everything felt heavy today, calf and knee both barking a bit.",
                mood: "struggling", workoutDate: date(2026, 4, 19),
                workoutDistanceMiles: 3.5, workoutDurationMinutes: 33.83,
                processingStatus: "completed", processingError: nil, processingAttempts: 1,
                transcriptUrl: nil, coachInsight: nil, workoutNotes: nil,
                workoutPacePerMile: "9:40", workoutType: "recovery", source: "check_in",
                vitalWorkoutId: nil, paceSegments: nil, parsedStructure: nil,
                title: nil, feltRpe: 4
            ),
            [
                JournalNiggle(id: UUID(), trainingLogId: nil, bodyArea: "calf", side: "left", verbatimQuote: "calf barking"),
                JournalNiggle(id: UUID(), trainingLogId: nil, bodyArea: "knee", side: "right", verbatimQuote: "knee barking"),
            ]
        ),
    ]
}
#endif
