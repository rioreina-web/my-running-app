//
//  ConfidenceBar.swift
//  RunningLog
//
//  Three small filled rectangles + a mono level label, plus a short
//  sub-line explaining why. HIGH = 3 filled, MEDIUM = 2, LOW = 1.
//  Non-interactive — purely informational.
//
//  Phase 3.4 of coach-the-read-prompts.md.
//

import SwiftUI

struct ConfidenceBar: View {
    let confidence: CoachRead.Confidence

    private var filledCount: Int {
        switch confidence.level {
        case .high:   return 3
        case .medium: return 2
        case .low:    return 1
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Left: mono CONFIDENCE eyebrow + sub-line.
            VStack(alignment: .leading, spacing: 2) {
                Text("CONFIDENCE")
                    .font(.dripStat(10))
                    .foregroundStyle(Color.drip.textSecondary)
                    .tracking(1.2) // 0.12em × 10pt

                if !confidence.sub.isEmpty {
                    Text(confidence.sub)
                        .font(.dripCaption(10))
                        .foregroundStyle(Color.drip.textTertiary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }

            Spacer(minLength: 8)

            // Right: three rectangles + level label.
            HStack(alignment: .center, spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(
                            i < filledCount
                                ? Color.drip.coral
                                : Color.drip.divider
                        )
                        .frame(width: 14, height: 4)
                }
                Text(confidence.level.rawValue)
                    .font(.dripStat(10))
                    .foregroundStyle(Color.drip.coral)
                    .tracking(1.0) // 0.10em × 10pt — pill/caption tracking
                    .padding(.leading, 4)
            }
        }
        .padding(.vertical, 8)
    }
}

#Preview("ConfidenceBar — all three levels") {
    VStack(alignment: .leading, spacing: 16) {
        ConfidenceBar(confidence: .init(
            level: .high,
            sub: "5 workouts and a recent half"
        ))
        ConfidenceBar(confidence: .init(
            level: .medium,
            sub: "2 quality sessions, last week was light"
        ))
        ConfidenceBar(confidence: .init(
            level: .low,
            sub: "first read — light evidence"
        ))
    }
    .padding()
    .background(Color.drip.background)
}
