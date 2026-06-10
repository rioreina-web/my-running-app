//
//  TrainingHeader.swift
//  RunningLog
//
//  Shared header for the Training tab — sits above the WEEK/BLOCK
//  segmenter and reads the same in both views:
//
//      TRAINING  ·  WEEK 09 OF 16              MON  ·  APR 27
//      Marathon block.
//      Sub-3:10 · May 18 · 47 days out.  Race plan ↗
//
//  Coral discipline: NONE. Per the redesign handoff, the header is a
//  quiet anchor; coral lives in the segmenter, today hero, and coach
//  note clusters below. Goal line is italic PT Serif; "Race plan ↗"
//  is a hairline-bordered text link, not a coral CTA.
//

import SwiftUI

struct TrainingHeader: View {
    let weekText: String        // e.g. "TRAINING  ·  WEEK 09 OF 16"
    let dateText: String        // e.g. "MON  ·  APR 27"
    let headline: String        // e.g. "Marathon block."
    let goalLine: String?       // e.g. "Sub-3:10 · May 18 · 47 days out."
    let onOpenRacePlan: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(weekText)
                    .font(.dripEyebrow(11))
                    .tracking(1.3)  // 0.12em
                    .foregroundStyle(Color.drip.textSecondary)
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
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(goalLine)
                        .font(.system(size: 13, design: .serif).italic())
                        .foregroundStyle(Color.drip.textSecondary)
                    if let onOpenRacePlan {
                        Button(action: onOpenRacePlan) {
                            Text("Race plan ↗")
                                .font(.system(size: 13, design: .serif))
                                .foregroundStyle(Color.drip.textSecondary)
                                .overlay(alignment: .bottom) {
                                    Rectangle()
                                        .fill(Color.drip.divider)
                                        .frame(height: 1)
                                        .offset(y: 1)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
