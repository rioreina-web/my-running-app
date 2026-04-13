//
//  BiomechanicsVideoCaptureView.swift
//  RunningLog
//
//  Video capture and import for biomechanics analysis.
//  Supports recording new video via camera or importing from photo library.
//

import AVFoundation
import PhotosUI
import SwiftUI

// MARK: - BiomechanicsVideoCaptureView

struct BiomechanicsVideoCaptureView: View {
    @Environment(\.dismiss) private var dismiss

    // Multi-clip state
    @State private var clips: [VideoClip] = []
    @State private var pendingVideoURL: URL?
    @State private var selectedViewAngle: ViewAngle = .sagittalLeft

    // Capture
    @State private var showPhotoPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isLoadingVideo = false

    // Quality
    @State private var processingQuality: ProcessingQuality = .fast

    // Presentation
    @State private var activeSheet: ActiveSheet?

    // Processing state
    @State private var isProcessing = false
    @State private var processingClipIndex = 0
    @State private var totalClipsCount = 0
    @State private var processingError: String?
    @State private var processingTask: Task<Void, Never>?

    // Results
    @State private var analysisResult: BiomechanicsAnalysis?

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

    let biomechanicsService: BiomechanicsService
    @State private var poseDetectionService = PoseDetectionService()

    /// Angles already used by existing clips
    private var usedAngles: Set<ViewAngle> {
        Set(clips.map(\.viewAngle))
    }

    /// Suggested next angle based on what's been captured
    private var suggestedAngle: ViewAngle {
        let priority: [ViewAngle] = [.sagittalLeft, .sagittalRight, .posterior, .frontal]
        return priority.first { !usedAngles.contains($0) } ?? .sagittalLeft
    }

    /// Angles not yet captured
    private var missingAngles: [ViewAngle] {
        ViewAngle.allCases.filter { !usedAngles.contains($0) }
    }

