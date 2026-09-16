//
//  MileageSkylineGrid.swift
//  RunningLog · Training › Analytics
//
//  The "MILEAGE · BY DAY" grid cells. Each day is a SKYLINE bar whose
//  HEIGHT encodes miles and FILL encodes the day's hardest zone, with the
//  mileage labeled above. The week's shape — long-run cadence, deloads,
//  rest days — reads at a glance. Same data, same palette as the rest of
//  the tab. Wired into `TrainingTabView.mileageByDay`.
//
//  Reuses the existing GridWeek / DayCell / ZoneSplit / IntensityBucket
//  types from TrainingAnalyticsViewModel.
//

import SwiftUI

/// One week (Mon→Sun) of the mileage skyline. A shared hairline baseline
/// under the row is the "ground" every bar rises from.
struct MileageSkylineRow: View {
    let week: GridWeek
    let maxMiles: Double
    @Binding var expandedDay: Date?
    let onTap: (Date) -> Void

    private let rowHeight: CGFloat = 68

    var body: some View {
        HStack(spacing: 3) {
            Text(week.label)
                .font(.dripEyebrow(9)).tracking(0.6)
                .foregroundStyle(Color.drip.textTertiary)
                .frame(width: 54, alignment: .leading)
            ForEach(week.cells) { cell in
                MileageSkylineCell(
                    cell: cell,
                    maxMiles: maxMiles,
                    selected: expandedDay.map { Calendar.current.isDate($0, inSameDayAs: cell.date) } ?? false,
                    onTap: { onTap(cell.date) }
                )
            }
        }
        .frame(height: rowHeight)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.drip.divider).frame(height: 1)
        }
    }
}

/// A single day. Logged days render as a labeled bar (height ∝ miles, fill
/// = hardest zone). Rest = hollow dot on the baseline; future = faint
/// hairline. The selected day gets a coral tick under its bar.
struct MileageSkylineCell: View {
    let cell: DayCell
    let maxMiles: Double
    let selected: Bool
    let onTap: () -> Void

    // Bar geometry — tuned so a 14-mi long run nearly fills the row and a
    // recovery 3-mi still reads as a clear bar, not a sliver.
    private let barWidth: CGFloat = 12
    private let barFloor: CGFloat = 4
    private let barRange: CGFloat = 46

    var body: some View {
        Button(action: { if !cell.isRest && !cell.isFuture { onTap() } }) {
            VStack(spacing: 5) {
                if !cell.isRest && !cell.isFuture {
                    Text(String(format: "%.1f", cell.miles))
                        .font(.dripStat(9))
                        .monospacedDigit()
                        .foregroundStyle(selected ? Color.drip.textPrimary : Color.drip.textSecondary)
                }
                mark
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .overlay(alignment: .bottom) {
                if selected {
                    Rectangle()
                        .fill(Color.drip.coral)
                        .frame(width: barWidth, height: 2.5)
                        .offset(y: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(cell.isRest || cell.isFuture)
    }

    @ViewBuilder
    private var mark: some View {
        if cell.isFuture {
            Rectangle()
                .fill(Color.drip.divider)
                .frame(width: 7, height: 1)
                .padding(.bottom, 5)
        } else if cell.isRest {
            Circle()
                .strokeBorder(Color.drip.textTertiary.opacity(0.5), lineWidth: 1)
                .frame(width: 7, height: 7)
                .padding(.bottom, 5)
        } else {
            let h = barFloor + CGFloat(cell.miles / max(1, maxMiles)) * barRange
            RoundedRectangle(cornerRadius: 2)
                .fill(cell.split.hardestBucket.color)
                .frame(width: barWidth, height: h)
        }
    }
}
