//
//  ErrorView.swift
//  RunningLog
//
//  Reusable error states for async-loaded views.
//

import SwiftUI

// MARK: - AsyncContentView

/// Wraps async-loaded content with loading, error, and empty states.
/// Replaces scattered `if isLoading ... else if error ... else` patterns.
struct AsyncContentView<Content: View>: View {
    let isLoading: Bool
    let error: String?
    let isEmpty: Bool
    let emptyIcon: String
    let emptyTitle: String
    let emptySubtitle: String
    let onRetry: (() async -> Void)?
    @ViewBuilder let content: () -> Content

    init(
        isLoading: Bool,
        error: String? = nil,
        isEmpty: Bool = false,
        emptyIcon: String = "tray",
        emptyTitle: String = "Nothing here",
        emptySubtitle: String = "",
        onRetry: (() async -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.isLoading = isLoading
        self.error = error
        self.isEmpty = isEmpty
        self.emptyIcon = emptyIcon
        self.emptyTitle = emptyTitle
        self.emptySubtitle = emptySubtitle
        self.onRetry = onRetry
        self.content = content
    }

    var body: some View {
        if isLoading {
            VStack(spacing: 12) {
                ProgressView()
                    .tint(Color.drip.coral)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error {
            ErrorStateView(message: error, onRetry: onRetry)
        } else if isEmpty {
            EmptyStateView(icon: emptyIcon, title: emptyTitle, subtitle: emptySubtitle)
        } else {
            content()
        }
    }
}

// MARK: - ErrorStateView

struct ErrorStateView: View {
    let message: String
    let onRetry: (() async -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.drip.struggling)

            Text(message)
                .font(.dripBody(14))
                .foregroundStyle(Color.drip.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if let onRetry {
                Button {
                    Task { await onRetry() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Retry")
                            .font(.dripLabel(13))
                    }
                    .foregroundStyle(Color.drip.coral)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.drip.coral.opacity(0.1))
                    .clipShape(Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - Toast Banner

/// Temporary toast for non-blocking errors and success feedback.
struct ToastBanner: View {
    let message: String
    let type: ToastType

    enum ToastType {
        case error, success, info

        var icon: String {
            switch self {
            case .error: "xmark.circle.fill"
            case .success: "checkmark.circle.fill"
            case .info: "info.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .error: Color.drip.struggling
            case .success: Color.drip.energized
            case .info: Color.drip.neutral
            }
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: type.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(type.color)

            Text(message)
                .font(.dripCaption(12))
                .foregroundStyle(Color.drip.textPrimary)
                .lineLimit(2)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
        .padding(.horizontal, 20)
    }
}

// MARK: - View Extension for Toast

extension View {
    func toast(_ message: Binding<String?>, type: ToastBanner.ToastType = .error) -> some View {
        overlay(alignment: .top) {
            if let text = message.wrappedValue {
                ToastBanner(message: text, type: type)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            withAnimation { message.wrappedValue = nil }
                        }
                    }
                    .padding(.top, 8)
            }
        }
        .animation(.spring(response: 0.3), value: message.wrappedValue != nil)
    }
}
