//
//  DripTabBar.swift
//  RunningLog
//
//  The Post Run Drip canonical tab bar — dot + uppercase mono label, no
//  icons. Mirrors the JSX primitive at:
//    Post Run Drip Design System/ui_kits/ios_app/Primitives.jsx::TabBar
//  with token values from `ui_kits/ios_app/tokens.css` (`.tab-bar`,
//  `.tdot`, `.tlbl`).
//
//  Why this exists: the system `TabView` forces an icon-and-label layout
//  via `UITabBarAppearance`, which violates the spec — *"Stroked, not
//  filled. The only filled glyph in the system is the active-tab dot."*
//  (design-system/README.md). This view owns the bar surface end-to-end
//  so the active indicator can be the dot, and the dot only.
//
//  Behaviour summary
//  • Dot is the indicator: inactive = 1.5pt textTertiary stroke, active
//    = filled coral.
//  • Label is mono 10pt, uppercase, +0.12em tracked. Active label uses
//    textPrimary + semibold; inactive uses textSecondary regular.
//  • Selection fires a `UISelectionFeedbackGenerator` on commit.
//  • Press feedback is a 0.97 scale via custom `ButtonStyle`.
//  • Disabled tabs render at 0.32 opacity and reject hit tests.
//  • Badged tabs render a 6pt coral dot offset top-trailing of the label.
//  • Host applies via `.safeAreaInset(edge: .bottom) { DripTabBar(...) }`.
//    The bar's paper background ignores the bottom safe area so the home
//    indicator gutter paints the same warm paper instead of going white.
//

import SwiftUI
import UIKit

// MARK: - DripTab

/// The canonical tabs — **Log · Train · Trends · Ask** — input → what it
/// did → overview → why. (Ask took the fourth slot from Charts on
/// 2026-08-19; the settled IA before either was the three-tab
/// Log · Train · Trends.)
///
/// Raw values match the integer tags `MainTabView` uses for `selectedTab`
/// (the bar binds to `Binding<Int>`, so tags stay stable across IA
/// changes — `CoachReadView` jumps to tag 1 (Train) and still works).
/// ORDER COMES FROM DECLARATION ORDER, NOT FROM THE RAW VALUES: `allCases`
/// walks the cases as written, which is why Trends keeps its historical
/// non-contiguous tag 4 while sitting third. Reordering the bar means
/// moving a `case` line, never renumbering one.
///
/// Retired in Phase A: `training2` (6, evaluation calendar — its
/// treatments were absorbed into Train's CALENDAR mode), `signal`
/// (5, pace-spectrum prototype — now pushed from Trends' GO DEEPER),
/// and `plan` (3 — Plan folded into Train's CALENDAR mode; the plan is
/// a subset of training, not its own destination).
///
/// Retired 2026-07-28: `coach` (2, The Read). `CoachReadView` stays in
/// the repo, unlinked, so the surface can come back as its own tab or as
/// a pushed screen without rebuilding it.
///
/// Retired 2026-08-19: `instruments` (8, Charts) — replaced in its own
/// slot by `ask`, per the IA-cost note on `sheet` below. It was the
/// stated candidate: mock data only, no fetch, no service.
/// `InstrumentsTabView` stays in the repo, unlinked.
///
/// Retired 2026-08-19: `read` (7, The Read) — the DEBUG-only comparison
/// tab. It existed to run `TrendsReadTabView` beside Trends until one of
/// them won; Trends did. DEBUG and release are now the same four tabs,
/// which is the first time they have matched since Phase A.
/// `TrendsReadTabView` stays in the repo, unlinked.
enum DripTab: Int, CaseIterable, Identifiable {
    case log = 0
    /// Declared second as of 2026-08-11, so `allCases` renders Train in the
    /// slot beside Log. Log is where a run goes in and Train is where it
    /// lands — putting Trends and Read between them meant the two halves of
    /// one action sat at opposite ends of the bar. Tag 1 is unchanged, so
    /// every existing jump-to-tab call site (e.g. `CoachReadView` → tag 1)
    /// still arrives here.
    case training = 1
    case trends = 4
    /// Week (`WeekTabView`) — the weekly decision surface. Added
    /// 2026-08-19. Three questions (faster / absorbing / the marathon), each
    /// answered by its own signal cluster, ending in glass-box proposals that
    /// change the week only when tapped.
    ///
    /// Declared here so the bar reads Log · Train · Trends · Week · Ask ·
    /// Sheet: Week sits between the surface that observes (Trends) and the
    /// surface that holds the plan (Train's calendar), because it reads the
    /// first and writes the second.
    ///
    /// Tag 11 is fresh. 2, 3, 5, 6, 7 and 8 are retired tags, 9 is the Sheet
    /// and 10 is Ask — reusing any of them would land old jump-to-tab call
    /// sites here.
    case week = 11
    /// Ask (`AskTabView`) — the analysis surface: pick a question, get it
    /// answered from your own runs. Added 2026-08-19 in the slot Charts
    /// held, so the bar stays five wide.
    ///
    /// The `AskBar` at the foot of Trends is unchanged and still works —
    /// this tab is a second door to the same surface, not a move. Both
    /// share `AskService.shared`, whose `loadCatalog` guards on
    /// `catalogLoaded`, so two mounted bars never double-fetch.
    ///
    /// Tag 10 is fresh — 2, 3, 5, 6, 7 and 8 are all retired tags (see
    /// above) and 9 is the Sheet. Reusing 7 or 8 would land old
    /// jump-to-tab call sites here.
    case ask = 10
    /// The Sheet (`SheetTabView`) — the dense session table, added 2026-08-11.
    /// One row per SESSION (not per day and not per upload — see
    /// `SessionRollup.swift`), week-grouped, with tag chips and search.
    ///
    /// Declared last so the four established tabs keep their slots and their
    /// muscle memory. Moving it beside Log is a one-line change: move this
    /// `case` up, never renumber it.
    ///
    /// Tag 9 is fresh — 2, 3, 5, 6, 7 (Read) and 8 (Charts) are all retired
    /// tags; see above.
    ///
    /// IA COST: the bar is five tabs as of 2026-08-19 — Log · Train ·
    /// Trends · Ask — plus this one, in DEBUG and release alike. At 393pt
    /// five items is ~78pt each against a 44pt minimum touch target, which
    /// fits with room to spare now that Charts and the DEBUG Read are gone.
    /// Adding a sixth is possible but should still be argued for: the last
    /// two additions were both eventually spent replacing something.
    case sheet = 9

