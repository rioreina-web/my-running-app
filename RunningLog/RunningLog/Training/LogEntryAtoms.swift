//
//  LogEntryAtoms.swift
//  RunningLog
//
//  Small pieces of a training-log entry — source badge, niggle marks —
//  factored out of `JournalLogRow` so the Log tab row and the workout
//  detail sheet render the same thing instead of two hand-copied
//  versions that quietly drift (as `JournalLogRow` and `memoBlock` in
//  `HistoryDetailSheet+Editorial.swift` already have: same concepts,
//  different names, and the detail sheet is missing niggles and the
//  key-session star entirely).
//

import SwiftUI

/// Audio / text / check-in indicator. Same three states `JournalLogRow`
/// has always shown, just callable from more than one place now.
struct LogSourceBadge: View {
    let isCheckIn: Bool
    let hasAudio: Bool

    var body: some View {
        if isCheckIn {
            Text("CHECK-IN")
                .font(.dripEyebrow(10))
                .tracking(0.8)
                .foregroundStyle(Color.drip.textTertiary)
        } else if hasAudio {
            HStack(spacing: 5) {
                Image(systemName: "play.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.drip.coral)
                Text("VOICE")
                    .font(.dripEyebrow(10))
                    .tracking(0.8)
                    .foregroundStyle(Color.drip.coral)
            }
        } else {
            Text("TEXT ONLY")
                .font(.dripEyebrow(10))
                .tracking(0.8)
                .foregroundStyle(Color.drip.textTertiary)
        }
    }
}

/// Full chip for one journal niggle mention — the athlete's own body-area
/// words, quoted verbatim per the Niggles spec (detection, never
/// diagnosis). Used where there's room to actually read them: the detail
/// sheet, the niggle timeline.
///
/// Named `JournalNiggleChip` (not `NiggleChip`) because `WorkoutReceiptSignals.swift`
/// already owns that name for a different, richer concept — a tappable
/// chip over `ReceiptNiggle` with a watching/flagged/resolved status. This
/// one is a plain, non-interactive body-area mention off `JournalNiggle`.
struct JournalNiggleChip: View {
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(Color.drip.textTertiary).frame(width: 4, height: 4)
            Text(label.uppercased())
                .font(.dripEyebrow(9))
                .tracking(0.6)
                .foregroundStyle(Color.drip.textSecondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .overlay(Capsule().stroke(Color.drip.divider, lineWidth: 1))
    }
}

/// Compact dot + count for a row that doesn't have room to spell out
/// which body part — the row still says *something was mentioned*,
/// and a tap into the entry gets the verbatim word. Restraint here
/// matches `MoodBadge`'s own rule: a mark, not a chip wall.
struct NiggleCountIndicator: View {
    let count: Int

    var body: some View {
        if count > 0 {
            HStack(spacing: 4) {
                Circle().fill(Color.drip.textTertiary).frame(width: 4, height: 4)
                Text("\(count)")
                    .font(.dripEyebrow(9))
            }
            .foregroundStyle(Color.drip.textSecondary)
        }
    }
}
