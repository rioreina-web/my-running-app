//
//  SignInView.swift
//  RunningLog
//
//  Sign in with Apple screen shown before the main app.
//

import AuthenticationServices
import SwiftUI

// MARK: - SignInView

struct SignInView: View {
    @State private var isSigningIn = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var currentNonce: String?

    var body: some View {
        ZStack {
            DripBackground()
                .ignoresSafeArea()

            VStack(spacing: 40) {
                Spacer()

                // App branding
                VStack(spacing: 24) {
                    Image("Logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 160)
                }

                Spacer()

                // Sign in with Apple
                VStack(spacing: 16) {
                    SignInWithAppleButton(.signIn) { request in
                        let nonce = AuthManager.shared.randomNonceString()
                        currentNonce = nonce
                        request.requestedScopes = [.email, .fullName]
                        request.nonce = AuthManager.shared.sha256(nonce)
                    } onCompletion: { result in
                        handleSignInResult(result)
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    if isSigningIn {
                        ProgressView()
                            .tint(Color.drip.coral)
                    }
                }
                .padding(.horizontal, 40)

                Spacer()
                    .frame(height: 60)
            }
        }
        .alert("Sign In Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "An error occurred. Please try again.")
        }
    }

    private func handleSignInResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let identityTokenData = credential.identityToken,
                  let idToken = String(data: identityTokenData, encoding: .utf8),
                  let nonce = currentNonce else {
                errorMessage = "Could not process Apple credentials."
                showError = true
                return
            }

            isSigningIn = true
            Task {
                do {
                    try await AuthManager.shared.signInWithApple(idToken: idToken, nonce: nonce)
                } catch {
                    await MainActor.run {
                        isSigningIn = false
                        errorMessage = error.localizedDescription
                        showError = true
                    }
                }
            }

        case .failure(let error):
            let nsError = error as NSError
            if nsError.code != ASAuthorizationError.canceled.rawValue {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}
