//
//  PaceZoneBarsChart.swift
//  RunningLog
//
//  Negative Splits — horizontal pace-zone volume chart.
//
//  Replaces the experimental `PaceVolumeSpectrumChart` for the dashboard.
//  The spectrum chart proved hard to read when the runner's reference
//  paces are tightly clustered or when actual training paces don't
//  overlap the reference range. This chart trades elegance for legibility:
//  one row per zone, a colored bar, miles, and percentage.
//
//  The four zones are derived from the four reference paces (Easy / MP /
//  LT / 5K). Each zone owns the pace range from itself to the midpoint
//  of the adjacent anchor. A workout's contribution to a zone is its full
//  distance, assigned by the workout's average pace.
//

import SwiftUI

struct PaceZoneBarsChart: View {

    let workouts: [RunningWorkout]   // workouts in scope (e.g. last 7 days)
    let anchors: [PaceAnchor]        // 4 anchors, slowest first (EASY / MP / LT / 5K)

    var body: some View {
        let rows = computeRows()
        let totalMiles = rows.reduce(0.0) { $0 + $1.miles }
        let maxMiles = max(rows.map { $0.miles }.max() ?? 0, 0.01)

        VStack(spacing: 12) {
            ForEach(rows.indices, id: \.self) { i in
                rowView(rows[i], maxMiles: maxMiles)
            }
            if totalMiles == 0 {
                Text("No miles yet — bars will fill as you run.")
                    .font(.system(size: 13, design: .serif).italic())
                    .foregroundStyle(Color.drip.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func rowView(_ row: ZoneRow, maxMiles: Double) -> some View {
        let fraction: CGFloat = maxMiles > 0 ? CGFloat(row.miles / maxMiles) : 0

        HStack(spacing: 10) {
            // Zone label (mono caps)
            Text(row.label)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(Color.drip.textPrimary)
                .frame(width: 50, alignment: .leading)

            // Pace range (mono, slate-light)
            Text(row.paceRange)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Color.drip.textTertiary)
                .frame(width: 92, alignment: .leading)

            // Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.drip.background)
                        .frame(height: 12)
                    Rectangle()
                        .fill(row.color)
                        .frame(width: max(fraction * geo.size.width, row.miles > 0 ? 4 : 0), height: 12)
                }
            }
            .frame(height: 12)

            // Miles + percent
            HStack(spacing: 8) {
                Text(formatMiles(row.miles))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.drip.textPrimary)
                    .frame(width: 48, alignment: .trailing)
                Text(formatPercent(row.percent))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.drip.textTertiary)
                    .frame(width: 32, alignment: .trailing)
            }
        }
    }

    // MARK: - Math

    private struct ZoneRow {
        let label: String
        let color: Color
        let paceRange: String
        let miles: Double
        let percent: Double
    }

    /// Compute zone boundaries from the anchors and assign each workout's
    /// distance to the zone whose pace range it falls into. Returns one
    /// row per anchor in slowest-first order.
    private func computeRows() -> [ZoneRow] {
        // Anchors are sorted slowest-first by paceSeconds DESC (larger seconds = slower).
        let sortedAnchors = anchors.sorted { $0.paceSeconds > $1.paceSeconds }
        guard sortedAnchors.count >= 2 else {
            return sortedAnchors.map {
                ZoneRow(
                    label: $0.label,
                    color: $0.color,
                    paceRange: formatPace($0.paceSeconds) + " /MI",
                    miles: 0,
                    percent: 0
                )
            }
        }

        // Boundaries: midpoint between adjacent anchors. The slowest zone owns
        // everything slower than the midpoint of (slowest, next-slowest); the
        // fastest zone owns everything faster than the midpoint of the last two.
        var bounds: [Double] = []   // bounds.count == sortedAnchors.count - 1
        for i in 0..<(sortedAnchors.count - 1) {
            bounds.append((sortedAnchors[i].paceSeconds + sortedAnchors[i + 1].paceSeconds) / 2)
        }

        // Assign each workout's miles to a zone
        var milesPerZone = Array(repeating: 0.0, count: sortedAnchors.count)
        for w in workouts {
            let pace = w.pacePerMile * 60   // RunningWorkout.pacePerMile is min/mi → seconds/mi
            guard pace > 0 else { continue }
            let zoneIdx = zoneIndex(forPace: pace, bounds: bounds)
            milesPerZone[zoneIdx] += w.distanceMiles
        }
        let total = milesPerZone.reduce(0, +)

        // Pace range labels per zone
        return sortedAnchors.enumerated().map { idx, anchor in
            let lo: Double
            let hi: Double
            if idx == 0 {
                // Slowest zone — open-ended on the slow side, capped by first boundary
                lo = bounds.first ?? anchor.paceSeconds
                hi = .infinity
            } else if idx == sortedAnchors.count - 1 {
                // Fastest zone — open-ended on the fast side
                lo = 0
                hi = bounds.last ?? anchor.paceSeconds
            } else {
                lo = bounds[idx]
                hi = bounds[idx - 1]
            }
            let range = paceRangeLabel(lo: lo, hi: hi, anchor: anchor.paceSeconds)
            let miles = milesPerZone[idx]
            let pct = total > 0 ? (miles / total * 100) : 0
            return ZoneRow(
                label: anchor.label,
                color: anchor.color,
                paceRange: range,
                miles: miles,
                percent: pct
            )
        }
    }

    /// Find the zone index for a given pace, given the boundaries between
    /// adjacent anchors. Boundaries are sorted slowest-first (descending
    /// seconds).
    private func zoneIndex(forPace pace: Double, bounds: [Double]) -> Int {
        // Slowest zone (idx 0): pace > bounds[0]
        // Middle zones (idx i): bounds[i] <= pace < bounds[i-1]
        // Fastest zone (last): pace <= bounds[last]
        for (i, b) in bounds.enumerated() {
            if pace > b {
                return i
            }
        }
        return bounds.count
    }

    // MARK: - Format

    private func paceRangeLabel(lo: Double, hi: Double, anchor: Double) -> String {
        if hi == .infinity {
            return "≥ \(formatPace(lo)) /MI"
        }
        if lo == 0 {
            return "≤ \(formatPace(hi)) /MI"
        }
        return "\(formatPace(hi))–\(formatPace(lo)) /MI"
    }

    private func formatPace(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    private func formatMiles(_ miles: Double) -> String {
        if miles == 0 { return "—" }
        if miles < 10 { return String(format: "%.1fMI", miles) }
        return "\(Int(miles.rounded()))MI"
    }

    private func formatPercent(_ pct: Double) -> String {
        if pct == 0 { return "" }
        return "\(Int(pct.rounded()))%"
    }
}

