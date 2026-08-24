//
//  TrainingHeader.swift
//  RunningLog
//
//  Shared header for the Training tab — sits above the WEEK/BLOCK
//  segmenter and reads the same in both views:
//
//      WEEK 09 OF 16                           MON  ·  APR 27
//      Marathon block.
//      Sub-3:10 · May 18 · 47 days out.
//
//  Coral discipline: NONE. Per the redesign handoff, the header is a
//  quiet anchor; coral lives in the segmenter, today hero, and coach
//  note clusters below. Goal line is italic PT Serif.
//
//  The header carries no "Race plan ↗" link. It used to, and it pushed
//  the exact same destination as the "VIEW PLAN ↗" link ~100pt below in
//  the week section — two labels, one screen, one destination. The
//  contextual one won.
//

import SwiftUI

struct TrainingHeader: View {
    let weekText: String        // e.g. "WEEK 09 OF 16" — empty when no plan
    let dateText: String        // e.g. "MON  ·  APR 27"
    let headline: String        // e.g. "Marathon block."
    let goalLine: String?       // e.g. "Sub-3:10 · May 18 · 47 days out."

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                if !weekText.isEmpty {
                    Text(weekText)
                        .font(.dripEyebrow(11))
                        .tracking(1.3)  // 0.12em
                        .foregroundStyle(Color.drip.textSecondary)
                }
                Spacer(minLength: 12)
                Text(dateText)
                    .font(.dripEyebrow(11))
                    .tracking(1.3)
                    .foregroundStyle(Color.drip.textSecondary)
            }

            Text(headline)
                .font(.dripDisplay(32))
                .foregroundStyle(Color.drip.textPrimary)
                .padding(.top, 4)

            if let goalLine, !goalLine.isEmpty {
                Text(goalLine)
                    .font(.system(size: 13, design: .serif).italic())
                    .foregroundStyle(Color.drip.textSecondary)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
