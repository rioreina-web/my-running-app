//
//  ReadSectionsView.swift
//  RunningLog
//
//  v5 sectioned narrative renderer for The Read — the editorial
//  "coach snapshot" layout (design: outputs/the-read-storytelling-mock.html
//  + outputs/the-read-narrative-screen-spec-for-xcode-agent-2026-06-15.md).
//
//  Renders an ordered list of labeled sections (The week → The hard days →
//  The long run → How you felt → One thing) as flowing prose, with two
//  QUIET inline tap-throughs: a workout ref (→ workout detail) and a niggle
//  ref (→ that body part's timeline). The first section is the editorial
//  lede, set in the display serif (no drop cap).
//
//  Tap treatment: hairline coral underline, ink-colored text — discoverable,
//  not a chip. Mirrors the FlowLayout technique from ReadProse so a ref can
//  sit inline in wrapping prose.
//

import SwiftUI

struct ReadSectionsView: View {
    let eyebrow: String?
    let sections: [CoachRead.Section]
    let question: String?

    /// Tap routing — the host (CoachReadView) presents the matching sheet.
    @Binding var selectedWorkoutId: UUID?
    @Binding var selectedNiggle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if let eyebrow, !eyebrow.isEmpty {
                Text(eyebrow.uppercased())
                    .font(.dripStat(11)).tracking(1.3)
                    .foregroundStyle(Color.drip.coral)
            }

            ForEach(Array(sections.enumerated()), id: \.offset) { idx, section in
                sectionBlock(section, isLede: idx == 0)
            }

            if let question, !question.isEmpty {
                Text(question)
                    .font(.dripBody(16)).italic()
                    .foregroundStyle(Color.drip.textPrimary)
                    .padding(.leading, 14)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(Color.drip.coral)
                            .frame(width: 2)
                    }
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - One section

    @ViewBuilder
    private func sectionBlock(_ section: CoachRead.Section, isLede: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // The lede (first section) carries no label — it's the standfirst.
            if !isLede {
                Text(section.label.uppercased())
                    .font(.dripStat(11)).tracking(1.2)
                    .foregroundStyle(Color.drip.textSecondary)
            }

            SectionFlowLayout(spacing: 0, lineSpacing: isLede ? 5 : 4) {
                ForEach(Array(tokens(for: section).enumerated()), id: \.offset) { _, token in
                    tokenView(token, isLede: isLede)
                }
            }
        }
    }

    // MARK: - Tokens

    private enum Token {
        case word(String)
        case workout(text: String, id: UUID)
        case niggle(text: String, part: String)
    }

    private func tokens(for section: CoachRead.Section) -> [Token] {
        var out: [Token] = []
        for seg in section.body {
            switch seg {
            case .text(let raw):
                out.append(contentsOf: Self.splitIntoWords(raw).map(Token.word))
            case .workout(let text, let id):
                out.append(.workout(text: text, id: id))
            case .niggle(let text, let part):
                out.append(.niggle(text: text, part: part))
            }
        }
        return out
    }

    /// Split prose into space-bounded tokens, each carrying its own
    /// trailing whitespace (so FlowLayout spacing can be 0).
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

    @ViewBuilder
    private func tokenView(_ token: Token, isLede: Bool) -> some View {
        switch token {
        case .word(let s):
            Text(s)
                .font(isLede ? .dripDisplay(21) : .dripBody(16))
                .foregroundStyle(Color.drip.textPrimary)

        case .workout(let text, let id):
            refText(text, isLede: isLede) { selectedWorkoutId = id }

        case .niggle(let text, let part):
            refText(text, isLede: isLede) { selectedNiggle = part }
        }
    }

    /// The quiet tap treatment: ink text + hairline coral underline.
    private func refText(_ text: String, isLede: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(isLede ? .dripDisplay(21) : .dripBody(16))
                .foregroundStyle(Color.drip.textPrimary)
                .underline(true, color: Color.drip.coral.opacity(0.32))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - FlowLayout (mirrors ReadProse.ProseFlowLayout, which is private there)

/// Left-to-right wrapping layout; each subview is one flowable unit.
/// Words flow and wrap; refs stay atomic so they never break across lines.
private struct SectionFlowLayout: Layout {
    var spacing: CGFloat = 0
    var lineSpacing: CGFloat = 4

    typealias Cache = Void
    func makeCache(subviews _: Subviews) -> Cache {}

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout Cache) -> CGSize {
        let width = proposal.width ?? .infinity
        let plan = computePlan(subviews: subviews, width: width)
        return CGSize(width: proposal.width ?? plan.bounds.width, height: plan.bounds.height)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout Cache) {
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

    private struct Plan {
        var positions: [CGPoint]
        var sizes: [CGSize]
        var bounds: CGSize
    }

    private func computePlan(subviews: Subviews, width: CGFloat) -> Plan {
        var positions = Array(repeating: CGPoint.zero, count: subviews.count)
        var sizes = Array(repeating: CGSize.zero, count: subviews.count)
        for (idx, sub) in subviews.enumerated() {
            sizes[idx] = sub.sizeThatFits(.unspecified)
        }

        var rowStart = 0
        var x: CGFloat = 0
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
            positions[idx] = CGPoint(x: x, y: 0)
            x += size.width + spacing
            currentRowHeight = max(currentRowHeight, size.height)
        }
        if rowStart < subviews.count {
            rows.append((rowStart, subviews.count, currentRowHeight))
        }

        var totalHeight: CGFloat = 0
        for row in rows {
            let rowBottom = totalHeight + row.height
            for idx in row.start..<row.end {
                positions[idx].y = rowBottom - sizes[idx].height
            }
            totalHeight = rowBottom + lineSpacing
        }
        if !rows.isEmpty { totalHeight -= lineSpacing }

        return Plan(positions: positions, sizes: sizes, bounds: CGSize(width: width, height: totalHeight))
    }
}

