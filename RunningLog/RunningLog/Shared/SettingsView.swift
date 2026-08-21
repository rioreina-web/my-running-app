import Auth
import os
import PhotosUI
import Supabase
import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("coachCheckInsEnabled") private var coachCheckInsEnabled = true
    @AppStorage("smartInsightsEnabled") private var smartInsightsEnabled = true
    @AppStorage("isCoachMode") private var isCoachMode = false
    @AppStorage("userMaxHR") private var userMaxHR: Int = 180
    // Display units for distance & pace. Default Miles; flips the whole app.
    @AppStorage("distanceUnit") private var distanceUnit: String = DistanceUnit.miles.rawValue
    @State private var maxHRText: String = ""
    @State private var displayNameText: String = ""
    @State private var bioText: String = ""
    @State private var avatarPath: String?
    @State private var avatarSignedURL: URL?
    @State private var pickedAvatar: UIImage?
    @State private var avatarPickerItem: PhotosPickerItem?
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
    @State private var showTimeZonePicker = false
    /// Observed so the row's "FOLLOWING DEVICE" / "SET MANUALLY" caption updates
    /// the moment the picker writes, without a manual refresh.
    @AppStorage(AthleteTimeZone.overrideKey) private var timezoneOverride: String = ""
    @State private var showDeleteAccount = false
    @State private var syncService = WorkoutSyncService()
    @State private var backfillResultMessage: String?
    @State private var isStravaSyncing = false
    @State private var stravaSyncResultMessage: String?

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
                        // Coach Mode toggle removed in Phase A (2026-07-13):
                        // the tab it swapped (Plan → CoachTabView) no longer
                        // exists — the 4-tab IA has no Plan tab, and the web
                        // coach portal is canonical for coach work. Shipping
                        // an inert toggle would be worse than none.
                        trainingSection
                        dataSection
                        appSection
                        if AuthManager.shared.isAuthenticated {
                            signOutSection
                            deleteAccountSection
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
                    Button("Done") {
                        // Persist any profile edits before closing (fire-and-
                        // forget upsert; the sheet can dismiss immediately).
                        Task { await saveProfile() }
                        dismiss()
                    }
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
            .sheet(isPresented: $showDeleteAccount) {
                DeleteAccountSheet()
            }
        }
    }

    // MARK: - Account / Profile Masthead

    // The athlete's identity, treated like a magazine masthead rather than a
    // form: photo (or monogram), name in the display serif, an editorial bio
    // note with a coral rule. Edits write to the same athlete_settings row the
    // coach portal reads.
    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top, spacing: 15) {
                avatarView

                VStack(alignment: .leading, spacing: 3) {
                    Text("ATHLETE")
                        .font(.dripEyebrow(9))
                        .tracking(9 * 0.16)
                        .foregroundStyle(Color.drip.textTertiary)
                    TextField("Add your name", text: $displayNameText)
                        .font(.dripDisplay(27))
                        .foregroundStyle(Color.drip.textPrimary)
                        .submitLabel(.done)
                        .onSubmit { Task { await saveProfile() } }
                    Text(AuthManager.shared.userEmail ?? "Apple ID User")
                        .font(.dripEyebrow(10.5))
                        .foregroundStyle(Color.drip.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }

            // Editorial bio note with a single coral rule (the one accent).
            HStack(alignment: .top, spacing: 11) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.drip.coral)
                    .frame(width: 2)
                TextField("Your goals, context — optional", text: $bioText, axis: .vertical)
                    .font(.dripCaption(14.5))
                    .italic()
                    .foregroundStyle(Color.drip.textSecondary)
                    .lineLimit(1...4)
            }
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                Image(systemName: "number")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.drip.textTertiary)
                Text("User ID")
                    .font(.dripEyebrow(9.5))
                    .tracking(9.5 * 0.1)
                    .foregroundStyle(Color.drip.textTertiary)
                Spacer()
                Text(String(AuthManager.shared.currentUserId?.prefix(8) ?? "---"))
                    .font(.dripEyebrow(11))
                    .foregroundStyle(Color.drip.textTertiary)
            }
            .padding(.top, 2)
        }
        .padding(20)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .task { await loadProfile() }
        .onChange(of: avatarPickerItem) { _, newItem in
            guard let newItem else { return }
            Task { await handlePickedAvatar(newItem) }
        }
    }

    // Avatar: locally-picked image → signed remote URL → initials monogram,
    // with a PhotosPicker over the whole thing and a coral camera badge.
    private var avatarView: some View {
        PhotosPicker(selection: $avatarPickerItem, matching: .images) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let img = pickedAvatar {
                        Image(uiImage: img).resizable().scaledToFill()
                    } else if let url = avatarSignedURL {
                        AsyncImage(url: url) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFill()
                            } else {
                                monogram
                            }
                        }
                    } else {
                        monogram
                    }
                }
                .frame(width: 64, height: 64)
                .clipShape(Circle())

                Image(systemName: "camera.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(5)
                    .background(Color.drip.coral)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.drip.cardBackground, lineWidth: 2))
            }
        }
        .buttonStyle(.plain)
    }

    private var monogram: some View {
        ZStack {
            Color(red: 14/255, green: 29/255, blue: 78/255) // navy — pace ramp dark end (PaceSpectrum.mile)
            Text(initials)
                .font(.dripDisplay(22))
                .foregroundStyle(.white)
        }
    }

    // Initials from the name, or first letter of email, or a neutral dot.
    private var initials: String {
        let words = displayNameText.split(separator: " ").prefix(2)
        let fromName = words.compactMap { $0.first }.map(String.init).joined().uppercased()
        if !fromName.isEmpty { return fromName }
        if let e = AuthManager.shared.userEmail?.first { return String(e).uppercased() }
        return "•"
    }

    // MARK: - Profile actions

    /// Load the athlete's saved name/bio/photo into the masthead.
    private func loadProfile() async {
        let profile = await AthleteSettingsService.fetchProfile()
        displayNameText = profile.displayName
        bioText = profile.bio
        avatarPath = profile.avatarPath
        if let path = profile.avatarPath, !path.isEmpty {
            avatarSignedURL = await AthleteSettingsService.signedAvatarURL(path)
        }
    }

    /// Show the picked photo immediately, then downscale, upload, and persist.
    private func handlePickedAvatar(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let ui = UIImage(data: data) else { return }
        let resized = ui.resizedForAvatar()
        pickedAvatar = resized
        if let jpeg = resized.jpegData(compressionQuality: 0.8) {
            if let path = await AthleteSettingsService.uploadAvatar(jpeg) {
                avatarPath = path
            }
        }
    }

    /// Persist name + bio to the athlete's account. Called on submit and on Done.
    private func saveProfile() async {
        await AthleteSettingsService.saveProfile(displayName: displayNameText, bio: bioText)
    }

    // MARK: - Coaching Section

    private var coachingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            EditorialSectionHeader(index: "01", title: "Coaching")

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
            EditorialSectionHeader(index: "03", title: "Training")

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
                                    // Persist to the account so zones sync across devices.
                                    Task { await AthleteSettingsService.saveMaxHR(val) }
                                }
                            }
                        Text("bpm")
                            .font(.dripCaption(12))
                            .foregroundStyle(Color.drip.textTertiary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                Divider().overlay(Color.drip.divider).padding(.leading, 16)

                // Distance units — flips distance & pace across the whole app.
                HStack {
                    Image(systemName: "ruler")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.drip.coral)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Units")
                            .font(.dripBody(14))
                            .foregroundStyle(Color.drip.textPrimary)
                        Text("Distance & pace shown in miles or kilometers")
                            .font(.dripCaption(12))
                            .foregroundStyle(Color.drip.textTertiary)
                    }
                    Spacer()
                    Picker("Units", selection: $distanceUnit) {
                        ForEach(DistanceUnit.allCases) { unit in
                            Text(unit.label).tag(unit.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 116)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                Divider().overlay(Color.drip.divider).padding(.leading, 16)

                // Time zone — decides what hour a run is drawn at on the week
                // training-stress strip, and what "Morning" means anywhere the
                // app says it. Follows the device unless set explicitly; the
                // explicit case is travel, where the device zone would slide
                // every past run sideways the moment you land.
                Button { showTimeZonePicker = true } label: {
                    HStack {
                        Image(systemName: "clock")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.drip.coral)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Time Zone")
                                .font(.dripBody(14))
                                .foregroundStyle(Color.drip.textPrimary)
                            Text("When your runs are placed on the training clock")
                                .font(.dripCaption(12))
                                .foregroundStyle(Color.drip.textTertiary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(AthleteTimeZone.displayName(AthleteTimeZone.identifier))
                                .font(.dripCaption(12))
                                .foregroundStyle(Color.drip.textPrimary)
                            Text(timezoneOverride.isEmpty ? "FOLLOWING DEVICE" : "SET MANUALLY")
                                .font(.dripCaption(10)).tracking(0.8)
                                .foregroundStyle(Color.drip.textTertiary)
                        }
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.drip.textTertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .sheet(isPresented: $showTimeZonePicker) { AthleteTimeZonePicker() }
        .onAppear { maxHRText = "\(userMaxHR)" }
        .task {
            // Pull the account value (set on any device) into the local cache.
            await AthleteSettingsService.syncMaxHRFromServer()
            maxHRText = "\(userMaxHR)"
        }
    }

    // MARK: - Data Section

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            EditorialSectionHeader(index: "04", title: "Data")

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

                #if DEBUG
                Divider()
                    .background(Color.drip.divider)

                Button {
                    Task { await runStravaSync() }
                } label: {
                    HStack {
                        Image(systemName: "figure.run.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.drip.coral)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sync from Strava")
                                .font(.dripBody(14))
                                .foregroundStyle(Color.drip.textPrimary)
                            Text(stravaSyncSubtitle)
                                .font(.dripCaption(12))
                                .foregroundStyle(Color.drip.textTertiary)
                        }
                        Spacer()
                        if isStravaSyncing {
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
                .disabled(isStravaSyncing)
                .buttonStyle(.plain)
                #endif
            }
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private var stravaSyncSubtitle: String {
        if isStravaSyncing { return "Pulling latest runs…" }
        if let msg = stravaSyncResultMessage { return msg }
        return "Pull recent runs into training_logs (dev)"
    }

    private func runStravaSync() async {
        isStravaSyncing = true
        stravaSyncResultMessage = nil
        defer { isStravaSyncing = false }

        struct SyncBody: Encodable { let limit: Int }
        struct SyncResponse: Decodable {
            let ok: Bool?
            let totalActivities: Int?
            let imported: Int?
            let skipped: Int?
            let runs: Int?
            let filteredOut: Int?
            let error: String?
        }

        do {
            let response: SyncResponse = try await supabase.functions.invoke(
                "strava-test-pull",
                options: FunctionInvokeOptions(body: SyncBody(limit: 30))
            )
            if let err = response.error {
                stravaSyncResultMessage = "Error: \(err)"
                return
            }
            let imported = response.imported ?? 0
            let skipped = response.skipped ?? 0
            let total = response.totalActivities ?? 0
            let runs = response.runs ?? 0
            let filteredOut = response.filteredOut ?? 0
            if imported > 0 {
                stravaSyncResultMessage = "Imported \(imported), \(skipped) already synced"
            } else if runs == 0 {
                stravaSyncResultMessage = "No runs in last \(total) activities (\(filteredOut) non-runs filtered)"
            } else {
                stravaSyncResultMessage = "No new runs — \(runs) returned, \(skipped) already synced"
            }
        } catch {
            Log.app.error("Strava sync failed: \(error.localizedDescription)")
            stravaSyncResultMessage = "Failed: \(error.localizedDescription)"
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
            EditorialSectionHeader(index: "05", title: "App")

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

    // MARK: - Delete Account Section

    // Understated on purpose: a rarely-used, irreversible action shouldn't
    // compete with everyday controls. The weight lives in the confirmation
    // sheet, which requires typing DELETE before the button arms.
    private var deleteAccountSection: some View {
        Button {
            showDeleteAccount = true
        } label: {
            Text("Delete Account")
                .font(.dripCaption(12))
                .foregroundStyle(Color.drip.textTertiary)
                .underline()
        }
        .padding(.top, 2)
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
            EditorialSectionHeader(index: "02", title: "Coach Plan")

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

// MARK: - Editorial section header

/// A magazine-style section header: a coral index number, the label in the
/// mono eyebrow face, and a hairline rule running to the trailing edge. Gives
/// the Settings screen editorial rhythm instead of stacked identical cards.
struct EditorialSectionHeader: View {
    let index: String
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            Text(index)
                .font(.dripEyebrow(10))
                .tracking(10 * 0.12)
                .foregroundStyle(Color.drip.coral.opacity(0.7))
            Text(title.uppercased())
                .font(.dripEyebrow(11))
                .tracking(11 * 0.12)
                .foregroundStyle(Color.drip.textSecondary)
            Rectangle()
                .fill(Color.drip.divider)
                .frame(height: 1)
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Delete Account confirmation sheet

/// A deliberate, hard-to-fat-finger confirmation for permanent account
/// deletion. Spells out exactly what is erased, then requires the athlete to
/// type DELETE before the destructive button arms. On success it clears the
/// local session so RootView returns to the sign-in screen.
struct DeleteAccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var confirmText = ""
    @State private var isDeleting = false
    @State private var errorMessage: String?

    private var isArmed: Bool {
        confirmText.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "DELETE"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DripBackground().ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("DELETE ACCOUNT")
                                .font(.dripEyebrow(10))
                                .tracking(10 * 0.16)
                                .foregroundStyle(Color.drip.injured)
                            Text("This can't be undone.")
                                .font(.dripDisplay(27))
                                .foregroundStyle(Color.drip.textPrimary)
                        }

                        Text("Deleting your account permanently removes everything tied to it:")
                            .font(.dripBody(14))
                            .foregroundStyle(Color.drip.textSecondary)

                        VStack(alignment: .leading, spacing: 8) {
                            erasedRow("Every run, workout, and pace split")
                            erasedRow("All voice memos and their transcripts")
                            erasedRow("Niggles, moods, and check-ins")
                            erasedRow("Training plans and coaching history")
                            erasedRow("Your profile, bio, and photo")
                            erasedRow("Your sign-in — you'll be logged out")
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.drip.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 16))

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Type DELETE to confirm")
                                .font(.dripCaption(12))
                                .foregroundStyle(Color.drip.textSecondary)
                            TextField("DELETE", text: $confirmText)
                                .font(.dripBody(16))
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .padding(12)
                                .background(Color.drip.cardBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.dripCaption(12))
                                .foregroundStyle(Color.drip.injured)
                        }

                        Button {
                            Task { await performDeletion() }
                        } label: {
                            HStack {
                                if isDeleting { ProgressView().tint(.white) }
                                Text(isDeleting ? "Deleting…" : "Delete My Account")
                                    .font(.dripLabel(14))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.drip.injured)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        .disabled(!isArmed || isDeleting)
                        .opacity(!isArmed || isDeleting ? 0.5 : 1)

                        Button {
                            dismiss()
                        } label: {
                            Text("Cancel")
                                .font(.dripLabel(14))
                                .foregroundStyle(Color.drip.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .disabled(isDeleting)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 40)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isDeleting)
        }
    }

    private func erasedRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.drip.injured)
                .frame(width: 3, height: 3)
                .padding(.top, 7)
            Text(text)
                .font(.dripBody(13.5))
                .foregroundStyle(Color.drip.textPrimary)
            Spacer(minLength: 0)
        }
    }

    private struct DeleteResponse: Decodable {
        let ok: Bool?
        let error: String?
    }

    private func performDeletion() async {
        isDeleting = true
        errorMessage = nil
        do {
            let response: DeleteResponse = try await supabase.functions.invoke("delete-account")
            if let serverError = response.error {
                await MainActor.run {
                    errorMessage = serverError
                    isDeleting = false
                }
                return
            }
            // Data + auth identity are gone server-side. Clear the local
            // session; RootView swaps to the sign-in screen.
            try? await AuthManager.shared.signOut()
            await MainActor.run { dismiss() }
        } catch {
            Log.app.error("Account deletion failed: \(error.localizedDescription)")
            await MainActor.run {
                errorMessage = "Couldn't delete your account. Please check your connection and try again."
                isDeleting = false
            }
        }
    }
}

// MARK: - Avatar image helper

private extension UIImage {
    /// Downscale so the longest side is at most `max` px before upload — keeps
    /// profile photos small (a few hundred KB) without a visible quality hit.
    func resizedForAvatar(max: CGFloat = 512) -> UIImage {
        let longest = Swift.max(size.width, size.height)
        guard longest > max, longest > 0 else { return self }
        let scale = max / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
