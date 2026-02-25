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
    @State private var authManager = AuthManager.shared

    init() {
        configureAppearance()
    }

    var body: some Scene {
        WindowGroup {
            // TODO: Restore auth gate when Apple Developer Program is active
            // if authManager.isLoading { ... } else if authManager.isAuthenticated { MainTabView() } else { SignInView() }
            MainTabView()
            .preferredColorScheme(.dark)
        }
    }

    private func configureAppearance() {
        // Tab Bar
        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithOpaqueBackground()
        tabBarAppearance.backgroundColor = UIColor(Color(hex: "0A0A0B"))
        tabBarAppearance.stackedLayoutAppearance.selected.iconColor = UIColor(Color(hex: "FF2D2D"))
        tabBarAppearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor(Color(hex: "FF2D2D"))]
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
    @State private var showInjuries = false
    @State private var showFitnessPredictor = false
    @State private var showPaceChart = false
    @State private var showContentLibrary = false
    @State private var showFormCheck = false
    @State private var showPlanBuilder = false
    @State private var showSettings = false

    // Sidebar state
    @State private var showSidebar = false

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                NavigationStack {
                    VoiceLogView()
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button {
                                    showSettings = true
                                } label: {
                                    Image(systemName: "gearshape")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundStyle(Color.drip.textSecondary)
                                }
                            }
                        }
                }
                .tag(0)
                .tabItem {
                    Label("Log", systemImage: "mic.fill")
                }

                NavigationStack {
                    TrainingDashboardView()
                }
                .tag(1)
                .tabItem {
                    Label("Training", systemImage: "chart.bar.fill")
                }

                NavigationStack {
                    CoachView()
                }
                .tag(2)
                .tabItem {
                    Label("Coach", systemImage: "message.fill")
                }

                NavigationStack {
                    TrainingPlanView()
                }
                .tag(3)
                .tabItem {
                    Label("Plan", systemImage: "calendar")
                }
            }
            .tint(Color.drip.coral)
            .environment(\.showSidebar, $showSidebar)

            // App Menu Sidebar Overlay (must be after TabView in ZStack)
            ContentLibrarySidebar(
                isPresented: $showSidebar,
                showGoals: $showGoals,
                showAnalysis: $showAnalysis,
                showInjuries: $showInjuries,
                showFitnessPredictor: $showFitnessPredictor,
                showPaceChart: $showPaceChart,
                showFormCheck: $showFormCheck,
                showPlanBuilder: $showPlanBuilder,
                showContentLibrary: $showContentLibrary
            )

            // Offline banner
            VStack {
                if !NetworkMonitor.shared.isConnected {
                    HStack(spacing: 8) {
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 12, weight: .semibold))
                        Text("No internet connection")
                            .font(.dripCaption(12))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .padding(.top, 44)
                    .background(Color.drip.tired)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer()
            }
            .animation(.spring(response: 0.3), value: NetworkMonitor.shared.isConnected)
            .ignoresSafeArea(edges: .top)
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
        .fullScreenCover(isPresented: $showInjuries) {
            NavigationStack {
                InjuryListView()
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                showInjuries = false
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(Color.drip.textSecondary)
                            }
                        }
                    }
            }
        }
        .fullScreenCover(isPresented: $showFitnessPredictor) {
            NavigationStack {
                FitnessPredictorView(trainingViewModel: TrainingPlanViewModel())
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                showFitnessPredictor = false
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(Color.drip.textSecondary)
                            }
                        }
                    }
            }
        }
        .fullScreenCover(isPresented: $showPaceChart) {
            NavigationStack {
                PaceChartView()
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                showPaceChart = false
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(Color.drip.textSecondary)
                            }
                        }
                    }
            }
        }
        .fullScreenCover(isPresented: $showContentLibrary) {
            NavigationStack {
                ContentLibraryHubView()
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                showContentLibrary = false
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(Color.drip.textSecondary)
                            }
                        }
                    }
            }
        }
        .fullScreenCover(isPresented: $showFormCheck) {
            NavigationStack {
                FormCheckListView()
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                showFormCheck = false
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(Color.drip.textSecondary)
                            }
                        }
                    }
            }
        }
        .fullScreenCover(isPresented: $showPlanBuilder) {
            NavigationStack {
                CustomPlanBuilderView(trainingPlanViewModel: TrainingPlanViewModel())
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                showPlanBuilder = false
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(Color.drip.textSecondary)
                            }
                        }
                    }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
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
