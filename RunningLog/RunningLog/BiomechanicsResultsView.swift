//
//  BiomechanicsResultsView.swift
//  RunningLog
//
//  Displays biomechanics analysis results — joint angles, ROM,
//  foot strike pattern, and shank angle at contact.
//

import AVFoundation
import SwiftUI

// MARK: - BiomechanicsResultsView

struct BiomechanicsResultsView: View {
    @State var analysis: BiomechanicsAnalysis
    @State private var biomechanicsService = BiomechanicsService()
    @State private var isRequestingAI = false
    @State private var showingInfo: BiomechanicsInfoType?

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

    private func footStrikeCard(_ footStrike: FootStrikeAnalysis) -> some View {
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

    private func angleDetail(label: String, value: Double, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.dripCaption(10))
                .foregroundStyle(Color.drip.textTertiary)
            Text(String(format: "%.1f%@", value, unit))
                .font(.dripLabel(16))
                .foregroundStyle(Color.drip.textPrimary)
        }
    }

    // MARK: - Joint Angles Section

    private func jointAnglesSection(_ angles: JointAnglesSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Joint Angles", action: { showingInfo = .jointAngles }, actionIcon: "info.circle")
                .padding(.horizontal, 20)

            // Hip
            if let hipLeft = angles.hipLeft {
                jointAngleCard(
                    joint: "Hip",
                    data: hipLeft,
                    referenceRange: BiomechanicsReferenceRanges.hipFlexion,
                    side: "Left"
                )
            }
            if let hipRight = angles.hipRight {
                jointAngleCard(
                    joint: "Hip",
                    data: hipRight,
                    referenceRange: BiomechanicsReferenceRanges.hipFlexion,
                    side: "Right"
                )
            }

            // Knee
            if let kneeLeft = angles.kneeLeft {
                jointAngleCard(
                    joint: "Knee",
                    data: kneeLeft,
                    referenceRange: BiomechanicsReferenceRanges.kneeFlexionSwing,
                    side: "Left"
                )
            }
            if let kneeRight = angles.kneeRight {
                jointAngleCard(
                    joint: "Knee",
                    data: kneeRight,
                    referenceRange: BiomechanicsReferenceRanges.kneeFlexionSwing,
                    side: "Right"
                )
            }

            // Ankle ROM omitted — Vision lacks foot/toe joints, so ankle
            // dorsiflexion cannot be measured accurately.
        }
    }

    private func jointAngleCard(
        joint: String,
        data: JointAngleData,
        referenceRange: BiomechanicsReferenceRanges.JointRange,
        side: String
    ) -> some View {
        let romStatus = BiomechanicsReferenceRanges.status(value: data.rangeOfMotion, range: referenceRange)

        return VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(side) \(joint)")
                        .font(.dripLabel(15))
                        .foregroundStyle(Color.drip.textPrimary)

                    Text("Normal: \(Int(referenceRange.normalMin))°-\(Int(referenceRange.normalMax))°")
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.textTertiary)
                }

                Spacer()

                // ROM status badge
                HStack(spacing: 4) {
                    Circle()
                        .fill(romStatus.color)
                        .frame(width: 6, height: 6)
                    Text(romStatus.label)
                        .font(.dripCaption(11))
                }
                .foregroundStyle(romStatus.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(romStatus.color.opacity(0.12))
                .clipShape(Capsule())
            }

            // Stats grid
            HStack(spacing: 0) {
                angleStat(label: "ROM", value: data.rangeOfMotion)
                angleStat(label: "Mean", value: data.meanAngle)
                angleStat(label: "Max", value: data.maxAngle)
                angleStat(label: "Min", value: data.minAngle)
            }

            // ROM range bar
            ROMRangeBar(
                min: data.minAngle,
                max: data.maxAngle,
                normalMin: referenceRange.normalMin,
                normalMax: referenceRange.normalMax
            )
        }
        .padding(16)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 20)
    }

    private func angleStat(label: String, value: Double) -> some View {
        VStack(spacing: 2) {
            Text(String(format: "%.1f°", value))
                .font(.dripLabel(16))
                .foregroundStyle(Color.drip.textPrimary)
            Text(label)
                .font(.dripCaption(10))
                .foregroundStyle(Color.drip.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Shank Angle Section

    private func shankAngleSection(left: ShankAngleData, right: ShankAngleData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Shank Angle (Overstriding)", action: { showingInfo = .shankAngle }, actionIcon: "info.circle")
                .padding(.horizontal, 20)

            HStack(spacing: 10) {
                shankCard(data: left, side: "Left")
                shankCard(data: right, side: "Right")
            }
            .padding(.horizontal, 20)
        }
    }

    private func shankAngleSection(shank: ShankAngleData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Shank Angle (Overstriding)", action: { showingInfo = .shankAngle }, actionIcon: "info.circle")
                .padding(.horizontal, 20)

            shankCard(data: shank, side: "")
                .padding(.horizontal, 20)
        }
    }

    private func shankCard(data: ShankAngleData, side: String) -> some View {
        let risk = data.overstridingRisk

        return VStack(spacing: 10) {
            if !side.isEmpty {
                Text(side)
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textSecondary)
            }

            if let atContact = data.atInitialContact {
                Text(String(format: "%.1f°", atContact))
                    .font(.dripLabel(24))
                    .foregroundStyle(risk.color)

                Text("at initial contact")
                    .font(.dripCaption(10))
                    .foregroundStyle(Color.drip.textTertiary)
            }

            HStack(spacing: 4) {
                Circle()
                    .fill(risk.color)
                    .frame(width: 6, height: 6)
                Text(risk == .normal ? "Good" : risk == .borderline ? "Mild overstriding" : "Overstriding")
                    .font(.dripCaption(11))
                    .foregroundStyle(risk.color)
            }

            Text("Ideal: < 5° past vertical")
                .font(.dripCaption(10))
                .foregroundStyle(Color.drip.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Shoulder Rotation Section

    private func shoulderRotationSection(_ data: ShoulderRotationData) -> some View {
        let status = data.rotationStatus

        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Shoulder Rotation", action: { showingInfo = .shoulderRotation }, actionIcon: "info.circle")
                .padding(.horizontal, 20)

            VStack(spacing: 14) {
                // Status badge
                HStack {
                    Text("Trunk Counter-Rotation")
                        .font(.dripLabel(15))
                        .foregroundStyle(Color.drip.textPrimary)

                    Spacer()

                    HStack(spacing: 4) {
                        Circle()
                            .fill(status.color)
                            .frame(width: 6, height: 6)
                        Text(status.label)
                            .font(.dripCaption(11))
                    }
                    .foregroundStyle(status.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(status.color.opacity(0.12))
                    .clipShape(Capsule())
                }

                // Stats
                HStack(spacing: 0) {
                    VStack(spacing: 2) {
                        Text(String(format: "%.1f°", data.rangeOfMotion))
                            .font(.dripLabel(16))
                            .foregroundStyle(Color.drip.textPrimary)
                        Text("ROM")
                            .font(.dripCaption(10))
                            .foregroundStyle(Color.drip.textTertiary)
                    }
                    .frame(maxWidth: .infinity)

                    VStack(spacing: 2) {
                        Text(String(format: "%.1f°", data.meanRotation))
                            .font(.dripLabel(16))
                            .foregroundStyle(Color.drip.textPrimary)
                        Text("Mean")
                            .font(.dripCaption(10))
                            .foregroundStyle(Color.drip.textTertiary)
                    }
                    .frame(maxWidth: .infinity)

                    VStack(spacing: 2) {
                        Text(String(format: "%.1f°", data.peakRotation))
                            .font(.dripLabel(16))
                            .foregroundStyle(Color.drip.textPrimary)
                        Text("Peak")
                            .font(.dripCaption(10))
                            .foregroundStyle(Color.drip.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                }

                // Reference
                ROMRangeBar(
                    min: 0,
                    max: data.rangeOfMotion,
                    normalMin: 5,
                    normalMax: 15
                )

                Text("Normal: 5°-15° ROM. Efficient counter-rotation reduces energy waste.")
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textTertiary)
            }
            .padding(16)
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Gait Metrics Section

    private func gaitMetricsSection(_ metrics: GaitMetrics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Ground Contact Time", action: { showingInfo = .groundContactTime }, actionIcon: "info.circle")
                .padding(.horizontal, 20)

            VStack(spacing: 16) {
                // Average GCT
                if let gct = metrics.groundContactTime {
                    HStack {
                        Text("Average GCT")
                            .font(.dripLabel(14))
                            .foregroundStyle(Color.drip.textPrimary)
                        Spacer()
                        Text(String(format: "%.0f ms", gct))
                            .font(.dripLabel(22))
                            .foregroundStyle(Color.drip.textPrimary)
                    }
                }

                // L/R breakdown
                if let leftGCT = metrics.groundContactTimeLeft,
                   let rightGCT = metrics.groundContactTimeRight
                {
                    VStack(spacing: 12) {
                        // L/R values
                        HStack(spacing: 0) {
                            VStack(spacing: 2) {
                                Text("Left")
                                    .font(.dripCaption(11))
                                    .foregroundStyle(Color.drip.textTertiary)
                                Text(String(format: "%.0f ms", leftGCT))
                                    .font(.dripLabel(18))
                                    .foregroundStyle(Color.drip.textPrimary)
                            }
                            .frame(maxWidth: .infinity)

                            VStack(spacing: 2) {
                                Text("Right")
                                    .font(.dripCaption(11))
                                    .foregroundStyle(Color.drip.textTertiary)
                                Text(String(format: "%.0f ms", rightGCT))
                                    .font(.dripLabel(18))
                                    .foregroundStyle(Color.drip.textPrimary)
                            }
                            .frame(maxWidth: .infinity)
                        }

                        // Balance bar
                        if let balance = metrics.groundContactBalance {
                            VStack(spacing: 6) {
                                GCTBalanceBar(leftPercent: balance)

                                HStack {
                                    Text(String(format: "L %.1f%%", balance))
                                        .font(.dripCaption(11))
                                        .foregroundStyle(Color.drip.textTertiary)
                                    Spacer()
                                    // Balance status badge
                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(metrics.balanceStatus.color)
                                            .frame(width: 6, height: 6)
                                        Text(balanceLabel(metrics.balanceStatus))
                                            .font(.dripCaption(11))
                                    }
                                    .foregroundStyle(metrics.balanceStatus.color)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(metrics.balanceStatus.color.opacity(0.12))
                                    .clipShape(Capsule())
                                    Spacer()
                                    Text(String(format: "R %.1f%%", 100 - balance))
                                        .font(.dripCaption(11))
                                        .foregroundStyle(Color.drip.textTertiary)
                                }
                            }
                        }
                    }
                } else if let leftGCT = metrics.groundContactTimeLeft {
                    VStack(spacing: 8) {
                        HStack {
                            Text("Left GCT")
                                .font(.dripLabel(14))
                                .foregroundStyle(Color.drip.textPrimary)
                            Spacer()
                            Text(String(format: "%.0f ms", leftGCT))
                                .font(.dripLabel(22))
                                .foregroundStyle(Color.drip.textPrimary)
                        }
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.drip.textTertiary)
                            Text("Record a right side video to see L/R balance")
                                .font(.dripCaption(11))
                                .foregroundStyle(Color.drip.textTertiary)
                        }
                    }
                } else if let rightGCT = metrics.groundContactTimeRight {
                    VStack(spacing: 8) {
                        HStack {
                            Text("Right GCT")
                                .font(.dripLabel(14))
                                .foregroundStyle(Color.drip.textPrimary)
                            Spacer()
                            Text(String(format: "%.0f ms", rightGCT))
                                .font(.dripLabel(22))
                                .foregroundStyle(Color.drip.textPrimary)
                        }
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.drip.textTertiary)
                            Text("Record a left side video to see L/R balance")
                                .font(.dripCaption(11))
                                .foregroundStyle(Color.drip.textTertiary)
                        }
                    }
                }

                Text("Typical running GCT: 200-300 ms. Balanced = close to 50/50 L/R split.")
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textTertiary)
            }
            .padding(16)
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 20)
        }
    }

    private func balanceLabel(_ status: ROMStatus) -> String {
        switch status {
        case .normal: return "Balanced"
        case .borderline: return "Slight asymmetry"
        case .atypical: return "Asymmetric"
        case .unknown: return "—"
        }
    }

    // MARK: - AI Analysis Section

    private func aiAnalysisSection(_ aiAnalysis: BiomechanicsAIAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("AI Form Analysis")
                .padding(.horizontal, 20)

            // Overall score
            if let score = aiAnalysis.overallScore {
                HStack {
                    Text("Overall Score")
                        .font(.dripLabel(15))
                        .foregroundStyle(Color.drip.textPrimary)
                    Spacer()
                    Text("\(score)/10")
                        .font(.dripLabel(24))
                        .foregroundStyle(scoreColor(score))
                }
                .padding(16)
                .background(Color.drip.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 20)
            }

            // Form assessment
            if let assessment = aiAnalysis.formAssessment {
                Text(assessment)
                    .font(.dripBody(14))
                    .foregroundStyle(Color.drip.textSecondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.drip.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 20)
            }

            // Findings
            if let findings = aiAnalysis.findings, !findings.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Findings")
                        .font(.dripLabel(14))
                        .foregroundStyle(Color.drip.textPrimary)
                        .padding(.horizontal, 20)

                    ForEach(findings) { finding in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(finding.area)
                                    .font(.dripLabel(14))
                                    .foregroundStyle(Color.drip.textPrimary)
                                Spacer()
                                Text(finding.severity.capitalized)
                                    .font(.dripCaption(11))
                                    .foregroundStyle(finding.severityColor)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(finding.severityColor.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                            Text(finding.observation)
                                .font(.dripBody(13))
                                .foregroundStyle(Color.drip.textSecondary)
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "lightbulb.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.drip.coral.opacity(0.7))
                                    .padding(.top, 2)
                                Text(finding.recommendation)
                                    .font(.dripBody(12))
                                    .foregroundStyle(Color.drip.textTertiary)
                            }
                        }
                        .padding(16)
                        .background(Color.drip.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal, 20)
                    }
                }
            }

            // Injury risk factors
            if let riskFactors = aiAnalysis.injuryRiskFactors, !riskFactors.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.drip.tired)
                        Text("Injury Risk Factors")
                            .font(.dripLabel(14))
                            .foregroundStyle(Color.drip.textPrimary)
                    }

                    ForEach(riskFactors, id: \.self) { factor in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(Color.drip.tired)
                                .frame(width: 5, height: 5)
                                .padding(.top, 6)
                            Text(factor)
                                .font(.dripBody(13))
                                .foregroundStyle(Color.drip.textSecondary)
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

            // Improvement priorities
            if let priorities = aiAnalysis.improvementPriorities, !priorities.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "target")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.drip.coral)
                        Text("Improvement Priorities")
                            .font(.dripLabel(14))
                            .foregroundStyle(Color.drip.textPrimary)
                    }

                    ForEach(priorities) { priority in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Text("#\(priority.priority)")
                                    .font(.dripLabel(13))
                                    .foregroundStyle(Color.drip.coral)
                                    .frame(width: 24)
                                Text(priority.area)
                                    .font(.dripLabel(13))
                                    .foregroundStyle(Color.drip.textPrimary)
                            }

                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "figure.strengthtraining.traditional")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.drip.positive)
                                    .padding(.top, 2)
                                Text(priority.drill)
                                    .font(.dripLabel(12))
                                    .foregroundStyle(Color.drip.positive)
                            }

                            Text(priority.explanation)
                                .font(.dripBody(12))
                                .foregroundStyle(Color.drip.textTertiary)

                            if priority.priority < priorities.count {
                                Divider()
                                    .foregroundStyle(Color.drip.textTertiary.opacity(0.2))
                            }
                        }
                    }
                }
                .padding(16)
                .background(Color.drip.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 20)
            }

            // Comparison notes
            if let comparison = aiAnalysis.comparisonNotes {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.drip.textSecondary)
                        Text("Compared to Previous")
                            .font(.dripLabel(13))
                            .foregroundStyle(Color.drip.textPrimary)
                    }
                    Text(comparison)
                        .font(.dripBody(13))
                        .foregroundStyle(Color.drip.textSecondary)
                }
                .padding(16)
                .background(Color.drip.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 20)
            }

            // Disclaimer
            if let disclaimer = aiAnalysis.disclaimer {
                Text(disclaimer)
                    .font(.dripCaption(10))
                    .foregroundStyle(Color.drip.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.top, 4)
            }
        }
    }

    private func scoreColor(_ score: Int) -> Color {
        if score >= 8 { return Color.drip.positive }
        if score >= 5 { return Color.drip.coral }
        return Color.drip.injured
    }
}

