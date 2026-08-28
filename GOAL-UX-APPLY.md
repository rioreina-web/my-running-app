# THE GOAL AS A SECOND CLOCK — APPLY

**Authored:** 2026-08-24
**Question:** how do we build the goal to be a central part of the UI/UX?
**Companions:** `GOAL-ELEMENT-APPLY.md` (§04 of The Read), `GOAL-IA-APPLY.md` (placement + wiring)
**Prototype:** `goal-as-second-clock-prototype.html` — drag the days-out slider

**NOT COMPILED HERE** — no Xcode in this container.

---

## 0 · The model

The app keeps **calendar time**: today, this week, last 28 days, the rolling
four-week block. A goal introduces a **second axis** — time to the race — and
that axis is the one runners and coaches actually think in. Nobody plans around
"24 August". They plan around *"fifteen weeks out"*, *"the last big week"*,
*"three days to go"*.

**Making the goal central means printing that second clock wherever the first
clock already appears.** Not a tab. Not a card. A coordinate.

That gives one testable rule:

> **Anywhere the app prints a date, it may also print the race-relative
> position. Where there is no goal, it prints nothing.**

The rule degrades honestly by construction — no goal, no second clock, and the
app is exactly what it is today. `TrainingDateline` already implements it for
one slot, and its header states the principle: *"A dateline is only printed when
it's true."*

### What centrality must not become

Rio's constraint, and it governs everything below: **an athlete can hold a goal
they are not fit for.** That is the normal condition of having a goal, not an
error state.

| The goal is | The goal is not |
|---|---|
| **A compass** — which way the race is, and how far | A fuel gauge. No percent-ready, no progress bar, no readiness score |
| **A time axis** — "Week 9 of 15" beats "24 August" | A deadline that turns a bad week into a failure |
| **A frame** — it decides what a number *means* | A pace source. Fitness sets paces; the goal never does (`GOAL-ELEMENT-APPLY §5 rail 6`) |
| **Their words** — quoted back, not converted | A grade on whether they are good enough yet |

Orientation, not scoring. Every surface below has to stay true for an athlete
who will miss their goal by ten minutes, which is why none of them score
anything.

---

## 1 · The goal is already the app's most powerful single input — server-side

`computeDataDepth` (`athlete-state.ts:398`):

```ts
if (args.uniqueDayCount >= 21) return 3;
if (args.hasActiveGoal && args.workoutCount >= 1) return 3;
```

**A goal plus one run buys the same register as twenty-one training days.**
`data_depth` is the gate on how much the product is willing to say. The decision
that the goal is central has already been made in the state builder; the UI
never caught up.

(iOS reads `data_depth` only as a commented proxy in `TrendsDetailViews.swift`,
not directly. Worth closing separately.)

---

## 2 · Minute one — and it has never worked

Onboarding is four steps and step 3 is *"What are you training for?"* — the
right question in the right place. Then:

### It writes to columns that do not exist

`OnboardingView.swift:520–529` inserts `goal_type` and `target_time`. Checked
against production 2026-08-24: **`user_goals` has neither column.** The insert
fails. **Onboarding has never saved a goal, for anyone.**

That single fact explains the rest of the data:

| Production, 2026-08-24 | |
|---|---|
| `user_goals` rows | 6 — all created by hand in `GoalsView` |
| with `raw_statement` | **0** — `interpret-goal` has persisted an interpretation once, on the day its migration shipped |
| `athlete_confirmed` | **0** |
| `training_plans` with a goal time | **0** |
| `athlete_pace_profiles` rows | 1 |

### It never asks when the race is, then invents an answer

```swift
"target_date": ISO8601DateFormatter().string(from: Date().addingTimeInterval(86400 * 120))
```

A race date 120 days out, made up. `target_date` is `NOT NULL`, so something had
to go in the slot and this is what went in. **Without a real date there is no
second clock** — no countdown, no phase, no week-of-block. And a *fake* date is
worse than none, because every consumer downstream believes it. This is
`WEEK-TAB-APPLY.md §0` rule 1, violated in the first minute of the product.

### It only saves when a time was entered, and time is labelled OPTIONAL

`guard totalSeconds > 0 else { return }`. An athlete who taps MARATHON and skips
the picker — which the label invites — gets no goal at all.

### It throws away the sentence