    /// Overall progress across all clips
    private var overallProgress: Double {
        guard totalClipsCount > 0 else { return 0 }
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
                } else if pendingVideoURL != nil {
                    viewAngleSelectionView
                } else if !clips.isEmpty {
                    clipListView
                } else {
                    captureSelectionView
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("NEW ANALYSIS")
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
            .fullScreenCover(item: $activeSheet) { sheet in
                switch sheet {
                case .camera:
                    VideoCameraView(videoURL: $pendingVideoURL, isPresented: $activeSheet)
                        .ignoresSafeArea()
                case .results:
                    if let result = analysisResult {
                        NavigationStack {
                            BiomechanicsResultsView(analysis: result)
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

    // MARK: - Capture Selection (first video)

    private var captureSelectionView: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "figure.run")
                .font(.system(size: 64))
                .foregroundStyle(Color.drip.coral.opacity(0.6))

            VStack(spacing: 12) {
                Text("Capture Your Running Form")
                    .font(.dripLabel(22))
                    .foregroundStyle(Color.drip.textPrimary)

                Text("Record or import videos from multiple angles for a comprehensive analysis. Start with a side view for best results.")
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

    // MARK: - View Angle Selection (assign angle to pending video)

    private var viewAngleSelectionView: some View {
        VStack(spacing: 32) {
            Spacer()

            if let pendingVideoURL {
                VideoThumbnailView(url: pendingVideoURL)
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 20)
            }

            VStack(spacing: 16) {
                Text("Camera Angle")
                    .font(.dripLabel(18))
                    .foregroundStyle(Color.drip.textPrimary)

                Text("Select how this video was filmed.")
                    .font(.dripBody(13))
                    .foregroundStyle(Color.drip.textSecondary)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(ViewAngle.allCases) { angle in
                        let alreadyUsed = usedAngles.contains(angle)
                        Button {
                            selectedViewAngle = angle
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: angle.icon)
                                    .font(.system(size: 16))
                                Text(angle.displayName)
                                    .font(.dripLabel(14))
                                if alreadyUsed {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color.drip.positive)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(selectedViewAngle == angle ? Color.drip.coral.opacity(0.15) : Color.drip.cardBackground)
                            .foregroundStyle(selectedViewAngle == angle ? Color.drip.coral : Color.drip.textSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(selectedViewAngle == angle ? Color.drip.coral.opacity(0.5) : Color.clear, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }

            // Add clip button
            DripButton("Add This Angle", icon: "plus.circle.fill", style: .primary) {
                addPendingClip()
            }
            .padding(.horizontal, 40)

            // Discard this video
            Button {
                pendingVideoURL = nil
                selectedPhotoItem = nil
            } label: {
                Text("Discard Video")
                    .font(.dripBody(13))
                    .foregroundStyle(Color.drip.textSecondary)
            }

            Spacer()
        }
    }

    // MARK: - Clip List (shows added clips, add more, or analyze)

    private var clipListView: some View {
        VStack(spacing: 20) {
            Spacer()

            // Clip count
            VStack(spacing: 8) {
                Image(systemName: "video.badge.checkmark")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.drip.coral.opacity(0.7))

                Text("\(clips.count) Video\(clips.count == 1 ? "" : "s") Added")
                    .font(.dripLabel(20))
                    .foregroundStyle(Color.drip.textPrimary)
            }

            // Clip cards
            VStack(spacing: 8) {
                ForEach(clips) { clip in
                    HStack(spacing: 12) {
                        VideoThumbnailView(url: clip.url)
                            .frame(width: 80, height: 50)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Image(systemName: clip.viewAngle.icon)
                                    .font(.system(size: 12))
                                Text(clip.viewAngle.displayName)
                                    .font(.dripLabel(14))
                            }
                            .foregroundStyle(Color.drip.textPrimary)

                            Text(clip.viewAngle.instruction)
                                .font(.dripCaption(11))
                                .foregroundStyle(Color.drip.textSecondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Button {
                            clips.removeAll { $0.id == clip.id }
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

            // Add more videos
            VStack(spacing: 12) {
                DripButton("Record Another Angle", icon: "video.fill.badge.plus", style: .secondary) {
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

            // Quality picker
            VStack(spacing: 8) {
                Text("PROCESSING QUALITY")
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textTertiary)
                    .tracking(1.5)

                HStack(spacing: 10) {
                    ForEach(ProcessingQuality.allCases) { quality in
                        Button {
                            processingQuality = quality
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: quality.icon)
                                    .font(.system(size: 18))
                                Text(quality.displayName)
                                    .font(.dripLabel(13))
                                Text(quality.subtitle)
                                    .font(.dripCaption(10))
                                    .foregroundStyle(processingQuality == quality ? Color.drip.coral.opacity(0.7) : Color.drip.textTertiary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(processingQuality == quality ? Color.drip.coral.opacity(0.12) : Color.drip.cardBackground)
                            .foregroundStyle(processingQuality == quality ? Color.drip.coral : Color.drip.textSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(processingQuality == quality ? Color.drip.coral.opacity(0.4) : Color.clear, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }

            // Analyze button
            DripButton("Analyze Running Form", icon: "wand.and.stars", style: .primary) {
                startProcessing()
            }
            .padding(.horizontal, 40)

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
                Text("Analyzing Your Form")
                    .font(.dripLabel(20))
                    .foregroundStyle(Color.drip.textPrimary)

                if totalClipsCount > 1 && overallProgress < 0.99 {
                    Text("Processing video \(processingClipIndex + 1) of \(totalClipsCount)...")
                        .font(.dripBody(14))
                        .foregroundStyle(Color.drip.textSecondary)
                } else if overallProgress >= 0.99 {
                    Text("Running AI form analysis...")
                        .font(.dripBody(14))
                        .foregroundStyle(Color.drip.textSecondary)
                } else {
                    Text("Detecting body pose and calculating joint angles...")
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
            // No camera (Simulator or restricted) — fall back to photo library
            showPhotoPicker = true
        }
    }

    // MARK: - Actions

    private func addPendingClip() {
        guard let url = pendingVideoURL else { return }
        clips.append(VideoClip(url: url, viewAngle: selectedViewAngle))
        pendingVideoURL = nil
        selectedPhotoItem = nil
        // Pre-select next suggested angle
        selectedViewAngle = suggestedAngle
    }

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
                    pendingVideoURL = videoData.url
                    isLoadingVideo = false
                    selectedViewAngle = suggestedAngle
                }
            } catch {
                await MainActor.run {
                    isLoadingVideo = false
                    processingError = "Failed to import video: \(error.localizedDescription)"
                }
            }
        }
    }

    private func startProcessing() {
        guard !clips.isEmpty else { return }
        isProcessing = true
        processingError = nil
        processingClipIndex = 0
        totalClipsCount = clips.count

        let clipsSnapshot = clips
        let service = biomechanicsService
        let sampleRate = processingQuality.sampleRate

        processingTask = Task {
            do {
                var allSummaries: [(summary: JointAnglesSummary, viewAngle: ViewAngle)] = []
                var allFootStrikes: [(analysis: FootStrikeAnalysis, viewAngle: ViewAngle)] = []
                var allGaitMetrics: [(metrics: GaitMetrics, viewAngle: ViewAngle)] = []
                var totalDuration: Double = 0
                var totalFrameCount = 0
                var primaryFPS: Double = 0

                for (index, clip) in clipsSnapshot.enumerated() {
                    try Task.checkCancellation()
                    await MainActor.run { processingClipIndex = index }

                    let metadata = try await PoseDetectionService.videoMetadata(for: clip.url)
                    try Task.checkCancellation()

                    // Short videos (< 3s) need every frame for reliable contact
                    // detection — override sample rate to native fps (capped at 30)
                    let effectiveRate = metadata.duration < 3.0
                        ? min(metadata.fps, 30.0)
                        : sampleRate
                    let poseFrames = try await poseDetectionService.processVideo(url: clip.url, sampleRate: effectiveRate)
                    try Task.checkCancellation()

                    // Skip clips with too few frames but don't fail the whole analysis
                    guard poseFrames.count >= 5 else { continue }

                    let jointAngles = BiomechanicsCalculator.computeSummary(frames: poseFrames)
                    allSummaries.append((jointAngles, clip.viewAngle))

                    // Foot strike: two-pass refinement at native fps
                    let fsSide = BiomechanicsCalculator.footStrikeSide(
                        viewAngle: clip.viewAngle, frames: poseFrames
                    )
                    let fsTimestamps = BiomechanicsCalculator.contactTimestamps(
                        frames: poseFrames, side: fsSide
                    )

                    var footStrike: FootStrikeAnalysis?
                    if !fsTimestamps.isEmpty {
                        let refinedWindows = try await poseDetectionService.refineAroundTimestamps(
                            url: clip.url, timestamps: fsTimestamps
                        )
                        footStrike = BiomechanicsCalculator.classifyFootStrikeRefined(
                            coarseFrames: poseFrames,
                            refinedWindows: refinedWindows,
                            side: fsSide
                        )
                    }
                    // Fall back to coarse classification if refinement didn't work
                    if footStrike == nil {
                        footStrike = BiomechanicsCalculator.computeFootStrike(
                            frames: poseFrames, viewAngle: clip.viewAngle
                        )
                    }

                    if let fs = footStrike {
                        allFootStrikes.append((fs, clip.viewAngle))
                    }

                    if let gaitMetrics = BiomechanicsCalculator.computeGaitMetrics(frames: poseFrames, viewAngle: clip.viewAngle) {
                        allGaitMetrics.append((gaitMetrics, clip.viewAngle))
                    }

                    totalDuration += metadata.duration
                    totalFrameCount += metadata.frameCount
                    if index == 0 { primaryFPS = metadata.fps }
                }

                try Task.checkCancellation()

                guard !allSummaries.isEmpty else {
                    throw BiomechanicsError.insufficientFrames(0)
                }

                // Merge results from all clips
                let mergedAngles = BiomechanicsCalculator.mergeSummaries(allSummaries)
                let bestFootStrike = BiomechanicsCalculator.bestFootStrike(allFootStrikes)
                let mergedGaitMetrics = BiomechanicsCalculator.mergeGaitMetrics(allGaitMetrics)

                // Save first clip's video as the primary local file
                let localFilename = try BiomechanicsService.saveVideoLocally(from: clipsSnapshot[0].url)

                try Task.checkCancellation()

                let analysisId = await service.createAnalysis(
                    localVideoFilename: localFilename,
                    viewAngle: clipsSnapshot[0].viewAngle,
                    durationSeconds: totalDuration,
                    frameCount: totalFrameCount,
                    fps: primaryFPS,
                    jointAngles: mergedAngles,
                    footStrike: bestFootStrike,
                    gaitMetrics: mergedGaitMetrics,
                    notes: clipsSnapshot.count > 1
                        ? "Combined from \(clipsSnapshot.count) angles: \(clipsSnapshot.map(\.viewAngle.displayName).joined(separator: ", "))"
                        : nil
                )

                guard let analysisId else {
                    await MainActor.run {
                        isProcessing = false
                        processingError = service.errorMessage ?? "Failed to save analysis."
                    }
                    return
                }

                try Task.checkCancellation()

                // Use fetched analysis if available, otherwise build from local data
                var analysis = service.analyses.first(where: { $0.id == analysisId })
                    ?? BiomechanicsAnalysis(
                        id: analysisId,
                        userId: AuthManager.shared.currentUserId ?? "",
                        videoStoragePath: nil,
                        localVideoFilename: localFilename,
                        recordedAt: Date(),
                        durationSeconds: totalDuration,
                        frameCount: totalFrameCount,
                        fps: primaryFPS,
                        viewAngle: clipsSnapshot[0].viewAngle,
                        status: .completed,
                        jointAngles: mergedAngles,
                        footStrike: bestFootStrike,
                        gaitMetrics: mergedGaitMetrics,
                        aiAnalysis: nil,
                        aiAnalysisAt: nil,
                        linkedInjuryId: nil,
                        notes: clipsSnapshot.count > 1
                            ? "Combined from \(clipsSnapshot.count) angles: \(clipsSnapshot.map(\.viewAngle.displayName).joined(separator: ", "))"
                            : nil,
                        createdAt: Date(),
                        updatedAt: Date()
                    )

                // Auto-trigger AI analysis
                if let aiResult = await service.requestAIAnalysis(analysisId: analysisId) {
                    analysis.aiAnalysis = aiResult
                    analysis.aiAnalysisAt = Date()
                }

                await MainActor.run {
                    analysisResult = analysis
                    isProcessing = false
                    activeSheet = .results
                }
            } catch is CancellationError {
                await MainActor.run {
                    isProcessing = false
                }
            } catch {
                await MainActor.run {
                    isProcessing = false
                    processingError = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - VideoTransferable

struct VideoTransferable: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let tempDir = FileManager.default.temporaryDirectory
            let filename = "\(UUID().uuidString).mov"
            let destination = tempDir.appendingPathComponent(filename)
            try FileManager.default.copyItem(at: received.file, to: destination)
            return VideoTransferable(url: destination)
        }
    }
}

// MARK: - VideoCameraView (UIImagePickerController wrapper)

struct VideoCameraView: UIViewControllerRepresentable {
    @Binding var videoURL: URL?
    @Binding var isPresented: BiomechanicsVideoCaptureView.ActiveSheet?

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
        let parent: VideoCameraView

        init(_ parent: VideoCameraView) {
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

// MARK: - VideoThumbnailView

struct VideoThumbnailView: View {
    let url: URL
    @State private var thumbnail: UIImage?

    var body: some View {
        Group {
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(Color.drip.cardBackground)
                    .overlay {
                        Image(systemName: "film")
                            .font(.system(size: 32))
                            .foregroundStyle(Color.drip.textTertiary)
                    }
            }
        }
        .task {
            thumbnail = await generateThumbnail(from: url)
        }
    }

    private func generateThumbnail(from url: URL) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 600, height: 400)

        let time = CMTime(seconds: 1, preferredTimescale: 600)
        do {
            let (cgImage, _) = try await generator.image(at: time)
            return UIImage(cgImage: cgImage)
        } catch {
            return nil
        }
    }
}