// MARK: - ROMRangeBar

struct ROMRangeBar: View {
    let min: Double
    let max: Double
    let normalMin: Double
    let normalMax: Double

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let totalRange = 180.0
            let normalStart = normalMin / totalRange * width
            let normalWidth = (normalMax - normalMin) / totalRange * width
            let actualStart = min / totalRange * width
            let actualWidth = (max - min) / totalRange * width

            ZStack(alignment: .leading) {
                // Full range background
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.drip.cardBackgroundElevated)
                    .frame(height: 6)

                // Normal range band
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.drip.positive.opacity(0.2))
                    .frame(width: normalWidth, height: 6)
                    .offset(x: normalStart)

                // Actual range bar
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.drip.coral)
                    .frame(width: Swift.max(actualWidth, 4), height: 6)
                    .offset(x: actualStart)
            }
        }
        .frame(height: 6)
    }
}

// MARK: - BiomechanicsInfoType

enum BiomechanicsInfoType: String, Identifiable {
    case footStrike
    case jointAngles
    case shankAngle
    case shoulderRotation
    case groundContactTime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .footStrike: return "Foot Strike Pattern"
        case .jointAngles: return "Joint Angles"
        case .shankAngle: return "Shank Angle"
        case .shoulderRotation: return "Shoulder Rotation"
        case .groundContactTime: return "Ground Contact Time"
        }
    }

    var description: String {
        switch self {
        case .footStrike:
            return "Foot strike pattern is estimated from the shank (shin) angle at the moment of ground contact. A large forward angle means the foot is ahead of the body, typical of heel striking. A near-vertical shank means the foot lands under the body, typical of forefoot striking. Note: this is an estimate — Vision tracks joints down to the ankle but not the foot itself."
        case .jointAngles:
            return "The angles formed at your hip and knee throughout the gait cycle. Range of motion (ROM) is the difference between max and min angles — it indicates how much each joint moves during running. Ankle ROM is not shown because Vision tracks joints only down to the ankle, not the foot."
        case .shankAngle:
            return "The angle of your shin (tibia) relative to vertical at the moment your foot contacts the ground. A shin close to vertical means your foot lands under your body. A large forward angle indicates overstriding, which increases braking forces and injury risk."
        case .shoulderRotation:
            return "The rotation of your shoulders relative to your hips in the transverse (horizontal) plane. During running, your shoulders naturally rotate opposite to your hips — this counter-rotation is efficient and helps maintain balance. Too much rotation wastes energy; too little indicates a rigid torso."
        case .groundContactTime:
            return "The time your foot spends on the ground each step (in milliseconds). Faster runners tend to have shorter GCT. L/R balance close to 50/50 indicates symmetric gait."
        }
    }
}

