# THE GOAL ELEMENT — section 04 of The Read

**Authored:** 2026-08-24
**For:** an agent working in `my-running-app`
**Companions:** `WEEKLY-READ-APPLY.md` (§1 section map, §3(2) data honesty, §4 schema),
`BUILD-THE-READ.md` (phases and gates), `ASK-REGISTRY.md` (analyzer specs),
`the-weekly-read-prototype.html` (§04 markup, lines 328–352)

This document specs one section: **04 · Against the goal.** It covers what the
section may know, how it resolves the goal, how the framing changes as the race
approaches, what it says when it can't speak, and the order to build it in.

Scope decision taken before writing: **a race with a date anchors the section
even with no time target.** A time target upgrades it. See §3.

---

## 0 · The decision this document exists to force

Three artifacts in this repo disagree about the single most load-bearing number
in this section — the projected finish.

| Artifact | What it says |
|---|---|
| `prompts/daily-read.v5.ts:137` | *"PREDICTIONS (highest-priority correctness rule): ONLY as a range with confidence… NEVER a single time… A bare seconds-precision finish time is a hard failure."* |
| `analyzers/raceProjection.ts` header | The range **was tried and reverted on 2026-07-18**. A confidence-scaled band read as *too wide and inaccurate*, and a marathon window whose fast end beat the athlete's own PR was worse than one honest estimate. It now ships **point + confidence tier + lifetime PR**, rounded to the whole minute for half and marathon. |
| `the-weekly-read-prototype.html:335,347,559` | Renders `3:19–3:24` — a range — and a provenance sheet whose subtitle is *"A range, not a time."* |

**This is not a style disagreement. It is a build blocker.** The report's safety
model is `validateNarration()`: the model may speak only numbers present in
`facts[]`. `race_projection` does not emit a range, so **the prototype's lead
paragraph cannot be narrated today.** Something has to change before Phase D.

### The resolution this document recommends

**Ship the analyzer's shape. Update the rail. Fix the prototype.**

The v5 rail's actual target is *false precision* — "3:21:30". `race_projection`
already defeats that: `roundsToMinute()` rounds half and marathon to the whole
minute, so the point estimate is "3:21", and hard rule #7 makes it travel with a
confidence tier and the athlete's real PR. That is a stronger honesty guarantee
than a band, because a band invites the athlete to read its fast end as a
promise — which is the failure the 2026-07-18 revert recorded.

So, three changes:

1. `prompts/weekly-read.v6.ts` states the position directly instead of
   inheriting the v5 sentence: *a projected finish may be shown at the precision
   the analyzer emits, only as a `facts[]` value, only alongside its confidence
   tier and the lifetime PR. Prose may not restate it as a prediction.*
2. **Prose never speaks the projected finish as a future event.** It speaks the
   **gap** and the **PR relation**. See rail 1 in §5.
3. The prototype's `3:19–3:24` and its "A range, not a time" sheet are replaced
   with the point + tier + PR trio. A prototype that shows a number no analyzer
   emits is exactly the failure `WEEK-TAB-APPLY.md §0` was written after.

**If that trade is wrong, stop here.** Everything below assumes it. The
alternative — put the range back into `fitness_prediction`'s consumers — is a
larger change than this section and reopens a decision that was already made
with evidence.

### Inherited and non-negotiable

From `WEEK-TAB-APPLY.md §0`:

1. **If a value cannot be derived from the athlete's own rows, do not produce it.**
2. **Never attach provenance to a number you invented.**

---

## 1 · What the section is

Four questions, in this order:

| | Question | Why it's here |
|---|---|---|
| 1 | What is the goal, in the athlete's own words? | It is their frame. The structured time is an internal handle — `20260620210000` says so in the column comment. |
| 2 | Where is the fitness against it? | The gap, the confidence, the PR it would have to beat. |
| 3 | Is the training becoming specific to it? | The share of running at goal pace, and which way that share is moving. |
| 4 | What does the remaining time change? | Not urgency. What a week *this far out* is for. See §5 rail 2. |

