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
        #if DEBUG
        SentryService.capture("Sentry test event from iOS launch", level: "error")
        #endif
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
        // Tab bar appearance lives on the custom `DripTabBar` view now
        // (App/DripTabBar.swift). There's no UIKit `UITabBar` in the
        // hierarchy anymore, so the old `UITabBarAppearance` block was
        // dead code and has been removed.

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
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab = 0
    @State private var checkInManager = CoachCheckInManager()
    @State private var athleteProfileService = AthleteProfileService()
    @State private var activeDestination: AppDestination?
    @State private var showSettings = false

    // Sidebar state
    @State private var showSidebar = false

    var body: some View {
        ZStack {
            // Custom bar (DripTabBar) replaces the system TabView. The
            // editorial spec calls for `dot + uppercase mono label`, no
            // icons — see design-system/ui_kits/ios_app/Primitives.jsx::TabBar
            // and Post Run Drip Design System/ui_kits/ios_app/tokens.css.
            //
            // Routing: all 5 tab views render simultaneously in a ZStack
            // and we toggle `.opacity` + `.allowsHitTesting` based on
            // `selectedTab`. This matches the system TabView's behaviour
            // (each tab's `@State` and scroll position survive a swap)
            // and prevents the in-flight URLSession requests of the
            // outgoing tab from being cancelled mid-fetch on every swap —
            // which previously surfaced as spurious "Network error"
            // banners because `URLError(.cancelled)` got wrapped as
            // `.network`. (The reporter now suppresses cancellations
            // independently; this just stops the cancellations from
            // happening in the first place.)
            //
            // Cost: 5 view trees alive at once instead of 1. Acceptable
            // for the user-visible win and avoids the refetch storm
            // (loadActivePlan / fitness-prediction / scheduled-workouts
            // each previously refired on every tab re-entry).
            ZStack {
                // Tab 0 — Log (front door)
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
                .opacity(selectedTab == 0 ? 1 : 0)
                .allowsHitTesting(selectedTab == 0)

                // Tab 1 — Train
                NavigationStack { TrainingTabView() }
                    .opacity(selectedTab == 1 ? 1 : 0)
                    .allowsHitTesting(selectedTab == 1)

                // Tab 2 — Trends
                NavigationStack { TrendsTabView() }
                    .opacity(selectedTab == 2 ? 1 : 0)
                    .allowsHitTesting(selectedTab == 2)

                // Tab 3 — Coach
                NavigationStack { CoachReadView() }
                    .opacity(selectedTab == 3 ? 1 : 0)
                    .allowsHitTesting(selectedTab == 3)

                // Tab 4 — Plan (or Coach in coach mode)
                NavigationStack {
                    if isCoachMode {
                        CoachTabView()
                    } else {
                        TrainingPlanView()
                    }
                }
                .opacity(selectedTab == 4 ? 1 : 0)
                .allowsHitTesting(selectedTab == 4)
            }
            .safeAreaInset(edge: .bottom) {
                DripTabBar(selected: $selectedTab)
            }

            .environment(checkInManager)
            .environment(athleteProfileService)
            .environment(\.selectedTab, $selectedTab)
            .environment(\.showSidebar, $showSidebar)
            .task {
                await athleteProfileService.fetchProfile()
                try? await AthletePaceProfileService.shared.refresh()
                try? await PaceZonesService.shared.refresh()
                try? await DailyReadService.shared.refresh()

                // Auto-sync HealthKit workouts to training_logs on launch.
                // Vital replaced by HealthKit for V1 — Terra integration planned for V1.1.
                _ = await HealthKitManager.shared.requestAuthorization()
                let hkWorkouts = await HealthKitManager.shared.fetchRecentRunningWorkouts(limit: 30)
                if !hkWorkouts.isEmpty {
                    let syncService = WorkoutSyncService()
                    await syncService.syncUnloggedWorkouts(workouts: hkWorkouts)
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                // Re-fire the daily Coach Read fetch every time the
                // app comes back to the foreground. Cheap when a
                // completed row already exists (one SELECT, two IN
                // queries); generates a fresh Read on first foreground
                // of a new day.
                if newPhase == .active {
                    Task { try? await DailyReadService.shared.refresh() }
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
    case settings

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
        case .settings: SettingsView()
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
