# Trends — audit and simplification

**Post Run Drip · 3 August 2026**
Scope: the shipped iOS Trends module, the four HTML explorations from 31 July, and the five design specs dated 3 July – 30 July.

---

## The short version

Trends is 3,912 lines of Swift across 26 files, and **47% of it can't be reached in a release build.** The live tab renders five sections that call out to eleven view types, five of which ignore the time range you picked. There is no 30-day view — the default is 12 weeks, and the only three choices are 4wk / 12wk / 6mo.

The five signals you want on the first screen already exist in the data. Four of them are solid. The fifth — recovery score — does not exist, and your own spec of record bans it in its strongest language. That conflict is the one real decision in this document, and it's resolved below.

The recommendation is **one screen, five lanes, one time axis** — not a calendar. The reasoning is in §5, and it comes down to one thing: a calendar can't survive the 1-year range, and a structure that only works at one range isn't a structure.

---

## 1. What's actually there

| | |
|---|---|
| Files in `RunningLog/Trends/` | 26 |
| Lines of Swift | 3,912 |
| Reachable only in a debug build, or not at all | **1,830 lines (47%)** |
| Sections on the live tab | 5, plus 4 sub-blocks |
| Distinct destinations a user can reach | 3 in release, 7 in debug |
| Time ranges offered | 3 (4 wk / 12 wk / 6 mo) |
| Default on open | **12 weeks** |

**The live tab, in render order:** `01 LOAD` (weekly miles + acute:chronic band) → `02 PACE` (every mile sorted by pace) → `02b THRESHOLD MILES` → `03 KEY SESSIONS` (a canvas dot grid) → `03b` week readout → `03c` key sessions list → `03d TWO SIDE BY SIDE` → `04 RECOVERY` → `04b HOW IT'S FELT` (mood) → `04c NIGGLES` → `05 RACE PREDICTION`.

That is eleven blocks. Your own July 11 review already called this out — *"~12 full-bleed chart sections — a punishing scroll where every chart shouts equally"* — and the count hasn't come down since.

**Three structural problems worth naming:**

**The tab has two personalities.** `TrendsV2View` is a complete parallel version of the whole surface, 537 lines, sitting behind `#if DEBUG`. It renders a calendar, three recovery cards, an efficiency chart, and a key-sessions list. It's not dead code — it compiles and works — it's just invisible to anyone who isn't you. Every hour spent on v1 and v2 in parallel is an hour spent twice.

**The time range is a suggestion, not a rule.** Six blocks honor the range you picked. Five don't: the key-sessions list reads the whole timeline, the head-to-head card reads the whole timeline, the recovery block reads fixed 28-day fields, race prediction takes no arguments at all, and the session grid only appears to be windowed — it drops out-of-range sessions because there's no column to put them in, not because anyone told it to. So the header says "4 WK" and half the screen is showing you something else.

**Three things are computed more than once, and two of them disagree.** Weekly miles get recalculated from daily data in three separate places plus a fourth on the server. UTC date parsing is implemented four times. And the load story is told twice, in contradiction: section 01 ships an acute:chronic ratio, while `TrendsRecoveryDayWeek.swift` opens with a comment saying *"NO acute:chronic ratio (that number was dismantled)"* and computes load-vs-your-own-baseline instead. Both ship, on different screens.

**Dead weight to delete:** `TrendInsightsService.swift` (128 lines, a complete API client with zero callers), and `TrendsEfficiencyView.swift` (175 lines that can only draw real output in preview mode — the one live call site passes `previewMode: false`, so it renders an empty state).

---

## 2. The five signals — where they live today

| Signal | Data exists? | Where it is | Verdict |
|---|---|---|---|
| **Mileage** | Yes, daily and weekly | `TrendsWeek.miles`, `TrendsDay.miles` | Ready. Nothing to build. |
| **Mood** | Yes, daily and weekly | `TrendsWeek.mood`, `TrendsDay.mood` — six-word vocabulary, `null` when not logged | Ready. The `null` handling is right and should be protected. |
| **Key workouts** | Yes — the richest model in the module | `KeySession`: zone, work pace, heat category, HR, structure, quality load | Ready, but **"key workout" is never actually defined in writing.** Pin it down before build. |
| **Niggles** | Yes, but the live tab uses the weak version | Weekly: labels only. Daily: area + severity word + **verbatim quote** | Ready. Switch the tab to the daily model — the quotes are the whole point and they're currently unreachable. |
| **Recovery score** | **No.** | No numeric recovery value exists anywhere in the module | See §3. |

Four of five need no new data at all. That is the good news, and it's the reason this can ship soon.

---

## 3. The recovery score conflict — and the resolution

Your `trends-v2-spec` (30 July) says:

> **"There is no recovery score, and there should never be one."**

Your `daily-score-mock.html` (31 July — one day later) has a 0–100 score. And you've now asked for one on the first view.