**What the section is not.** It is not a verdict on whether the athlete will hit
the goal, and it is not a weekly grade. The name "Against the goal" invites both.
§5 rail 3 exists to stop it.

---

## 2 · Goal resolution — one resolver, and there are three today

Three implementations of "what is this athlete's goal" are live right now, and
two of them can be reached inside this one section:

| Where | How it resolves | Problem |
|---|---|---|
| `athlete-state.ts:1889` | Regex `distancePatterns` over `goal_title`, then a time regex | This is the parser `interpret-goal/index.ts` says in its header it **replaces**. Its own comment records the bug it shipped: `/\bmarathon\b/` matches inside "half marathon", so every half goal was filed as a marathon until the order was flipped. |
| `raceProjection.ts:136–162` | `user_goals` structured columns → `athlete_state` fallback | No title fallback, no unconfirmed handling |
| `racePaceSpecificity.ts:87` `resolveGoal()` | `user_goals` structured → `athlete_state` → narrow title parse, and returns `sawUnparsedGoal` | The best of the three, and private to one file |

The section renders facts from both analyzers side by side. **Two resolvers can
disagree inside one section** — `race_projection` finds no structured goal and
falls back to a plan-derived marathon while `race_pace_specificity` parses "sub
1:25 at Austin" off the title and computes a half pace. Both facts render. Both
carry provenance. They describe different races.

### The spec

**Extract one resolver into `_shared/analyzers/goal.ts`.** Take
`racePaceSpecificity.resolveGoal()` as the base — it already has the right
tiering and the right `sawUnparsedGoal` behaviour — and widen its return:

```ts
export interface ResolvedGoal {
  raceKey: string;            // "marathon" | "half" | free text as stored
  distanceMiles: number|null; // null when the distance isn't derivable
  seconds: number | null;     // NULL is legal — anchor mode, see §3
  targetDate: string | null;  // user_goals.target_date
  rawStatement: string|null;  // verbatim; quote, never coerce
  framing: string | null;     // interpretation.framing — "sub-3", "BQ"
  namedRace: { name: string; date: string|null; raceIntelId: string|null } | null;
  confirmed: boolean;         // user_goals.athlete_confirmed
  from: "confirmed" | "structured" | "plan_state" | "title";
}
```

**Tiering, most to least trustworthy:**

| Tier | Source | Treatment |
|---|---|---|
| 1 | `user_goals` active **and** `athlete_confirmed = true` | Settled. Prose may speak it plainly. |
| 2 | `user_goals` active, structured columns, **not** confirmed | Renders, but `coverage.missing` carries *"this goal hasn't been confirmed yet"* and the CTA is `confirm_goal`. Prose may not treat it as settled (§5 rail 4). |
| 3 | `athlete_state.goal_race` + `goal_time_seconds` | Plan-derived only. Populated only when a training plan exists — which is why `raceProjection`'s comment calls the athlete-with-goal-but-no-plan "the common case". |
| 4 | Title parse | Last resort. Always declared: *"goal pace read from your goal's wording, not a confirmed goal time"* — the line `racePaceSpecificity` already writes. |
| — | Nothing parseable, but a goal row exists | `sawUnparsedGoal` empty state. Not a dark section — a one-tap fix. |

**Then delete the regex block in `athlete-state.ts:1889` and have `active_goals`
read from `goal.ts`.** Leaving it is how the two-resolver disagreement above
happens. `interpret-goal` is deployed (`supabase/functions/interpret-goal/`);
its Phase-1 column writes are best-effort and the migration is in
`20260620210000`, so the structured columns are real.

**Non-derivable distances are a first-class case.** `RACE_DISTANCE_MILES`
(`analyzers/athleteState.ts:145`) covers mile, 5K, 10K, 15K, 10-mile, half,
marathon. `target_race_distance` is deliberately **open free text** — the
migration comment names 50k, relays, backyard ultras. A goal of "sub-5 at the
Bandera 50k" resolves fine, has a date, has a raw statement, and has **no
`distanceMiles`, therefore no goal pace, therefore no specificity fact.** That
is anchor mode with a further reduction, not an error. It must never fall
through to a marathon.

