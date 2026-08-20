//
//  InstrumentsCardKit.swift
//  RunningLog · Trends
//
//  Shared pieces of the Charts tab ("The Instruments"): the expandable card
//  container, stat rows, legend, chart furniture — and `InstrumentsData`, the
//  derivation layer that turns `TrendsService`'s real rows into the series each
//  card draws.
//
//  **There is no mock data in this surface.** Every number a card renders is
//  derived from `TrendsService` (`weeks` · `days` · `keySessions` · `bandLaps`),
//  which is the same real backend feed `TrendsV2View` uses. A card with no rows
//  renders `EmptyStateView`, never a placeholder number and never an em-dash
//  (hard rule #8).
//
//  Headlines are computed from the series too, not authored. If a card says
//  "52 to 72 across 13 weeks", those three numbers came out of `weeks`. This
//  mirrors the Ask surface's rule — if a number is not in the data, it does not
//  exist — applied to card copy.
//
//  One coral element per card, maximum; coral always marks "now" (the latest
//  bar, today's dot, the target line). Mood colour never appears without its
//  word alongside, because sage and warm-grey are not separable for a
//  colour-blind reader.
//

import SwiftUI

// MARK: - InstrumentCard

/// Collapsed: eyebrow · computed headline · italic sub · right-aligned stat ·
/// chevron. Expanded: the card's chart content under a hairline.
struct InstrumentCard<Trailing: View, Content: View>: View {
    let eyebrow: String
    let title: String
    let sub: String
    @ViewBuilder let trailing: () -> Trailing
    @ViewBuilder let content: () -> Content

    @State private var isOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.3)) { isOpen.toggle() }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(eyebrow)
                            .font(.dripEyebrow(11))
                            .tracking(1.3)
                            .foregroundStyle(Color.drip.textSecondary)
                        Text(title)
                            .font(.dripDisplay(21))
                            .foregroundStyle(Color.drip.textPrimary)
                            .lineSpacing(1)
                            .padding(.top, 7)
                            .multilineTextAlignment(.leading)
                        if !sub.isEmpty {
                            Text(sub)
                                .font(.system(size: 12, design: .serif).italic())
                                .foregroundStyle(Color.drip.textTertiary)
                                .lineSpacing(2)
                                .padding(.top, 6)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    trailing()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.drip.textTertiary)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                        .padding(.top, 3)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(isOpen ? "Collapses the chart" : "Expands the chart")

            if isOpen {
                Hairline().padding(.top, 14)
                content()
                    .padding(.top, 14)
                    .transition(.opacity)
            }
        }
        .padding(20)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)
        .padding(.top, 16)
    }
}

/// The right-side collapsed stat: mono value with optional small suffix.
struct InstrumentStat: View {
    let value: String
    var suffix: String?
    let caption: String

    var body: some View {
        VStack(alignment: .trailing, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value)
                    .font(.dripStat(19))
                    .foregroundStyle(Color.drip.textPrimary)
                if let suffix {
                    Text(suffix)
                        .font(.dripStat(11))
                        .foregroundStyle(Color.drip.textSecondary)
                }
            }
            Text(caption)
                .font(.dripEyebrow(8.5))
                .tracking(0.85)
                .foregroundStyle(Color.drip.textTertiary)
        }
        .fixedSize()
        .padding(.top, 1)
    }
}

/// Stat row under a chart. Every item is a derived figure; a card omits an item
/// rather than showing a placeholder for a number it doesn't have.
struct InstrumentStatRow: View {
    struct Item: Identifiable {
        let id = UUID()
        let value: String
        let unit: String
        let detail: String
    }

    let items: [Item]

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(item.value)
                            .font(.dripStat(16))
                            .foregroundStyle(Color.drip.textPrimary)
                        Text(item.unit)
                            .font(.dripEyebrow(8))
                            .tracking(0.8)
                            .foregroundStyle(Color.drip.textSecondary)
                    }
                    Text(item.detail)
                        .font(.dripEyebrow(8))
                        .tracking(0.64)
                        .foregroundStyle(Color.drip.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.top, 14)
        .overlay(alignment: .top) { Hairline() }
        .padding(.top, 14)
    }
}

/// A single derived observation, stated as fact. Uses the canonical coral-at-50%
/// left bar. Unlike a coach note this is never authored prose — the caller
/// builds the string from numbers already on screen.
struct InstrumentNote: View {
    let eyebrow: String
    let text: String

    init(_ text: String, eyebrow: String = "WHAT THE DATA SAYS") {
        self.text = text
        self.eyebrow = eyebrow
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(eyebrow)
                .font(.dripEyebrow(8.5))
                .tracking(0.85)
                .foregroundStyle(Color.drip.textTertiary)
            Text(text)
                .font(.dripBody(13))
                .foregroundStyle(Color.drip.textPrimary)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 12)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.drip.coral.opacity(0.5))
                .frame(width: 2)
        }
        .padding(.top, 16)
    }
}

