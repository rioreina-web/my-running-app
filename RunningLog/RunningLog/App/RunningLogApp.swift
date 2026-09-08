//
//  RunningLogApp.swift
//  RunningLog
//
//  Created by Rio Reina on 1/24/26.
//

import SwiftUI
import UIKit

// MARK: - AppDelegate

/// App-level orientation gate. UIKit intersects this mask with the top view
/// controller's own, so narrowing it to `.landscape` while a full-screen
/// instrument (The Effort) is up is what makes its orientation stick —
/// `requestGeometryUpdate` alone is a suggestion the system re-evaluates
/// against a portrait-happy SwiftUI hosting controller, which is how the
/// landscape takeover ended up rendering in portrait.
final class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientationMask: UIInterfaceOrientationMask = .all

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?)
        -> UIInterfaceOrientationMask {
        Self.orientationMask
    }
}

// MARK: - RunningLogApp

@main
struct RunningLogApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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
            #if DEBUG
            // Boot straight into a preview-seeded surface for visual iteration,
            // bypassing auth/nav. Launch with `-trendsV2Preview 1`. Remove with
            // the v2 dev scaffolding once the surface is real.
            if CommandLine.arguments.contains("-workoutSignals") {
                // Act 2 of the workout detail sheet, signals-first — for
                // visual iteration. Remove with the dev scaffolding.
                WorkoutSignalsPreviewScene()
                    .preferredColorScheme(.light)
            // Removed 2026-08-05 with the surfaces they existed to iterate on:
            // `-trendsV2Zone` (TrendsZoneDetailView), `-trendsV2New`
            // (TrendsEfficiencyView + TrendsKeySessionsView) and
            // `-trendsV2Recovery` (the three convergence cards). Those views
            // were the last thing keeping seventeen orphaned Trends files in
            // the target; all of it is in git if a screenshot harness is
            // wanted back.
            } else if CommandLine.arguments.contains("-effortLandscape") {
                EffortLandscapePreviewScene()
                    .preferredColorScheme(.light)
            } else if CommandLine.arguments.contains("-effortPreview") {
                // "The Effort" portrait 3a — seeded with the handoff's synthetic
                // 5 × 2 mi @ MP session, for visual iteration without auth/data.
                EffortPreviewScene()
                    .preferredColorScheme(.light)
            } else if CommandLine.arguments.contains("-logRowPreview") {
                // Redesigned JournalLogRow (2026-09-01 stat-strip pass) —
                // seeded week, for visual iteration without auth/data.
                LogRowPreviewScene()
                    .preferredColorScheme(.light)
            } else if CommandLine.arguments.contains("-voiceLogPreview") {
                // The REAL VoiceLogView — record button, mode toggle, and
                // all — to confirm the row redesign sits under the actual
                // front door unchanged. Feed will show its normal
                // sign-in/network error since there's no auth here; the
                // top section doesn't depend on that.
                NavigationStack {
                    VoiceLogView()
                }
                .environment(CoachCheckInManager())
                .preferredColorScheme(.light)
            } else if CommandLine.arguments.contains("-threadPreview") {
                // The REAL TrainingThreadView against live data — the screen
                // is four levels down (Train ▸ CURRENT ▸ the 90-day door), so
                // this is the only way to iterate on it without tapping
                // through every launch. Needs a signed-in simulator; with no
                // auth it renders its own error state. Dev scaffolding —
                // remove with the rest when the surface settles.
                NavigationStack {
                    // Reads the real service, so it needs a signed-in
                    // simulator. To iterate without one, generate a local
                    // `ThreadPreviewData.swift` fixture and pass
                    // `preview: .previewLive` here — deliberately NOT
                    // committed, because that fixture is 90 days of real
                    // training memos.
                    TrainingThreadView()
                }
                .preferredColorScheme(.light)
            } else if CommandLine.arguments.contains("-trendsV2Preview") {
                NavigationStack {
                    // v2 rebuilt 2026-08-03: no previewMode / demoBiometrics
                    // any more — the five-signal surface has no demo-only
                    // section, so it renders the same way against seeded and
                    // live data.
                    TrendsV2View(
                        service: TrendsService(
                            preview: [],
                            days: TrendsDay.previewMonthRich,
                            keySessions: KeySession.previewLadder,
                            paceBands: .preview
                        )
                    )
                }
                .preferredColorScheme(.light)
            } else {
                rootScene
            }
            #else
            rootScene
            #endif
        }
    }

    private var rootScene: some View {
        RootView()
            .environment(AuthManager.shared)
            .environment(NetworkMonitor.shared)
            .environment(VitalManager.shared)
            .environmentObject(HealthKitManager.shared)
            .preferredColorScheme(.light)
            .background(KeyboardDismissHelper())
    }

    private func configureAppearance() {
        // Tab bar appearance lives on the custom `DripTabBar` view now
        // (App/DripTabBar.swift). There's no UIKit `UITabBar` in the
        // hierarchy anymore, so the old `UITabBarAppearance` block was
        // dead code and has been removed.

        // Navigation Bar - Clean editorial
        let navBarAppearance = UINavigationBarAppearance()
        navBarAppearance.configureWithOpaqueBackground()
        navBarAppearance.backgroundColor = UIColor(Color.drip.background)
        navBarAppearance.titleTextAttributes = [.foregroundColor: UIColor(Color.drip.textPrimary)]
        navBarAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor(Color.drip.textPrimary)]
        UINavigationBar.appearance().standardAppearance = navBarAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navBarAppearance
        UINavigationBar.appearance().compactAppearance = navBarAppearance
    }
}

