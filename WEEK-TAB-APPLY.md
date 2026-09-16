# WEEK — the weekly decision tab

**Applied:** 2026-08-19 · directly to the working tree
**Scope:** one new tab (`week`, tag 11) + five files under
`RunningLog/RunningLog/Week/`. Two existing files patched.
**NOT COMPILED HERE** — the cloud container has no Xcode. Build before
trusting it. Verify steps in §6.

---

## 0 · The thing that happened, recorded first

This tab shipped twice on 2026-08-19. **The first version was entirely
invented** — a hand-built fixture rendering 48 miles a week, six runs, 340
load-minutes, fourteen filled mood dots, a threshold at 5:21. It looked
finished. Rio asked one question — *"what's 48 miles from?"* — and the honest
answer was **nothing**. It was a string I typed.

Worse than miscalibrated, it was the **wrong shape**:

| | The fixture | The real account |
|---|---|---|
| Weekly miles | 48 | **52–77** |
| Runs per week | 6 | **8–16** |
| Weekly load | 340 vs a 250 "normal" | **473–711** |
| Mood entries / 14 days | 14, all filled | **1–5 per week** |
| Doubles | none | **most days** (Mon 17 Aug: 6.0 + 4.0; Tue: 2.1 + 6.2 + 2.0) |

A day cell holding one number cannot represent an athlete who doubles. A mood
row with fourteen filled dots invents the athlete's own words back at them.
Those are design errors, not data errors, and wiring the fixture layout to
real data would have produced a wrong-shaped page with correct numbers in it.

So the fixture was deleted and the tab rebuilt on the real rows. **Two rules
came out of it, and they bind anything built on this surface:**

1. **If a value cannot be derived from the athlete's own rows, do not produce
   it.** No constants standing in for data, no "typical" values, no
   placeholder series. The section says why it is dark, in a sentence.
2. **Never add provenance to a number you invented.** Mid-fix, the next step
   was going to be attaching source rows to the fixture — fake sessions citing
   fake laps. That makes a false number *more* convincing, not less. It was
   reverted before it landed.

## 1 · What this is

Three questions, answered from the athlete's own training.

| | Question | Signals |
|---|---|---|
| 01 | Am I getting faster? | Threshold bands (HMP/MP), session by session, on heat-adjusted pace |
| 02 | Am I absorbing the work? | Weekly load stacked by pace zone vs own baseline; niggles; mood; overnight |
| 03 | What moves the marathon? | Long runs, pace-spectrum distribution, threshold volume, weekly volume |
| — | The call | **Nothing.** No proposal engine exists; the section says so. |

**Every chart is tappable and every number can name its source.** Tap a point
on the threshold line → the session, its minutes in band, the heat-adjusted
pace membership was decided on, and the raw pace the watch recorded, with the
correction between them. Tap a load bar → the runs in that week and each one's
load. Tap a spectrum zone → the runs that put miles there. Tap a day → its
runs, in clock order. Tap the week total → the days that add up to it.

That last one exists specifically because of §0.

## 2 · Files

```
RunningLog/RunningLog/Week/WeekModels.swift       NEW  the value type + provenance types
RunningLog/RunningLog/Week/WeekService.swift      NEW  derives everything from TrendsService
RunningLog/RunningLog/Week/WeekComponents.swift   NEW  charts, chips, card, provenance sheet
RunningLog/RunningLog/Week/WeekTabView.swift      NEW  the surface
RunningLog/RunningLog/Week/WeekPreviewData.swift  NEW  EMPTY STATES ONLY — no sample data, ever
RunningLog/RunningLog/App/DripTabBar.swift        EDIT + `case week = 11`, + label
RunningLog/RunningLog/App/RunningLogApp.swift     EDIT + mount at tag 11
CLAUDE.md                                         EDIT IA section corrected (see §5)
```

The Xcode project uses `PBXFileSystemSynchronizedRootGroup`, so files under
`RunningLog/RunningLog/` are picked up automatically. No `.pbxproj` edit
needed, and none was made.

## 3 · Architecture — a second reader, not a second fetch

`WeekService` **does not fetch.** It calls `TrendsService.refresh()` and maps
the result. That payload (`trends-timeline`) already carries, per day:

- deduped miles with **doubles summed**, plus `runs[]` with clock times
- the full ten-zone `zoneMinutes` / `zoneMiles` / `zoneLoad` breakdown
- `mood`, nil when unlogged — *"never fabricated"*, per its own contract
- `niggles[]` verbatim, `stress_load`, `durationMin`
- `hrvRmssd` / `restingHr` / `sleepTotalMin` / `sleepQuality`

…and `paceBands`, which carries per-session `paceAdjSec`, `paceRawSec`,
`correctionSec` and `hrAvg` — the provenance in §1, already computed.

