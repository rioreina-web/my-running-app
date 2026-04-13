//
//  ContentLibraryView.swift
//  RunningLog
//
//  View for displaying videos in a content library category.
//

import SwiftUI

// MARK: - ContentLibraryView

struct ContentLibraryView: View {
    let category: ContentCategory
    @Environment(\.dismiss) private var dismiss

    @State private var videos: [ContentLibraryItem] = []
    @State private var isLoading = true
    @State private var selectedVideo: ContentLibraryItem?
    @State private var showVideoPlayer = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.drip.background.ignoresSafeArea()

                if isLoading {
                    loadingView
                } else if videos.isEmpty {
                    emptyView
                } else {
                    videoList
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
                        Image(systemName: category.icon)
                            .font(.system(size: 14))
                            .foregroundStyle(category.accentColor)
                        Text(category.displayName.uppercased())
                            .font(.dripCaption(12))
                            .foregroundStyle(Color.drip.textSecondary)
                            .tracking(1.5)
                    }
                }
            }
            .toolbarBackground(Color.drip.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .task {
                await loadVideos()
            }
            .fullScreenCover(isPresented: $showVideoPlayer) {
                if let video = selectedVideo {
                    VideoPlayerView(video: video)
                }
            }
        }
    }

    // MARK: - Video List

    private var videoList: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                // Category header
                VStack(alignment: .leading, spacing: 8) {
                    Text(category.displayName)
                        .font(.dripDisplay(28))
                        .foregroundStyle(Color.drip.textPrimary)

                    Text(category.description)
                        .font(.dripBody(14))
                        .foregroundStyle(Color.drip.textSecondary)

                    Text("\(videos.count) videos")
                        .font(.dripCaption(12))
                        .foregroundStyle(Color.drip.textTertiary)
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 8)

                // Video cards
                ForEach(videos) { video in
                    VideoCard(video: video) {
                        selectedVideo = video
                        showVideoPlayer = true
                    }
                    .padding(.horizontal, 20)
                }

                Spacer()
                    .frame(height: 40)
            }
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            ForEach(0 ..< 3, id: \.self) { _ in
                VideoCardSkeleton()
                    .padding(.horizontal, 20)
            }
        }
        .padding(.top, 40)
    }

    // MARK: - Empty View

    private var emptyView: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(category.accentColor.opacity(0.1))
                    .frame(width: 100, height: 100)

                Image(systemName: category.icon)
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(category.accentColor)
            }

            VStack(spacing: 8) {
                Text("No Videos Yet")
                    .font(.dripLabel(18))
                    .foregroundStyle(Color.drip.textPrimary)

                Text("Check back soon for new \(category.displayName.lowercased()) content.")
                    .font(.dripBody(14))
                    .foregroundStyle(Color.drip.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
    }

    private func loadVideos() async {
        isLoading = true
        videos = await ContentLibraryService.shared.fetchVideos(for: category)
        isLoading = false
    }
}

// MARK: - VideoCard

struct VideoCard: View {
    let video: ContentLibraryItem
    let action: () -> Void

    @State private var downloadManager = VideoDownloadManager.shared
    @State private var showDownloadError = false
    @State private var downloadErrorMessage = ""

    private var isDownloaded: Bool {
        downloadManager.isDownloaded(video.id)
    }

    private var isDownloading: Bool {
        downloadManager.isDownloading(video.id)
    }

    private var downloadProgress: Double {
        downloadManager.progress(for: video.id)
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                // Thumbnail
                ZStack {
                    if let thumbnailUrl = video.thumbnailUrl, let url = URL(string: thumbnailUrl) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case let .success(image):
                                image
                                    .resizable()
                                    .aspectRatio(16 / 9, contentMode: .fill)
                            case .failure:
                                thumbnailPlaceholder
                            case .empty:
                                thumbnailPlaceholder
                                    .overlay(ProgressView().tint(Color.drip.textSecondary))
                            @unknown default:
                                thumbnailPlaceholder
                            }
                        }
                    } else {
                        thumbnailPlaceholder
                    }

                    // Play button overlay
                    Circle()
                        .fill(Color.drip.coral)
                        .frame(width: 56, height: 56)
                        .overlay(
                            Image(systemName: "play.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(.white)
                                .offset(x: 2)
                        )
                        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)

                    // Duration badge
                    if video.durationSeconds != nil {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Text(video.formattedDuration)
                                    .font(.dripCaption(11))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.black.opacity(0.7))
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                    .padding(12)
                            }
                        }
                    }

                    // Featured badge
                    if video.isFeatured {
                        VStack {
                            HStack {
                                Text("FEATURED")
                                    .font(.dripCaption(9))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.drip.coral)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                    .padding(12)
                                Spacer()
                            }
                            Spacer()
                        }
                    }

                    // Downloaded indicator
                    if isDownloaded {
                        VStack {
                            HStack {
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(.white)
                                    .background(
                                        Circle()
                                            .fill(Color.drip.positive)
                                            .frame(width: 22, height: 22)
                                    )
                                    .padding(12)
                            }
                            Spacer()
                        }
                    }
                }
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                // Info
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(video.title)
                            .font(.dripLabel(16))
                            .foregroundStyle(Color.drip.textPrimary)
                            .lineLimit(2)

                        Spacer()

                        // Download button
                        downloadButton
                    }

                    if let description = video.description {
                        Text(description)
                            .font(.dripCaption(13))
                            .foregroundStyle(Color.drip.textSecondary)
                            .lineLimit(2)
                    }
                }
                .padding(.top, 12)
            }
            .padding(16)
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.drip.divider, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .alert("Download Error", isPresented: $showDownloadError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(downloadErrorMessage)
        }
    }

    private var downloadButton: some View {
        Button {
            handleDownloadTap()
        } label: {
            Group {
                if isDownloading {
                    // Show progress ring
                    ZStack {
                        Circle()
                            .stroke(Color.drip.divider, lineWidth: 2)
                            .frame(width: 28, height: 28)

                        Circle()
                            .trim(from: 0, to: downloadProgress)
                            .stroke(Color.drip.coral, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .frame(width: 28, height: 28)
                            .rotationEffect(.degrees(-90))

                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.drip.textSecondary)
                    }
                } else if isDownloaded {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.drip.positive)
                } else {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.drip.coral)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func handleDownloadTap() {
        if isDownloading {
            // Cancel download
            downloadManager.cancelDownload(for: video.id)
        } else if !isDownloaded {
            // Start download
            downloadManager.download(video: video) { result in
                if case let .failure(error) = result {
                    downloadErrorMessage = error.localizedDescription
                    showDownloadError = true
                }
            }
        }
        // If already downloaded, do nothing (tap on card to play)
    }

    private var thumbnailPlaceholder: some View {
        Rectangle()
            .fill(Color.drip.cardBackgroundElevated)
            .aspectRatio(16 / 9, contentMode: .fill)
            .overlay(
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.drip.textTertiary)
            )
    }
}

// MARK: - VideoCardSkeleton

struct VideoCardSkeleton: View {
    var body: some View {
        SkeletonPulse {
            VStack(alignment: .leading, spacing: 0) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.drip.cardBackgroundElevated)
                    .frame(height: 180)

                VStack(alignment: .leading, spacing: 8) {
                    SkeletonBar(height: 18)
                        .frame(maxWidth: .infinity)
                    SkeletonBar(width: 200, height: 14)
                }
                .padding(.top, 12)
            }
            .padding(16)
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
}

#Preview {
    ContentLibraryView(category: .mobility)
}