// MARK: - BiomechanicsInfoSheet

struct BiomechanicsInfoSheet: View {
    let type: BiomechanicsInfoType
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.drip.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Diagram
                        diagramView
                            .frame(height: 200)
                            .padding(.horizontal, 20)
                            .padding(.top, 12)

                        // Description
                        Text(type.description)
                            .font(.dripBody(14))
                            .foregroundStyle(Color.drip.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)

                        // Reference ranges
                        referenceInfo
                            .padding(.horizontal, 20)
                    }
                    .padding(.bottom, 30)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(type.title.uppercased())
                        .font(.dripCaption(12))
                        .foregroundStyle(Color.drip.textSecondary)
                        .tracking(2)
                }
            }
            .toolbarBackground(Color.drip.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    @ViewBuilder
    private var diagramView: some View {
        switch type {
        case .footStrike:
            FootStrikeDiagram()
        case .jointAngles:
            JointAnglesDiagram()
        case .shankAngle:
            ShankAngleDiagram()
        case .shoulderRotation:
            ShoulderRotationDiagram()
        case .groundContactTime:
            GCTDiagram()
        }
    }

    @ViewBuilder
    private var referenceInfo: some View {
        VStack(spacing: 8) {
            switch type {
            case .footStrike:
                referenceRow("Rearfoot (Heel)", "Shank ≥ 10° forward")
                referenceRow("Midfoot", "Shank 5°–10° forward")
                referenceRow("Forefoot", "Shank < 5° forward")
            case .jointAngles:
                referenceRow("Hip Flexion ROM", "40°-55° normal")
                referenceRow("Knee Flexion ROM", "90°-120° normal")
            case .shankAngle:
                referenceRow("< 5° past vertical", "Good — foot lands under body")
                referenceRow("5°-10° past vertical", "Mild overstriding")
                referenceRow("> 10° past vertical", "Overstriding — higher injury risk")
            case .shoulderRotation:
                referenceRow("5°-15° ROM", "Normal counter-rotation")
                referenceRow("< 3° ROM", "Too rigid — limited arm swing")
                referenceRow("> 20° ROM", "Excessive — energy waste")
            case .groundContactTime:
                referenceRow("Elite (< 200ms)", "Fast turnover, efficient")
                referenceRow("Recreational (200-300ms)", "Typical range")
                referenceRow("L/R Balance", "Within 2% = symmetric")
            }
        }
        .padding(16)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func referenceRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.dripLabel(13))
                .foregroundStyle(Color.drip.textPrimary)
            Spacer()
            Text(value)
                .font(.dripCaption(12))
                .foregroundStyle(Color.drip.textTertiary)
        }
    }
}

