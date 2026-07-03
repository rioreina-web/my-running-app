# Spec: editable workouts (notes + correct the parse) — for the Xcode agent

**Why:** workouts are auto-parsed (type + structure from laps) and the athlete
has no way to correct them or add their own notes. They need to: **change the
workout type**, **add/edit notes**, and **mark a mis-parsed "workout" as not
one**. Build this as a real edit form — it's interactive UI that needs a
compile/tap loop to get right.

> Context: this was attempted from a no-Xcode environment and the inline
> `Menu` on the type label **did not respond to taps inside the sheet** — a
> known SwiftUI flakiness. Use `Form` + `Picker` + a `Button`/`confirmationDialog`,
> NOT an inline `Menu` in the scrolling sheet. That's the one real gotcha here.

## Where it lives

- The workout detail is `RunningLog/Analysis/WorkoutRepChart.swift`, presented
  in a `NavigationStack` sheet from `Training/Analytics/WorkoutsAndRepsSection.swift`
  (and embedded in the Read via `Coaching/ModelOfYou/ModelOfYouView.swift`).
- Add a toolbar **"Edit"** button to that `NavigationStack` (`.toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Edit") {...} } }`) that presents an `EditWorkoutSheet` (a `Form`). A Form sheet is the reliable pattern — don't try to make the read-only chart inline-editable.
- `WorkoutRepChart` already has a working type control via `confirmationDialog`
  (the coral pill). You can keep that as a shortcut, but the full edit lives in
  the Form.

## Data facts (verified — these will not be the blocker)

- **RLS allows the write:** `training_logs` has `auth_update_own_logs`
  (`UPDATE` where `user_id = auth.uid()::text`). The user can update their own logs.
- **Columns to write:**
  - `workout_type` (text) — the type. Options below.
  - `notes` (text) — freeform athlete notes. *The daily Read reads
    `cleaned_notes ?? notes`, so writing `notes` flows into the Read.*
  - To "mark as not a real workout": set `workout_type = 'easy'` (or `'recovery'`).
- **Override durability:** `compute-workout-features` only fills `workout_type`
  when it's `null`, so a manual value already persists against incremental
  re-scoring. For hardening against a *full* re-backfill, add a
  `workout_type_locked boolean default false` column (migration) and have the
  classifier skip locked rows. Set it true on manual edit. (Nice-to-have, not
  required for v1.)

Type options (match the classifier vocabulary):
`intervals · threshold · tempo · fartlek · progression · easy · long_run · recovery · race`

## The save call (use a typed payload, not [String: Any])

```swift
struct WorkoutEdit: Encodable {
    let workout_type: String
    let notes: String?
    // let workout_type_locked: Bool   // if you add the column
}

func save(workoutId: UUID, type: String, notes: String?) async throws {
    try await supabase
        .from("training_logs")
        .update(WorkoutEdit(workout_type: type, notes: notes?.isEmpty == true ? nil : notes))
        .eq("id", value: workoutId.uuidString)
        .execute()
}
```

## The form (sketch)

```swift
struct EditWorkoutSheet: View {
    let workoutId: UUID
    @State var type: String
    @State var notes: String
    @Environment(\.dismiss) private var dismiss
    var onSaved: (() -> Void)? = nil

    let types = ["intervals","threshold","tempo","fartlek","progression","easy","long_run","recovery","race"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Type") {
                    Picker("Workout type", selection: $type) {
                        ForEach(types, id: \.self) { Text(pretty($0)).tag($0) }
                    }
                    // .pickerStyle(.menu) works fine INSIDE a Form (unlike a bare Menu in a ScrollView)
                }
                Section("Notes") {
                    TextField("How did it feel? Sleep, travel, niggles…", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            .navigationTitle("Edit workout")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { try? await save(workoutId: workoutId, type: type, notes: notes); onSaved?(); dismiss() }
                    }
                }
            }
        }
    }
}
```

Post Run Drip: use the app's `Color.drip.*` + `.drip*` fonts on the labels;
the `Form` chrome can stay native or be themed to taste.

## Acceptance

- From a workout, tap **Edit** → a form opens (it WILL open; Form/Picker/TextField
  are reliable where the inline Menu wasn't).
- Change the type and/or notes, hit **Save** → `training_logs` updates; the
  detail and the Workouts & reps list reflect the new type; the notes show up
  (and feed the daily Read).
- Re-open the workout → the edit persisted.

## Notes for whoever builds it

- The athlete's manual edits are higher-trust than the parse — once they set a
  type or write notes, treat them as source of truth (the `workout_type_locked`
  flag is how you enforce that if you add it).
- This is the "correctable model" idea: letting the athlete fix the parse is
  both a trust win and a data-quality win (their corrections improve the
  classifier's ground truth over time).