/// One legend entry: swatch + tracked micro label.
struct InstrumentLegendItem: View {
    enum Swatch {
        case fill(Color)
        case line(Color)
        case dot(Color)
        case none
    }

    let swatch: Swatch
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            switch swatch {
            case .fill(let color):
                RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            case .line(let color):
                Capsule().fill(color).frame(width: 10, height: 2)
            case .dot(let color):
                Circle().fill(color).frame(width: 7, height: 7)
            case .none:
                EmptyView()
            }
            Text(label)
                .font(.dripEyebrow(8.5))
                .tracking(0.85)
                .foregroundStyle(Color.drip.textSecondary)
                // Without this the item hands back a width of whatever it is
                // given, and a squeezed row wraps every label one letter per
                // line. That is what turned a six-item legend into a wall of
                // vertical characters on device (2026-08-09).
                .fixedSize(horizontal: true, vertical: false)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

/// Left-aligned wrapping row. Items keep their natural width and spill onto the
/// next line instead of being compressed.
///
/// `InstrumentLegendRow` used to be a plain `HStack`, which is correct for
/// three items and catastrophic for six: SwiftUI shrinks every child to fit,
/// and tracked 8.5pt uppercase text under pressure wraps per character. A card
/// legend has no fixed item count, so the row has to be able to wrap.
struct DripFlowLayout: Layout {
    var hSpacing: CGFloat = 13
    var vSpacing: CGFloat = 7

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(_ subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let projected = current.indices.isEmpty
                ? size.width
                : current.width + hSpacing + size.width
            if !current.indices.isEmpty, projected > maxWidth {
                rows.append(current)
                current = Row(indices: [index], width: size.width, height: size.height)
            } else {
                current.indices.append(index)
                current.width = projected
                current.height = max(current.height, size.height)
            }
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        let laid = rows(subviews, maxWidth: maxWidth)
        let height = laid.reduce(0) { $0 + $1.height }
            + CGFloat(max(laid.count - 1, 0)) * vSpacing
        let width = laid.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var y = bounds.minY
        for row in rows(subviews, maxWidth: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + hSpacing
            }
            y += row.height + vSpacing
        }
    }
}

struct InstrumentLegendRow: View {
    let items: [(InstrumentLegendItem.Swatch, String)]

    var body: some View {
        DripFlowLayout(hSpacing: 13, vSpacing: 7) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                InstrumentLegendItem(swatch: item.0, label: item.1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 12)
        .overlay(alignment: .top) { Hairline() }
        .padding(.top, 12)
    }
}

// MARK: - Chart furniture

/// Marker triangle for key/field-test points.
struct InstrumentTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

extension Text {
    /// Axis tick / chart micro-label.
    func instrumentTick(color: Color = Color.drip.textTertiary) -> some View {
        font(.dripEyebrow(8))
            .tracking(0.64)
            .foregroundStyle(color)
    }
}

/// The card-level empty state. Every card routes through this when its series is
/// empty, so a card never renders an invented number or an em-dash placeholder.
struct InstrumentEmpty: View {
    let title: String

    var body: some View {
        EmptyStateView(variant: .dataPending, title: title)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
    }
}

// MARK: - InstrumentsData (derivation)

/// Pure derivations over `TrendsService`'s real rows. No network, no storage,
/// no invented values — each helper either returns real figures or returns
/// nothing so the caller can show its empty state.
enum InstrumentsData {
    // MARK: Volume

    /// Weekly miles, oldest → newest, dropping leading zero-mile weeks so the
    /// chart starts where the athlete's history actually starts.
    static func weeklyMiles(_ weeks: [TrendsWeek]) -> [(label: String, miles: Double)] {
        let rows = weeks.map { (label: $0.dateLabel, miles: $0.miles) }
        guard let first = rows.firstIndex(where: { $0.miles > 0 }) else { return [] }
        return Array(rows[first...])
    }

    /// Trailing 4-week rolling mean, aligned to `values`.
    static func rollingMean(_ values: [Double], window: Int = 4) -> [Double] {
        values.indices.map { i in
            let slice = values[max(0, i - window + 1)...i]
            return slice.reduce(0, +) / Double(slice.count)
        }
    }

    // MARK: Key pace

    /// Weekly key-session pace (sec/mi) for weeks that actually had quality work.
    ///
    /// **Superseded 2026-08-09 — do not build on this.** Card 02 no longer
    /// reads it. One averaged pace per week silently mixes a 400m rep session
    /// with a marathon-pace long run, carries no `training_log_id` so nothing
    /// can be opened from it, and drops quality-free weeks without saying so.
    /// `KeyPaceBuilder.read(sessions:bandLaps:settings:window:)` reads
    /// `TrendsService.keySessions` instead — one row per session, with its
    /// zone and its workout id. Kept only because Trends v2 still reads
    /// `TrendsWeek.keyPaceSec` directly; delete this helper once nothing calls it.
    @available(*, deprecated, message: "Use KeyPaceBuilder.read — see KeyPaceModels.swift")
    static func keyPaces(_ weeks: [TrendsWeek]) -> [(label: String, sec: Int)] {
        weeks.compactMap { week in
            guard let sec = week.keyPaceSec, sec > 0 else { return nil }
            return (label: week.dateLabel, sec: sec)
        }
    }

