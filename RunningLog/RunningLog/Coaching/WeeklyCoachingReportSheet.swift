//
//  WeeklyCoachingReportSheet.swift
//  RunningLog
//
//  Sheet displaying the AI-generated weekly coaching analysis.
//

import SwiftUI

struct WeeklyCoachingReportSheet: View {
    @State private var service = WeeklyCoachingReportService()
    @State private var report: WeeklyCoachingReport?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.drip.background.ignoresSafeArea()

                if service.isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(Color.drip.coral)
                        Text("Analyzing your week...")
                            .font(.dripBody(14))
                            .foregroundStyle(Color.drip.textSecondary)
                    }
                } else if let report {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            // Week header
                            weekHeader(report)

                            // Coaching narrative — the hero section
                            narrativeSection(report.coachingNarrative)

                            // Alerts (if any)
                            if !report.alerts.isEmpty {
                                alertsSection(report.alerts)
                            }

                            // Adjustments + Focus in a combined action section
                            if !report.adjustments.isEmpty || !report.focusAreas.isEmpty {
                                VStack(alignment: .leading, spacing: 16) {
                                    if !report.adjustments.isEmpty {
                                        adjustmentsSection(report.adjustments)
                                    }
                                    if !report.focusAreas.isEmpty {
                                        focusAreasSection(report.focusAreas)
                                    }
                                }
                                .padding(16)
                                .background(Color.drip.cardBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                            }

                            // Metrics at the bottom — supporting data
                            if let metrics = report.metrics {
                                metricsSection(metrics)
                            }

                            Spacer().frame(height: 40)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                    }
                } else if let error = service.error {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 32))
                            .foregroundStyle(Color.drip.coral)
                        Text(error)
                            .font(.dripBody(14))
                            .foregroundStyle(Color.drip.textSecondary)
                            .multilineTextAlignment(.center)
                        DripButton("Retry", icon: "arrow.clockwise", style: .secondary) {
                            Task { await loadReport() }
                        }
                    }
                    .padding(40)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("WEEKLY ANALYSIS")
                        .font(.dripCaption(12))
                        .foregroundStyle(Color.drip.textSecondary)
                        .tracking(2)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.drip.coral)
                }
            }
            .toolbarBackground(Color.drip.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .task {
            await loadReport()
        }
    }

    private func loadReport() async {
        do {
            report = try await service.fetchReport()
        } catch {
            if service.error == nil {
                service.error = error.localizedDescription
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func weekHeader(_ report: WeeklyCoachingReport) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                if let weekNum = report.planWeekNumber {
                    Text("Week \(weekNum)")
                        .font(.dripLabel(18))
                        .foregroundStyle(Color.drip.textPrimary)
                }
                Text("\(formatWeekDate(report.weekStart)) — \(formatWeekDate(report.weekEnd))")
                    .font(.dripCaption(12))
                    .foregroundStyle(Color.drip.textSecondary)
            }
            Spacer()

            // Overall status from alerts
            let worstSeverity = worstAlertSeverity(report.alerts)
            Image(systemName: alertIcon(worstSeverity))
                .font(.system(size: 24))
                .foregroundStyle(alertColor(worstSeverity))
        }
        .padding(16)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func focusAreasSection(_ areas: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FOCUS THIS WEEK")
                .font(.dripCaption(11))
                .foregroundStyle(Color.drip.textTertiary)
                .tracking(1.5)

            FlowLayout(spacing: 8) {
                ForEach(areas, id: \.self) { area in
                    Text(area)
                        .font(.dripLabel(13))
                        .foregroundStyle(Color.drip.coral)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.drip.coral.opacity(0.1))
                        .clipShape(Capsule())
                }
            }
        }
    }

    @ViewBuilder
    private func alertsSection(_ alerts: [WeeklyAlert]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ALERTS")
                .font(.dripCaption(11))
                .foregroundStyle(Color.drip.textTertiary)
                .tracking(1.5)

            ForEach(alerts) { alert in
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(alertColor(alert.severity))
                        .frame(width: 8, height: 8)
                        .padding(.top, 5)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(alert.title)
                            .font(.dripLabel(14))
                            .foregroundStyle(Color.drip.textPrimary)
                        Text(alert.message)
                            .font(.dripBody(13))
                            .foregroundStyle(Color.drip.textSecondary)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.drip.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    @ViewBuilder
    private func narrativeSection(_ narrative: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section accent bar
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.drip.coral)
                    .frame(width: 3, height: 14)

                Text("COACH'S ANALYSIS")
                    .font(.dripCaption(10))
                    .foregroundStyle(Color.drip.textTertiary)
                    .tracking(2)
            }

            // Split narrative into paragraphs for better typography
            let paragraphs = narrative
                .replacingOccurrences(of: "\\n", with: "\n")
                .components(separatedBy: "\n\n")
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                    Text(paragraph.trimmingCharacters(in: .whitespacesAndNewlines))
                        .font(.dripBody(14))
                        .foregroundStyle(Color.drip.textPrimary)
                        .lineSpacing(5)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.drip.coral.opacity(0.15), lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private func metricsSection(_ metrics: WeeklyMetrics) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("METRICS")
                .font(.dripCaption(11))
                .foregroundStyle(Color.drip.textTertiary)
                .tracking(1.5)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
            ], spacing: 12) {
                if let miles = metrics.totalMiles {
                    metricCell("Miles", value: String(format: "%.1f", miles))
                }
                if let runs = metrics.runCount {
                    metricCell("Runs", value: "\(runs)")
                }
                if let acwr = metrics.acwr {
                    metricCell("ACWR", value: String(format: "%.2f", acwr))
                }
                if let compliance = metrics.complianceScore {
                    metricCell("Compliance", value: "\(Int(compliance * 100))%")
                }
                if let longRun = metrics.longRunMiles {
                    metricCell("Long Run", value: String(format: "%.1f mi", longRun))
                }
                if let volChange = metrics.volumeChangePct {
                    metricCell("Vol Change", value: "\(volChange > 0 ? "+" : "")\(Int(volChange))%")
                }
            }
            .padding(16)
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder
    private func metricCell(_ label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.dripLabel(16))
                .foregroundStyle(Color.drip.textPrimary)
            Text(label)
                .font(.dripCaption(10))
                .foregroundStyle(Color.drip.textTertiary)
        }
    }

    @ViewBuilder
    private func adjustmentsSection(_ adjustments: [WeeklyAdjustment]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RECOMMENDED ADJUSTMENTS")
                .font(.dripCaption(11))
                .foregroundStyle(Color.drip.textTertiary)
                .tracking(1.5)

            ForEach(adjustments) { adj in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(adj.action.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.dripLabel(13))
                            .foregroundStyle(Color.drip.textPrimary)
                        Spacer()
                        Text(adj.priority.capitalized)
                            .font(.dripCaption(11))
                            .foregroundStyle(adjustmentPriorityColor(adj.priority))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(adjustmentPriorityColor(adj.priority).opacity(0.1))
                            .clipShape(Capsule())
                    }

                    Text(adj.targetWorkoutType.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.dripCaption(12))
                        .foregroundStyle(Color.drip.textSecondary)

                    Text(adj.rationale)
                        .font(.dripBody(13))
                        .foregroundStyle(Color.drip.textSecondary)
                        .lineSpacing(2)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.drip.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    // MARK: - Helpers

    private func formatWeekDate(_ dateStr: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateStr) else { return dateStr }
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    private func worstAlertSeverity(_ alerts: [WeeklyAlert]) -> String {
        let order = ["red", "orange", "yellow", "green"]
        for sev in order {
            if alerts.contains(where: { $0.severity == sev }) { return sev }
        }
        return "green"
    }

    private func alertIcon(_ severity: String) -> String {
        switch severity {
        case "red": return "xmark.shield.fill"
        case "orange": return "exclamationmark.triangle.fill"
        case "yellow": return "exclamationmark.shield.fill"
        default: return "checkmark.shield.fill"
        }
    }

    private func alertColor(_ severity: String) -> Color {
        switch severity {
        case "red": return Color.drip.coral
        case "orange": return .orange
        case "yellow": return Color.drip.energized
        default: return Color.drip.positive
        }
    }

    private func adjustmentPriorityColor(_ priority: String) -> Color {
        switch priority {
        case "high": return Color.drip.coral
        case "medium": return Color.drip.energized
        default: return Color.drip.positive
        }
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var maxHeight: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > width, currentX > 0 {
                currentX = 0
                currentY += rowHeight + spacing
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            currentX += size.width + spacing
            maxHeight = currentY + rowHeight
        }

        return CGSize(width: width, height: maxHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        var currentX: CGFloat = bounds.minX
        var currentY: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX, currentX > bounds.minX {
                currentX = bounds.minX
                currentY += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: .unspecified)
            rowHeight = max(rowHeight, size.height)
            currentX += size.width + spacing
        }
    }
}
