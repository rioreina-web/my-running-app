# Trends v2 — the synthesis surface, spec

*2026-07-30 · the design behind `outputs/trends-v2-prototype-2026-07-30.html`. Tested against Maya (self-coached, 3:28:41 marathon PB from November anchoring a 3:16 goal, ~40 mpw base built to 53, journals mood + niggles).*

**Supersedes on presentation:** the twelve-chart Trends surface audited in `outputs/trends-chart-guide-2026-07-27.html`. That audit's verdict — *"the two charts that work are the two that say a sentence first and show a picture second"* — is the organising rule of this document.

**Companions:** `outputs/trends-catalog-2026-07-23.md` (the thirteen trends), `outputs/trends-metrics-spec-2026-07-10.md` (metric formulas), `docs/specs/recovery-trend-v2-2026-07-27.md` (the recovery + HRV evidence base — **authoritative for §5 and §6 below**), `docs/specs/trends-insights-plan-2026-07-23.md` (the `TrendsWeek` pipeline).

---

## 1. The one rule

**Every chart states its conclusion in a sentence before it draws a picture — and that sentence is computed from the same data as the picture.**

The first half of that is the Jul 27 audit's finding. The second half is the part that turned out to matter more in practice. While building this prototype, three hand-written headlines had to be thrown away because they contradicted the charts beneath them — *"volume climbed for eleven weeks with one real down week"* sat above a chart showing five down weeks. Prose written once and rendered forever will drift from the data behind it, silently, and nobody catches it because the sentence is the thing people read instead of the chart.

So: **the ledes are functions, not strings.** `timelineLede()`, `ladderLede()`, `recoveryVerdict()` and the metric-card headlines all derive from the window in view. They branch on the sign and size of the measured change, and they have a sentence for the case where nothing happened. A chart that can't reach a conclusion says so.

The corollaries:

- **No silent axis inversion.** The old grid flipped five of six tiles so "up" always meant "better", signalled only by a small ▲. Nothing on this screen is inverted. Pace is plotted as pace — the slowest value sits at the top, the line falls as you get faster, and the card says *"pace plotted as pace · the line sits lower when you're faster · no axis flips on this screen."*
- **Real calendar axes everywhere.** Never session-number spacing. A three-week injury gap is three weeks wide, including in the metric charts whose series are sparse.
- **Reference lines live inside the domain.** If the 5% drift line falls outside the data range, it isn't drawn, and the caption says *"5% sits outside this range"* rather than pointing at a line that isn't there.
- **No silent truncation.** When the ladder withholds a zone for thin data it names it: *"5K isn't shown — fewer than two weeks of that work in this window. Not missing, just not enough to draw a line through."*

---

## 2. Information architecture

One scroll, six sections, in the order Maya reads them.

| # | Section | Question it answers |
|---|---|---|
| 1 | **The verdict** | What's the one thing? (the 5-second view) |
| 2 | **The calendar** | What did the block actually look like — and on which days? |
| 3 | **Recovery · convergence** | Am I absorbing it? |
| 4 | **Overnight · HRV and resting HR** | What do the numbers say — and can they be read at all? |
| 5 | **The pace ladder** | Am I getting faster, and where? |
| 6 | **What the work is costing you** | HR at pace · drift · heat |
| 7 | **Key sessions** | Show me the actual runs |

Section 1 carries the time-scale switch. Sections 2–7 all re-read at the selected scale.

Bottom nav is the target 4-tab IA — `Log · Trends · Train · Coach`.

---

## 3. Time scale — near term to long term

A single segmented control, and it is the most load-bearing control on the screen.

| Scale | Window | Granularity | Figure |
|---|---|---|---|
| **Month** | 28 days | daily buckets | FIG. 01 |
| **Block** | 84 days (12 weeks) | daily buckets | FIG. 02 |
| **Season** | 371 days (53 weeks) | weekly buckets, race anchors drawn | FIG. 03 |

**The point of the switch is that the same metric honestly says different things at different windows, and the screen admits it.** Heart rate at easy pace reads *"hasn't moved across the window — inside the week-to-week noise on this measure. Nothing is proven here yet. Switch to Season to see whether it's moving underneath"* at Month, and *"152 → 141 bpm"* at Season. Long-run drift is flat over a month and clearly falling over a year.

This is the mechanism that stops a hot July from reading as failure, and it's cheaper and more honest than any smoothing.