---

## 3 · Three modes, one section

### Gap mode — distance, time, and a date

Everything renders. This is the prototype's state.

### Anchor mode — a race and a date, no time target

Rio's scope decision. What still reads honestly:

| Renders | Source |
|---|---|
| The goal in their words | `raw_statement` |
| Days out, and the phase it implies | `target_date` (§5 rail 2) |
| Projection at that distance + confidence tier + lifetime PR | `race_projection` — `pickRace()` already defaults to the goal race |
| Where the work at that distance's demands is trending | `zone_trend`, which picks the pace system the athlete has actually run |
| A CTA that turns anchor mode into gap mode | `{ label: "Add a target time", action: "open_goal" }` |

**Does not render:** goal pace, gap, miles-at-goal-pace, share. All four need a
goal time. `race_pace_specificity` returns its "no goal to measure against"
empty state and that is correct — do not paper over it.

**Explicitly rejected: measuring specificity against the *projected* pace.** It
is derivable, and it is near-circular — the projection is computed from the
training, so "what share of your training sits at the pace your training
predicts" mostly measures how consistent the athlete is, then dresses it as
race-specificity. It would also be the section's most confident-looking number
and its least meaningful one. Don't.

### Dark — no goal at all

One empty state, and it is arguably the most valuable thing on the page:

> **Against the goal · no goal set**
> There is no race or target on file, so there is nothing to measure the week
> against. Set one and this section becomes the most useful part of the Read.

(`the-weekly-read-prototype.html:719` — keep it verbatim.)

---

## 4 · The facts

`facts[]` is the section's entire evidence base. If it isn't here, prose can't
say it.

| Fact key | Label | Source | Status |
|---|---|---|---|
| `goal_statement` | the goal, verbatim | `user_goals.raw_statement` | **JOIN** — stored since `20260620210000`, surfaced nowhere |
| `days_out` | Days to *race* | `user_goals.target_date` | **JOIN** — see below |
| `projection` | Projection · Marathon | `race_projection` | WRAP |
| `confidence_tier` | Confidence tier | `race_projection` | WRAP |
| `lifetime_pr` | Lifetime PR · Marathon · 2025 | `race_projection`, `race_prs` view | WRAP |
| `goal_gap` | Goal · 3:16 | `race_projection` | WRAP — one tone change, §5 rail 3 |
| `pr_relation` | Goal vs your PR | `goal_gap` + `lifetime_pr` | **JOIN** — one subtraction, nothing does it |
| `goal_pace` | Goal pace · Marathon | `race_pace_specificity` | WRAP |
| `at_pace_miles` | Miles at goal pace · 56 days | `race_pace_specificity` | WRAP |
| `share` | Share of running at goal pace | `race_pace_specificity` (carries `delta` vs first half) | WRAP |
| `sessions` | Sessions with real work at it | `race_pace_specificity` | WRAP |

### `days_out` is currently smuggled through the wrong field

`raceProjection.ts:261–269` does this:

```ts
const goal = (state?.active_goals ?? []).find((g) => g?.days_until != null);
// …
windowDays: goal?.days_until != null ? Number(goal.days_until) : 0,
```

`Coverage.windowDays` means *the analysis window* in every other analyzer —
`race_pace_specificity` passes 56, `zone_trend` passes its lookback. Here it
carries a countdown. Any client that renders "last N days" under this card
prints the days-to-race. **Emit `days_out` as a `FactLine` and set
`windowDays` to the prediction's actual window.**

### `pr_relation` — the join worth making

`race_projection` already fetches the PR and already computes the gap. Nothing
states the relation between the goal and the PR, and it is the fact that tells
an athlete what kind of goal they set:

- Goal **inside** the PR by a lot → this is a personal-best attempt, and the
  section should read like one all block.
- Goal **outside** the PR → this is a return, or a different course, or a
  different distance. Very different week-to-week story.

