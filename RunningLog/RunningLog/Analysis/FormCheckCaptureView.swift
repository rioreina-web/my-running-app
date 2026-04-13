//
//  FormCheckCaptureView.swift
//  RunningLog
//
//  Multi-angle video capture for qualitative form check.
//  Auto-detects camera angle, merges data from multiple clips,
//  then runs AI analysis on the combined results.
//

import AVFoundation
import os
import PhotosUI
import SwiftUI

struct FormCheckCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    let formCheckService: FormCheckService

    @State private var poseDetectionService = PoseDetectionService()

    // Multi-clip state
    @State private var clips: [URL] = []
    @State private var pendingVideoURL: URL?
    @State private var activeSheet: ActiveSheet?
    @State private var showPhotoPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isLoadingVideo = false

    // Processing state
    @State private var isProcessing = false
    @State private var processingError: String?
    @State private var processingTask: Task<Void, Never>?
    @State private var processingClipIndex = 0
    @State private var totalClipsCount = 0

    // Results
    @State private var formCheckResult: FormCheck?

    enum ActiveSheet: Identifiable {
        case camera
        case results

        var id: String {
            switch self {
            case .camera: return "camera"
            case .results: return "results"
            }
        }
    }

    private var overallProgress: Double {
        guard totalClipsCount > 0 else { return poseDetectionService.progress }
        let base = Double(processingClipIndex) / Double(totalClipsCount)
        let current = poseDetectionService.progress / Double(totalClipsCount)
        return base + current
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.drip.background.ignoresSafeArea()

                if isProcessing || processingError != nil {
                    processingView
                } else if !clips.isEmpty {
                    clipListView
                } else {
                    captureSelectionView
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
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        processingTask?.cancel()
                        poseDetectionService.cancel()
                        activeSheet = nil
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color.drip.textSecondary)
                    }
                }
            }
            .toolbarBackground(Color.drip.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .fullScreenCover(item: $activeSheet, onDismiss: {
                // Move pending camera result into clips AFTER dismiss animation completes
                if let url = pendingVideoURL {
                    clips.append(url)
                    pendingVideoURL = nil
                }
            }) { sheet in
                switch sheet {
                case .camera:
                    FormCheckCameraView(videoURL: $pendingVideoURL, isPresented: $activeSheet)
                        .ignoresSafeArea()
                case .results:
                    if let result = formCheckResult {
                        NavigationStack {
                            FormCheckResultsView(formCheck: result, formCheckService: formCheckService)
                                .toolbar {
                                    ToolbarItem(placement: .topBarLeading) {
                                        Button {
                                            activeSheet = nil
                                            dismiss()
                                        } label: {
                                            Image(systemName: "xmark")
                                                .font(.system(size: 16, weight: .medium))
                                                .foregroundStyle(Color.drip.textSecondary)
                                        }
                                    }
                                }
                        }
                    }
                }
            }
            .photosPicker(
                isPresented: $showPhotoPicker,
                selection: $selectedPhotoItem,
                matching: .videos
            )
            .onChange(of: selectedPhotoItem) { _, newItem in
                if let newItem {
                    loadVideo(from: newItem)
                }
            }
        }
    }

    // MARK: - Capture Selection

    private var captureSelectionView: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "figure.run.circle")
                .font(.system(size: 64))
                .foregroundStyle(Color.drip.coral.opacity(0.6))

            VStack(spacing: 12) {
                Text("Quick Form Check")
                    .font(.dripLabel(22))
                    .foregroundStyle(Color.drip.textPrimary)

                Text("Record yourself running from any angle. Add multiple angles for a more complete analysis.")
                    .font(.dripBody(14))
                    .foregroundStyle(Color.drip.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            VStack(spacing: 12) {
                DripButton("Record Video", icon: "video.fill", style: .primary) {
                    openCamera()
                }
                .padding(.horizontal, 40)

                DripButton("Import from Library", icon: "photo.on.rectangle", style: .secondary) {
                    selectedPhotoItem = nil
                    showPhotoPicker = true
                }
                .padding(.horizontal, 40)
            }

            if isLoadingVideo {
                ProgressView("Loading video...")
                    .tint(Color.drip.coral)
                    .foregroundStyle(Color.drip.textSecondary)
            }

            Spacer()
            Spacer()
        }
    }

    // MARK: - Clip List

    private var clipListView: some View {
        VStack(spacing: 24) {
            Spacer()

            // Clip cards
            VStack(spacing: 10) {
                ForEach(Array(clips.enumerated()), id: \.offset) { index, url in
                    HStack(spacing: 12) {
                        VideoThumbnailView(url: url)
                            .frame(width: 80, height: 50)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Video \(index + 1)")
                                .font(.dripLabel(14))
                                .foregroundStyle(Color.drip.textPrimary)

                            Text("Angle auto-detected")
                                .font(.dripCaption(11))
                                .foregroundStyle(Color.drip.textTertiary)
                        }

                        Spacer()

                        Button {
                            clips.remove(at: index)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(Color.drip.textTertiary)
                        }
                    }
                    .padding(12)
                    .background(Color.drip.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.horizontal, 20)

            // Add more
            HStack(spacing: 12) {
                Button {
                    openCamera()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "video.fill.badge.plus")
                            .font(.system(size: 13))
                        Text("Record Another Angle")
                            .font(.dripBody(13))
                    }
                    .foregroundStyle(Color.drip.coral)
                }

                Text("|")
                    .foregroundStyle(Color.drip.textTertiary)
                    .font(.dripCaption(11))

                Button {
                    selectedPhotoItem = nil
                    showPhotoPicker = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 13))
                        Text("Import")
                            .font(.dripBody(13))
                    }
                    .foregroundStyle(Color.drip.coral)
                }
            }

            if isLoadingVideo {
                ProgressView("Loading video...")
                    .tint(Color.drip.coral)
                    .foregroundStyle(Color.drip.textSecondary)
            }

            // Analyze button
            VStack(spacing: 8) {
                DripButton("Analyze Form", icon: "wand.and.stars", style: .primary) {
                    startProcessing()
                }
                .padding(.horizontal, 40)

                if clips.count == 1 {
                    Text("Add more angles for a fuller picture")
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.textTertiary)
                } else {
                    Text("\(clips.count) videos — angles will be auto-detected")
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.textSecondary)
                }
            }

            Spacer()
        }
    }

    // MARK: - Processing View

    private var processingView: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "figure.run")
                .font(.system(size: 56))
                .foregroundStyle(Color.drip.coral)
                .symbolEffect(.pulse)

            VStack(spacing: 12) {
                Text("Checking Your Form")
                    .font(.dripLabel(20))
                    .foregroundStyle(Color.drip.textPrimary)

                if overallProgress >= 0.99 {
                    Text("Running AI form analysis...")
                        .font(.dripBody(14))
                        .foregroundStyle(Color.drip.textSecondary)
                } else if totalClipsCount > 1 {
                    Text("Processing video \(processingClipIndex + 1) of \(totalClipsCount)...")
                        .font(.dripBody(14))
                        .foregroundStyle(Color.drip.textSecondary)
                } else {
                    Text("Detecting body pose...")
                        .font(.dripBody(14))
                        .foregroundStyle(Color.drip.textSecondary)
                }
            }

            VStack(spacing: 8) {
                ProgressView(value: overallProgress)
                    .tint(Color.drip.coral)
                    .scaleEffect(y: 2.0)
                    .padding(.horizontal, 60)

                Text("\(Int(overallProgress * 100))%")
                    .font(.dripCaption(12))
                    .foregroundStyle(Color.drip.textSecondary)
            }

            if let error = processingError {
                Text(error)
                    .font(.dripBody(13))
                    .foregroundStyle(Color.drip.injured)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                DripButton("Try Again", icon: "arrow.clockwise", style: .secondary) {
                    processingError = nil
                    startProcessing()
                }
                .padding(.horizontal, 60)
            }

            Button {
                processingTask?.cancel()
                poseDetectionService.cancel()
                isProcessing = false
                processingError = nil
            } label: {
                Text(processingError != nil ? "Back" : "Cancel")
                    .font(.dripBody(14))
                    .foregroundStyle(Color.drip.textSecondary)
            }

            Spacer()
            Spacer()
        }
    }

    // MARK: - Camera

    private var isCameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    private func openCamera() {
        if isCameraAvailable {
            activeSheet = .camera
        } else {
            showPhotoPicker = true
        }
    }

    // MARK: - Video Import

    private func loadVideo(from item: PhotosPickerItem) {
        isLoadingVideo = true
        Task {
            do {
                guard let videoData = try await item.loadTransferable(type: VideoTransferable.self) else {
                    await MainActor.run {
                        isLoadingVideo = false
                        processingError = "Could not load the selected video."
                    }
                    return
                }
                await MainActor.run {
                    clips.append(videoData.url)
                    isLoadingVideo = false
                }
            } catch {
                await MainActor.run {
                    isLoadingVideo = false
                    processingError = "Failed to import video: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Processing Pipeline (Multi-Clip)

    private func startProcessing() {
        guard !clips.isEmpty else { return }
        isProcessing = true
        processingError = nil
        processingClipIndex = 0
        totalClipsCount = clips.count

        let clipURLs = clips
        let service = formCheckService

        processingTask = Task {
            do {
                var allSummaries: [(summary: JointAnglesSummary, viewAngle: ViewAngle)] = []
                var allFootStrikes: [(analysis: FootStrikeAnalysis, viewAngle: ViewAngle)] = []
                var allGaitMetrics: [(metrics: GaitMetrics, viewAngle: ViewAngle)] = []
                var trunkLeans: [Double] = []
                var headOffsets: [Double] = []
                var armSymmetries: [Double] = []
                var bestFatigue: (trunkLeanEarly: Double?, trunkLeanLate: Double?,
                                  cadenceEarly: Double?, cadenceLate: Double?) = (nil, nil, nil, nil)
                var longestClipFrameCount = 0
                var totalDuration: Double = 0
                var totalFrameCount = 0
                var primaryFPS: Double = 0

                Log.biomechanics.info("[FormCheck] Starting processing for \(clipURLs.count) clip(s)")

                // Process each clip
                for (index, url) in clipURLs.enumerated() {
                    try Task.checkCancellation()
                    await MainActor.run { processingClipIndex = index }

                    // 1. Extract video metadata
                    let metadata = try await PoseDetectionService.videoMetadata(for: url)
                    Log.biomechanics.info("[FormCheck] Clip \(index + 1): \(metadata.duration)s, \(metadata.fps)fps")

                    // 30 fps gives ~33ms between frames — enough to capture
                    // foot strike transitions (~20ms) and ground contact (~200ms).
                    // Previous 10 fps was too coarse for accurate foot strike classification.
                    let effectiveRate = min(metadata.fps, 30.0)

                    // 2. Extract pose frames
                    let frames = try await poseDetectionService.processVideo(url: url, sampleRate: effectiveRate)
                    Log.biomechanics.info("[FormCheck] Clip \(index + 1): \(frames.count) pose frames")

                    guard frames.count >= 5 else {
                        Log.biomechanics.warning("[FormCheck] Clip \(index + 1): insufficient frames (\(frames.count)), skipping")
                        continue
                    }

                    // 3. Auto-detect view angle
                    let viewAngle = BiomechanicsCalculator.detectViewAngle(frames: frames)
                    Log.biomechanics.info("[FormCheck] Clip \(index + 1): detected angle = \(viewAngle.rawValue)")

                    // 4. Compute metrics tagged with view angle
                    let summary = BiomechanicsCalculator.computeSummary(frames: frames)
                    allSummaries.append((summary, viewAngle))

                    // 4b. Refined foot strike: use dense frames around contact points
                    let fsSide = BiomechanicsCalculator.footStrikeSide(viewAngle: viewAngle, frames: frames)
                    let contactTs = BiomechanicsCalculator.contactTimestamps(frames: frames, side: fsSide)
                    if !contactTs.isEmpty {
                        let refinedWindows = try await poseDetectionService.refineAroundTimestamps(
                            url: url, timestamps: contactTs
                        )
                        if let refinedFS = BiomechanicsCalculator.classifyFootStrikeRefined(
                            coarseFrames: frames, refinedWindows: refinedWindows, side: fsSide
                        ) {
                            allFootStrikes.append((refinedFS, viewAngle))
                        } else if let fs = BiomechanicsCalculator.computeFootStrike(frames: frames, viewAngle: viewAngle) {
                            allFootStrikes.append((fs, viewAngle))
                        }
                    } else if let fs = BiomechanicsCalculator.computeFootStrike(frames: frames, viewAngle: viewAngle) {
                        allFootStrikes.append((fs, viewAngle))
                    }
                    if let gm = BiomechanicsCalculator.computeGaitMetrics(frames: frames, viewAngle: viewAngle) {
                        allGaitMetrics.append((gm, viewAngle))
                    }

                    // 5. Qualitative posture metrics
                    if let t = BiomechanicsCalculator.computeTrunkLean(frames: frames) { trunkLeans.append(t) }
                    if let h = BiomechanicsCalculator.computeHeadForwardOffset(frames: frames) { headOffsets.append(h) }
                    // Only compute arm swing from frontal/posterior — both arms equally visible
                    if viewAngle == .frontal || viewAngle == .posterior {
                        if let a = BiomechanicsCalculator.computeArmSwingSymmetry(frames: frames) { armSymmetries.append(a) }
                    }

                    // 5b. Fatigue analysis (use longest clip for best temporal resolution)
                    if frames.count > longestClipFrameCount {
                        longestClipFrameCount = frames.count
                        bestFatigue = BiomechanicsCalculator.computeFatigueIndicators(frames: frames)
                    }

                    totalDuration += metadata.duration
                    totalFrameCount += metadata.frameCount
                    if index == 0 { primaryFPS = metadata.fps }
                }

                try Task.checkCancellation()

                // 6. Merge results from all clips
                let merged = BiomechanicsCalculator.mergeSummaries(allSummaries)
                let bestFS = BiomechanicsCalculator.bestFootStrike(allFootStrikes)
                let mergedGait = BiomechanicsCalculator.mergeGaitMetrics(allGaitMetrics)

                let avgTrunk = trunkLeans.isEmpty ? nil : trunkLeans.reduce(0, +) / Double(trunkLeans.count)
                let avgHead = headOffsets.isEmpty ? nil : headOffsets.reduce(0, +) / Double(headOffsets.count)
                let avgArm = armSymmetries.isEmpty ? nil : armSymmetries.reduce(0, +) / Double(armSymmetries.count)

                Log.biomechanics.info("[FormCheck] Merged: hipL=\(merged.hipLeft?.rangeOfMotion ?? -1), hipR=\(merged.hipRight?.rangeOfMotion ?? -1), footStrike=\(bestFS?.pattern.rawValue ?? "nil"), trunk=\(avgTrunk ?? -1)")

                // 7. Build pose data summary for AI
                let poseData = FormCheckPoseData(
                    hipROMLeft: merged.hipLeft?.rangeOfMotion,
                    hipROMRight: merged.hipRight?.rangeOfMotion,
                    kneeROMLeft: merged.kneeLeft?.rangeOfMotion,
                    kneeROMRight: merged.kneeRight?.rangeOfMotion,
                    ankleROMLeft: merged.ankleLeft?.rangeOfMotion,
                    ankleROMRight: merged.ankleRight?.rangeOfMotion,
                    shoulderRotationROM: merged.shoulderRotation?.rangeOfMotion,
                    footStrikePattern: bestFS?.pattern.rawValue,
                    footStrikeConfidence: bestFS?.confidence,
                    heelVsForefoot: bestFS?.heelVsForefoot,
                    shankAngleAtContact: bestFS?.shankAngleAtContact,
                    contactCount: bestFS?.frameIndices?.count,
                    gctLeft: mergedGait?.groundContactTimeLeft,
                    gctRight: mergedGait?.groundContactTimeRight,
                    gctBalance: mergedGait?.groundContactBalance,
                    avgTrunkLean: avgTrunk,
                    headForwardOffset: avgHead,
                    armSwingSymmetry: avgArm,
                    shankAtContactLeft: merged.shankLeft?.atInitialContact,
                    shankAtContactRight: merged.shankRight?.atInitialContact,
                    cadence: mergedGait?.cadence,
                    trunkLeanEarly: bestFatigue.trunkLeanEarly,
                    trunkLeanLate: bestFatigue.trunkLeanLate,
                    cadenceEarly: bestFatigue.cadenceEarly,
                    cadenceLate: bestFatigue.cadenceLate
                )

                // 8. Save first clip's video locally
                let localFilename = try BiomechanicsService.saveVideoLocally(from: clipURLs[0])
                Log.biomechanics.info("[FormCheck] Saved primary video as \(localFilename)")
                try Task.checkCancellation()

                // 9. Save to Supabase
                let anglesUsed = allSummaries.map { $0.viewAngle.displayName }
                let notes = clipURLs.count > 1
                    ? "Combined from \(clipURLs.count) angles: \(anglesUsed.joined(separator: ", "))"
                    : nil

                let formCheckId = await service.createFormCheck(
                    localVideoFilename: localFilename,
                    durationSeconds: totalDuration,
                    frameCount: totalFrameCount,
                    fps: primaryFPS,
                    poseDataSummary: poseData,
                    notes: notes
                )

                guard let formCheckId else {
                    Log.biomechanics.error("[FormCheck] Failed to create form check in Supabase")
                    await MainActor.run {
                        isProcessing = false
                        processingError = service.errorMessage ?? "Failed to save form check."
                    }
                    return
                }

                Log.biomechanics.info("[FormCheck] Created form check \(formCheckId)")
                try Task.checkCancellation()

                // 10. Auto-trigger AI analysis
                var formCheck = service.formChecks.first(where: { $0.id == formCheckId })
                    ?? FormCheck(
                        id: formCheckId,
                        userId: AuthManager.shared.currentUserId ?? "",
                        localVideoFilename: localFilename,
                        recordedAt: Date(),
                        durationSeconds: totalDuration,
                        frameCount: totalFrameCount,
                        fps: primaryFPS,
                        status: .completed,
                        poseDataSummary: poseData,
                        aiAnalysis: nil,
                        aiAnalysisAt: nil,
                        notes: notes,
                        createdAt: Date(),
                        updatedAt: Date()
                    )

                if let aiResult = await service.requestAIAnalysis(formCheckId: formCheckId) {
                    formCheck.aiAnalysis = aiResult
                    formCheck.aiAnalysisAt = Date()
                    Log.biomechanics.info("[FormCheck] AI analysis completed")
                } else {
                    Log.biomechanics.warning("[FormCheck] AI analysis returned nil, showing results without AI")
                }

                await MainActor.run {
                    formCheckResult = formCheck
                    isProcessing = false
                    activeSheet = .results
                }
            } catch is CancellationError {
                Log.biomechanics.info("[FormCheck] Processing cancelled")
                await MainActor.run {
                    isProcessing = false
                }
            } catch {
                Log.biomechanics.error("[FormCheck] Processing failed: \(error)")
                await MainActor.run {
                    isProcessing = false
                    processingError = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - FormCheckCameraView (UIImagePickerController wrapper)

struct FormCheckCameraView: UIViewControllerRepresentable {
    @Binding var videoURL: URL?
    @Binding var isPresented: FormCheckCaptureView.ActiveSheet?

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = ["public.movie"]
        picker.videoMaximumDuration = 60
        picker.videoQuality = .typeHigh
        picker.cameraCaptureMode = .video
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: FormCheckCameraView

        init(_ parent: FormCheckCameraView) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let url = info[.mediaURL] as? URL {
                parent.videoURL = url
            }
            parent.isPresented = nil
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.isPresented = nil
        }
    }
}
