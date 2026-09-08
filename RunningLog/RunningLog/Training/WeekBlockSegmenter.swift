//
//  WeekBlockSegmenter.swift
//  RunningLog
//
//  Three-tab segmenter that sits below the TrainingHeader and switches
//  the Train tab between CURRENT (today-anchored editorial view),
//  CALENDAR (month grid of what happened and what's planned) and
//  HISTORY (longer-arc analytics: totals, pace × volume, recent log).
//
//  CALENDAR is where the old Plan tab went. The target IA makes the
//  plan a subset of Train rather than a peer of it, so a plan is one
//  way to read the month, not the reason the month exists — the grid
//  still draws with `activePlan == nil`.
//
//  Coral discipline: the active tab is the only coral element in this
//  cluster — coral foreground + 1.5pt coral underline that overlaps the
//  shared 1pt baseline divider. Inactive tabs read textSecondary on a
//  transparent underline.
//

import SwiftUI

/// Three-state segment for the Train tab. Persisted to @AppStorage at
/// the parent so deep-linking back to Train returns the user to
/// wherever they left off.
///
/// Raw values are storage keys, not display copy — `label` owns what
/// the user sees. Values persisted by the earlier two-state version
/// ("THIS WEEK" / "THE BLOCK") no longer decode and fall back to
/// `.current`, which is the right landing segment anyway.
enum TrainingTabSegment: String, CaseIterable, Identifiable {
    case current  = "current"
    case calendar = "calendar"
    case history  = "history"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .current:  "CURRENT"
        case .calendar: "CALENDAR"
        case .history:  "HISTORY"
        }
    }
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
            Text(seg.label)
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
        .accessibilityLabel("\(seg.label) segment")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}
