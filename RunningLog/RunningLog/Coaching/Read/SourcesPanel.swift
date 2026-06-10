//
//  SourcesPanel.swift
//  RunningLog
//
//  The expandable Sources panel at the bottom of a Coach Read.
//  Lists every workout and doc the Read cited (rendered as expanded
//  EvidenceChip / DocChip cards), plus voice memos that informed the
//  Read but never appear inline (`♪` MemoChip — verbatim athlete
//  quote with the mono label eyebrow). Wrapped in a DisclosureGroup
//  so the panel collapses when the athlete doesn't need it.
//
//  Phase 3.4 of coach-the-read-prompts.md.
//

import SwiftUI

struct SourcesPanel: View {
    let sources: CoachRead.Sources
    let workouts: [UUID: TrainingLog]
    let docs: [UUID: CoachingDocument]
    @Binding var selectedWorkoutId: UUID?
    @Binding var selectedDocId: UUID?

    @State private var isExpanded = false

    private var totalCount: Int {
        sources.workouts.count + sources.docs.count + sources.memos.count
    }

    var body: some View {
        // Top + bottom hairline borders match the design mock.
        VStack(spacing: 0) {
            Divider()
                .background(Color.drip.divider)

            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 12) {
                    // Workouts — expanded chip cards.
                    ForEach(sources.workouts, id: \.self) { id in
                        if let workout = workouts[id] {
                            EvidenceChip.expanded(
                                workout: workout,
                                selectedWorkoutId: $selectedWorkoutId
                            )
                        }
                    }

                    // Docs — expanded chip cards.
                    ForEach(sources.docs, id: \.self) { id in
                        if let doc = docs[id] {
                            DocChip.expanded(
                                doc: doc,
                                selectedDocId: $selectedDocId
                            )
                        }
                    }

                    // Voice memos — ♪ chip, sources-only.
                    ForEach(sources.memos, id: \.logId) { memo in
                        MemoChip(memo: memo)
                    }
                }
                .padding(.vertical, 12)
            } label: {
                Text(headerText)
                    .font(.dripStat(10))
                    .foregroundStyle(Color.drip.textSecondary)
                    .tracking(1.2) // 0.12em × 10pt — section eyebrow
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .tint(Color.drip.textSecondary)
            .padding(.horizontal, 4)
            .padding(.vertical, 10)

            Divider()
                .background(Color.drip.divider)
        }
    }

    /// Mono header line: "SOURCES · N · WORKOUTS, KNOWLEDGE, VOICE MEMOS".
    /// The category list trims to whatever's actually present so we
    /// don't claim categories we have zero of.
    private var headerText: String {
        var parts: [String] = []
        if !sources.workouts.isEmpty { parts.append("WORKOUTS") }
        if !sources.docs.isEmpty { parts.append("KNOWLEDGE") }
        if !sources.memos.isEmpty { parts.append("VOICE MEMOS") }
        let kinds = parts.isEmpty ? "" : " · " + parts.joined(separator: ", ")
        return "SOURCES · \(totalCount)\(kinds)"
    }
}

// MARK: - MemoChip

/// Voice-memo source row. Mono "♪ <label>" eyebrow + italic verbatim
/// excerpt of what the athlete said. Non-interactive in v1 — tapping
/// the original voice log is future work.
private struct MemoChip: View {
    let memo: CoachRead.Sources.Memo

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("♪ \(memo.label.uppercased())")
                    .font(.dripStat(10))
                    .foregroundStyle(Color.drip.textSecondary)
                    .tracking(1.2) // 0.12em × 10pt

                Text("\u{201C}\(memo.excerpt)\u{201D}") // curly quotes
                    .font(.dripBody(14))
                    .italic()
                    .foregroundStyle(Color.drip.textPrimary)
                    .lineSpacing(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.drip.cardBackgroundElevated)
        .cornerRadius(12)
    }
}

#Preview("SourcesPanel — full panel") {
    SourcesPanelPreviewHost()
        .padding()
        .background(Color.drip.background)
}

private struct SourcesPanelPreviewHost: View {
    @State private var selectedWorkout: UUID?
    @State private var selectedDoc: UUID?

    private let w1 = UUID(uuidString: "aaaaaaaa-1111-1111-1111-111111111111")!
    private let d1 = UUID(uuidString: "bbbbbbbb-1111-1111-1111-111111111111")!
    private let m1 = UUID(uuidString: "cccccccc-1111-1111-1111-111111111111")!

    var body: some View {
        SourcesPanel(
            sources: .init(
                workouts: [w1],
                docs: [d1],
                memos: [
                    .init(
                        label: "TUE AM check-in",
                        excerpt:
                            "Legs feeling smooth — first time in three weeks the calf hasn't said anything.",
                        logId: m1
                    ),
                ]
            ),
            workouts: [w1: Self.mockWorkout(id: w1)],
            docs: [d1: Self.mockDoc(id: d1)],
            selectedWorkoutId: $selectedWorkout,
            selectedDocId: $selectedDoc
        )
    }

    private static func mockWorkout(id: UUID) -> TrainingLog {
        let iso = ISO8601DateFormatter().string(from: Date())
        let json = """
        {
          "id": "\(id.uuidString)",
          "created_at": "\(iso)",
          "workout_date": "\(iso.prefix(10))",
          "workout_type": "tempo",
          "workout_distance_miles": 6.0,
          "workout_duration_minutes": 44.5,
          "workout_pace_per_mile": "7:29",
          "workout_notes": "6 × 1mi tempo, 90s recovery"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(TrainingLog.self, from: json.data(using: .utf8)!))!
    }

    private static func mockDoc(id: UUID) -> CoachingDocument {
        CoachingDocument(
            id: id,
            title: "Aerobic support through a build block",
            category: "training principles",
            content:
                "Aerobic support workouts do most of the development work in the middle of a block."
        )
    }
}