The title is synthesized: `"Marathon Goal"`. But every real goal on file is a
sentence the athlete wrote:

> *"Run sub 2:20 at CIM"* · *"Run a sub 1:10 at Austin Half Marathon"* ·
> *"Get in shape for a sub 15 5k"* · *"Run up to 90 mpw"*

### The rebuild: one field

Replace the chip row and the time picker with **one text field and one
follow-up**.

```
eyebrow    A GOAL
headline   What are you training for?
sub        — in your own words. The app works out the rest and asks you to confirm. —
field      [ Run sub 2:20 at CIM                      ]
→ interpret-goal → race-intel → a confirm card
```

Why this is not a stylistic preference:

- **`interpret-goal` is deployed and this is its input.** It parses the time
  correctly (2:20 → 8400s, not 140s), extracts the framing the athlete speaks
  ("sub 2:20"), resolves the named race, and **triggers `race-intel` with the
  clean canonical name** — which returns the real date, the course and the
  five-year weather. The chip row destroys the race name, which is the key to
  all of it.
- **It handles goals the chips cannot.** "Run up to 90 mpw" has no distance and
  no time. Under the chips it is unrepresentable. As a sentence it is stored
  verbatim, quoted back, and simply carries no pace math.
- **The date stops being invented.** When `race-intel` resolves the race, the
  date comes with it. When it does not, that is the one follow-up question —
  asked, never guessed.
- **Confirmation becomes natural.** `athlete_confirmed` exists and nothing sets
  it. A parse the athlete reads and approves is the confirm step, and it is also
  the app's best first trust beat: it proves the product understood them in
  minute one.

**Time stays optional. The date does not.** Per the scope call in
`GOAL-ELEMENT-APPLY.md §3`, a race with a date anchors everything; a time
upgrades it to a gap.

---

## 3 · The four positions

Ordered by value. The prototype shows all four.

### 3.1 · The dateline — every plate

`TrainingDateline` into `PlateStrip`'s trailing slot, everywhere.
`DesignSystem.swift:611` already documents this as the slot's correct value;
three call sites still pass `"FIG. 18"` / `"FIG. 7"` / `"FIG. 28"`. Full wiring
in `GOAL-IA-APPLY.md §6`.

Make it **tappable** and it is also the goal's door from every screen — which is
the whole answer to "it can't be hidden in a drawer."

### 3.2 · The masthead — top of TODAY

The design system is explicitly editorial, and a newspaper's masthead is where
the paper says what it is. That is the goal's job.

```
CIM · sub-2:20                                          −104D
Training projects 2:24 today, medium confidence, against a 2:31 PR.
▪▪▪▪▪▫▫▫▫▫▫▫▫▫▫                     Week 5 of 15 · Race week
```

Three lines: the goal in their framing, the second clock, and one sentence of
where the fitness sits. The block bar is **position, not progress** — it says
where in the block this week falls, never how ready anyone is.

With no goal it collapses to a single line and a way in. Nothing is invented and
nothing below it changes.

**Not a separate page.** `HomePage` is a closed enum and adding a `.goal` case
is the sanctioned extension (`PAGED-HOME-APPLY.md §3`), but the pager runs
*backwards* in time from today and the goal is the only thing that looks
forward. As a masthead it sits above the axis instead of fighting it, and costs
no swipe position. Revisit if the masthead proves too small.

### 3.3 · Relative time inside the day

Once the second clock exists, individual days can be placed on it:

> *"The longest run of the block so far, and the first to carry marathon-pace
> work at the end."*

"Of the block" is only sayable because the block has a shape, and the block only
has a shape because the race defines its end. This is where the goal stops being
a badge and starts changing what the app *says* — and it costs no new UI, only a
comparison window bounded by the goal instead of by a rolling 28 days.

### 3.4 · The Read §04 — the weekly moment

Specced in `GOAL-ELEMENT-APPLY.md`. The phase enum there (`capacity` →
`specificity` → `readiness` → `quiet` → `after`) is the narrative expression of
this same second clock — which is why dragging the days-out slider in the
prototype changes what the section is *about* rather than what it *scores*.

---

## 4 · The lifecycle — nothing today can end a goal

Production: two goals are `status = 'active'` right now. One has a target date
of **3 April 2026**. Nothing retires it.

