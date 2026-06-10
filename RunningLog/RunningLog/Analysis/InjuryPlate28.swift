//
//  InjuryPlate28.swift
//  RunningLog
//
//  Plate 28 — editorial redesign of the Injuries list.
//
//  Replaces the icon-card list with an editorial ledger:
//    • Display-serif body-area name + AMBER severity number
//    • Mono eyebrow line: SIDE · ACTIVE · Nd
//    • 4-stat strip: MENTIONS · AVG VOL · AVG LOAD · TREND
//    • 14-day mention dots — AMBER on days the ache was mentioned
//    • Italic-serif quote of the most recent voice mention
//    • Mono action links: View detail · Update · Mark resolved
//
//  v1 surfaces what we can show *today* from the existing Injury model;
//  the comparison stats (MENTIONS / AVG VOL / AVG LOAD) require either
//  scanning training_logs for matching dates OR a backend `injury_mentions`
//  table. Until that lands, those cells render `—` and the row layout
//  stays the same — design absorbs missing data without breaking.
//
//  Disclaimer becomes a quiet italic-serif line in the header instead of
//  a red-bordered banner. Liability cover is preserved; visual urgency
//  drops.
//
//  To revert: delete this file and revert InjuryView.swift body changes.
//

import SwiftUI

// MARK: - Editorial header

/// Editorial header that replaces the toolbar "INJURIES" + medical-banner
/// stack. Mono eyebrow with count, display-serif title, italic-serif
/// disclaimer underneath.
struct InjuryHeader28: View {
    let activeCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TRACKING NOW  ·  \(activeCount)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(Color.drip.coral)
            Text("Active aches")
                .font(.dripDisplay(28))
                .foregroundStyle(Color.drip.textPrimary)
            Text("Not medical advice. If anything gets sharper, see a clinician.")
                .font(.system(size: 13, design: .serif).italic())
                .foregroundStyle(Color.drip.textSecondary)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Editorial rule
//
// `InjuryRule28` was deleted — use the shared `EditorialRule` from
// DesignSystem.swift instead. Callsites in InjuryView were renamed in
// the same pass.

// MARK: - Injury entry (active)

/// One injury entry in the editorial style. All sub-components fold
/// gracefully when data is missing — empty quote hides the quote section,
/// no mention history hides the dots row, etc.
struct InjuryEntry28: View {
    let injury: Injury
    /// Optional context — these would come from a future
    /// `injury_mentions` table joined against training_logs. When nil,
    /// the cells render `—` rather than fabricating numbers.
    var mentionsCount: Int? = nil
    var avgVolumeMiles: Double? = nil
    var avgLoad: Int? = nil
    var trendLabel: TrendLabel? = nil
    /// Indices (0…13) into the trailing 14 days where a mention occurred.
    var mentionDotIndices: Set<Int> = []
    /// Most recent verbatim quote pulled from a voice log.
    var lastQuote: String? = nil

    let onViewDetail: () -> Void
    let onUpdate: () -> Void
    let onMarkResolved: () -> Void

    enum TrendLabel: String {
        case easing    = "EASING"
        case steady    = "STEADY"
        case worsening = "WORSENING"

        var color: Color {
            // Severity score already claims coral in the top row — per
            // the spec's "one coral element per visual cluster" rule,
            // EASING uses the energized green instead. Conflict resolved.
            switch self {
            case .easing:    return Color.drip.energized
            case .steady:    return Color.drip.textPrimary
            case .worsening: return Color.drip.injured
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Top row — name + severity
            HStack(alignment: .firstTextBaseline) {
                Text(injury.displayName)
                    .font(.dripDisplay(22))
                    .foregroundStyle(Color.drip.textPrimary)
                Spacer()
                Text("\(injury.severity) / 10")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.drip.coral)
            }

            // Side / status / days line
            Text(metaLine)
                .font(.system(size: 10, design: .monospaced))
                .tracking(0.5)
                .foregroundStyle(Color.drip.textSecondary)

            // 4-stat strip: MENTIONS · AVG VOL · AVG LOAD · TREND
            statStrip
                .padding(.top, 4)

            // 14-day mention dots
            if mentionsCount != nil {
                mentionDotsRow
                    .padding(.top, 4)
            }

            // Quote (most recent mention)
            if let quote = lastQuote, !quote.isEmpty {
                quoteSection(quote)
                    .padding(.top, 4)
            }

            // Action links
            HStack(spacing: 0) {
                actionLink("View detail", action: onViewDetail)
                middot()
                actionLink("Update", action: onUpdate)
                middot()
                actionLink("Mark resolved", action: onMarkResolved)
                Spacer(minLength: 0)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Sub-views

    private var statStrip: some View {
        HStack(spacing: 0) {
            statCell(label: "MENTIONS",
                     value: mentionsCount.map { "\($0)×" } ?? "—",
                     color: Color.drip.textPrimary)
            statCell(label: "AVG VOL",
                     value: avgVolumeMiles.map { formatMiles($0) } ?? "—",
                     suffix: avgVolumeMiles != nil ? "mi" : "",
                     color: Color.drip.textPrimary)
            statCell(label: "AVG LOAD",
                     value: avgLoad.map(String.init) ?? "—",
                     color: Color.drip.textPrimary)
            statCell(label: "TREND",
                     value: trendLabel?.rawValue ?? "—",
                     color: trendLabel?.color ?? Color.drip.textTertiary)
        }
    }

    private func statCell(label: String, value: String, suffix: String = "",
                          color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.dripEyebrow(10))  // bumped from 8pt — below the spec's t-meta-sm floor
                .tracking(1.0)  // 0.10em caption tracking at 10pt
                .foregroundStyle(Color.drip.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(color)
                if !suffix.isEmpty {
                    Text(suffix)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.drip.textTertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var mentionDotsRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("MENTIONS  ·  LAST 14 DAYS")
                .font(.dripEyebrow(10))  // bumped from 8pt
                .tracking(1.0)
                .foregroundStyle(Color.drip.textTertiary)
            HStack(spacing: 0) {
                ForEach(0..<14, id: \.self) { idx in
                    let mentioned = mentionDotIndices.contains(idx)
                    Circle()
                        .fill(mentioned ? Color.drip.coral : Color.drip.textTertiary)
                        .frame(width: mentioned ? 6 : 2,
                               height: mentioned ? 6 : 2)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func quoteSection(_ quote: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("LAST MENTIONED")
                .font(.dripEyebrow(10))  // bumped from 8pt
                .tracking(1.0)
                .foregroundStyle(Color.drip.textTertiary)
            Text("\u{201C}\(quote)\u{201D}")
                .font(.system(size: 13, design: .serif).italic())
                .foregroundStyle(Color.drip.textPrimary)
                .lineSpacing(2)
                .lineLimit(3)
        }
    }

    // MARK: - Helpers

    private var metaLine: String {
        var parts: [String] = []
        if injury.side != "unknown" {
            parts.append(injury.side.uppercased())
        }
        parts.append(injury.status.displayName.uppercased())
        parts.append("\(injury.daysSinceReported)d")
        return parts.joined(separator: "  ·  ")
    }

    private func formatMiles(_ m: Double) -> String {
        if m == m.rounded() { return String(format: "%.0f", m) }
        return String(format: "%.1f", m)
    }

    private func actionLink(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.drip.textSecondary)
        }
        .buttonStyle(.plain)
    }

    private func middot() -> some View {
        Text("·")
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(Color.drip.textTertiary)
            .padding(.horizontal, 8)
    }
}
