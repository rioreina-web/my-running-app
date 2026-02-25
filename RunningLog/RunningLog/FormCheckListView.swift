//
//  FormCheckListView.swift
//  RunningLog
//
//  Entry point for the Form Check feature — lists past form checks
//  and provides access to new single-video capture.
//

import SwiftUI

// MARK: - FormCheckListView

struct FormCheckListView: View {
    @State private var formCheckService = FormCheckService()
    @State private var selectedCheck: FormCheck?
    @State private var showNewCheck = false

    var body: some View {
        ZStack {
            Color.drip.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    // Disclaimer
                    MedicalDisclaimerBanner(text: FormCheckDisclaimer.analysis, isCompact: true)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                    // Completed checks
                    if !formCheckService.completedChecks.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader("Form Checks (\(formCheckService.completedChecks.count))")
                                .padding(.horizontal, 20)

                            LazyVStack(spacing: 10) {
                                ForEach(formCheckService.completedChecks) { check in
                                    FormCheckCard(formCheck: check)
                                        .onTapGesture { selectedCheck = check }
                                        .contextMenu {
                                            Button(role: .destructive) {
                                                Task { _ = await formCheckService.deleteFormCheck(id: check.id) }
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }

                    // Empty state
                    if formCheckService.formChecks.isEmpty && !formCheckService.isLoading {
                        VStack(spacing: 16) {
                            Image(systemName: "figure.run.circle")
                                .font(.system(size: 48))
                                .foregroundStyle(Color.drip.coral.opacity(0.5))

                            Text("No form checks yet")
                                .font(.dripBody(16))
                                .foregroundStyle(Color.drip.textSecondary)

                            Text("Quick form check from a single video. AI will analyze your running form for imbalances, posture, and foot strike.")
                                .font(.dripBody(13))
                                .foregroundStyle(Color.drip.textTertiary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)

                            DripButton("Check Your Form", icon: "video.fill", style: .primary) {
                                showNewCheck = true
                            }
                            .padding(.horizontal, 60)
                        }
                        .padding(.top, 60)
                    }

                    Spacer().frame(height: 80)
                }
            }

            // Floating add button
            if !formCheckService.formChecks.isEmpty {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            showNewCheck = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 56, height: 56)
                                .background(Color.drip.coral)
                                .clipShape(Circle())
                                .shadow(color: Color.drip.coral.opacity(0.4), radius: 8, y: 4)
                        }
                        .padding(.trailing, 24)
                        .padding(.bottom, 24)
                    }
                }
            }

            if formCheckService.isLoading {
                ProgressView()
                    .tint(Color.drip.coral)
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
        .onAppear {
            Task { await formCheckService.fetchFormChecks() }
        }
        .sheet(item: $selectedCheck) { check in
            NavigationStack {
                FormCheckResultsView(formCheck: check, formCheckService: formCheckService)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                selectedCheck = nil
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(Color.drip.textSecondary)
                            }
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(role: .destructive) {
                                let id = check.id
                                selectedCheck = nil
                                Task { _ = await formCheckService.deleteFormCheck(id: id) }
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(Color.drip.injured)
                            }
                        }
                    }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $showNewCheck) {
            FormCheckCaptureView(formCheckService: formCheckService)
        }
    }
}

// MARK: - FormCheckCard

private struct FormCheckCard: View {
    let formCheck: FormCheck

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Top row: date + chevron
            HStack {
                Text(formCheck.displayDate)
                    .font(.dripLabel(15))
                    .foregroundStyle(Color.drip.textPrimary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.drip.textTertiary)
            }

            // Assessment snippet
            if let assessment = formCheck.aiAnalysis?.overallAssessment {
                Text(assessment.prefix(100) + (assessment.count > 100 ? "..." : ""))
                    .font(.dripBody(12))
                    .foregroundStyle(Color.drip.textSecondary)
                    .lineLimit(2)
            }

            // Finding severity dots
            if let findings = formCheck.aiAnalysis?.findings, !findings.isEmpty {
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "eye.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.drip.textTertiary)
                        Text("\(findings.count) finding\(findings.count == 1 ? "" : "s")")
                            .font(.dripCaption(11))
                            .foregroundStyle(Color.drip.textTertiary)
                    }

                    // Severity dots for top 3 findings
                    HStack(spacing: 3) {
                        ForEach(Array(findings.prefix(3).enumerated()), id: \.offset) { _, finding in
                            Circle()
                                .fill(finding.severityColor)
                                .frame(width: 6, height: 6)
                        }
                    }

                    Spacer()
                }
            } else if formCheck.aiAnalysis == nil {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10))
                    Text("AI analysis pending")
                        .font(.dripCaption(11))
                }
                .foregroundStyle(Color.drip.tired)
            }
        }
        .padding(16)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
