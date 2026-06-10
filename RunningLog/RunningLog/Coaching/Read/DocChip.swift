//
//  DocChip.swift
//  RunningLog
//
//  The § knowledge-doc citation chip used by the Coach Read. Same
//  shape as `EvidenceChip` but with a different visual treatment per
//  the design spec:
//
//    - `.inline(doc:)`   — `§ <title>`, no background fill, 1px border
//                          in `Color.drip.divider`. Sits on the text
//                          baseline; never wraps mid-chip.
//    - `.expanded(doc:)` — full card with title, category eyebrow,
//                          italic excerpt, and a trailing `↗`. Lives
//                          in the Sources panel.
//
//  Tap action: writes the doc's id to a `Binding<UUID?>` on the
//  parent, mirroring EvidenceChip's pattern. `CoachReadView` (Phase
//  4.1) reads the selection and presents `DocDetailSheet`.
//
//  Phase 3.2 of coach-the-read-prompts.md.
//

import SwiftUI

struct DocChip: View {
    enum Form {
        case inline
        case expanded
    }

    let form: Form
    let doc: CoachingDocument
    @Binding var selectedDocId: UUID?

    // MARK: - Convenience initializers

    /// Outlined inline chip — sits on the paragraph's text baseline.
    static func inline(
        doc: CoachingDocument,
        selectedDocId: Binding<UUID?>
    ) -> DocChip {
        DocChip(
            form: .inline,
            doc: doc,
            selectedDocId: selectedDocId
        )
    }

    /// Full doc card — used inside the Sources panel.
    static func expanded(
        doc: CoachingDocument,
        selectedDocId: Binding<UUID?>
    ) -> DocChip {
        DocChip(
            form: .expanded,
            doc: doc,
            selectedDocId: selectedDocId
        )
    }

    // MARK: - Body

    var body: some View {
        switch form {
        case .inline: inlineChip
        case .expanded: expandedCard
        }
    }

    // MARK: - Inline chip

    private var inlineChip: some View {
        Button {
            selectedDocId = doc.id
        } label: {
            Text("§ \(doc.title)")
                .font(.dripCaption(11))
                .foregroundStyle(Color.drip.textPrimary)
                // Body-cased title; less mono kerning than the workout
                // chip. Light tracking keeps the rule-line readable.
                .tracking(0.4)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.drip.divider, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
    }

    // MARK: - Expanded card

    private var expandedCard: some View {
        Button {
            selectedDocId = doc.id
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    // Title.
                    Text(doc.title)
                        .font(.dripDisplay(18))
                        .foregroundStyle(Color.drip.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    // Category eyebrow (mono, ink-3).
                    if let category = doc.category, !category.isEmpty {
                        Text(category.uppercased())
                            .font(.dripStat(10))
                            .foregroundStyle(Color.drip.textTertiary)
                            .tracking(1.0) // 0.10em × 10pt
                    }

                    // Italic excerpt — first ~140 chars of content.
                    Text(doc.coachReadExcerpt)
                        .font(.dripBody(13.5))
                        .italic()
                        .foregroundStyle(Color.drip.textSecondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .padding(.top, 2)
                }

                Spacer(minLength: 8)

                Text("↗")
                    .font(.dripStat(14))
                    .foregroundStyle(Color.drip.textTertiary)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.drip.cardBackgroundElevated)
            .overlay(
                // Cards use 12pt radius (--r-card) per tokens.css.
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.drip.divider, lineWidth: 1)
            )
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - CoachingDocument helpers

private extension CoachingDocument {
    /// Single-paragraph excerpt for the expanded card. Strips internal
    /// double-newlines so the italic block stays compact at three lines.
    var coachReadExcerpt: String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstPara = trimmed.split(
            separator: "\n",
            omittingEmptySubsequences: true
        ).first.map(String.init) ?? trimmed
        let limit = 180
        if firstPara.count <= limit { return firstPara }
        let idx = firstPara.index(firstPara.startIndex, offsetBy: limit)
        return firstPara[..<idx] + "…"
    }
}

// MARK: - Preview

#Preview("DocChip — both forms") {
    DocChipPreviewHost()
        .padding()
        .background(Color.drip.background)
}

private struct DocChipPreviewHost: View {
    @State private var selected: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("INLINE")
                    .font(.dripStat(10))
                    .foregroundStyle(Color.drip.textSecondary)
                    .tracking(0.8)
                HStack(spacing: 6) {
                    Text("The")
                        .font(.dripBody(16))
                    DocChip.inline(
                        doc: Self.mockDoc,
                        selectedDocId: $selected
                    )
                    Text("says hold steady.")
                        .font(.dripBody(16))
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("EXPANDED")
                    .font(.dripStat(10))
                    .foregroundStyle(Color.drip.textSecondary)
                    .tracking(0.8)
                DocChip.expanded(
                    doc: Self.mockDoc,
                    selectedDocId: $selected
                )
            }

            Text("tapped id: \(selected?.uuidString.prefix(8) ?? "—")")
                .font(.dripStat(11))
                .foregroundStyle(Color.drip.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static let mockDoc = CoachingDocument(
        id: UUID(uuidString: "bbbbbbbb-1111-1111-1111-111111111111")!,
        title: "Aerobic support through a build block",
        category: "training principles",
        content:
            """
            Aerobic support workouts — easy runs, long runs, and \
            steady efforts — do most of the development work in the \
            middle of a block. The temptation is to push every \
            tempo. The discipline is to hold steady.
            """
    )
}
