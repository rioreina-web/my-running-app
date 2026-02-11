//
//  ContentLibrarySidebar.swift
//  RunningLog
//
//  Sidebar overlay for accessing the content library categories.
//

import SwiftUI

// MARK: - ContentLibrarySidebar

struct ContentLibrarySidebar: View {
    @Binding var isPresented: Bool
    @Binding var selectedCategory: ContentCategory?

    @State private var categoryCounts: [ContentCategory: Int] = [:]
    @State private var isLoadingCounts = true
    @State private var showDownloads = false
    @State private var downloadManager = VideoDownloadManager.shared

    var body: some View {
        ZStack(alignment: .leading) {
            // Dimmed background
            Color.black.opacity(isPresented ? 0.5 : 0)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.3)) {
                        isPresented = false
                    }
                }

            // Sidebar panel
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image("Logo")
                                .renderingMode(.original)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 28)

                            Spacer()

                            Button {
                                withAnimation(.spring(response: 0.3)) {
                                    isPresented = false
                                }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(Color.drip.textSecondary)
                                    .frame(width: 32, height: 32)
                                    .background(Color.drip.cardBackgroundElevated)
                                    .clipShape(Circle())
                            }
                        }

                        Text("CONTENT LIBRARY")
                            .font(.dripCaption(10))
                            .foregroundStyle(Color.drip.textSecondary)
                            .tracking(1.5)
                            .padding(.top, 8)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 60)
                    .padding(.bottom, 24)

                    // Category list
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(ContentCategory.allCases) { category in
                                CategoryRow(
                                    category: category,
                                    count: categoryCounts[category] ?? 0,
                                    isLoading: isLoadingCounts
                                ) {
                                    withAnimation(.spring(response: 0.3)) {
                                        isPresented = false
                                    }
                                    // Set category after sidebar closes to trigger fullScreenCover
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                        selectedCategory = category
                                    }
                                }
                            }

                            // Downloads section
                            if !downloadManager.downloadedVideos.isEmpty {
                                Divider()
                                    .background(Color.drip.divider)
                                    .padding(.vertical, 8)

                                DownloadsRow(
                                    count: downloadManager.downloadedVideos.count
                                ) {
                                    withAnimation(.spring(response: 0.3)) {
                                        isPresented = false
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                        showDownloads = true
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                    }

                    Spacer()

                    // Footer
                    VStack(spacing: 4) {
                        Divider()
                            .background(Color.drip.divider)
                            .padding(.horizontal, 20)

                        Text("Training videos and resources")
                            .font(.dripCaption(11))
                            .foregroundStyle(Color.drip.textTertiary)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                    }
                }
                .frame(width: 280)
                .background(Color.drip.background)
                .offset(x: isPresented ? 0 : -280)

                Spacer()
            }
        }
        .task {
            await loadCategoryCounts()
        }
        .fullScreenCover(isPresented: $showDownloads) {
            DownloadsView()
        }
    }

    private func loadCategoryCounts() async {
        isLoadingCounts = true
        categoryCounts = await ContentLibraryService.shared.fetchCategoryCounts()
        isLoadingCounts = false
    }
}

// MARK: - CategoryRow

struct CategoryRow: View {
    let category: ContentCategory
    let count: Int
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                // Icon
                ZStack {
                    Circle()
                        .fill(category.accentColor.opacity(0.15))
                        .frame(width: 40, height: 40)

                    Image(systemName: category.icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(category.accentColor)
                }

                // Text
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.displayName)
                        .font(.dripLabel(15))
                        .foregroundStyle(Color.drip.textPrimary)

                    Text(category.description)
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.textTertiary)
                        .lineLimit(1)
                }

                Spacer()

                // Count badge
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                } else if count > 0 {
                    Text("\(count)")
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.drip.cardBackgroundElevated)
                        .clipShape(Capsule())
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.drip.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - DownloadsRow

struct DownloadsRow: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                // Icon
                ZStack {
                    Circle()
                        .fill(Color.drip.positive.opacity(0.15))
                        .frame(width: 40, height: 40)

                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.drip.positive)
                }

                // Text
                VStack(alignment: .leading, spacing: 2) {
                    Text("Downloads")
                        .font(.dripLabel(15))
                        .foregroundStyle(Color.drip.textPrimary)

                    Text("Saved for offline")
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.textTertiary)
                        .lineLimit(1)
                }

                Spacer()

                // Count badge
                if count > 0 {
                    Text("\(count)")
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.positive)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.drip.positive.opacity(0.15))
                        .clipShape(Capsule())
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.drip.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ZStack {
        Color.drip.background.ignoresSafeArea()

        ContentLibrarySidebar(
            isPresented: .constant(true),
            selectedCategory: .constant(nil)
        )
    }
}
