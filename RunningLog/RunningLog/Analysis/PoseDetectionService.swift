//
//  PoseDetectionService.swift
//  RunningLog
//
//  Pose detection pipeline — extracts 3D body pose data from video frames.
//  Primary: MediaPipe BlazePose (33 landmarks including heel + foot index).
//  Fallback: Apple Vision framework (17 landmarks, no foot joints).
//

import AVFoundation
import Foundation
import os
@preconcurrency import MediaPipeTasksVision
import Vision

@Observable
final class PoseDetectionService {
    var isProcessing = false
    var progress: Double = 0
    var errorMessage: String?

    private var currentTask: Task<[PoseFrame], Error>?

    // MARK: - MediaPipe Landmarker

    /// Lazily initialized per detection session. Uses `.image` mode so frame
    /// order doesn't matter (safe for both full-video and refinement passes).
    nonisolated private func createLandmarker() -> PoseLandmarker? {
        guard let modelPath = Bundle.main.path(
            forResource: "pose_landmarker_lite", ofType: "task"
        ) else {
            print("[PoseDetection] MediaPipe model not found in bundle")
            return nil
        }

        let options = PoseLandmarkerOptions()
        options.baseOptions.modelAssetPath = modelPath
        options.runningMode = .image
        options.numPoses = 1
        options.minPoseDetectionConfidence = 0.5
        options.minPosePresenceConfidence = 0.5
        options.minTrackingConfidence = 0.5

        do {
            return try PoseLandmarker(options: options)
        } catch {
            print("[PoseDetection] Failed to create PoseLandmarker: \(error.localizedDescription)")
            return nil
        }
    }

    // MediaPipe landmark index → our joint name
    nonisolated private static let mediaPipeJointMap: [(Int, String)] = [
        (0, "centerHead"),
        (11, "leftShoulder"), (12, "rightShoulder"),
        (13, "leftElbow"), (14, "rightElbow"),
        (15, "leftWrist"), (16, "rightWrist"),
        (23, "leftHip"), (24, "rightHip"),
        (25, "leftKnee"), (26, "rightKnee"),
        (27, "leftAnkle"), (28, "rightAnkle"),
        (29, "leftHeel"), (30, "rightHeel"),
        (31, "leftFootIndex"), (32, "rightFootIndex"),
    ]

    // MARK: - Process Video

    /// Process a local video file and extract pose frames.
    @MainActor
    func processVideo(url: URL, sampleRate: Double = 10.0) async throws -> [PoseFrame] {
        guard !isProcessing else {
            throw BiomechanicsError.alreadyProcessing
        }

        isProcessing = true
        progress = 0
        errorMessage = nil

        let task = Task.detached(priority: .utility) { [weak self] in
            try await self?.extractPoseFrames(from: url, sampleRate: sampleRate) ?? []
        }
        currentTask = task

        do {
            let frames = try await task.value
            await MainActor.run {
                self.isProcessing = false
                self.progress = 1.0
            }

            if frames.isEmpty {
                throw BiomechanicsError.noPersonDetected
            }

            Log.biomechanics.info("Processed \(frames.count) pose frames from video")
            return frames
        } catch {
            await MainActor.run {
                self.isProcessing = false
                self.errorMessage = error.localizedDescription
            }
            throw error
        }
    }

