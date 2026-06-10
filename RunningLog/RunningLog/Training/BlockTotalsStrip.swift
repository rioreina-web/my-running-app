//
//  BlockTotalsStrip.swift
//  RunningLog
//
//  The BLOCK view's three-column borderless totals strip.
//
//      BLOCK TOTAL         AVG WEEK         LONG RUN
//      342 MI              38 MI            20 MI
//
//  Columns separated by 1pt hairlines. No coral, no card chrome —
//  the typography carries the weight.
//

import SwiftUI

struct BlockTotals {
    let blockTotal: Double   // sum of distance over the active plan to date
    let avgWeek: Double      // blockTotal / completedWeeks
    let longTops: Double     // max single-run distance in the block
}

struct BlockTotalsStrip: View {
    let totals: BlockTotals

    private var columns: [(label: String, value: Double)] {
        [
            ("BLOCK TOTAL", totals.blockTotal),
            ("AVG WEEK",    totals.avgWeek),
            ("LONG RUN",    totals.longTops),
        ]
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(columns.enumerated()), id: \.offset) { idx, col in
                column(label: col.label, value: col.value)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if idx < columns.count - 1 {
                    Rectangle()
                        .fill(Color.drip.divider)
                        .frame(width: 1)
                }
            }
        }
    }

    @ViewBuilder
    private func column(label: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(1.1)  // 0.12em
                .foregroundStyle(Color.drip.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(formatValue(value))
                    .font(.dripStat(26))
                    .foregroundStyle(Color.drip.textPrimary)
                    .monospacedDigit()
                Text("MI")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.drip.textSecondary)
            }
        }
        .padding(.horizontal, 10)
    }

    private func formatValue(_ value: Double) -> String {
        if value <= 0 { return "—" }
        return "\(Int(value.rounded()))"
    }
}
