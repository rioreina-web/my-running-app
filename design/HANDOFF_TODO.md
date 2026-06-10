# Handoff — Negative Splits redesign

This is the punch list for shipping everything done in our session.
Ordered by priority: do the verification first, then deploy, then the
backfill, then the deferred work.

## 1 — Verify the iOS build (do this first)

The biggest risk is that new files aren't in the Xcode target. If any
of these files are in the Project navigator but show in **grey/black**
(not blue), or aren't there at all, they're not in the build target.

Open `RunningLog/RunningLog.xcodeproj` in Xcode → in the Project
navigator left sidebar, confirm each of these exists AND has the
`RunningLog` target checked in the File Inspector (right sidebar):

- [ ] `App/CoachIntent.swift` (new)
- [ ] `App/TodayPlate18.swift` (new)
- [ ] `Training/DayDetailPlate22.swift` (new)
- [ ] `Training/TrainingDayExpanded.swift` (new)
- [ ] `Training/TrainingWeekExpanded.swift` (new)
- [ ] `Workouts/WorkoutDetailPlate23.swift` (new)
- [ ] `Analysis/InjuryPlate28.swift` (new)

For any that aren't there: right-click the parent folder in Xcode →
"Add Files to RunningLog…" → select the missing file → confirm the
`RunningLog` target checkbox is on → Add.

- [ ] Press ⌘B to build. **If it succeeds**, run on simulator (⌘R)
  and visually verify each redesigned screen.
- [ ] **If it fails with errors**, paste them — we'll fix in another
  pass.

## 2 — Verify each redesigned screen renders correctly

After a successful build, walk through these surfaces and confirm
the editorial design is visible. Any one of them showing the old
layout means that file wasn't in the target.

- [ ] **Today tab** — open the app. Should see `MONDAY · MAY 12, 2026`
  monospaced eyebrow → race countdown line → five-circle mood prompt
  → editorial rule → yesterday's journal entry → tomorrow's
  prescription → editorial rule → fitness chart → zone shifts →
  race predictions. NO "Good morning" greeting.
- [ ] **Plan tab → tap any scheduled workout day** — sheet shows
  `TUESDAY · PLAN` eyebrow → `May 5` Crimson Pro display →
  italic-serif "MP rhythm session · 11 mi" → two-slot DISTANCE +
  DURATION stat strip (NOT a 2×2 card grid with icons) → editorial
  rule → heat compensation → editorial rule → STRUCTURE eyebrow + step
  list → editorial rule → FROM YOUR COACH italic block (if notes set)
  → editorial rule → `Mark complete ↗` AMBER serif + mono text-link
  secondary actions.
- [ ] **Logs tab → tap a Strava-synced workout** — sheet shows
  `THURSDAY · LOG` eyebrow → `May 7` display → italic-serif
  "5.01 mi · 35:59 · Strava" → two-slot DISTANCE + DURATION strip →
  small mono row with AVG PACE / HR AVG / ELEV / CALORIES → editorial
  rules → PACE × HR / HEART RATE / SPLITS / ROUTE eyebrows above each
  section.
- [ ] **Training tab → tap a day cell in the 28-day grid** — AMBER
  ring on the tapped cell, expansion panel slides in below with date
  eyebrow + headline + meta line + IN CONTEXT comparison lines. Tap
  again → collapses.
- [ ] **Training tab → tap a weekly load bar** — full AMBER fill on
  that bar, expansion panel slides in with week range + headline +
  ZONE MIX + DAY BY DAY + KEY SESSION. Tap again → collapses.
