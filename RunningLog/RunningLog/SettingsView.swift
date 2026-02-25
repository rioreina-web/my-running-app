import os
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showSignOutConfirmation = false
    @State private var isSigningOut = false

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DripBackground().ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        accountSection
                        appSection
                        signOutSection
                        footerSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("SETTINGS")
                        .font(.dripCaption(13))
                        .foregroundStyle(Color.drip.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.dripLabel(14))
                        .foregroundStyle(Color.drip.coral)
                }
            }
            .toolbarBackground(Color.drip.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .alert("Sign Out?", isPresented: $showSignOutConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Sign Out", role: .destructive) { performSignOut() }
            } message: {
                Text("You will need to sign in again to access your training data.")
            }
        }
    }

    // MARK: - Account Section

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Account")

            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.drip.coral)
                    Text(AuthManager.shared.userEmail ?? "Apple ID User")
                        .font(.dripBody(14))
                        .foregroundStyle(Color.drip.textPrimary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                Divider()
                    .background(Color.drip.divider)

                HStack {
                    Image(systemName: "number")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.drip.textSecondary)
                    Text("User ID")
                        .font(.dripBody(14))
                        .foregroundStyle(Color.drip.textSecondary)
                    Spacer()
                    Text(String(AuthManager.shared.currentUserId?.prefix(8) ?? "---"))
                        .font(.dripCaption(12))
                        .foregroundStyle(Color.drip.textTertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: - App Section

    private var appSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("App")

            VStack(spacing: 0) {
                Link(destination: URL(string: "https://postrundrip.com/privacy")!) {
                    HStack {
                        Image(systemName: "hand.raised.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.drip.coral)
                        Text("Privacy Policy")
                            .font(.dripBody(14))
                            .foregroundStyle(Color.drip.textPrimary)
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.drip.textTertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }

                Divider()
                    .background(Color.drip.divider)

                HStack {
                    Image(systemName: "info.circle")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.drip.textSecondary)
                    Text("Version")
                        .font(.dripBody(14))
                        .foregroundStyle(Color.drip.textSecondary)
                    Spacer()
                    Text(appVersion)
                        .font(.dripCaption(12))
                        .foregroundStyle(Color.drip.textTertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: - Sign Out Section

    private var signOutSection: some View {
        Button {
            showSignOutConfirmation = true
        } label: {
            HStack {
                if isSigningOut {
                    ProgressView()
                        .tint(Color.drip.injured)
                } else {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 16, weight: .semibold))
                }
                Text("Sign Out")
                    .font(.dripLabel(14))
            }
            .foregroundStyle(Color.drip.injured)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.drip.injured.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .disabled(isSigningOut)
    }

    // MARK: - Footer

    private var footerSection: some View {
        Text("POST RUN DRIP")
            .font(.dripCaption(10))
            .foregroundStyle(Color.drip.textTertiary)
            .padding(.top, 8)
    }

    // MARK: - Actions

    private func performSignOut() {
        isSigningOut = true
        Task {
            do {
                try await AuthManager.shared.signOut()
            } catch {
                Log.app.error("Sign out failed: \(error)")
                await MainActor.run { isSigningOut = false }
            }
        }
    }
}
