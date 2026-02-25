//
//  BiomechanicsCalculator.swift
//  RunningLog
//
//  Pure computation for joint angles, range of motion, foot strike
//  classification, and shank angle analysis from 3D pose data.
//

import Foundation
import os
import simd

enum BiomechanicsCalculator {

    // MARK: - Core Angle Calculation

    /// Calculate angle at joint B formed by segments A→B and B→C.
    /// Returns angle in degrees (0-180).
    static func jointAngle(
        pointA: simd_float3,
        pointB: simd_float3,
        pointC: simd_float3
    ) -> Double {
        let vectorBA = pointA - pointB
        let vectorBC = pointC - pointB
        let magnitudeBA = simd_length(vectorBA)
        let magnitudeBC = simd_length(vectorBC)

        guard magnitudeBA > 0, magnitudeBC > 0 else { return 0 }

        let cosAngle = simd_dot(vectorBA, vectorBC) / (magnitudeBA * magnitudeBC)
        let clamped = max(-1.0, min(1.0, cosAngle))
        return Double(acos(clamped)) * 180.0 / .pi
    }

    // MARK: - Joint-Specific Angles

    /// Hip flexion angle: shoulder → hip → knee
    static func hipFlexion(frame: PoseFrame, side: String) -> Double? {
        guard let shoulder = frame.jointPosition(named: "\(side)Shoulder"),
              let hip = frame.jointPosition(named: "\(side)Hip"),
              let knee = frame.jointPosition(named: "\(side)Knee")
        else { return nil }
        return jointAngle(pointA: shoulder, pointB: hip, pointC: knee)
    }

    /// Knee flexion angle: hip → knee → ankle
    static func kneeFlexion(frame: PoseFrame, side: String) -> Double? {
        guard let hip = frame.jointPosition(named: "\(side)Hip"),
              let knee = frame.jointPosition(named: "\(side)Knee"),
              let ankle = frame.jointPosition(named: "\(side)Ankle")
        else { return nil }
        return jointAngle(pointA: hip, pointB: knee, pointC: ankle)
    }

    // MARK: - Shoulder Rotation (Transverse Plane)

    /// Shoulder-hip counter-rotation angle in the transverse (horizontal) plane.
    /// Projects the shoulder line (L shoulder → R shoulder) and hip line (L hip → R hip)
    /// onto the XZ plane, then measures the angle between them.
    /// Normal running produces 5-15° of counter-rotation per stride.
    static func shoulderRotation(frame: PoseFrame) -> Double? {
        guard let leftShoulder = frame.jointPosition(named: "leftShoulder"),
              let rightShoulder = frame.jointPosition(named: "rightShoulder"),
              let leftHip = frame.jointPosition(named: "leftHip"),
              let rightHip = frame.jointPosition(named: "rightHip")
        else { return nil }

        // Project to horizontal plane (XZ, zero out Y)
        let shoulderDir = simd_float2(rightShoulder.x - leftShoulder.x, rightShoulder.z - leftShoulder.z)
        let hipDir = simd_float2(rightHip.x - leftHip.x, rightHip.z - leftHip.z)

        let shoulderLen = simd_length(shoulderDir)
        let hipLen = simd_length(hipDir)
        guard shoulderLen > 0, hipLen > 0 else { return nil }

        let cosAngle = simd_dot(shoulderDir, hipDir) / (shoulderLen * hipLen)
        let clamped = max(-1.0, min(1.0, cosAngle))
        return Double(acos(clamped)) * 180.0 / .pi
    }

    /// Compute shoulder rotation summary across all frames.
    static func computeShoulderRotation(frames: [PoseFrame]) -> ShoulderRotationData? {
        let angles: [Double] = frames.compactMap { shoulderRotation(frame: $0) }

        // Require at least 40% coverage
        let coverageRatio = Double(angles.count) / Double(max(frames.count, 1))
        guard angles.count >= 5, coverageRatio >= 0.4 else { return nil }

        let mean = angles.reduce(0, +) / Double(angles.count)
        let peak = angles.max() ?? 0
        let minAngle = angles.min() ?? 0
        let rom = peak - minAngle

        return ShoulderRotationData(
            meanRotation: round(mean * 10) / 10,
            peakRotation: round(peak * 10) / 10,
            rangeOfMotion: round(rom * 10) / 10,
            anglTimeSeries: angles
        )
    }

    // MARK: - Shank Angle (Tibial Inclination)

    /// Shank angle relative to vertical at a given frame.
    /// Positive = shin tilted forward of vertical (overstriding).
    /// Negative = shin tilted backward of vertical.
    /// Near zero = shin close to vertical at contact (ideal).
    ///
    /// `runDirection` is the forward direction inferred from overall body movement.
    /// Use `inferRunningDirection(frames:)` to compute it once for the whole clip.
    static func shankAngle(frame: PoseFrame, side: String, runDirection: simd_float3? = nil) -> Double? {
        guard let knee = frame.jointPosition(named: "\(side)Knee"),
              let ankle = frame.jointPosition(named: "\(side)Ankle")
        else { return nil }

        let shankVector = knee - ankle // ankle to knee direction
        let vertical = simd_float3(0, 1, 0)

        let shankLength = simd_length(shankVector)
        guard shankLength > 0 else { return nil }

        let cosAngle = simd_dot(simd_normalize(shankVector), vertical)
        let angleFromVertical = Double(acos(max(-1, min(1, cosAngle)))) * 180.0 / .pi

        // Determine sign: positive if ankle is ahead of knee (overstriding).
        // shankVector = knee - ankle, so when ankle is ahead its horizontal component
        // points BACKWARD (opposite to forward) → dot < 0 → positive sign.
        let forward = runDirection ?? simd_float3(1, 0, 0)
        let shankHorizontal = simd_float3(shankVector.x, 0, shankVector.z)
        let sign: Double = simd_dot(shankHorizontal, forward) > 0 ? -1.0 : 1.0
        return sign * angleFromVertical
    }