    // MARK: - Cancel

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        isProcessing = false
        progress = 0
    }

    // MARK: - Frame Extraction

    private func extractPoseFrames(from url: URL, sampleRate: Double) async throws -> [PoseFrame] {
        let asset = AVURLAsset(url: url)

        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw BiomechanicsError.noVideoTrack
        }

        let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
        let duration = try await asset.load(.duration)
        let totalFrames = Int(Double(nominalFrameRate) * CMTimeGetSeconds(duration))
        let frameSkip = max(1, Int(Double(nominalFrameRate) / sampleRate))

        let reader = try AVAssetReader(asset: asset)
        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        let output = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false
        reader.add(output)

        guard reader.startReading() else {
            throw BiomechanicsError.videoReadFailed(reader.error?.localizedDescription ?? "Unknown error")
        }

        // Try to create MediaPipe landmarker; fall back to Vision if unavailable
        let landmarker = createLandmarker()
        if landmarker != nil {
            Log.biomechanics.info("Using MediaPipe BlazePose (33 landmarks)")
        } else {
            Log.biomechanics.info("MediaPipe unavailable, falling back to Apple Vision")
        }

        var frames: [PoseFrame] = []
        var frameIndex = 0

        while let sampleBuffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()

            if frameIndex % frameSkip == 0 {
                if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                    let timestamp = Double(frameIndex) / Double(nominalFrameRate)
                    let poseFrame: PoseFrame?

                    if let landmarker {
                        poseFrame = detectPoseMediaPipe(
                            in: pixelBuffer, frameIndex: frameIndex,
                            timestamp: timestamp, landmarker: landmarker
                        )
                    } else {
                        poseFrame = try detectPoseVision(
                            in: pixelBuffer, frameIndex: frameIndex,
                            timestamp: timestamp
                        )
                    }

                    if let poseFrame {
                        frames.append(poseFrame)
                    }
                }
                await Task.yield()
            }

            frameIndex += 1

            if frameIndex % 10 == 0 {
                let currentProgress = min(Double(frameIndex) / Double(totalFrames), 0.99)
                await MainActor.run { [currentProgress] in
                    self.progress = currentProgress
                }
            }
        }

        reader.cancelReading()
        return frames
    }

    // MARK: - MediaPipe Detection

    nonisolated private func detectPoseMediaPipe(
        in pixelBuffer: CVPixelBuffer,
        frameIndex: Int,
        timestamp: Double,
        landmarker: PoseLandmarker
    ) -> PoseFrame? {
        guard let mpImage = try? MPImage(pixelBuffer: pixelBuffer) else { return nil }
        guard let result = try? landmarker.detect(image: mpImage) else { return nil }

        guard let landmarks2D = result.landmarks.first,
              let worldLandmarks = result.worldLandmarks.first
        else { return nil }

        var joints: [JointPosition3D] = []

        for (idx, name) in Self.mediaPipeJointMap {
            guard idx < worldLandmarks.count, idx < landmarks2D.count else { continue }
            let wl = worldLandmarks[idx]
            let nl = landmarks2D[idx]

            let visibility = nl.visibility?.floatValue ?? 0
            guard visibility > 0.3 else { continue }

            joints.append(JointPosition3D(
                name: name,
                x: wl.x,
                y: -wl.y, // Negate: MediaPipe y-down → our y-up
                z: wl.z,
                confidence: visibility,
                imageX: nl.x,
                imageY: 1.0 - nl.y // Convert top-left origin → bottom-left origin
            ))
        }

        // Synthetic root (hip midpoint) for compatibility with existing code
        if let lh = joints.first(where: { $0.name == "leftHip" }),
           let rh = joints.first(where: { $0.name == "rightHip" })
        {
            joints.append(JointPosition3D(
                name: "root",
                x: (lh.x + rh.x) / 2,
                y: (lh.y + rh.y) / 2,
                z: (lh.z + rh.z) / 2,
                confidence: min(lh.confidence, rh.confidence),
                imageX: lh.imageX.flatMap { lx in rh.imageX.map { rx in (lx + rx) / 2 } },
                imageY: lh.imageY.flatMap { ly in rh.imageY.map { ry in (ly + ry) / 2 } }
            ))
        }

        guard joints.count >= 6 else { return nil }

        // Estimate body height from world landmarks
        var bodyHeight: Float?
        if let head = joints.first(where: { $0.name == "centerHead" }),
           let ankle = joints.first(where: { $0.name == "leftAnkle" })
            ?? joints.first(where: { $0.name == "rightAnkle" })
        {
            bodyHeight = abs(head.y - ankle.y)
        }

        return PoseFrame(
            frameIndex: frameIndex,
            timestamp: timestamp,
            joints: joints,
            bodyHeight: bodyHeight
        )
    }

    // MARK: - Vision Fallback

    nonisolated private func detectPoseVision(
        in pixelBuffer: CVPixelBuffer, frameIndex: Int, timestamp: Double
    ) throws -> PoseFrame? {
        if #available(iOS 17.0, *) {
            return try detectPose3D(in: pixelBuffer, frameIndex: frameIndex, timestamp: timestamp)
        } else {
            return try detectPose2D(in: pixelBuffer, frameIndex: frameIndex, timestamp: timestamp)
        }
    }

    // Joint name mapping — Vision framework
    @available(iOS 17.0, *)
    nonisolated private static let jointNameMap3D: [(VNHumanBodyPose3DObservation.JointName, String)] = [
        (.root, "root"),
        (.leftHip, "leftHip"), (.rightHip, "rightHip"),
        (.leftKnee, "leftKnee"), (.rightKnee, "rightKnee"),
        (.leftAnkle, "leftAnkle"), (.rightAnkle, "rightAnkle"),
        (.leftShoulder, "leftShoulder"), (.rightShoulder, "rightShoulder"),
        (.leftElbow, "leftElbow"), (.rightElbow, "rightElbow"),
        (.leftWrist, "leftWrist"), (.rightWrist, "rightWrist"),
        (.centerHead, "centerHead"), (.topHead, "topHead"),
    ]

    nonisolated private static let jointNameMap2D: [(VNHumanBodyPoseObservation.JointName, String)] = [
        (.root, "root"),
        (.leftHip, "leftHip"), (.rightHip, "rightHip"),
        (.leftKnee, "leftKnee"), (.rightKnee, "rightKnee"),
        (.leftAnkle, "leftAnkle"), (.rightAnkle, "rightAnkle"),
        (.leftShoulder, "leftShoulder"), (.rightShoulder, "rightShoulder"),
        (.leftElbow, "leftElbow"), (.rightElbow, "rightElbow"),
        (.leftWrist, "leftWrist"), (.rightWrist, "rightWrist"),
    ]

    @available(iOS 17.0, *)
    nonisolated private func detectPose3D(in pixelBuffer: CVPixelBuffer, frameIndex: Int, timestamp: Double) throws -> PoseFrame? {
        let request = VNDetectHumanBodyPose3DRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try handler.perform([request])

        guard let observation = request.results?.first else { return nil }

        var joints: [JointPosition3D] = []

        for (visionName, simpleName) in Self.jointNameMap3D {
            do {
                let point = try observation.recognizedPoint(visionName)
                let modelPos = point.position
                let imagePoint = try? observation.pointInImage(visionName)
                joints.append(JointPosition3D(
                    name: simpleName,
                    x: modelPos.columns.3.x,
                    y: modelPos.columns.3.y,
                    z: modelPos.columns.3.z,
                    confidence: 1.0,
                    imageX: imagePoint.map { Float($0.x) },
                    imageY: imagePoint.map { Float($0.y) }
                ))
            } catch {
                continue
            }
        }

        guard joints.count >= 6 else { return nil }

        return PoseFrame(
            frameIndex: frameIndex,
            timestamp: timestamp,
            joints: joints,
            bodyHeight: observation.bodyHeight
        )
    }

    nonisolated private func detectPose2D(in pixelBuffer: CVPixelBuffer, frameIndex: Int, timestamp: Double) throws -> PoseFrame? {
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try handler.perform([request])

        guard let observation = request.results?.first else { return nil }

        var joints: [JointPosition3D] = []

        for (visionName, simpleName) in Self.jointNameMap2D {
            if let point = try? observation.recognizedPoint(visionName),
               point.confidence > 0.3
            {
                joints.append(JointPosition3D(
                    name: simpleName,
                    x: Float(point.location.x),
                    y: Float(point.location.y),
                    z: 0,
                    confidence: Float(point.confidence),
                    imageX: Float(point.location.x),
                    imageY: Float(point.location.y)
                ))
            }
        }

        guard joints.count >= 6 else { return nil }

        return PoseFrame(
            frameIndex: frameIndex,
            timestamp: timestamp,
            joints: joints,
            bodyHeight: nil
        )
    }

    // MARK: - Two-Pass Refinement

    /// Extract dense pose frames at native fps in small windows around contact timestamps.
    func refineAroundTimestamps(
        url: URL,
        timestamps: [Double],
        windowSeconds: Double = 0.2
    ) async throws -> [[PoseFrame]] {
        try await Task.detached(priority: .utility) { [weak self] in
            guard let self else { return [[PoseFrame]]() }
            return try await self.extractRefinedFrames(
                from: url, timestamps: timestamps, windowSeconds: windowSeconds
            )
        }.value
    }

    private func extractRefinedFrames(
        from url: URL,
        timestamps: [Double],
        windowSeconds: Double
    ) async throws -> [[PoseFrame]] {
        guard !timestamps.isEmpty else { return [] }

        let asset = AVURLAsset(url: url)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw BiomechanicsError.noVideoTrack
        }
        let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)

        let maxRefineRate: Double = 60.0
        let frameSkip = max(1, Int(Double(nominalFrameRate) / maxRefineRate))
        let maxFramesPerWindow = 30

        // Fresh landmarker for the refinement pass
        let landmarker = createLandmarker()

        Log.biomechanics.info(
            "Refining \(timestamps.count) contacts at \(String(format: "%.0f", nominalFrameRate))fps, skip \(frameSkip), ±\(String(format: "%.0f", windowSeconds * 1000))ms"
        )

        var allWindows: [[PoseFrame]] = []

        for timestamp in timestamps {
            try Task.checkCancellation()

            let startTime = max(0, timestamp - windowSeconds)
            let endTime = timestamp + windowSeconds
            let timeRange = CMTimeRange(
                start: CMTime(seconds: startTime, preferredTimescale: 600),
                end: CMTime(seconds: endTime, preferredTimescale: 600)
            )

            let reader = try AVAssetReader(asset: asset)
            reader.timeRange = timeRange

            let outputSettings: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            let output = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: outputSettings)
            output.alwaysCopiesSampleData = false
            reader.add(output)

            guard reader.startReading() else {
                Log.biomechanics.warning("  Window t=\(String(format: "%.3f", timestamp))s: reader failed to start")
                allWindows.append([])
                continue
            }

            var frames: [PoseFrame] = []
            var rawFrameCount = 0
            while let sampleBuffer = output.copyNextSampleBuffer() {
                try Task.checkCancellation()

                rawFrameCount += 1
                guard rawFrameCount % frameSkip == 0 else { continue }
                guard frames.count < maxFramesPerWindow else { break }

                let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                let frameTimestamp = CMTimeGetSeconds(pts)
                let frameIndex = Int(round(frameTimestamp * Double(nominalFrameRate)))

                if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                    let poseFrame: PoseFrame?
                    if let landmarker {
                        poseFrame = detectPoseMediaPipe(
                            in: pixelBuffer, frameIndex: frameIndex,
                            timestamp: frameTimestamp, landmarker: landmarker
                        )
                    } else {
                        poseFrame = try detectPoseVision(
                            in: pixelBuffer, frameIndex: frameIndex,
                            timestamp: frameTimestamp
                        )
                    }
                    if let poseFrame {
                        frames.append(poseFrame)
                    }
                }
                await Task.yield()
            }

            reader.cancelReading()
            allWindows.append(frames)

            Log.biomechanics.info(
                "  Window t=\(String(format: "%.3f", timestamp))s: \(frames.count) pose frames from \(rawFrameCount) raw"
            )
        }

        return allWindows
    }

    // MARK: - Video Metadata

    static func videoMetadata(for url: URL) async throws -> (duration: Double, fps: Double, frameCount: Int) {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)

        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw BiomechanicsError.noVideoTrack
        }

        let fps = Double(try await track.load(.nominalFrameRate))
        let frameCount = Int(fps * durationSeconds)

        return (durationSeconds, fps, frameCount)
    }
}

// MARK: - Errors

enum BiomechanicsError: LocalizedError {
    case alreadyProcessing
    case noVideoTrack
    case noPersonDetected
    case videoReadFailed(String)
    case insufficientFrames(Int)

    var errorDescription: String? {
        switch self {
        case .alreadyProcessing:
            return "A video is already being processed."
        case .noVideoTrack:
            return "No video track found in the selected file."
        case .noPersonDetected:
            return "No person was detected in the video. Make sure the full body is visible."
        case .videoReadFailed(let reason):
            return "Could not read video: \(reason)"
        case .insufficientFrames(let count):
            return "Only \(count) frames detected. Record at least 10 seconds of running."
        }
    }
}
