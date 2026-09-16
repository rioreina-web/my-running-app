//
//  AskView.swift
//  RunningLog · Analysis
//
//  The Ask surface's two public pieces:
//
//    • `AskBar`       — the affordance at the foot of Trends. Chip rail plus,
//                       when free text ships, a question field. Presents
//                       `CoachAskSheet`, which renders the answer.
//    • `AskAnswerCard` — the answer itself: narration over fact lines over a
//                       chart, with the coverage statement under all of it.
//
//  Why the foot of Trends and not a tab: Trends answers "how am I trending".
//  Ask answers "why, and compared to what". They're different questions —
//  mixing them is what made the old eleven-block Trends tab unreadable — but
//  the second one is what an athlete wants *immediately after* reading the
//  first, so it lives at the bottom of that scroll rather than behind a tab.
//
//  What these views will NOT do:
//    • compute a number. Every figure comes from `facts`.
//    • fill a gap when narration is absent. The facts stand alone.
//    • suggest a question the registry can't answer. Follow-ups are the
//      analyzer's own `related` ids, resolved server-side.
//

import SwiftUI

// MARK: - AskBar (the Trends foot)

struct AskBar: View {
    @State private var service = AskService.shared
    @State private var staged: StagedAsk?

    /// What the sheet was opened with. Identifiable so `.sheet(item:)` can
    /// present it without a second boolean to keep in sync.
    struct StagedAsk: Identifiable {
        let id = UUID()
        let analyzer: AskAnalyzer?
        let question: String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("ASK")
                    .font(.dripEyebrow(10))
                    .tracking(1.3)
                    .foregroundStyle(Color.drip.coral)
                Text("Why, and compared to what.")
                    .font(.dripDisplay(21))
                    .foregroundStyle(Color.drip.textPrimary)
                Text("This page shows the shape. Ask reads one session against its fairest match, trends a pace band across the block, or checks whether the ramp is holding — computed from your own runs, then put into words.")
                    .font(.dripBody(14))
                    .lineSpacing(3)
                    .foregroundStyle(Color.drip.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if service.catalog.isEmpty {
                Text("The question list loads from the analysis service. It fills in once you're online.")
                    .font(.dripBody(13.5))
                    .foregroundStyle(Color.drip.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                FlowRow(spacing: 6) {
                    ForEach(service.catalog) { analyzer in
                        AskChip(label: analyzer.label) {
                            staged = StagedAsk(analyzer: analyzer, question: analyzer.label)
                        }
                    }
                }
            }

            if AskFeature.freeTextEnabled {
                Button {
                    staged = StagedAsk(analyzer: nil, question: "")
                } label: {
                    HStack {
                        Text("Ask something else…")
                            .font(.dripBody(14))
                            .foregroundStyle(Color.drip.textTertiary)
                        Spacer()
                        Image(systemName: "arrow.up")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.drip.textSecondary)
                    }
                    .padding(.horizontal, 15)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(Color.drip.cardBackground))
                    .overlay(Capsule().stroke(Color.drip.divider, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .task { await service.loadCatalog() }
        .sheet(item: $staged) { item in
            CoachAskSheet(
                question: item.question,
                focus: nil,
                analyzer: item.analyzer
            )
        }
    }
}

// MARK: - Answer card

struct AskAnswerCard: View {
    let question: String
    let response: AskResponse
    let onFollowup: (AskFollowup) -> Void
    /// Nil hides the switcher — callers that can't re-run (previews, history)
    /// shouldn't show a control that does nothing.
    var onVariant: ((AskVariant) -> Void)?
    /// The variant being fetched, so the tapped chip can show it's working
    /// without blanking the answer already on screen.
    var pendingVariant: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if onVariant != nil, response.variants.count > 1 { variantRail }
            switch response.mode {
            case .ambiguous:
                ambiguousBody
            default:
                if let empty = response.empty { emptyBody(empty) } else { analyzedBody }
            }
            if !response.followups.isEmpty { followupRail }
        }
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.drip.cardBackground))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.drip.divider, lineWidth: 1))
    }

    /// `prose` used to badge itself "NO ANALYZER" — the registry reporting its
    /// own coverage gap to someone who never asked about the registry. Since
    /// 2026-08-10 that outcome renders as an ordinary conversational answer in
    /// `CoachAskSheet` and this card isn't built for it at all; the label is
    /// kept honest for the DEBUG/preview paths that can still construct one.
    private var badge: (text: String, color: Color) {
        switch response.mode {
        case .analyzed:  return ("COMPUTED", Color.drip.coral)
        case .prose:     return ("FROM THE COACH", Color.drip.textSecondary)
        case .ambiguous: return ("WHICH ONE?", Color.drip.tired)
        case .catalog:   return ("CATALOG", Color.drip.textSecondary)
        }
    }

    /// The headline. Prefers what the analyzer actually answered over what the
    /// chip asked — tapping "Is my LT pace improving?" when the athlete's fast
    /// work is mostly 10K resolves to "Is my 10K pace improving?", so the title
    /// stops contradicting the facts directly beneath it.
    private var headline: String {
        response.resolvedTitle ?? question
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(badge.text)
                .font(.dripEyebrow(8.5))
                .tracking(1.1)
                .foregroundStyle(badge.color)
            Text(headline)
                .font(.dripDisplay(18))
                .foregroundStyle(Color.drip.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 15)
        .padding(.top, 13)
    }

    private var analyzedBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let narration = response.narration {
                Text(narration.text)
                    .font(.dripBody(14.5))
                    .lineSpacing(3)
                    .foregroundStyle(Color.drip.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
                if let caveat = narration.caveat {
                    Text(caveat)
                        .font(.dripBody(13).italic())
                        .lineSpacing(2)
                        .foregroundStyle(Color.drip.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                }
            }

            if !response.facts.isEmpty {
                AskFactGrid(facts: response.facts)
                    .padding(.top, response.narration == nil ? 12 : 14)
            }

            if let series = response.series, series.points.count > 1 {
                VStack(alignment: .leading, spacing: 6) {
                    AskChart(series: series)
                    AskChartAxis(series: series)
                }
                .padding(.top, 14)
            }

            if let coverage = response.coverage {
                AskCoverageRow(coverage: coverage)
            }
        }
        .padding(.horizontal, 15)
        .padding(.bottom, 14)
    }

    private func emptyBody(_ empty: AskEmptyState) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(empty.eyebrow.uppercased())
                .font(.dripEyebrow(9))
                .tracking(1.1)
                .foregroundStyle(Color.drip.textTertiary)
            Text(empty.nudge)
                .font(.dripBody(14.5))
                .lineSpacing(3)
                .foregroundStyle(Color.drip.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let coverage = response.coverage {
                AskCoverageRow(coverage: coverage)
            }
        }
        .padding(.horizontal, 15)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    private var ambiguousBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("A few ways to read that. Which one did you mean?")
                .font(.dripBody(14.5))
                .foregroundStyle(Color.drip.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let options = response.disambiguation {
                FlowRow(spacing: 6) {
                    ForEach(options) { option in
                        AskChip(label: option.label, emphasis: .followup) {
                            onFollowup(AskFollowup(id: option.id, label: option.label))
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 15)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    /// The zone switcher. Only drawn when there is a genuine choice — a single
    /// band on file is a fact about the training, not a control.
    private var variantRail: some View {
        FlowRow(spacing: 6) {
            ForEach(response.variants) { variant in
                AskChip(
                    label: variant.label,
                    emphasis: variant.active ? .selected : .standard,
                    isDisabled: pendingVariant != nil
                ) {
                    onVariant?(variant)
                }
                .opacity(pendingVariant == variant.label ? 0.55 : 1)
            }
        }
        .padding(.horizontal, 15)
        .padding(.top, 11)
        .accessibilityLabel("Pace band")
    }

    private var followupRail: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("NEXT")
                .font(.dripEyebrow(8))
                .tracking(1.1)
                .foregroundStyle(Color.drip.textTertiary)
            FlowRow(spacing: 6) {
                ForEach(response.followups) { followup in
                    AskChip(label: followup.label, emphasis: .followup) {
                        onFollowup(followup)
                    }
                }
            }
        }
        .padding(.horizontal, 15)
        .padding(.bottom, 14)
    }
}

// MARK: - FlowRow

/// Wrapping horizontal stack. Chips are variable-width sentences, so a
/// fixed-column grid leaves ragged holes; this packs them like text.
struct FlowRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
