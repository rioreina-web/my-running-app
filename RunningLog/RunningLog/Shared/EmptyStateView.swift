//
//  EmptyStateView.swift
//  RunningLog
//
//  Empty-state component (eyebrow + nudge + optional CTA) + skeleton loaders.
//  Spec: docs/conventions/empty-states.md.
//

import SwiftUI

// MARK: - EmptyStateView

struct EmptyStateView: View {
    enum Variant {
        /// Action required — the user must do something for this surface to populate.
        case setupNeeded
        /// Data will appear once enough activity has been logged.
        case dataPending
        /// Legitimately empty; not a problem.
        case optionalEmpty
        /// A fetch or computation failed.
        case error
    }

    struct CTA {
        let label: String
        let action: () -> Void
    }

    let variant: Variant
    let eyebrow: String?
    let title: String
    let cta: CTA?
    let icon: String?

    init(
        variant: Variant,
        eyebrow: String? = nil,
        title: String,
        icon: String? = nil,
        cta: CTA? = nil
    ) {
        self.variant = variant
        self.eyebrow = eyebrow
        self.title = title
        self.icon = icon
        self.cta = cta
    }

    /// Legacy initializer — used by older callers. New code should pick a variant.
    init(icon: String, title: String, subtitle: String) {
        self.variant = .optionalEmpty
        self.eyebrow = nil
        self.title = subtitle.isEmpty ? title : "\(title)\n\(subtitle)"
        self.icon = icon
        self.cta = nil
    }

    var body: some View {
        VStack(spacing: 12) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(iconColor)
            }
            if let eyebrow {
                Text(eyebrow.uppercased())
                    .font(.dripLabel(11))
                    .tracking(0.8)
                    .foregroundStyle(eyebrowColor)
            }
            Text(title)
                .font(.dripBody(14))
                .foregroundStyle(Color.drip.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let cta {
                Button(action: cta.action) {
                    Text(cta.label)
                        .font(.dripLabel(14))
                        .foregroundStyle(Color.drip.coral)
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, variant == .optionalEmpty ? 24 : 40)
    }

    private var eyebrowColor: Color {
        switch variant {
        case .setupNeeded: return Color.drip.coral
        case .error:       return Color.drip.coral
        case .dataPending, .optionalEmpty: return Color.drip.textTertiary
        }
    }

    private var iconColor: Color {
        switch variant {
        case .error: return Color.drip.coral.opacity(0.8)
        default:     return Color.drip.textTertiary
        }
    }
}

// MARK: - SkeletonPulse

/// Wraps content with a pulsing opacity animation for skeleton loading.
struct SkeletonPulse<Content: View>: View {
    @State private var isAnimating = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .opacity(isAnimating ? 0.5 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    isAnimating = true
                }
            }
    }
}

// MARK: - SkeletonBar

/// A single placeholder bar used in skeleton loading states.
struct SkeletonBar: View {
    var width: CGFloat? = nil
    var height: CGFloat = 12

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.drip.cardBackgroundElevated)
            .frame(width: width, height: height)
    }
}
