//
//  BiomechanicsListView.swift
//  RunningLog
//
//  Entry point for biomechanics feature — lists past analyses
//  and provides access to new video capture.
//

import os
import SwiftUI

// MARK: - BiomechanicsListView

struct BiomechanicsListView: View {
    @State private var biomechanicsService = BiomechanicsService()
    @State private var selectedAnalysis: BiomechanicsAnalysis?
    @State private var showNewAnalysis = false
    #if DEBUG
    @State private var isRunningTest = false
    @State private var testProgress: Double = 0
    #endif

    var body: some View {
        ZStack {
            Color.drip.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    // Disclaimer
                    MedicalDisclaimerBanner(text: BiomechanicsDisclaimer.analysis, isCompact: true)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                    // Completed analyses
                    if !biomechanicsService.completedAnalyses.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader("Analyses (\(biomechanicsService.completedAnalyses.count))")
                                .padding(.horizontal, 20)

                            LazyVStack(spacing: 10) {
                                ForEach(biomechanicsService.completedAnalyses) { analysis in
                                    AnalysisCard(analysis: analysis)
                                        .onTapGesture { selectedAnalysis = analysis }
                                        .contextMenu {
                                            Button(role: .destructive) {
                                                Task { _ = await biomechanicsService.deleteAnalysis(id: analysis.id) }
                                            } label: {
                                                Label("Delete Analysis", systemImage: "trash")
                                            }
                                        }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }

                    // Empty state
                    if biomechanicsService.analyses.isEmpty && !biomechanicsService.isLoading {
                        VStack(spacing: 16) {
                            Image(systemName: "figure.run")
                                .font(.system(size: 48))
                                .foregroundStyle(Color.drip.coral.opacity(0.5))

                            Text("No analyses yet")
                                .font(.dripBody(16))
                                .foregroundStyle(Color.drip.textSecondary)

                            Text("Record or import a video of yourself running to analyze your form, joint angles, and foot strike pattern.")
                                .font(.dripBody(13))
                                .foregroundStyle(Color.drip.textTertiary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)

                            DripButton( "Analyze Your Form", icon: "video.fill", style: .primary) {
                                showNewAnalysis = true
                            }
                            .padding(.horizontal, 60)
                        }
                        .padding(.top, 60)
                    }

                    Spacer().frame(height: 80)
                }
            }

            // Floating add button (shown when there are existing analyses)
            if !biomechanicsService.analyses.isEmpty {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            showNewAnalysis = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 56, height: 56)
                                .background(Color.drip.coral)
                                .clipShape(Circle())
                                .shadow(color: Color.drip.coral.opacity(0.4), radius: 8, y: 4)
                        }
                        .padding(.trailing, 24)
                        .padding(.bottom, 24)
                    }
                }
            }

            if biomechanicsService.isLoading {
                ProgressView()
                    .tint(Color.drip.coral)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("BIOMECHANICS")
                    .font(.dripCaption(12))
                    .foregroundStyle(Color.drip.textSecondary)
                    .tracking(2)
            }
        }
        .toolbarBackground(Color.drip.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        #if DEBUG
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    runBundledVideoTest()
                } label: {
                    Image(systemName: isRunningTest ? "gear" : "play.circle")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.drip.coral)
                        .symbolEffect(.rotate, isActive: isRunningTest)
                }
                .disabled(isRunningTest)
            }
        }
        #endif
        .onAppear {
            Task { await biomechanicsService.fetchAnalyses() }
        }
        .sheet(item: $selectedAnalysis) { analysis in
            NavigationStack {
                BiomechanicsResultsView(analysis: analysis)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                selectedAnalysis = nil
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(Color.drip.textSecondary)
                            }
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(role: .destructive) {
                                let id = analysis.id
                                selectedAnalysis = nil
                                Task { _ = await biomechanicsService.deleteAnalysis(id: id) }
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(Color.drip.injured)
                            }
                        }
                    }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $showNewAnalysis) {
            BiomechanicsVideoCaptureView(biomechanicsService: biomechanicsService)
        }
    }

    // MARK: - Debug Video Test

    #if DEBUG
    private func runBundledVideoTest() {
        guard let videoURL = Bundle.main.url(forResource: "Shannon", withExtension: "mov") else {
            Log.biomechanics.error("Shannon.mov not found in app bundle")
            return
        }

        isRunningTest = true
        let poseService = PoseDetectionService()

        Task {
            do {
                Log.biomechanics.info("=== STARTING BUNDLED VIDEO TEST (Shannon.mov) ===")

                let metadata = try await PoseDetectionService.videoMetadata(for: videoURL)
                Log.biomechanics.info("Video: \(String(format: "%.1f", metadata.duration))s, \(String(format: "%.0f", metadata.fps))fps, \(metadata.frameCount) frames")

                let frames = try await poseService.processVideo(url: videoURL, sampleRate: 10.0)
                Log.biomechanics.info("Extracted \(frames.count) pose frames")

                let fps = BiomechanicsCalculator.effectiveSampleRate(frames: frames)
                Log.biomechanics.info("Effective sample rate: \(String(format: "%.1f", fps)) fps")

                // Running direction
                let runDir = BiomechanicsCalculator.inferRunningDirection(frames: frames)
                Log.biomechanics.info("Running direction: \(runDir.map { "(\(String(format: "%.3f", $0.x)), \(String(format: "%.3f", $0.y)), \(String(format: "%.3f", $0.z)))" } ?? "nil")")

                // Joint angles summary
                let summary = BiomechanicsCalculator.computeSummary(frames: frames)
                logJointData("Left Hip", summary.hipLeft)
                logJointData("Right Hip", summary.hipRight)
                logJointData("Left Knee", summary.kneeLeft)
                logJointData("Right Knee", summary.kneeRight)
                logShankData("Left Shank", summary.shankLeft)
                logShankData("Right Shank", summary.shankRight)

                if let rot = summary.shoulderRotation {
                    Log.biomechanics.info("Shoulder Rotation — mean: \(String(format: "%.1f", rot.meanRotation))°, peak: \(String(format: "%.1f", rot.peakRotation))°, ROM: \(String(format: "%.1f", rot.rangeOfMotion))°")
                }

                // Foot strike — coarse pass first
                let coarseFootStrike = BiomechanicsCalculator.computeFootStrike(frames: frames, viewAngle: .sagittalLeft)
                if let fs = coarseFootStrike {
                    Log.biomechanics.info("""
                    === FOOT STRIKE (COARSE 10fps) ===
                      Pattern: \(fs.pattern.rawValue)
                      Confidence: \(String(format: "%.0f", fs.confidence * 100))%
                      Shank at contact: \(fs.shankAngleAtContact.map { String(format: "%.1f°", $0) } ?? "nil")
                      Contact frames: \(fs.frameIndices?.count ?? 0)
                    """)
                } else {
                    Log.biomechanics.warning("Foot strike (coarse): could not classify")
                }

                // Foot strike — two-pass refinement at native fps
                let fsSide = BiomechanicsCalculator.footStrikeSide(viewAngle: .sagittalLeft, frames: frames)
                let fsTimestamps = BiomechanicsCalculator.contactTimestamps(frames: frames, side: fsSide)
                var footStrike = coarseFootStrike

                if !fsTimestamps.isEmpty {
                    Log.biomechanics.info("=== REFINING \(fsTimestamps.count) contacts at native fps ===")
                    let refinedWindows = try await poseService.refineAroundTimestamps(
                        url: videoURL, timestamps: fsTimestamps
                    )
                    if let refined = BiomechanicsCalculator.classifyFootStrikeRefined(
                        coarseFrames: frames, refinedWindows: refinedWindows, side: fsSide
                    ) {
                        footStrike = refined
                        Log.biomechanics.info("""
                        === FOOT STRIKE (REFINED native fps) ===
                          Pattern: \(refined.pattern.rawValue)
                          Confidence: \(String(format: "%.0f", refined.confidence * 100))%
                          Shank at contact: \(refined.shankAngleAtContact.map { String(format: "%.1f°", $0) } ?? "nil")
                          Contact frames: \(refined.frameIndices?.count ?? 0)
                        """)
                    } else {
                        Log.biomechanics.warning("Foot strike refinement failed, using coarse result")
                    }
                }

                // Contact event details (IC + mid-stance minimum)
                Log.biomechanics.info("=== CONTACT EVENT DETAILS (left) ===")
                let allAnkleY: [Double] = frames.compactMap { f in
                    guard let a = f.jointPosition(named: "leftAnkle") else { return nil }
                    return Double(a.y)
                }
                let totalRange = (allAnkleY.max() ?? 0) - (allAnkleY.min() ?? 0)
                let contactFrames = BiomechanicsCalculator.detectInitialContactFrames(frames: frames, side: "left")
                for (i, cf) in contactFrames.enumerated() {
                    let shank = BiomechanicsCalculator.shankAngle(frame: cf, side: "left", runDirection: runDir)
                    let kneeFlex = BiomechanicsCalculator.kneeFlexion(frame: cf, side: "left")
                    let ankle = cf.jointPosition(named: "leftAnkle")
                    Log.biomechanics.info("""
                    Contact \(i): frame \(cf.frameIndex), t=\(String(format: "%.3f", cf.timestamp))s
                      ankle pos: \(ankle.map { "(\(String(format: "%.4f", $0.x)), \(String(format: "%.4f", $0.y)), \(String(format: "%.4f", $0.z)))" } ?? "nil")
                      shank angle: \(shank.map { String(format: "%.1f°", $0) } ?? "nil")
                      knee flexion: \(kneeFlex.map { String(format: "%.1f°", $0) } ?? "nil")
                    """)
                }
                Log.biomechanics.info("Total ankle Y range: \(String(format: "%.4f", totalRange))")

                // GCT
                let gait = BiomechanicsCalculator.computeGaitMetrics(frames: frames, viewAngle: .sagittalLeft)
                if let g = gait {
                    Log.biomechanics.info("GCT: \(g.groundContactTime.map { String(format: "%.0f ms", $0) } ?? "nil"), left: \(g.groundContactTimeLeft.map { String(format: "%.0f ms", $0) } ?? "nil")")
                }

                // Ankle Y trajectory for debugging
                let ankleYs = frames.compactMap { f -> String? in
                    guard let a = f.jointPosition(named: "leftAnkle") else { return nil }
                    return String(format: "%.4f", a.y)
                }
                Log.biomechanics.info("Ankle Y trajectory (left, \(ankleYs.count) pts): [\(ankleYs.joined(separator: ", "))]")

                Log.biomechanics.info("=== TEST COMPLETE ===")

                // Build a local analysis to show results view with overlay
                let testAnalysis = BiomechanicsAnalysis(
                    id: UUID(),
                    userId: "debug",
                    videoStoragePath: nil,
                    localVideoFilename: nil,
                    recordedAt: Date(),
                    durationSeconds: metadata.duration,
                    frameCount: frames.count,
                    fps: metadata.fps,
                    viewAngle: .sagittalLeft,
                    status: .completed,
                    jointAngles: summary,
                    footStrike: footStrike,
                    gaitMetrics: gait,
                    aiAnalysis: nil,
                    aiAnalysisAt: nil,
                    linkedInjuryId: nil,
                    notes: "Debug test — Shannon.mov",
                    createdAt: Date(),
                    updatedAt: Date()
                )
                await MainActor.run {
                    selectedAnalysis = testAnalysis
                }
            } catch {
                Log.biomechanics.error("Test failed: \(error.localizedDescription)")
            }
            await MainActor.run { isRunningTest = false }
        }
    }

    private func logJointData(_ name: String, _ data: JointAngleData?) {
        guard let d = data else {
            Log.biomechanics.info("\(name): no data")
            return
        }
        Log.biomechanics.info("\(name) — ROM: \(String(format: "%.1f", d.rangeOfMotion))°, mean: \(String(format: "%.1f", d.meanAngle))°, min: \(String(format: "%.1f", d.minAngle))°, max: \(String(format: "%.1f", d.maxAngle))°")
    }

    private func logShankData(_ name: String, _ data: ShankAngleData?) {
        guard let d = data else {
            Log.biomechanics.info("\(name): no data")
            return
        }
        Log.biomechanics.info("\(name) — at contact: \(d.atInitialContact.map { String(format: "%.1f°", $0) } ?? "nil"), mean: \(String(format: "%.1f", d.meanAngle))°, min: \(String(format: "%.1f", d.minAngle))°, max: \(String(format: "%.1f", d.maxAngle))°")
    }
    #endif
}

