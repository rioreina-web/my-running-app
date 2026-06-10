//
//  WeekBlockSegmenter.swift
//  RunningLog
//
//  Two-tab segmenter that sits below the TrainingHeader and switches
//  the Train tab between THIS WEEK (today-anchored editorial view) and
//  THE BLOCK (longer-arc analytics: totals, pace × volume, recent log).
//
//  Coral discipline: the active tab is the only coral element in this
//  cluster — coral foreground + 1.5pt coral underline that overlaps the
//  shared 1pt baseline divider. Inactive tabs read textSecondary on a
//  transparent underline.
//

import SwiftUI

/// Two-state segment for the Train tab. Persisted to @AppStorage at the
/// parent so deep-linking back to Train returns the user to wherever
/// they left off.
enum TrainingTabSegment: String, CaseIterable, Identifiable {
    case week  = "THIS WEEK"
    case block = "THE BLOCK"

    var id: String { rawValue }
}

struct WeekBlockSegmenter: View {
    @Binding var segment: TrainingTabSegment

    var body: some View {
        HStack(spacing: 0) {
            ForEach(TrainingTabSegment.allCases) { seg in
                tab(seg)
            }
        }
        .overlay(alignment: .bottom) {
            // Shared 1pt baseline. The active underline below sits on
            // top of this with a small downward offset so the join
            // reads as a single continuous mark.
            Rectangle()
                .fill(Color.drip.divider)
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private func tab(_ seg: TrainingTabSegment) -> some View {
        let isActive = segment == seg
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                segment = seg
            }
        } label: {
            Text(seg.rawValue)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1.4)  // 0.14em
                .foregroundStyle(isActive ? Color.drip.coral : Color.drip.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(isActive ? Color.drip.coral : Color.clear)
                        .frame(height: 1.5)
                        .offset(y: 0.5)
                }
        }
        .buttonStyle(.plain)
    }
}
