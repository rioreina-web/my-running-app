//
//  CantSeeBlock.swift
//  RunningLog
//
//  The "what I can't see" block. Surfaces honest uncertainty —
//  missing sleep data, an unsynced workout, a niggle mentioned once,
//  a prediction sitting on thin evidence. The single biggest trust
//  move in the brand voice (§3.4). Rendered only when the Coach Read
//  has a non-nil `cantSee` field — never invent one to seem humble.
//
//  Phase 3.4 of coach-the-read-prompts.md.
//

import SwiftUI

struct CantSeeBlock: View {
    let block: CoachRead.CantSee

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Left bar — ink-tertiary, 2pt wide, full block height.
            Rectangle()
                .fill(Color.drip.textTertiary)
                .frame(width: 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(block.eyebrow.uppercased())
                    .font(.dripStat(10))
                    .foregroundStyle(Color.drip.textTertiary)
                    .tracking(1.2) // 0.12em × 10pt — section-eyebrow tracking

                Text(block.body)
                    // 14pt body matches the `.coach-quote` primitive
                    // size; the gray left bar (vs coral) intentionally
                    // signals "uncertainty" rather than "coach voice."
                    .font(.dripBody(14))
                    .italic()
                    .foregroundStyle(Color.drip.textPrimary)
                    .lineSpacing(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.drip.cardBackgroundElevated)
    }
}

#Preview("CantSeeBlock — common variants") {
    VStack(spacing: 16) {
        CantSeeBlock(block: .init(
            eyebrow: "NO SLEEP DATA",
            body: "Watch isn't syncing sleep this week — I'm guessing on recovery."
        ))
        CantSeeBlock(block: .init(
            eyebrow: "ONE DATA POINT",
            body: "You mentioned the calf once on Tuesday and haven't brought it up since. Worth a flag, not a diagnosis."
        ))
        CantSeeBlock(block: .init(
            eyebrow: "NO PROGRAM IN APP",
            body: "I can see your runs but not your coach's plan, so I'm describing what's happening rather than evaluating it."
        ))
    }
    .padding()
    .background(Color.drip.background)
}