// MARK: - Foot Strike Diagram

private struct FootStrikeDiagram: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let groundY = h * 0.80

            // Ground line
            var groundPath = Path()
            groundPath.move(to: CGPoint(x: 10, y: groundY))
            groundPath.addLine(to: CGPoint(x: w - 10, y: groundY))
            context.stroke(groundPath, with: .color(Color.drip.textTertiary.opacity(0.3)), lineWidth: 1)

            // Three strike patterns with different shank angles
            drawShankPattern(context: context, x: w * 0.18, groundY: groundY,
                             shankDeg: 14, label: "Heel", subtitle: "≥ 10°", color: Color.drip.tired)
            drawShankPattern(context: context, x: w * 0.50, groundY: groundY,
                             shankDeg: 7, label: "Midfoot", subtitle: "5°–10°", color: Color.drip.positive)
            drawShankPattern(context: context, x: w * 0.82, groundY: groundY,
                             shankDeg: 2, label: "Forefoot", subtitle: "< 5°", color: Color.drip.coral)

            // Title
            context.draw(
                Text("Shank Angle at Initial Contact")
                    .font(.dripCaption(10))
                    .foregroundColor(Color.drip.textTertiary),
                at: CGPoint(x: w / 2, y: h * 0.06)
            )
            context.draw(
                Text("More forward = heel first · Vertical = forefoot first")
                    .font(.dripCaption(9))
                    .foregroundColor(Color.drip.textTertiary),
                at: CGPoint(x: w / 2, y: h * 0.14)
            )
        }
    }

    private func drawShankPattern(context: GraphicsContext, x: CGFloat, groundY: CGFloat,
                                  shankDeg: CGFloat, label: String, subtitle: String, color: Color) {
        let shinLength: CGFloat = 70
        let ankleY = groundY - 5
        let angleRad = shankDeg * .pi / 180

        // Knee position: shank tilted forward from ankle
        let kneePoint = CGPoint(
            x: x - sin(angleRad) * shinLength,
            y: ankleY - cos(angleRad) * shinLength
        )
        let anklePoint = CGPoint(x: x, y: ankleY)

        // Vertical reference line (dashed)
        var vertLine = Path()
        vertLine.move(to: CGPoint(x: x, y: ankleY))
        vertLine.addLine(to: CGPoint(x: x, y: ankleY - shinLength - 10))
        context.stroke(vertLine, with: .color(Color.drip.textTertiary.opacity(0.3)),
                       style: StrokeStyle(lineWidth: 1, dash: [4, 3]))

        // Shin line
        var shinPath = Path()
        shinPath.move(to: anklePoint)
        shinPath.addLine(to: kneePoint)
        context.stroke(shinPath, with: .color(color), lineWidth: 3.5)

        // Knee dot
        context.fill(
            Path(ellipseIn: CGRect(x: kneePoint.x - 4, y: kneePoint.y - 4, width: 8, height: 8)),
            with: .color(color)
        )

        // Ankle dot
        context.fill(
            Path(ellipseIn: CGRect(x: anklePoint.x - 5, y: anklePoint.y - 5, width: 10, height: 10)),
            with: .color(color)
        )

        // Angle arc
        if shankDeg > 3 {
            var arcPath = Path()
            arcPath.addArc(center: anklePoint, radius: 22,
                           startAngle: .degrees(-90),
                           endAngle: .degrees(-90 + Double(shankDeg)),
                           clockwise: false)
            context.stroke(arcPath, with: .color(color.opacity(0.6)), lineWidth: 1.5)
        }

        // Angle label
        context.draw(
            Text(subtitle).font(.dripCaption(9)).foregroundColor(color),
            at: CGPoint(x: x + 22, y: ankleY - shinLength * 0.5)
        )

        // Pattern name below ground
        context.draw(
            Text(label).font(.dripLabel(12)).foregroundColor(color),
            at: CGPoint(x: x, y: groundY + 16)
        )
    }
}

