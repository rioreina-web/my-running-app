# Tab Bar Port · Implementation Plan

**Where:** `RunningLog/RunningLog/App/`
**Spec:** `Post Run Drip Design System/outputs/Tab Bar Spec.html`
**Decision:** V1 Canonical · Shortened roster (`Log · Train · Trends · Coach · Plan`) · light mode default.

---

## What to land

Three changes, in order. Each one is independently reversible until you commit.

1. **Add `App/DripTabBar.swift`** — the new component (see `outputs/DripTabBar.swift` in this design-system project, ready to copy).
2. **Rewrite `MainTabView.body`** in `App/RunningLogApp.swift` — swap `TabView` for a `switch` + `.safeAreaInset(edge: .bottom) { DripTabBar(...) }`.
3. **Delete the `UITabBarAppearance` block** in `configureAppearance()` — it's dead code once `TabView` is gone.

---

## 1 · `DripTabBar.swift`

Drop the file into `RunningLog/RunningLog/App/` (sibling to `RunningLogApp.swift` and `DesignSystem.swift`).

The file is self-contained. Two public types:

- `enum DripTab` — `.log .train .trends .coach .plan`, with `rawValue: Int` matching your existing `selectedTab` integer tags. **No host refactor needed** — the bar binds to `Binding<Int>`.
- `struct DripTabBar` — the view itself. Two optional props: `badged: Set<DripTab>` (renders a 6pt coral dot offset from the label) and `disabled: Set<DripTab>` (opacity 0.32 + no hit-test).

Previews included. Compile and confirm the bar looks right in isolation before touching `MainTabView`.

---

## 2 · `MainTabView` rewrite

In `App/RunningLogApp.swift`, the current shape (line 85-149) is:

```swift
TabView(selection: $selectedTab) {
    NavigationStack { VoiceLogView()... }.tag(0).tabItem { Label("Log", ...) }
    NavigationStack { TrainingTabView() }.tag(1).tabItem { Label("Training", ...) }
    NavigationStack { TrendsTabView() }  .tag(2).tabItem { Label("Trends", ...) }
    NavigationStack { CoachReadView() }  .tag(3).tabItem { Label("Coach", ...) }
    NavigationStack {
        if isCoachMode { CoachTabView() } else { TrainingPlanView() }
    }.tag(4).tabItem { Label("Plan / Coach", ...) }
}
.tint(Color.drip.coral)
```

Replace with:

```swift
Group {
    switch selectedTab {
    case 0:
        NavigationStack {
            VoiceLogView()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showSettings = true } label: {
                            Image(systemName: "gearshape")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(Color.drip.textSecondary)
                        }
                    }
                }
        }
    case 1: NavigationStack { TrainingTabView() }
    case 2: NavigationStack { TrendsTabView() }
    case 3: NavigationStack { CoachReadView() }
    case 4:
        NavigationStack {
            if isCoachMode { CoachTabView() } else { TrainingPlanView() }
        }
    default: NavigationStack { VoiceLogView() }
    }
}
.safeAreaInset(edge: .bottom) {
    DripTabBar(selected: $selectedTab)
}
```

Drop `.tint(Color.drip.coral)` — there's no system TabView to tint anymore.
The custom bar owns its colors.

### State preservation tradeoff

The `switch` tears down each tab's view on change → loses scroll position
and any `@State` inside. For most of your screens that's fine (they fetch
on appear). If a specific tab needs to preserve state across selection
(e.g. an in-progress edit in `VoiceLogView`), wrap that one in a
`@StateObject` view model held at the `MainTabView` level so the data
survives the view teardown.

If you want **all five tabs to keep their state** like `TabView` did,
swap the `switch` for a `ZStack` with `.opacity` + `.allowsHitTesting`:

```swift
ZStack {
    NavigationStack { VoiceLogView()... }
        .opacity(selectedTab == 0 ? 1 : 0)
        .allowsHitTesting(selectedTab == 0)
    NavigationStack { TrainingTabView() }
        .opacity(selectedTab == 1 ? 1 : 0)
        .allowsHitTesting(selectedTab == 1)
    // ...etc
}
```

Heavier memory; identical UX to the old `TabView`. **My recommendation:**
start with the `switch` — it's simpler and most screens won't notice.
Promote to `ZStack` only for the tabs where users complain.

---

## 3 · Delete dead `UITabBarAppearance` config

In `configureAppearance()` (lines 41-55 of `RunningLogApp.swift`), delete:

```swift
// Tab Bar - Warm paper background, burnt orange accent
let tabBarAppearance = UITabBarAppearance()
tabBarAppearance.configureWithOpaqueBackground()
tabBarAppearance.backgroundColor = UIColor(Color(hex: "F5F3F0"))
tabBarAppearance.stackedLayoutAppearance.selected.iconColor = UIColor(Color(hex: "D4592A"))
tabBarAppearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor(Color(hex: "D4592A"))]
tabBarAppearance.stackedLayoutAppearance.normal.iconColor = UIColor(Color(hex: "6B6560"))
tabBarAppearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor(Color(hex: "6B6560"))]
UITabBar.appearance().standardAppearance = tabBarAppearance
UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
```

**Keep** the `UINavigationBarAppearance` block below it — that one's still in use.

---

## QA checklist

Do these in order. Stop and fix at the first ✗.

| # | Check | Where |
|---|---|---|
| 1 | Compiles | Build |
| 2 | Bar renders with dot + label, no icons | Light mode, any screen |
| 3 | Coral dot fills + label bolds on tab tap | All five tabs |
| 4 | Selection haptic fires on commit | Device only — sim won't haptic |
| 5 | Pressed scale (0.97) feels intentional, not laggy | Hold a tab |
| 6 | Home indicator clearance is correct | iPhone 16 Pro (34pt) **and** iPhone SE 3rd gen (0pt) |
| 7 | Scroll content does not paint under the bar | Scroll any tab to the bottom |
| 8 | `isCoachMode` toggle still swaps tab 4's content (Plan ↔ Coach) | Settings → Coach mode |
| 9 | Sidebar overlay still sits on top of the bar | Open sidebar from any tab |
| 10 | Error / offline banners still position correctly above content | Toggle airplane mode |

---

## What I'm **not** including (and why)

- **Tab roster IA change.** Spec roster (LOG · TRAIN · TRENDS · COACH · RUNS) was considered and rejected — keeping `Plan` because the codebase has a real `TrainingPlanView` and the spec's `RUNS` would be a fifth surface that doesn't exist yet. If you want RUNS later, swap `.plan → .runs` in the enum and route case 4 to a new `RunsView`.
- **Badge wiring.** `DripTabBar` accepts a `badged: Set<DripTab>` param but I'm not wiring it to live data. When you want Coach's unread count to surface, pass `badged: [.coach]` from `MainTabView` based on `coachViewModel.unreadCount > 0`.
- **Disabled state.** Same as above — `disabled: Set<DripTab>` is there if you ever need it (e.g. `Plan` before a plan is generated), but I'm not gating any tab in this initial port.
- **Dark mode wiring.** The bar honours `Color.drip.background` etc., so it automatically inverts when those tokens get a dark variant — but your `DripColors` struct currently only ships light values. That's a separate piece of work in `DesignSystem.swift`.

---

**Estimated total scope:** one new file (~190 lines including previews + comments), ~80 lines changed in `RunningLogApp.swift`, ~10 lines deleted from `configureAppearance()`. A focused half-day including device QA.