// MARK: - MainTabView

struct MainTabView: View {
    @Environment(NetworkMonitor.self) private var networkMonitor
    @Environment(\.scenePhase) private var scenePhase
    /// Guards the foreground refresh so it doesn't fire on the launch
    /// transition, when the launch task is already fetching.
    @State private var didInitialRunsFetch = false
    @State private var selectedTab = 0
    /// Latches the first time Ask (tag 10) is opened. See the tab-10
    /// branch below — `CoachView` acts on appear, so it must not be
    /// mounted until the athlete actually asks for it.
    @State private var askEverOpened = false
    @State private var checkInManager = CoachCheckInManager()
    @State private var athleteProfileService = AthleteProfileService()
    @State private var activeDestination: AppDestination?
    @State private var showSettings = false
    /// Which skin renders. Only tab 0 reads it today — see DripTheme.swift.
    @State private var skinStore = DripSkinStore.shared

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
            // Routing: all tab views render simultaneously in a ZStack
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
            // Cost: 3 view trees alive at once instead of 1. Acceptable
            // for the user-visible win and avoids the refetch storm
            // (loadActivePlan / fitness-prediction / scheduled-workouts
            // each previously refired on every tab re-entry).
            //
            // Phase A (2026-07-13): 7 tabs → 4 (Log · Trends · Train ·
            // Coach). Train 2 + Signal evaluation tabs retired; Plan
            // folded into Train's CALENDAR mode. See
            // outputs/beta-design-overhaul-plan-2026-07-13.md.
            // 2026-07-28: Coach (The Read) retired → 3 tabs.
            // 2026-08-19: Week added (tag 11) — Log · Train · Trends · Week ·
            // Ask · Sheet. See WEEK-TAB-APPLY.md.
            // 2026-08-19: Charts → Ask in the same slot, and the DEBUG-only
            // Read tab dropped.
            // 2026-08-30: Sheet → Read (CoachReadView, tag 12) in the same
            // slot.
            // 2026-09-08: Week retired (tag 11) — removed outright, no slot
            // swap. The bar is Log · Train · Trends · Ask · Read in DEBUG
            // and release alike.
            ZStack {
                // Tab 0 — Log (front door)
                //
                // Two screens, one tab. `LogWildView` is Direction I; the
                // editorial `VoiceLogView` is untouched and still serves
                // the default skin. REDESIGN-SAFELY.md §5 tier 3: same
                // data, different bones — both read VoiceLogViewModel, so
                // flipping the skin never changes what is in the journal.
                //
                // Flip it in ☰ → the footer toggle.
                NavigationStack {
                    Group {
                        if skinStore.skin == .wild {
                            LogWildView()
                        } else {
                            VoiceLogView()
                        }
                    }
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

                // Tab 7 — The Read retired 2026-08-19. It ran
                // `TrendsReadTabView` beside Trends in DEBUG so the two
                // reads could be compared on device; Trends won, so DEBUG
                // and release now show the same tabs. The view stays in the
                // repo, unlinked.

                // Tab 5 — Trends 2 removed 2026-07-27. Trends is one tab now;
                // `TrendsInsightsTabView` stays in the repo, unlinked, and the
                // `trends-insights` edge function stays deployed.

                // Tab 1 — Train (the detail surface: CURRENT · CALENDAR ·
                // HISTORY). Phase A folded the Plan tab into CALENDAR —
                // the plan is a subset of training, not its own
                // destination; TrainingPlanView is pushed from there.
                // Train 2 (TrainingTabTwoView) retired as a tab.
                NavigationStack { TrainingTabView() }
                    .opacity(selectedTab == 1 ? 1 : 0)
                    .allowsHitTesting(selectedTab == 1)

                // Tab 10 — ASK. The free-text chat (`CoachView`), in the
                // slot Charts held until 2026-08-19. Not the analyzer chip
                // rail: a fixed catalog answering in cards is narrower than
                // the questions athletes actually ask, and those cards were
                // under-developed. `AskBar`/`AskAnswerCard`/`CoachAskSheet`
                // stay in the repo, unlinked.
                //
                // MOUNTED LAZILY, unlike every other tab here. The others
                // are free to render hidden because none of them act on
                // appear. `CoachView`'s `.task` requests HealthKit
                // authorization, loads the active plan and runs a fitness
                // prediction — eager mounting would throw the HealthKit
                // permission prompt at launch, at someone who never opened
                // Ask. `askEverOpened` latches on first visit and never
                // resets, so the thread survives tab switches from then on.
                //
                // Charts ("The Instruments") retired here. Mock data only,
                // no fetch, no service; `InstrumentsTabView` stays in the
                // repo, unlinked.
                if askEverOpened {
                    NavigationStack { AskTabView() }
                        .opacity(selectedTab == 10 ? 1 : 0)
                        .allowsHitTesting(selectedTab == 10)
                }

                // Tab 11 — Week retired 2026-09-08. The weekly decision
                // surface (three questions, three glass-box proposals) was
                // removed from the bar outright and `RunningLog/Week/` was
                // deleted (fixture-driven, never wired to a service). Restore
                // from git history if it comes back. Tag 11 is retired — do
                // not reuse it.

                // Tab 12 — THE READ (`CoachReadView`), restored 2026-08-30
                // in the slot The Sheet held. First shipped as Coach (tag 2,
                // removed 2026-07-28); the view waited in the repo, unlinked,
                // for exactly this restore. Mounted eagerly like every tab
                // except Ask: it has no `.task` and never spends a paid call
                // on appear — `DailyReadService.shared` is refreshed by the
                // launch task below, and generation only happens on explicit
                // intent (pull-to-refresh or the empty-state CTA). The web
                // coach portal remains canonical for coach work
                // (adaptive-coach-plan-builder-spec-2026-07-03).
                NavigationStack { CoachReadView() }
                    .opacity(selectedTab == 12 ? 1 : 0)
                    .allowsHitTesting(selectedTab == 12)

                // Tab 9 — The Sheet retired 2026-08-30; its slot went to The
                // Read. `SheetTabView` stays in the repo, unlinked, per the
                // restore-without-rebuilding convention. Tag 9 is retired —
                // do not reuse it.
            }
            .safeAreaInset(edge: .bottom) {
                DripTabBar(selected: $selectedTab)
            }
            .onChange(of: selectedTab) { _, tab in
                if tab == DripTab.ask.rawValue { askEverOpened = true }
            }
            // THE STATUS BAR BAND. Every tab is a ScrollView, and a
            // ScrollView draws its content through the top safe area. No
            // surface in this app has an opaque navigation bar to hide that
            // content — some hide the bar outright, the rest carry a
            // title-less transparent one — so headline type scrolled straight
            // into the clock and battery on all of them (Rio, 2026-08-18).
            //
            // One scrim here covers every tab, present and future, because
            // this is the container they all live in. Applying it per-tab
            // instead is the version of this fix that goes stale the next
            // time a tab is added. Sidebar and error banners are SIBLINGS of
            // this container in the outer ZStack, so they still draw above
            // the scrim — the offline bar keeps its deliberate bleed into
            // the notch. See `DripStatusBarScrim` in DesignSystem.swift.
            .dripStatusBarScrim()

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
                // The athlete's key-session declarations. One small query; the
                // calendar, journal and day sheet all read the same store, so
                // it has to be warm before any of them draws a star.
                async let keySessions: Void = KeySessionStore.shared.loadOverrides()
                async let maxHRSync: Void = AthleteSettingsService.syncMaxHRFromServer()
                // Beta-audit #10: keep athlete_settings.timezone current so
                // the Daily Read cron fires at the athlete's LOCAL morning.
                async let tzSync: Void = AthleteSettingsService.syncDeviceTimezone()
                async let healthKitSync: Void = {
                    // Auto-sync HealthKit workouts to training_logs on launch.
                    // Vital replaced by HealthKit for V1 — Terra integration planned for V1.1.
                    _ = await HealthKitManager.shared.requestAuthorization()
                    // Existing athletes granted a smaller type set and are never
                    // re-asked by the probe path, so the overnight trio would
                    // stay unrequested and silently empty. One-time top-up.
                    await HealthKitManager.shared.ensureAuthorizationCoversCurrentTypes()
                    // Publishes BOTH lists: `recentRuns` (HealthKit + Vital
                    // + Strava, merged — what every athlete-facing surface
                    // reads) and `recentWorkouts` (raw HealthKit — what the
                    // sync below must use). One fetch at launch; views read
                    // the published result instead of re-requesting auth on
                    // appear (the duplicate cost ~2 concurrent auth prompts).
                    await HealthKitManager.shared.refreshRecentRuns(limit: 30)
                    // HealthKit-only on purpose: syncUnloggedWorkouts writes
                    // its input into training_logs, and the Strava rows in the
                    // merged list are already there.
                    let hkWorkouts = await MainActor.run {
                        HealthKitManager.shared.recentWorkouts
                    }
                    if !hkWorkouts.isEmpty {
                        await WorkoutSyncService().syncUnloggedWorkouts(workouts: hkWorkouts)
                    }
                    // Sleep / resting HR / HRV → daily_biometrics. Feeds the
                    // recovery ledger's Overnight + Sleep factors, which have
                    // had no producer since Vital went quiet on 2026-04-03.
                    // Detached at background priority: it only writes to the
                    // DB — nothing on screen waits for it, so it shouldn't
                    // compete with first-paint fetches for the network.
                    Task.detached(priority: .background) {
                        await HealthBiometricsSync.shared.sync()
                    }
                }()
                _ = await (profile, paceProfile, paceZones, dailyRead, maxHRSync, tzSync, healthKitSync, keySessions)
            }
            .onChange(of: scenePhase) { _, newPhase in
                // Re-fire the daily Coach Read fetch every time the
                // app comes back to the foreground. Cheap when a
                // completed row already exists (one SELECT, two IN
                // queries); generates a fresh Read on first foreground
                // of a new day.
                if newPhase == .active {
                    // SELECT-only (default): hydrates today's Read if one
                    // exists; never triggers a paid LLM generation. See
                    // DailyReadService.refresh(generateIfMissing:).
                    Task { try? await DailyReadService.shared.refresh() }
                    // Pick up runs that landed while the app was backgrounded.
                    // iOS almost never kills a suspended app, so without this
                    // the recent-runs list could sit days out of date — which
                    // is exactly how a run showed in the journal feed but not
                    // in the Log tab's linked-run block (2026-08-24).
                    // Skipped on the first .active so it can't race the launch
                    // task's own fetch above.
                    if didInitialRunsFetch {
                        Task { await HealthKitManager.shared.refreshRecentRuns() }
                    } else {
                        didInitialRunsFetch = true
                    }
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
        // The tap target every TrainingDateline opens into — see
        // ActiveGoalStore.swift's "Environment door" section.
        .environment(\.openGoalEditor) { activeDestination = .goals }
        .fullScreenCover(item: $activeDestination) { destination in
            NavigationStack {
                destination.view
                    .environment(athleteProfileService)
                    // CheckInView reads @Environment(CoachCheckInManager.self)
                    // and this cover presents from the OUTER ZStack, so it is
                    // not a descendant of the inner TabView's injection at the
                    // top of this file. Same trap as AthleteProfileService
                    // above — without this line, ☰ → Check In crashes.
                    .environment(checkInManager)
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
                .environment(athleteProfileService)
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
    /// Check in — added 2026-08-21 with the wild skin. That skin drops the
    /// LOG RUN / CHECK IN control from the Log screen, so the mode needs a
    /// door of its own; this is it. Harmless under the editorial skin,
    /// where the on-screen control still exists too.
    case checkIn
    /// Niggles — the mention timeline. Aches are the thing runners go looking
    /// for by name, so the timeline gets its own door rather than living only
    /// as a card buried on the injuries screen.
    case niggles

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
        case .checkIn: CheckInView()
        case .niggles: NiggleTimelineScreen()
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