    /// Infer the forward running direction from ankle oscillation.
    ///
    /// Vision 3D positions are root-relative (hip ≈ origin), so root displacement
    /// is always ~0. Instead, we use the fact that the ankle oscillates forward and
    /// backward relative to the hip during each gait cycle. PCA on the ankle's
    /// horizontal (XZ) positions gives the forward-backward axis, and the correlation
    /// with vertical position determines the sign (ankle is forward when low = contact).
    static func inferRunningDirection(frames: [PoseFrame]) -> simd_float3? {
        // Collect ankle positions — prefer left, fall back to right
        var ankleData: [(x: Float, y: Float, z: Float)] = frames.compactMap { frame in
            guard let ankle = frame.jointPosition(named: "leftAnkle") else { return nil }
            return (ankle.x, ankle.y, ankle.z)
        }
        if ankleData.count < 10 {
            ankleData = frames.compactMap { frame in
                guard let ankle = frame.jointPosition(named: "rightAnkle") else { return nil }
                return (ankle.x, ankle.y, ankle.z)
            }
        }
        guard ankleData.count >= 10 else { return nil }

        let n = Float(ankleData.count)
        let meanX = ankleData.map(\.x).reduce(0, +) / n
        let meanY = ankleData.map(\.y).reduce(0, +) / n
        let meanZ = ankleData.map(\.z).reduce(0, +) / n

        // PCA on horizontal (XZ) plane + correlation with Y for sign
        var cxx: Float = 0, cxz: Float = 0, czz: Float = 0
        var covXY: Float = 0, covZY: Float = 0
        for d in ankleData {
            let dx = d.x - meanX
            let dy = d.y - meanY
            let dz = d.z - meanZ
            cxx += dx * dx
            cxz += dx * dz
            czz += dz * dz
            covXY += dx * dy
            covZY += dz * dy
        }
        cxx /= n; cxz /= n; czz /= n; covXY /= n; covZY /= n

        let totalVariance = cxx + czz
        guard totalVariance > 0.0001 else { return nil }

        // Principal eigenvector of 2x2 covariance matrix [[cxx, cxz], [cxz, czz]]
        let diff = cxx - czz
        let discriminant = sqrt(diff * diff + 4 * cxz * cxz)

        var dir: simd_float2
        if abs(cxz) > 0.0001 {
            let lambda1 = (cxx + czz + discriminant) / 2
            dir = simd_float2(cxz, lambda1 - cxx)
        } else if cxx >= czz {
            dir = simd_float2(1, 0)
        } else {
            dir = simd_float2(0, 1)
        }

        let dirLen = simd_length(dir)
        guard dirLen > 0 else { return nil }
        dir = dir / dirLen

        // Determine forward sign: at initial contact (low Y), the ankle is at its
        // most FORWARD position → negative correlation between forward-axis projection
        // and Y. If correlation is positive, flip the direction.
        let corrProjection = covXY * dir.x + covZY * dir.y
        if corrProjection > 0 {
            dir = -dir
        }

        return simd_float3(dir.x, 0, dir.y)
    }

    // MARK: - Foot Strike Classification

    /// Check whether frames contain heel + foot index landmarks (MediaPipe).
    private static func hasFootLandmarks(_ frames: [PoseFrame], side: String) -> Bool {
        // Check a few frames — if any have heel data, MediaPipe is active
        let sample = frames.prefix(5)
        return sample.contains { $0.jointPosition(named: "\(side)Heel") != nil }
    }

    /// Heel-to-forefoot Y difference at a frame. Negative = heel is lower.
    /// Only available with MediaPipe landmarks.
    private static func heelVsForefootDiff(frame: PoseFrame, side: String) -> Double? {
        guard let heel = frame.jointPosition(named: "\(side)Heel"),
              let footIdx = frame.jointPosition(named: "\(side)FootIndex")
        else { return nil }
        // In our coordinate system, y-up: lower y = closer to ground.
        // Difference = heel.y - footIndex.y
        // Negative → heel is lower → heel strike
        // Positive → forefoot is lower → forefoot strike
        return Double(heel.y - footIdx.y)
    }

    /// Classify foot strike from heel vs. forefoot Y difference.
    private static func patternFromFootDiff(_ diff: Double) -> FootStrikePattern {
        // Threshold in meters — heel ~2cm below forefoot = clear rearfoot
        if diff < -0.015 {
            return .rearfoot
        } else if diff > 0.015 {
            return .forefoot
        } else {
            return .midfoot
        }
    }

    /// Classify foot strike pattern using the best available method.
    /// When MediaPipe heel + foot index landmarks are present, compares their
    /// Y positions at contact (direct measurement). Falls back to shank angle
    /// when only Vision joints are available (no foot landmarks).
    static func classifyFootStrike(frames: [PoseFrame], side: String) -> FootStrikeAnalysis? {
        let runDir = inferRunningDirection(frames: frames)
        let contactFrames = detectInitialContactFrames(frames: frames, side: side)
        guard !contactFrames.isEmpty else { return nil }

        let useFootLandmarks = hasFootLandmarks(frames, side: side)

        if useFootLandmarks {
            return classifyWithFootLandmarks(
                contactFrames: contactFrames, allFrames: frames,
                side: side, runDirection: runDir
            )
        } else {
            return classifyWithShankAngle(
                contactFrames: contactFrames, allFrames: frames,
                side: side, runDirection: runDir
            )
        }
    }

    /// Direct foot strike classification using heel and foot index positions.
    private static func classifyWithFootLandmarks(
        contactFrames: [PoseFrame], allFrames: [PoseFrame],
        side: String, runDirection: simd_float3?
    ) -> FootStrikeAnalysis? {
        let diffs = contactFrames.compactMap { heelVsForefootDiff(frame: $0, side: side) }
        guard !diffs.isEmpty else { return nil }

        let avgDiff = diffs.reduce(0, +) / Double(diffs.count)
        let pattern = patternFromFootDiff(avgDiff)

        // Also compute shank angle for supplementary data
        let shankAngles = contactFrames.compactMap { shankAngle(frame: $0, side: side, runDirection: runDirection) }
        let avgShank = shankAngles.isEmpty ? nil : shankAngles.reduce(0, +) / Double(shankAngles.count)

        Log.biomechanics.info("""
        FootStrike [MediaPipe \(side)]: \(diffs.count) contacts, \
        heel-forefoot diffs: \(diffs.map { String(format: "%.3f", $0) })m, \
        avg: \(String(format: "%.3f", avgDiff))m → \(pattern.rawValue)
        """)

        // Confidence: consistency of the foot diff + sample size
        let stdDev = standardDeviation(diffs)
        let consistencyScore = max(0.0, 1.0 - (stdDev / 0.03)) // 3cm std dev = 0 consistency
        let sampleScore = min(1.0, Double(diffs.count) / 3.0)
        let confidence = max(0.5, min(0.95, (consistencyScore * 0.6 + sampleScore * 0.4)))

        let contactDetail = buildContactFrameDetail(
            contactFrames: contactFrames, side: side,
            runDirection: runDirection, targetShank: avgShank ?? 0
        )

        return FootStrikeAnalysis(
            pattern: pattern,
            confidence: confidence,
            ankleAngleAtContact: nil,
            shankAngleAtContact: avgShank.map { round($0 * 10) / 10 },
            heelVsForefoot: round(avgDiff * 1000) / 1000, // meters, 3 decimal places
            frameIndices: contactFrames.map { $0.frameIndex },
            contactFrameDetail: contactDetail
        )
    }

