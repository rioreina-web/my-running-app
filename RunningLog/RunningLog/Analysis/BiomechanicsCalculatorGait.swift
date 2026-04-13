//
//  BiomechanicsCalculatorGait.swift
//  RunningLog
//
//  Ground contact detection, gait summary computation,
//  and ground contact time estimation.
//

import Foundation
import os
import simd

extension BiomechanicsCalculator {

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
            ankleLeft: computeJointData(frames: frames, joint: "ankle", side: "left"),
            ankleRight: computeJointData(frames: frames, joint: "ankle", side: "right"),
            shankLeft: computeShankData(frames: frames, side: "left", runDirection: runDir),
            shankRight: computeShankData(frames: frames, side: "right", runDirection: runDir),
            shoulderRotation: computeShoulderRotation(frames: frames)
        )
    }

    /// Get the minimum confidence of the joints used for an angle computation.
    private static func jointConfidence(frame: PoseFrame, joint: String, side: String) -> Float {
        switch joint {
        case "hip":
            let confs = [
                frame.joint(named: "\(side)Shoulder")?.confidence,
                frame.joint(named: "\(side)Hip")?.confidence,
                frame.joint(named: "\(side)Knee")?.confidence,
            ].compactMap { $0 }
            return confs.min() ?? 0
        case "knee":
            let confs = [
                frame.joint(named: "\(side)Hip")?.confidence,
                frame.joint(named: "\(side)Knee")?.confidence,
                frame.joint(named: "\(side)Ankle")?.confidence,
            ].compactMap { $0 }
            return confs.min() ?? 0
        case "ankle":
            let confs = [
                frame.joint(named: "\(side)Knee")?.confidence,
                frame.joint(named: "\(side)Ankle")?.confidence,
                frame.joint(named: "\(side)FootIndex")?.confidence,
            ].compactMap { $0 }
            return confs.min() ?? 0
        default:
            return 0
        }
    }

    private static func computeJointData(frames: [PoseFrame], joint: String, side: String) -> JointAngleData? {
        var anglesWithWeights: [(angle: Double, weight: Double)] = []
        for frame in frames {
            let angle: Double?
            switch joint {
            case "hip": angle = hipFlexion(frame: frame, side: side)
            case "knee": angle = kneeFlexion(frame: frame, side: side)
            case "ankle": angle = ankleDorsiflexion(frame: frame, side: side)
            default: angle = nil
            }
            guard let a = angle else { continue }
            let conf = Double(jointConfidence(frame: frame, joint: joint, side: side))
            anglesWithWeights.append((a, conf))
        }

        let angles = anglesWithWeights.map(\.angle)

        // Require at least 40% of frames to have valid joint data for this side.
        let coverageRatio = Double(angles.count) / Double(max(frames.count, 1))
        guard angles.count >= 5, coverageRatio >= 0.4 else { return nil }

        let min = angles.min() ?? 0
        let max = angles.max() ?? 0

        // Confidence-weighted mean: higher-confidence frames contribute more
        let totalWeight = anglesWithWeights.map(\.weight).reduce(0, +)
        let mean: Double
        if totalWeight > 0 {
            mean = anglesWithWeights.map { $0.angle * $0.weight }.reduce(0, +) / totalWeight
        } else {
            mean = angles.reduce(0, +) / Double(angles.count)
        }

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

    /// Estimate cadence (steps per minute) from ankle oscillation zero-crossings.
    /// Counts contacts on both sides and doubles to get full step count.
    static func estimateCadence(frames: [PoseFrame]) -> Double? {
        guard frames.count >= 10 else { return nil }
        let duration = frames.last!.timestamp - frames.first!.timestamp
        guard duration >= 1.0 else { return nil } // need at least 1 second

        // Count contacts from both ankles
        let leftContacts = detectInitialContactFrames(frames: frames, side: "left")
        let rightContacts = detectInitialContactFrames(frames: frames, side: "right")

        // Use whichever side has more contacts (better tracked)
        let bestContacts = leftContacts.count >= rightContacts.count ? leftContacts : rightContacts
        guard bestContacts.count >= 2 else { return nil }

        // Each contact = one step on one side. Cadence from one side = contacts/time * 60.
        // Multiply by 2 for both feet = steps per minute.
        let stepsPerMinute = (Double(bestContacts.count) / duration) * 60.0 * 2.0

        // Sanity check: running cadence is typically 140-220 spm
        guard stepsPerMinute >= 120 && stepsPerMinute <= 240 else { return nil }

        return round(stepsPerMinute)
    }

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

        let cadence = estimateCadence(frames: frames)

        guard leftGCT != nil || rightGCT != nil || cadence != nil else { return nil }

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
            cadence: cadence,
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

        // Use first available cadence (any angle works since we use best-side contacts)
        let cadence = clips.compactMap { $0.metrics.cadence }.first

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
            cadence: cadence,
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
}
