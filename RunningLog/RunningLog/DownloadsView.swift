//
//  DownloadsView.swift
//  RunningLog
//
//  View for managing downloaded videos.
//

import os
import SwiftUI

// MARK: - DownloadsView

struct DownloadsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var downloadManager = VideoDownloadManager.shared
    @State private var downloadedVideos: [ContentLibraryItem] = []
    @State private var isLoading = true
    @State private var selectedVideo: ContentLibraryItem?
    @State private var showVideoPlayer = false
    @State private var showDeleteConfirmation = false
    @State private var videoToDelete: ContentLibraryItem?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.drip.background.ignoresSafeArea()

                if isLoading {
                    ProgressView()
                        .tint(Color.drip.coral)
                } else if downloadedVideos.isEmpty {
                    emptyView
                } else {
                    downloadsList
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.drip.textSecondary)
                    }
                }

                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.drip.coral)
                        Text("DOWNLOADS")
                            .font(.dripCaption(12))
                            .foregroundStyle(Color.drip.textSecondary)
                            .tracking(1.5)
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if !downloadedVideos.isEmpty {
                        Menu {
                            Button(role: .destructive) {
                                showDeleteConfirmation = true
                            } label: {
                                Label("Delete All", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.drip.coral)
                        }
                    }
                }
            }
            .toolbarBackground(Color.drip.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .task {
                await loadDownloadedVideos()
            }
            .fullScreenCover(isPresented: $showVideoPlayer) {
                if let video = selectedVideo {
                    VideoPlayerView(video: video)
                }
            }
            .alert("Delete All Downloads?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete All", role: .destructive) {
                    deleteAllDownloads()
                }
            } message: {
                Text("This will remove all \(downloadedVideos.count) downloaded videos from your device.")
            }
            .alert("Delete Video?", isPresented: .init(
                get: { videoToDelete != nil },
                set: { if !$0 { videoToDelete = nil } }
            )) {
                Button("Cancel", role: .cancel) {
                    videoToDelete = nil
                }
                Button("Delete", role: .destructive) {
                    if let video = videoToDelete {
                        deleteVideo(video)
                    }
                    videoToDelete = nil
                }
            } message: {
                if let video = videoToDelete {
                    Text("Remove \"\(video.title)\" from downloads?")
                }
            }
        }
    }

    // MARK: - Downloads List

    private var downloadsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Storage info header
                storageHeader
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 16)

                // Downloaded videos
                ForEach(downloadedVideos) { video in
                    DownloadedVideoRow(video: video) {
                        selectedVideo = video
                        showVideoPlayer = true
                    } onDelete: {
                        videoToDelete = video
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                }

                Spacer()
                    .frame(height: 40)
            }
        }
    }

    // MARK: - Storage Header

    private var storageHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(downloadedVideos.count) videos")
                    .font(.dripLabel(16))
                    .foregroundStyle(Color.drip.textPrimary)

                Text(VideoDownloadManager.formatBytes(downloadManager.totalDownloadedSize()))
                    .font(.dripCaption(13))
                    .foregroundStyle(Color.drip.textSecondary)
            }

            Spacer()
        }
        .padding(16)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Empty View

    private var emptyView: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.drip.coral.opacity(0.1))
                    .frame(width: 100, height: 100)

                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(Color.drip.coral)
            }

            VStack(spacing: 8) {
                Text("No Downloads")
                    .font(.dripLabel(18))
                    .foregroundStyle(Color.drip.textPrimary)

                Text("Downloaded videos will appear here for offline viewing.")
                    .font(.dripBody(14))
                    .foregroundStyle(Color.drip.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
    }

    // MARK: - Data Loading

    private func loadDownloadedVideos() async {
        isLoading = true

        // Use cached metadata for offline support - no network required
        downloadedVideos = downloadManager.getAllDownloadedVideos()

        Log.video.debug("Loaded \(downloadedVideos.count) downloaded videos from cache")

        isLoading = false
    }

    private func deleteVideo(_ video: ContentLibraryItem) {
        downloadManager.deleteDownload(for: video.id)
        downloadedVideos.removeAll { $0.id == video.id }
    }

    private func deleteAllDownloads() {
        downloadManager.deleteAllDownloads()
        downloadedVideos = []
    }
}

// MARK: - DownloadedVideoRow

struct DownloadedVideoRow: View {
    let video: ContentLibraryItem
    let onPlay: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            // Thumbnail
            ZStack {
                if let thumbnailUrl = video.thumbnailUrl, let url = URL(string: thumbnailUrl) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case let .success(image):
                            image
                                .resizable()
                                .aspectRatio(16 / 9, contentMode: .fill)
                        default:
                            thumbnailPlaceholder
                        }
                    }
                } else {
                    thumbnailPlaceholder
                }

                // Play icon
                Image(systemName: "play.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(Color.drip.coral)
                    .clipShape(Circle())
            }
            .frame(width: 100, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .onTapGesture {
                onPlay()
            }

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(video.title)
                    .font(.dripLabel(14))
                    .foregroundStyle(Color.drip.textPrimary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if video.durationSeconds != nil {
                        Text(video.formattedDuration)
                            .font(.dripCaption(11))
                            .foregroundStyle(Color.drip.textSecondary)
                    }

                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.drip.positive)

                    Text("Downloaded")
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.positive)
                }
            }

            Spacer()

            // Delete button
            Button {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.drip.textTertiary)
                    .frame(width: 36, height: 36)
            }
        }
        .padding(12)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var thumbnailPlaceholder: some View {
        Rectangle()
            .fill(Color.drip.cardBackgroundElevated)
            .overlay(
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.drip.textTertiary)
            )
    }
}

#Preview {
    DownloadsView()
}
