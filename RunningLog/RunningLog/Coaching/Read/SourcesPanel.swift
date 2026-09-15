//
//  SourcesPanel.swift
//  RunningLog
//
//  The "what this read is based on" footer of a Coach Read. One
//  collapsed row answers two questions at a glance — *what did the
//  coach look at?* and *how sure is it?* — and expands to show the
//  evidence itself:
//
//      READ FROM · 5 WORKOUTS · 2 MEMOS              ▪▪▫ MEDIUM
//      ▸ "6 runs and 3 memos, latest yesterday"      (confidence sub)
//        [workout cards] [doc cards] [memo excerpts]
//
//  Folding confidence into this header (it used to be its own
//  `ConfidenceBar` row) keeps the page to one line of footer chrome
//  and puts the level next to the evidence that earned it.
//
//  Workouts and docs render as expanded EvidenceChip / DocChip cards;
//  voice memos render as `♪` MemoChip rows — the athlete's own words,
//  verbatim, so she can see what the paragraph paraphrased.
//

import SwiftUI

struct SourcesPanel: View {
    let sources: CoachRead.Sources
    let confidence: CoachRead.Confidence
    let workouts: [UUID: TrainingLog]
    let docs: [UUID: CoachingDocument]
    @Binding var selectedWorkoutId: UUID?
    @Binding var selectedDocId: UUID?

    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            Hairline()

            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 12) {
                    // Why this confidence level — plain clause from the
                    // prompt ("6 runs and 3 memos, latest yesterday").
                    if !confidence.sub.isEmpty {
                        Text(confidence.sub)
                            .font(.dripBody(13))
                            .italic()
                            .foregroundStyle(Color.drip.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    ForEach(sources.workouts, id: \.self) { id in
                        if let workout = workouts[id] {
                            EvidenceChip.expanded(
                                workout: workout,
                                selectedWorkoutId: $selectedWorkoutId
                            )
                        }
                    }

                    ForEach(sources.docs, id: \.self) { id in
                        if let doc = docs[id] {
                            DocChip.expanded(
                                doc: doc,
                                selectedDocId: $selectedDocId
                            )
                        }
                    }

                    ForEach(sources.memos, id: \.logId) { memo in
                        MemoChip(memo: memo)
                    }
                }
                .padding(.vertical, 12)
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    Text(headerText)
                        .font(.dripEyebrow(10))
                        .foregroundStyle(Color.drip.textSecondary)
                        .tracking(1.2) // 0.12em × 10pt — section eyebrow
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 8)

                    ConfidencePips(level: confidence.level)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .tint(Color.drip.textSecondary)
            .padding(.horizontal, 4)
            .padding(.vertical, 10)

            Hairline()
        }
    }

    /// "READ FROM · 5 WORKOUTS · 2 MEMOS · 1 DOC". Only the kinds that
    /// are actually present; "READ FROM · NOTHING YET" on an empty Read.
    private var headerText: String {
        var parts: [String] = []
        if !sources.workouts.isEmpty {
            parts.append(count(sources.workouts.count, "WORKOUT"))
        }
        if !sources.memos.isEmpty {
            parts.append(count(sources.memos.count, "MEMO"))
        }
        if !sources.docs.isEmpty {
            parts.append(count(sources.docs.count, "DOC"))
        }
        if parts.isEmpty { return "READ FROM · NOTHING YET" }
        return "READ FROM · " + parts.joined(separator: " · ")
    }

    private func count(_ n: Int, _ noun: String) -> String {
        n == 1 ? "1 \(noun)" : "\(n) \(noun)S"
    }
}

// MARK: - ConfidencePips

/// Three small rectangles + a mono level label. HIGH = 3 filled,
/// MEDIUM = 2, LOW = 1. Coral is the one accent in this cluster.
private struct ConfidencePips: View {
    let level: CoachRead.Confidence.Level

    private var filledCount: Int {
        switch level {
        case .high:   return 3
        case .medium: return 2
        case .low:    return 1
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i < filledCount ? Color.drip.coral : Color.drip.divider)
                    .frame(width: 12, height: 4)
            }
            Text(level.rawValue)
                .font(.dripEyebrow(10))
                .foregroundStyle(Color.drip.coral)
                .tracking(1.0) // 0.10em × 10pt — pill/caption tracking
                .padding(.leading, 4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Confidence \(level.rawValue.lowercased())")
    }
}

// MARK: - MemoChip

/// Voice-memo source row. Mono "♪ <label>" eyebrow + italic verbatim
/// excerpt of what the athlete said. Non-interactive in v1 — tapping
/// through to the original voice log is future work.
private struct MemoChip: View {
    let memo: CoachRead.Sources.Memo

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("♪ \(memo.label.uppercased())")
                    .font(.dripEyebrow(10))
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
            confidence: .init(level: .medium, sub: "4 runs and 1 memo, latest yesterday"),
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
