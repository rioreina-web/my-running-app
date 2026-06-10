//
//  AuthManager.swift
//  RunningLog
//
//  Manages Sign in with Apple authentication via Supabase Auth.
//

import AuthenticationServices
import CryptoKit
import Foundation
import Auth
import Supabase

// MARK: - AuthManager

@Observable
final class AuthManager {
    static let shared = AuthManager()

    var isAuthenticated = false
    var isLoading = true
    var currentUserId: String?
    var userEmail: String?

    /// Returns the authenticated user ID. Nil if not signed in.
    var userId: String {
        guard let id = currentUserId else {
            print("[Auth] WARNING: userId accessed before authentication")
            return ""
        }
        return id
    }

    private var authStateTask: Task<Void, Never>?
    private var pendingRefreshTask: Task<Void, Never>?
    private var splashTimeoutTask: Task<Void, Never>?

    private init() {
        startAuthStateListener()
        startSplashTimeout()
    }

    /// Safety net: if the auth state listener hasn't flipped isLoading within
    /// 8 seconds (e.g. Supabase SDK hangs on a bad connection), force the
    /// splash away so the app is never permanently stuck.
    private func startSplashTimeout() {
        splashTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard let self, self.isLoading else { return }
            print("[Auth] Splash timeout reached — showing sign-in screen.")
            self.isAuthenticated = false
            self.isLoading = false
        }
    }

    /// Run a task with a timeout; throws if it doesn't finish in time.
    private func withTimeout<T: Sendable>(seconds: Double, _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw AuthTimeoutError()
            }
            guard let first = try await group.next() else { throw AuthTimeoutError() }
            group.cancelAll()
            return first
        }
    }

    // MARK: - Auth State Listener

    private func startAuthStateListener() {
        authStateTask = Task { @MainActor [weak self] in
            for await (event, session) in supabase.auth.authStateChanges {
                guard let self else { return }
                switch event {
                case .initialSession:
                    if let session = session {
                        // We have a stored session — try to refresh it with a
                        // bounded timeout so we can't hang forever on bad networks.
                        do {
                            let refreshed = try await self.withTimeout(seconds: 5) {
                                try await supabase.auth.refreshSession()
                            }
                            self.isAuthenticated = true
                            self.currentUserId = refreshed.user.id.uuidString.lowercased()
                            self.userEmail = refreshed.user.email
                        } catch {
                            print("[Auth] Session refresh failed: \(error.localizedDescription)")
                            self.handleRefreshFailure(existingSession: session)
                        }
                    } else {
                        self.isAuthenticated = false
                        self.currentUserId = nil
                        self.userEmail = nil
                    }
                    self.isLoading = false
                    self.splashTimeoutTask?.cancel()
                case .signedIn:
                    self.isAuthenticated = true
                    self.currentUserId = session?.user.id.uuidString.lowercased()
                    self.userEmail = session?.user.email
                    self.isLoading = false
                    self.splashTimeoutTask?.cancel()
                case .signedOut:
                    self.isAuthenticated = false
                    self.currentUserId = nil
                    self.userEmail = nil
                    self.isLoading = false
                    self.splashTimeoutTask?.cancel()
                case .tokenRefreshed:
                    break
                default:
                    break
                }
            }
        }
    }

    // MARK: - Refresh Failure Handling

    @MainActor
    private func handleRefreshFailure(existingSession: Session?) {
        if !NetworkMonitor.shared.isConnected {
            // Offline: keep existing session and queue refresh for reconnect
            print("[Auth] Offline — keeping existing session, will retry on reconnect.")
            if let session = existingSession {
                self.isAuthenticated = true
                self.currentUserId = session.user.id.uuidString.lowercased()
                self.userEmail = session.user.email
            }
            queueRefreshOnReconnect()
            return
        }

        // Online: retry once after 2 seconds
        print("[Auth] Retrying session refresh in 2 seconds…")
        pendingRefreshTask?.cancel()
        pendingRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, !Task.isCancelled else { return }

            do {
                let refreshed = try await supabase.auth.refreshSession()
                self.isAuthenticated = true
                self.currentUserId = refreshed.user.id.uuidString.lowercased()
                self.userEmail = refreshed.user.email
                print("[Auth] Retry refresh succeeded.")
            } catch {
                print("[Auth] Retry refresh failed: \(error.localizedDescription). Signing out.")
                try? await supabase.auth.signOut()
                self.isAuthenticated = false
                self.currentUserId = nil
                self.userEmail = nil
            }
        }
    }

    /// Observes network connectivity and retries session refresh once online.
    private func queueRefreshOnReconnect() {
        pendingRefreshTask?.cancel()
        pendingRefreshTask = Task { @MainActor [weak self] in
            // Poll until connected (withObservationTracking fires once per change)
            while !NetworkMonitor.shared.isConnected {
                try? await Task.sleep(for: .seconds(2))
                if Task.isCancelled { return }
            }
            guard let self, !Task.isCancelled else { return }
            print("[Auth] Connectivity restored — retrying session refresh.")
            do {
                let refreshed = try await supabase.auth.refreshSession()
                self.isAuthenticated = true
                self.currentUserId = refreshed.user.id.uuidString.lowercased()
                self.userEmail = refreshed.user.email
            } catch {
                print("[Auth] Post-reconnect refresh failed: \(error.localizedDescription). Signing out.")
                try? await supabase.auth.signOut()
                self.isAuthenticated = false
                self.currentUserId = nil
                self.userEmail = nil
            }
        }
    }

    // MARK: - Sign In with Apple

    func signInWithApple(idToken: String, nonce: String) async throws {
        print("[Auth] signInWithApple: starting Supabase signInWithIdToken…")
        do {
            let response = try await withTimeout(seconds: 15) {
                try await supabase.auth.signInWithIdToken(
                    credentials: .init(
                        provider: .apple,
                        idToken: idToken,
                        nonce: nonce
                    )
                )
            }
            print("[Auth] signInWithApple: success, user=\(response.user.id.uuidString)")
        } catch {
            print("[Auth] signInWithApple FAILED: \(error)")
            print("[Auth] localized: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Sign Out

    func signOut() async throws {
        try await supabase.auth.signOut()
    }

    // MARK: - Nonce Helpers

    func randomNonceString(length: Int = 32) -> String {
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length
        while remainingLength > 0 {
            let randoms: [UInt8] = (0 ..< 16).map { _ in
                var random: UInt8 = 0
                _ = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                return random
            }
            for random in randoms {
                if remainingLength == 0 { break }
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }
        return result
    }

    func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - AuthProvider Conformance

extension AuthManager: AuthProvider {}

// MARK: - Errors

private struct AuthTimeoutError: Error {
    var localizedDescription: String { "Auth refresh timed out" }
}
