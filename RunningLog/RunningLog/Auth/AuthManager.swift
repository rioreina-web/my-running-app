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

    private init() {
        startAuthStateListener()
    }

    // MARK: - Auth State Listener

    private func startAuthStateListener() {
        authStateTask = Task { @MainActor [weak self] in
            for await (event, session) in supabase.auth.authStateChanges {
                guard let self else { return }
                switch event {
                case .initialSession:
                    if let session = session {
                        // We have a stored session — try to refresh it to get
                        // a valid access token. If refresh fails, sign out so
                        // the user gets a fresh Sign In with Apple flow.
                        do {
                            let refreshed = try await supabase.auth.refreshSession()
                            self.isAuthenticated = true
                            self.currentUserId = refreshed.user.id.uuidString.lowercased()
                            self.userEmail = refreshed.user.email
                        } catch {
                            print("[Auth] Session refresh failed: \(error.localizedDescription). Signing out for fresh auth.")
                            try? await supabase.auth.signOut()
                            self.isAuthenticated = false
                            self.currentUserId = nil
                            self.userEmail = nil
                        }
                    } else {
                        self.isAuthenticated = false
                        self.currentUserId = nil
                        self.userEmail = nil
                    }
                    self.isLoading = false
                case .signedIn:
                    self.isAuthenticated = true
                    self.currentUserId = session?.user.id.uuidString.lowercased()
                    self.userEmail = session?.user.email
                    self.isLoading = false
                case .signedOut:
                    self.isAuthenticated = false
                    self.currentUserId = nil
                    self.userEmail = nil
                    self.isLoading = false
                case .tokenRefreshed:
                    break
                default:
                    break
                }
            }
        }
    }

    // MARK: - Sign In with Apple

    func signInWithApple(idToken: String, nonce: String) async throws {
        try await supabase.auth.signInWithIdToken(
            credentials: .init(
                provider: .apple,
                idToken: idToken,
                nonce: nonce
            )
        )
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
