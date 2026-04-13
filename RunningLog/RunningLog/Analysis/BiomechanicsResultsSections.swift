//
//  BiomechanicsResultsSections.swift
//  RunningLog
//
//  Section views for BiomechanicsResultsView — joint angles,
//  shank angle, shoulder rotation, gait metrics, and AI analysis.
//

import SwiftUI

// MARK: - BiomechanicsResultsView Sections

extension BiomechanicsResultsView {

    // MARK: - Joint Angles Section

    func jointAnglesSection(_ angles: JointAnglesSummary) -> some View {
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

    func jointAngleCard(
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

    func angleStat(label: String, value: Double) -> some View {
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

    func shankAngleSection(left: ShankAngleData, right: ShankAngleData) -> some View {
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

    func shankAngleSection(shank: ShankAngleData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Shank Angle (Overstriding)", action: { showingInfo = .shankAngle }, actionIcon: "info.circle")
                .padding(.horizontal, 20)

            shankCard(data: shank, side: "")
                .padding(.horizontal, 20)
        }
    }

    func shankCard(data: ShankAngleData, side: String) -> some View {
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

    func shoulderRotationSection(_ data: ShoulderRotationData) -> some View {
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

    func gaitMetricsSection(_ metrics: GaitMetrics) -> some View {
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

    func balanceLabel(_ status: ROMStatus) -> String {
        switch status {
        case .normal: return "Balanced"
        case .borderline: return "Slight asymmetry"
        case .atypical: return "Asymmetric"
        case .unknown: return "—"
        }
    }

    // MARK: - AI Analysis Section

    func aiAnalysisSection(_ aiAnalysis: BiomechanicsAIAnalysis) -> some View {
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

    func scoreColor(_ score: Int) -> Color {
        if score >= 8 { return Color.drip.positive }
        if score >= 5 { return Color.drip.coral }
        return Color.drip.injured
    }
}
