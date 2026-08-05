//
//  SleepCheckInPrompt.swift
//  RunningLog
//
//  The one-tap sleep check-in — "Last night's sleep." Rough / OK / Good.
//
//  The highest-leverage single signal in the recovery design
//  (recovery-trend-v2 §2b: self-reported sleep quality is the strongest
//  prospective signal in the runner injury literature — Tier 1, one tap,
//  no hardware). Writes one row per night to `daily_checkins`
//  (user_id + local date, upsert — tapping again overwrites), which
//  `trends-timeline` decorates onto the daily substrate and the recovery
//  ledger's Sleep factor reads. The closed 3-word vocabulary matches the
//  mood discipline: the word is the input, points are derived downstream,
//  never stored numerically.
//
//  Visual register mirrors `TodayMoodPrompt` (eyebrow row · question ·
//  capsule choices) so the two check-ins read as one daily ritual. Unlike
//  the mood prompt's local-only storage, this writes through: the ledger
//  needs the row server-side. An @AppStorage echo keeps the card instant
//  and offline-tolerant; a failed write rolls the echo back.
//

import SwiftUI
import Supabase
import os

struct SleepCheckInPrompt: View {
    /// Local echo of today's rating, "YYYY-MM-DD:good". Render-fast cache
    /// only — the `daily_checkins` row is the source of truth.
    @AppStorage("todaySleepCheckIn") private var todaySleepKey: String = ""
    @State private var saving = false

    private let choices: [(key: String, label: String, color: Color)] = [
        ("rough", "ROUGH", Color.drip.tired),
        ("ok",    "OK",    Color.drip.neutral),
        ("good",  "GOOD",  Color.drip.positive),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("LAST NIGHT")
                    .font(.dripEyebrow(10))
                    .tracking(1.0)
                    .foregroundStyle(Color.drip.textSecondary)
                Spacer()
                if currentSelection != nil {
                    Text("LOGGED")
                        .font(.dripEyebrow(10))
                        .tracking(1.0)
                        .foregroundStyle(Color.drip.energized)
                }
            }

            Text("How did you sleep?")
                .font(.dripDisplay(20))
                .foregroundStyle(Color.drip.textPrimary)

            HStack(spacing: 8) {
                ForEach(choices, id: \.key) { choice in
                    let isSelected = currentSelection == choice.key
                    Button {
                        select(choice.key)
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(isSelected ? .white : choice.color)
                                .frame(width: 5, height: 5)
                            Text(choice.label)
                                .font(.dripEyebrow(11))
                                .tracking(1.1)
                        }
                        .foregroundStyle(isSelected ? .white : choice.color)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(isSelected ? choice.color : choice.color.opacity(0.12))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(saving)
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - State

    /// Today's rating, decoded from the @AppStorage key "YYYY-MM-DD:key".
    private var currentSelection: String? {
        let parts = todaySleepKey.split(separator: ":", maxSplits: 1)
        guard parts.count == 2, parts[0] == Substring(todayDateKey) else { return nil }
        return String(parts[1])
    }

    /// The night being rated — today's LOCAL date, matching the
    /// `daily_checkins.date` contract ("one row per athlete per local date").
    private var todayDateKey: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    // MARK: - Persistence

    private func select(_ quality: String) {
        let date = todayDateKey
        let previous = todaySleepKey
        todaySleepKey = "\(date):\(quality)"   // optimistic; it's one tap
        saving = true

        Task {
            defer { saving = false }
            guard let userId = AuthManager.shared.currentUserId else {
                todaySleepKey = previous
                return
            }
            struct CheckinRow: Encodable {
                let user_id: String
                let date: String
                let sleep_quality: String
                let updated_at: String
            }
            let row = CheckinRow(
                user_id: userId,
                date: date,
                sleep_quality: quality,
                updated_at: ISO8601DateFormatter().string(from: Date())
            )
            do {
                try await supabase
                    .from("daily_checkins")
                    .upsert(row, onConflict: "user_id,date")
                    .execute()
            } catch {
                Log.app.error("sleep check-in failed: \(error.localizedDescription)")
                todaySleepKey = previous   // roll back the optimistic tap
            }
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 24) {
        SleepCheckInPrompt()
    }
    .padding(24)
    .background(Color.drip.background)
}
