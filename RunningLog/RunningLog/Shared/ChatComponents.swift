//
//  ChatComponents.swift
//  RunningLog
//
//  Reusable chat UI components shared across coaching, plan builder,
//  and workout chat views.
//

import SwiftUI

// MARK: - ChatInputBar

struct ChatInputBar: View {
    @Binding var text: String
    let isLoading: Bool
    var isFocused: FocusState<Bool>.Binding
    let placeholder: String
    let onSend: () -> Void

    init(
        text: Binding<String>,
        isLoading: Bool,
        isFocused: FocusState<Bool>.Binding,
        placeholder: String = "Ask your coach...",
        onSend: @escaping () -> Void
    ) {
        self._text = text
        self.isLoading = isLoading
        self.isFocused = isFocused
        self.placeholder = placeholder
        self.onSend = onSend
    }

    var body: some View {
        HStack(spacing: 12) {
            TextField(placeholder, text: $text, axis: .vertical)
                .font(.dripBody(15))
                .foregroundStyle(Color.drip.textPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.drip.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.drip.divider, lineWidth: 1)
                )
                .focused(isFocused)
                .lineLimit(1 ... 5)
                .submitLabel(.send)
                .onSubmit(onSend)

            Button(action: onSend) {
                ZStack {
                    Circle()
                        .fill(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading
                            ? Color.drip.textTertiary
                            : Color.drip.coral)
                        .frame(width: 44, height: 44)

                    if isLoading {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Color.drip.background
                .shadow(color: .black.opacity(0.3), radius: 10, y: -5)
        )
    }
}

// MARK: - TypingIndicator

struct TypingIndicator: View {
    @State private var dotOpacity: [Double] = [0.3, 0.3, 0.3]

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Coach avatar
            ZStack {
                Circle()
                    .fill(Color.drip.coral.opacity(0.2))
                    .frame(width: 32, height: 32)

                Image(systemName: "figure.run")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.drip.coral)
            }

            HStack(spacing: 4) {
                ForEach(0 ..< 3) { index in
                    Circle()
                        .fill(Color.drip.textSecondary)
                        .frame(width: 8, height: 8)
                        .opacity(dotOpacity[index])
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.drip.divider, lineWidth: 1)
            )

            Spacer()
        }
        .onAppear {
            animateDots()
        }
    }

    private func animateDots() {
        for i in 0 ..< 3 {
            withAnimation(
                .easeInOut(duration: 0.5)
                    .repeatForever(autoreverses: true)
                    .delay(Double(i) * 0.15)
            ) {
                dotOpacity[i] = 1.0
            }
        }
    }
}
