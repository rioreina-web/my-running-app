import Auth
import os
import Supabase
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("coachCheckInsEnabled") private var coachCheckInsEnabled = true
    @AppStorage("smartInsightsEnabled") private var smartInsightsEnabled = true
    @AppStorage("isCoachMode") private var isCoachMode = false
    @AppStorage("userMaxHR") private var userMaxHR: Int = 180
    @State private var maxHRText: String = ""
    @State private var showSignOutConfirmation = false
    @State private var isSigningOut = false
    @State private var signInEmail = ""
    @State private var signInPassword = ""
    @State private var isSignUpMode = false
    @State private var isSigningIn = false
    @State private var signInError: String?
    @State private var showJoinPlan = false
    @State private var showBackup = false
    @State private var showRestore = false
    @State private var showAthleteProfile = false
    @State private var syncService = WorkoutSyncService()
    @State private var backfillResultMessage: String?

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
                        coachingSection
                        coachPlanSection
                        coachModeSection
                        trainingSection
                        dataSection
                        appSection
                        if AuthManager.shared.isAuthenticated {
                            signOutSection
                        } else {
                            signInSection
                        }
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
            .sheet(isPresented: $showBackup) {
                BackupView()
            }
            .sheet(isPresented: $showRestore) {
                RestoreView()
            }
            .sheet(isPresented: $showAthleteProfile) {
                AthleteProfileView()
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

    // MARK: - Coaching Section

    private var coachingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Coaching")

            VStack(spacing: 0) {
                Toggle(isOn: $coachCheckInsEnabled) {
                    HStack {
                        Image(systemName: "bubble.left.and.text.bubble.right.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.drip.coral)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Coach Check-Ins")
                                .font(.dripBody(14))
                                .foregroundStyle(Color.drip.textPrimary)
                            Text("Get proactive coaching when you're struggling")
                                .font(.dripCaption(12))
                                .foregroundStyle(Color.drip.textTertiary)
                        }
                    }
                }
                .tint(Color.drip.coral)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                Divider()
                    .background(Color.drip.divider)

                Toggle(isOn: $smartInsightsEnabled) {
                    HStack {
                        Image(systemName: "chart.line.text.clipboard")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.drip.coral)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Smart Insights")
                                .font(.dripBody(14))
                                .foregroundStyle(Color.drip.textPrimary)
                            Text("Coach uses your data to ask follow-up questions")
                                .font(.dripCaption(12))
                                .foregroundStyle(Color.drip.textTertiary)
                        }
                    }
                }
                .tint(Color.drip.coral)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: - Training Section

    private var trainingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Training")

            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Max Heart Rate")
                            .font(.dripBody(14))
                            .foregroundStyle(Color.drip.textPrimary)
                        Text("Used for HR zone targets in workouts")
                            .font(.dripCaption(12))
                            .foregroundStyle(Color.drip.textTertiary)
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        TextField("180", text: $maxHRText)
                            .font(.dripStat(16))
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 48)
                            .onChange(of: maxHRText) { _, new in
                                if let val = Int(new), val > 100, val < 250 {
                                    userMaxHR = val
                                }
                            }
                        Text("bpm")
                            .font(.dripCaption(12))
                            .foregroundStyle(Color.drip.textTertiary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .onAppear { maxHRText = "\(userMaxHR)" }
    }

    // MARK: - Data Section

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Data")

            VStack(spacing: 0) {
                Button {
                    Task { await runBackfill() }
                } label: {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.drip.coral)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Backfill Pace Splits")
                                .font(.dripBody(14))
                                .foregroundStyle(Color.drip.textPrimary)
                            Text(backfillSubtitle)
                                .font(.dripCaption(12))
                                .foregroundStyle(Color.drip.textTertiary)
                        }
                        Spacer()
                        if syncService.isBackfilling {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.drip.textTertiary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .disabled(syncService.isBackfilling)
                .buttonStyle(.plain)
            }
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private var backfillSubtitle: String {
        if syncService.isBackfilling {
            let (done, total) = syncService.backfillProgress
            return "Processing \(done) of \(total)..."
        }
        if let msg = backfillResultMessage { return msg }
        return "Re-process Garmin runs missing splits"
    }

    private func runBackfill() async {
        backfillResultMessage = nil
        await syncService.backfillPaceSegments()
        let count = syncService.lastBackfillCount
        backfillResultMessage = count > 0 ? "Updated \(count) workouts" : "All workouts already have splits"
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

                Button {
                    showBackup = true
                } label: {
                    HStack {
                        Image(systemName: "externaldrive.badge.checkmark")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.drip.coral)
                        Text("Backup All Data")
                            .font(.dripBody(14))
                            .foregroundStyle(Color.drip.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.drip.textTertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }

                Divider()
                    .background(Color.drip.divider)

                Button {
                    showRestore = true
                } label: {
                    HStack {
                        Image(systemName: "arrow.down.doc.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.drip.coral)
                        Text("Restore from Backup")
                            .font(.dripBody(14))
                            .foregroundStyle(Color.drip.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.drip.textTertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }

                Divider()
                    .background(Color.drip.divider)

                Button {
                    showAthleteProfile = true
                } label: {
                    HStack {
                        Image(systemName: "figure.run.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.drip.coral)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Athlete Profile")
                                .font(.dripBody(14))
                                .foregroundStyle(Color.drip.textPrimary)
                            Text("Your training patterns & history")
                                .font(.dripCaption(12))
                                .foregroundStyle(Color.drip.textTertiary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
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

    // MARK: - Sign In Section

    private var signInSection: some View {
        VStack(spacing: 12) {
            Text("Sign in to unlock coaching, analysis, and sync.")
                .font(.dripBody(13))
                .foregroundStyle(Color.drip.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            TextField("Email", text: $signInEmail)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.emailAddress)
                .font(.dripBody(15))
                .padding(12)
                .background(Color.drip.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            SecureField("Password", text: $signInPassword)
                .textContentType(.password)
                .font(.dripBody(15))
                .padding(12)
                .background(Color.drip.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            if let signInError {
                Text(signInError)
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.injured)
            }

            Button {
                if isSignUpMode {
                    performSignUp()
                } else {
                    performSignIn()
                }
            } label: {
                HStack {
                    if isSigningIn {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(isSignUpMode ? "Create Account" : "Sign In")
                        .font(.dripLabel(14))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.drip.coral)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .disabled(signInEmail.isEmpty || signInPassword.isEmpty || isSigningIn)
            .opacity(signInEmail.isEmpty || signInPassword.isEmpty ? 0.5 : 1)

            Button {
                isSignUpMode.toggle()
                signInError = nil
            } label: {
                Text(isSignUpMode ? "Already have an account? Sign In" : "No account? Create one")
                    .font(.dripCaption(12))
                    .foregroundStyle(Color.drip.coral)
            }
        }
    }

    private func performSignIn() {
        isSigningIn = true
        signInError = nil
        Task {
            do {
                try await supabase.auth.signIn(email: signInEmail, password: signInPassword)
                await MainActor.run {
                    isSigningIn = false
                }
            } catch {
                await MainActor.run {
                    isSigningIn = false
                    signInError = error.localizedDescription
                }
            }
        }
    }

    private func performSignUp() {
        isSigningIn = true
        signInError = nil
        Task {
            do {
                try await supabase.auth.signUp(email: signInEmail, password: signInPassword)
                await MainActor.run {
                    isSigningIn = false
                }
            } catch {
                await MainActor.run {
                    isSigningIn = false
                    signInError = error.localizedDescription
                }
            }
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

    // MARK: - Coach Plan Section (Athlete)

    private var coachPlanSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Coach Plan")

            VStack(spacing: 0) {
                Button {
                    showJoinPlan = true
                } label: {
                    HStack {
                        Image(systemName: "link.badge.plus")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.drip.coral)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Join a Coach Plan")
                                .font(.dripBody(14))
                                .foregroundStyle(Color.drip.textPrimary)
                            Text("Enter a 6-character code from your coach")
                                .font(.dripCaption(12))
                                .foregroundStyle(Color.drip.textTertiary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.drip.textTertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
            }
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .sheet(isPresented: $showJoinPlan) {
            JoinCoachPlanSheet()
        }
    }

    // MARK: - Coach Mode Section

    private var coachModeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Coach Mode")

            VStack(spacing: 0) {
                Toggle(isOn: $isCoachMode) {
                    HStack {
                        Image(systemName: "person.badge.shield.checkmark.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.drip.coral)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Enable Coach Mode")
                                .font(.dripBody(14))
                                .foregroundStyle(Color.drip.textPrimary)
                            Text("Replaces the Plan tab with coach tools")
                                .font(.dripCaption(12))
                                .foregroundStyle(Color.drip.textTertiary)
                        }
                    }
                }
                .tint(Color.drip.coral)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
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
