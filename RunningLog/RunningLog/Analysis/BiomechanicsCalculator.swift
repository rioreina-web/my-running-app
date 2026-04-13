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

    /// Ankle dorsiflexion angle: knee → ankle → footIndex
    /// Only available with MediaPipe (which provides foot landmarks).
    static func ankleDorsiflexion(frame: PoseFrame, side: String) -> Double? {
        guard let knee = frame.jointPosition(named: "\(side)Knee"),
              let ankle = frame.jointPosition(named: "\(side)Ankle"),
              let footIndex = frame.jointPosition(named: "\(side)FootIndex")
        else { return nil }
        return jointAngle(pointA: knee, pointB: ankle, pointC: footIndex)
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

    /// Estimate foot length from heel-to-toe distance across multiple frames.
    /// Returns average foot length in meters, or nil if insufficient data.
    private static func estimateFootLength(frames: [PoseFrame], side: String) -> Double? {
        let lengths: [Double] = frames.compactMap { frame in
            guard let heel = frame.jointPosition(named: "\(side)Heel"),
                  let toe = frame.jointPosition(named: "\(side)FootIndex")
            else { return nil }
            return Double(simd_distance(heel, toe))
        }
        guard lengths.count >= 3 else { return nil }
        return lengths.reduce(0, +) / Double(lengths.count)
    }

    /// Classify foot strike from heel vs. forefoot Y difference.
    /// Threshold is relative to foot length when available (10% of foot length),
    /// falling back to 15mm when foot length can't be estimated.
    private static func patternFromFootDiff(_ diff: Double, footLength: Double? = nil) -> FootStrikePattern {
        // Use 10% of foot length as threshold (~0.025m for a typical 25cm foot)
        // Falls back to 15mm if foot length is unavailable
        let threshold = footLength.map { $0 * 0.10 } ?? 0.015

        if diff < -threshold {
            return .rearfoot
        } else if diff > threshold {
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
        let footLength = estimateFootLength(frames: allFrames, side: side)
        let pattern = patternFromFootDiff(avgDiff, footLength: footLength)

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
            let footLength = estimateFootLength(frames: coarseFrames, side: side)
            pattern = patternFromFootDiff(avgDiff, footLength: footLength)
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
}
