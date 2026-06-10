//
//  ContentLibrarySidebar.swift
//  RunningLog
//
//  App navigation sidebar — the editorial "numbered index" menu from the
//  Post Run Drip kit (design-system/ui_kits/ios_app/SettingsSheets.jsx ·
//  AppSidebar). Wordmark masthead, plate row, identity (real email),
//  grouped 01–07 destination index, footer with sign-out + build string.
//
//  Only the menu presentation changed in the 2026-05-29 rebrand pass.
//  Bindings, AppDestination routing, and the other structs in this file
//  (CategoryRow, DownloadsRow, ContentLibraryHubView) are unchanged.
//

import SwiftUI

// MARK: - Menu model (editorial numbered index)

private struct MenuEntry: Identifiable {
    let id = UUID()
    let number: String
    let label: String
    let hint: String
    let destination: AppDestination
}

private struct MenuGroup: Identifiable {
    let id = UUID()
    let head: String
    let entries: [MenuEntry]
}

private let menuGroups: [MenuGroup] = [
    MenuGroup(head: "Targets", entries: [
        MenuEntry(number: "01", label: "Goals", hint: "Race & training targets.", destination: .goals),
        MenuEntry(number: "02", label: "Pace Chart", hint: "Your training paces, by zone.", destination: .paceChart),
        MenuEntry(number: "03", label: "Fitness Predictor", hint: "AI race-time predictions.", destination: .fitnessPredictor),
    ]),
    MenuGroup(head: "Review", entries: [
        MenuEntry(number: "04", label: "Training Analysis", hint: "Trends across your block.", destination: .analysis),
        MenuEntry(number: "05", label: "Injuries", hint: "Track, analyze, recover.", destination: .injuries),
    ]),
    MenuGroup(head: "Library & Account", entries: [
        MenuEntry(number: "06", label: "Content Library", hint: "Films, drills & reading.", destination: .contentLibrary),
        MenuEntry(number: "07", label: "Settings", hint: "Account, data & app preferences.", destination: .settings),
    ]),
]

// MARK: - ContentLibrarySidebar

struct ContentLibrarySidebar: View {
    @Binding var isPresented: Bool
    @Binding var activeDestination: AppDestination?

    var body: some View {
        GeometryReader { geo in
            let panelWidth = min(geo.size.width * 0.85, 360)

            ZStack(alignment: .leading) {
                // Scrim — design spec rgba(26,24,21,0.46)
                Color(hex: "1A1815")
                    .opacity(isPresented ? 0.46 : 0)
                    .ignoresSafeArea()
                    .onTapGesture { close() }
                    .allowsHitTesting(isPresented)

                // Panel
                VStack(alignment: .leading, spacing: 0) {
                    masthead
                    ScrollView { indexList }
                    footer
                }
                .frame(width: panelWidth, alignment: .leading)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(Color.drip.background)
                .shadow(color: .black.opacity(0.22), radius: 14, x: 2, y: 0)
                .offset(x: isPresented ? 0 : -(panelWidth + 24))
                .ignoresSafeArea(edges: .bottom)
            }
            .animation(.spring(response: 0.34, dampingFraction: 0.92), value: isPresented)
        }
    }

    // MARK: Masthead

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Menu.")
                    .font(.dripDisplay(30))
                    .foregroundStyle(Color.drip.textPrimary)
                Spacer()
                closeButton
            }

            if let email = AuthManager.shared.userEmail, !email.isEmpty {
                Text(email)
                    .font(.dripStat(11))
                    .foregroundStyle(Color.drip.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.top, 14)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 64)
        .padding(.bottom, 22)
    }

    private var closeButton: some View {
        Button { close() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.drip.textSecondary)
                .frame(width: 34, height: 34)
                .overlay(Circle().stroke(Color.drip.divider, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Index

    private var indexList: some View {
        let entries = menuGroups.flatMap { $0.entries }
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { idx, entry in
                Button { select(entry.destination) } label: {
                    HStack {
                        Text(entry.label)
                            .font(.dripDisplay(21))
                            .foregroundStyle(Color.drip.textPrimary)
                        Spacer(minLength: 8)
                        Text("↗")
                            .font(.dripStat(12))
                            .foregroundStyle(Color.drip.textTertiary)
                    }
                    .padding(.vertical, 16)
                    .contentShape(Rectangle())
                    .overlay(alignment: .bottom) {
                        if idx < entries.count - 1 {
                            Rectangle().fill(Color.drip.divider).frame(height: 1)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(alignment: .firstTextBaseline) {
            Button { signOut() } label: {
                Text("Sign out")
                    .font(.dripLabel(14))
                    .foregroundStyle(Color.drip.textSecondary)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Color.drip.divider).frame(height: 1).offset(y: 2)
                    }
            }
            .buttonStyle(.plain)
            Spacer()
            Text(buildString)
                .font(.dripEyebrow(9))
                .tracking(0.9)  // 0.10em at 9pt
                .foregroundStyle(Color.drip.textTertiary)
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 18)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.drip.divider).frame(height: 1)
        }
    }

    private var buildString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "POST RUN DRIP · v\(version) · BUILD \(build)"
    }

    // MARK: Actions

    private func close() {
        isPresented = false
    }

    private func select(_ destination: AppDestination) {
        isPresented = false
        Task {
            try? await Task.sleep(for: .seconds(0.34))
            activeDestination = destination
        }
    }

    private func signOut() {
        isPresented = false
        Task { @MainActor in
            try? await AuthManager.shared.signOut()
        }
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
            activeDestination: .constant(nil)
        )
    }
}
