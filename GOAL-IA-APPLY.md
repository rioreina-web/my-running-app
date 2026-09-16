# WHERE THE GOAL LIVES — APPLY

**Authored:** 2026-08-24
**Companion:** `GOAL-ELEMENT-APPLY.md` (§04 of The Read — the goal's weekly moment)
**Question:** the goal is behind the ☰ drawer. Where should it be instead?

**NOT COMPILED HERE** — no Xcode in this container. Nothing below is type-checked.

---

## 0 · The answer in one line

**The goal is not a screen. It is a line that rides every plate in the app — and
the component that prints that line was built, documented, and never wired up.**

Three things already exist for exactly this problem and none of them are
mounted. The work is wiring, not building.

---

## 1 · Where the goal lives today — four places, three stores

| Door | Surface | Writes to |
|---|---|---|
| ☰ → **01 Goals** (`ContentLibrarySidebar.swift:35`) | Full-screen cover, `GoalsView` | `user_goals` + `interpret-goal` — the natural-language record |
| Train tab → **"GOALS & TARGETS · OPTIONAL"** (`TrainingTabView.swift:655–695`) | A `DisclosureGroup`, **collapsed by default** | `EditGoalSheet` → `update-plan-goal` → `training_plans` + `athlete_pace_profiles` |
| Train tab ⋯ → Edit Goal (`TrainingPlanView.swift:257`) | Sheet | Same as above |
| Onboarding race confirm (`RACE-CONFIRM-ONBOARDING-APPLY.md`) | Sheet, first session | `race_results.confirmed_at` |

The Train tab's disclosure carries this copy, verbatim:

> *"Targets stay out of the way until you want them. The only place goal paces appear."*

That sentence is the problem stated as a feature. The section is labelled
**OPTIONAL** and starts collapsed, in an app whose weekly report has a section
called *Against the goal*.

**And the two main doors write different tables**, which is the deeper issue —
see §5.

---

## 2 · Three components built for this, none mounted

### `TrainingDateline.swift` — the goal countdown, ready to print

Pure, deterministic, injectable `now`, unit-testable, no I/O. Returns
`"CHICAGO −47D"`, or `"MARATHON −7W"` past 100 days, or **nil** when there is
no upcoming goal. Its header states the rule: *"A dateline is only printed when
it's true."*

`DesignSystem.swift:611` documents where it goes:

```
/// Usage: PlateStrip(surface: "LOG · v1 DIARY + CHARTS", fig: TrainingDateline.string(for: goal))
///
/// The trailing slot is the *training dateline* — a goal countdown when one
/// exists (e.g. "BERLIN −86D"), else nil → the slot renders nothing. It used
/// to be a fake figure number; pass `TrainingDateline.string(for:)`, never a
/// hardcoded "FIG. NN".
```

**No call site passes it.** Three still pass the thing the comment forbids:

| File | Passes |
|---|---|
| `App/TodayHomeView.swift:100` | `fig: "FIG. 18"` |
| `Analysis/TrainingAnalysisView.swift:66` | `fig: "FIG. 7"` |
| `Analysis/InjuryView.swift:31` | `fig: "FIG. 28"` |

The rest pass nothing, so the slot is empty. `PlateStrip` is described in `Post Run Drip Design System/README.md:220` as
*"the single most identifiable visual gesture"* of the product. Right now its most identifiable gesture ends in decoration pretending
to be information.

### `GoalAndPacesCard.swift` — defined, never instantiated

Its own header says why it exists:

> *"This card makes the goal a first-class, always-visible artifact… Until this
> card existed, the goal-time editor was buried in the toolbar ⋯ menu and only
> reachable when a plan was already active."*

`grep -rn "GoalAndPacesCard(" RunningLog/` returns **nothing**. The card that
was written to un-bury the goal is itself buried.

### `interpret-goal` — deployed, and the app barely uses what it produces

The function is live and writes `raw_statement`, `interpretation`,
`target_race_distance`, `target_time_seconds`, `athlete_confirmed`. `GoalsView`
calls it (`GoalsView.swift:509`). But `GoalsView.UserGoal` decodes only
`goal_title`, `target_date`, `status`, `created_at`, `updated_at` — **the
structured interpretation is written and then never read back into the UI.**

---

## 3 · The recommendation

### It does not get a tab

The bar is six wide — Log · Train · Trends · Week · Ask · Sheet.
`DripTabBar.swift:121` argues the cost already:

> *"Adding a sixth is possible but should still be argued for: the last two
> additions were both eventually spent replacing something."*

A goal is not a place you go. It is the frame the other five tabs are read
against. Giving it a tab would put it beside the surfaces it should be printed
*on*.

### It gets four positions instead, in this order of value

| # | Position | What it is | Cost |
|---|---|---|---|
| 1 | **The dateline** | `TrainingDateline` in every `PlateStrip` trailing slot. The countdown is on-screen on every plate in the app, in the design system's signature gesture. | Pass a value at ~6 call sites |
| 2 | **Tap the dateline** | The dateline becomes the door. Tappable → the goal. Visible everywhere *and* reachable everywhere, with no new tab and no new screen. | `PlateStrip` gains an optional `onFigTap` |
| 3 | **Top of Train** | Mount `GoalAndPacesCard`. Delete the collapsed "GOALS & TARGETS · OPTIONAL" disclosure and its copy. This is where goal *paces* belong, because every pace in the plan derives from that number. | Mount an existing view; remove a `DisclosureGroup` |
| 4 | **§04 of the Read** | The weekly moment — gap, specificity, phase. Plus the Read's eyebrow, which already carries the goal at report scale (`daily-read.v5.ts:109`: *"Chasing 3:16 · off your 3:28"*). | `GOAL-ELEMENT-APPLY.md` |

**Positions 1 and 2 are the whole answer to "I can't have it hidden."** 3 and 4
are depth. The ☰ entry stays as a secondary path — a drawer is a fine *second*
door, it is only a bad *only* door.

### Considered and not recommended, with reasons

**A `.goal` page in the home pager.** `HomePage` is a closed enum
(`.day` / `.cockpit` / `.gap`) and adding a case is the sanctioned extension —
`PAGED-HOME-APPLY.md §3` made it an enum precisely so new page shapes are
deliberate. It would work. It costs a swipe position on the app's
highest-traffic surface, and the dateline already puts the goal on that screen
without spending one. **Do this only if the dateline proves too small a
presence in use.** It stays cheap to add later.

**A goal banner on Log.** `RACE-CONFIRM-ONBOARDING-APPLY.md §1` already
reserves the Log-top card for race confirmation. Two persistent cards competing
at the top of Log is how a surface becomes a dashboard.

---

## 4 · What the dateline says, and the one rule it must keep

`TrainingDateline` already refuses to print when there is nothing true to print
— no goal, or a goal in the past, returns nil and the slot renders empty. Keep
that. A countdown that falls back to a block week or a fake figure is the
`WEEK-TAB-APPLY.md §0` failure in a two-word slot.

Two changes worth making to it:

1. **Race name over distance where one exists.** `raceLabel(from: goalTitle)`
   parses the distance out of the title. Once the goal resolver from
   `GOAL-ELEMENT-APPLY.md §2` is in, `interpretation.named_race.name` is
   available — `"CHICAGO −47D"` is a better dateline than `"MARATHON −47D"`,
   and it is the athlete's own word for it.
2. **Unconfirmed goals read as drafts.** A goal parsed but never confirmed by
   the athlete (`athlete_confirmed = false`) should not print a hard countdown
   as if it were settled. Either suppress it or mark it. Decide — §7.

---

## 5 · Step zero: the dateline cannot work until one store wins

`TrainingDateline.string(for:)` takes a `UserGoal` — the `user_goals` shape.
`GoalsView` writes there. **`EditGoalSheet` does not** — it goes through
`update-plan-goal`, which writes `training_plans` and mirrors to
`athlete_pace_profiles`.

So an athlete who sets their goal on the Train tab has a goal that is plainly
visible in the app, drives every pace in their plan, and **prints no dateline at
all**, because `user_goals` is empty. Wire the dateline before fixing this and
it will look broken for exactly the athletes who are furthest along.

**And step zero has a live bug under it.** `update-plan-goal` writes
`easy_pace_confidence: "athlete_goal"` into columns still constrained to
`('high','medium','low')` — verified against production 2026-08-24, constraints
unchanged, one `athlete_pace_profiles` row. **The athlete-only goal-save path
returns a 500**, which is the path `GoalAndPacesCard` and the onboarding sheet
use. Mounting the card (step 4) without fixing this ships a card whose save
fails. See `GOAL-ELEMENT-APPLY.md §5 rail 6` — the fix and the pace-precedence
change are one change, not two.

**The fix, and it is the same one `GOAL-ELEMENT-APPLY.md §2` specs for the
server:** `user_goals` is canonical. `update-plan-goal` writes through to it
(it already mirrors to `athlete_pace_profiles`; this is a third mirror in the
same function). Every reader — dateline, `GoalAndPacesCard`, both analyzers,
`athlete-state.ts` — resolves through one path.

Note the symmetry: **the UI has three doors because the data has three stores.**
Fixing the IA without fixing the store just moves the confusion somewhere more
visible.

---

## 6 · Build order

| # | Step | Files | Check |
|---|---|---|---|
| 0 | One canonical goal record **and the pace-precedence fix** | `update-plan-goal/index.ts` writes through to `user_goals`; CHECK constraint + goal-ladder demotion per `GOAL-ELEMENT-APPLY.md §5 rail 6`; server resolver per §2 | A goal set on Train appears in `user_goals`, saves without a 500, and does not overwrite a fitness-derived pace |
| 1 | Goal into scope where plates render | the soonest active goal, loaded once and shared | — |
| 2 | Dateline into every `PlateStrip` | ~6 call sites; **delete `"FIG. 18"`, `"FIG. 7"`, `"FIG. 28"`** | No hardcoded `FIG.` string survives in the repo |
| 3 | Dateline is tappable | `PlateStrip` gains `onFigTap`; opens the goal | One tap from any plate |
| 4 | Mount `GoalAndPacesCard` at the top of Train | `TrainingTabView.swift` | The card renders with a real goal |
| 5 | Retire the collapsed disclosure | `TrainingTabView.swift:655–706` — note **both** the populated label (`:683`) and the empty-state label (`:704`) say OPTIONAL | "OPTIONAL" is gone from the goal |
| 6 | `GoalsView` reads the structured record | add `raw_statement`, `interpretation`, `athlete_confirmed`, `target_*` to `UserGoal` | The screen shows what `interpret-goal` wrote |
| 7 | Race name in the dateline | `TrainingDateline.raceLabel` | `"CHICAGO −47D"`, not `"MARATHON −47D"` |

Steps 2–5 are wiring and deletion. Step 0 is the only real build, and it is
already scoped in the companion doc.

---

## 7 · Verify

| # | Check | Pass |
|---|---|---|
| 1 | Account with a goal set through ☰ → Goals | Dateline prints on every plate |
| 2 | Account with a goal set through Train | Same dateline. Same string |
| 3 | Account with no goal | Slot is empty. No "FIG. NN", no placeholder |
| 4 | Account whose goal is yesterday | Slot is empty (`TrainingDateline` returns nil for past dates) |
| 5 | Tap the dateline from Log, Train, Trends | Same destination each time |
| 6 | `grep -rn '"FIG\.' RunningLog/` | No matches |
| 7 | Goal ≥100 days out | Weeks, not a three-digit day count |
| 8 | Train tab | Goal card at the top. No collapsed "OPTIONAL" section |

---

## 8 · Open

1. **Unconfirmed goals in the dateline.** Print, suppress, or mark? A countdown
   is a strong claim to make from a parse the athlete has never seen.
2. **More than one active goal.** `user_goals` allows several. The dateline can
   only print one — nearest date is the obvious rule, and it should be a rule
   rather than an accident of query order.
3. **The `.goal` home page.** Deferred, not rejected. Revisit after the dateline
   has been in use for a couple of weeks.
4. **`GoalAndPacesCard` if step 4 is skipped.** Delete it. A component built to
   solve this problem, sitting unmounted, is how the problem stays solved on
   paper and unsolved in the app.
