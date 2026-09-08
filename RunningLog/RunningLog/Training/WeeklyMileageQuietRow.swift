//
//  WeeklyMileageQuietRow.swift
//  RunningLog
//
//  The WEEK view's small mileage block — eyebrow + delta + one big
//  number. No chart. The 8-week sparkline + 4-week comparison bar live
//  exclusively in the BLOCK view; here we're just stating *this week's*
//  total so the runner can clock progress without scrolling.
//
//      WEEKLY MILEAGE                                      +8% VS PRIOR
//      47.2
//
//  The "MILES" unit label is gone — the eyebrow one line above already
//  says MILEAGE, and the number is the point.
//
//  Coral discipline: none — except the delta turns coral when the
//  comparison drops below prior (a small signal that volume slipped).
//  Positive delta is `energized`. Zero/no-comparison is textSecondary.
//

import SwiftUI

struct WeeklyMileageQuietRow: View {
    let thisWeekMiles: Double
    let lastWeekMiles: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("WEEKLY MILEAGE")
                    .font(.dripEyebrow(11))
                    .tracking(1.3)
                    .foregroundStyle(Color.drip.textSecondary)
                Spacer(minLength: 12)
                Text(deltaText)
                    .font(.dripEyebrow(11))
                    .tracking(1.3)
                    .foregroundStyle(deltaColor)
            }

            Text(numberText)
                .font(.dripStat(40))
                .foregroundStyle(Color.drip.textPrimary)
                .monospacedDigit()
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Zero renders as "0.0", not an em-dash. Nothing logged yet is a
    /// real, honest number here — and em-dash placeholders are against
    /// the design system's empty-state rule.
    private var numberText: String {
        String(format: "%.1f", max(0, thisWeekMiles))
    }

    private var deltaText: String {
        guard lastWeekMiles > 0 else { return "NEW WEEK" }
        let deltaPct = (thisWeekMiles - lastWeekMiles) / lastWeekMiles * 100
        let sign = deltaPct >= 0 ? "+" : ""
        return "\(sign)\(Int(deltaPct.rounded()))% VS PRIOR"
    }

    private var deltaColor: Color {
        guard lastWeekMiles > 0 else { return Color.drip.textSecondary }
        let delta = thisWeekMiles - lastWeekMiles
        if delta > 0 { return Color.drip.energized }
        if delta < 0 { return Color.drip.coral }
        return Color.drip.textSecondary
    }
}
