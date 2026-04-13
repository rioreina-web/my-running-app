//
//  FormCheckResultsView.swift
//  RunningLog
//
//  AI-first qualitative results display for form checks.
//  Shows narrative findings, compensation patterns, and drill recommendations.
//

import SwiftUI

struct FormCheckResultsView: View {
    @State var formCheck: FormCheck
    let formCheckService: FormCheckService

    @State private var isRequestingAI = false

    var body: some View {
        ZStack {
            Color.drip.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    // Disclaimer
                    MedicalDisclaimerBanner(text: FormCheckDisclaimer.analysis, isCompact: true)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                    // Header
                    headerCard
                        .padding(.horizontal, 20)

                    // AI Analysis content
                    if let ai = formCheck.aiAnalysis {
                        aiContent(ai)
                    } else {
                        aiLoadingCard
                    }

                    Spacer().frame(height: 40)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("FORM CHECK")
                    .font(.dripCaption(12))
                    .foregroundStyle(Color.drip.textSecondary)
                    .tracking(2)
            }
        }
        .toolbarBackground(Color.drip.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task {
            if formCheck.aiAnalysis == nil && !isRequestingAI {
                await requestAIAnalysis()
            }
        }
    }

    // MARK: - Header Card

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(formCheck.displayDate)
                        .font(.dripLabel(16))
                        .foregroundStyle(Color.drip.textPrimary)

