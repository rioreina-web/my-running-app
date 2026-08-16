//
//  TrainingLoadExplainer.swift
//  RunningLog
//
//  What TLS is, opened by tapping a TLS number.
//
//  The week section had been carrying a one-line definition — "intensity ×
//  minutes; a minute at 5K pace costs 5.5× a minute easy" — under every day
//  panel. It was true, it was permanent furniture on a surface being cut
//  down, and it still did not answer the question, because the interesting
//  part of TLS is not the formula but the SHAPE of the weighting: that the
//  cost of a minute rises eightfold across the range, and non-linearly.
//
//  So the definition became a graphic behind a tap. The ladder is the whole
//  idea in one look — bar length is what a minute in that zone costs — and
//  the worked example underneath grounds it in the exact number the athlete
//  just tapped, so the sheet is explaining THEIR 114, not an abstraction.
//
//  THE WEIGHTS ARE NOT DECLARED HERE. They are read from `TrendsZoneWeight`,
//  which is already the one client-side mirror of `ZONE_WEIGHTS` in
//  `_shared/workoutSegmentation.ts`. A hand-typed copy in an explainer is the
//  worst possible place for the table to drift, because it is the screen that
//  claims to be authoritative.
//

import SwiftUI

struct TrainingLoadExplainer: View {

    /// The day whose number was tapped, if any. Nil renders the concept
    /// without the worked example rather than inventing a sample day —
    /// a made-up example on an explainer screen teaches the wrong number.
    let day: WeekTrainingLoadSection.LoadDay?

    @ScaledMetric(relativeTo: .caption2)
    private var eyebrowMicro: CGFloat = DripTypeFloor.eyebrowMicro
    @ScaledMetric(relativeTo: .caption)
    private var eyebrowSmall: CGFloat = DripTypeFloor.eyebrowSmall

    /// The heaviest weight in the table sets the full-bar length, so the
    /// ladder is a ratio chart and not an arbitrary scale.
    private var maxWeight: Double {
        ZoneTaxonomy.ordered.map { TrendsZoneWeight.weight($0) }.max() ?? 8
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                Text("TRAINING LOAD SCORE")
                    .font(.dripEyebrow(eyebrowSmall)).tracking(1.3)
                    .foregroundStyle(Color.drip.textSecondary)

                // Intensity and duration are named outright. The old lede
                // ("minutes, weighted by how hard those minutes were") was
                // accurate but described the arithmetic; this says what the
                // number is FOR before the ladder explains how it is built.
                Text("Intensity × duration — one number for the training stress a run carried.")
                    .font(.system(size: 17, design: .serif))
                    .foregroundStyle(Color.drip.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)

                Hairline().padding(.top, 22)

                // MARK: The ladder

                Text("THE COST OF ONE MINUTE")
                    .font(.dripEyebrow(eyebrowMicro)).tracking(1.1)
                    .foregroundStyle(Color.drip.textTertiary)
                    .padding(.top, 16)
                    .padding(.bottom, 4)

                ForEach(ZoneTaxonomy.ordered, id: \.self) { token in
                    ladderRow(token)
                }

                Text("Ten minutes easy costs 10. The same ten minutes at 5K costs 55.")
                    .font(.system(size: 13, design: .serif))
                    .foregroundStyle(Color.drip.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)

                // MARK: This day, worked

                if let d = day, d.hasZones {
                    Hairline().padding(.top, 22)

                    Text("WHERE \(d.label.uppercased())'S \(Int(d.load.rounded())) CAME FROM")
                        .font(.dripEyebrow(eyebrowMicro)).tracking(1.1)
                        .foregroundStyle(Color.drip.textTertiary)
                        .padding(.top, 16)
                        .padding(.bottom, 4)

                    ForEach(d.zones) { z in
                        workedRow(z)
                    }

                    HStack {
                        Text("TOTAL")
                            .font(.dripEyebrow(eyebrowMicro)).tracking(1.1)
                            .foregroundStyle(Color.drip.textSecondary)
                        Spacer()
                        Text("\(Int(d.load.rounded())) TLS")
                            .font(.dripStat(eyebrowSmall + 3))
                            .foregroundStyle(Color.drip.textPrimary)
                    }
                    .padding(.top, 10)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(Color.drip.textTertiary)
                            .frame(height: 1)
                    }

                    // The same caveat the day panel carries. Repeated here
                    // rather than assumed: this is the screen that explains
                    // where the number came from, so a chunk of the run that
                    // is NOT in it belongs on the page.
                    if d.hasUnclassified {
                        Text("The \(String(format: "%.1f", d.unclassifiedMiles)) mi that came in "
                             + "without a pace zone are not in this total.")
                            .font(.system(size: 12, design: .serif).italic())
                            .foregroundStyle(Color.drip.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 12)
                    }
                }