    /// Fallback: classify using shank angle (Vision framework — no foot joints).
    private static func classifyWithShankAngle(
        contactFrames: [PoseFrame], allFrames: [PoseFrame],
        side: String, runDirection: simd_float3?
    ) -> FootStrikeAnalysis? {
        let shankAngles = contactFrames.compactMap { shankAngle(frame: $0, side: side, runDirection: runDirection) }
        guard !shankAngles.isEmpty else { return nil }

        let avgShank = shankAngles.reduce(0, +) / Double(shankAngles.count)

        Log.biomechanics.info("""
        FootStrike [Vision \(side)]: \(shankAngles.count) contacts, \
        shank angles: \(shankAngles.map { String(format: "%.1f", $0) }), \
        avg: \(String(format: "%.1f", avgShank))°
        """)

        let pattern: FootStrikePattern
        if avgShank >= 10 {
            pattern = .rearfoot
        } else if avgShank >= 5 {
            pattern = .midfoot
        } else {
            pattern = .forefoot
        }

        let stdDev = standardDeviation(shankAngles)
        let consistencyScore = max(0.0, 1.0 - (stdDev / 10.0))
        let sampleScore = min(1.0, Double(shankAngles.count) / 4.0)
        let confidence = max(0.4, min(0.95, (consistencyScore * 0.7 + sampleScore * 0.3)))

        let contactDetail = buildContactFrameDetail(
            contactFrames: contactFrames, side: side,
            runDirection: runDirection, targetShank: avgShank
        )

        return FootStrikeAnalysis(
            pattern: pattern,
            confidence: confidence,
            ankleAngleAtContact: nil,
            shankAngleAtContact: round(avgShank * 10) / 10,
            heelVsForefoot: nil,
            frameIndices: contactFrames.map { $0.frameIndex },
            contactFrameDetail: contactDetail
        )
    }

    // MARK: - Two-Pass Refined Foot Strike

    /// Get approximate timestamps of ground contacts from coarse-pass frames.
    static func contactTimestamps(frames: [PoseFrame], side: String) -> [Double] {
        detectInitialContactFrames(frames: frames, side: side).map { $0.timestamp }
    }

    /// Determine which side to analyze based on camera angle and available data.
    static func footStrikeSide(viewAngle: ViewAngle, frames: [PoseFrame]) -> String {
        switch viewAngle {
        case .sagittalLeft: return "left"
        case .sagittalRight: return "right"
        case .frontal, .posterior:
            let leftCount = contactTimestamps(frames: frames, side: "left").count
            let rightCount = contactTimestamps(frames: frames, side: "right").count
            return leftCount >= rightCount ? "left" : "right"
        }
    }

    /// Refined foot strike classification using dense (native fps) frames around contacts.
    /// Uses heel + foot index landmarks (MediaPipe) when available.
    static func classifyFootStrikeRefined(
        coarseFrames: [PoseFrame],
        refinedWindows: [[PoseFrame]],
        side: String
    ) -> FootStrikeAnalysis? {
        let runDir = inferRunningDirection(frames: coarseFrames)
        guard !refinedWindows.isEmpty else { return nil }

        let useFootLandmarks = hasFootLandmarks(coarseFrames, side: side)

        var icFrames: [PoseFrame] = []
        var shankAngles: [Double] = []
        var footDiffs: [Double] = []

        for window in refinedWindows {
            guard !window.isEmpty else { continue }
            guard let icFrame = findInitialContact(in: window, side: side) else { continue }

            icFrames.append(icFrame)

            if let shank = shankAngle(frame: icFrame, side: side, runDirection: runDir) {
                shankAngles.append(shank)
            }
            if let diff = heelVsForefootDiff(frame: icFrame, side: side) {
                footDiffs.append(diff)
            }
        }

        guard !icFrames.isEmpty else { return nil }

        let pattern: FootStrikePattern
        let confidence: Double
        let avgShank = shankAngles.isEmpty ? nil : shankAngles.reduce(0, +) / Double(shankAngles.count)
        let avgFootDiff = footDiffs.isEmpty ? nil : footDiffs.reduce(0, +) / Double(footDiffs.count)

        if useFootLandmarks, let avgDiff = avgFootDiff, !footDiffs.isEmpty {
            pattern = patternFromFootDiff(avgDiff)
            let stdDev = standardDeviation(footDiffs)
            let consistencyScore = max(0.0, 1.0 - (stdDev / 0.03))
            let sampleScore = min(1.0, Double(footDiffs.count) / 3.0)
            confidence = max(0.5, min(0.95, (consistencyScore * 0.6 + sampleScore * 0.4)))

            Log.biomechanics.info("""
            FootStrike REFINED [MediaPipe \(side)]: \(footDiffs.count) contacts, \
            heel-forefoot: \(footDiffs.map { String(format: "%.3f", $0) })m, \
            avg: \(String(format: "%.3f", avgDiff))m → \(pattern.rawValue)
            """)
        } else if let avg = avgShank, !shankAngles.isEmpty {
            if avg >= 10 { pattern = .rearfoot }
            else if avg >= 5 { pattern = .midfoot }
            else { pattern = .forefoot }

            let stdDev = standardDeviation(shankAngles)
            let consistencyScore = max(0.0, 1.0 - (stdDev / 10.0))
            let sampleScore = min(1.0, Double(shankAngles.count) / 4.0)
            confidence = max(0.4, min(0.95, (consistencyScore * 0.7 + sampleScore * 0.3)))

            Log.biomechanics.info("""
            FootStrike REFINED [Vision \(side)]: \(shankAngles.count) contacts, \
            shank angles: \(shankAngles.map { String(format: "%.1f", $0) }), \
            avg: \(String(format: "%.1f", avg))°
            """)
        } else {
            return nil
        }

        let contactDetail = buildContactFrameDetail(
            contactFrames: icFrames, side: side,
            runDirection: runDir, targetShank: avgShank ?? 0
        )

        return FootStrikeAnalysis(
            pattern: pattern,
            confidence: confidence,
            ankleAngleAtContact: nil,
            shankAngleAtContact: avgShank.map { round($0 * 10) / 10 },
            heelVsForefoot: avgFootDiff.map { round($0 * 1000) / 1000 },
            frameIndices: icFrames.map { $0.frameIndex },
            contactFrameDetail: contactDetail
        )
    }