// MARK: - Joint Angles Diagram

private struct JointAnglesDiagram: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height

            // Stick figure (side view, running pose)
            let shoulder = CGPoint(x: w * 0.45, y: h * 0.15)
            let hip = CGPoint(x: w * 0.42, y: h * 0.38)
            let knee = CGPoint(x: w * 0.55, y: h * 0.58)
            let ankle = CGPoint(x: w * 0.45, y: h * 0.8)
            let head = CGPoint(x: w * 0.47, y: h * 0.06)

            // Body lines
            let bodyColor = Color.drip.textSecondary
            let joints: [(from: CGPoint, to: CGPoint)] = [
                (head, shoulder),
                (shoulder, hip),
                (hip, knee),
                (knee, ankle),
            ]
            for joint in joints {
                var path = Path()
                path.move(to: joint.from)
                path.addLine(to: joint.to)
                context.stroke(path, with: .color(bodyColor), lineWidth: 3)
            }

            // Joint dots
            let allJoints = [head, shoulder, hip, knee, ankle]
            for pt in allJoints {
                context.fill(
                    Path(ellipseIn: CGRect(x: pt.x - 5, y: pt.y - 5, width: 10, height: 10)),
                    with: .color(bodyColor)
                )
            }

            // Hip angle arc (shoulder-hip-knee) — coral
            drawAngleArc(context: context, vertex: hip, from: shoulder, to: knee,
                         radius: 28, color: Color.drip.coral, label: "Hip", labelOffset: CGPoint(x: -50, y: 0))

            // Knee angle arc (hip-knee-ankle) — positive green
            drawAngleArc(context: context, vertex: knee, from: hip, to: ankle,
                         radius: 24, color: Color.drip.positive, label: "Knee", labelOffset: CGPoint(x: 35, y: 8))

            // Ankle dot (no angle shown — Vision lacks foot/toe joints)
            context.fill(
                Path(ellipseIn: CGRect(x: ankle.x - 5, y: ankle.y - 5, width: 10, height: 10)),
                with: .color(bodyColor)
            )
        }
    }

    private func drawAngleArc(context: GraphicsContext, vertex: CGPoint, from: CGPoint, to: CGPoint,
                              radius: CGFloat, color: Color, label: String, labelOffset: CGPoint)
    {
        let angle1 = atan2(from.y - vertex.y, from.x - vertex.x)
        let angle2 = atan2(to.y - vertex.y, to.x - vertex.x)

        var arcPath = Path()
        arcPath.addArc(center: vertex, radius: radius,
                       startAngle: .radians(Double(angle1)),
                       endAngle: .radians(Double(angle2)),
                       clockwise: angle1 > angle2)
        context.stroke(arcPath, with: .color(color), lineWidth: 2.5)

        context.draw(
            Text(label)
                .font(.dripCaption(11))
                .foregroundColor(color),
            at: CGPoint(x: vertex.x + labelOffset.x, y: vertex.y + labelOffset.y)
        )
    }
}

// MARK: - Shank Angle Diagram