One subtraction, and it changes the register of every sentence above it.
`time_is_official` must travel with it — a watch-time PR is systematically fast
(`raceProjection.ts:90–95`), and a goal measured against a fast PR reads as
harder than it is.

### Deliberately out of v1

**Race-day conditions against training conditions.** `race_intel.weather_data`
holds `avg_temp_f`, `avg_humidity_pct`, `avg_wind_mph` for the named race and is
linked to the goal by `race_intel.goal_id`; `heat_effect` emits `neutral_pace`
and `dew_point` for what the athlete has actually been running in. The join —
*"you've done this block at a 62°F dew point; Chicago's five-year average is
41"* — is the strongest idea available to this section and it is a **BUILD**.
Note it, and don't do it in v1. Same for the course: `course_data.key_hills`
exists and nothing reads it, and `BUILD-THE-READ.md` already records hills as
the one thing in the brief that is not close.

---

## 5 · The framing rails

These are the rules that decide what the section *means*, not what it prints.
They belong in `weekly-read.v6.ts` as the section-04 block, and the worked copy
in §6 is calibration for them.

### Rail 1 — the section reads the present, never the future

Every sentence must be true at the moment it is written.

| Allowed | Banned |
|---|---|
| "The gap is four seconds a mile." | "You'll run 3:15." |
| "That would be eleven minutes under your PR." | "You're on track for a PR." |
| "Six percent of the last four weeks has been at goal pace." | "Keep this up and the goal is yours." |
| "Confidence on that projection is MEDIUM — it's built on 14 sessions." | "It's looking good." |

