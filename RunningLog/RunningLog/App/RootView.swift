//
//  RootView.swift
//  RunningLog
//
//  Root view that gates the app behind authentication.
//

import SwiftUI

struct RootView: View {
    @Environment(AuthManager.self) private var auth
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        Group {
            if auth.isLoading {
                // Splash / loading state while checking stored session
                ZStack {
                    Color.drip.background.ignoresSafeArea()
                    VStack(spacing: 16) {
                        Image(systemName: "figure.run")
                            .font(.system(size: 40, weight: .light))
                            .foregroundStyle(Color.drip.coral)
                        ProgressView()
                            .tint(Color.drip.coral)
                    }
                }
            } else if !auth.isAuthenticated {
                // Pre-auth surfaces get the status bar band painted here.
                // `MainTabView` paints its own, one level further in, so the
                // error / offline banners can still bleed into the notch on
                // top of it — see the comment on its `.dripStatusBarScrim()`.
                SignInView()
                    .dripStatusBarScrim()
            } else if !hasCompletedOnboarding {
                OnboardingView()
                    .dripStatusBarScrim()
            } else {
                MainTabView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: auth.isAuthenticated)
        .animation(.easeInOut(duration: 0.3), value: auth.isLoading)
        .animation(.easeInOut(duration: 0.3), value: hasCompletedOnboarding)
    }
}
