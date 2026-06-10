//
//  ReadProse.swift
//  RunningLog
//
//  The paragraph renderer for the Coach Read. Takes the segmented
//  paragraph that comes back from the edge function — an ordered mix
//  of plain text and `{workout_id}` / `{doc_id}` citation objects —
//  and lays them out as flowing prose with inline chips on the text
//  baseline.
//
//  Why this is non-trivial:
//    SwiftUI's `Text` concatenation operator (`+`) only works between
//    two `Text` values. The moment we want to mix `Text` with a
//    custom View (the chip components have tap state and their own
//    visual chrome), concatenation breaks. The supported workaround
//    is a custom `Layout` that flows mixed View types left-to-right
//    and wraps at the proposed width — `FlowLayout` below.
//
//  Phase 3.3 of coach-the-read-prompts.md.
//

import SwiftUI

struct ReadProse: View {
    let segments: [CoachRead.Segment]
    let workouts: [UUID: TrainingLog]
    let docs: [UUID: CoachingDocument]
    @Binding var selectedWorkoutId: UUID?
    @Binding var selectedDocId: UUID?

    var body: some View {
        // The FlowLayout treats every leaf View as one flowable unit.
        // Text segments are pre-split into per-word tokens so the
        // paragraph can wrap mid-sentence; chips stay atomic so they
        // never break across lines.
        ProseFlowLayout(spacing: 0, lineSpacing: 4) {
            ForEach(Array(tokens().enumerated()), id: \.offset) { _, token in
                tokenView(token)
            }
        }
        .font(.dripBody(16))
        .foregroundStyle(Color.drip.textPrimary)
    }

    // MARK: - Token enumeration

    /// A single layout token — either a word of prose (carrying its
    /// own trailing whitespace) or one of the two chip variants.
    private enum Token {
        case word(String)
        case workout(UUID)
        case doc(UUID)
    }

    private func tokens() -> [Token] {
        var out: [Token] = []
        for seg in segments {
            switch seg {
            case .text(let raw):
                out.append(contentsOf: Self.splitIntoWords(raw).map(Token.word))
            case .workout(let id):
                out.append(.workout(id))
            case .doc(let id):
                out.append(.doc(id))
            }
        }
        return out
    }