**Every number on the screen is counted from the window in view** — the verdict chips (miles, key sessions, niggles, modal mood) are derived, so they cannot drift from the charts below them.

---

## 4. Section 2 — the calendar (the first chart)

The primary chart, and the app's actual differentiator: Strava and Garmin cannot triangulate against the athlete's own words.

**It is a calendar grid, not a time series.** That choice buys one thing a time axis structurally cannot show: **which day of the week.** Weekday rhythm is where a self-coached runner's habits live — Monday off, Tuesday quality, Sunday long — and it's where the most actionable co-occurrence hides. On the lane chart, "the mentions follow the long run" is invisible. On the calendar it's the first thing you see.

This **replaces** the four-lane shared-axis chart rather than joining it. Both drew the same numbers, and the Jul 27 audit's clearest finding was that two charts of the same values, one scroll apart, are worse than either alone.

### Encoding — adopted from `calendar-month-prototype.html`

The encoding is **not** mine. It's the one already tested in `calendar-month-prototype.html` and specified in `CALENDAR-2-MONTH-APPLY.md`. My first pass used fill-depth for volume and pace-zone colour for the session bar; both were wrong, and the existing prototype had already worked out why.

**A calendar cell is not a label — it's a bar-chart bar.** Height is the day's miles on a **fixed 0–20 scale**, so months compare. That makes every week row a seven-bar chart and the block a stack of them, read left to right like any other chart. Fill-depth relative to the window maximum — my first version — makes the same 8-mile day look different in a light month than in a heavy one. That's a quiet lie.

Four channels, each owning a different part of the cell so none compete for the same pixels:

| Channel | Where | How |
|---|---|---|
| **Volume** | bar height, bottom-anchored | fixed 0–20 mi scale |
| **Session type** | bar fill | coral = key session · dark warm grey = long run · light warm grey = easy |
| **Mood** | 3.5px strip, bottom edge, full width | **rest days carry it too** — mood is not a property of a run |
| **Niggle** | 2.5px bar, left edge | opacity by the athlete's own severity word |

Plus: date numeral top-left, small coral dot top-right on key-session days, coral inset ring on today.

**Bars are not coloured by pace zone.** Tested and rejected in the existing prototype: pace is a property of a segment, not of a day, and at bar width a ten-step ramp collapses into one wash that also destroys the long-run channel. Pace zones belong in the week view and the day sheet. One coral — intensity is the only thing that gets the accent.

**Niggles use deep rose, not coral**, which keeps coral to a single job on this surface. The left edge is deliberate: a top-right corner notch sits next to the *next* day's numeral and reads as belonging to it.

Severity renders as opacity derived from the **verbatim word** (`slight` → `noticeable`), never a number. `InjuryModels.swift` is explicit that the 1–10 score exists for sorting only and is never displayed.

### The week rail

An eighth column **inside** the grid, so a heavy week and the days that made it sit on one line. Per week: the total, a bar scaled against the window's biggest week, and a mood-average tick underneath. Partial weeks render dimmed and tagged `PART`.

### The lens

A row of chips under the grid — **Key · Long · Niggle · Energized · Positive · Neutral · Tired · Struggling**, each with its count. Tapping one dims every day that doesn't match. Also borrowed from the existing prototype, and it is the cheapest pattern-finding tool on the screen: the whole window collapses to just the thing you asked about, in place, without navigating anywhere.

The lens replaces the lede with its own derived read:

> **Small n — name them.** "*Niggle* — 2 of 28 days: JUL 7 (a key session) and JUL 19 (a long run)."

> **Weekday clustering.** "*Key* — 6 of 28 days. Most of them fall on a **Tuesday**."

> **Time clustering.** "*Struggling* — 6 of 28 days. They bunch in the **second half** of this window."

> **No shape.** "*Tired* — 11 of 28 days. They spread fairly evenly across the window."

Selecting a time scale clears the lens.

### Two grid modes

| Scale | Layout | Row |
|---|---|---|
| **Month** | weeks as rows, weekdays as columns | 62px — full bar, all four channels |
| **Block** | same grid, shorter rows | 48px — 13 week-charts stacked; the mood strip cooling down the block is visible in one glance |
| **Season** | transposed and dense: 53 weeks across, 7 weekdays down | ~5px — session-type fill and niggle edge only |

