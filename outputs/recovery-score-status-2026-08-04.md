# Recovery score — where it's at

**Snapshot date:** 2026-08-04
**One line:** You have a working recovery score today — but it runs entirely on your
*words* and your *runs*. Nothing from the watch (HRV, sleep, resting HR, stress) reaches
it yet. The pipe to bring that in is designed and written but not switched on.

*Verified against the live `RunningAppMVP2` database and the codebase this session, not
from the design docs.*

---

## At a glance

Legend: 🟢 **Live** (in the app now) · 🟡 **Authored, not applied** (written, sitting in
the repo, not switched on) · 🔵 **Designed** (spec exists, nothing built) · ⚪ **Idea**
(discussed only) · 🖼️ **Mockup** (visual only)

| Piece | What it is | Status |
|---|---|---|
| **Recovery ledger** (`TrendsRecoveryLedger`) | The base-50 daily score on your screen: mood, recent load, body mentions, load vs 8-wk, days-on | 🟢 Live |
| **Readiness verdict** (`buildReadiness`) | push / hold / pull read in the coach layer, from memo-mentioned sleep/stress + load + mood | 🟢 Live |
| **Race readiness** | Separate 0–100 race-day fitness projection | 🟢 Live |
| **Garmin → Vital → app** | Workout ingestion (278 runs stored) | 🟢 Live |
| **Weather / heat per run** | temp, dew point, humidity, heat category, composite score on each run | 🟢 Live |
| **felt vs planned RPE** | How hard each run felt vs planned — collected | 🟢 Live |
| **HRV / resting HR / sleep / stress in the score** | Any watch biometric feeding recovery | 🔴 **Not in the app at all** |
| **Stress-load per workout** | `stress_load` migration + compute | 🟡 Authored, not applied |
| **Sleep/HRV ingestion** (`daily_biometrics`, webhook branch) | Brings watch data into the DB | 🟡 Authored, not applied |
| **One-tap sleep check-in** (`daily_checkins`) | Self-rated sleep quality | 🟡 Migration written; UI 🔵 designed |
| **The Daily Read** (unified score) | Balances load, heat, mood, niggles, sleep, HRV — the new model | 🔵 Designed |
| **Accuracy engine** (filter + per-athlete learning + felt-RPE loop) | Makes the score learn you over time | ⚪ Idea / partly discussed |
| **Card mockup** | Interactive card showing all new lines + the convergence gate | 🖼️ Mockup (artifact) |

---

## 🟢 What's live in the app today

**The recovery ledger** — the "31 · Flat" card. Starts at 50, five factors move it: mood
(your logged word), recent load (last 3 days of miles), body mentions (niggles, 14-day
look-back), load (last 7 days vs your own 8-week average), and days-on (consecutive days
run). Every line shows its arithmetic. **All five inputs are your words or your runs — no
sensor data.**

**The readiness verdict** — a separate push/hold/pull read that lives in the coach layer.
Worth knowing: it *looks* biometric (its code says "sleep" and "stress"), but those come
from what you *say* in voice memos — "rough sleep," "work stress" — not from the watch.
Same story: self-report + training load.

**The raw materials already flowing** — three things you collect today that the new score
wants and that make it cheap to build: every run comes in from Garmin through Vital;
every run carries real heat data (this week's Austin runs scored ~156 with a 75°F dew
point); and every run has how-hard-it-felt vs how-hard-it-was-planned. That last one is
the key to making the score accurate later.

---

## 🔴 The honest headline

**No version of your recovery score uses any watch biometric.** Not HRV, not resting
heart rate, not sleep, not body battery, not Garmin stress. That data reaches Vital and
then hits a wall: the webhook only keeps *workouts* and drops everything else, because
there's no table to put it in. This isn't a bug — it matches your own evidence review,
which argued the self-report signal is the real one and biometrics are corroboration. But
it means "recovery based on HRV and sleep" does not exist in the product yet.

---

## 🟡 Written this session, sitting in your repo, not switched on

These are real files on disk, additive and safe, waiting for a `db push` / deploy:

- `supabase/migrations/20260804090000_daily_biometrics.sql` — the table that catches HRV,
  resting HR, sleep from the watch.
- `supabase/migrations/20260804090100_daily_checkins.sql` — the table for your one-tap
  sleep rating.
- The **webhook sleep branch** (a paste-in block for `vital-webhook`) — routes the watch
  data into that table.
- The two **ledger factors** (Overnight = HRV paired with resting HR; Sleep) — Swift to
  extend the score.
- `SLEEP-HRV-APPLY-NOTES.md` — the step-by-step to apply all of the above.

Also still unapplied from *before* this session: the **stress-load** migration
(`20260731120000`), which the load factors want so they can use real training stress
instead of raw miles.

---

## 🔵 Designed, nothing built

- **The Daily Read** (`outputs/the-daily-read-score-design-2026-08-04.md`) — the unified
  score: load, heat stress, mood, niggles, sleep, HRV×resting-HR, life stress, monotony,
  all measured against your own baseline, evidence-weighted, with the convergence gate
  (biometrics only count when your words agree) and a confidence label.
- **The one-tap sleep UI** — the highest-value single addition; a small logging surface,
  specced in the apply notes.

---

## ⚪ Discussed, not yet specced

- **The accuracy engine** — the state-space filter (don't let noisy numbers yank the
  score), per-athlete weight learning (the score gets to know *you*), and the felt-RPE
  feedback loop (it checks itself against how your runs actually felt). This is the path
  from "a sensible score" to "an accurate-to-you score," and it's not written down yet.

---

## 🖼️ Visual only

- **The card mockup** (in your artifact gallery) — your Daily Read screen with all the new
  lines and a toggle demonstrating the convergence gate. Not wired to real data.

---

## The critical path (smallest steps, biggest unlock first)

1. **Apply the two migrations + the webhook branch, flip on sleep in Junction.** After
   this, HRV and sleep are landing in your database. Nothing on screen changes yet —
   safe, reversible. *(Turns the biggest 🔴 into collected data.)*
2. **Apply the stress-load migration** while you're there, so the load factors get real.
3. **Ship the one-tap sleep check-in.** Small UI, biggest evidenced signal.
4. **Wire the two ledger factors** so the score shows Sleep + Overnight lines.
5. **Then** decide big-picture: keep evolving the ledger, or build the full Daily Read.
6. **Later:** spec and build the accuracy engine, once there's a few weeks of data to
   learn from.

Everything in steps 1–4 is already written. The only genuinely new build is step 5's
score logic and step 6's learning loop.

---

## Docs produced this session (all in the repo)

- `outputs/sleep-hrv-recovery-ingestion-spec-2026-08-04.md`
- `outputs/the-daily-read-score-design-2026-08-04.md`
- `SLEEP-HRV-APPLY-NOTES.md`
- `supabase/migrations/20260804090000_daily_biometrics.sql`
- `supabase/migrations/20260804090100_daily_checkins.sql`
- `outputs/recovery-score-status-2026-08-04.md` *(this file)*
- Card mockup — in the artifact gallery
