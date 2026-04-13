//
//  EmptyStateView.swift
//  RunningLog
//
//  Reusable empty state and skeleton loading components.
//

import SwiftUI

// MARK: - EmptyStateView

struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Color.drip.textTertiary)

            VStack(spacing: 4) {
                Text(title)
                    .font(.dripLabel(16))
                    .foregroundStyle(Color.drip.textSecondary)

                Text(subtitle)
                    .font(.dripBody(14))
                    .foregroundStyle(Color.drip.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
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
