//
//  BiomechanicsResultsView.swift
//  RunningLog
//
//  Displays biomechanics analysis results — joint angles, ROM,
//  foot strike pattern, and shank angle at contact.
//

import SwiftUI

// MARK: - BiomechanicsResultsView

struct BiomechanicsResultsView: View {
    @State var analysis: BiomechanicsAnalysis
    @State private var biomechanicsService = BiomechanicsService()
    @State private var isRequestingAI = false
    @State var showingInfo: BiomechanicsInfoType?

    var body: some View {
        ZStack {
            Color.drip.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    // Disclaimer
                    MedicalDisclaimerBanner(text: BiomechanicsDisclaimer.analysis, isCompact: true)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                    // Header card
                    headerCard
                        .padding(.horizontal, 20)

                    // Foot strike pattern
                    if let footStrike = analysis.footStrike {
                        footStrikeCard(footStrike)
                            .padding(.horizontal, 20)
                    }

                    // Joint angles
                    if let jointAngles = analysis.jointAngles {
                        jointAnglesSection(jointAngles)
                    }

                    // Shank angle
                    if let shankLeft = analysis.jointAngles?.shankLeft,
                       let shankRight = analysis.jointAngles?.shankRight
                    {
                        shankAngleSection(left: shankLeft, right: shankRight)
                    } else if let shank = analysis.jointAngles?.shankLeft ?? analysis.jointAngles?.shankRight {
                        shankAngleSection(shank: shank)
                    }

                    // Shoulder Rotation
                    if let shoulderRotation = analysis.jointAngles?.shoulderRotation {
                        shoulderRotationSection(shoulderRotation)
                    }

                    // Ground Contact Time & Balance
                    if let gaitMetrics = analysis.gaitMetrics {
                        gaitMetricsSection(gaitMetrics)
                    }

                    // AI Analysis
                    if let aiAnalysis = analysis.aiAnalysis {
                        aiAnalysisSection(aiAnalysis)
                    } else {
                        // AI analysis loading / retry
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

                                    Text("AI analysis of your running form, injury risk factors, and personalized drill recommendations.")
                                        .font(.dripBody(13))
                                        .foregroundStyle(Color.drip.textSecondary)
                                        .multilineTextAlignment(.center)

                                    DripButton("Analyze with AI", icon: "sparkles", style: .primary) {
                                        requestAIAnalysis()
                                    }
                                }

                                if let error = biomechanicsService.errorMessage {
                                    Text(error)
                                        .font(.dripCaption(11))
                                        .foregroundStyle(Color.drip.injured)

                                    DripButton("Retry", icon: "arrow.clockwise", style: .secondary) {
                                        biomechanicsService.errorMessage = nil
                                        requestAIAnalysis()
                                    }
                                }
                            }
                            .padding(20)
                            .background(Color.drip.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .padding(.horizontal, 20)
                        }
                    }

                    Spacer().frame(height: 40)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("ANALYSIS RESULTS")
                    .font(.dripCaption(12))
                    .foregroundStyle(Color.drip.textSecondary)
                    .tracking(2)
            }
        }
        .toolbarBackground(Color.drip.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .sheet(item: $showingInfo) { infoType in
            BiomechanicsInfoSheet(type: infoType)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .task {
            // Auto-trigger AI analysis if not yet available
            if analysis.aiAnalysis == nil && !isRequestingAI {
                requestAIAnalysis()
            }
        }
    }

    // MARK: - AI Analysis Request

    private func requestAIAnalysis() {
        guard !isRequestingAI else { return }
        isRequestingAI = true
        Task {
            let aiResult = await biomechanicsService.requestAIAnalysis(analysisId: analysis.id)
            await MainActor.run {
                if let aiResult {
                    analysis.aiAnalysis = aiResult
                    analysis.aiAnalysisAt = Date()
                }
                isRequestingAI = false
            }
        }
    }

    // MARK: - Header Card

    private var headerCard: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(analysis.displayDate)
                        .font(.dripLabel(18))
                        .foregroundStyle(Color.drip.textPrimary)

                    if let notes = analysis.notes, notes.hasPrefix("Combined from") {
                        Text(notes)
                            .font(.dripCaption(12))
                            .foregroundStyle(Color.drip.textSecondary)
                    } else {
                        Text(analysis.viewAngle.displayName)
                            .font(.dripCaption(12))
                            .foregroundStyle(Color.drip.textSecondary)
                    }
                }

                Spacer()

                // Status badge
                HStack(spacing: 4) {
                    Image(systemName: analysis.status.icon)
                        .font(.system(size: 10))
                    Text(analysis.status.displayName)
                        .font(.dripCaption(11))
                }
                .foregroundStyle(analysis.statusColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(analysis.statusColor.opacity(0.12))
                .clipShape(Capsule())
            }

            // Metadata row
            HStack(spacing: 16) {
                if let duration = analysis.durationSeconds {
                    metadataItem(icon: "clock", value: String(format: "%.1fs", duration))
                }
                if let frameCount = analysis.frameCount {
                    metadataItem(icon: "film", value: "\(frameCount) frames")
                }
                if let fps = analysis.fps {
                    metadataItem(icon: "gauge.with.dots.needle.bottom.50percent", value: String(format: "%.0f fps", fps))
                }
                Spacer()
            }
        }
        .padding(16)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func metadataItem(icon: String, value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(Color.drip.textTertiary)
            Text(value)
                .font(.dripCaption(11))
                .foregroundStyle(Color.drip.textSecondary)
        }
    }

    // MARK: - Foot Strike Card

    func footStrikeCard(_ footStrike: FootStrikeAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("Foot Strike Pattern", action: { showingInfo = .footStrike }, actionIcon: "info.circle")

            HStack(spacing: 16) {
                // Pattern badge
                VStack(spacing: 8) {
                    Image(systemName: "shoe.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(footStrike.pattern.color)

                    Text(footStrike.pattern.displayName)
                        .font(.dripLabel(15))
                        .foregroundStyle(Color.drip.textPrimary)

                    Text("\(Int(footStrike.confidence * 100))% confidence")
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(footStrike.pattern.color.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                // Details
                VStack(alignment: .leading, spacing: 10) {
                    if let shankAngle = footStrike.shankAngleAtContact {
                        angleDetail(label: "Shank at Contact", value: shankAngle, unit: "°")
                    }
                }
                .frame(maxWidth: .infinity)
            }

            Text(footStrike.pattern.description)
                .font(.dripBody(12))
                .foregroundStyle(Color.drip.textTertiary)

            // Video frame overlay at contact
            if let contactDetail = footStrike.contactFrameDetail,
               let videoURL = videoURLForOverlay
            {
                FootStrikeOverlayView(
                    videoURL: videoURL,
                    contactFrame: contactDetail,
                    pattern: footStrike.pattern
                )
            }
        }
        .padding(16)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    /// Resolve the local video URL for the overlay.
    private var videoURLForOverlay: URL? {
        if let filename = analysis.localVideoFilename {
            return BiomechanicsService.localVideoURL(for: filename)
        }
        // Debug test: check if Shannon.mov is bundled
        return Bundle.main.url(forResource: "Shannon", withExtension: "mov")
    }

    func angleDetail(label: String, value: Double, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.dripCaption(10))
                .foregroundStyle(Color.drip.textTertiary)
            Text(String(format: "%.1f%@", value, unit))
                .font(.dripLabel(16))
                .foregroundStyle(Color.drip.textPrimary)
        }
    }
}