    // MARK: Efficiency

    /// Metres covered per heartbeat during a session's work bouts — the honest
    /// aerobic-efficiency figure, computed from two measured values (work pace
    /// and average work HR) and nothing else.
    ///
    /// One mile takes `paceSec` seconds and costs `paceSec / 60 × hr` beats, so
    /// metres per beat is `1609.344 ÷ beats`. Sessions without an HR average are
    /// skipped rather than estimated.
    static func metresPerBeat(paceSec: Int, hr: Int) -> Double? {
        guard paceSec > 0, hr > 0 else { return nil }
        let beats = Double(paceSec) / 60 * Double(hr)
        guard beats > 0 else { return nil }
        return 1609.344 / beats
    }

    /// **Superseded 2026-08-18 — do not build on this.** Card 03 no longer
    /// reads it: one raw m/beat series across mixed zones measures the
    /// training schedule, not fitness. `EfficiencyIndexBuilder.build`
    /// (`EfficiencyIndexModels.swift`) scores each session against the
    /// athlete's own speed-and-heat curve instead. Delete once nothing calls it.
    @available(*, deprecated, message: "Use EfficiencyIndexBuilder.build — see EfficiencyIndexModels.swift")
    static func efficiency(_ sessions: [KeySession]) -> [(label: String, value: Double)] {
        sessions.compactMap { session in
            guard let hr = session.workHrAvg,
                  let value = metresPerBeat(paceSec: session.workPaceSec, hr: hr)
            else { return nil }
            return (label: session.dateLabel, value: value)
        }
    }

    // MARK: Heat

    /// Per-session heat penalty: how many seconds a mile the conditions cost,
    /// as the backend already computed it (`rawSec` actually run vs `adjSec`
    /// adjusted to ideal conditions). Only sessions carrying a dew point are
    /// plotted, since dew point is the x-axis.
    static func heatPenalties(_ bands: BandLaps?) -> [(dewPoint: Int, penalty: Double, label: String)] {
        guard let bands else { return [] }
        return bands.sessions.compactMap { session in
            guard let dew = session.dewPointF else { return nil }
            let laps = session.laps.filter { !$0.skip && $0.rawSec > 0 && $0.adjSec > 0 }
            guard !laps.isEmpty else { return nil }
            let penalty = laps.reduce(0.0) { $0 + Double($1.rawSec - $1.adjSec) } / Double(laps.count)
            return (dewPoint: dew, penalty: penalty, label: session.dateLabel)
        }
    }

    // MARK: Mood

    /// Mood words for the last `limit` days that have one, oldest → newest.
    static func moods(_ days: [TrendsDay], limit: Int = 30) -> [(date: String, mood: String)] {
        let rows = days.compactMap { day -> (date: String, mood: String)? in
            guard let mood = day.mood, !mood.isEmpty else { return nil }
            return (date: day.date, mood: mood)
        }
        return Array(rows.suffix(limit))
    }

    /// Distribution across the closed vocabulary, best → worst, empties dropped.
    static func moodCounts(_ moods: [(date: String, mood: String)]) -> [(mood: String, count: Int)] {
        var counts: [String: Int] = [:]
        for entry in moods { counts[entry.mood.lowercased(), default: 0] += 1 }
        return TrendsMoodColor.ordered.compactMap { mood in
            guard let count = counts[mood], count > 0 else { return nil }
            return (mood, count)
        }
    }

    // MARK: Reps

    /// The most recent session that has more than one scored lap — the one worth
    /// drawing rep-by-rep.
    static func latestRepSession(_ bands: BandLaps?) -> BandSession? {
        bands?.sessions.last { $0.laps.filter { !$0.skip }.count > 1 }
    }

    // MARK: Head to head

    /// The two most recent sessions that share a lap count, so the comparison is
    /// like-for-like. Returns (earlier, later).
    static func comparablePair(_ bands: BandLaps?) -> (BandSession, BandSession)? {
        guard let sessions = bands?.sessions, sessions.count >= 2 else { return nil }
        let scored = sessions.map { ($0, $0.laps.filter { !$0.skip }.count) }.filter { $0.1 > 1 }
        for i in stride(from: scored.count - 1, through: 1, by: -1) {
            for j in stride(from: i - 1, through: 0, by: -1) where scored[i].1 == scored[j].1 {
                return (scored[j].0, scored[i].0)
            }
        }
        return nil
    }

    // MARK: Formatting

    /// Whole miles when large, one decimal when small — the app's convention.
    static func miles(_ value: Double) -> String {
        value >= 100 ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }

    static func pace(_ sec: Int) -> String { TrendsFormat.pace(sec) }

    /// Signed second delta, using the editorial minus sign.
    static func signedSec(_ delta: Int) -> String {
        delta == 0 ? "0s" : (delta < 0 ? "\u{2212}" : "+") + "\(abs(delta))s"
    }
}
