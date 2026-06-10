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
    @State private var currentNonce: String?

    // Email sign-in
    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false

    var body: some View {
        ZStack {
            DripBackground()
                .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // App branding
                VStack(spacing: 24) {
                    Image("Logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 160)
                }

                // Welcome block — display headline + italic-serif tagline.
                // Per SignInScreen.jsx in the design system.
                VStack(spacing: 6) {
                    Text(isSignUp ? "Start fresh." : "Welcome back.")
                        .font(.dripDisplay(32))
                        .foregroundStyle(Color.drip.textPrimary)
                    Text("— a quieter log for serious runners. —")
                        .font(.system(size: 13, design: .serif).italic())
                        .foregroundStyle(Color.drip.textSecondary)
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
                    .clipShape(RoundedRectangle(cornerRadius: 10))  // --r-button: 10px

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
                .clipShape(RoundedRectangle(cornerRadius: 8))  // --r-input: 8px

            SecureField("Password", text: $password)
                .textContentType(isSignUp ? .newPassword : .password)
                .font(.dripBody(15))
                .padding(12)
                .background(Color.drip.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))  // --r-input: 8px

            Button {
                signInWithEmail()
            } label: {
                HStack(spacing: 8) {
                    if isSigningIn {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(isSigningIn
                        ? (isSignUp ? "Creating account…" : "Signing in…")
                        : (isSignUp ? "Create account" : "Sign in"))
                        .font(.dripLabel(15))  // Crimson Pro semibold per spec
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.drip.coral)
                .clipShape(RoundedRectangle(cornerRadius: 10))  // --r-button: 10px
            }
            .disabled(email.isEmpty || password.isEmpty || isSigningIn)
            .opacity((email.isEmpty || password.isEmpty || isSigningIn) ? 0.5 : 1)

            // Inline error (replaces the dismissable alert so the user can't miss it)
            if let errorMessage {
                Text(errorMessage)
                    .font(.dripCaption(12))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }

            // Mode toggle — sentence-case link, not lowercase voice.
            Button {
                isSignUp.toggle()
                errorMessage = nil
            } label: {
                Text(isSignUp ? "Sign in" : "Create account")
                    .font(.dripLabel(13))
                    .foregroundStyle(Color.drip.textSecondary)
                    .underline()
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Email Sign In

    private func signInWithEmail() {
        guard !email.isEmpty, !password.isEmpty else { return }
        isSigningIn = true
        errorMessage = nil
        print("[SignIn] Starting email \(isSignUp ? "sign-up" : "sign-in")… url=\(supabaseURL)")

        let modeSignUp = isSignUp
        let emailCopy = email
        let passwordCopy = password

        Task {
            do {
                if modeSignUp {
                    _ = try await supabase.auth.signUp(email: emailCopy, password: passwordCopy)
                } else {
                    _ = try await supabase.auth.signIn(email: emailCopy, password: passwordCopy)
                }
                print("[SignIn] Email auth call succeeded")

                // Give the auth listener 3 seconds to flip isAuthenticated.
                // If it doesn't, something's off — clear the spinner so the
                // user isn't stuck, and show a hint.
                try? await Task.sleep(for: .seconds(3))
                await MainActor.run {
                    if isSigningIn {
                        print("[SignIn] Auth state didn't update — clearing spinner")
                        isSigningIn = false
                        if modeSignUp {
                            errorMessage = "Account created, but the app didn't switch over. Tap Sign In to try logging in."
                        } else {
                            errorMessage = "Sign-in completed but the app didn't switch over. Try again."
                        }
                    }
                }
            } catch {
                print("[SignIn] Email sign-in failed: \(error)")
                await MainActor.run {
                    isSigningIn = false
                    errorMessage = friendlyAuthError(error)
                }
            }
        }
    }

    /// Translate common Supabase errors into something useful.
    private func friendlyAuthError(_ error: Error) -> String {
        let msg = error.localizedDescription.lowercased()
        if msg.contains("hostname could not be found") || msg.contains("timed out") {
            return "Can't reach the server. Try switching your phone's Wi-Fi DNS to 1.1.1.1 (Settings → Wi-Fi → your network → Configure DNS → Manual)."
        }
        if msg.contains("user already registered") {
            return "That email is already signed up. Switch to Sign In mode."
        }
        if msg.contains("invalid login credentials") {
            return "Wrong email or password. If you've never signed up, tap 'no account? sign up'."
        }
        if msg.contains("email signups are disabled") {
            return "Email sign-up is disabled in Supabase. Enable it in Dashboard → Auth → Providers → Email."
        }
        if msg.contains("password") && msg.contains("6") {
            return "Password must be at least 6 characters."
        }
        return error.localizedDescription
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
                return
            }

            isSigningIn = true
            print("[SignIn] Apple credentials received, calling Supabase…")
            Task {
                do {
                    try await AuthManager.shared.signInWithApple(idToken: idToken, nonce: nonce)
                    print("[SignIn] Supabase sign-in call returned successfully")
                    // The AuthManager listener should flip isAuthenticated, which
                    // causes RootView to swap this view out. If that doesn't happen
                    // within 2s, something is wrong — stop the spinner so the user
                    // can try again.
                    try? await Task.sleep(for: .seconds(2))
                    await MainActor.run {
                        if isSigningIn {
                            print("[SignIn] Auth state didn't update after success — clearing spinner")
                            isSigningIn = false
                        }
                    }
                } catch {
                    print("[SignIn] Sign-in failed: \(error)")
                    await MainActor.run {
                        isSigningIn = false
                        errorMessage = friendlyAuthError(error)
                    }
                }
            }

        case .failure(let error):
            let nsError = error as NSError
            if nsError.code != ASAuthorizationError.canceled.rawValue {
                errorMessage = friendlyAuthError(error)
            }
        }
    }
}
