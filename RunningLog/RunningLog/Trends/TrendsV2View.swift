//
//  TrendsV2View.swift
//  RunningLog · Trends
//
//  The Trends-v2 synthesis surface (see `trends-v2-spec-2026-07-30.md`). One
//  scroll; the calendar is the first and primary chart. Consumes
//  `TrendsService` — the same endpoint the v1 tab reads — but renders the
//  daily substrate (`days`) as a calendar rather than the weekly bars.
//
//  PARALLEL SURFACE: not yet swapped into the live 5-tab nav. It exists so
//  the v2 calendar is buildable and reviewable end-to-end while the rest of
//  the v2 sections (recovery, HRV, ladder, cost-of-work) are wired in. The
//  IA swap (v1 → v2) is a later, deliberate call.
//

import SwiftUI

/// A tapped pace-ladder zone, for the drill-down sheet.
struct ZoneSelection: Identifiable {
    let zone: String
    var id: String { zone }
}

struct TrendsV2View: View {
    @State private var service: TrendsService
    @State private var scale: TrendsCalendarScale = .month
    @State private var selectedZone: ZoneSelection?
    /// Demo-only overnight biometrics for the recovery card, until the
    /// `daily_biometrics` pipeline is live. Live builds pass nil → Tier 2
    /// renders its honest "no watch data" state.
    private let demoBiometrics: RecoveryBiometrics?
    /// True only for the design-scaffold boot (synthetic data). Off for the
    /// live surface, so the demo-only sections (efficiency curve) show an honest
    /// empty state against real data instead of fabricated numbers.
    private let previewMode: Bool

