//
//  ThresholdCheckSection.swift
//  RunningLog · Trends
//
//  Trends section 05 — the threshold check. Renders `ThresholdCheckRead`
//  (`ThresholdCheckModels.swift`): a verdict, the efforts behind it, the
//  context that doesn't get a vote, and what the check cannot test.
//
//  **The verdict is carried by words and weight, never by hue.** No green
//  "good band", no red "bad band" — that would be a grade, and this surface
//  observes. Coral appears exactly once, on the verdict line, because that is
//  the "now" of this surface (three-palette rule, `CLAUDE.md`).
//
//  There is no button that moves the band. The controls for that live in
//  section 04 above, where the athlete already owns them.
//

import SwiftUI

struct ThresholdCheckView: View {
    let read: ThresholdCheckRead
    /// Tapping an effort opens the workout behind it.
    var onOpen: ((ThresholdEffort) -> Void)?

    var body: some View {
        if read.isEmpty {
            EmptyStateView(
                variant: .dataPending,
                eyebrow: "No band yet",
                title: "Once your log carries a pace band, this checks it against the efforts that tested it."
            )
        } else {
            VStack(alignment: .leading, spacing: 0) {
                verdictLine
                headline.padding(.top, 10)

                if !read.efforts.isEmpty {
                    Text("THE EFFORTS THAT TESTED IT")
                        .font(.dripEyebrow(9))
                        .tracking(0.9)
                        .foregroundStyle(Color.drip.textTertiary)
                        .padding(.top, 20)
                    ForEach(read.efforts) { effort in
                        effortRow(effort)
                    }
                }

                contextRows.padding(.top, 18)

                if let note = ThresholdCheckProse.note(read) {
                    InstrumentNote(note, eyebrow: "WHAT THE DATA SAYS")
                }
            }
        }
    }

    // MARK: Verdict

    private var verdictLine: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(Color.drip.coral)
                .frame(width: 3, height: 13)
            Text(read.verdict.label)
                .font(.dripEyebrow(11).weight(.semibold))
                .tracking(1.3)
                .foregroundStyle(Color.drip.textPrimary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Verdict: \(read.verdict.label)")
    }

    private var headline: some View {
        Text(ThresholdCheckProse.headline(read))
            .font(.dripDisplay(21))
            .foregroundStyle(Color.drip.textPrimary)
            .lineSpacing(1)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Efforts

    private func effortRow(_ effort: ThresholdEffort) -> some View {
        Button {
            onOpen?(effort)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(effort.dateLabel.uppercased())
                    .font(.dripEyebrow(9))
                    .tracking(0.8)
                    .foregroundStyle(Color.drip.textTertiary)
                    .frame(width: 54, alignment: .leading)

                VStack(alignment: .leading, spacing: 3) {
                    Text(readingLabel(effort))
                        .font(.dripEyebrow(9.5).weight(.semibold))
                        .tracking(0.9)
                        .foregroundStyle(Color.drip.textPrimary)
                    Text(detail(effort))
                        .font(.dripEyebrow(8.5))
                        .tracking(0.6)
                        .foregroundStyle(Color.drip.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Text(String(format: "%.1f%%", effort.decouplingPct))
                    .font(.dripStat(14))
                    .foregroundStyle(Color.drip.textPrimary)
            }
            .padding(.vertical, 9)
            .overlay(alignment: .bottom) { Hairline() }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(effort.dateLabel), \(readingLabel(effort)), drift \(String(format: "%.1f", effort.decouplingPct)) percent")
    }

    /// Words, not colour.
    private func readingLabel(_ effort: ThresholdEffort) -> String {
        switch effort.reading {
        case .held: effort.heldByMargin ? "HELD, COMFORTABLY" : "HELD"
        case .failed: "DID NOT HOLD"
        case .inconclusive: "INCONCLUSIVE"
        }
    }

    private func detail(_ effort: ThresholdEffort) -> String {
        var parts = [
            "\(TrendsFormat.pace(effort.paceSec)) /MI",
            String(format: "%+.0f%% VS BAND", effort.devPct),
            "\(Int(effort.durationMin.rounded())) MIN",
        ]
        if effort.inHeat { parts.append("IN HEAT") }
        return parts.joined(separator: " · ")
    }

    // MARK: Context

    private var contextRows: some View {
        InstrumentStatRow(items: contextItems)
    }

    private var contextItems: [InstrumentStatRow.Item] {
        var items: [InstrumentStatRow.Item] = []

        if let anchor = read.anchorSec {
            items.append(.init(
                value: TrendsFormat.pace(anchor),
                unit: read.anchorLabel.uppercased(),
                detail: "YOUR BAND"
            ))
        }
        if let age = read.anchorAgeDays {
            items.append(.init(
                value: "\(age / 7)",
                unit: age / 7 == 1 ? "WEEK" : "WEEKS",
                detail: "SINCE IT MOVED"
            ))
        }
        if let drift = read.drift {
            if drift.isDirectional {
                items.append(.init(
                    value: String(format: "%+.1f%%", drift.pct),
                    unit: "EFFICIENCY",
                    detail: "AT BAND PACE"
                ))
            } else {
                // A null with a stated resolution is a finding. It is not an
                // empty cell, so it never becomes a dash (hard rule #8).
                items.append(.init(
                    value: "NO CHANGE",
                    unit: String(format: "\u{00B1}%.0f%%", drift.resolutionPct),
                    detail: "EFFICIENCY AT BAND"
                ))
            }
        }
        return items
    }
}

// MARK: - Previews

#Preview("Threshold check · untested") {
    ThresholdCheckView(read: ThresholdCheckRead(
        verdict: .untested,
        efforts: [],
        anchorSec: 311,
        anchorLabel: "HMP",
        anchorAgeDays: 77,
        drift: EfficiencyDrift(pct: -0.2, loPct: -2.0, hiPct: 1.2),
        nearMissCount: 12,
        closestDevPct: 14.8
    ))
    .padding(24)
    .background(Color.drip.background)
}