    /// Find the initial contact frame within a dense window.
    /// Uses the lowest foot point available: heel (MediaPipe) or ankle (Vision).
    /// Finds the minimum Y, then walks backward to the first frame entering the
    /// contact zone (within 15% of range above minimum).
    private static func findInitialContact(in window: [PoseFrame], side: String) -> PoseFrame? {
        // Prefer heel Y (actual ground contact point) over ankle Y
        let ankleData: [(y: Double, frame: PoseFrame)] = window.compactMap { frame in
            // Use the lowest of heel, foot index, ankle — whichever is available
            let heel = frame.jointPosition(named: "\(side)Heel")
            let footIdx = frame.jointPosition(named: "\(side)FootIndex")
            let ankle = frame.jointPosition(named: "\(side)Ankle")

            let lowestY: Float?
            if let h = heel, let f = footIdx {
                lowestY = min(h.y, f.y) // lower y = closer to ground
            } else if let h = heel {
                lowestY = h.y
            } else if let a = ankle {
                lowestY = a.y
            } else {
                lowestY = nil
            }

            guard let y = lowestY else { return nil }
            return (Double(y), frame)
        }
        guard ankleData.count >= 3 else { return ankleData.first?.frame }

        let yValues = ankleData.map(\.y)
        guard let yMin = yValues.min(),
              let yMax = yValues.max(),
              yMax > yMin
        else { return ankleData.first?.frame }

        // Find the minimum index (mid-stance)
        guard let (minIndex, _) = yValues.enumerated().min(by: { $0.element < $1.element }) else {
            return ankleData.first?.frame
        }

        // Contact zone: within 15% of the range above minimum
        let contactThreshold = yMin + (yMax - yMin) * 0.15

        // Walk backward from minimum to find where ankle first enters the contact zone
        var icIndex = minIndex
        for i in stride(from: minIndex - 1, through: 0, by: -1) {
            if yValues[i] > contactThreshold {
                // This frame is above the contact zone — the next one was the first in the zone
                icIndex = i + 1
                break
            }
            icIndex = i
        }

        Log.biomechanics.info(
            "  IC found at frame \(ankleData[icIndex].frame.frameIndex), t=\(String(format: "%.3f", ankleData[icIndex].frame.timestamp))s, \(minIndex - icIndex) frames before mid-stance"
        )

        return ankleData[icIndex].frame
    }

    /// Pick the contact frame whose shank angle is closest to the average.
    private static func buildContactFrameDetail(
        contactFrames: [PoseFrame], side: String,
        runDirection: simd_float3?, targetShank: Double
    ) -> FootStrikeContactFrame? {
        struct Candidate {
            let frame: PoseFrame
            let hipImg: CGPoint
            let kneeImg: CGPoint
            let ankleImg: CGPoint
            let heelImg: CGPoint?
            let footIndexImg: CGPoint?
            let shank: Double
        }

        var candidates: [Candidate] = []
        for frame in contactFrames {
            guard let hipImg = frame.imagePosition(named: "\(side)Hip"),
                  let kneeImg = frame.imagePosition(named: "\(side)Knee"),
                  let ankleImg = frame.imagePosition(named: "\(side)Ankle"),
                  let shank = shankAngle(frame: frame, side: side, runDirection: runDirection)
            else { continue }

            let heelImg = frame.imagePosition(named: "\(side)Heel")
            let footIndexImg = frame.imagePosition(named: "\(side)FootIndex")

            candidates.append(Candidate(
                frame: frame, hipImg: hipImg, kneeImg: kneeImg, ankleImg: ankleImg,
                heelImg: heelImg, footIndexImg: footIndexImg, shank: shank
            ))
        }

        guard let best = candidates.min(by: {
            abs($0.shank - targetShank) < abs($1.shank - targetShank)
        }) else { return nil }

        return FootStrikeContactFrame(
            timestamp: best.frame.timestamp,
            frameIndex: best.frame.frameIndex,
            hipImageX: Float(best.hipImg.x),
            hipImageY: Float(best.hipImg.y),
            kneeImageX: Float(best.kneeImg.x),
            kneeImageY: Float(best.kneeImg.y),
            ankleImageX: Float(best.ankleImg.x),
            ankleImageY: Float(best.ankleImg.y),
            heelImageX: best.heelImg.map { Float($0.x) },
            heelImageY: best.heelImg.map { Float($0.y) },
            footIndexImageX: best.footIndexImg.map { Float($0.x) },
            footIndexImageY: best.footIndexImg.map { Float($0.y) },
            shankAngle: round(best.shank * 10) / 10
        )
    }

    // MARK: - Ground Contact Detection

