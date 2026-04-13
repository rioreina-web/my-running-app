//
//  BiomechanicsCalculatorAnalysis.swift
//  RunningLog
//
//  Multi-video merging, FPS detection, view angle detection,
//  qualitative posture metrics, fatigue analysis, and utilities.
//

import Foundation
import os
import simd

extension BiomechanicsCalculator {

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
    /// Compares left vs right elbow flexion angle oscillation (shoulder→elbow→wrist).
    /// Elbow angle is more stable than wrist position and less affected by partial occlusion.
    /// Should only be called for frontal/posterior clips where both arms are visible.
    static func computeArmSwingSymmetry(frames: [PoseFrame]) -> Double? {
        let minConfidence: Float = 0.5

        let leftAngles: [Double] = frames.compactMap { frame in
            guard let shoulder = frame.joint(named: "leftShoulder"),
                  let elbow = frame.joint(named: "leftElbow"),
                  let wrist = frame.joint(named: "leftWrist"),
                  shoulder.confidence >= minConfidence,
                  elbow.confidence >= minConfidence,
                  wrist.confidence >= minConfidence
            else { return nil }
            let a = simd_float3(shoulder.x, shoulder.y, shoulder.z)
            let b = simd_float3(elbow.x, elbow.y, elbow.z)
            let c = simd_float3(wrist.x, wrist.y, wrist.z)
            let ba = a - b
            let bc = c - b
            let lenBA = simd_length(ba)
            let lenBC = simd_length(bc)
            guard lenBA > 0.001, lenBC > 0.001 else { return nil }
            let cosAngle = simd_dot(ba, bc) / (lenBA * lenBC)
            return Double(acos(min(1, max(-1, cosAngle))) * 180 / .pi)
        }

        let rightAngles: [Double] = frames.compactMap { frame in
            guard let shoulder = frame.joint(named: "rightShoulder"),
                  let elbow = frame.joint(named: "rightElbow"),
                  let wrist = frame.joint(named: "rightWrist"),
                  shoulder.confidence >= minConfidence,
                  elbow.confidence >= minConfidence,
                  wrist.confidence >= minConfidence
            else { return nil }
            let a = simd_float3(shoulder.x, shoulder.y, shoulder.z)
            let b = simd_float3(elbow.x, elbow.y, elbow.z)
            let c = simd_float3(wrist.x, wrist.y, wrist.z)
            let ba = a - b
            let bc = c - b
            let lenBA = simd_length(ba)
            let lenBC = simd_length(bc)
            guard lenBA > 0.001, lenBC > 0.001 else { return nil }
            let cosAngle = simd_dot(ba, bc) / (lenBA * lenBC)
            return Double(acos(min(1, max(-1, cosAngle))) * 180 / .pi)
        }

        guard leftAngles.count >= 10, rightAngles.count >= 10 else { return nil }

        let leftRange = trimmedRange(leftAngles)
        let rightRange = trimmedRange(rightAngles)

        // Elbow ROM should vary noticeably during running (at least a few degrees)
        guard leftRange > 2.0, rightRange > 2.0 else { return nil }

        let ratio = min(leftRange, rightRange) / max(leftRange, rightRange)
        return round(ratio * 100) / 100
    }

    /// Range between 5th and 95th percentile to ignore outliers from occlusion/noise.
    private static func trimmedRange(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let lo = sorted[max(0, sorted.count / 20)]           // 5th percentile
        let hi = sorted[min(sorted.count - 1, sorted.count * 19 / 20)] // 95th percentile
        return hi - lo
    }

    // MARK: - Fatigue Analysis

    /// Compare form in the first half vs second half of frames.
    /// Returns (earlyTrunkLean, lateTrunkLean, earlyCadence, lateCadence).
    /// Only meaningful for clips with enough data (>= 20 frames, >= 2 seconds).
    static func computeFatigueIndicators(frames: [PoseFrame]) -> (
        trunkLeanEarly: Double?, trunkLeanLate: Double?,
        cadenceEarly: Double?, cadenceLate: Double?
    ) {
        guard frames.count >= 20 else {
            return (nil, nil, nil, nil)
        }
        let duration = frames.last!.timestamp - frames.first!.timestamp
        guard duration >= 2.0 else {
            return (nil, nil, nil, nil)
        }

        let midpoint = frames.count / 2
        let earlyFrames = Array(frames[..<midpoint])
        let lateFrames = Array(frames[midpoint...])

        let earlyTrunk = computeTrunkLean(frames: earlyFrames)
        let lateTrunk = computeTrunkLean(frames: lateFrames)
        let earlyCadence = estimateCadence(frames: earlyFrames)
        let lateCadence = estimateCadence(frames: lateFrames)

        return (earlyTrunk, lateTrunk, earlyCadence, lateCadence)
    }

    // MARK: - Utility

    static func movingAverage(_ values: [Double], window: Int) -> [Double] {
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

    static func standardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let squaredDiffs = values.map { ($0 - mean) * ($0 - mean) }
        return sqrt(squaredDiffs.reduce(0, +) / Double(values.count - 1))
    }
}