At Season the legend adapts and the card says what it dropped: *"A year at this size holds volume, session type and niggles. Bar height and mood need a bigger cell — they're on the Month and Block grids."* No silent truncation.

### Detection — the lede

Two derived sentences. The first is load-clustering, from `timelineLede()`:

> **Clustered.** "Every *right achilles* mention lands in your highest-mileage weeks — 51 and 53 miles. Nothing in the lighter ones. That shape is load-shaped; what it means is your call."

> **Not clustered.** "Your *right achilles* mentions don't track your mileage — they fall in weeks of 38 and 41 miles, none of them near your biggest. That's a real finding, and a reassuring one."

> **Mixed.** "3 of 4 *right achilles* mentions land in your bigger weeks (41, 49, 51 and 53 miles); the others don't. Too mixed to call a pattern either way."

> **Single / none.** "One mention in this window — *left calf*, on JUL 12. One isn't a pattern." · "No body mentions in this window. Volume, mood and load are still plotted together — the quiet stretch is worth seeing too."

**Rule:** a mention is clustered if its week ranks in the top third of the window by mileage. Fires on 2+ mentions of the same `body_area`.

The second sentence is **new, and only the calendar earns it** — weekday rhythm, from `weekdayLede()`:

> "All of them fall on a key session or the day after one."
> "Every one of them lands on a **Sunday**."
> "3 of 4 fall on a key session or the morning after."
> "They scatter across the week — no weekday rhythm to them."

**Rule:** a mention counts as session-linked if its own day is a key session, or the previous day was. Same evidential standard as the load rule — where mentions fell, never what they mean.

### The verbatim card

Below the calendar, the last three mentions in Maya's own words, dated and area-tagged, closing with: *"Mentions are surfaced verbatim and never interpreted. What they mean is your call."*

Detection, not diagnosis, applies doubly here. Both ledes report **co-occurrence and stop.** No mechanism, no severity, no body-part theory.

### What was dropped

The lane chart's **acute ÷ chronic lane went with it** — which partly resolves open question §9.1. Load now appears where `recovery-trend-v2` puts it: as a Tier-3 annotation row in the recovery card, stated as a plain comparison, and as the week totals down the calendar's right gutter. **Still outstanding:** those week totals are raw, with no 8-week trailing baseline to compare against, and the evidenced single-session spike detector isn't built.

## 5. Section 3 — recovery as convergence, not a score

**There is no recovery score, and there should never be one.** A 0–100 composite is precisely what the convergence rule exists to prevent, and `recovery-trend-v2` §4 additionally bans `recovered`, `ready` and `risk` from the copy, along with any numeric readiness figure.

Instead the card runs the rule and reports what it found. Signals are tiered by evidence weight — Tier 1 leads because the runner literature puts the predictive signal in cheap self-report, not in autonomic measures.

| Tier | Signal | Source | Role |
|---|---|---|---|
| **1** | Niggle burden | `body_mentions` | **Leads** — soreness elevated 1–2 wks pre-injury |
| **1** | Mood / fatigue | `training_logs.mood` | **Leads** — fatigue elevated 1 wk pre-injury |
| **1** | Self-reported sleep quality | *not captured* | **Leads** — the strongest single signal, and the app's biggest gap |
| **2** | Resting HR | `daily_biometrics.resting_hr` | Corroborates |
| **2** | HRV (lnRMSSD) | `daily_biometrics.hrv_rmssd` | Corroborates — **only paired with RHR** |
| **3** | Sleep duration | HealthKit | Annotation. Never agrees or disagrees |
| **3** | Load | `training_logs` | Annotation. Never agrees or disagrees |

### Agreement rules

| Signal | Agrees when |
|---|---|
| Niggles | 2+ mentions of the same `body_area` in the window |
| Mood | ≥45% of days logged `tired` or `struggling` |
| Resting HR | 7-night mean above baseline by >0.5 × own between-night SD |
| HRV | 7-night mean below baseline by >0.5 × own SD **and** RHR agreeing |

### States