    /// Detect frames where the foot is on the ground.
    /// Uses the lowest available foot landmark (heel > foot index > ankle)
    /// and finds Y minima via velocity zero-crossings on smoothed data.
    static func detectInitialContactFrames(frames: [PoseFrame], side: String) -> [PoseFrame] {
        let fps = effectiveSampleRate(frames: frames)
        let ankleData: [(y: Double, frame: PoseFrame)] = frames.compactMap { frame in
            let heel = frame.jointPosition(named: "\(side)Heel")
            let footIdx = frame.jointPosition(named: "\(side)FootIndex")
            let ankle = frame.jointPosition(named: "\(side)Ankle")

            let lowestY: Float?
            if let h = heel, let f = footIdx {
                lowestY = min(h.y, f.y)
            } else if let h = heel {
                lowestY = h.y
            } else if let a = ankle {
                lowestY = a.y
            } else {
                lowestY = nil
            }

            guard let y = lowestY else { return nil }
            return (Double(y), frame)
        }

        // Need ~0.4s of ankle data — enough for one gait cycle
        let minFrames = max(5, Int(fps * 0.4))
        guard ankleData.count >= minFrames else { return [] }

        let smoothWindow = max(3, Int(fps * 0.15) | 1)
        let smoothed = movingAverage(ankleData.map { $0.y }, window: smoothWindow)

        var velocity: [Double] = []
        for i in 0 ..< smoothed.count {
            if i == 0 {
                velocity.append(smoothed[1] - smoothed[0])
            } else if i == smoothed.count - 1 {
                velocity.append(smoothed[i] - smoothed[i - 1])
            } else {
                velocity.append((smoothed[i + 1] - smoothed[i - 1]) / 2.0)
            }
        }

        guard let yMin = smoothed.min(), let yMax = smoothed.max(), yMax > yMin else { return [] }
        let contactThreshold = yMin + (yMax - yMin) * 0.4

        let minGapFrames = max(2, Int(fps * 0.2))
        var minimaIndices: [Int] = []
        var lastMinIndex = -minGapFrames

        for i in 1 ..< velocity.count {
            let crossesZero = velocity[i - 1] < 0 && velocity[i] >= 0
            let inLowerRange = smoothed[i] < contactThreshold
            let gapOK = (i - lastMinIndex) >= minGapFrames

            if crossesZero && inLowerRange && gapOK {
                minimaIndices.append(i)
                lastMinIndex = i
            }
        }

        // Fallback for very short clips: if zero-crossing found nothing,
        // use the global ankle Y minimum as a single contact approximation
        if minimaIndices.isEmpty {
            if let (minIdx, _) = smoothed.enumerated().min(by: { $0.element < $1.element }),
               smoothed[minIdx] < contactThreshold
            {
                minimaIndices.append(minIdx)
            }
        }

        return minimaIndices.map { ankleData[$0].frame }
    }

    // MARK: - Summary Computation

    /// Compute full joint angles summary from all pose frames.
    static func computeSummary(frames: [PoseFrame]) -> JointAnglesSummary {
        let runDir = inferRunningDirection(frames: frames)
        return JointAnglesSummary(
            hipLeft: computeJointData(frames: frames, joint: "hip", side: "left"),
            hipRight: computeJointData(frames: frames, joint: "hip", side: "right"),
            kneeLeft: computeJointData(frames: frames, joint: "knee", side: "left"),
            kneeRight: computeJointData(frames: frames, joint: "knee", side: "right"),
            ankleLeft: nil, // Vision lacks foot/toe joints — ankle ROM is not measurable
            ankleRight: nil,
            shankLeft: computeShankData(frames: frames, side: "left", runDirection: runDir),
            shankRight: computeShankData(frames: frames, side: "right", runDirection: runDir),
            shoulderRotation: computeShoulderRotation(frames: frames)
        )
    }

    private static func computeJointData(frames: [PoseFrame], joint: String, side: String) -> JointAngleData? {
        let angles: [Double] = frames.compactMap { frame in
            switch joint {
            case "hip": return hipFlexion(frame: frame, side: side)
            case "knee": return kneeFlexion(frame: frame, side: side)
            default: return nil
            }
        }

        // Require at least 40% of frames to have valid joint data for this side.
        // If fewer than 40% of frames detected the joints, tracking was too sparse
        // (likely occluded far side from sagittal view) and the data isn't reliable.
        let coverageRatio = Double(angles.count) / Double(max(frames.count, 1))
        guard angles.count >= 5, coverageRatio >= 0.4 else { return nil }

        let min = angles.min() ?? 0
        let max = angles.max() ?? 0
        let mean = angles.reduce(0, +) / Double(angles.count)

        return JointAngleData(
            meanAngle: round(mean * 10) / 10,
            maxAngle: round(max * 10) / 10,
            minAngle: round(min * 10) / 10,
            rangeOfMotion: round((max - min) * 10) / 10,
            angleTimeSeries: angles
        )
    }

    private static func computeShankData(frames: [PoseFrame], side: String, runDirection: simd_float3? = nil) -> ShankAngleData? {
        let angles: [Double] = frames.compactMap { shankAngle(frame: $0, side: side, runDirection: runDirection) }
        guard !angles.isEmpty else { return nil }

        let contactFrames = detectInitialContactFrames(frames: frames, side: side)
        let contactAngles = contactFrames.compactMap { shankAngle(frame: $0, side: side, runDirection: runDirection) }
        let atContact: Double? = contactAngles.isEmpty ? nil :
            contactAngles.reduce(0, +) / Double(contactAngles.count)

        return ShankAngleData(
            atInitialContact: atContact.map { round($0 * 10) / 10 },
            meanAngle: round((angles.reduce(0, +) / Double(angles.count)) * 10) / 10,
            maxAngle: round((angles.max() ?? 0) * 10) / 10,
            minAngle: round((angles.min() ?? 0) * 10) / 10
        )
    }

    /// Compute foot strike analysis for both sides.
    static func computeFootStrike(frames: [PoseFrame], viewAngle: ViewAngle) -> FootStrikeAnalysis? {
        // Determine which side is visible based on camera angle
        let side: String
        switch viewAngle {
        case .sagittalLeft: side = "left"
        case .sagittalRight: side = "right"
        case .frontal, .posterior:
            // For frontal/posterior, try both sides and use the one with more data
            let leftResult = classifyFootStrike(frames: frames, side: "left")
            let rightResult = classifyFootStrike(frames: frames, side: "right")
            if let left = leftResult, let right = rightResult {
                return left.confidence > right.confidence ? left : right
            }
            return leftResult ?? rightResult
        }

        return classifyFootStrike(frames: frames, side: side)
    }

    // MARK: - Ground Contact Time

