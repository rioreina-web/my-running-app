import io, sys, re

ROOT = "/sessions/rcw-0155cncschzqmhnzzarvtwqn/mnt/my-running-app/RunningLog/RunningLog/"

def rd(p):
    return io.open(ROOT + p, encoding="utf-8").read()

def wr(p, s):
    io.open(ROOT + p, "w", encoding="utf-8").write(s)

def sub(src, old, new, path):
    if old not in src:
        print("MISS in %s: %r" % (path, old[:80]))
        sys.exit(1)
    if src.count(old) != 1:
        print("AMBIGUOUS in %s (%d): %r" % (path, src.count(old), old[:80]))
        sys.exit(1)
    return src.replace(old, new)

# ---------- 1. DripTabBar.swift ----------
p = "App/DripTabBar.swift"
s = rd(p)

s = sub(s, """/// The four canonical tabs — the beta IA (Phase A of the design overhaul,
/// see `outputs/beta-design-overhaul-plan-2026-07-13.md`):
/// **Log · Trends · Train · Coach** — input → overview → detail → synthesis.
///
/// Raw values match the integer tags `MainTabView` uses for `selectedTab`
/// (the bar binds to `Binding<Int>`, so tags stay stable across IA
/// changes — `VoiceLogView` jumps to tag 2 (Coach) and `CoachReadView`
/// to tag 1 (Train) and both still work). Trends keeps its historical
/// non-contiguous tag 4 but is *declared* second so `allCases`
/// (declaration order) renders it in the second slot.
///
/// Retired in Phase A: `training2` (6, evaluation calendar — its
/// treatments were absorbed into Train's CALENDAR mode), `signal`
/// (5, pace-spectrum prototype — now pushed from Trends' GO DEEPER),
/// and `plan` (3 — Plan folded into Train's CALENDAR mode; the plan is
/// a subset of training, not its own destination).
enum DripTab: Int, CaseIterable, Identifiable {
    case log = 0
    case trends = 4
    case training = 1
    case coach = 2
""", """/// The three canonical tabs — **Log · Trends · Train** — input →
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
""", p)

s = sub(s, """    /// Trends 2 (tag 5, `TrendsInsightsTabView`) was removed 2026-07-27 when
    /// Trends was restructured into a single tab. The view file remains in the
    /// repo, unlinked.
    var label: String {
        switch self {
        case .log: "Log"
        case .trends: "Trends"
        case .training: "Train"
        case .coach: "Coach"
        }
    }""", """    /// Trends 2 (tag 5, `TrendsInsightsTabView`) was removed 2026-07-27 when
    /// Trends was restructured into a single tab. The view file remains in the
    /// repo, unlinked.
    var label: String {
        switch self {
        case .log: "Log"
        case .trends: "Trends"
        case .training: "Train"
        }
    }""", p)

s = sub(s, """/// - `badged`: tabs that should display a 6pt coral notification dot.
///   Wire from your host based on whatever signal you want to surface
///   (e.g. `coachViewModel.unreadCount > 0 ? [.coach] : []`).""", """/// - `badged`: tabs that should display a 6pt coral notification dot.
///   Wire from your host based on whatever signal you want to surface
///   (e.g. `planViewModel.hasUnseenChanges ? [.training] : []`).""", p)

s = sub(s, """/// - `disabled`: tabs that should render dimmed and reject taps. Useful
///   for gating `.plan` until a plan exists, etc.""", """/// - `disabled`: tabs that should render dimmed and reject taps. Useful
///   for gating a tab until its data exists, etc.""", p)

s = sub(s, """#Preview("Coach selected") {
    PreviewHost(initial: 2)
}

#Preview("Coach badged, Trends disabled") {
    PreviewHost(
        initial: 1,
        badged: [.coach],
        disabled: [.trends]
    )
}

#Preview("All states (run on SE 3 sim for 0pt home indicator)") {
    // Pick "iPhone SE (3rd generation)" as the active simulator to
    // verify the 0pt home-indicator clearance case. `.previewDevice` is
    // deprecated under the #Preview macro, so the device choice lives
    // with the simulator selection instead of the source.
    PreviewHost(initial: 2, badged: [.coach])
}""", """#Preview("Train selected") {
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
}""", p)

s = sub(s, """//  The Post Run Drip canonical tab bar""", """//  The Post Run Drip canonical tab bar""", p)
wr(p, s)
print("ok", p)

