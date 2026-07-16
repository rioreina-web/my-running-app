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
    @Environment(NetworkMonitor.self) private var networkMonitor
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab = 0
    @State private var checkInManager = CoachCheckInManager()
    @State private var athleteProfileService = AthleteProfileService()
    @State private var activeDestination: AppDestination?
    @State private var showSettings = false

    // Sidebar state
    @State private var showSidebar = false

    // Staged coach question (e.g. from the Trends ask bar). Consumed by
    // The Read tab's composer. See CoachAskContext.
    @State private var coachAsk = CoachAskContext()

    var body: some View {
        ZStack {
            // Custom bar (DripTabBar) replaces the system TabView. The
            // editorial spec calls for `dot + uppercase mono label`, no
            // icons — see design-system/ui_kits/ios_app/Primitives.jsx::TabBar
            // and Post Run Drip Design System/ui_kits/ios_app/tokens.css.
            //
            // Routing: all 4 tab views render simultaneously in a ZStack
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
            // Cost: 4 view trees alive at once instead of 1. Acceptable
            // for the user-visible win and avoids the refetch storm
            // (loadActivePlan / fitness-prediction / scheduled-workouts
            // each previously refired on every tab re-entry).
            //
            // Phase A (2026-07-13): 7 tabs → 4 (Log · Trends · Train ·
            // Coach). Train 2 + Signal evaluation tabs retired; Plan
            // folded into Train's CALENDAR mode. See
            // outputs/beta-design-overhaul-plan-2026-07-13.md.
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

                // Tab 4 — Trends (chart-centric "show me what I can't see"
                // surface; the unified mileage/intensity/pace/mood/niggle
                // timeline). Non-contiguous tag 4 is historical; the bar
                // displays it in slot 2 (declaration order in DripTab).
                // The Signal pace-spectrum prototype (PaceSignalView) is
                // pushed from Trends' GO DEEPER — no longer its own tab.
                NavigationStack { TrendsTabView() }
                    .opacity(selectedTab == 4 ? 1 : 0)
                    .allowsHitTesting(selectedTab == 4)

                // Tab 1 — Train (the detail surface: CURRENT · CALENDAR ·
                // HISTORY). Phase A folded the Plan tab into CALENDAR —
                // the plan is a subset of training, not its own
                // destination; TrainingPlanView is pushed from there.
                // Train 2 (TrainingTabTwoView) retired as a tab.
                NavigationStack { TrainingTabView() }
                    .opacity(selectedTab == 1 ? 1 : 0)
                    .allowsHitTesting(selectedTab == 1)

                // Tab 2 — COACH (The Read) = the v5 editorial narrative
                // (the-read-storytelling-mock.html). Renders sectioned reads
                // from daily_coaching_reads, falling back to the flat
                // paragraph for pre-v5 rows. The cards ModelOfYouView is
                // retained in the repo as the "evidence" drill-down.
                // Note: the iOS coach-mode surface (CoachTabView) lost its
                // tab in Phase A — the web coach portal is canonical for
                // coach work (adaptive-coach-plan-builder-spec-2026-07-03).
                NavigationStack { CoachReadView() }
                    .opacity(selectedTab == 2 ? 1 : 0)
                    .allowsHitTesting(selectedTab == 2)
            }
            .safeAreaInset(edge: .bottom) {
                DripTabBar(selected: $selectedTab)
            }

            .environment(checkInManager)
            .environment(athleteProfileService)
            .environment(\.selectedTab, $selectedTab)
            .environment(\.showSidebar, $showSidebar)
            .environment(\.coachAsk, coachAsk)
            .task {
                // These launch refreshes are INDEPENDENT — run them concurrently
                // instead of serially. Previously each `await` blocked the next, so
                // launch latency was the SUM of all of them (profile rebuild alone
                // is ~1.6–2.6s); now it's ~the slowest single one. HealthKit auth +
                // sync runs in its own branch so it never gates the UI refreshes.
                async let profile: Void = athleteProfileService.fetchProfile()
                async let paceProfile: Void = { try? await AthletePaceProfileService.shared.refresh() }()
                async let paceZones: Void = { try? await PaceZonesService.shared.refresh() }()
                async let dailyRead: Void = { try? await DailyReadService.shared.refresh() }()
                async let maxHRSync: Void = AthleteSettingsService.syncMaxHRFromServer()
                // Beta-audit #10: keep athlete_settings.timezone current so
                // the Daily Read cron fires at the athlete's LOCAL morning.
                async let tzSync: Void = AthleteSettingsService.syncDeviceTimezone()
                async let healthKitSync: Void = {
                    // Auto-sync HealthKit workouts to training_logs on launch.
                    // Vital replaced by HealthKit for V1 — Terra integration planned for V1.1.
                    _ = await HealthKitManager.shared.requestAuthorization()
                    let hkWorkouts = await HealthKitManager.shared.fetchRecentRunningWorkouts(limit: 30)
                    if !hkWorkouts.isEmpty {
                        await WorkoutSyncService().syncUnloggedWorkouts(workouts: hkWorkouts)
                    }
                }()
                _ = await (profile, paceProfile, paceZones, dailyRead, maxHRSync, tzSync, healthKitSync)
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

            // Error + Offline banners.
            // The container respects the top safe area so the error card
            // never slides under the status bar / Dynamic Island (its text
            // used to collide with the clock). The offline bar sits at the
            // very top and lets only its *background* bleed up into the
            // notch, while its label stays below the status bar.
            VStack(spacing: 8) {
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
                    .background(
                        Color.drip.tired
                            .ignoresSafeArea(edges: .top)
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Suppress network errors while the offline bar already
                // says the same thing, so we never stack two banners.
                ErrorBanner(suppressNetworkError: !networkMonitor.isConnected)
                    .padding(.top, networkMonitor.isConnected ? 8 : 0)

                Spacer()
            }
            .animation(.spring(response: 0.3), value: networkMonitor.isConnected)
        }
        // AthleteProfileService is injected on the inner TabView above, but the
        // Settings surfaces present from THIS outer ZStack (.sheet + the
        // .settings fullScreenCover), so they're not descendants of that
        // injection. AthleteProfileView reads @Environment(AthleteProfileService)
        // and crashes without it — inject here so both presentation paths inherit it.
        .environment(athleteProfileService)
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
