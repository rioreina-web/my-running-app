//
//  ContentLibrarySidebar.swift
//  RunningLog
//
//  App navigation sidebar — provides quick access to all major features.
//

import SwiftUI

// MARK: - Menu Item

private struct MenuItem {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
}

private let featureItems: [MenuItem] = [
    MenuItem(title: "Goals", subtitle: "Race & training targets", icon: "target", color: Color.drip.coral),
    MenuItem(title: "Training Analysis", subtitle: "Review your training trends", icon: "chart.bar.xaxis", color: Color.drip.coral),
    MenuItem(title: "Injuries", subtitle: "Track & analyze injuries", icon: "bandage.fill", color: Color.drip.coral),
    MenuItem(title: "Fitness Predictor", subtitle: "AI race time predictions", icon: "trophy.fill", color: Color.drip.coral),
    MenuItem(title: "Pace Chart", subtitle: "View training paces", icon: "speedometer", color: Color.drip.coral),
    MenuItem(title: "Form Check", subtitle: "Quick qualitative form review", icon: "figure.run.circle", color: Color.drip.coral),
    MenuItem(title: "Plan Builder", subtitle: "Create a custom training plan", icon: "doc.text.fill", color: Color.drip.coral),
]

private let contentLibraryItem = MenuItem(
    title: "Content Library",
    subtitle: "Training videos & resources",
    icon: "books.vertical.fill",
    color: Color.drip.coral
)

// MARK: - ContentLibrarySidebar

struct ContentLibrarySidebar: View {
    @Binding var isPresented: Bool
    @Binding var showGoals: Bool
    @Binding var showAnalysis: Bool
    @Binding var showInjuries: Bool
    @Binding var showFitnessPredictor: Bool
    @Binding var showPaceChart: Bool
    @Binding var showFormCheck: Bool
    @Binding var showPlanBuilder: Bool
    @Binding var showContentLibrary: Bool

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
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 60)
                    .padding(.bottom, 24)

                    // Menu items
                    ScrollView {
                        VStack(spacing: 4) {
                            // Features section
                            Text("FEATURES")
                                .font(.dripCaption(10))
                                .foregroundStyle(Color.drip.textSecondary)
                                .tracking(1.5)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 4)

                            ForEach(Array(featureItems.enumerated()), id: \.offset) { index, item in
                                MenuItemRow(item: item) {
                                    navigateTo(index: index)
                                }
                            }

                            Divider()
                                .background(Color.drip.divider)
                                .padding(.vertical, 12)
                                .padding(.horizontal, 8)

                            // Resources section
                            Text("RESOURCES")
                                .font(.dripCaption(10))
                                .foregroundStyle(Color.drip.textSecondary)
                                .tracking(1.5)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 4)

                            MenuItemRow(item: contentLibraryItem) {
                                dismissAndPresent { showContentLibrary = true }
                            }
                        }
                        .padding(.horizontal, 12)
                    }

                    Spacer()
                }
                .frame(width: 280)
                .background(Color.drip.background)
                .offset(x: isPresented ? 0 : -280)

                Spacer()
            }
        }
    }

    private func navigateTo(index: Int) {
        switch index {
        case 0: dismissAndPresent { showGoals = true }
        case 1: dismissAndPresent { showAnalysis = true }
        case 2: dismissAndPresent { showInjuries = true }
        case 3: dismissAndPresent { showFitnessPredictor = true }
        case 4: dismissAndPresent { showPaceChart = true }
        case 5: dismissAndPresent { showFormCheck = true }
        case 6: dismissAndPresent { showPlanBuilder = true }
        default: break
        }
    }

    private func dismissAndPresent(_ present: @escaping () -> Void) {
        withAnimation(.spring(response: 0.3)) {
            isPresented = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            present()
        }
    }
}

// MARK: - MenuItemRow

private struct MenuItemRow: View {
    let item: MenuItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(item.color.opacity(0.15))
                        .frame(width: 40, height: 40)

                    Image(systemName: item.icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(item.color)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.dripLabel(15))
                        .foregroundStyle(Color.drip.textPrimary)

                    Text(item.subtitle)
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.textTertiary)
                        .lineLimit(1)
                }

                Spacer()

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

// MARK: - CategoryRow (used by ContentLibraryHubView)

struct CategoryRow: View {
    let category: ContentCategory
    let count: Int
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(category.accentColor.opacity(0.15))
                        .frame(width: 40, height: 40)

                    Image(systemName: category.icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(category.accentColor)
                }

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
                ZStack {
                    Circle()
                        .fill(Color.drip.positive.opacity(0.15))
                        .frame(width: 40, height: 40)

                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.drip.positive)
                }

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

// MARK: - ContentLibraryHubView

struct ContentLibraryHubView: View {
    @State private var categoryCounts: [ContentCategory: Int] = [:]
    @State private var isLoading = true
    @State private var selectedCategory: ContentCategory?
    @State private var showDownloads = false
    @State private var downloadManager = VideoDownloadManager.shared

    var body: some View {
        ZStack {
            DripBackground()

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(ContentCategory.allCases) { category in
                        CategoryRow(
                            category: category,
                            count: categoryCounts[category] ?? 0,
                            isLoading: isLoading
                        ) {
                            selectedCategory = category
                        }
                    }

                    if !downloadManager.downloadedVideos.isEmpty {
                        Divider()
                            .background(Color.drip.divider)
                            .padding(.vertical, 8)

                        DownloadsRow(
                            count: downloadManager.downloadedVideos.count
                        ) {
                            showDownloads = true
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("CONTENT LIBRARY")
                    .font(.dripCaption(12))
                    .foregroundStyle(Color.drip.textSecondary)
                    .tracking(2)
            }
        }
        .toolbarBackground(Color.drip.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task {
            categoryCounts = await ContentLibraryService.shared.fetchCategoryCounts()
            isLoading = false
        }
        .fullScreenCover(item: $selectedCategory) { category in
            ContentLibraryView(category: category)
        }
        .fullScreenCover(isPresented: $showDownloads) {
            DownloadsView()
        }
    }
}

#Preview {
    ZStack {
        Color.drip.background.ignoresSafeArea()

        ContentLibrarySidebar(
            isPresented: .constant(true),
            showGoals: .constant(false),
            showAnalysis: .constant(false),
            showInjuries: .constant(false),
            showFitnessPredictor: .constant(false),
            showPaceChart: .constant(false),
            showFormCheck: .constant(false),
            showPlanBuilder: .constant(false),
            showContentLibrary: .constant(false)
        )
    }
}