    init(
        service: TrendsService = .shared,
        previewMode: Bool = false,
        demoBiometrics: RecoveryBiometrics? = nil
    ) {
        _service = State(initialValue: service)
        self.previewMode = previewMode
        self.demoBiometrics = demoBiometrics
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 100)
        }
        .background(Color.drip.background)
        .task { await service.refresh() }
        .sheet(item: $selectedZone) { sel in
            TrendsZoneDetailView(zone: sel.zone, sessions: service.keySessions)
        }
    }

    // MARK: State-aware content

    @ViewBuilder
    private var content: some View {
        if !service.days.isEmpty {
            verdictSection
            EditorialRule().padding(.vertical, 24)
            calendarSection
            EditorialRule().padding(.vertical, 24)
            efficiencySection
            EditorialRule().padding(.vertical, 24)
            recoverySection
            EditorialRule().padding(.vertical, 24)
            spectrumSection
            EditorialRule().padding(.vertical, 24)
            ladderSection
            EditorialRule().padding(.vertical, 24)
            keySessionsSection
        } else if service.isLoading {
            loadingState
        } else if service.lastError != nil {
            EmptyStateView(
                variant: .error,
                eyebrow: "Couldn't load",
                title: "Your timeline didn't load. Try again in a moment.",
                cta: .init(label: "Retry") { Task { await service.refresh(force: true) } }
            )
            .padding(.top, 40)
        } else {
            EmptyStateView(
                variant: .dataPending,
                eyebrow: "Nothing to chart yet",
                title: "Your training shapes this view. Log a few runs and the calendar fills in."
            )
            .padding(.top, 40)
        }
    }

    // MARK: The verdict (the 5-second view)

    private var verdictSection: some View {
        let window = Array(service.days.suffix(scale.rawValue))
        let miles = window.reduce(0) { $0 + $1.miles }
        let keyCount = window.filter { $0.type == .key }.count
        let niggleCount = window.reduce(0) { $0 + $1.niggles.count }
        let modal = Self.modalMood(window)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("The 5-second view")
                    .font(.dripEyebrow(11))
                    .foregroundStyle(Color.drip.textSecondary)
                Spacer()
                scaleSwitch
            }

            if let first = window.first?.date, let last = window.last?.date {
                Text("\(Self.monthDay(first)) – \(Self.monthDay(last)) · last \(scale.rawValue / 7) weeks")
                    .font(.dripBody(12.5))
                    .italic()
                    .foregroundStyle(Color.drip.textTertiary)
            }

            // Chips — counted from the window, so they can't drift from the
            // charts below them (spec §3).
            HStack(spacing: 6) {
                chip(value: "\(Int(miles.rounded()))", label: "MI")
                chip(value: "\(keyCount)", label: "KEY SESSIONS")
                chip(value: "\(niggleCount)", label: niggleCount == 1 ? "NIGGLE" : "NIGGLES")
                if let modal { chip(value: modal.uppercased(), label: "MOST DAYS") }
            }
        }
    }

    private func chip(value: String, label: String) -> some View {
        HStack(spacing: 4) {
            Text(value)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.drip.textPrimary)
            Text(label)
                .font(.dripCaption(8))
                .foregroundStyle(Color.drip.textSecondary)
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(Capsule().fill(Color.drip.cardBackground))
        .overlay(Capsule().stroke(Color.drip.divider, lineWidth: 1))
    }

    /// Modal mood across the window (most-days), or nil when no feeling logged.
    private static func modalMood(_ days: [TrendsDay]) -> String? {
        var counts: [String: Int] = [:]
        for d in days { if let m = d.mood, !m.isEmpty { counts[m.lowercased(), default: 0] += 1 } }
        return counts.max { $0.value < $1.value }?.key
    }

    private static let monthAbbr = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                                    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// "2026-07-30" → "Jul 30".
    private static func monthDay(_ iso: String) -> String {
        let p = iso.split(separator: "-")
        guard p.count == 3, let m = Int(p[1]), (1...12).contains(m), let d = Int(p[2]) else { return iso }
        return "\(monthAbbr[m - 1]) \(d)"
    }

    // MARK: The calendar (primary chart)

    private var calendarSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("The block, as a calendar")
                    .font(.dripEyebrow(11))
                    .foregroundStyle(Color.drip.textSecondary)
                Spacer()
            }
            .padding(.bottom, 12)

            // The calendar rides on a white card so the paper day-cells read as
            // cells (page and cell are both warm paper; the card is the ground
            // that separates them — the prototype's `.card` on `--paper`).
            VStack(alignment: .leading, spacing: 0) {
                // Derived lede — states the conclusion before the picture.
                Text(TrendsCalendarLede.text(days: service.days, window: scale.rawValue))
                    .font(.dripBody(14.5))
                    .foregroundStyle(Color.drip.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 14)

                TrendsCalendarView(days: service.days, scale: scale)

                legend
                    .padding(.top, 14)

                Text(scale == .month
                     ? "Bar height is that day’s miles on a fixed 0–20 scale, so months compare. Mood runs along the bottom edge of every day, rest days too."
                     : "13 week-charts stacked. The mood strip cooling down the block is visible in one glance.")
                    .font(.dripCaption(10))
                    .foregroundStyle(Color.drip.textTertiary)
                    .padding(.top, 10)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.drip.cardBackground)
                    .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
            )
        }
    }

    // MARK: Recovery · convergence

    private var recoverySection: some View {
        let m = RecoveryModel(days: service.days, window: scale.rawValue, biometrics: demoBiometrics)
        let agreeing = m.signals.filter { $0.agrees }.count
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recovery")
                    .font(.dripEyebrow(11))
                    .foregroundStyle(Color.drip.textSecondary)
                Spacer()
                Text((m.verdict.alert ? "active" : "quiet") + (agreeing > 0 ? " · \(agreeing) agreeing" : ""))
                    .font(.dripCaption(9))
                    .foregroundStyle(Color.drip.textTertiary)
            }
            .padding(.bottom, 14)

            subEyebrow("Day to day · push or pull today?")
            card { TrendsRecoveryDayView(days: service.days, biometrics: demoBiometrics) }

            subEyebrow("The convergence · this week").padding(.top, 18)
            card { TrendsRecoveryView(days: service.days, scale: scale, biometrics: demoBiometrics) }

            subEyebrow("Week to week · are you overloading?").padding(.top, 18)
            card { TrendsRecoveryWeekView(days: service.days) }
        }
    }

    private func subEyebrow(_ text: String) -> some View {
        Text(text)
            .font(.dripCaption(9))
            .foregroundStyle(Color.drip.textSecondary)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.drip.cardBackground)
                    .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
            )
    }

    // MARK: Efficiency (is the engine getting cheaper?)

    private var efficiencySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Efficiency · the engine")
                    .font(.dripEyebrow(11))
                    .foregroundStyle(Color.drip.textSecondary)
                Spacer()
                Text("heart rate at pace")
                    .font(.dripCaption(9))
                    .foregroundStyle(Color.drip.textTertiary)
            }
            .padding(.bottom, 12)

            card {
                if previewMode {
                    TrendsEfficiencyView.preview
                } else {
                    // Real efficiency (heat-corrected HR at a pace band, split by
                    // period) needs the Group B stream aggregation — not wired
                    // yet, so show the honest gap rather than a demo curve.
                    EmptyStateView(
                        variant: .dataPending,
                        eyebrow: "Efficiency is still gathering",
                        title: "Heart-rate-at-pace trends fill in as your runs sync with heart-rate streams."
                    )
                }
            }
        }
    }

    // MARK: Key sessions (show me the actual runs)

    private var keySessionsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Key sessions")
                    .font(.dripEyebrow(11))
                    .foregroundStyle(Color.drip.textSecondary)
                Spacer()
                Text("the actual runs")
                    .font(.dripCaption(9))
                    .foregroundStyle(Color.drip.textTertiary)
            }
            .padding(.bottom, 12)

            card { TrendsKeySessionsView(sessions: service.keySessions) }
        }
    }

    // MARK: The pace spectrum (where the miles live)

    private var spectrumSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Pace spectrum")
                    .font(.dripEyebrow(11))
                    .foregroundStyle(Color.drip.textSecondary)
                Spacer()
                Text("every mile, sorted by pace")
                    .font(.dripCaption(9))
                    .foregroundStyle(Color.drip.textTertiary)
            }
            .padding(.bottom, 12)

            // Real-data surface — buckets the athlete's runs into pace zones
            // against their race-anchored zone table. Manages its own fetch
            // (SignalService + PaceZonesService), so it shows its own empty
            // state in the preview-seeded debug boot and live data signed in.
            PaceSignalView(embedded: true)
        }
    }

    // MARK: The pace ladder (per-zone trend)

    private var ladderSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("The pace ladder")
                    .font(.dripEyebrow(11))
                    .foregroundStyle(Color.drip.textSecondary)
                Spacer()
                Text("heat + hills priced out")
                    .font(.dripCaption(9))
                    .foregroundStyle(Color.drip.textTertiary)
            }
            .padding(.bottom, 12)

            TrendsPaceLadderView(
                sessions: service.keySessions,
                onSelect: { selectedZone = ZoneSelection(zone: $0) }
            )
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.drip.cardBackground)
                    .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
            )
        }
    }

    private var scaleSwitch: some View {
        HStack(spacing: 14) {
            ForEach(TrendsCalendarScale.allCases) { s in
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { scale = s }
                } label: {
                    Text(s.label.uppercased())
                        .font(.dripCaption(10))
                        .foregroundStyle(scale == s ? Color.drip.coral : Color.drip.textTertiary)
                        .overlay(alignment: .bottom) {
                            if scale == s {
                                Rectangle().fill(Color.drip.coral).frame(height: 1.5)
                                    .offset(y: 3)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem(color: Color.drip.coral, label: "key session")
            legendItem(color: Color.drip.textSecondary, label: "long run")
            legendItem(color: Color.drip.textTertiary.opacity(0.55), label: "easy")
            legendTick(color: Color.drip.injured, label: "niggle")
        }
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            Text(label.uppercased()).font(.dripCaption(8)).foregroundStyle(Color.drip.textTertiary)
        }
    }

    private func legendTick(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 3, height: 10)
            Text(label.uppercased()).font(.dripCaption(8)).foregroundStyle(Color.drip.textTertiary)
        }
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Building your calendar…")
                .font(.dripCaption(10))
                .foregroundStyle(Color.drip.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

// MARK: - Preview

#Preview("Trends v2 · calendar") {
    TrendsV2View(
        service: TrendsService(
            preview: [],
            days: TrendsDay.previewMonthRich,
            keySessions: KeySession.previewLadder
        ),
        previewMode: true,
        demoBiometrics: .previewGood
    )
}
