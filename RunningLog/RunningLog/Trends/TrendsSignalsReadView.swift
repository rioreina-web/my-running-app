//
//  TrendsSignalsReadView.swift
//  RunningLog · Trends
//
//  "What moved" — the five-second read, now that the score is gone.
//
//  Sits above the lanes because the order is the argument: the finding
//  first, then the evidence you can check it against. The lanes answer
//  "show me"; this answers "is there anything to look at".
//
//  ── Two deliberate refusals ───────────────────────────────────────────────
//
//  NO LEADING-EDGE RULE. A 2pt rule at a block's leading edge means MOOD in
//  this system and nothing else (`design-system/README.md`, and the table in
//  CLAUDE.md). These findings are not moods, so the structure is carried by a
//  heavy rule ABOVE the block. Coral is doubly wrong there — it is alert-only
//  and a leading rule is structure — so the accent is spent on one dot beside
//  the eyebrow, which is also the one-coral-per-cluster budget.
//
//  NO COUNT WHEN THERE IS NOTHING. A quiet day gets a sentence, not "0
//  findings" and not an empty card. The whole point of deleting the score was
//  that a surface which must report a figure every morning will invent one.
//

import SwiftUI

struct TrendsSignalsReadView: View {

    let read: TrendsSignalsRead
    /// Opens the lane an item came from, so a finding can be checked against
    /// the chart that produced it without hunting for the right chip.
    var onOpenLane: ((TrendsMoodLane) -> Void)? = nil

    @ScaledMetric(relativeTo: .caption2)
    private var eyebrowSmall: CGFloat = DripTypeFloor.eyebrowSmall

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(Color.drip.textPrimary)
                .frame(height: 2)
                .padding(.bottom, 12)

            HStack(spacing: 7) {
                Circle()
                    .fill(read.isQuiet ? Color.drip.textTertiary : Color.drip.coral)
                    .frame(width: 6, height: 6)
                Text(read.isQuiet ? "Nothing outside your usual" : "What moved")
                    .font(.dripEyebrow(eyebrowSmall)).tracking(1.3)
                    .foregroundStyle(Color.drip.textSecondary)
            }
            .padding(.bottom, read.isQuiet ? 8 : 12)

            if read.isQuiet {
                Text("Every signal is inside the range it normally sits in.")
                    .font(.dripBody(15))
                    .foregroundStyle(Color.drip.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(read.items) { item in
                        row(item)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ item: TrendsSignalsRead.Item) -> some View {
        let content = VStack(alignment: .leading, spacing: 4) {
            Text(item.text)
                .font(.dripBody(15))
                .foregroundStyle(Color.drip.textPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            // The receipt. Every claim above names the baseline it was read
            // against and when — no finding without one.
            Text(item.detail.uppercased())
                .font(.dripEyebrow(eyebrowSmall - 1)).tracking(0.6)
                .foregroundStyle(Color.drip.textTertiary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        if let lane = item.lane, let onOpenLane {
            Button { onOpenLane(lane) } label: { content }
                .buttonStyle(.plain)
                .accessibilityLabel("\(item.text). \(item.detail).")
                .accessibilityHint("Shows the \(lane.chipLabel) lane")
        } else {
            content
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(item.text). \(item.detail).")
        }
    }
}

#Preview("What moved") {
    VStack(alignment: .leading, spacing: 28) {
        TrendsSignalsReadView(
            read: TrendsSignalsRead(items: [
                .init(text: "One night at 3h 17m on Aug 21.",
                      detail: "2.9 SD below your usual 6h 20m",
                      lane: .sleep),
                .init(text: "No sleep or resting HR readings for 3 nights.",
                      detail: "newest is Aug 21 · nothing to place against your usual since",
                      lane: .restingHR),
                .init(text: "Ankle and knee mentioned on 2 of the last 10 days.",
                      detail: "Aug 21 · Aug 22",
                      lane: .niggles),
            ])
        )
        TrendsSignalsReadView(read: TrendsSignalsRead(items: []))
    }
    .padding(20)
    .background(Color.drip.background)
}