                Hairline().padding(.top, 22)

                Text("TLS is for comparing one week against another. It is not a score out "
                     + "of anything, it is not fitness, and it is not a recommendation.")
                    .font(.system(size: 13, design: .serif))
                    .foregroundStyle(Color.drip.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 16)
            }
            .padding(.horizontal, 22)
            .padding(.top, 24)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.drip.background)
        .presentationDragIndicator(.visible)
    }

    // MARK: Rows

    /// Zone name, a bar whose length is the multiplier, and the multiplier.
    /// The bar carries the shape — that the top of the range costs eight
    /// times the bottom, and that the jumps are not even — which the numbers
    /// alone do not communicate at a glance.
    private func ladderRow(_ token: String) -> some View {
        let w = TrendsZoneWeight.weight(token)
        // A zone the tapped day actually ran is set in primary ink. Nothing
        // is hidden from the others; the emphasis just answers "which of
        // these applied to me" without a second graphic.
        let used = day?.zones.contains { $0.token == token } ?? false

        return HStack(spacing: 9) {
            Text(ZoneTaxonomy.label(token))
                .font(.dripEyebrow(eyebrowMicro)).tracking(0.9)
                .foregroundStyle(used ? Color.drip.textPrimary : Color.drip.textSecondary)
                .frame(width: 58, alignment: .leading)
                .lineLimit(1)

            GeometryReader { g in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.drip.paperDeep)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(ZoneTaxonomy.color(token))
                        .frame(width: max(2, g.size.width * CGFloat(w / maxWeight)))
                }
            }
            .frame(height: 13)

            Text("×\(Self.fmtWeight(w))")
                .font(.dripStat(eyebrowSmall + 1))
                .foregroundStyle(Color.drip.textPrimary)
                .frame(width: 42, alignment: .trailing)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(ZoneTaxonomy.label(token)): one minute costs \(Self.fmtWeight(w))"
        )
    }

    /// `HMP  23 min  ×3.25  75` — the multiplication done in front of you,
    /// with the day's own minutes.
    private func workedRow(_ z: WeekTrainingLoadSection.ZoneTotal) -> some View {
        VStack(spacing: 0) {
            Hairline()
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(ZoneTaxonomy.color(z.token))
                    .frame(width: 8, height: 13)
                Text(ZoneTaxonomy.label(z.token))
                    .font(.dripEyebrow(eyebrowMicro)).tracking(0.9)
                    .foregroundStyle(Color.drip.textSecondary)
                    .padding(.leading, 8)
                    .frame(width: 60, alignment: .leading)

                // ONE DECIMAL, NOT WHOLE MINUTES. This row shows its own
                // arithmetic, so the numbers on it have to multiply. Rounding
                // 9.9 minutes to "10" next to a true load of 39 printed
                // "10 min × 4 = 39" — an explainer screen visibly failing to
                // do the multiplication it is explaining. The tenth is worth
                // more here than the tidier integer.
                Text("\(String(format: "%.1f", z.minutes)) min")
                    .font(.dripStat(eyebrowSmall + 1))
                    .foregroundStyle(Color.drip.textPrimary)

                Spacer()

                Text("×\(Self.fmtWeight(TrendsZoneWeight.weight(z.token)))")
                    .font(.dripStat(eyebrowSmall + 1))
                    .foregroundStyle(Color.drip.textTertiary)

                Text("\(Int(z.load.rounded()))")
                    .font(.dripStat(eyebrowSmall + 1))
                    .foregroundStyle(Color.drip.textPrimary)
                    .frame(width: 48, alignment: .trailing)
            }
            .padding(.vertical, 8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(ZoneTaxonomy.label(z.token)): \(String(format: "%.1f", z.minutes)) minutes "
            + "times \(Self.fmtWeight(TrendsZoneWeight.weight(z.token))) "
            + "is \(Int(z.load.rounded()))"
        )
    }

    /// "1", "1.4", "2.15" — trailing zeros stripped so the column reads as
    /// multipliers rather than as currency.
    private static func fmtWeight(_ w: Double) -> String {
        if w == w.rounded() { return String(Int(w)) }
        var s = String(format: "%.2f", w)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }
}