Reading the spec carefully, the objection isn't to *a number*. It's to **an opaque number** — a composite that arrives with authority and no accounting, which is exactly what Whoop and Garmin ship. The spec's own words: a 0–100 composite is *"precisely what the convergence rule exists to prevent."* The convergence rule is about **showing your work** — never letting one signal speak alone.

So: **keep the score, and make it show its arithmetic.** Every score on the screen is a receipt.

```
Starts at 50
  Mood            POSITIVE · logged                    +6
  Yesterday       8.1 mi long                          −3
  Body mentions   none in 14 days                       0
  Load            in line with your 8-wk average       +4
  Days on         day off today                         0
                                                    ————
                                                       57  WORN
```

This satisfies the spec's real objection: no signal fires alone, every line carries the evidence it moved on, and a skeptical user can audit the number in four seconds. It's the `daily-score-mock` pattern, which was your most recent thinking anyway.

**Three changes I made to that pattern:**

1. **Dropped the acute:chronic ratio.** Your `recovery-trend-v2` dismantled it thoroughly — coupling produces r = 0.52 from arithmetic alone, the only RCT was null. But three of the four mocks still plot its 0.8–1.3 band. Replaced with load measured against **your own 8-week average**, which is what the same document recommends.
2. **Renamed the bands.** `READY` and `FRESH` are both on your copy-lint ban list. Now: **FLAT · WORN · STEADY · CLEAR** — `CLEAR` reuses the vocabulary already in `RecoveryDayModel`.
3. **Four of five inputs are the athlete's own words.** No watch data required. This ships today, and per your own sequencing note, Tier 1 alone *"would be carrying most of the signal anyway."*

**One caveat you should see, because the ledger makes it visible:** in the mock, today's score moved **+23 points overnight** — because yesterday was a long run and today is a day off, and mood ticked up at the same time. That's a real swing for a number people will read as a status. The ledger is what surfaced it; a plain number would have hidden it. Before ship, either damp the day-to-day inputs or display a 3-day average as the headline with today's raw score underneath. **This is the one number I'd want to tune with real data before beta.**

---

## 4. What to cut

| Cut | Lines | Why |
|---|---|---|
| `TrendInsightsService.swift` | 128 | Complete API client, zero callers |
| `TrendsEfficiencyView.swift` | 175 | Only renders in preview mode; live path shows an empty state |
| Acute:chronic ratio in section 01 | — | Dismantled by your own research; contradicts another shipped screen |
| Race prediction (from Trends) | — | Takes no arguments, ignores the range, answers a different question. It's a destination, not a trend. |
| One of the two grid renderers | ~400 | `TrendsSessionGrid` and `TrendsCalendarView` both answer "which weekday does the work land on" and share no code |
| The duplicated pace-bands row | ~50 | Copy-pasted between v1 and v2, and the two show **different numbers** from the same data |
| Head-to-head card | — | Genuinely useful — but it's a workout-comparison tool, not a trend. Move it to the workout detail screen. |

**Consolidate rather than cut:** four separate views read the same `keySessions` array and each re-derives its own zone colors and sort order — two of them use *different* color maps. One key-session component, used everywhere.

**Decide, don't defer:** two calendars will exist (Trends and Train). Your spec already flags this. Either they share one cell renderer or Trends links to Train's and keeps only the derived sentences. Picking now is cheaper than picking later.

---

## 5. The recommended structure — and why lanes, not a calendar

Your 30 July spec chose a calendar grid over the aligned-lane chart, and the argument was good: a calendar shows **which day of the week**, and weekday rhythm is where a self-coached runner's habits live.

**I'm recommending you go back to lanes, for one reason: the range switcher you just asked for.**

A calendar cell has to be at least ~45px to hold four channels. At 30 days that's five rows — fine. At 3 months it's thirteen rows — a long scroll, but workable. At **1 year it's impossible**, and your own spec admits it: at Season scale the cells drop to ~5px and the card has to announce *"bar height and mood need a bigger cell — they're on the Month and Block grids."* That's the calendar telling you it only works at two of your five ranges.

Lanes degrade gracefully instead. The same five rows read identically at 30 daily columns and at 53 weekly ones — only the bucket changes, and the screen says so. **One structure that survives every range is worth more than the best structure for one range**, especially for a beta you intend to build on.

What the lanes fix, versus your July 31 aligned-lanes mock:

- **Every lane is its own row now**, with a label on the left and its current value on the right. In the old mock the mood lane was 16px and the niggle lane was 6px — decorative, not readable. Now each lane reads as a table row *and* shares the x-axis, so you get both the scan and the read-across.
- **Mood is colour only, never height.** Your spec listed this as an open question — *"the closest thing on the screen to treating mood as numeric, and mood is stored as TEXT deliberately."* Resolved in the safe direction.
- **Mood coverage is counted in days, never buckets.** At the 1-year view a week with one check-in out of seven would otherwise read as "logged." The header says `323/365 DAYS LOGGED`.
- **At weekly grain, bars stop being coloured by session type.** Nearly every week contains a key session, so type-colouring washes the whole lane coral and says nothing. Weeks render neutral and the KEY WORK lane carries the count.
- **The acute:chronic lane is gone**, replaced by the recovery lane — five lanes, five signals, exactly what you asked for.