private struct ShankAngleDiagram: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let groundY = h * 0.85

            // Ground
            var groundPath = Path()
            groundPath.move(to: CGPoint(x: 20, y: groundY))
            groundPath.addLine(to: CGPoint(x: w - 20, y: groundY))
            context.stroke(groundPath, with: .color(Color.drip.textTertiary.opacity(0.3)), lineWidth: 1)

            // --- Good form (left side) ---
            let goodAnkle = CGPoint(x: w * 0.3, y: groundY - 5)
            let goodKnee = CGPoint(x: w * 0.3, y: groundY - 85)

            // Vertical reference line
            var vertLine = Path()
            vertLine.move(to: CGPoint(x: goodAnkle.x, y: groundY - 5))
            vertLine.addLine(to: CGPoint(x: goodAnkle.x, y: groundY - 100))
            context.stroke(vertLine, with: .color(Color.drip.textTertiary.opacity(0.4)),
                           style: StrokeStyle(lineWidth: 1, dash: [5, 4]))

            // Shin
            var goodShin = Path()
            goodShin.move(to: goodAnkle)
            goodShin.addLine(to: goodKnee)
            context.stroke(goodShin, with: .color(Color.drip.positive), lineWidth: 4)

            // Joint dots
            for pt in [goodAnkle, goodKnee] {
                context.fill(
                    Path(ellipseIn: CGRect(x: pt.x - 4, y: pt.y - 4, width: 8, height: 8)),
                    with: .color(Color.drip.positive)
                )
            }

            context.draw(
                Text("Good")
                    .font(.dripLabel(13))
                    .foregroundColor(Color.drip.positive),
                at: CGPoint(x: goodAnkle.x, y: groundY + 16)
            )
            context.draw(
                Text("~0°")
                    .font(.dripCaption(11))
                    .foregroundColor(Color.drip.positive),
                at: CGPoint(x: goodAnkle.x + 30, y: groundY - 60)
            )

            // --- Overstriding (right side) ---
            let badAnkle = CGPoint(x: w * 0.7, y: groundY - 5)
            let badKnee = CGPoint(x: w * 0.7 - 25, y: groundY - 80)

            // Vertical reference
            var vertLine2 = Path()
            vertLine2.move(to: CGPoint(x: badAnkle.x, y: groundY - 5))
            vertLine2.addLine(to: CGPoint(x: badAnkle.x, y: groundY - 100))
            context.stroke(vertLine2, with: .color(Color.drip.textTertiary.opacity(0.4)),
                           style: StrokeStyle(lineWidth: 1, dash: [5, 4]))

            // Shin (angled forward)
            var badShin = Path()
            badShin.move(to: badAnkle)
            badShin.addLine(to: badKnee)
            context.stroke(badShin, with: .color(Color.drip.injured), lineWidth: 4)

            for pt in [badAnkle, badKnee] {
                context.fill(
                    Path(ellipseIn: CGRect(x: pt.x - 4, y: pt.y - 4, width: 8, height: 8)),
                    with: .color(Color.drip.injured)
                )
            }

            // Angle arc
            let vertAngle = -CGFloat.pi / 2 // straight up
            let shinAngle = atan2(badKnee.y - badAnkle.y, badKnee.x - badAnkle.x)
            var arcPath = Path()
            arcPath.addArc(center: badAnkle, radius: 30,
                           startAngle: .radians(Double(vertAngle)),
                           endAngle: .radians(Double(shinAngle)),
                           clockwise: true)
            context.stroke(arcPath, with: .color(Color.drip.injured), lineWidth: 2)

            context.draw(
                Text("Overstriding")
                    .font(.dripLabel(13))
                    .foregroundColor(Color.drip.injured),
                at: CGPoint(x: badAnkle.x, y: groundY + 16)
            )
            context.draw(
                Text("> 10°")
                    .font(.dripCaption(11))
                    .foregroundColor(Color.drip.injured),
                at: CGPoint(x: badAnkle.x + 35, y: groundY - 55)
            )
        }
    }
}

// MARK: - Shoulder Rotation Diagram

private struct ShoulderRotationDiagram: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height

            // Top-down view of torso showing counter-rotation
            let centerX = w / 2
            let centerY = h * 0.45

            // --- Hip line (horizontal baseline) ---
            let hipHalfWidth: CGFloat = 40
            let hipLeft = CGPoint(x: centerX - hipHalfWidth, y: centerY + 30)
            let hipRight = CGPoint(x: centerX + hipHalfWidth, y: centerY + 30)

            var hipPath = Path()
            hipPath.move(to: hipLeft)
            hipPath.addLine(to: hipRight)
            context.stroke(hipPath, with: .color(Color.drip.textSecondary), lineWidth: 4)

            // Hip joint dots
            for pt in [hipLeft, hipRight] {
                context.fill(
                    Path(ellipseIn: CGRect(x: pt.x - 5, y: pt.y - 5, width: 10, height: 10)),
                    with: .color(Color.drip.textSecondary)
                )
            }

            context.draw(
                Text("Hips")
                    .font(.dripCaption(11))
                    .foregroundColor(Color.drip.textSecondary),
                at: CGPoint(x: centerX + hipHalfWidth + 28, y: centerY + 30)
            )

            // --- Shoulder line (rotated relative to hips) ---
            let shoulderHalfWidth: CGFloat = 50
            let rotationAngle: CGFloat = 15 * .pi / 180 // 15° counter-rotation

            let shoulderLeft = CGPoint(
                x: centerX - shoulderHalfWidth * cos(rotationAngle),
                y: centerY - 30 - shoulderHalfWidth * sin(rotationAngle)
            )
            let shoulderRight = CGPoint(
                x: centerX + shoulderHalfWidth * cos(rotationAngle),
                y: centerY - 30 + shoulderHalfWidth * sin(rotationAngle)
            )

            var shoulderPath = Path()
            shoulderPath.move(to: shoulderLeft)
            shoulderPath.addLine(to: shoulderRight)
            context.stroke(shoulderPath, with: .color(Color.drip.coral), lineWidth: 4)

            // Shoulder dots
            for pt in [shoulderLeft, shoulderRight] {
                context.fill(
                    Path(ellipseIn: CGRect(x: pt.x - 5, y: pt.y - 5, width: 10, height: 10)),
                    with: .color(Color.drip.coral)
                )
            }

            context.draw(
                Text("Shoulders")
                    .font(.dripCaption(11))
                    .foregroundColor(Color.drip.coral),
                at: CGPoint(x: centerX + shoulderHalfWidth + 38, y: centerY - 30)
            )

            // Spine / center line
            var spinePath = Path()
            spinePath.move(to: CGPoint(x: centerX, y: centerY - 30))
            spinePath.addLine(to: CGPoint(x: centerX, y: centerY + 30))
            context.stroke(spinePath, with: .color(Color.drip.textTertiary.opacity(0.5)),
                           style: StrokeStyle(lineWidth: 2, dash: [4, 3]))

            // Rotation arc
            let arcRadius: CGFloat = 55
            var arcPath = Path()
            arcPath.addArc(center: CGPoint(x: centerX + arcRadius, y: centerY),
                           radius: 15,
                           startAngle: .degrees(-90),
                           endAngle: .degrees(-90 + 15),
                           clockwise: false)
            context.stroke(arcPath, with: .color(Color.drip.coral), lineWidth: 2)

            // Top-down label
            context.draw(
                Text("Top-Down View")
                    .font(.dripCaption(10))
                    .foregroundColor(Color.drip.textTertiary),
                at: CGPoint(x: centerX, y: h * 0.08)
            )

            // Counter-rotation arrow labels
            context.draw(
                Text("Counter-rotation")
                    .font(.dripLabel(12))
                    .foregroundColor(Color.drip.coral),
                at: CGPoint(x: centerX, y: h * 0.85)
            )
            context.draw(
                Text("Shoulders twist opposite to hips")
                    .font(.dripCaption(10))
                    .foregroundColor(Color.drip.textTertiary),
                at: CGPoint(x: centerX, y: h * 0.93)
            )
        }
    }
}