| State | Condition | Copy |
|---|---|---|
| **A shape worth watching.** | ≥1 Tier 1 **and** ≥1 Tier 2 | *"Your own words moved and the overnight numbers moved with them — niggles and mood, alongside resting HR and HRV. Any one of those is noise. Together it's a shape worth watching, and what it means is yours."* |
| **Your own words are moving.** | ≥2 Tier 1, no Tier 2 | *"Niggles and mood are both pointing the same way. That's the side of this the evidence actually supports, and it doesn't need a watch to say so."* |
| **One thing is moving.** | exactly 1 Tier 1 | *"Only mood is moving. One signal on its own isn't a pattern — it stays in the list below so you can see it, and it doesn't reach further than that."* |
| **Numbers moved, your words didn't.** | Tier 2 only | *"The overnight numbers drifted this week, but nothing in your own words did. On its own that isn't a pattern — as likely a late night or a glass of wine as anything about training. Noted, not flagged."* |
| **No shape here.** | nothing agrees | *"Your load moved around this window and the recovery signals didn't track it either way. That's the boring answer, and it's the true one."* |

**Biometrics can never fire alone** — not as product taste, but because single-source biometric inference is unsupported.

**Agreement is carried by ink weight, never colour.** Coral stays on the state headline only; four coral "AGREES" labels in a stack would violate one-coral-per-cluster, and the existing head-to-head table already solves this correctly with bold ink.

### The gap row

Self-reported sleep quality renders as an explicit `gap`: *"not captured · one tap a night would add it."* It is the best-evidenced single signal in the runner literature and would be a cheaper, better input than the entire watch pipeline.

---

## 6. Section 4 — HRV status

**Not a status score. A quadrant.**

RMSSD is a non-monotonic function of vagal activity, and resting RMSSD rises toward *both* performance improvement and decrement. A rising HRV is compatible with adaptation and with overreaching. **HRV alone cannot be read.** HRV paired with resting HR can be, and only in one cell of nine.

### The 3×3

|  | **RHR falling** | **RHR flat** | **RHR rising** |
|---|---|---|---|
| **HRV falling** | Possible parasympathetic saturation — often accompanies genuine adaptation. **Quiet.** | Ambiguous. **Quiet.** | **The one interpretable cell.** Eligible for `active`. |
| **HRV flat** | Quiet | Quiet | Weak — quiet unless Tier 1 agrees strongly |
| **HRV rising** | Ambiguous by construction. **Quiet.** | Quiet | Likely artifact or illness. **Quiet.** |

**The grid is drawn on the card**, with eight cells visibly marked QUIET and one marked READ, captioned `ONE CELL OF NINE IS INTERPRETABLE`. The low yield is the feature — it's what stops the app doing what Garmin and Whoop do, which is ping people over single bad mornings in directions the literature doesn't support. Hiding it would be designing for the wrong product.

Copy for the two cells that matter most:

> **Interpretable.** "HRV down, resting HR up. The one combination this card is willing to read. Overnight, your heart rate sat a little higher while HRV sat a little lower — the direction that isn't ambiguous."

> **Saturation.** "HRV down, resting HR down too. HRV is down and your resting heart rate is down with it. In a block like this that combination usually means the opposite of tired — but it's genuinely ambiguous, so this card isn't going to guess."

### Gates — all enforced, none decorative

| Gate | Value | Why |
|---|---|---|
| Valid nights in the week | **≥5** | below this the weekly mean is unstable; the card shows *"Only 4 of the last 7 nights recorded"* |
| Aggregation | **weekly means only** | isolated single-day values run SMD −0.45 (ns, wrong sign) vs 0.81 for weekly averages. **A single night, however extreme, never changes status.** |
| Baseline window | the **28 days** before the current 7, needing **≥21 valid nights** in it | below this the card is dark, not guessing |
| Change threshold | **0.5 × her own between-night SD** | the smallest-worthwhile-change convention. Never an imported percentage — nocturnal CV runs about half morning CV, so morning-derived bands are systematically too wide |
| Confidence | `low` until ≥56 nights of baseline, then `medium`; `high` needs two cycles | reads as low in the copy, not just in a badge |

### Cycle phase — flag, never correct

Cycle phase is a **larger effect than training** on both measures. When ≥4 of the last 7 nights fall in the late-luteal window, the card renders an annotation and **suppresses Tier-2 escalation** — Tier 1 still speaks:

> *"This window of your cycle typically moves these numbers on its own, often more than training does. Reading the dip as fatigue would be premature — so nothing escalates from here this week."*

No per-phase correction is applied. No validated one exists, the phase label itself is frequently wrong, and subtracting a constant would be false precision on top of a bad label. Capture is opt-in health data; the card must work, degraded and honestly labelled, for users who decline.

### States before data exists

