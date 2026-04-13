//
//  SignInView.swift
//  RunningLog
//
//  Sign in screen with Apple and email/password options.
//

import Auth
import AuthenticationServices
import Supabase
import SwiftUI

// MARK: - SignInView

struct SignInView: View {
    @State private var isSigningIn = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var currentNonce: String?

    // Email sign-in
    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false

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

                VStack(spacing: 16) {
                    // Email sign-in (primary)
                    emailForm

                    // Sign in with Apple (secondary — requires Apple Developer Program)
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

    // MARK: - Email Form

    private var emailForm: some View {
        VStack(spacing: 12) {
            TextField("Email", text: $email)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.emailAddress)
                .font(.dripBody(15))
                .padding(12)
                .background(Color.drip.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            SecureField("Password", text: $password)
                .textContentType(isSignUp ? .newPassword : .password)
                .font(.dripBody(15))
                .padding(12)
                .background(Color.drip.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            Button {
                signInWithEmail()
            } label: {
                Text(isSignUp ? "Create Account" : "Sign In")
                    .font(.dripBody(15))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.drip.coral)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .disabled(email.isEmpty || password.isEmpty || isSigningIn)
            .opacity(email.isEmpty || password.isEmpty ? 0.5 : 1)

            Button {
                isSignUp.toggle()
            } label: {
                Text(isSignUp ? "already have an account? sign in" : "no account? sign up")
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textTertiary)
            }
        }
    }

    // MARK: - Email Sign In

    private func signInWithEmail() {
        guard !email.isEmpty, !password.isEmpty else { return }
        isSigningIn = true

        Task {
            do {
                if isSignUp {
                    try await supabase.auth.signUp(email: email, password: password)
                } else {
                    try await supabase.auth.signIn(email: email, password: password)
                }
            } catch {
                await MainActor.run {
                    isSigningIn = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }

    // MARK: - Apple Sign In

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
