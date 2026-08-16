//
//  TheWorkoutBlock.swift
//  RunningLog
//
//  "THE WORKOUT" — what the athlete set out to run. ONE implementation,
//  rendered by every surface that shows a completed session.
//
//  Why this file exists (2026-08-10)
//  ─────────────────────────────────
//  The description of a session used to be rendered — and edited — in two
//  places under two different names:
//
//    • the journal entry's inline composer, labelled "WORKOUT NOTES",
//      writing `workout_notes` on the JOURNAL row (`entryId`); and
//    • the receipt's `workoutRecipeSection`, labelled "THE WORKOUT",
//      reading and writing `workout_notes` on the STREAM row
//      (`linkedStreamLogId`).
//
//  Same column, two labels, two rows, no reconciliation. On a Strava-linked
//  run an edit in one was invisible in the other. `mirrorWorkoutNotes` was
//  added to hide the symptom; this removes the second editor entirely.
//
//  There is now one block and one editor. It takes the row it renders from
//  (`workoutId`) plus any rows that must stay in step (`mirrorIds`), and
//  `EditWorkoutNotesSheet` writes all of them in one save. Whichever surface
//  the athlete edits from, every surface agrees on the next read.
//
//  This is still a patch over the identity split — two rows for one run. The
//  fix is `session_id` (see WORKOUT-EDITABILITY-EVAL.md); when it lands,
//  `mirrorIds` goes away and this file keeps working unchanged.
//

import SwiftUI

struct TheWorkoutBlock: View {

    /// The `training_logs` row this block reads and writes. Nil in previews
    /// and injected-lap test seams — the block then renders read-only.
    let workoutId: UUID?

    /// Other rows holding the same session that must not drift. On a linked
    /// run the journal sheet passes the journal row here while rendering
    /// against the stream row. Empty everywhere else.
    var mirrorIds: [UUID] = []

    /// Shown as the editor sheet's headline, e.g. "August 8".
    let dateLabel: String

    /// The structure the parser derived — "8 × 800", "18.1 MI". Sits opposite
    /// the eyebrow as a quiet receipt of what was actually run. Never a
    /// substitute for the athlete's own words.
    var repHeadline: String?

    /// Pre-loaded text, for callers that already fetched the prescription
    /// (the receipt does, as part of its single batched load). Pass
    /// `loadsOwnNotes: false` alongside it to skip the redundant round trip.
    var notes: String?

    /// Fetch `workout_notes` on appear. True for callers that don't already
    /// hold it — the journal entry, which renders this block above the fold,
    /// before the receipt further down has loaded anything.
    var loadsOwnNotes: Bool = true

    /// Fired after a successful save so the caller can re-read whatever it
    /// derives from this text (the receipt re-derives its rep structure).
    var onSaved: () -> Void = {}

    @State private var fetched: String?
    @State private var didFetch = false
    @State private var showEditor = false

    /// The value this block last wrote, held locally so the text on screen
    /// changes the instant the editor dismisses — the caller's refresh may
    /// wait on laps, streams, and a server-side re-parse.
    ///
    /// A `String?` behind a `didEdit` flag, not a bare optional: clearing the
    /// field is a real value (nil = "no description"), and a bare optional
    /// would be indistinguishable from "hasn't been edited" and fall back to
    /// the stale text the caller injected.
    @State private var didEdit = false
    @State private var editedText: String?

    /// The athlete's own description, or nothing.
    ///
    /// Deliberately never falls back to `parsed_structure.pattern`. The
    /// pattern is the parser's guess at what the GPS trace looked like;
    /// showing it under "THE WORKOUT" would launder a guess into the
    /// athlete's own words, and pre-filling the editor with it would let a
    /// single Save make that laundering permanent. With no description there
    /// is an invitation to write one, and nothing else.
    private var text: String {
        let raw = didEdit ? editedText : (notes ?? fetched)
        return (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Group {
            if !text.isEmpty {
                described
            } else if workoutId != nil {
                addAffordance
            }
        }
        .task {
            guard loadsOwnNotes, !didFetch, let id = workoutId else { return }
            didFetch = true
            let pre = await WorkoutLapsService.fetchPrescription(workoutId: id)
            // `.notes` only — see the note on `text` about `.pattern`.
            fetched = pre.notes
        }
        .sheet(isPresented: $showEditor) {
            if let id = workoutId {
                EditWorkoutNotesSheet(
                    workoutId: id,
                    mirrorIds: mirrorIds,
                    dateLabel: dateLabel,
                    initialText: text
                ) { saved in
                    didEdit = true
                    editedText = saved
                    onSaved()
                }
            }
        }
    }

    // ────────────────────────────────────────────────────────────────────
    // Described — the eyebrow, the receipt of what was run, and the recipe
    // ────────────────────────────────────────────────────────────────────

    private var described: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text("THE WORKOUT")
                    .font(.dripEyebrow(11)).tracking(1.3)
                    .foregroundStyle(Color.drip.textSecondary)
                Spacer(minLength: 8)
                if let repHeadline, !repHeadline.isEmpty {
                    Text(repHeadline.uppercased())
                        .font(.dripStat(9)).tracking(1.0)
                        .foregroundStyle(Color.drip.textTertiary)
                        .lineLimit(1)
                }
                // The affordance sits next to the thing it edits. No global
                // edit mode — one field, one tap, one write.
                if workoutId != nil {
                    Text("EDIT")
                        .font(.dripStat(9)).tracking(1.2)
                        .foregroundStyle(Color.drip.coral)
                }
            }

            // Parsed into rows when it reads as a recipe; verbatim when it
            // doesn't. An unparseable note is never hidden and never rejected
            // — the athlete should not have to write for the parser.
            if let steps = WorkoutRecipeParser.parse(text) {
                WorkoutRecipeView(steps: steps)
            } else {
                Text(text)
                    .font(.dripBody(13))
                    .foregroundStyle(Color.drip.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if workoutId != nil { showEditor = true } }
    }

    // ────────────────────────────────────────────────────────────────────
    // Undescribed — the invitation
    // ────────────────────────────────────────────────────────────────────

    /// Was: nothing at all. A run with no description rendered no section, so
    /// there was nothing to tap and no way to acquire one.
    private var addAffordance: some View {
        Button { showEditor = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus").font(.system(size: 10, weight: .semibold))
                Text("ADD THE WORKOUT")
                    .font(.dripStat(9)).tracking(1.2)
            }
            .foregroundStyle(Color.drip.textTertiary)
            .padding(.horizontal, 12).padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(Color.drip.divider)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
