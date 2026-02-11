//
//  RunningLogApp.swift
//  RunningLog
//
//  Created by Rio Reina on 1/24/26.
//

import SwiftUI

// MARK: - RunningLogApp

@main
struct RunningLogApp: App {
    init() {
        configureAppearance()
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
        }
    }

    private func configureAppearance() {
        // Tab Bar
        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithOpaqueBackground()
        tabBarAppearance.backgroundColor = UIColor(Color(hex: "0A0A0B"))
        tabBarAppearance.stackedLayoutAppearance.selected.iconColor = UIColor(Color(hex: "FF6B4A"))
        tabBarAppearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor(Color(hex: "FF6B4A"))]
        tabBarAppearance.stackedLayoutAppearance.normal.iconColor = UIColor(Color(hex: "48484A"))
        tabBarAppearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor(Color(hex: "48484A"))]
        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance

        // Navigation Bar
        let navBarAppearance = UINavigationBarAppearance()
        navBarAppearance.configureWithOpaqueBackground()
        navBarAppearance.backgroundColor = UIColor(Color(hex: "0A0A0B"))
        navBarAppearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        navBarAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        UINavigationBar.appearance().standardAppearance = navBarAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navBarAppearance
        UINavigationBar.appearance().compactAppearance = navBarAppearance
    }
}

// MARK: - MainTabView

struct MainTabView: View {
    @State private var selectedTab = 0
    @State private var showGoals = false
    @State private var showAnalysis = false

    // Content Library state
    @State private var showSidebar = false
    @State private var selectedCategory: ContentCategory?

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                NavigationStack {
                    VoiceLogView()
                }
                .tag(0)
                .tabItem {
                    Label("Log", systemImage: "mic.fill")
                }

                NavigationStack {
                    WorkoutsView()
                }
                .tag(1)
                .tabItem {
                    Label("Workouts", systemImage: "figure.run")
                }

                NavigationStack {
                    HistoryView()
                }
                .tag(2)
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }

                NavigationStack {
                    CoachView()
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Menu {
                                    Button {
                                        showGoals = true
                                    } label: {
                                        Label("Goals", systemImage: "target")
                                    }

                                    Button {
                                        showAnalysis = true
                                    } label: {
                                        Label("Training Analysis", systemImage: "chart.bar.xaxis")
                                    }
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(Color.drip.coral)
                                }
                            }
                        }
                }
                .tag(3)
                .tabItem {
                    Label("Coach", systemImage: "message.fill")
                }

                NavigationStack {
                    TrainingPlanView()
                }
                .tag(4)
                .tabItem {
                    Label("Plan", systemImage: "calendar")
                }
            }
            .tint(Color.drip.coral)
            .environment(\.showSidebar, $showSidebar)

            // Content Library Sidebar Overlay (must be after TabView in ZStack)
            ContentLibrarySidebar(
                isPresented: $showSidebar,
                selectedCategory: $selectedCategory
            )
        }
        .fullScreenCover(isPresented: $showGoals) {
            NavigationStack {
                GoalsView()
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                showGoals = false
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(Color.drip.textSecondary)
                            }
                        }
                    }
            }
        }
        .fullScreenCover(isPresented: $showAnalysis) {
            NavigationStack {
                AnalysisView()
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                showAnalysis = false
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(Color.drip.textSecondary)
                            }
                        }
                    }
            }
        }
        .fullScreenCover(item: $selectedCategory) { category in
            ContentLibraryView(category: category)
        }
    }
}

// MARK: - ShowSidebarKey

private struct ShowSidebarKey: EnvironmentKey {
    static let defaultValue: Binding<Bool> = .constant(false)
}

extension EnvironmentValues {
    var showSidebar: Binding<Bool> {
        get { self[ShowSidebarKey.self] }
        set { self[ShowSidebarKey.self] = newValue }
    }
}

// MARK: - SidebarMenuButton

struct SidebarMenuButton: View {
    @Environment(\.showSidebar) private var showSidebar

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.3)) {
                showSidebar.wrappedValue = true
            }
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.drip.coral)
        }
    }
}