| State | Renders |
|---|---|
| **Dark** (no watch) | *"No overnight data yet. HRV and resting heart rate arrive once a watch is connected. When they do, they join the signals above — neither of them will ever raise something on its own."* Plus what it will need first. |
| **Gated** (nights or baseline short) | Names the specific shortfall and what fills it. |
| **Live** | Quadrant + conclusion + the two baseline bands behind a disclosure. |

The prototype carries a **demo toggle** in the section header to switch between dark and live. That control is prototype-only and does not ship.

### The disclosure

Both series against **her own** bands — half of her own between-night spread, explicitly *"not a published range"* — with the baseline depth, the nights recorded, and the confidence tier stated in prose.

---

## 7. Section 5 — the pace ladder

Rows for **Easy · MP · HMP · 5K**, on the blue depth ramp. Each row: current pace, change, sparkline, and **the volume that supports it** (miles and % of window), because a pace with 3% of the miles behind it is a different claim from one with 32%.

Paces are **neutral-equivalent** — what she'd have run cool, dry and flat. Raw paces sit slower through the summer, and the disclosure says so.

### Derived lede

| Case | Copy |
|---|---|
| All race paces down ≥2s | *"Every race pace came down together — MP, HMP and 5K. That's the shape of a block that's working."* |
| Some down, some not | *"MP and HMP came down. 5K didn't — and the miles behind that zone are thin enough that it may be sample size, not fitness."* |
| None down | *"No race pace moved in this window. Volume went somewhere; it hasn't shown up at the sharp end yet."* |

Easy is appended separately, because Easy behaving differently is the *point*:

- `|Δ| ≤ 6s` → *"Easy barely moved — that's discipline, not a plateau."*
- `Δ < −6s` → *"Easy crept 8s/mi faster too, which is worth a look: easy days drifting quick is how the sharp end goes flat."*

Closing note derives the aerobic share: *"82% of the miles behind these paces were easy, moderate or long. The base is carrying the sharp end, which is the arrangement you want."*

Zones with fewer than two weeks of data are withheld **and named**.

---

## 8. Section 6 — what the work is costing you

Three cards. Each gated, each branching on the sign of the change.

### 8a. HR at a fixed easy pace

Mean HR in the 8:45–9:15/mi band, heat-corrected, per week.

- `Δ ≥ 3 bpm` → *"Nine-minute miles cost you 152 bpm at the start of this window. They cost 141 now, once the heat is priced out. That's the aerobic base, measured without a race."*
- `Δ ≤ −3` → *"The same nine-minute miles are costing 4 more beats… Not a verdict on its own; look at it next to sleep and mood above."*
- `|Δ| < 3` → **"inside the week-to-week noise on this measure. Nothing is proven here yet."**

That third branch is the most important line on the screen. It is the difference between a tool that observes and a tool that manufactures signal.

Gate: <3 weeks of samples → empty state. Disclosure shows raw against corrected.

### 8b. Drift inside the long run

`(HR ÷ pace, second half) ÷ (first half) − 1` on continuous efforts. Gate: <4 efforts. Branches on falling / rising / flat. The 5% line draws only when it falls inside the data range.