    var id: Int { rawValue }

    /// Display label. Rendered uppercase by the view; stored sentence-
    /// case here so future copy tweaks read naturally in source.
    ///
    /// Trends 2 (tag 5, `TrendsInsightsTabView`) was removed 2026-07-27 when
    /// Trends was restructured into a single tab. The view file remains in the
    /// repo, unlinked.
    var label: String {
        switch self {
        case .log: "Log"
        case .trends: "Trends"
        case .training: "Train"
        case .ask: "Ask"
        case .week: "Week"
        case .sheet: "Sheet"
        }
    }

    var accessibilityLabel: String {
        "\(label) tab"
    }
}

// MARK: - DripTabBar

/// The bar itself. Binds to the same `Int` tag the host already owns.
///
/// Optional props:
/// - `badged`: tabs that should display a 6pt coral notification dot.
///   Wire from your host based on whatever signal you want to surface
///   (e.g. `planViewModel.hasUnseenChanges ? [.training] : []`).
/// - `disabled`: tabs that should render dimmed and reject taps. Useful
///   for gating a tab until its data exists, etc.
struct DripTabBar: View {
    @Binding var selected: Int
    var badged: Set<DripTab> = []
    var disabled: Set<DripTab> = []

    // Persisted feedback generator so we don't pay alloc cost on each tap.
    private let haptic = UISelectionFeedbackGenerator()