                    HStack(spacing: 12) {
                        if let duration = formCheck.durationSeconds {
                            HStack(spacing: 4) {
                                Image(systemName: "timer")
                                    .font(.system(size: 11))
                                Text("\(duration, specifier: "%.1f")s")
                                    .font(.dripCaption(11))
                            }
                            .foregroundStyle(Color.drip.textSecondary)
                        }

                        if let frames = formCheck.frameCount {
                            HStack(spacing: 4) {
                                Image(systemName: "film")
                                    .font(.system(size: 11))
                                Text("\(frames) frames")
                                    .font(.dripCaption(11))
                            }
                            .foregroundStyle(Color.drip.textSecondary)
                        }
                    }
                }

                Spacer()

                Text(formCheck.status.displayName.uppercased())
                    .font(.dripCaption(9))
                    .tracking(0.5)
                    .foregroundStyle(formCheck.statusColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(formCheck.statusColor.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
        .padding(16)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - AI Content

    @ViewBuilder
    private func aiContent(_ ai: FormCheckAIAnalysis) -> some View {
        if ai.notRunning == true {
            // Not a running video — show rejection message
            notRunningCard(ai.overallAssessment ?? "This doesn't appear to be a running video.")
        } else {
            // Overall assessment
            if let assessment = ai.overallAssessment {
                overallAssessmentCard(assessment)
            }

            // Findings
            if let findings = ai.findings, !findings.isEmpty {
                findingsSection(findings)
            }

            // Compensation patterns
            if let patterns = ai.compensationPatterns, !patterns.isEmpty {
                compensationSection(patterns)
            }

            // Drills
            if let drills = ai.drills, !drills.isEmpty {
                drillsSection(drills)
            }

            // Summary
            if let summary = ai.summary {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "text.quote")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.drip.coral)
                        Text("Takeaway")
                            .font(.dripLabel(14))
                            .foregroundStyle(Color.drip.textPrimary)
                    }

                    Text(summary)
                        .font(.dripBody(14))
                        .foregroundStyle(Color.drip.textSecondary)
                        .italic()
                }
                .padding(16)
                .background(Color.drip.coral.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.drip.coral.opacity(0.15), lineWidth: 1)
                )
                .padding(.horizontal, 20)
            }

            // Disclaimer
            if let disclaimer = ai.disclaimer {
                Text(disclaimer)
                    .font(.dripCaption(10))
                    .foregroundStyle(Color.drip.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
    }

    // MARK: - Not Running Card

    private func notRunningCard(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "figure.run.circle")
                .font(.system(size: 40))
                .foregroundStyle(Color.drip.textTertiary)

            Text("Not a Running Video")
                .font(.dripLabel(16))
                .foregroundStyle(Color.drip.textPrimary)

            Text(message)
                .font(.dripBody(14))
                .foregroundStyle(Color.drip.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 20)
    }

    // MARK: - Overall Assessment

    private func overallAssessmentCard(_ assessment: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Overall Assessment")
                .padding(.horizontal, 20)

            Text(assessment)
                .font(.dripBody(14))
                .foregroundStyle(Color.drip.textSecondary)
                .lineSpacing(3)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.drip.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 20)
        }
    }

    // MARK: - Findings

    private func findingsSection(_ findings: [FormCheckFinding]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Findings")
                .padding(.horizontal, 20)

            ForEach(findings) { finding in
                VStack(alignment: .leading, spacing: 10) {
                    // Area + severity badge
                    HStack {
                        HStack(spacing: 6) {
                            Image(systemName: finding.severityIcon)
                                .font(.system(size: 12))
                                .foregroundStyle(finding.severityColor)
                            Text(finding.area)
                                .font(.dripLabel(14))
                                .foregroundStyle(Color.drip.textPrimary)
                        }
                        Spacer()
                        Text(finding.severityLabel)
                            .font(.dripCaption(11))
                            .foregroundStyle(finding.severityColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(finding.severityColor.opacity(0.12))
                            .clipShape(Capsule())
                    }

                    // Observation
                    Text(finding.observation)
                        .font(.dripBody(13))
                        .foregroundStyle(Color.drip.textSecondary)

                    // Detail
                    if !finding.detail.isEmpty {
                        Text(finding.detail)
                            .font(.dripBody(12))
                            .foregroundStyle(Color.drip.textTertiary)
                            .lineSpacing(2)
                    }
                }
                .padding(16)
                .background(Color.drip.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - Compensation Patterns

    private func compensationSection(_ patterns: [CompensationPattern]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Compensation Patterns")
                .padding(.horizontal, 20)

            ForEach(patterns) { pattern in
                VStack(alignment: .leading, spacing: 10) {
                    // Pattern name
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.drip.tired)
                        Text(pattern.pattern)
                            .font(.dripLabel(14))
                            .foregroundStyle(Color.drip.textPrimary)
                    }

                    // Likely cause
                    HStack(alignment: .top, spacing: 6) {
                        Text("Likely cause:")
                            .font(.dripCaption(11))
                            .foregroundStyle(Color.drip.textTertiary)
                        Text(pattern.likelyCause)
                            .font(.dripBody(12))
                            .foregroundStyle(Color.drip.textSecondary)
                    }

                    // Affected areas chain
                    if !pattern.affectedAreas.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(Array(pattern.affectedAreas.enumerated()), id: \.offset) { index, area in
                                if index > 0 {
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 8))
                                        .foregroundStyle(Color.drip.textTertiary)
                                }
                                Text(area)
                                    .font(.dripCaption(10))
                                    .foregroundStyle(Color.drip.tired)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.drip.tired.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
                .padding(16)
                .background(Color.drip.tired.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.drip.tired.opacity(0.15), lineWidth: 1)
                )
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - Drills

    private func drillsSection(_ drills: [FormDrill]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.drip.coral)
                Text("RECOMMENDED DRILLS")
                    .font(.dripCaption(12))
                    .foregroundStyle(Color.drip.textSecondary)
                    .tracking(1.5)
            }
            .padding(.horizontal, 24)

            ForEach(drills) { drill in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(drill.name)
                            .font(.dripLabel(14))
                            .foregroundStyle(Color.drip.textPrimary)

                        Spacer()

                        Text(drill.target)
                            .font(.dripCaption(10))
                            .foregroundStyle(Color.drip.coral)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.drip.coral.opacity(0.12))
                            .clipShape(Capsule())
                    }

                    Text(drill.description)
                        .font(.dripBody(12))
                        .foregroundStyle(Color.drip.textSecondary)
                        .lineSpacing(2)

                    HStack(spacing: 4) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 11))
                        Text(drill.frequency)
                            .font(.dripCaption(11))
                    }
                    .foregroundStyle(Color.drip.positive)
                }
                .padding(16)
                .background(Color.drip.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - AI Loading Card

    private var aiLoadingCard: some View {
        VStack(spacing: 12) {
            SectionHeader("AI Form Analysis")
                .padding(.horizontal, 20)

            VStack(spacing: 16) {
                if isRequestingAI {
                    ProgressView()
                        .tint(Color.drip.coral)
                        .scaleEffect(1.2)
                    Text("Analyzing your running form...")
                        .font(.dripBody(13))
                        .foregroundStyle(Color.drip.textSecondary)
                } else {
                    Image(systemName: "brain")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.drip.coral.opacity(0.6))

                    Text("AI will analyze your form for imbalances, posture issues, and foot strike pattern.")
                        .font(.dripBody(13))
                        .foregroundStyle(Color.drip.textSecondary)
                        .multilineTextAlignment(.center)

                    DripButton("Analyze with AI", icon: "sparkles", style: .primary) {
                        Task { await requestAIAnalysis() }
                    }
                }

                if let error = formCheckService.errorMessage {
                    Text(error)
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.injured)

                    DripButton("Retry", icon: "arrow.clockwise", style: .secondary) {
                        formCheckService.errorMessage = nil
                        Task { await requestAIAnalysis() }
                    }
                }
            }
            .padding(20)
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 20)
        }
    }

    // MARK: - AI Request

    private func requestAIAnalysis() async {
        isRequestingAI = true
        if let result = await formCheckService.requestAIAnalysis(formCheckId: formCheck.id) {
            formCheck.aiAnalysis = result
            formCheck.aiAnalysisAt = Date()
        }
        isRequestingAI = false
    }
}