    /// Compute ground contact time (ms) for the visible side(s) based on camera angle.
    /// From a sagittal view, only the near-side ankle is reliably tracked —
    /// the far-side ankle is occluded and produces inaccurate data.
    static func computeGaitMetrics(frames: [PoseFrame], viewAngle: ViewAngle) -> GaitMetrics? {
        let leftGCT: Double?
        let rightGCT: Double?

        switch viewAngle {
        case .sagittalLeft:
            // Left side is near the camera — only trust left ankle
            leftGCT = estimateGCT(frames: frames, side: "left")
            rightGCT = nil
        case .sagittalRight:
            // Right side is near the camera — only trust right ankle
            leftGCT = nil
            rightGCT = estimateGCT(frames: frames, side: "right")
        case .frontal, .posterior:
            // Both sides roughly equidistant — compute both
            leftGCT = estimateGCT(frames: frames, side: "left")
            rightGCT = estimateGCT(frames: frames, side: "right")
        }

        guard leftGCT != nil || rightGCT != nil else { return nil }

        let avgGCT: Double?
        if let l = leftGCT, let r = rightGCT {
            avgGCT = (l + r) / 2
        } else {
            avgGCT = leftGCT ?? rightGCT
        }

        // Only report balance when both sides are available (frontal/posterior
        // or merged from two sagittal videos)
        let balance: Double?
        if let l = leftGCT, let r = rightGCT, l + r > 0 {
            balance = round((l / (l + r)) * 1000) / 10
        } else {
            balance = nil
        }

        return GaitMetrics(
            cadence: nil,
            strideLength: nil,
            groundContactTime: avgGCT.map { round($0 * 10) / 10 },
            groundContactTimeLeft: leftGCT.map { round($0 * 10) / 10 },
            groundContactTimeRight: rightGCT.map { round($0 * 10) / 10 },
            groundContactBalance: balance,
            flightTime: nil,
            stancePhasePercent: nil,
            swingPhasePercent: nil,
            verticalOscillation: nil,
            gaitCycleEvents: nil
        )
    }

    /// Estimate average ground contact time (ms) for one side.
    /// Uses threshold-based stance detection on ankle y-position.
    ///
    /// Parameters scale with effective fps:
    /// - Min data: ~800ms worth of frames
    /// - Smoothing: ~300ms window (preserves ~250ms stance phase signal)
    private static func estimateGCT(frames: [PoseFrame], side: String) -> Double? {
        let fps = effectiveSampleRate(frames: frames)
        let ankleData: [(timestamp: Double, y: Double)] = frames.compactMap { frame in
            guard let ankle = frame.jointPosition(named: "\(side)Ankle") else { return nil }
            return (frame.timestamp, Double(ankle.y))
        }

        let minFrames = max(5, Int(fps * 0.4))
        guard ankleData.count >= minFrames else { return nil }

        let yValues = ankleData.map { $0.y }
        let smoothWindow = max(3, Int(fps * 0.3) | 1) // ~300ms, ensure odd
        let smoothed = movingAverage(yValues, window: smoothWindow)

        guard let yMin = smoothed.min(), let yMax = smoothed.max(), yMax > yMin else { return nil }

        // Dynamic threshold at 40% from minimum (stance = ankle low, swing = ankle high)
        let threshold = yMin + (yMax - yMin) * 0.40

        // Detect stance phases (below threshold)
        var gctValues: [Double] = []
        var stanceStartTime: Double?

        for i in 0 ..< smoothed.count {
            if smoothed[i] < threshold {
                if stanceStartTime == nil {
                    stanceStartTime = ankleData[i].timestamp
                }
            } else {
                if let start = stanceStartTime {
                    let gctMs = (ankleData[i].timestamp - start) * 1000
                    // Running GCT typically 150–400ms; allow wide range for slow joggers
                    if gctMs > 80 && gctMs < 500 {
                        gctValues.append(gctMs)
                    }
                    stanceStartTime = nil
                }
            }
        }

        // Need at least 1 stance phase; 2+ is better but 1 is usable
        guard !gctValues.isEmpty else { return nil }

        // With 2+ values, remove outliers via IQR
        if gctValues.count >= 4 {
            let sorted = gctValues.sorted()
            let q1 = sorted[sorted.count / 4]
            let q3 = sorted[(sorted.count * 3) / 4]
            let iqr = q3 - q1
            let lowerBound = q1 - 1.5 * max(iqr, 20)
            let upperBound = q3 + 1.5 * max(iqr, 20)
            let filtered = gctValues.filter { $0 >= lowerBound && $0 <= upperBound }
            if !filtered.isEmpty {
                return filtered.reduce(0, +) / Double(filtered.count)
            }
        }

        return gctValues.reduce(0, +) / Double(gctValues.count)
    }

    /// Merge gait metrics from multiple clips, preferring the best view angle per side.
    static func mergeGaitMetrics(_ clips: [(metrics: GaitMetrics, viewAngle: ViewAngle)]) -> GaitMetrics? {
        guard !clips.isEmpty else { return nil }
        if clips.count == 1 { return clips[0].metrics }

        // Prefer sagittal_left for left GCT, sagittal_right for right GCT
        let leftPriority: [ViewAngle] = [.sagittalLeft, .frontal, .posterior, .sagittalRight]
        let rightPriority: [ViewAngle] = [.sagittalRight, .frontal, .posterior, .sagittalLeft]

        let bestLeftGCT = pickBestValue(from: clips, keyPath: \.groundContactTimeLeft, priority: leftPriority)
        let bestRightGCT = pickBestValue(from: clips, keyPath: \.groundContactTimeRight, priority: rightPriority)

        let avgGCT: Double?
        if let l = bestLeftGCT, let r = bestRightGCT {
            avgGCT = round(((l + r) / 2) * 10) / 10
        } else {
            avgGCT = bestLeftGCT ?? bestRightGCT
        }

        let balance: Double?
        if let l = bestLeftGCT, let r = bestRightGCT, l + r > 0 {
            balance = round((l / (l + r)) * 1000) / 10
        } else {
            balance = nil
        }

        return GaitMetrics(
            cadence: nil,
            strideLength: nil,
            groundContactTime: avgGCT,
            groundContactTimeLeft: bestLeftGCT,
            groundContactTimeRight: bestRightGCT,
            groundContactBalance: balance,
            flightTime: nil,
            stancePhasePercent: nil,
            swingPhasePercent: nil,
            verticalOscillation: nil,
            gaitCycleEvents: nil
        )
    }

