//
//  InsightCard.swift
//  RunningLog
//
//  Compact card for displaying AI insights in a horizontal scroll.
//

import SwiftUI

struct InsightCard: View {
    let insight: AIInsight
    let onTap: () -> Void

    @State private var showDetail = false

    private var accentColor: Color {
        switch insight.priority {
        case "high": return Color.drip.struggling
        case "medium": return Color.drip.tired
        default: return Color.drip.positive
        }
    }

    private var typeLabel: String {
        switch insight.insightType {
        case "post_run_analysis": return "POST-RUN"
        case "injury_early_warning": return "INJURY RISK"
        case "race_readiness": return "RACE READY"
        default: return "INSIGHT"
        }
    }

    var body: some View {
        Button {
            showDetail = true
            onTap()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                // Header
                HStack(spacing: 6) {
                    Image(systemName: insight.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(accentColor)

                    Text(typeLabel)
                        .font(.dripCaption(9))
                        .foregroundStyle(accentColor)
                        .tracking(1)

                    Spacer()

                    if insight.isUnread {
                        Circle()
                            .fill(Color.drip.coral)
                            .frame(width: 6, height: 6)
                    }
                }

                // Title or summary
                if let title = insight.title, !title.isEmpty {
                    Text(title)
                        .font(.dripLabel(12))
                        .foregroundStyle(Color.drip.textPrimary)
                        .lineLimit(1)
                }

                // Summary preview
                if let summary = insight.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.dripBody(11))
                        .foregroundStyle(Color.drip.textSecondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }

                // Time
                Text(insight.createdAt, style: .relative)
                    .font(.dripCaption(9))
                    .foregroundStyle(Color.drip.textTertiary)
            }
            .frame(width: 220, alignment: .leading)
            .padding(12)
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(insight.isUnread ? accentColor.opacity(0.3) : Color.drip.divider, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetail) {
            InsightDetailSheet(insight: insight)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Detail Sheet

struct InsightDetailSheet: View {
    let insight: AIInsight
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.drip.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Type badge
                        HStack(spacing: 6) {
                            Image(systemName: insight.icon)
                                .font(.system(size: 14, weight: .semibold))
                            Text(insight.insightType.replacingOccurrences(of: "_", with: " ").uppercased())
                                .font(.dripCaption(11))
                                .tracking(1.5)
                        }
                        .foregroundStyle(Color.drip.coral)

                        // Title
                        if let title = insight.title, !title.isEmpty {
                            Text(title)
                                .font(.dripDisplay(22))
                                .foregroundStyle(Color.drip.textPrimary)
                        }

                        // Date
                        Text(insight.createdAt, format: .dateTime.weekday(.wide).month(.abbreviated).day().hour().minute())
                            .font(.dripCaption(12))
                            .foregroundStyle(Color.drip.textTertiary)

                        // Summary
                        if let summary = insight.summary, !summary.isEmpty {
                            Text(summary)
                                .font(.dripBody(15))
                                .foregroundStyle(Color.drip.textPrimary)
                                .lineSpacing(5)
                                .padding(16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.drip.cardBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(Color.drip.coral.opacity(0.15), lineWidth: 1)
                                )
                        }

                        // Full analysis
                        if let full = insight.fullAnalysis, !full.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("FULL ANALYSIS")
                                    .font(.dripCaption(10))
                                    .foregroundStyle(Color.drip.textTertiary)
                                    .tracking(1.5)

                                Text(full)
                                    .font(.dripBody(14))
                                    .foregroundStyle(Color.drip.textSecondary)
                                    .lineSpacing(4)
                            }
                        }

                        Spacer().frame(height: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.dripBody(15))
                        .foregroundStyle(Color.drip.textSecondary)
                }
            }
            .toolbarBackground(Color.drip.background, for: .navigationBar)
        }
    }
}
