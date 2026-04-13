//
//  VideoPlayerView.swift
//  RunningLog
//
//  Full-screen video player using AVPlayer for self-hosted videos.
//

import AVKit
import os
import SwiftUI

// MARK: - VideoPlayerView

struct VideoPlayerView: View {
    let video: ContentLibraryItem
    @Environment(\.dismiss) private var dismiss

    @State private var player: AVPlayer?
    @State private var isBuffering = true
    @State private var error: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            }

            // Show loading overlay while buffering
            if isBuffering, error == nil {
                loadingView
            }

            // Error view
            if let error {
                errorView(error)
            }

            // Close button overlay
            VStack {
                HStack {
                    Button {
                        player?.pause()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                    }
                    .padding(.leading, 16)
                    .padding(.top, 60)

                    Spacer()
                }
                Spacer()
            }

            // Video info overlay at bottom
            VStack {
                Spacer()

                VStack(alignment: .leading, spacing: 8) {
                    Text(video.title)
                        .font(.dripLabel(18))
                        .foregroundStyle(.white)

                    if let description = video.description {
                        Text(description)
                            .font(.dripCaption(13))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background(
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.8)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }

    // MARK: - Setup Player

    private func setupPlayer() {
        // Check if video is downloaded locally
        let downloadManager = VideoDownloadManager.shared
        let videoURL: URL

        Log.video.debug("Setting up player for: \(video.title)")
        Log.video.debug("Video ID: \(video.id)")
        Log.video.debug("Is downloaded: \(downloadManager.isDownloaded(video.id))")

        if let localURL = downloadManager.localURL(for: video.id) {
            // Use local file - instant playback
            Log.video.info("Using LOCAL file: \(localURL.path)")
            videoURL = localURL
        } else if let remoteURL = URL(string: video.videoUrl) {
            // Stream from remote
            Log.video.info("Using REMOTE URL: \(remoteURL)")
            videoURL = remoteURL
        } else {
            error = "Invalid video URL"
            return
        }

        // Create asset with optimized loading
        let asset = AVURLAsset(url: videoURL)

        // Create player item
        let playerItem = AVPlayerItem(asset: asset)

        // Prefer faster start over perfect buffering
        playerItem.preferredForwardBufferDuration = 2.0

        // Create player
        let newPlayer = AVPlayer(playerItem: playerItem)

        // Start playback as soon as possible (don't wait for full buffer)
        newPlayer.automaticallyWaitsToMinimizeStalling = false

        // Observe playback status
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { _ in
            // Video finished - could loop or dismiss
        }

        // Observe for errors
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { _ in
            error = "Playback failed. Please try again."
        }

        // KVO for buffering state
        playerItem.addObserver(
            PlayerObserver.shared,
            forKeyPath: "playbackLikelyToKeepUp",
            options: [.new],
            context: nil
        )

        player = newPlayer

        // Start playing immediately
        newPlayer.play()

        // Update buffering state based on player
        Task {
            // Give a moment for playback to start
            try? await Task.sleep(nanoseconds: 500_000_000)
            await MainActor.run {
                isBuffering = false
            }
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.white)

            Text("Loading video...")
                .font(.dripCaption(13))
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.5))
    }

    // MARK: - Error View

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.drip.coral)

            Text("Unable to Play Video")
                .font(.dripLabel(18))
                .foregroundStyle(.white)

            Text(message)
                .font(.dripCaption(13))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                error = nil
                isBuffering = true
                setupPlayer()
            } label: {
                Text("Try Again")
                    .font(.dripLabel(14))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.drip.coral)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .padding(.top, 8)

            Button {
                dismiss()
            } label: {
                Text("Go Back")
                    .font(.dripLabel(14))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}

// MARK: - PlayerObserver

/// Simple observer class for KVO
private class PlayerObserver: NSObject {
    static let shared = PlayerObserver()

    // swiftlint:disable:next block_based_kvo
    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        // Buffering state changes handled here if needed
    }
}

#Preview {
    VideoPlayerView(
        video: ContentLibraryItem(
            id: UUID(),
            title: "Dynamic Warm-Up Routine",
            description: "A complete 10-minute warm-up to prepare your body for running.",
            category: "mobility",
            videoUrl: "https://example.com/video.mp4",
            thumbnailUrl: nil,
            durationSeconds: 600,
            sortOrder: 1,
            isFeatured: true,
            isActive: true,
            createdAt: Date(),
            updatedAt: Date()
        )
    )
}