    private static func pickBestValue(
        from clips: [(metrics: GaitMetrics, viewAngle: ViewAngle)],
        keyPath: KeyPath<GaitMetrics, Double?>,
        priority: [ViewAngle]
    ) -> Double? {
        for angle in priority {
            if let clip = clips.first(where: { $0.viewAngle == angle }),
               let value = clip.metrics[keyPath: keyPath]
            {
                return value
            }
        }
        return clips.compactMap { $0.metrics[keyPath: keyPath] }.first
    }

    // MARK: - Multi-Video Merging

    /// Merge joint angle summaries from multiple videos shot at different angles.
    /// Prefers data from the camera angle that best captures each joint.
    static func mergeSummaries(_ clips: [(summary: JointAnglesSummary, viewAngle: ViewAngle)]) -> JointAnglesSummary {
        guard !clips.isEmpty else {
            return JointAnglesSummary(
                hipLeft: nil, hipRight: nil, kneeLeft: nil, kneeRight: nil,
                ankleLeft: nil, ankleRight: nil, shankLeft: nil, shankRight: nil,
                shoulderRotation: nil
            )
        }

        if clips.count == 1 { return clips[0].summary }

        // Priority order for left-side joints: sagittalLeft > frontal > posterior > sagittalRight
        let leftPriority: [ViewAngle] = [.sagittalLeft, .frontal, .posterior, .sagittalRight]
        // Priority order for right-side joints: sagittalRight > frontal > posterior > sagittalLeft
        let rightPriority: [ViewAngle] = [.sagittalRight, .frontal, .posterior, .sagittalLeft]

        // Shoulder rotation is best from frontal/posterior (both shoulders visible)
        let rotationPriority: [ViewAngle] = [.frontal, .posterior, .sagittalLeft, .sagittalRight]

        return JointAnglesSummary(
            hipLeft: pickBestJointData(from: clips, keyPath: \.hipLeft, priority: leftPriority),
            hipRight: pickBestJointData(from: clips, keyPath: \.hipRight, priority: rightPriority),
            kneeLeft: pickBestJointData(from: clips, keyPath: \.kneeLeft, priority: leftPriority),
            kneeRight: pickBestJointData(from: clips, keyPath: \.kneeRight, priority: rightPriority),
            ankleLeft: pickBestJointData(from: clips, keyPath: \.ankleLeft, priority: leftPriority),
            ankleRight: pickBestJointData(from: clips, keyPath: \.ankleRight, priority: rightPriority),
            shankLeft: pickBestShankData(from: clips, keyPath: \.shankLeft, priority: leftPriority),
            shankRight: pickBestShankData(from: clips, keyPath: \.shankRight, priority: rightPriority),
            shoulderRotation: pickBestRotationData(from: clips, priority: rotationPriority)
        )
    }

    private static func pickBestJointData(
        from clips: [(summary: JointAnglesSummary, viewAngle: ViewAngle)],
        keyPath: KeyPath<JointAnglesSummary, JointAngleData?>,
        priority: [ViewAngle]
    ) -> JointAngleData? {
        // Try angles in priority order
        for angle in priority {
            if let clip = clips.first(where: { $0.viewAngle == angle }),
               let data = clip.summary[keyPath: keyPath]
            {
                return data
            }
        }
        // Fall back to any clip that has data
        return clips.compactMap { $0.summary[keyPath: keyPath] }.first
    }

    private static func pickBestShankData(
        from clips: [(summary: JointAnglesSummary, viewAngle: ViewAngle)],
        keyPath: KeyPath<JointAnglesSummary, ShankAngleData?>,
        priority: [ViewAngle]
    ) -> ShankAngleData? {
        for angle in priority {
            if let clip = clips.first(where: { $0.viewAngle == angle }),
               let data = clip.summary[keyPath: keyPath]
            {
                return data
            }
        }
        return clips.compactMap { $0.summary[keyPath: keyPath] }.first
    }

    private static func pickBestRotationData(
        from clips: [(summary: JointAnglesSummary, viewAngle: ViewAngle)],
        priority: [ViewAngle]
    ) -> ShoulderRotationData? {
        for angle in priority {
            if let clip = clips.first(where: { $0.viewAngle == angle }),
               let data = clip.summary.shoulderRotation
            {
                return data
            }
        }
        return clips.compactMap { $0.summary.shoulderRotation }.first
    }

    /// Pick the best foot strike analysis from multiple videos.
    /// Sagittal views give the most accurate foot strike classification.
    static func bestFootStrike(_ analyses: [(analysis: FootStrikeAnalysis, viewAngle: ViewAngle)]) -> FootStrikeAnalysis? {
        guard !analyses.isEmpty else { return nil }
        if analyses.count == 1 { return analyses[0].analysis }

        // Prefer sagittal views for foot strike
        let sagittalPriority: [ViewAngle] = [.sagittalLeft, .sagittalRight, .frontal, .posterior]
        for angle in sagittalPriority {
            if let match = analyses.first(where: { $0.viewAngle == angle }) {
                return match.analysis
            }
        }
        return analyses.first?.analysis
    }

    // MARK: - FPS Detection

    /// Infer the effective sample rate (fps) from frame timestamps.
    /// Returns ~10 for fast mode, ~20 for enhanced mode.
    static func effectiveSampleRate(frames: [PoseFrame]) -> Double {
        guard frames.count >= 2 else { return 10.0 }
        let totalTime = frames.last!.timestamp - frames.first!.timestamp
        guard totalTime > 0 else { return 10.0 }
        return Double(frames.count - 1) / totalTime
    }

    // MARK: - View Angle Detection

