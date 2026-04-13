//
//  InjuryAnalysisComponents.swift
//  RunningLog
//
//  AI analysis display components for the injury tracking feature.
//

import SwiftUI

// MARK: - InjuryAnalysisSection

struct InjuryAnalysisSection: View {
    let injury: Injury
    @Bindable var injuryService: InjuryService

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("AI ANALYSIS")
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textTertiary)
                    .tracking(1.2)

                Spacer()

                if let analysisDate = injury.aiAnalysisAt {
                    Text(analysisDate, style: .relative)
                        .font(.dripCaption(10))
                        .foregroundStyle(Color.drip.textTertiary)
                }
            }

            if let analysis = injury.aiAnalysis {
                AnalysisResultView(analysis: analysis)
            } else if injuryService.isAnalyzing {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(Color.drip.coral)
                    Text("Analyzing injury...")
                        .font(.dripBody(13))
                        .foregroundStyle(Color.drip.textSecondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.drip.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                if let error = injuryService.errorMessage {
                    Text(error)
                        .font(.dripCaption(12))
                        .foregroundStyle(Color.drip.injured)
                        .padding(.bottom, 4)
                }

                Button {
                    Task { _ = await injuryService.analyzeInjury(injuryId: injury.id) }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Analyze Injury")
                            .font(.dripLabel(14))
                    }
                    .foregroundStyle(Color.drip.coral)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.drip.coral.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.drip.coral.opacity(0.3), lineWidth: 1)
                    )
                }
            }

            MedicalDisclaimerBanner(text: MedicalDisclaimer.aiAnalysis, isCompact: true)
        }
    }
}

// MARK: - AnalysisResultView

struct AnalysisResultView: View {
    let analysis: InjuryAnalysis

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Summary
            if let summary = analysis.summary {
                Text(summary)
                    .font(.dripBody(14))
                    .foregroundStyle(Color.drip.textPrimary)
                    .lineSpacing(3)
            }

            // Risk level
            if let risk = analysis.riskLevel {
                HStack(spacing: 6) {
                    Circle()
                        .fill(analysis.riskColor)
                        .frame(width: 8, height: 8)
                    Text("Risk: \(risk.capitalized)")
                        .font(.dripLabel(13))
                        .foregroundStyle(analysis.riskColor)
                }
            }

            // Recurring injury warning
            if analysis.isRecurring == true {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Recurring injury pattern detected")
                        .font(.dripLabel(12))
                }
                .foregroundStyle(.orange)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Recovery timeline
            if let timeline = analysis.recoveryTimelineDays {
                VStack(alignment: .leading, spacing: 4) {
                    Text("RECOVERY TIMELINE")
                        .font(.dripCaption(10))
                        .foregroundStyle(Color.drip.textTertiary)
                        .tracking(0.8)

                    HStack(spacing: 16) {
                        if let opt = timeline.optimistic {
                            TimelineStatView(label: "Best", days: opt, color: Color.drip.positive)
                        }
                        if let typ = timeline.typical {
                            TimelineStatView(label: "Typical", days: typ, color: Color.drip.tired)
                        }
                        if let con = timeline.conservative {
                            TimelineStatView(label: "Conservative", days: con, color: Color.drip.injured)
                        }
                    }
                }
            }

            // Likely causes
            if let causes = analysis.likelyCauses, !causes.isEmpty {
                AnalysisListSection(title: "LIKELY CAUSES", items: causes, icon: "arrow.right.circle.fill", color: Color.drip.textSecondary)
            }

            // Recommended actions
            if let actions = analysis.recommendedActions, !actions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("RECOMMENDED ACTIONS")
                        .font(.dripCaption(10))
                        .foregroundStyle(Color.drip.textTertiary)
                        .tracking(0.8)

                    ForEach(actions) { action in
                        HStack(alignment: .top, spacing: 8) {
                            Text(action.priorityLabel)
                                .font(.dripCaption(9))
                                .foregroundStyle(action.priorityColor)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(action.priorityColor.opacity(0.12))
                                .clipShape(Capsule())
                                .frame(width: 52)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(action.action)
                                    .font(.dripLabel(12))
                                    .foregroundStyle(Color.drip.textPrimary)
                                Text(action.detail)
                                    .font(.dripBody(11))
                                    .foregroundStyle(Color.drip.textSecondary)
                            }
                        }
                    }
                }
            }

            // Warning signs
            if let warnings = analysis.warningSigns, !warnings.isEmpty {
                AnalysisListSection(title: "SEEK MEDICAL ATTENTION IF", items: warnings, icon: "exclamationmark.triangle.fill", color: Color.drip.injured)
            }

            // Return to running
            if let criteria = analysis.returnToRunningCriteria, !criteria.isEmpty {
                AnalysisListSection(title: "RETURN TO RUNNING WHEN", items: criteria, icon: "checkmark.circle.fill", color: Color.drip.positive)
            }

            // Goal impact
            if let goalImpact = analysis.goalImpact, !goalImpact.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("GOAL IMPACT")
                        .font(.dripCaption(10))
                        .foregroundStyle(Color.drip.textTertiary)
                        .tracking(0.8)

                    Text(goalImpact)
                        .font(.dripBody(12))
                        .foregroundStyle(Color.drip.textSecondary)
                        .lineSpacing(2)
                }
            }
        }
        .padding(16)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - AnalysisListSection

struct AnalysisListSection: View {
    let title: String
    let items: [String]
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.dripCaption(10))
                .foregroundStyle(Color.drip.textTertiary)
                .tracking(0.8)

            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                        .foregroundStyle(color)
                        .padding(.top, 2)
                    Text(item)
                        .font(.dripBody(12))
                        .foregroundStyle(Color.drip.textSecondary)
                }
            }
        }
    }
}

// MARK: - TimelineStatView

struct TimelineStatView: View {
    let label: String
    let days: Int
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text("\(days)")
                .font(.dripStat(18))
                .foregroundStyle(color)
            Text(label)
                .font(.dripCaption(9))
                .foregroundStyle(Color.drip.textTertiary)
        }
    }
}
