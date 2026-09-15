//
//  SoftQuestionsBlock.swift
//  RunningLog
//
//  The one or two soft questions a Coach Read leaves the athlete to sit
//  with. Set apart from the paragraph so they read as an invitation to
//  think, not as the paragraph trailing off.
//
//  Design: the "from your coach" treatment from the design system —
//  italic serif with the 2pt coral-at-50% left bar (the one sanctioned
//  coloured left border, see `CoachQuote` in DesignSystem.swift). Not
//  `CoachQuote` itself because these are the coach's own questions, not
//  quoted speech, so no curly quotes. The eyebrow stays ink-2 so the
//  bar is the single coral element in this cluster.
//
//  Voice contract (daily-read.v3 prompt): questions are observations
//  turned toward the athlete — "How did Sunday's 16 feel next to the
//  one three weeks ago?" — never directives. The view renders whatever
//  the validator let through; it does not rewrite copy.
//

import SwiftUI

struct SoftQuestionsBlock: View {
    let questions: [String]

    var body: some View {
        if !questions.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("TO SIT WITH")
                    .font(.dripEyebrow(10))
                    .tracking(1.2) // 0.12em × 10pt — section-eyebrow tracking
                    .foregroundStyle(Color.drip.textSecondary)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(questions.enumerated()), id: \.offset) { _, question in
                        Text(question)
                            .font(.system(size: 15, design: .serif).italic())
                            .foregroundStyle(Color.drip.textPrimary)
                            .lineSpacing(4)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 12)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Color.drip.coral.opacity(0.5))
                        .frame(width: 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview("SoftQuestionsBlock") {
    VStack(alignment: .leading, spacing: 24) {
        SoftQuestionsBlock(questions: [
            "How did Sunday's 16 feel next to the one three weeks ago?",
            "Is the right hamstring getting your attention, or are we both just noticing it?",
        ])
        SoftQuestionsBlock(questions: ["What are you pointing this block at?"])
    }
    .padding(24)
    .background(Color.drip.background)
}