# ---------- 2. RunningLogApp.swift ----------
p = "App/RunningLogApp.swift"
s = rd(p)

s = sub(s, """                // Tab 2 — COACH (The Read) = the v5 editorial narrative
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
            }""", """                // Tab 2 — COACH (The Read) removed 2026-07-28. The tab bar
                // is Log · Trends · Train. `CoachReadView` stays in the repo,
                // unlinked, so the surface can be restored as a tab or as a
                // pushed screen without rebuilding it. The web coach portal
                // remains canonical for coach work
                // (adaptive-coach-plan-builder-spec-2026-07-03).
            }""", p)

s = sub(s, """            // Phase A (2026-07-13): 7 tabs → 4 (Log · Trends · Train ·
            // Coach). Train 2 + Signal evaluation tabs retired; Plan
            // folded into Train's CALENDAR mode. See
            // outputs/beta-design-overhaul-plan-2026-07-13.md.""", """            // Phase A (2026-07-13): 7 tabs → 4 (Log · Trends · Train ·
            // Coach). Train 2 + Signal evaluation tabs retired; Plan
            // folded into Train's CALENDAR mode. See
            // outputs/beta-design-overhaul-plan-2026-07-13.md.
            // 2026-07-28: Coach (The Read) retired → 3 tabs.""", p)

s = sub(s, """            // Routing: all 4 tab views render simultaneously in a ZStack""", """            // Routing: all tab views render simultaneously in a ZStack""", p)
s = sub(s, """            // Cost: 4 view trees alive at once instead of 1. Acceptable""", """            // Cost: 3 view trees alive at once instead of 1. Acceptable""", p)
wr(p, s)
print("ok", p)

# ---------- 3. VoiceLogView.swift ----------
p = "Workouts/VoiceLogView.swift"
s = rd(p)

s = sub(s, """                            // Coach check-in eyebrow line
                            if checkInManager.showBanner, checkInManager.pendingCheckIn != nil {
                                nsCoachCheckInLine
                            }

""", "", p)

s = sub(s, """    /// Coach check-in surfaced as a quiet single-line eyebrow.
    @ViewBuilder
    private var nsCoachCheckInLine: some View {
        Button {
            // Coach is tab 2 since the Train + Trends tabs were collapsed
            // into a single Training tab (slot 1).
            selectedTab.wrappedValue = 2
        } label: {
            HStack(spacing: 8) {
                Text("COACH HAS A CHECK-IN WAITING")
                    .font(.dripEyebrow(11))
                    .tracking(1.2)
                    .foregroundStyle(Color.drip.coral)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.drip.coral)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        checkInManager.dismiss()
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.drip.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

""", "", p)

# selectedTab is now unused in this view
s = sub(s, """    @Environment(\\.selectedTab) private var selectedTab\n""", "", p)
wr(p, s)
print("ok", p)

# ---------- 4. TrendsTabView.swift ----------
p = "Trends/TrendsTabView.swift"
s = rd(p)

s = sub(s, """            insights

            askBar
                .padding(.top, 18)
""", """            insights
""", p)

s = sub(s, """    // MARK: ask bar

    private var askBar: some View {
        Button {
            // Stage a question about the scrubbed (or latest) week, then
            // hand off to The Read (tab tag 2), which presents the composer.
            if let week = readoutWeek {
                coachAsk.stage(
                    question: Self.askPrompt(for: week),
                    focus: "week of \\(week.dateLabel)"
                )
            }
            selectedTab.wrappedValue = 2
        } label: {
            HStack(spacing: 10) {
                Text("Ask about a week, a pattern, a pace…")
                    .font(.dripBody(14))
                    .foregroundStyle(Color.drip.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ZStack {
                    Circle()
                        .fill(Color.drip.coral)
                        .frame(width: 30, height: 30)
                    Image(systemName: "mic.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Color.drip.cardBackground)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.drip.divider, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

""", "", p)

s = sub(s, """    /// Build the contextual question the ask bar stages for a given week.
    /// Kept light — the coach has the full picture; this just points it at
    /// the week the athlete was looking at.
    private static func askPrompt(for w: TrendsWeek) -> String {
        "Walk me through the week of \\(w.dateLabel) — \\(Int(w.miles)) mi. What stands out?"
    }
""", "", p)

s = sub(s, """    @Environment(\\.coachAsk) private var coachAsk\n""", "", p)
wr(p, s)
print("ok", p)
