//
//  EditWorkoutNotesSheet.swift
//  RunningLog
//
//  "THE WORKOUT" — the athlete's own description of the session they set out
//  to run: reps, recoveries, target paces. Free text, no schema.
//
//  Why this exists (2026-08-06)
//  ────────────────────────────
//  `workout_notes` was editable only through `HistoryDetailSheet`'s global
//  edit mode, which writes to the *journal* row (`entryId`). A Strava-linked
//  run is TWO `training_logs` rows — the voice/manual entry and the import
//  that carries the stream and laps — and the receipt renders from the import
//  row (`linkedStreamLogId`). So the edit saved cleanly, returned 200, and
//  changed nothing on screen. There was no error to see.
//
//  This sheet takes the row id it was handed and writes to that row, which is
//  by construction the row the caller is rendering. One field, one tap, one
//  write, no mode.
//
//  `mirrorIds` (2026-08-10) closes the other half. A caller that holds BOTH
//  ids — the journal sheet renders against the stream row while owning the
//  journal row — passes the other one here, and the save writes them together
//  in one call site. Mirroring used to live in `HistoryDetailViewModel`, which
//  meant it applied to edits made from the journal and not to edits made from
//  the receipt; now it applies to every edit, because there is only one editor.
//
//  This is a patch, not the fix. The fix is a `session_id` that makes the two
//  rows one session — see WORKOUT-EDITABILITY-EVAL.md. When it lands, delete
//  `mirrorIds` and nothing else changes.
//
//  "AI advises, never acts": whatever the import or the parser guessed, what
//  the athlete types here wins.
//

import SwiftUI
import Supabase
import os

struct EditWorkoutNotesSheet: View {
    /// The `training_logs` row to write. MUST be the row the caller reads its
    /// prescription from — passing the journal row here recreates the bug.
    let workoutId: UUID
    /// Rows carrying the same session that must not drift out of step with
    /// `workoutId`. Written best-effort after the primary row succeeds.
    var mirrorIds: [UUID] = []
    let dateLabel: String
    let initialText: String
    /// Called after a successful save with the value that was written — nil
    /// when the athlete cleared the field. The caller can render it straight
    /// away instead of waiting on its own re-read.
    var onSaved: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    @State private var text: String = ""
    @State private var saving = false
    @State private var errorMsg: String?

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isDirty: Bool {
        trimmed != initialText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.drip.background.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("THE WORKOUT")
                            .font(.dripEyebrow(11)).tracking(1.3)
                            .foregroundStyle(Color.drip.coral)
                        Text(dateLabel)
                            .font(.dripDisplay(28))
                            .foregroundStyle(Color.drip.textPrimary)
                        Text("What was the session meant to be? Reps, recoveries, target paces — one per line.")
                            .font(.dripBody(14))
                            .foregroundStyle(Color.drip.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // Plain text, deliberately. The recipe parser reads this on
                    // the way out; it is never required to. An unparseable note
                    // renders verbatim rather than being rejected at entry —
                    // the athlete should never have to write for the parser.
                    ZStack(alignment: .topLeading) {
                        if trimmed.isEmpty {
                            Text(Self.placeholder)
                                .font(.dripBody(14))
                                .foregroundStyle(Color.drip.textTertiary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 16)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $text)
                            .font(.dripBody(14))
                            .foregroundStyle(Color.drip.textPrimary)
                            .scrollContentBackground(.hidden)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .focused($focused)
                    }
                    .frame(minHeight: 180, maxHeight: 320)
                    .background(Color.drip.cardBackgroundElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.drip.divider, lineWidth: 1)
                    )

                    if let errorMsg {
                        Text(errorMsg)
                            .font(.dripBody(13))
                            .foregroundStyle(Color.drip.injured)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text("Saved to this run everywhere it appears. Clearing the field removes the description.")
                        .font(.dripCaption(12))
                        .foregroundStyle(Color.drip.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer()
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(.dripBody(15))
                        .foregroundStyle(Color.drip.textSecondary)
                        .disabled(saving)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await save() }
                    } label: {
                        if saving {
                            ProgressView().tint(Color.drip.coral)
                        } else {
                            Text("Save")
                                .font(.dripLabel(15))
                                .foregroundStyle(isDirty ? Color.drip.coral : Color.drip.textTertiary)
                        }
                    }
                    .disabled(saving || !isDirty)
                }
            }
            .toolbarBackground(Color.drip.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear {
            text = initialText
            // One tap in, straight to typing. The athlete opened this sheet on
            // purpose; making them tap the box again is a wasted step.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { focused = true }
        }
    }

    private static let placeholder = """
    Warmup: 2 miles
    Intervals: 5 × 4 min @ 5:20/mi, 90s–2 min jog recovery
    Cooldown: 1 mile
    """

    @MainActor
    private func save() async {
        saving = true
        errorMsg = nil
        // Empty clears the field rather than writing "" — a blank string would
        // read as "described, with nothing in it" everywhere downstream and
        // suppress the ADD affordance that gets the athlete back in here.
        let saved: String? = trimmed.isEmpty ? nil : trimmed
        let updateData: [String: AnyJSON] = [
            "workout_notes": saved.map { AnyJSON.string($0) } ?? .null,
        ]
        do {
            try await supabase
                .from("training_logs")
                .update(updateData)
                .eq("id", value: workoutId.uuidString)
                .execute()

            // Keep the run's other row in step. Best-effort by design: the row
            // the caller renders from is already written, so a mirror failure
            // must never surface as a failed save. It logs and moves on.
            for mirrorId in mirrorIds where mirrorId != workoutId {
                do {
                    try await supabase
                        .from("training_logs")
                        .update(updateData)
                        .eq("id", value: mirrorId.uuidString)
                        .execute()
                } catch {
                    Log.database.error("mirror workout_notes to \(mirrorId) failed: \(error)")
                }
            }

            // Re-derive the rep structure from what the athlete just typed.
            // The parser treats typed `workout_notes` as the TOP source for
            // structure/intent — above the GPS guess — so "5 × 4 min w/ 90s
            // jog" reshapes the chart to match. A manual "Fix reps"
            // correction is NOT clobbered: parse-workout-structure treats
            // `parsed_structure.edited_by_user === true` as sacrosanct.
            //
            // Fire-and-forget, and deliberately AFTER `onSaved()` below is
            // wired: the text lands immediately, the chart catches up when the
            // function returns. Making the athlete watch a spinner for a
            // background re-parse would be the wrong trade.
            let reparseId = workoutId.uuidString
            let reparseUserId = AuthManager.shared.userId
            let refresh = onSaved
            Task {
                _ = try? await callEdgeFunction(
                    name: "parse-workout-structure",
                    body: ["training_log_id": reparseId, "user_id": reparseUserId]
                )
                await MainActor.run { refresh(saved) }
            }

            saving = false
            onSaved(saved)
            dismiss()
        } catch {
            Log.database.error("save workout_notes failed: \(error)")
            ErrorReporter.shared.report(error, context: "edit workout notes")
            errorMsg = "Couldn't save. Check your connection and try again."
            saving = false
        }
    }
}