    /// Split a text segment into space-bounded tokens, each carrying
    /// its own trailing whitespace. "Three good weeks." →
    /// ["Three ", "good ", "weeks."]. The trailing space on each
    /// non-final token is what produces inter-word gaps when the
    /// FlowLayout's own spacing is set to 0.
    private static func splitIntoWords(_ s: String) -> [String] {
        if s.isEmpty { return [] }
        var tokens: [String] = []
        var current = ""
        for ch in s {
            current.append(ch)
            if ch.isWhitespace {
                tokens.append(current)
                current = ""
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    // MARK: - Token rendering

    @ViewBuilder
    private func tokenView(_ token: Token) -> some View {
        switch token {
        case .word(let s):
            Text(s)

        case .workout(let id):
            if let workout = workouts[id] {
                EvidenceChip.inline(
                    workout: workout,
                    selectedWorkoutId: $selectedWorkoutId
                )
            } else {
                // Citation pointed at a workout we don't have hydrated.
                // The edge function's validator strips ids that don't
                // exist on the server, but this is a belt-and-braces
                // fallback for hydration races (rare).
                Text("◆ ?")
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textTertiary)
            }

        case .doc(let id):
            if let doc = docs[id] {
                DocChip.inline(
                    doc: doc,
                    selectedDocId: $selectedDocId
                )
            } else {
                Text("§ ?")
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textTertiary)
            }
        }
    }
}

// MARK: - FlowLayout

/// A left-to-right, top-to-bottom wrapping `Layout`. Each subview is
/// measured at its intrinsic size and packed into rows; when a row
/// can't fit the next subview, it wraps. Within a row, subviews are
/// aligned to a common bottom edge (approximating text-baseline
/// alignment for the chip-on-prose case).
///
/// Generic enough to be reusable; kept here as a private nested type
/// because nothing else in the app needs it yet.
private struct ProseFlowLayout: Layout {
    /// Horizontal spacing between adjacent subviews on the same row.
    /// Set to 0 for `ReadProse` since each word carries its own
    /// trailing whitespace.
    var spacing: CGFloat = 0
    /// Vertical spacing between rows.
    var lineSpacing: CGFloat = 4

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache _: inout Cache
    ) -> CGSize {
        let width = proposal.width ?? .infinity
        let plan = computePlan(subviews: subviews, width: width)
        return CGSize(
            width: proposal.width ?? plan.bounds.width,
            height: plan.bounds.height
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout Cache
    ) {
        let plan = computePlan(subviews: subviews, width: bounds.width)
        for (idx, sub) in subviews.enumerated() {
            let pos = plan.positions[idx]
            sub.place(
                at: CGPoint(x: bounds.minX + pos.x, y: bounds.minY + pos.y),
                anchor: .topLeading,
                proposal: ProposedViewSize(plan.sizes[idx])
            )
        }
    }

    // MARK: - Layout planning

    /// Cache is unused but the Layout protocol requires the type to
    /// exist; keep it `Void`-shaped so we don't pay the cost of
    /// caching during a redraw.
    typealias Cache = Void
    func makeCache(subviews _: Subviews) -> Cache {}

    private struct Plan {
        var positions: [CGPoint]
        var sizes: [CGSize]
        var bounds: CGSize
    }

    /// Walk every subview, place them on rows, and return positions +
    /// sizes + total bounds. Two-pass per row: first measure heights
    /// to find the row's max height, then place each subview within
    /// that row aligned to the row's bottom edge.
    private func computePlan(subviews: Subviews, width: CGFloat) -> Plan {
        var positions: [CGPoint] = Array(
            repeating: .zero,
            count: subviews.count
        )
        var sizes: [CGSize] = Array(
            repeating: .zero,
            count: subviews.count
        )

        // Measure every subview once. `.unspecified` lets each one
        // report its intrinsic size — chips return their compact
        // pill size, words return their natural typographic width.
        for (idx, sub) in subviews.enumerated() {
            sizes[idx] = sub.sizeThatFits(.unspecified)
        }

        var rowStart = 0
        var x: CGFloat = 0

        // Group subviews into rows by greedy wrapping.
        var rows: [(start: Int, end: Int, height: CGFloat)] = []
        var currentRowHeight: CGFloat = 0

        for idx in 0..<subviews.count {
            let size = sizes[idx]
            let needsWrap = x + size.width > width && idx > rowStart
            if needsWrap {
                rows.append((rowStart, idx, currentRowHeight))
                rowStart = idx
                x = 0
                currentRowHeight = 0
            }
            // Track the running x position for the current row only;
            // the actual placement happens in the second pass below.
            positions[idx] = CGPoint(x: x, y: 0) // y resolved per-row later
            x += size.width + spacing
            currentRowHeight = max(currentRowHeight, size.height)
        }
        // Tail row.
        if rowStart < subviews.count {
            rows.append((rowStart, subviews.count, currentRowHeight))
        }

        // Resolve y-positions per row, aligning each subview's bottom
        // edge to the row's bottom edge. This approximates baseline
        // alignment well enough for chip-on-prose mixing — true text
        // baseline alignment isn't exposed by the Layout protocol.
        var totalHeight: CGFloat = 0
        for row in rows {
            let rowBottom = totalHeight + row.height
            for idx in row.start..<row.end {
                let h = sizes[idx].height
                positions[idx].y = rowBottom - h
            }
            totalHeight = rowBottom + lineSpacing
        }
        // Trim the trailing lineSpacing off the final row's height.
        if !rows.isEmpty {
            totalHeight -= lineSpacing
        }

        return Plan(
            positions: positions,
            sizes: sizes,
            bounds: CGSize(width: width, height: totalHeight)
        )
    }
}

// MARK: - Preview

#Preview("ReadProse — design mock paragraph") {
    ReadProsePreviewHost()
        .padding()
        .background(Color.drip.background)
}

private struct ReadProsePreviewHost: View {
    @State private var selectedWorkout: UUID?
    @State private var selectedDoc: UUID?

    private let workoutId = UUID(uuidString: "aaaaaaaa-1111-1111-1111-111111111111")!
    private let docId = UUID(uuidString: "bbbbbbbb-1111-1111-1111-111111111111")!

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("THE READ")
                .font(.dripStat(10))
                .foregroundStyle(Color.drip.textSecondary)
                .tracking(0.8)

            Text("The base is taking.")
                .font(.dripDisplay(28))
                .foregroundStyle(Color.drip.textPrimary)

            ReadProse(
                segments: Self.mockSegments(
                    workoutId: workoutId,
                    docId: docId
                ),
                workouts: [workoutId: Self.mockWorkout(id: workoutId)],
                docs: [docId: Self.mockDoc(id: docId)],
                selectedWorkoutId: $selectedWorkout,
                selectedDocId: $selectedDoc
            )

            Text(
                "tapped — workout: \(selectedWorkout?.uuidString.prefix(8) ?? "—") · "
                + "doc: \(selectedDoc?.uuidString.prefix(8) ?? "—")"
            )
            .font(.dripStat(11))
            .foregroundStyle(Color.drip.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Mocks

    private static func mockSegments(
        workoutId: UUID,
        docId: UUID
    ) -> [CoachRead.Segment] {
        [
            .text("Three good weeks in a row. "),
            .workout(workoutId: workoutId),
            .text(
                " came in 6s under target — the third tempo this block to "
                + "land where it should. The "
            ),
            .doc(docId: docId),
            .text(" says this is the phase to hold steady, not push."),
        ]
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
          "workout_pace_per_mile": "7:29"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(TrainingLog.self, from: json.data(using: .utf8)!))!
    }

    private static func mockDoc(id: UUID) -> CoachingDocument {
        CoachingDocument(
            id: id,
            title: "rules on aerobic support",
            category: "training principles",
            content:
                "Aerobic support workouts do most of the development work "
                + "in the middle of a block. Hold steady."
        )
    }
}
