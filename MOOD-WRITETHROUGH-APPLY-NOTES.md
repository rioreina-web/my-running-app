# Mood write-through — apply notes

**Date:** 2026-08-06 · Fixes the coverage gap the `recovery-score-evaluation-2026-08-05`
backtest measured: the Today mood prompt stored taps in `@AppStorage` only, so the
ledger's lead factor (mood) could only ever see moods attached to a logged run. Coverage
fell from ~60% of days in January to 0% in August. This makes the one-tap mood persist,
exactly like the sleep check-in already does.

Three files changed, all on disk in your repo now:

1. **`supabase/migrations/20260806120000_daily_checkins_mood.sql`** — adds a `mood` column
   to the existing `daily_checkins` table (closed vocabulary, lowercase, matching the
   ledger's `moodPoints` keys). Additive; no data touched.
2. **`RunningLog/RunningLog/App/TodayPlate18.swift`** — `TodayMoodPrompt.select()` now
   upserts one row per local date to `daily_checkins` (optimistic tap, rollback on
   failure), mirroring `SleepCheckInPrompt`. Only the `mood` column is sent, so a same-day
   sleep check-in on the shared row is preserved.
3. **`supabase/functions/trends-timeline/index.ts`** — the daily substrate now reads
   `mood` from `daily_checkins` and fills a day's mood **only when no run carried one**
   (a run-attached voice-log mood still wins). Additive; degrades to no-op if the column
   isn't there yet.

## Your steps, in order (~8 minutes)

### 1 · Terminal — commit, then push the migration
```bash
cd ~/my-running-app
git checkout -b mood-writethrough
git add -A && git commit -m "Mood write-through: persist one-tap mood to daily_checkins + timeline merge"
supabase migration list        # confirm 20260806120000_daily_checkins_mood is pending
supabase db push
```
`db push` applies every pending migration — eyeball the list first (the earlier
sleep/HRV and stress-load migrations may still be pending from before).

### 2 · Terminal — deploy the timeline function
```bash
supabase functions deploy trends-timeline
```
Order doesn't matter here: if you deploy before pushing, the function degrades to no
decoration (the column simply isn't selected yet) — it can't 500.

### 3 · Xcode — verify the Swift (2 min)
Open the project → **⌘B**. Run the app → Today → tap a mood. Then:
- The pill should show **CHECKED IN** and stay selected.
- Confirm the row landed:
  ```sql
  select date, mood, sleep_quality from daily_checkins order by date desc limit 3;
  ```
  You should see today's date with your mood lowercased.

### 4 · See it feed the score
Trends → Recovery Score. On a day with no logged run, the Mood factor now reads your tap
("POSITIVE · 1 day in 7") instead of "nothing logged in 7 days." Tapping again overwrites
the same row (upsert on `user_id,date`).

## One decision flagged for you
On a day that has **both** a voice-logged run mood and a one-tap check-in, the **run mood
wins** (it's contemporaneous with the effort; the check-in fills gaps). That's the
conservative merge and matches how sleep decorates. If you'd rather the deliberate daily
tap always win, flip the precedence in `index.ts` — change `if (m && !d.mood)` to set
`d.mood = m` unconditionally. One line; I left it as fill-in on purpose.

## What this does not do
Doesn't backfill history — coverage improves from today forward. Doesn't touch the
felt-RPE loop (still 0 rows; separate work). The mood prompt still has no automated test
(it's UI + network, like the sleep prompt); step 3 is the manual verification, same as
sleep.
