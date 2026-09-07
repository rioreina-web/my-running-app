//
//  DripTabBar.swift
//  RunningLog
//
//  Editorial bottom tab bar — replaces the system TabView chrome with the
//  canonical Post Run Drip pattern: 6pt coral dot above a 10pt uppercase
//  monospaced label, +0.12em tracking, no icons.
//
//  Token mapping (from App/DesignSystem.swift):
//    paper / background  → Color.drip.background
//    rule / divider      → Color.drip.divider
//    ink-2 (inactive)    → Color.drip.textSecondary
//    ink-3 (dot border)  → Color.drip.textTertiary
//    coral (accent)      → Color.drip.coral
//    ink (active label)  → Color.drip.textPrimary
//
//  Drop the view into a `.safeAreaInset(edge: .bottom)` on the active
//  screen — that's the only correct way to keep home-indicator clearance
//  honest across iPhone SE through 16 Pro Max.

import SwiftUI

// MARK: - DripTab

/// The five surfaces of the app, in tab-bar order.
/// `rawValue` is the legacy `Int` tag MainTabView's `@State selectedTab`
/// already binds to (0 = Log, 1 = Training, 2 = Trends, 3 = Coach, 4 = Plan),
/// so adopting this enum doesn't churn the rest of the app — the
/// `selectedTab` Int binding still works via `DripTab(rawValue: idx)`.
enum DripTab: Int, CaseIterable, Hashable {
    case log    = 0
    case train  = 1
    case trends = 2
    case coach  = 3
    case plan   = 4

    /// Display label. Shortened roster per spec — TRAINING → TRAIN
    /// so all five labels fit cleanly at 10pt mono.
    var label: String {
        switch self {
        case .log:    "Log"
        case .train:  "Train"
        case .trends: "Trends"
        case .coach:  "Coach"
        case .plan:   "Plan"
        }
    }
}

// MARK: - DripTabBar

/// The bar itself. Binds to an `Int` selection so the host's existing
/// `@State private var selectedTab = 0` keeps working without a refactor.
struct DripTabBar: View {
    @Binding var selected: Int

    /// Tabs that should render a badge dot to the right of the label.
    /// Pass an empty set for the default case.
    var badged: Set<DripTab> = []

    /// Tabs that should render at 0.32 opacity and refuse taps.
    /// Pass an empty set for the default case.
    var disabled: Set<DripTab> = []

    var body: some View {
        VStack(spacing: 0) {
            // Hairline above the bar — separates it from screen content.
            Rectangle()
                .fill(Color.drip.divider)
                .frame(height: 1)

            HStack(spacing: 0) {
                ForEach(DripTab.allCases, id: \.self) { tab in
                    DripTabItem(
                        tab: tab,
                        isActive: selected == tab.rawValue,
                        isBadged: badged.contains(tab),
                        isDisabled: disabled.contains(tab),
                        onTap: { selected = tab.rawValue }
                    )
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
        .background(Color.drip.background)
        // Crisp selection haptic — matches the editorial-restrained motion
        // language in the rest of the app. Fires on every selection change.
        .sensoryFeedback(.selection, trigger: selected)
    }
}

// MARK: - DripTabItem

private struct DripTabItem: View {
    let tab: DripTab
    let isActive: Bool
    let isBadged: Bool
    let isDisabled: Bool
    let onTap: () -> Void

    @State private var isPressed = false

    var body: some View {
        VStack(spacing: 7) {
            dot
            label
        }
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .opacity(isDisabled ? 0.32 : 1.0)
        .contentShape(Rectangle())
        .allowsHitTesting(!isDisabled)
        // Two separate animations — the active-state crossfade is slower
        // and softer (150ms) than the press feedback (80ms).
        .animation(.easeOut(duration: 0.15), value: isActive)
        .animation(.easeOut(duration: 0.08), value: isPressed)
        .onTapGesture { onTap() }
        // Touch-down highlight without committing the tap. Releasing
        // outside the tab still cancels because onEnded fires.
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded   { _ in isPressed = false }
        )
    }

    // MARK: subviews

    /// Active = filled coral. Inactive = ink-3 stroked.
    private var dot: some View {
        ZStack {
            Circle()
                .strokeBorder(
                    isActive ? Color.drip.coral : Color.drip.textTertiary,
                    lineWidth: 1.5
                )
            if isActive {
                Circle().fill(Color.drip.coral)
            }
        }
        .frame(width: 6, height: 6)
        // Touch-down shrink the dot a touch — gives the press a felt
        // mechanical click without animating the whole tab too aggressively.
        .scaleEffect(isPressed ? 0.65 : 1.0)
    }

    private var label: some View {
        Text(tab.label.uppercased())
            .font(.system(size: 10,
                          weight: isActive ? .semibold : .regular,
                          design: .monospaced))
            .tracking(1.2) // 0.12em × 10pt = 1.2pt
            .foregroundStyle(isActive
                ? Color.drip.textPrimary
                : Color.drip.textSecondary)
            // Badge sits to the right of the label so it never crowds
            // the dot column. The 2pt paper halo keeps it visually
            // separate from any neighbouring active dot.
            .overlay(alignment: .topTrailing) {
                if isBadged {
                    Circle()
                        .fill(Color.drip.coral)
                        .frame(width: 6, height: 6)
                        .overlay(
                            Circle().stroke(Color.drip.background, lineWidth: 2)
                        )
                        .offset(x: 9, y: -14)
                }
            }
    }
}

// MARK: - Preview

#Preview("Light · default") {
    StatefulPreview(initial: 0) { selected in
        VStack(spacing: 0) {
            Color.drip.background.overlay(
                Text("Screen body")
                    .font(.dripBody(15))
                    .foregroundStyle(Color.drip.textSecondary)
            )
            DripTabBar(selected: selected)
        }
    }
    .ignoresSafeArea(edges: .top)
}

#Preview("With badge + disabled") {
    StatefulPreview(initial: 1) { selected in
        VStack(spacing: 0) {
            Color.drip.background.overlay(
                Text("Train active · Coach has 1 new · Plan disabled")
                    .font(.dripBody(13))
                    .foregroundStyle(Color.drip.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding()
            )
            DripTabBar(
                selected: selected,
                badged: [.coach],
                disabled: [.plan]
            )
        }
    }
    .ignoresSafeArea(edges: .top)
}

/// Tiny helper so SwiftUI previews can host an `@State` binding.
private struct StatefulPreview<Content: View>: View {
    @State private var value: Int
    let content: (Binding<Int>) -> Content

    init(initial: Int, @ViewBuilder content: @escaping (Binding<Int>) -> Content) {
        self._value = State(initialValue: initial)
        self.content = content
    }

    var body: some View { content($value) }
}