This is what makes a projected finish survivable at all. The number is honest
because the **tense** is honest. A projection stated in the present ("your
training projects a 3:21 today") is a reading of the current state. The same
number in the future tense is a promise the product cannot keep, and it is the
fastest way to lose an athlete permanently — `raceProjection.ts` says exactly
that in its header, and it is right.

**Prose may not restate the projected finish at all.** It lives in `facts[]`
where the client renders it with its tier and its PR beside it. Prose speaks the
gap and the PR relation. This is stricter than it needs to be and the strictness
is the point: the one number an athlete will screenshot is the one number that
must never appear in a sentence the model wrote.

### Rail 2 — time-to-race changes the subject, not the confidence

Confidence comes from coverage — sessions, laps, tier. It never comes from the
calendar. What the calendar changes is **what the section is about**. One closed
enum, computed from `days_out`, handed to the prompt as a phase:

| Phase | Days out | What the section is about | What it must not do |
|---|---|---|---|
| `capacity` | 100+ | Is the engine growing. The projection and its direction lead; a low specificity share is **expected and should be said so**. | Push race-pace work. A base block that chases goal pace is the thing this phase exists to prevent. |
| `specificity` | 30–99 | Is the work becoming the race. The share and its direction lead. | Lead with the gap. At this range the gap moves because the work changed, not the other way round. |
| `readiness` | 8–29 | Has the work already been done. Reads backward across the block. | Imply anything can still be built. |
| `quiet` | 0–7 | Names the goal, the projection, the PR. Two sentences. Stops. | Anything else. A weekly report cannot improve a race that starts in four days, and a late "one thing" is where a training product does real harm. |
| `after` | ≤30 days past `target_date` | What happened. If a `race_results` row exists, say it. | **Infer a race from a fast run.** `20260420100000` records the no-race-inference constraint: `confirmed_races` is user-declared. Ask; never assume. |

`athlete_state.active_goals` already retains goals up to 30 days past their date
"so coach can reference goal pace and gap even if target date just slipped"
(`athlete-state.ts:1887–1888`) — the `after` phase is what that retention was for.

**The prompt gets the phase, never the raw day count**, so it cannot invent
urgency arithmetic ("only 47 days!"). The day count is a fact the client renders.

### Rail 3 — the goal is a reference frame, not a grade

The section's name invites a weekly verdict on whether the athlete is good
enough. That verdict is worthless (it is one week) and corrosive (it is most
wrong exactly when an athlete is doing the un-glamorous work that later makes
the goal possible).

Concretely: **no fact in this section may use `tone: "watch"` for being behind.**
`watch` is reserved for coverage problems — an unconfirmed goal, a title parse,
a watch-time PR, a thin window.

`raceProjection.ts:245` currently does the opposite:

```ts
tone: gap > 0 ? "watch" : "good",
```

Being four seconds a mile off goal pace nine weeks out is the ordinary condition
of an athlete mid-block, and this paints it as a warning. `analyzers/types.ts`
opens with *"Never 'bad'. Observation, not judgement."* and hard rule #2 forbids
severity assessment. **Change both arms to `neutral`.** The `delta` field already
carries `"outside"` / `"inside"`; direction without a colour verdict is the whole
posture. One line.

### Rail 4 — an unconfirmed goal is a draft

`user_goals.athlete_confirmed` exists and nothing enforces it. The migration is
explicit: *"an unverified parse never silently drives training — consistent with
'AI advises, never acts.'"*

So: an unconfirmed goal renders the section, and the prose says whose words it
is working from. *"Working from 'sub-3:16 at Chicago' as it was read out of your
goal — confirm it and the numbers below are settled."* Never a sentence that
sounds decided on top of a parse the athlete has never seen.

### Rail 5 — quote, don't paraphrase

`raw_statement` is stored verbatim precisely so it can be handed back. An
athlete who wrote *"stay healthy and finally break 3 at CIM"* said two things,
and the section is at its best when it repeats them rather than converting them
into "sub-3:00 marathon". The structured time is an internal handle; the framing
in `interpretation` is what the section speaks.

This is also where the goal element earns the rest of the Read: the constraint
half of a goal ("stay healthy") is the thread §03 is already tracking through
`niggle_timeline`. The two sections should not repeat each other — §04 quotes it
once as the frame and leaves the niggle work in §03.

### Rail 6 — the goal never sets a pace the athlete trains at

**The goal says what they are chasing. Fitness says what they can run today.
Training paces come from fitness.** An athlete can hold a goal they are not fit
for; that is the normal state of having a goal, and it must not turn into a
pace they are told to run.

This is already the repo's stated position. `_shared/paces.ts:359–363`:

> *"Race anchor takes priority — the athlete's actual race performance is a more
> trusted fitness signal than goal time or the per-distance pace cache, which
> can be derived from goal time (i.e., aspirational)."*

`subscribe-to-plan/index.ts:537` calls it the Q20 roadmap decision. **The rule
does not currently hold**, in two places:

1. `update-plan-goal/index.ts:212–238` upserts **all six reference paces** —
   `easy`, `marathon`, `half`, `10k`, `5k`, `mile` — from
   `derivePaceTableFromGoal(goal)`. An aspirational goal rewrites the athlete's
   *easy pace*.
2. The guard meant to outrank it, `pickAnchorRace(confirmedRaces)`, requires a
   **confirmed** race. `RACE-CONFIRM-ONBOARDING-APPLY.md §0` records a 0%
   confirmation rate.

### What production actually shows — checked 2026-08-24

| Query | Result |
|---|---|
| `pg_constraint` on `athlete_pace_profiles` `*_confidence` | Still `CHECK (… IN ('high','medium','low'))` — six of them |
| `athlete_pace_profiles` rows | **1**, all confidences `high` (snapshot-derived) |
| `user_goals` | 6 rows, 2 active, 1 with a target time, **0 confirmed**, **0 with `raw_statement`** |
| `training_plans` with `target_time_seconds` | **0** |

`update-plan-goal` writes `easy_pace_confidence: "athlete_goal"` into a column
constrained to `('high','medium','low')`. **That upsert cannot succeed.** In the
athlete-only path it returns `500 Failed to save athlete goal`; in the
plan-scoped path the error is swallowed by `console.warn`
(`update-plan-goal/index.ts:245–254`).

Two consequences:

- **The athlete-only goal-save path is broken.** It is the path
  `GoalAndPacesCard` and the onboarding sheet use — which is part of why the
  card was never mounted, and why `athlete_pace_profiles` has one row.
- **The aspirational-pace overwrite is currently prevented by a bug.** The one
  pace profile on file is fitness-derived, which is correct — by accident. The
  obvious fix for the 500 is to widen the CHECK constraint to admit
  `'athlete_goal'`, and **that single line would turn aspirational training
  paces on for every athlete at once.**

So: widen the constraint *and* demote the goal-derived ladder below the
fitness-derived one in the same change, or fix neither. `'athlete_goal'` is the
right value to store precisely because it lets every reader see the ladder is
aspirational — it just has to lose to a measured source rather than overwrite
one.

Also stale and worth fixing while in there: `build-pace-profile/index.ts:22–24`
says *"`user_goals` only has title/date — it doesn't store race distance or
target time."* Migration `20260620210000` added both.

---

## 5A · Reachability — what the size of the gap does to the section

Rail 6 has a direct consequence for §04: **a goal-pace specificity number only
means something when goal pace is a pace the athlete can train at.** For an
athlete forty seconds a mile away from goal pace, "6% of your miles at goal
pace" is not a specificity finding. It is arithmetic on a pace they cannot yet
run, and printing it weekly with a provenance sheet turns an ordinary gap into a
recurring verdict.

So the section carries a second dimension beside the phase (§5 rail 2):

| Band | Definition | What the section is about | What it must not do |
|---|---|---|---|
| `at_reach` | The gap sits inside the at-pace tolerance band | Goal pace **is** current race pace. The specificity share leads. | — |
| `stretch` | Outside the band, but within a zone of it | The projection is the training target; the goal is the horizon. Specificity still renders. | Imply more goal-pace work closes the gap. **Fitness closes it.** |
| `aspirational` | Goal pace lands in a different zone of the athlete's own ladder than their projected race pace | Capacity — is fitness moving toward it. States the gap once, plainly. | Render `race_pace_specificity` at all. |

**The `at_reach` boundary is derived, not chosen.** `race_pace_specificity`
counts a mile as at-pace within ±2% (`DEFAULT_TOLERANCE_PCT`,
`racePaceSpecificity.ts:45`). If the projection sits inside that band, every
mile at projected pace *already counts* as a mile at goal pace — the analyzer
cannot tell them apart, so neither should the prose.

**The `aspirational` boundary must be a zone boundary, not a percentage.** The
athlete's full ladder is already computed by `derivePaceTableFromGoal`; the test
is whether goal pace and projected race pace fall in different zones of it.
That is checkable against real accounts. **Do not ship a hand-picked percentage
here** — a made-up threshold deciding whether a section renders is the same
class of error as a made-up number inside it.

### The aspirational empty state

`race_pace_specificity` will return ~0% for an aspirational goal, correctly.
Suppressing it is not hiding anything — the truth is one sentence, and it does
not need a fact tile:

> **Not counting goal pace yet**
> Goal pace for sub-2:50 is around 6:29 a mile. Today's projection puts your
> marathon pace nearer 7:10, so there are no miles at goal pace to count. This
> picks up when the two are close enough to be the same work.

This extends rail 3. An aspirational goal is not a failure state, and it gets no
`watch` tone either — the reachability band is coverage information, not a
grade.

---

## 6 · Worked copy

Same athlete throughout: sub-3:16 marathon at Chicago, PR 3:28, projection 3:21
at MEDIUM confidence, 6% of the last four weeks at goal pace and rising.

**`capacity` — 140 days out**

> Sub-3:16 at Chicago is twelve minutes under the 3:28 you ran. Today the
> training projects a 3:21, on medium confidence and fourteen sessions.
> Almost none of the last four weeks has been at goal pace, which is what a
> block this far out should look like — the engine gets built first and the
> pace work goes on top of it later.

**`specificity` — 47 days out (this is the prototype's week)**

> Sub-3:16 needs 7:29 a mile for twenty-six of them, and that is twelve
> minutes under your PR. Six percent of the last four weeks has sat at that
> pace, up from two — and Sunday was the first long run to carry a real block
> of it. That share is the thing moving right now, not the mileage.

**`readiness` — 19 days out**

> The work for Chicago is done or it isn't. Across the block, 34 miles landed
> at goal pace across nine sessions, most of it in the last six weeks and most
> of it inside long runs. The gap to 7:29 is four seconds a mile, on medium
> confidence.

**`quiet` — 4 days out**

> Chicago on Sunday. Sub-3:16, against a 3:28 PR, with the training projecting
> a 3:21 today.

**`after` — 6 days past**

> Chicago was Sunday and there's no result on file yet. Add it and the goal
> closes out properly — and the next projection gets a real race to anchor on
> instead of training data.

**Anchor mode — race and date, no time**

> Chicago is 47 days out and there's no target time on it yet. The training
> projects a 3:21 at the marathon today, on medium confidence, against a 3:28
> PR. Put a time on the goal and this section can tell you how much of your
> running is actually at it.

**Unconfirmed goal**

> Working from "sub-3:16 at Chicago" as it was read out of your goal — confirm
> it and the numbers below are settled. On that reading, goal pace is 7:29 and
> six percent of the last four weeks has been at it.

**What none of these do:** predict, congratulate, assess whether the athlete is
"on track", or use the word *we*.

---

## 7 · Empty and dark states

All four exist in code or prototype already. Use them; do not write new ones.

| Condition | State |
|---|---|
| No goal row at all | `the-weekly-read-prototype.html:719`, verbatim |
| Goal exists, distance/time unparseable | `racePaceSpecificity.ts:200` `sawUnparsedGoal` — eyebrow *"Goal needs a distance and a time"*, CTA `confirm_goal` |
| Goal fine, no `fitness_prediction` yet | `raceProjection.ts` *"No projection yet"* |
| Goal fine, projection fine, no lap splits in the window | `racePaceSpecificity.ts` *"No lap data in this window"* — the specificity facts go dark, the projection facts stay |

The fourth is the case that proves per-section narration was the right
architecture (`BUILD-THE-READ.md §D2`): **half this section can go dark and the
other half still stands.** Facts render from two analyzers; prose narrates only
the ones present. Do not let a missing share take the gap down with it.

Hard rule #8: never an em-dash placeholder. Every one of these is real prose.

---

## 8 · Build order

Small, ordered, and each step is checkable.

| # | Step | Files | Gate |
|---|---|---|---|
| 1 | One resolver | new `_shared/analyzers/goal.ts`, lifted from `racePaceSpecificity.resolveGoal()` and widened per §2 | Fixture: the same goal row resolves identically through both analyzers |
| 2 | Point the callers at it | `raceProjection.ts`, `racePaceSpecificity.ts`, `athlete-state.ts:1889` (delete the regex block) | Fixture: a "half marathon" goal never resolves as `marathon` |
| 3 | Tone fix | `raceProjection.ts:245` → `neutral` both arms | Fixture asserts no `watch` on `goal_gap` |
| 4 | `days_out` as a fact | `raceProjection.ts:261–269`; restore `windowDays` to the real window | Fixture: `windowDays` is a window, `days_out` is a countdown |
| 5 | `pr_relation` | `raceProjection.ts`, using the PR it already fetches | Fixture with a known PR and a known goal asserts the exact delta and the `time_is_official` flag |
| 6 | Anchor mode | `goal.ts` (`seconds: null` legal), `raceProjection.ts`, section assembly | Fixture: goal with date and no time renders 4 facts and the add-a-time CTA, and `race_pace_specificity` returns its empty state |
| 7 | The phase enum | section assembly + `weekly-read.v6.ts` | Fixtures at 140 / 47 / 19 / 4 / −6 days produce the five phases |
| 8 | Narration block | `weekly-read.v6.ts` §04 | `validateNarration()` passes; `guard_tripped = false`; no projected finish appears in prose |
| 9 | Prototype correction | `the-weekly-read-prototype.html:335,347,559` | The rendered numbers all exist in `facts[]` |

Steps 1–5 are analyzer work with fixtures and no prompt involved. **G3 from
`BUILD-THE-READ.md` applies: every new fact needs a fixture asserting a known
correct number, not just an empty state.**

---

## 9 · Verify

| # | Check | Pass |
|---|---|---|
| 1 | An account with a half-marathon goal | Both analyzers say "Half". Never "Marathon" |
| 2 | An account with a goal but no training plan | The gap fact renders (this is the case tier 3 alone misses) |
| 3 | An account with an unconfirmed goal | Section renders, coverage says unconfirmed, prose hedges, CTA is confirm |
| 4 | An account with a 50k goal | Anchor mode. No goal pace, no invented distance, never filed as a marathon |
| 5 | An account with a race and no target time | Anchor mode with the add-a-time CTA |
| 6 | A goal 4 days out | Two sentences, no call, no "one thing" pointed at the race |
| 7 | A goal 6 days past with no result | Asks for the result. Does not infer one from a fast run |
| 8 | Every number in the rendered section | Present in `facts[]`. Tap-through names its rows |
| 9 | Prose across all phases | Contains no projected finish time and no future-tense claim |
| 10 | `SELECT count(*) FROM analysis_queries WHERE guard_tripped` for §04 calls | `0` |
| 11 | A brand-new account | The no-goal empty state. No invented numbers |
| 12 | Grep the section's prose for "we" | None (`design-system/README.md`) |

Cassettes for `_evals/cassettes/weekly-read/`, per `WEEKLY-READ-APPLY.md §4`:
one per phase, one anchor mode, one unconfirmed, one no-goal, one `COACHED_MODE`
(where §06's call is suppressed and this section must not smuggle one in).

---

## 10 · What this deliberately does not build

- **Race-day conditions vs training conditions.** §4. The best idea available
  here, and a BUILD.
- **Course-specific reading.** `race_intel.course_data.key_hills` is stored and
  read by nothing. Hills as a verdict is already scoped out in
  `BUILD-THE-READ.md`.
- **A projection range.** Reverted 2026-07-18 with a recorded reason. Reopening
  it is a separate decision, not a side effect of this section.
- **A plan proposal.** No `proposed_actions` exists anywhere in the repo. §04 is
  prose and facts. The one bounded training call per week lives in §06 and stays
  there.
- **Multiple simultaneous goals.** `user_goals` allows several active rows and
  the resolver takes the first that resolves. A goal picker is a real feature and
  it is not this one.
- **Process goals** ("run five days a week", "stay healthy"). The natural-language
  record supports them; almost none of them have facts behind them today. Rail 5
  quotes them; the section does not try to measure them.

---

## 11 · Open, and worth deciding before step 1

1. **§0's trade.** Point + tier + PR, prose speaks only the gap. Everything above
   assumes yes. If the answer is "put the range back", stop and re-scope.
2. **`quiet` at 7 days.** Seven is a guess. The right number is however long
   before a race the athlete stops being able to act on a report — probably
   10–14 for a marathon and 3–4 for a 5K. Distance-dependent thresholds are one
   line and are probably correct; a single number is simpler. Pick.
3. **Multiple active goals.** Today: first that resolves, silently. That is fine
   until an athlete has a spring marathon and a summer 5K on file at once, and
   then it is confusing rather than wrong. Decide whether v1 picks the nearest
   date, and say so in coverage either way.
4. **The reachability bands.** §5A gives `at_reach` a derived boundary and
   argues `aspirational` should be a zone boundary. Both need checking against
   real accounts before they gate whether a section renders.
5. **The CHECK constraint.** Widening it to admit `'athlete_goal'` and demoting
   the goal-derived ladder are one change, not two. Sequencing them apart turns
   aspirational paces on for everyone in between.
6. **`after` and the ask.** The section asking for a race result is the first
   time §04 requests input. §07 already owns capture. Does this go through §07's
   control, or does §04 get its own CTA? Two capture surfaces in one report is a
   design decision, not an implementation detail.
