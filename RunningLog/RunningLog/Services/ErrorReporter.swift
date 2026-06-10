import Foundation
import os
import SwiftUI

// MARK: - AppError

enum AppError: LocalizedError {
    case network(underlying: Error)
    case database(operation: String, underlying: Error)
    case auth(String)
    case healthKit(String)
    case processing(String)
    case validation(String)
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .network:
            return "Network error. Check your connection and try again."
        case let .database(operation, _):
            return "Could not \(operation). Please try again."
        case let .auth(message):
            return message
        case let .healthKit(message):
            return message
        case let .processing(message):
            return message
        case let .validation(message):
            return message
        case .unknown:
            return "Something went wrong. Please try again."
        }
    }

    var isRetryable: Bool {
        switch self {
        case .network, .database, .processing:
            return true
        case .auth, .healthKit, .validation, .unknown:
            return false
        }
    }
}

// MARK: - ErrorReporter

@Observable
final class ErrorReporter {
    static let shared = ErrorReporter()

    /// The current user-facing error, if any.
    var currentError: AppError?

    /// Whether the error banner is visible.
    var isShowingError: Bool {
        currentError != nil
    }

    /// Optional retry action for the current error.
    @ObservationIgnored
    var retryAction: (@Sendable () async -> Void)?

    /// Report an error to the user and log it.
    @MainActor
    func report(_ error: AppError, retry: (@Sendable () async -> Void)? = nil) {
        Log.app.error("AppError: \(error.localizedDescription)")
        currentError = error
        retryAction = retry
    }

    /// Convenience: wrap a raw Error into an AppError and report it.
    @MainActor
    func report(_ error: Error, context: String = "complete the request", retry: (@Sendable () async -> Void)? = nil) {
        // Task cancellation is not a user-actionable failure — it means
        // the in-flight request was superseded (the view that started it
        // was torn down, a refreshable fired a new fetch, the app
        // backgrounded). URLSession surfaces this as URLError(.cancelled)
        // / NSURLErrorCancelled (-999); Swift structured concurrency
        // surfaces it as CancellationError. Either way: no banner.
        if Self.isCancellation(error) {
            Log.app.debug("ErrorReporter: suppressing cancellation \(error.localizedDescription)")
            return
        }

        if let urlError = error as? URLError {
            // Name the failing call + the transport reason so the console
            // identifies the source (the generic .network message can't).
            Log.app.error("Network error during [\(context)]: URLError.\(String(describing: urlError.code)) (\(urlError.code.rawValue)) — \(urlError.localizedDescription)")
            report(.network(underlying: urlError), retry: retry)
        } else {
            report(.database(operation: context, underlying: error), retry: retry)
        }
    }

    /// Returns true for the various flavours of "this task was cancelled."
    /// All of them are normal control flow, not user-visible failures.
    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain, ns.code == NSURLErrorCancelled { return true }
        // Some Supabase SDK paths re-throw the URLError boxed inside a
        // generic Error; the localized description still reads "cancelled".
        if ns.code == NSURLErrorCancelled { return true }
        return false
    }

    /// Dismiss the current error.
    @MainActor
    func dismiss() {
        currentError = nil
        retryAction = nil
    }
}

// MARK: - ErrorBanner View

struct ErrorBanner: View {
    @State private var errorReporter = ErrorReporter.shared

    var body: some View {
        if let error = errorReporter.currentError {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)

                    Text(error.localizedDescription)
                        .font(.dripBody(13))
                        .foregroundStyle(.white)
                        .lineLimit(3)

                    Spacer()

                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            errorReporter.dismiss()
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }

                if error.isRetryable, let retry = errorReporter.retryAction {
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            errorReporter.dismiss()
                        }
                        Task { await retry() }
                    } label: {
                        Text("Retry")
                            .font(.dripCaption(12))
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(.white.opacity(0.2))
                            .clipShape(Capsule())
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.red.opacity(0.85))
            )
            .padding(.horizontal, 16)
            .transition(.asymmetric(
                insertion: .move(edge: .top).combined(with: .opacity),
                removal: .opacity
            ))
        }
    }
}