    var body: some View {
        VStack(spacing: 0) {
            // Top hairline — 1pt rule per `.tab-bar { border-top: 1px solid
            // var(--rule); }`. Sits flush against the bar surface, not the
            // host content above.
            Rectangle()
                .fill(Color.drip.divider)
                .frame(height: 1)
                .frame(maxWidth: .infinity)

            HStack(spacing: 0) {
                ForEach(DripTab.allCases) { tab in
                    DripTabBarItem(
                        tab: tab,
                        isSelected: selected == tab.rawValue,
                        isBadged: badged.contains(tab),
                        isDisabled: disabled.contains(tab),
                        action: { tap(tab) }
                    )
                    .frame(maxWidth: .infinity)
                }
            }
            // Vertical padding matches the JSX: 10pt top, 12pt bottom of
            // the active content area. Anything below is home-indicator
            // safe-area gutter, painted by the background below.
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
        // Paper background extends through the bottom safe area so the
        // home-indicator gutter doesn't reveal whatever is behind the
        // bar (which would be `Color.white` from the SwiftUI default).
        .background(
            Color.drip.background
                .ignoresSafeArea(edges: .bottom)
        )
        .onAppear { haptic.prepare() }
    }

    private func tap(_ tab: DripTab) {
        guard !disabled.contains(tab) else { return }
        guard selected != tab.rawValue else { return }
        haptic.selectionChanged()
        // Prepare the next one — selection feedback generators want to
        // be re-armed after firing so the next tap is low-latency.
        haptic.prepare()
        selected = tab.rawValue
    }
}

// MARK: - DripTabBarItem

private struct DripTabBarItem: View {
    let tab: DripTab
    let isSelected: Bool
    let isBadged: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                // Indicator dot. Inactive = 6pt stroked circle (1.5pt
                // textTertiary). Active = filled coral. We render BOTH
                // states with the same 6×6 frame so the bar doesn't
                // shift when selection changes.
                ZStack {
                    Circle()
                        .stroke(Color.drip.textTertiary, lineWidth: 1.5)
                        .opacity(isSelected ? 0 : 1)
                    Circle()
                        .fill(Color.drip.coral)
                        .opacity(isSelected ? 1 : 0)
                }
                .frame(width: 6, height: 6)

                // Label with optional badge overlay.
                ZStack(alignment: .topTrailing) {
                    Text(tab.label.uppercased())
                        .font(.dripEyebrow(10))
                        // 0.12em at 10pt = 1.2 — matches the CSS spec
                        // `.tlbl { letter-spacing: 0.12em }`.
                        .tracking(1.2)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .foregroundStyle(
                            isSelected
                                ? Color.drip.textPrimary
                                : Color.drip.textSecondary
                        )
                        .fixedSize()

                    if isBadged {
                        // 6pt coral dot, offset just clear of the label's
                        // upper-right corner. Not a count badge — the
                        // editorial system doesn't do numbers in chrome.
                        Circle()
                            .fill(Color.drip.coral)
                            .frame(width: 6, height: 6)
                            .offset(x: 8, y: -3)
                            .accessibilityHidden(true)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(DripTabPressStyle())
        .opacity(isDisabled ? 0.32 : 1)
        .allowsHitTesting(!isDisabled)
        .accessibilityLabel(tab.accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(isBadged ? "Has new activity" : "")
    }
}

// MARK: - Press feedback

/// 0.97 scale on press, with a subtle ease so it doesn't feel laggy.
/// Reused by every bar item — kept private to this file so it doesn't
/// leak into the wider DesignSystem surface area.
private struct DripTabPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(
                .easeOut(duration: configuration.isPressed ? 0.05 : 0.18),
                value: configuration.isPressed
            )
    }
}

// MARK: - Previews

#Preview("Default — Log selected") {
    PreviewHost(initial: 0)
}

#Preview("Train selected") {
    PreviewHost(initial: 1)
}

#Preview("Train badged, Trends disabled") {
    PreviewHost(
        initial: 0,
        badged: [.training],
        disabled: [.trends]
    )
}

#Preview("All states (run on SE 3 sim for 0pt home indicator)") {
    // Pick "iPhone SE (3rd generation)" as the active simulator to
    // verify the 0pt home-indicator clearance case. `.previewDevice` is
    // deprecated under the #Preview macro, so the device choice lives
    // with the simulator selection instead of the source.
    PreviewHost(initial: 1, badged: [.training])
}

/// Lightweight wrapper so each preview can own its own `selected` state.
private struct PreviewHost: View {
    @State var selected: Int
    var badged: Set<DripTab> = []
    var disabled: Set<DripTab> = []

    init(initial: Int, badged: Set<DripTab> = [], disabled: Set<DripTab> = []) {
        _selected = State(initialValue: initial)
        self.badged = badged
        self.disabled = disabled
    }

    var body: some View {
        ZStack {
            Color.drip.background.ignoresSafeArea()
            VStack {
                Spacer()
                Text("Selected: \(selected)")
                    .font(.dripBody(15))
                    .foregroundStyle(Color.drip.textSecondary)
                Spacer()
            }
        }
        .safeAreaInset(edge: .bottom) {
            DripTabBar(selected: $selected, badged: badged, disabled: disabled)
        }
    }
}