// MARK: - AnalysisCard

private struct AnalysisCard: View {
    let analysis: BiomechanicsAnalysis

    var body: some View {
        VStack(spacing: 12) {
            // Top row: date and view angle
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(analysis.displayDate)
                        .font(.dripLabel(15))
                        .foregroundStyle(Color.drip.textPrimary)

                    HStack(spacing: 6) {
                        Image(systemName: analysis.viewAngle.icon)
                            .font(.system(size: 10))
                        Text(analysis.viewAngle.displayName)
                            .font(.dripCaption(11))
                    }
                    .foregroundStyle(Color.drip.textTertiary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.drip.textTertiary)
            }

            // Key metrics row
            HStack(spacing: 0) {
                if let hip = analysis.jointAngles?.hipLeft ?? analysis.jointAngles?.hipRight {
                    compactStat(label: "Hip ROM", value: String(format: "%.0f°", hip.rangeOfMotion))
                }
                if let knee = analysis.jointAngles?.kneeLeft ?? analysis.jointAngles?.kneeRight {
                    compactStat(label: "Knee ROM", value: String(format: "%.0f°", knee.rangeOfMotion))
                }
                if let footStrike = analysis.footStrike {
                    compactStat(label: "Strike", value: footStrike.pattern.displayName)
                }
            }

            // Shank / overstriding indicator
            if let shank = analysis.jointAngles?.shankLeft ?? analysis.jointAngles?.shankRight,
               let atContact = shank.atInitialContact
            {
                HStack(spacing: 6) {
                    Circle()
                        .fill(shank.overstridingRisk.color)
                        .frame(width: 6, height: 6)
                    Text("Shank at contact: \(String(format: "%.1f°", atContact))")
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.textSecondary)
                    Spacer()
                }
            }
        }
        .padding(16)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func compactStat(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.dripLabel(14))
                .foregroundStyle(Color.drip.textPrimary)
            Text(label)
                .font(.dripCaption(9))
                .foregroundStyle(Color.drip.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
}
