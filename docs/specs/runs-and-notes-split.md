# Splitting runs and notes

**Status:** design, approved 2026-08-05
**Supersedes:** the dedup migration series `20260613220000` → `20260702200000`

---

## Why we keep re-fixing this

`training_logs` stores two different kinds of thing in one table:

- a **run** — measured, arrives from Strava/HealthKit, owns laps, streams, splits
- a **note** — recorded by the athlete, owns audio, transcript, mood, RPE

Because they share a table, nothing in the schema says *"these two rows are the
same workout."* So every screen has to guess. There are currently six separate
guessing implementations, and they disagree:

| Where | Rule |
|---|---|
| `LogDedup.swift` | same day, ±0.1 mi, drop `voice_log` if a GPS row exists |
| `WorkoutSyncService.swift` | ±5 min & ±0.2 mi, OR same day & ±0.5 mi |
| `_shared/shared/dedup.ts` | same day, ±0.2 mi, ±2 min |
| `voiceOrphanMatch.ts` | ±4 h, max(0.5 mi, 8%) |
| `dedupe_recent_training_logs()` | same day, 0.5 mi buckets, last 3 days |
| `VoiceLogView.swift:759` | its own inline variant |

Two of them even use different priority ladders for the same sources
(`LogDedupHelpers` scores 4/3/2/1; `dedup.ts` scores 5/4/3/2/1).

The only uniqueness the database actually enforces is a unique index on
`vital_workout_id`. A voice row has that column set to `NULL`, and `NULL` is
exempt from a partial unique index. **Nothing can structurally prevent the
duplicate.**

### The loop we've been stuck in

The duplicate insert has existed since Strava sync launched in March. What
changed is only whether it was *visible*:

- **Before 2026-07-02** — the dedup cron deleted the voice row within 3 days.
  Symptom: *"voice memos are hidden."* The athlete's journal entry vanished.
- **2026-06-29** — fixed the orphaned audio file, still deleted the row.
- **2026-07-02** — stopped touching voice rows entirely. Correct product call
  (a memo is a first-class journal entry). Symptom flipped: two sheets per run.

Five migrations, both symptoms, same root cause, never addressed: **nobody fixed
the insert.** Six of the last eight memos duplicated; all three in August.

The lesson: this cannot be fixed by tuning a threshold. As long as a note can be
written as a row that *looks like a run*, we are choosing between deleting the
athlete's words and showing them twice.

---

## Target model

### `training_logs` — runs only

Add a real identity column:

```
external_id  text  NOT NULL     -- 'strava_19596935022' | 'healthkit_<uuid>' | 'manual_<uuid>'
UNIQUE (user_id, external_id)
```

Every writer must supply one. No writer may insert a run without a source
identity. This makes duplicate runs impossible at the database level rather than
by convention.

Qualitative columns (`audio_url`, `transcript_url`, `cleaned_notes`, `mood`,
`felt_rpe`, `rpe_*`, `extracted_data`) eventually move out.

### `workout_notes` — notes only

```
id              uuid pk
user_id         text not null
run_id          uuid null references training_logs(id) on delete set null
recorded_at     timestamptz not null
audio_url       text
transcript_url  text
raw_transcript  text
cleaned_text    text
mood            text
felt_rpe        smallint
rpe_tags        text[]
extracted_data  jsonb
processing_status text
```

**`run_id` is nullable on purpose.** It carries the case that started all of
this: a memo recorded before the run has synced. Today that becomes a fake run
row. In the new model it is simply a note with no run yet — a valid, complete,
displayable journal entry. When the run arrives, `linkNoteToRun()` fills in
`run_id`. Either way there is exactly **one** note record and it is never
deleted, never merged, never duplicated.

### Where fuzzy matching is allowed

Exactly one function: `linkNoteToRun(note, candidateRuns)`, reusing the
`voiceOrphanMatch.ts` thresholds (±4 h, max(0.5 mi, 8%)).

It may only ever set `run_id`. It may **never** decide whether a run exists, and
it may never delete anything. Every other fuzzy matcher in the table above gets
deleted.

### What the screens become

The two sheets in the Aug 4 bug report collapse into one:

- **Journal** = `workout_notes` LEFT JOIN `training_logs`, ordered by
  `recorded_at`. A note with no run still shows.
- **Workout detail** = a run plus its notes.
- **Mileage totals** = `SELECT sum(...) FROM training_logs`. No dedup pass —
  notes aren't in the table, so they cannot double-count.

`LogDedup.swift` and `dedupe_recent_training_logs()` are deleted outright.

---

## Migration path

Each phase ships on its own and leaves the app working.

**Phase 0 — stopgap (done 2026-08-05)**
- `VoiceLogView.fetchStravaRunningWorkouts` now includes `strava` in its source
  filter, so synced runs reach the link picker and the existing
  attach-to-existing-row branch fires.
- Six duplicate pairs merged; audio, transcript, mood and words moved onto the
  run row. Backup in `_backup_voice_dupe_merge_20260805`.

**Phase 1 — make duplicate *runs* impossible (done 2026-08-06)**
Migration `20260806015008_training_logs_external_id.sql`.
- `external_id` added, backfilled (276 rows → 276 distinct keys, no collisions).
- `UNIQUE (user_id, external_id)` + `NOT NULL`.
- `trg_training_logs_ensure_external_id` fills the column on insert when a
  writer omits it. Five writers insert runs; requiring all five to change first
  would leave a window where an insert *fails* and an athlete silently loses a
  run. The trigger removes that window.
- *Verified:* an insert of a second row for `strava_19596935022` with
  `vital_workout_id` left NULL — the exact shape the old schema could not catch —
  is now rejected by `training_logs_user_external_uniq`.

**Scope note.** Phase 1 closes *sync-side* duplicates: the same activity
imported twice. It does **not** close the voice-memo class, because a memo has
no source activity id and so no uniqueness rule here can catch it. That class is
closed by Phase 2 and, until then, only by the Phase 0 picker fix.

**Phase 2 — create `workout_notes`, dual-write**
- Create the table; backfill from rows where
  `source IN ('voice_log','check_in') OR audio_url IS NOT NULL`.
- Voice upload writes to `workout_notes` **and** the old columns.
- Nothing reads the new table yet. Fully reversible.

**Phase 3 — move readers, delete matchers**
- Point the journal, workout detail, and coaching prompt builders at
  `workout_notes`.
- Delete the six fuzzy dedup implementations one at a time, each with the
  totals verified before and after.

**Phase 4 — drop the old columns**
- Stop dual-writing; drop the qualitative columns from `training_logs`.
- Drop `dedupe_recent_training_logs()` and disable cron job 15.

---

## Known remaining duplicate paths

- `ingest-manual-workout` sets no source id, so every manual entry gets a
  synthetic `external_id`. Submitting the same manual workout twice still makes
  two rows. Fix when manual entry gets real use — derive the id from
  (user, date, distance, duration).
- A memo recorded before its run syncs still creates a run-shaped row. Phase 2.

## The invariant to hold onto

> One physical run = one row in `training_logs`, identified by
> `(user_id, external_id)`.
> One recorded reflection = one row in `workout_notes`, never deleted, never
> merged, optionally pointing at a run.

Everything above is in service of those two sentences. If a future change makes
either one untrue, this bug comes back.

### How to check it's still true

```sql
-- must return 0 rows, always
select user_id, workout_date, round(workout_distance_miles::numeric,1) mi, count(*)
from training_logs
group by 1,2,3 having count(*) > 1;
```

Worth running as a scheduled check so the next regression surfaces on its own
rather than in a screenshot.