Rep sessions render `not measured on reps` in the empty-state treatment — **never an em-dash** (hard rule #8).

### 8c. What the heat is taking

Seconds per mile charged by temp + dew point.

- Falling → *"…down from 29 at the worst of it. Same pace, same evening — you're acclimating."*
- At its own peak → *"…which is the steepest it has been in this window. Nothing here is about fitness — it's weather, and it's why the raw paces read flat."*

Drawn in ink, not coral: it's a pace measure, and coral is alert-only.

---

## 9. Open questions

1. **Load baseline — half-done.** The ACWR lane and its 0.8–1.3 band are **gone**, which settles the part of this that `recovery-trend-v2` §7.1 is unambiguous about: coupling produces r = 0.52 from arithmetic alone, random numbers reproduce the published association, the only RCT was null (RR 1.01), and the thresholds trace to an editorial carrying a correction disclosing excluded high-load data. What remains is the constructive half — week totals in the calendar gutter are currently raw. They should sit against an **8-week trailing baseline excluding the scored week**, stated as a plain comparison (*"this week: 340 load-minutes. Your 8-week average: 250"*), and the evidenced **single-session spike** detector (a run >100% longer than the longest in the prior 30 days, HRR 2.28) still needs building — on that evidence it's the one load signal that earns a card.
2. **Mood height encoding.** The mood lane plots the label's rank as height. Defensible, and the lane says `LABEL, NOT SCORE` — but it is the closest thing on the screen to treating mood as numeric, and mood is stored as TEXT deliberately. Alternative: drop the height encoding, use a colour band only.
3. **The niggle sentence.** It stops at co-occurrence and hands the meaning back. Worth reading aloud to confirm it sits on the right side of detection-not-diagnosis.
4. **Ladder withholding threshold.** Currently two weeks of data per zone. May be too low to be meaningful, or too high to be useful.
5. **Two calendars will exist.** This is the Trends calendar; `CALENDAR-BUILD-PLAN.md` slice 2 upgrades the Train tab's `TrainingCalendarSection` to the same encoding. They must share one cell renderer rather than drift — the build plan's own warning about two rollups disagreeing applies doubly to two calendars. Worth deciding whether Trends hosts a calendar at all, or links to Train's and keeps only the derived sentences.
6. **The rail's ACWR colour.** `CALENDAR-2-MONTH-APPLY.md` keys the week-rail bar off ACWR (coral above 1.12, grey below 0.85). It's dated one day after `recovery-trend-v2` §7.1 dismantled the ratio, so the two docs disagree. The rail currently draws neutral. One of them needs to give.
7. **Sleep quality capture.** A one-tap nightly rating is a Tier-1 signal the app doesn't have. Product decision, not a spec item — but it likely outranks the whole biometrics pipeline on value per unit of work.

---

## 10. Build sequence vs data readiness

| Surface | Data today | Ship |
|---|---|---|
| Verdict, derived chips | ✅ populated | **Now** |
| Calendar grid (miles · key sessions · niggles · mood) | ✅ populated | **Now** |
| Recovery, Tier 1 only (`quiet` + Tier-1 `active`) | ✅ populated | **Now** |
| Pace ladder + supporting volume | ✅ populated | **Now** |
| Heat cost | weather backfill pending | On backfill |
| HR at pace · drift | streams landing per run | As streams accumulate |
| Recovery Tier 2 · HRV quadrant | ❌ needs `daily_biometrics` + webhook branch | After branch + 28 nights |
| Cycle annotation | ❌ needs consented capture | With Tier 2 |

**The honest sequencing note:** Tier 1 needs no watch data at all. A recovery card built on Tier 1 alone could ship now, months before the biometrics mature — and on the evidence it would be carrying most of the signal anyway.

---

## 11. Engineering notes

- **Card contract unchanged:** `{ id, group, status: hidden|quiet|active, headline, body, evidence[], confidence }`. The view stays a dumb renderer.
- **Ledes are functions.** Detection and phrasing live together in TypeScript next to `weeklyAnalytics.ts`. No LLM in detection → unit tests only, no eval cassette. If card prose is later LLM-phrased, that prompt goes through the eval gate.
- **Copy lint** must run over rendered output, not source: `rest`, `ice`, `should`, `must`, `because`, `caused`, `stop running`, `recovered`, `ready`, `risk`, plus emoji and exclamation points. The prototype passes all six of its states.
- **Every gate declares itself in prose.** A hidden surface says what would fill it.
- **Date arithmetic must be calendar-field based, anchored at midday.** Adding 86,400,000 ms per day breaks across DST — it lands on 23:00 or 01:00 of an adjacent day and shifts `getDay()`, producing a "week" with no Sunday. This bug shipped in the first cut of the prototype and blanked the screen in `America/Chicago` while passing every test under UTC. **Worth auditing `_shared/dataAnalysis.ts` and `weeklyAnalytics.ts` for the same pattern** — weekly rollups and 7-day acute windows are exactly where it hides, and it would produce one wrong week twice a year that reads as a data glitch rather than a date bug.

---

## 12. What is synthetic in the prototype

53 weeks of seeded, deterministic data — identical on every load. Weekly mileage arc through two blocks with a November marathon (3:28:41) and an April half (1:36:20). Mood on the closed vocabulary, with `struggling` reserved for a low read **and** real load behind it. Five niggle mentions, three of them right-achilles in high-mileage weeks. Nocturnal HRV and resting HR are modelled so that **device error is larger than the training effect, and cycle phase larger than both** — a prototype that made HRV look clean would design the wrong product.

*— restraint as foundation, intensity as accent —*