A goal that cannot finish is not central, it is furniture. Five states:

| State | What the app does |
|---|---|
| **Draft** | Parsed, not yet confirmed. The countdown reads as provisional; nothing settles on it (`GOAL-ELEMENT-APPLY §5 rail 4`) |
| **Live** | The second clock runs. Phase drives what §04 is about |
| **Race week** | The clock goes quiet. Names the goal and the projection, makes no calls |
| **Result** | Asks for the finish. **Never infers a race from a fast run** — `20260420100000` records the no-race-inference constraint |
| **Closed** | Archives, becomes the anchor for the next projection, and asks what's next |

**Closed → next is the loop that makes the app a training partner rather than a
tracker**, and it is also where a confirmed result finally enters
`pickAnchorRace()` and outranks the aspirational pace ladder
(`GOAL-ELEMENT-APPLY §5 rail 6`). The lifecycle and the pace-precedence fix are
the same mechanism seen from two ends.

---

## 5 · Build order

| # | Step | Why here |
|---|---|---|
| 1 | **Fix the onboarding insert** — `goal_type` / `target_time` → the real columns | One-line class of bug. Until it lands, no new account has a goal and nothing else in this doc can be observed |
| 2 | **One text field + `interpret-goal` + confirm** in onboarding step 3; ask the date when `race-intel` can't supply it; **delete the +120-day fake** | The second clock needs a real date. Everything downstream depends on this one value |
| 3 | **One canonical goal record** — `GOAL-IA-APPLY.md §5`, `GOAL-ELEMENT-APPLY.md §2` | Two stores means two answers to "when is the race" |
| 4 | **Dateline into every `PlateStrip`**, tappable; delete the three `"FIG. NN"` strings | The cheapest, highest-coverage position |
| 5 | **The masthead on TODAY** | The goal's home, at zero IA cost |
| 6 | **Goal lifecycle** — archive on date-pass, race-week quiet, result prompt, next-goal ask | Stops the app accumulating dead goals |
| 7 | **Read §04** — `GOAL-ELEMENT-APPLY.md §8` | The depth layer, and it needs 1–3 anyway |
| 8 | Relative time inside day and workout copy | Polish, and the most distinctive of the lot |

Steps 1 and 2 are the whole difference between a goal system that exists and one
that has never once run end to end.

---

## 6 · Verify

| # | Check | Pass |
|---|---|---|
| 1 | Complete onboarding with "Run sub 2:20 at CIM" | A `user_goals` row with `raw_statement`, `interpretation`, distance, time, **a real date**, `athlete_confirmed = true` |
| 2 | Complete onboarding naming a race with no time | Goal saves. Anchor mode. No time invented |
| 3 | Complete onboarding with "Run up to 90 mpw" | Saves verbatim. No distance, no pace math, no crash |
| 4 | Skip the goal step entirely | No row. No fake date. Masthead collapses, dateline empty |
| 5 | `select count(*) from user_goals where target_date > now() + interval '119 days' and target_date < now() + interval '121 days'` | No new cluster at exactly +120 |
| 6 | Any plate, any tab, goal set | Same countdown string. Tap → the goal |
| 7 | Any plate, no goal | Empty slot. `grep -rn '"FIG\.' RunningLog/` → nothing |
| 8 | Day the race passes | Goal leaves `active` within a day. Result prompt appears |
| 9 | An athlete 40s/mi off goal pace | No score, no progress bar, no percentage anywhere on screen |
| 10 | Drag through a full block | The app changes what it talks about, never how well it grades |

---

## 7 · Open

1. **Block length.** The masthead bar needs a start. Plan start date when a plan
   exists; otherwise the first logged week after the goal was set. Both are
   derivable — pick one and be consistent, because "Week 9 of 15" is a claim.
2. **More than one active goal.** Two are active today. The masthead prints one.
   Nearest date is the obvious rule and should be a rule, not query order.
3. **Goals with no race** ("90 mpw"). They get the masthead's top line and no
   clock. Is that enough, or do process goals eventually need their own reading?
   Deliberately unanswered here — see `GOAL-ELEMENT-APPLY §10`.
4. **The `.goal` home page.** Deferred in favour of the masthead. Cheap to add.
5. **`data_depth` in iOS.** The server already treats a goal as worth 21 days of
   training. iOS only approximates it in comments.