// MARK: - GCT Diagram

private struct GCTDiagram: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height

            let barY = h * 0.35
            let barHeight: CGFloat = 40
            let margin: CGFloat = 30
            let barWidth = w - margin * 2

            // Title
            context.draw(
                Text("One Stride Cycle")
                    .font(.dripCaption(11))
                    .foregroundColor(Color.drip.textSecondary),
                at: CGPoint(x: w / 2, y: h * 0.1)
            )

            // Stance phase (60% of cycle)
            let stanceWidth = barWidth * 0.6
            let stanceRect = CGRect(x: margin, y: barY, width: stanceWidth, height: barHeight)
            var stancePath = Path()
            stancePath.addRoundedRect(in: stanceRect, cornerSize: CGSize(width: 6, height: 6))
            context.fill(stancePath, with: .color(Color.drip.coral.opacity(0.3)))
            context.stroke(stancePath, with: .color(Color.drip.coral), lineWidth: 1.5)

            context.draw(
                Text("Stance (GCT)")
                    .font(.dripLabel(12))
                    .foregroundColor(Color.drip.coral),
                at: CGPoint(x: margin + stanceWidth / 2, y: barY + barHeight / 2)
            )

            // Flight/Swing phase (40%)
            let flightWidth = barWidth * 0.4
            let flightRect = CGRect(x: margin + stanceWidth + 4, y: barY, width: flightWidth - 4, height: barHeight)
            var flightPath = Path()
            flightPath.addRoundedRect(in: flightRect, cornerSize: CGSize(width: 6, height: 6))
            context.fill(flightPath, with: .color(Color.drip.positive.opacity(0.2)))
            context.stroke(flightPath, with: .color(Color.drip.positive), lineWidth: 1.5)

            context.draw(
                Text("Flight")
                    .font(.dripLabel(12))
                    .foregroundColor(Color.drip.positive),
                at: CGPoint(x: margin + stanceWidth + flightWidth / 2, y: barY + barHeight / 2)
            )

            // Foot icons below
            // Stance — foot on ground
            context.draw(
                Text("🦶")
                    .font(.system(size: 20)),
                at: CGPoint(x: margin + stanceWidth / 2, y: barY + barHeight + 25)
            )
            context.draw(
                Text("Foot on ground")
                    .font(.dripCaption(10))
                    .foregroundColor(Color.drip.textTertiary),
                at: CGPoint(x: margin + stanceWidth / 2, y: barY + barHeight + 45)
            )

            // Flight — foot in air
            context.draw(
                Text("Foot in air")
                    .font(.dripCaption(10))
                    .foregroundColor(Color.drip.textTertiary),
                at: CGPoint(x: margin + stanceWidth + flightWidth / 2, y: barY + barHeight + 45)
            )

            // Balance section
            let balanceY = h * 0.82
            context.draw(
                Text("L/R Balance: how evenly you load each leg")
                    .font(.dripCaption(11))
                    .foregroundColor(Color.drip.textSecondary),
                at: CGPoint(x: w / 2, y: balanceY)
            )

            // Mini balance bar
            let miniBarWidth: CGFloat = 120
            let miniBarX = (w - miniBarWidth) / 2
            let leftRect = CGRect(x: miniBarX, y: balanceY + 12, width: miniBarWidth / 2 - 1, height: 10)
            let rightRect = CGRect(x: miniBarX + miniBarWidth / 2 + 1, y: balanceY + 12, width: miniBarWidth / 2 - 1, height: 10)

            context.fill(Path(roundedRect: leftRect, cornerRadius: 3), with: .color(Color.drip.coral.opacity(0.5)))
            context.fill(Path(roundedRect: rightRect, cornerRadius: 3), with: .color(Color.drip.coral.opacity(0.3)))

            context.draw(
                Text("L").font(.dripCaption(9)).foregroundColor(Color.drip.textTertiary),
                at: CGPoint(x: miniBarX - 8, y: balanceY + 17)
            )
            context.draw(
                Text("R").font(.dripCaption(9)).foregroundColor(Color.drip.textTertiary),
                at: CGPoint(x: miniBarX + miniBarWidth + 8, y: balanceY + 17)
            )
        }
    }
}

// MARK: - GCTBalanceBar

struct GCTBalanceBar: View {
    /// Left side percentage (0-100). 50 = perfectly balanced.
    let leftPercent: Double

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let leftWidth = max(width * leftPercent / 100, 4)
            let rightWidth = max(width - leftWidth, 4)
            let balanceStatus = balanceColor

            HStack(spacing: 2) {
                // Left bar
                RoundedRectangle(cornerRadius: 4)
                    .fill(balanceStatus.opacity(0.7))
                    .frame(width: leftWidth, height: 14)

                // Right bar
                RoundedRectangle(cornerRadius: 4)
                    .fill(balanceStatus.opacity(0.4))
                    .frame(width: rightWidth, height: 14)
            }

            // Center marker (50% line)
            Rectangle()
                .fill(Color.drip.textTertiary.opacity(0.4))
                .frame(width: 1, height: 20)
                .position(x: width / 2, y: 7)
        }
        .frame(height: 20)
    }

    private var balanceColor: Color {
        let deviation = abs(leftPercent - 50)
        if deviation < 2 { return Color.drip.positive }
        if deviation < 5 { return Color.drip.tired }
        return Color.drip.injured
    }
}

// MARK: - Foot Strike Overlay View

/// Shows a video frame at initial contact with shin + estimated foot angle overlay.
struct FootStrikeOverlayView: View {
    let videoURL: URL
    let contactFrame: FootStrikeContactFrame
    let pattern: FootStrikePattern

    @State private var frameImage: UIImage?
    @State private var isLoading = true