// MARK: - Preview

#if DEBUG
struct PaceZoneBarsChart_Previews: PreviewProvider {
    static var previews: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("PACE & VOLUME")
                    .font(.dripCaption(11))
                    .tracking(1.2)
                    .foregroundStyle(Color.drip.textSecondary)
                Spacer()
                Text("47.2 MI · 7 DAYS")
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textSecondary)
            }
            Rectangle().fill(Color.drip.divider).frame(height: 1)
            // Mock workouts to drive the bars (sub-3:10 marathoner mid-block)
            PaceZoneBarsChart(
                workouts: [
                    .init(id: UUID(), startDate: Date(), endDate: Date(), distanceMiles: 6.0, durationMinutes: 51, pacePerMile: 8.5, calories: 0, sourceApp: ""),
                    .init(id: UUID(), startDate: Date(), endDate: Date(), distanceMiles: 8.0, durationMinutes: 58, pacePerMile: 7.25, calories: 0, sourceApp: ""),
                    .init(id: UUID(), startDate: Date(), endDate: Date(), distanceMiles: 11.0, durationMinutes: 80, pacePerMile: 7.27, calories: 0, sourceApp: ""),
                    .init(id: UUID(), startDate: Date(), endDate: Date(), distanceMiles: 6.0, durationMinutes: 53, pacePerMile: 8.83, calories: 0, sourceApp: ""),
                    .init(id: UUID(), startDate: Date(), endDate: Date(), distanceMiles: 4.0, durationMinutes: 26, pacePerMile: 6.5, calories: 0, sourceApp: ""),
                    .init(id: UUID(), startDate: Date(), endDate: Date(), distanceMiles: 18.0, durationMinutes: 144, pacePerMile: 8.0, calories: 0, sourceApp: ""),
                ],
                anchors: PaceVolumeSpectrumChart.defaultAnchors(
                    easyPace: 510, marathonPace: 435, thresholdPace: 395, fiveKPace: 360
                )
            )
        }
        .padding(20)
        .background(Color.drip.background)
        .previewLayout(.sizeThatFits)
    }
}
#endif
