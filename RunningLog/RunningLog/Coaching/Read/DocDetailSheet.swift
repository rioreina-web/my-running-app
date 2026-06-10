//
//  DocDetailSheet.swift
//  RunningLog
//
//  The full-content view for a knowledge doc cited in a Coach Read.
//  Presented as a sheet from `CoachReadView` (Phase 4.1) when the user
//  taps a `DocChip` — inline or expanded.
//
//  This is a stub per Phase 3.2 of coach-the-read-prompts.md: it just
//  renders the doc's title, category eyebrow, and verbatim content in
//  a scrollable layout. Rich-text formatting, related-docs surfaces,
//  and saved-state are future scope.
//

import SwiftUI

struct DocDetailSheet: View {
    let doc: CoachingDocument

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Category eyebrow (mono, kerned, ink-tertiary).
                    if let category = doc.category, !category.isEmpty {
                        Text(category.uppercased())
                            .font(.dripStat(10))
                            .foregroundStyle(Color.drip.textTertiary)
                            .tracking(1.0) // 0.10em × 10pt
                    }

                    // Title — display register, two-line max for the
                    // big-headline feel.
                    Text(doc.title)
                        .font(.dripDisplay(28))
                        .foregroundStyle(Color.drip.textPrimary)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(2)

                    // Editorial rule between title and body.
                    Rectangle()
                        .fill(Color.drip.divider)
                        .frame(height: 1)
                        .padding(.vertical, 4)

                    // Body. Stub-level rendering — plain prose at body
                    // register, generous line-height for readability.
                    // Rich-text (markdown headings, bullet lists, code)
                    // is future scope; right now we just print the
                    // verbatim content.
                    Text(doc.content)
                        .font(.dripBody(16))
                        .foregroundStyle(Color.drip.textPrimary)
                        .lineSpacing(6)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(Color.drip.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color.drip.textSecondary)
                    }
                }
                ToolbarItem(placement: .principal) {
                    // Plate strip — same mono header convention used
                    // throughout the Coach Read surface.
                    Text("RUNNING LOG · KNOWLEDGE")
                        .font(.dripStat(10))
                        .foregroundStyle(Color.drip.textSecondary)
                        .tracking(1.4) // 0.14em × 10pt — plate strip tracking
                }
            }
            .toolbarBackground(Color.drip.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}

// MARK: - Preview

#Preview("DocDetailSheet") {
    DocDetailSheet(
        doc: CoachingDocument(
            id: UUID(uuidString: "bbbbbbbb-1111-1111-1111-111111111111")!,
            title: "Aerobic support through a build block",
            category: "training principles",
            content:
                """
                Aerobic support workouts — easy runs, long runs, and steady efforts — do most of the development work in the middle of a block. The temptation is to push every tempo. The discipline is to hold steady.

                Look for: consistent pace on long runs (steady, never drifting fast), easy days that actually feel easy (the test is conversation), and a moderate session every 10-14 days that keeps the aerobic engine awake without taxing recovery.

                Avoid: turning every Tuesday into a hero workout. Avoid: chasing pace on the easy day because the legs feel good. The block is long; the gains are cumulative.

                The athletes who develop fastest over a 12-week block aren't the ones who push hardest on Tuesday. They're the ones who execute every easy day correctly and arrive at Saturday's long run with fresh legs.
                """
        )
    )
}
