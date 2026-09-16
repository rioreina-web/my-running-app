# PREDICTOR ANCHOR PARITY — the Aug 15 incident

Filed 2026-08-15, from a live screenshot of the founder's own Predicted Times
screen. This is the parity break the architecture warns about, observed in
production, with a clean root cause. Fix is iOS-side, one concept.

## 0 · The incident

The phone's Predicted Times screen (FitnessPredictorView, on-device
`generateLocalPrediction`) showed:

```
ANCHORED ON   10K 33:04 · Apr 14 2026 · "your most recent timed effort" · 17W AGO
10K 33:44 · 5K 16:14 · MILE 4:47 · HALF 1:14        (PR 31:20 shown alongside)
```

The nightly SERVER snapshot from the same morning (`fitness_snapshots`,
2026-08-15 03:30 UTC) said:

```
anchor: race (10K) [Feb 7 · 31:20] → 10K 32:00 · 5K 15:24 · MILE 4:28 · HALF 1:10:32
```

**Same athlete, same day, 104 seconds apart on the 10K.** The screen and the
Trends tile were one refresh away from contradicting each other.

## 1 · Root cause — three compounding, each individually correct-looking

1. **The PB aged out of the phone's detection horizon 9 days before the
   screenshot.** iOS fetches 180 days of history for race detection
   (`fetchFromAllSources(days: 180)`) and detects races only from what it can
   see (workouts + voice-log note parsing). Feb 7 + 180 = **Aug 6**. On Aug 5
   the phone could see the 31:20; on Aug 7 it could not. The anchor silently
   switched to the only race left in window — the Cap10K. No code changed.
   **The server does not have this horizon**: `fitnessPrediction.ts` merges
   `race_results` (all-time) into detection — the merge that made the server
   "strictly more reliable" also made it silently DIFFERENT. The selection
   penalty (0.2%/wk) is identical on both platforms; the CANDIDATE SETS
   diverged.
2. **The surviving anchor is the un-normalized Cap10K** — 69°F/68°F dew/98%RH
   + ~100m climb, neutral-equivalent ≈ 31:50 (`raceNormalization.ts`, tested).
   Anchored raw at 33:04.
3. **17 weeks of staleness decay on top** pushed the forward read to 33:44 —
   slower than the anchor race itself. Correct decay logic, applied to the
   wrong anchor.

Also noted: iOS shows Apr 14 / 33:04 where `race_results` says Apr 12 / 33:02
— the phone note-parsed its own copy rather than reading the canonical row.
Same disease, milder symptom.

## 2 · The fix (iOS, one concept): the phone reads the race ledger

`FitnessPredictorService` merges `race_results` into its detected races before
anchor selection — the SAME merge the server already does, de-duplicated by
(raceType, date) the same way. Proof of fitness must come from the ledger, not
from what happens to be inside a fetch window.

- Query: `race_results` for the user, all time, excluding rows the athlete
  dismissed ("not a race"). Cheap: a handful of rows, already RLS-scoped.
- Map to the iOS `DetectedRace` shape; prefer `official_time_seconds` over
  `recorded_time_seconds` when present.
- Selection logic UNCHANGED — same 0.2%/wk age-weighted pick, same
  primary-window rules, same decay. With the Feb race back in the candidate
  set, the existing math already chooses it (penalized: Feb ≈ 1981 beats
  Apr ≈ 2049).
- Display the anchor from the canonical row (fixes Apr 14/33:04 vs Apr 12/33:02).

**Guard (cheap, catches every future divergence):** when a server snapshot
< 48h old exists and the local prediction's anchor differs from the
snapshot's `data_source`, log it (Sentry breadcrumb). The two implementations
are supposed to be identical; a disagreement is always a bug in one of them.

## 3 · Acceptance

- Predictor screen anchors **10K 31:20 · Feb 7** and predicts **≈ 32:00**,
  matching the nightly snapshot to within rounding.
- Time-travel test: with `now` mocked past Feb 7 + 180d, the anchor does NOT
  switch — the ledger has no horizon.
- A dismissed race never anchors.

## 4 · "Does it not evaluate my training at all?" (asked 2026-08-15)

It does — but only through channels that structurally cannot credit THIS
athlete's summer, which is why 78-mile weeks with two workouts read as
nothing on this screen:

- **Training may only nudge, never set.** A training anchor blends 50/50
  with a stale race and the net result is capped at 3% faster than the
  race-demonstrated pace (the 2026-07-16 displacement cap — correct; one hot
  fartlek must not move the estimate 9% in a day).
- **Training anchors are conservative by construction**, derived from rep
  paces. The athlete's threshold reps run ~5:18–5:21/mi, his race-equivalent
  is ~5:09 — so his own quality sessions parse SLOWER than his demonstrated
  fitness and the "must be actually faster than the race" rule quietly drops
  them. High-volume maintenance registers as no new evidence.
- **What training DOES do here is suppress decay** — `detectDetraining`
  correctly returns nothing for a training athlete, so a race anchor holds
  at full value. But the screen shows 33:44 off a 33:04 anchor: the forward
  read still moved slower despite a heavy block. Whichever term did that
  (staleness on the anchor path, not the snapshot path) is mis-tuned for an
  athlete in a build and should be verified while fixing §2.

The honest design position (CURRENT-FITNESS-APPLY.md §1.1): training can't
PROVE 31:20 fitness — only a race or race-equivalent effort can, and that
asymmetry is right. But training evidence should DRIFT the number between
anchors (ladder rungs 3–4), and the machinery for that drift now exists and
is not wired into the forward read: flat EF at higher volume + rep-shape
verdicts are affirmative maintenance evidence, currently invisible to this
screen. Wiring `fitness_signal`/`rep_signal` in as the drift term is the
right follow-up — as its own change, after parity is restored, so its effect
is measurable against a correct baseline.

## 5 · Sequencing with the other open work

- This fix restores parity on TODAY'S rule (raw times, penalized recency).
  **Conditions normalization (`pickAnchorIndex`) stays un-wired until it can
  land on both platforms in one change** — do not bundle it here; one
  behavior change at a time, each verifiable against the nightly snapshot.
- After this ships, the race-confirmation flow (RACE-CONFIRM-ONBOARDING-
  APPLY.md) gains a second reason to exist: the ledger the phone now reads is
  the one the athlete curates.