// MARK: - Preview (renders the design-mock read with sample data)

#Preview("ReadSections — coach snapshot") {
    ReadSectionsPreviewHost()
        .padding(24)
        .background(Color.drip.background)
}

private struct ReadSectionsPreviewHost: View {
    @State private var workout: UUID?
    @State private var niggle: String?
    private let longRunId = UUID(uuidString: "a1a1a1a1-0000-0000-0000-000000000001")!

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("A strong week — keep that achilles honest.")
                    .font(.dripDisplay(32))
                    .foregroundStyle(Color.drip.textPrimary)

                ReadSectionsView(
                    eyebrow: "Chasing 3:16 · off your 3:28",
                    sections: [
                        .init(label: "The week", body: [
                            .text("52 miles, and you handled every one of them — third straight build week, and this is about stacking them now, not chasing more.")
                        ]),
                        .init(label: "The hard days", body: [
                            .text("Two quality sessions. Tuesday's LT work was sharp; Saturday came apart a little in the last reps — three weeks of work catching up, not your engine.")
                        ]),
                        .init(label: "The long run", body: [
                            .workout(text: "The long run", workoutId: longRunId),
                            .text(" is the one I'd circle: eighteen miles, and you were still running it at the end.")
                        ]),
                        .init(label: "How you felt", body: [
                            .text("Flat in a couple of notes, fair after the heat. And the "),
                            .niggle(text: "achilles", bodyPart: "right achilles"),
                            .text(" is on its third week now — same note each time. If you raced today I'd have you in the low 3:20s.")
                        ])
                    ],
                    question: "How does the achilles feel first thing in the morning?",
                    selectedWorkoutId: $workout,
                    selectedNiggle: $niggle
                )

                Text("tapped — workout: \(workout?.uuidString.prefix(8) ?? "—") · niggle: \(niggle ?? "—")")
                    .font(.dripStat(11))
                    .foregroundStyle(Color.drip.textTertiary)
            }
        }
    }
}