`TrendsService` is a shared singleton that joins an in-flight load rather than
duplicating it, so opening Week costs nothing when Trends has been opened, and
warms Trends when it hasn't.

`WeekBuilder` is a pure `enum` of static functions — testable without a
network or a service. **That is where to add tests first.**

### Derived here, and how

| Field | Derivation |
|---|---|
| Week strip | Days in the current Mon-start week; `runs[]` rendered as "6.0 + 4.0" when a day has more than one |
| Week total | Sum of day miles. Tappable — this is the answer to "what's 48 from?" |
| Load series | `zoneLoad` summed per ISO week; baseline = mean ± 1 SD of the **prior** weeks, zero-running weeks held out |
| Spectrum | `zoneMiles` aggregated over 28 days, as a share of the total |
| Niggles / mood | `day.niggles` and `day.mood` over 14 days — **unlogged days render as empty rings** |
| Long runs | Days where `type == .long`; "inside it" is the real zone composition, not an inferred intent |
| Bands | `paceBands.sessions(in:)`, one point per session |
| Threshold volume | `paceBands.summary(.hm).minutes` |

## 4 · Three sections are honestly dark

Each returns a `WeekRead.Unavailable` and renders as prose via
`WeekUnavailableNote` — never a dash, never a greyed chart with invented shape.

1. **Heart-rate efficiency** — `.notWired`. `EfficiencyIndexCard` /
   `efficiency.ts` compute it; it isn't plumbed to this tab.
2. **Overnight biometrics** — `.notCaptured`. `daily_biometrics` is migrated,
   RLS'd and indexed and **empty**, because `vital-webhook` has no daily-sleep
   branch. Per `ASK-REGISTRY.md` §0 this is *one integration away, not four
   builds*.
3. **The proposals** — `.notWired`. There is no `proposed_actions` anywhere in
   the repo. The whole glass-box proposal flow from the prototype (diff,
   evidence chips, Apply/Adjust/Keep) is **not built**. `Proposal`,
   `Evidence` and `DayChange` remain in the model as the intended shape.

**Fuelling and cardiac drift were removed from the long-run ledger entirely.**
Carbohydrate intake is not captured anywhere — no column, no field, no
classifier — so the column was inventing a data source. That is a capture
problem before it is a display problem.

## 5 · CLAUDE.md was wrong, and it cost an argument

The IA section claimed **three tabs**. The app had shipped more since
2026-08-11 (Sheet), then Ask and Week on 08-19. The bar is now **six** — Log ·
Train · Trends · Week · Ask · Sheet.

Recorded because the stale number produced a wrong argument on the day: Week
was initially argued against for "reversing the direction of travel" from a
5 → 4 → 3 reduction that had already reversed months earlier. `DripTab` is the
only source of truth; CLAUDE.md now carries a warning saying so.

**The IA cost is real and unpaid.** `DripTabBar.swift` notes the last two tab
additions "were both eventually spent replacing something." Week should face
the test that retired Coach: *does it get opened, and does it end?*

**The merge worth revisiting:** Week is arguably what Ask becomes. Ask is
"pick any question from a closed analyzer enum"; Week is "here are the three
questions that matter this week, pre-answered." Ask's architecture — computed
first, narrated second, model may only speak the fact lines — is already the
safety model a proposal engine needs.

## 6 · Verify (Xcode)

1. **Build.** Nothing here was compiled.
2. Tab bar shows six items; WEEK between TRENDS and ASK.
3. **Signed in, the tab shows real training.** Week total should match the
   actual week; tapping it lists the days that sum to it.
4. Doubles: a day run twice shows "6.0 + 4.0" under the total, and tapping it
   lists both runs with clock times.
5. Mood row: days with nothing logged are **empty rings**. If the row is
   fully filled, the nil-handling regressed.
6. Threshold: HMP/MP toggle; tapping a point shows adjusted pace, raw pace and
   the heat correction. **Faster plots higher** — if it plots lower the y-axis
   inverted.
7. Load: bar heights match totals, stacks slow-at-base, baseline band behind.
   Tapping a bar lists that week's runs.
8. The three dark sections render sentences, not empty charts.
9. A brand-new account: `WeekRead.previewEmpty` is the expected look.
10. Dynamic Type at max: the long-run ledger row is the first thing to break
    (four fixed columns). Untested.

## 7 · Next, in order

1. **Tests for `WeekBuilder`** — it is pure and currently untested. Baseline
   with a layoff week; a day with three runs; a day with no lap breakdown; an
   account with two weeks of history.
2. **The `vital-webhook` daily-sleep branch** — unlocks section 02's bottom
   half and four analyzers at once.
3. **Fuelling capture** — a post-run field, or extraction from the voice memo.
4. **The proposal engine** — and before any of it, decide: do coach
   constraints bound it or inform it, and who owns the tap when a coach is
   attached?
