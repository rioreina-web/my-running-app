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

/// The three canonical tabs — **Log · Trends · Train** — input →
/// overview → detail.
///
/// Raw values match the integer tags `MainTabView` uses for `selectedTab`
/// (the bar binds to `Binding<Int>`, so tags stay stable across IA
/// changes — `CoachReadView` jumps to tag 1 (Train) and still works).
/// Trends keeps its historical non-contiguous tag 4 but is *declared*
/// second so `allCases` (declaration order) renders it in the second slot.
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
enum DripTab: Int, CaseIterable, Identifiable {
    case log = 0
    case trends = 4
    case training = 1

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