    var body: some View {
        ZStack {
            if let image = frameImage {
                overlayContent(image: image)
            } else if isLoading {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.drip.cardBackgroundElevated)
                    .frame(height: 220)
                    .overlay(ProgressView().tint(Color.drip.coral))
            }
        }
        .task {
            frameImage = await extractFrame()
            isLoading = false
        }
    }

    private func overlayContent(image: UIImage) -> some View {
        GeometryReader { geo in
            let size = fitSize(imageSize: image.size, in: geo.size)

            ZStack {
                // Video frame
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size.width, height: size.height)

                // Overlay: shin line + foot angle
                Canvas { context, canvasSize in
                    drawOverlay(context: context, size: size)
                }
                .frame(width: size.width, height: size.height)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 260)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func drawOverlay(context: GraphicsContext, size: CGSize) {
        let w = size.width
        let h = size.height

        // Convert normalized coords (bottom-left origin) to SwiftUI (top-left origin)
        let hip = CGPoint(x: CGFloat(contactFrame.hipImageX) * w,
                          y: (1 - CGFloat(contactFrame.hipImageY)) * h)
        let knee = CGPoint(x: CGFloat(contactFrame.kneeImageX) * w,
                           y: (1 - CGFloat(contactFrame.kneeImageY)) * h)
        let ankle = CGPoint(x: CGFloat(contactFrame.ankleImageX) * w,
                            y: (1 - CGFloat(contactFrame.ankleImageY)) * h)

        let heel: CGPoint? = contactFrame.heelImageX.flatMap { hx in
            contactFrame.heelImageY.map { hy in
                CGPoint(x: CGFloat(hx) * w, y: (1 - CGFloat(hy)) * h)
            }
        }
        let footIndex: CGPoint? = contactFrame.footIndexImageX.flatMap { fx in
            contactFrame.footIndexImageY.map { fy in
                CGPoint(x: CGFloat(fx) * w, y: (1 - CGFloat(fy)) * h)
            }
        }

        // Draw thigh (hip → knee)
        drawSegment(context: context, from: hip, to: knee,
                    color: Color.drip.textSecondary.opacity(0.6))

        // Draw shin (knee → ankle)
        drawSegment(context: context, from: knee, to: ankle, color: .white)

        // Draw foot segments if available (heel → ankle → foot index)
        if let heel {
            drawSegment(context: context, from: ankle, to: heel, color: .white, lineWidth: 2.5)
        }
        if let footIndex {
            drawSegment(context: context, from: ankle, to: footIndex, color: .white, lineWidth: 2.5)
        }
        if let heel, let footIndex {
            drawSegment(context: context, from: heel, to: footIndex,
                        color: pattern.color.opacity(0.7), lineWidth: 2)
        }

        // Joint dots — hip, knee
        for pt in [hip, knee] {
            context.fill(
                Path(ellipseIn: CGRect(x: pt.x - 5, y: pt.y - 5, width: 10, height: 10)),
                with: .color(.white)
            )
        }

        // Foot landmark dots (heel + ball of foot) or ankle dot
        if let heel, let footIndex {
            // Heel dot
            context.fill(
                Path(ellipseIn: CGRect(x: heel.x - 7, y: heel.y - 7, width: 14, height: 14)),
                with: .color(pattern == .rearfoot ? pattern.color : .white)
            )
            context.fill(
                Path(ellipseIn: CGRect(x: heel.x - 3, y: heel.y - 3, width: 6, height: 6)),
                with: .color(.white)
            )
            // Foot index dot
            context.fill(
                Path(ellipseIn: CGRect(x: footIndex.x - 7, y: footIndex.y - 7, width: 14, height: 14)),
                with: .color(pattern == .forefoot ? pattern.color : .white)
            )
            context.fill(
                Path(ellipseIn: CGRect(x: footIndex.x - 3, y: footIndex.y - 3, width: 6, height: 6)),
                with: .color(.white)
            )
            // Ankle dot (smaller, secondary)
            context.fill(
                Path(ellipseIn: CGRect(x: ankle.x - 4, y: ankle.y - 4, width: 8, height: 8)),
                with: .color(.white.opacity(0.7))
            )

            // Labels
            let labelAnchor = pattern == .rearfoot ? heel : footIndex
            context.draw(
                Text(pattern.displayName)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(pattern.color),
                at: CGPoint(x: labelAnchor.x + 30, y: labelAnchor.y - 12)
            )
            context.draw(
                Text("Initial Contact")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.8)),
                at: CGPoint(x: labelAnchor.x + 30, y: labelAnchor.y + 6)
            )
        } else {
            // Fallback: highlight ankle (Vision — no foot landmarks)
            context.fill(
                Path(ellipseIn: CGRect(x: ankle.x - 8, y: ankle.y - 8, width: 16, height: 16)),
                with: .color(pattern.color)
            )
            context.fill(
                Path(ellipseIn: CGRect(x: ankle.x - 4, y: ankle.y - 4, width: 8, height: 8)),
                with: .color(.white)
            )

            if let shank = contactFrame.shankAngle {
                context.draw(
                    Text(String(format: "%.0f°", shank))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(pattern.color),
                    at: CGPoint(x: ankle.x + 30, y: ankle.y - 12)
                )
            }
            context.draw(
                Text("Initial Contact")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.8)),
                at: CGPoint(x: ankle.x + 30, y: ankle.y + 6)
            )
        }

        // Pattern label at top
        context.draw(
            Text(pattern.displayName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white),
            at: CGPoint(x: w * 0.5, y: 18)
        )
    }

    private func drawSegment(context: GraphicsContext, from: CGPoint, to: CGPoint,
                             color: Color, lineWidth: CGFloat = 3) {
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        context.stroke(path, with: .color(color), lineWidth: lineWidth)
    }

    private func fitSize(imageSize: CGSize, in containerSize: CGSize) -> CGSize {
        let aspectRatio = imageSize.width / imageSize.height
        if containerSize.width / containerSize.height > aspectRatio {
            let h = containerSize.height
            return CGSize(width: h * aspectRatio, height: h)
        } else {
            let w = containerSize.width
            return CGSize(width: w, height: w / aspectRatio)
        }
    }

    private func extractFrame() async -> UIImage? {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.05, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.05, preferredTimescale: 600)

        let time = CMTime(seconds: contactFrame.timestamp, preferredTimescale: 600)
        do {
            let (cgImage, _) = try await generator.image(at: time)
            return UIImage(cgImage: cgImage)
        } catch {
            return nil
        }
    }
}