### The screen, top to bottom

```
TRENDS · 30-DAY VIEW
[ 30 D ][ 3 MO ][ 6 MO ][ 1 YR ][ CUSTOM ]     ← 30 D is the default

THE READ · JUL 5 – AUG 3
"Load eased off. You held level."               ← computed, never hand-written
Recovery moved +1.7 points — inside the week-to-week noise
on this measure. Nothing is proven here yet.

[ 112 MI ][ 7 KEY ][ NEUTRAL ][ 2 NIGGLES ][ 57 WORN ]
Every number counted from the window in view

01 · FIVE SIGNALS      ← mileage / key work / recovery / mood / niggles
                         one time axis, tap-and-drag to read across a day

02 · RECOVERY SCORE    ← the number, showing its arithmetic

03 · WHAT LINES UP     ← computed findings, small-n honest
```

**Range behaviour, and it announces itself:**

| Range | Buckets | What the screen says |
|---|---|---|
| **30 D** (default) | 30 daily | gridlines mark Mondays |
| 3 MO | 91 daily | same |
| 6 MO | 27 weekly | *"mood shows the week's most-logged label — day-level detail needs the 30-day or 3-month view"* |
| 1 YR | 53 weekly | same |
| Custom | daily ≤120 days, else weekly | same rule, stated |

No silent truncation. When the screen drops detail, it says which detail and where to find it.

### Three rules carried over from your specs, and kept

**Every headline is a function, not a string.** You already learned this the hard way — three hand-written headlines had to be thrown out because they contradicted the charts beneath them. In the mock, the headline, the noise line, the chips, and all three findings are computed from the same array the chart draws.

**The noise guard.** When recovery moves less than 3 points across the window, the screen says: *"inside the week-to-week noise on this measure. Nothing is proven here yet."* Your spec calls this the most important line on the screen and I agree — it's the difference between a tool that observes and a tool that manufactures signal. It fires at the 30-day, 3-month and 1-year ranges in the mock.

**Small n gets named, not inflated.** With two body mentions in 30 days the screen reads *"2 of 30 days — Jul 5 (a long run), Jul 14 (a key session). Too few to call a pattern."* With nine over six months it will say whether they cluster on key sessions or not — and *"your niggles aren't following the hard days"* is treated as a real finding, not an empty state.

---

## 6. Before you build

**Define "key workout" in writing.** It's the only one of your five signals with no written definition anywhere. The nearest basis in your docs is the zone weight table — which implies `key = contains meaningful time at marathon pace or faster`, plus a floor (the code uses 25 weighted minutes). Write it down, because four different views currently infer it independently.

**Tune the score's day-to-day volatility.** The +23 overnight swing described in §3.

**Decide who owns the calendar** — Trends or Train. One cell renderer, or a link.

**Consider adding self-reported sleep quality.** Your own catalog calls it *"the strongest single signal, and the app's biggest gap"* and notes *"one tap a night would add it"* and that *"it likely outranks the whole biometrics pipeline on value per unit of work."* It's a sixth ledger line and a one-tap input — the cheapest quality upgrade available to you.

**A note on the date bug.** Your spec flags that day arithmetic must be calendar-field based, not `+86400000` milliseconds — that bug shipped once and blanked the screen in `America/Chicago` while passing every test under UTC. The mock uses calendar-field arithmetic anchored at midday throughout. Worth auditing `_shared/dataAnalysis.ts` and `weeklyAnalytics.ts` for the same pattern.

---

## 7. Sequencing

| | Needs | When |
|---|---|---|
| Five-lane chart, 30-day default | Nothing new | **Now** |
| Verdict chips, computed headline | Nothing new | **Now** |
| Recovery score ledger, Tier 1 only | Nothing new | **Now** |
| Range switcher incl. custom | Nothing new | **Now** |
| Niggle quotes on the tab | Switch to the daily model | **Now** — a small change |
| Sleep quality as a ledger line | One-tap nightly input | Next |
| HRV / resting HR corroboration | `daily_biometrics` + 28 nights | Later, and per your own research it adds less than the above |

Everything in the first block runs on data you already have.

---

*Files reviewed: 14 Swift files in `RunningLog/RunningLog/Trends/`; `trends-v2-spec-2026-07-30.md`; `trends-catalog-2026-07-23.md`; `trends-metrics-spec-2026-07-10.md`; `longitudinal-trends-system-design-2026-07-03.md`; `ui-redesign/trends.md`; `trends-aligned-lanes-mock.html`; `trends-ledger-mock.html`; `trends-calendar-mock.html`; `daily-score-mock.html`.*