    /// Auto-detect camera view angle from pose landmark positions.
    /// Compares left vs right hip X-separation to infer sagittal vs frontal/posterior.
    static func detectViewAngle(frames: [PoseFrame]) -> ViewAngle {
        guard frames.count >= 3 else { return .frontal }

        var xSeparations: [Float] = []
        var leftHipXs: [Float] = []
        var rightHipXs: [Float] = []
        var noseZSamples: [Float] = []
        var hipMidZSamples: [Float] = []

        for frame in frames {
            guard let lh = frame.jointPosition(named: "leftHip"),
                  let rh = frame.jointPosition(named: "rightHip") else { continue }

            let xSep = abs(lh.x - rh.x)
            xSeparations.append(xSep)
            leftHipXs.append(lh.x)
            rightHipXs.append(rh.x)

            let hipMidZ = (lh.z + rh.z) / 2
            hipMidZSamples.append(hipMidZ)

            if let nose = frame.jointPosition(named: "nose") {
                noseZSamples.append(nose.z)
            }
        }

        guard xSeparations.count >= 3 else { return .frontal }

        let avgXSep = xSeparations.reduce(0, +) / Float(xSeparations.count)

        // If left and right hips are close together in X, camera is viewing from the side (sagittal)
        // If spread apart, camera is viewing from front or back
        let bodyHeights = frames.compactMap { $0.bodyHeight }
        let avgBodyHeight = bodyHeights.isEmpty ? Float(0.5) : bodyHeights.reduce(0, +) / Float(bodyHeights.count)
        let separationRatio = avgXSep / avgBodyHeight

        if separationRatio < 0.15 {
            // Sagittal view — hips nearly overlap in X
            let avgLeftX = leftHipXs.reduce(0, +) / Float(leftHipXs.count)
            let avgRightX = rightHipXs.reduce(0, +) / Float(rightHipXs.count)

            // The hip closer to center (0.5 in normalized coords) is the near hip
            let leftDistFromCenter = abs(avgLeftX - 0.5)
            let rightDistFromCenter = abs(avgRightX - 0.5)
            return leftDistFromCenter < rightDistFromCenter ? .sagittalLeft : .sagittalRight
        } else {
            // Frontal or posterior — hips are spread apart
            // If nose Z < hip midpoint Z, face is closer to camera → frontal
            if !noseZSamples.isEmpty, !hipMidZSamples.isEmpty {
                let avgNoseZ = noseZSamples.reduce(0, +) / Float(noseZSamples.count)
                let avgHipMidZ = hipMidZSamples.reduce(0, +) / Float(hipMidZSamples.count)
                return avgNoseZ < avgHipMidZ ? .frontal : .posterior
            }
            return .frontal
        }
    }

    // MARK: - Qualitative Posture Metrics (Form Check)

    /// Average trunk forward lean (degrees). Positive = leaning forward.
    /// Computed from the angle between shoulder midpoint → hip midpoint vector and vertical.
    static func computeTrunkLean(frames: [PoseFrame]) -> Double? {
        let angles: [Double] = frames.compactMap { frame in
            guard let leftShoulder = frame.jointPosition(named: "leftShoulder"),
                  let rightShoulder = frame.jointPosition(named: "rightShoulder"),
                  let leftHip = frame.jointPosition(named: "leftHip"),
                  let rightHip = frame.jointPosition(named: "rightHip")
            else { return nil }

            let shoulderMid = (leftShoulder + rightShoulder) / 2
            let hipMid = (leftHip + rightHip) / 2
            let trunkVector = shoulderMid - hipMid // hip → shoulder
            let vertical = simd_float3(0, 1, 0)

            let trunkLen = simd_length(trunkVector)
            guard trunkLen > 0.01 else { return nil }

            let cosAngle = simd_dot(simd_normalize(trunkVector), vertical)
            return Double(acos(max(-1, min(1, cosAngle)))) * 180.0 / .pi
        }

        guard angles.count >= 5 else { return nil }
        let mean = angles.reduce(0, +) / Double(angles.count)
        return round(mean * 10) / 10
    }

    /// Head forward offset relative to shoulder midpoint, normalized by body height.
    /// Positive = head is forward of shoulders. Values > 0.05 are notable.
    static func computeHeadForwardOffset(frames: [PoseFrame]) -> Double? {
        let runDir = inferRunningDirection(frames: frames) ?? simd_float3(1, 0, 0)

        let offsets: [Double] = frames.compactMap { frame in
            guard let head = frame.jointPosition(named: "centerHead"),
                  let leftShoulder = frame.jointPosition(named: "leftShoulder"),
                  let rightShoulder = frame.jointPosition(named: "rightShoulder")
            else { return nil }

            let shoulderMid = (leftShoulder + rightShoulder) / 2
            let headDiff = head - shoulderMid
            // Project onto running direction (forward component)
            let forwardOffset = simd_dot(headDiff, runDir)

            // Normalize by body height if available
            let height = frame.bodyHeight ?? 1.0
            guard height > 0.1 else { return nil }
            return Double(forwardOffset / height)
        }

        guard offsets.count >= 5 else { return nil }
        let mean = offsets.reduce(0, +) / Double(offsets.count)
        return round(mean * 1000) / 1000
    }

    /// Arm swing symmetry (0-1, where 1.0 = perfectly symmetric).
    /// Compares left vs right wrist Y-position oscillation amplitude relative to shoulders.
    static func computeArmSwingSymmetry(frames: [PoseFrame]) -> Double? {
        let leftAmplitudes: [Double] = frames.compactMap { frame in
            guard let wrist = frame.jointPosition(named: "leftWrist"),
                  let shoulder = frame.jointPosition(named: "leftShoulder")
            else { return nil }
            return Double(wrist.y - shoulder.y)
        }
        let rightAmplitudes: [Double] = frames.compactMap { frame in
            guard let wrist = frame.jointPosition(named: "rightWrist"),
                  let shoulder = frame.jointPosition(named: "rightShoulder")
            else { return nil }
            return Double(wrist.y - shoulder.y)
        }

        guard leftAmplitudes.count >= 5, rightAmplitudes.count >= 5 else { return nil }

        let leftRange = (leftAmplitudes.max() ?? 0) - (leftAmplitudes.min() ?? 0)
        let rightRange = (rightAmplitudes.max() ?? 0) - (rightAmplitudes.min() ?? 0)

        guard leftRange > 0.001, rightRange > 0.001 else { return nil }

        let ratio = min(leftRange, rightRange) / max(leftRange, rightRange)
        return round(ratio * 100) / 100
    }

    // MARK: - Utility

    private static func movingAverage(_ values: [Double], window: Int) -> [Double] {
        guard values.count >= window else { return values }
        var result: [Double] = []
        let halfWindow = window / 2

        for i in 0 ..< values.count {
            let start = max(0, i - halfWindow)
            let end = min(values.count - 1, i + halfWindow)
            let slice = values[start ... end]
            result.append(slice.reduce(0, +) / Double(slice.count))
        }

        return result
    }

    private static func standardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let squaredDiffs = values.map { ($0 - mean) * ($0 - mean) }
        return sqrt(squaredDiffs.reduce(0, +) / Double(values.count - 1))
    }
}