- [ ] **Injuries** (settings menu or wherever it's reached) — header
  reads `TRACKING NOW · 2` → `Active aches` → italic-serif disclaimer.
  Each entry is editorial (NOT a rounded green-bar card). 4-stat
  strip with MENTIONS / AVG VOL / AVG LOAD / TREND — currently shows
  `—` for the first three, `—` for trend. Mono action links at
  bottom (View detail · Update · Mark resolved).

## 3 — Deploy the backend (ACWR rewrite)

These edge functions now use intensity-weighted ACWR instead of
miles-only. **Existing data uses the OLD weights until the recompute
script runs in step 4.** Until then, the metric will be in transition.

```bash
cd supabase

# Use your prod project ref:
supabase functions deploy weekly-coaching-report compute-workout-features coaching-agent --project-ref $PROD_REF
```

- [ ] Deploy `compute-workout-features` (new ZONE_WEIGHTS)
- [ ] Deploy `weekly-coaching-report` (new featuresByLogId joining)
- [ ] Deploy `coaching-agent` (`athlete-state.ts` bundled with it)
- [ ] Smoke test: hit the weekly report endpoint manually for one
  user, confirm the `metrics.acwr` value comes back without errors.

## 4 — Backfill historical workout_features

The new ZONE_WEIGHTS mean every existing `workout_features` row has
an `intensity_score` computed under the OLD weights. This script
forces a full recompute. **Idempotent — safe to re-run.**

```bash
PROJECT_REF=$PROD_REF \
SERVICE_ROLE_KEY=$SERVICE_ROLE_KEY \
./scripts/recompute-workout-features.sh
```

- [ ] (Optional safety) First run for just YOUR user:
  `USER_ID=auth0|<you> ./scripts/recompute-workout-features.sh` —
  inspect a few rows in Supabase to confirm load numbers look sensible
- [ ] Then run the full backfill (script discovers all users from
  `training_logs` and loops)
- [ ] Spot-check that an anchor session you can recognize lands at a
  reasonable load value — e.g. a 10mi MP session should be ~180-200
  weighted-min.

## 5 — Visual QA / iteration

After the build is green and backend is deployed:

- [ ] Check that ACWR shows on the Training tab in a believable range
  (0.8-1.5 for steady training, can spike higher for big weeks)
- [ ] Check that **LOAD** appears on:
  - Today tab — yesterday's journal entry meta line
  - Workout detail — secondary stats row
  - Training tab — day expansion meta line, week expansion meta line
- [ ] Compare the displayed LOAD numbers against your intuition.
  Tune `ZONE_WEIGHTS` in `compute-workout-features/index.ts` if any
  feel off. (Current: mile=10, 3K=8, 5K=6, 10K=4, HMP=3.5, MP=3,
  steady=2.1, moderate=1.4, easy=1.0, recovery=0.7)

## 6 — Deferred features (mockups exist, not yet in iOS)

These are designed but not yet wired. Pick any when ready:

- [ ] **Plate 29 — Injury detail with mention timeline.** Shows
  severity sparkline, every voice mention with workout context, at-risk
  patterns. Mockup in `design/trends_mockup_plate_29.png`. Needs
  backend table: `injury_mentions (id, injury_id, training_log_id,
  severity, quote, mentioned_at)` plus an LLM extraction step in
  `process-training-memo`.
- [ ] **Plates 19/20/21 — Training tab variants.** Three approaches
  to a fuller-data Training tab. Mockups in `design/trends_mockup_plate_19.png`,
  `_20.png`, `_21.png`. None picked yet.
- [ ] **Plates 24/25 — Workout detail variants.** Alternative chart
  treatments (intensity-foregrounded, vs-typical comparison). Not
  picked yet.

## 7 — Deferred backend tables (would make existing screens fully real)

These features show `—` or fall back to local-only storage until the
backend lands:

- [ ] **`daily_check_ins` table** — needed for the Today tab mood
  prompt to sync cross-device. Currently saves to `@AppStorage`.
  Schema: `(user_id, date, mood, energy, sleep_hours, notes)` with
  RLS + unique index on `(user_id, date)`. ~3 hr backend + 1 hr iOS.
- [ ] **`coach_intent` column on `scheduled_workouts`** — replaces
  the hardcoded fallback strings in `CoachIntent.swift`. Should be
  populated at plan-generation time by an LLM call that knows
  athlete context. ~1 hr backend.
- [ ] **`injury_mentions` table** — fills the `—` placeholders on
  Plate 28's stat strip (MENTIONS / AVG VOL / AVG LOAD / TREND) and
  enables Plate 29 (injury detail with mention timeline). ~2 hr
  backend + 1 hr iOS.

## 8 — Cleanup / housekeeping

- [ ] **Old `InjuryCard`, `MedicalDisclaimerBanner`, `SeverityDots`**
  in `InjuryView.swift` are no longer used by the active-injuries path
  (only the resolved-injuries section still calls them). Can be
  removed once you confirm the new layout works — or leave for the
  next pass.
- [ ] **`TrainingDashboardView.swift`** — the older training dashboard
  is still on disk; `TrainingTabView.swift` is the one MainTabView
  uses now. Can delete `TrainingDashboardView.swift` once you're sure
  nothing references it (`git grep TrainingDashboardView` should be
  empty).
- [ ] **Mockup PDF** (`design/trends_mockups.pdf`) has 31 plates now.
  Not all are still relevant — Plates 1-15 were early Trends-tab
  iterations. Worth a future pass to mark which plates are canonical
  vs. exploratory.

---

## Reference — what shipped, in one place

| Plate | Surface | iOS file(s) | Status |
|---|---|---|---|
| 18 | Today tab | `TodayHomeView.swift`, `TodayPlate18.swift`, `CoachIntent.swift` | Code shipped |
| 22 | Plan day detail | `DayDetailSheet.swift`, `DayDetailPlate22.swift` | Code shipped |
| 23 | Workout detail | `VitalWorkoutDetailView.swift`, `WorkoutDetailPlate23.swift` | Code shipped |
| 26 | Training day expansion | `TrainingTabView.swift`, `TrainingDayExpanded.swift` | Code shipped |
| 27 | Training week expansion | `TrainingTabView.swift`, `TrainingWeekExpanded.swift` | Code shipped |
| 28 | Injuries list | `InjuryView.swift`, `InjuryPlate28.swift` | Code shipped |
| ACWR | Backend math | `weeklyAnalytics.ts`, `athlete-state.ts`, `compute-workout-features.ts`, `weekly-coaching-report` | Source-shipped, NOT deployed |
| 29 | Injury detail | — | Mockup only |
| 19/20/21 | Training variants | — | Mockup only |
| 24/25 | Workout detail variants | — | Mockup only |

All mockup PNGs are in `design/`. Combined PDF at
`design/trends_mockups.pdf`.
