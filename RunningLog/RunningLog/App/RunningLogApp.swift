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
        SentryService.start()
        UserDefaults.standard.register(defaults: [
            "coachCheckInsEnabled": true,
            "smartInsightsEnabled": true,
        ])
        configureAppearance()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(AuthManager.shared)
                .environment(NetworkMonitor.shared)
                .environment(VitalManager.shared)
                .environmentObject(HealthKitManager.shared)
                .preferredColorScheme(.light)
                .background(KeyboardDismissHelper())
        }
    }

    private func configureAppearance() {
        // Tab Bar - Warm paper background, burnt orange accent
        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithOpaqueBackground()
        tabBarAppearance.backgroundColor = UIColor(Color(hex: "F5F3F0"))
        tabBarAppearance.stackedLayoutAppearance.selected.iconColor = UIColor(Color(hex: "D4592A"))
        tabBarAppearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor(Color(hex: "D4592A"))]
        tabBarAppearance.stackedLayoutAppearance.normal.iconColor = UIColor(Color(hex: "9B9590"))
        tabBarAppearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor(Color(hex: "9B9590"))]
        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance

        // Navigation Bar - Clean editorial
        let navBarAppearance = UINavigationBarAppearance()
        navBarAppearance.configureWithOpaqueBackground()
        navBarAppearance.backgroundColor = UIColor(Color(hex: "F5F3F0"))
        navBarAppearance.titleTextAttributes = [.foregroundColor: UIColor(Color(hex: "1A1815"))]
        navBarAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor(Color(hex: "1A1815"))]
        UINavigationBar.appearance().standardAppearance = navBarAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navBarAppearance
        UINavigationBar.appearance().compactAppearance = navBarAppearance
    }
}

// MARK: - MainTabView

struct MainTabView: View {
    @AppStorage("isCoachMode") private var isCoachMode = false
    @Environment(NetworkMonitor.self) private var networkMonitor
    @State private var selectedTab = 0
    @State private var checkInManager = CoachCheckInManager()
    @State private var athleteProfileService = AthleteProfileService()
    @State private var activeDestination: AppDestination?
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
                    if isCoachMode {
                        CoachTabView()
                    } else {
                        TrainingPlanView()
                    }
                }
                .tag(3)
                .tabItem {
                    if isCoachMode {
                        Label("Coach", systemImage: "person.badge.shield.checkmark.fill")
                    } else {
                        Label("Plan", systemImage: "calendar")
                    }
                }
            }
            .tint(Color.drip.coral)

            .environment(checkInManager)
            .environment(athleteProfileService)
            .environment(\.selectedTab, $selectedTab)
            .environment(\.showSidebar, $showSidebar)
            .task {
                await athleteProfileService.fetchProfile()

                // Auto-sync Vital (Garmin) workouts to training_logs on launch
                let vitalWorkouts = await VitalManager.shared.fetchRecentRunningWorkouts(limit: 30)
                if !vitalWorkouts.isEmpty {
                    let syncService = WorkoutSyncService()
                    await syncService.syncUnloggedWorkouts(workouts: vitalWorkouts)
                }
            }

            // App Menu Sidebar Overlay (must be after TabView in ZStack)
            ContentLibrarySidebar(
                isPresented: $showSidebar,
                activeDestination: $activeDestination
            )

            // Error + Offline banners
            VStack {
                ErrorBanner()

                if !networkMonitor.isConnected {
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
            .animation(.spring(response: 0.3), value: networkMonitor.isConnected)
            .ignoresSafeArea(edges: .top)
        }
        .fullScreenCover(item: $activeDestination) { destination in
            NavigationStack {
                destination.view
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                activeDestination = nil
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

// MARK: - AppDestination

enum AppDestination: Identifiable {
    case goals
    case analysis
    case injuries
    case fitnessPredictor
    case paceChart
    case contentLibrary
    case formCheck

    var id: Self { self }

    @ViewBuilder
    var view: some View {
        switch self {
        case .goals: GoalsView()
        case .analysis: AnalysisView()
        case .injuries: InjuryListView()
        case .fitnessPredictor: FitnessPredictorView(trainingViewModel: TrainingPlanViewModel())
        case .paceChart: PaceChartView()
        case .contentLibrary: ContentLibraryHubView()
        case .formCheck: FormCheckListView()
        }
    }
}

// MARK: - SelectedTabKey

private struct SelectedTabKey: EnvironmentKey {
    static let defaultValue: Binding<Int> = .constant(0)
}

// MARK: - ShowSidebarKey

private struct ShowSidebarKey: EnvironmentKey {
    static let defaultValue: Binding<Bool> = .constant(false)
}

extension EnvironmentValues {
    var selectedTab: Binding<Int> {
        get { self[SelectedTabKey.self] }
        set { self[SelectedTabKey.self] = newValue }
    }

    var showSidebar: Binding<Bool> {
        get { self[ShowSidebarKey.self] }
        set { self[ShowSidebarKey.self] = newValue }
    }
}

// MARK: - Keyboard Dismiss Helper

/// Adds a UIKit tap gesture recognizer that dismisses the keyboard on tap
/// without interfering with buttons, toggles, or other interactive elements.
private struct KeyboardDismissHelper: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.dismiss))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator {
        @objc func dismiss() {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
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
