//
//  AthleteTimeZone.swift
//  RunningLog
//
//  The single answer to "what timezone did this athlete run in?"
//
//  WHY THIS EXISTS. `training_logs.workout_date` is `TIMESTAMPTZ`, so Postgres
//  normalizes every run to a UTC instant on write and PostgREST returns it with
//  a `+00:00` offset. The offset the run was actually recorded at is gone by the
//  time any client sees it. Anything that wants to say WHEN a run happened —
//  the week stress strip's whole x-axis, "Morning" vs "Evening", the hour in a
//  panel — has to reconstruct that from somewhere, and every caller
//  reconstructing it independently is how they get to disagree.
//
//  THE LADDER, most trustworthy first:
//    1. A non-zero offset carried on the timestamp itself. Some writer went to
//       the trouble of preserving it; it beats anything we could infer.
//    2. The athlete's explicit choice in Settings. Set once, syncs to the
//       account, and survives travel — the point of making it settable is that
//       a runner visiting another timezone for a week does not want last
//       month's dawn runs redrawn as evening ones.
//    3. The device timezone. The default, and right for almost everyone almost
//       always.
//
//  Step 2 is this file. `TrendsRunDTO.parse` owns step 1 and calls in here for
//  the rest.
//
//  WHY AN OVERRIDE RATHER THAN JUST WRITING THE PICKED ZONE. `AthleteSettings
//  Service.syncDeviceTimezone()` upserts the device zone at every launch, so a
//  picked value with nothing marking it as deliberate would be silently reverted
//  the next morning. The override flag is what makes a choice stick.
//

import Foundation
import SwiftUI

enum AthleteTimeZone {

    /// Local mirror of the athlete's explicit choice. Empty string means
    /// "follow the device", which is the default and is NOT the same as an
    /// athlete who has deliberately chosen UTC.
    static let overrideKey = "athleteTimezoneOverride"

    /// The athlete's chosen IANA identifier, or nil when following the device.
    static var overrideIdentifier: String? {
        let raw = UserDefaults.standard.string(forKey: overrideKey) ?? ""
        guard !raw.isEmpty, TimeZone(identifier: raw) != nil else { return nil }
        return raw
    }

    static var isOverridden: Bool { overrideIdentifier != nil }

    /// The timezone every "when did this happen" question should be answered
    /// in. Never read `TimeZone.current` directly at a call site — use this,
    /// so the Settings choice actually reaches the thing the athlete is
    /// looking at.
    static var resolved: TimeZone {
        overrideIdentifier.flatMap { TimeZone(identifier: $0) } ?? .current
    }

    static var identifier: String { resolved.identifier }

    /// "America/Chicago" → "Chicago · CDT". The identifier is the truth but the
    /// abbreviation is what a person recognizes, so the row shows both.
    static func displayName(_ identifier: String, on date: Date = Date()) -> String {
        guard let tz = TimeZone(identifier: identifier) else { return identifier }
        let city = identifier.split(separator: "/").last.map {
            $0.replacingOccurrences(of: "_", with: " ")
        } ?? identifier
        let abbrev = tz.abbreviation(for: date) ?? ""
        return abbrev.isEmpty ? String(city) : "\(city) · \(abbrev)"
    }

    /// Set (or clear) the override, and push it to the account so the server
    /// crons — the Daily Read fires at the athlete's local morning — agree with
    /// what the app is drawing. Passing nil returns to following the device.
    ///
    /// Writes UserDefaults FIRST so the UI is correct even if the network call
    /// fails; the launch sync retries the upload on the next cold start.
    @MainActor
    static func set(_ identifier: String?) async {
        let value = identifier.flatMap { TimeZone(identifier: $0) != nil ? $0 : nil }
        UserDefaults.standard.set(value ?? "", forKey: overrideKey)
        // Clearing the override hands control back to the device zone, so push
        // that rather than leaving the account on the abandoned choice.
        await AthleteSettingsService.saveTimezone(value ?? TimeZone.current.identifier)
    }

    /// The full IANA list, minus the deprecated aliases nobody means to pick.
    /// Sorted by identifier so the region groups stay together.
    static var allIdentifiers: [String] {
        TimeZone.knownTimeZoneIdentifiers
            .filter { $0.contains("/") && !$0.hasPrefix("Etc/") }
            .sorted()
    }
}

// MARK: - Picker

/// A searchable list of every timezone, with "follow this device" pinned at the
/// top. A `Picker` over ~400 identifiers is a menu nobody can use; a search
/// field finds "Chicago" in two keystrokes.
struct AthleteTimeZonePicker: View {

    @Environment(\.dismiss) private var dismiss
    @AppStorage(AthleteTimeZone.overrideKey) private var override: String = ""
    @State private var query = ""

    private var matches: [String] {
        let all = AthleteTimeZone.allIdentifiers
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return all }
        return all.filter { $0.replacingOccurrences(of: "_", with: " ")
                             .localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        Task { await AthleteTimeZone.set(nil); dismiss() }
                    } label: {
                        row(title: "Follow this device",
                            subtitle: AthleteTimeZone.displayName(TimeZone.current.identifier),
                            checked: override.isEmpty)
                    }
                } footer: {
                    Text("Your runs are placed on the training clock using this "
                         + "zone. Set it explicitly if you travel and want past "
                         + "runs to stay at the hour you actually ran them.")
                }

                Section {
                    ForEach(matches, id: \.self) { id in
                        Button {
                            Task { await AthleteTimeZone.set(id); dismiss() }
                        } label: {
                            row(title: id.replacingOccurrences(of: "_", with: " "),
                                subtitle: AthleteTimeZone.displayName(id),
                                checked: override == id)
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Search time zones")
            .navigationTitle("Time Zone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func row(title: String, subtitle: String, checked: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.dripBody(14))
                    .foregroundStyle(Color.drip.textPrimary)
                Text(subtitle)
                    .font(.dripCaption(12))
                    .foregroundStyle(Color.drip.textTertiary)
            }
            Spacer()
            if checked {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.drip.coral)
            }
        }
        .contentShape(Rectangle())
    }
}
