//
//  BiomechanicsResultsComponents.swift
//  RunningLog
//
//  Helper views for biomechanics results — range bars, info sheets,
//  diagrams, balance bars, and foot strike video overlay.
//

import AVFoundation
import SwiftUI

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
