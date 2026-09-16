//
//  DripEditorialPrimitives.swift
//  RunningLog
//
//  Small reusable view structs that match the Post Run Drip "editorial"
//  vocabulary: plate strips, hairlines, mono stat strips, key:value rows.
//  Drop into `App/DesignSystem.swift` or keep as its own file — either way,
//  no new tokens are introduced; everything resolves to existing
//  `Color.drip.*` + `.dripCaption(n)`.
//

import SwiftUI

// MARK: - Plate strip
// Mono editorial header. Replaces the chunky `.toolbar` nav bar across
// the rebrand. Two stacked mono lines on each side, sized 10pt / 0.14em.

struct DripPlateStrip: View {
    let leadingTop: String
    let leadingBottom: String
    let trailingTop: String?
    let trailingBottom: String

    init(
        leadingTop: String = "RUNNING LOG",
        leadingBottom: String,
        trailingTop: String? = nil,
        trailingBottom: String
    ) {
        self.leadingTop = leadingTop
        self.leadingBottom = leadingBottom
        self.trailingTop = trailingTop
        self.trailingBottom = trailingBottom
    }

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(leadingTop)
                    .font(.dripCaption(10))
                    .tracking(1.4)
                    .foregroundStyle(Color.drip.textPrimary)
                Text("— " + leadingBottom)
                    .font(.dripCaption(10))
                    .tracking(1.4)
                    .foregroundStyle(Color.drip.textSecondary)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 2) {
                if let trailingTop {
                    Text(trailingTop)
                        .font(.dripCaption(10))
                        .tracking(1.4)
                        .foregroundStyle(Color.drip.textPrimary)
                }
                Text(trailingBottom)
                    .font(.dripCaption(10))
                    .tracking(1.4)
                    .foregroundStyle(Color.drip.textSecondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
    }
}

// MARK: - Hairline
// 1pt full-width rule. Use horizontal padding on the parent VStack so the
// rule respects the 24pt editorial margins.

struct DripHairline: View {
    var body: some View {
        Rectangle()
            .fill(Color.drip.divider)
            .frame(height: 1)
    }
}

// MARK: - Eyebrow
// Mono uppercase label, 10pt, 14% tracking. Optional coral variant for the
// one-hit-per-cluster active state.

struct DripEyebrow: View {
    let text: String
    var coral: Bool = false

    var body: some View {
        Text(text)
            .font(.dripCaption(10))
            .tracking(1.4)
            .foregroundStyle(coral ? Color.drip.coral : Color.drip.textSecondary)
    }
}

// MARK: - Stat strip
// 5-cell hairline-bordered numeric strip. Mono numerals with optional unit
// hint. This is the replacement for both the "Distance: 6.9 mi /
// Duration: 51:06 / …" serif paragraph AND the mint LINKED WORKOUT tile —
// one component does both jobs.

struct DripStat {
    let label: String          // e.g. "DIST"
    let value: String          // e.g. "6.9"
    let unit: String?          // e.g. "mi" (small, secondary)

    init(_ label: String, _ value: String, unit: String? = nil) {
        self.label = label
        self.value = value
        self.unit = unit
    }
}

struct DripStatStrip: View {
    let stats: [DripStat]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(stats.enumerated()), id: \.offset) { idx, stat in
                VStack(spacing: 6) {
                    Text(stat.label)
                        .font(.dripCaption(9))
                        .tracking(1.2)
                        .foregroundStyle(Color.drip.textTertiary)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(stat.value)
                            .font(.dripCaption(18))
                            .fontWeight(.semibold)
                            .monospacedDigit()
                            .foregroundStyle(Color.drip.textPrimary)
                        if let unit = stat.unit {
                            Text(unit)
                                .font(.dripCaption(10))
                                .foregroundStyle(Color.drip.textTertiary)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                if idx < stats.count - 1 {
                    Rectangle()
                        .fill(Color.drip.divider)
                        .frame(width: 1)
                }
            }
        }
        .overlay(alignment: .top) { DripHairline() }
        .overlay(alignment: .bottom) { DripHairline() }
    }
}

// MARK: - Underlined coral text link
// Replaces the pink "Get Coach Feedback" pill and the gray "Save Notes"
// pill. Lives inline — no card, no background fill.

struct DripTextLink: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.dripLabel(14))
                .foregroundStyle(Color.drip.coral)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color.drip.coral)
                        .frame(height: 1)
                        .offset(y: 2)
                }
                .padding(.bottom, 3)
        }
        .buttonStyle(.plain)
    }
}
