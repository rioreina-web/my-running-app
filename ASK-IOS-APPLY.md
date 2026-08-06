# Ask · iOS surface — apply notes

*Placed 2026-08-05. Companion to `ASK-PHASE-A-APPLY.md` (the backend).*

The client for the `ask` endpoint. **4 new files, 1 new test file, 2 edits to
existing files.**

---

## 1 · Where it lives, and why it moved

The spec said "inside the Coach tab." **The Coach tab was retired
2026-07-28** — the app ships `Log · Trends · Train`, and `CoachReadView`,
`ModelOfYouView` and `SignalLabView` are all in the repo but unmounted.
`CoachAskSheet` was reachable only from `ModelOfYouView`, so it was dark too.

Ask therefore lands as **an `AskBar` at the foot of Trends that presents the
upgraded `CoachAskSheet`.** Trends answers *how am I trending*; Ask answers
*why, and compared to what*. Same reason those were split into two screens in
the first place — but the second question is what an athlete wants
immediately after the first, so it sits at the bottom of that scroll.

This revives `CoachAskSheet` and `CoachAskContext` rather than adding a
parallel surface. Anything that already stages a question through
`CoachAskContext` now gets computed answers for free.

---

## 2 · New files — `RunningLog/RunningLog/Analysis/`

| File | What it is |
|---|---|
| `AskModels.swift` | Wire types. The envelope is snake_case, the analyzer payload camelCase — `CodingKeys` are explicit rather than relying on a global key strategy, which would mangle `sessionsUsed` and silently drop coverage. |
| `AskService.swift` | `@Observable` client. Catalog cache + two `resolve(...)` calls. Holds no transcript — the sheet's `Phase` stays the single source of truth for what's on screen. |
| `AskComponents.swift` | `AskChip`, `AskFactGrid`, `AskCoverageRow`, `AskChart`, `AskChartAxis`. |
| `AskView.swift` | `AskBar` (the Trends foot) + `AskAnswerCard` + `FlowRow`. |

**Tests:** `RunningLogTests/AskModelsTests.swift` — 8 cases pinning the decode
contract, including that **facts and coverage survive a dropped narration**,
that an empty state carries no em-dash placeholder (hard rule #8), and that
unknown groups and unknown server fields don't break an older build.

---

## 3 · Edits to existing files

**`Coaching/CoachAskSheet.swift`** — rewritten around two answer paths, tried
in order:

1. **Computed** (`ask`): the question routes to one analyzer, which returns
   fact lines + chart + coverage. A model writes two sentences over those
   facts and cannot speak a number absent from them. Chips skip the router
   entirely.
2. **Prose** (`coaching-agent` via `DailyReadService.ask`): reached only when
   the endpoint reports `mode: "prose"` — no analyzer fits the question.

That fallthrough is what makes free text safe: the worst case for an
unroutable question is today's product, never a wrong number. The existing
`init(question:focus:)` is unchanged (`analyzer:` defaults to nil), so
`ModelOfYouView`'s call site still compiles.

**`Trends/TrendsV2View.swift`** — five lines: an `EditorialRule()` and
`AskBar()` after the "What lines up" section.

---

## 4 · Design decisions worth reviewing

- **The chip rail is built from the server's catalog**, not a hardcoded list.
  `AskBar` calls `{"analyzer_id":"__catalog__"}` on appear. Analyzer four
  appears in the app with no client release; `groupTitle` falls back to
  `.capitalized` so a group invented later still renders legibly.
- **Chips are free.** Layer 1 is never rate-limited server-side, so the rail
  costs nothing to touch. Only the narration call is metered, and an
  exhausted quota still serves the facts.
- **Coral appears once per card** — the `COMPUTED` badge. Fact tones use the
  mood palette (positive / tired), never coral. The three-palette rule holds:
  blue = pace, warm = mood, coral = alert.
- **`invertY` on the chart.** For a pace series lower is faster, so the axis
  flips and an improving athlete's line rises. Getting this backwards would
  make every pace chart read as a decline — check this one by eye first.
- **Free text is behind `AskFeature.freeTextEnabled = false`.** The composer
  works; it's off until the Layer-0 router has been exercised against real
  questions and `ask-narration` has recorded cassettes. One constant to flip.

---

## 5 · NOT verified — read this before trusting it

**None of this Swift is compiler-verified.** There is no Swift toolchain in
the cloud sandbox or in the Linux VM on the Mac, so unlike the TypeScript
(which was typechecked and passed 26 tests) this is careful-by-inspection
only.

What was checked by reading the actual source: `callEdgeFunction(name:body:)`,
`EdgeFunctionError`'s single case, the `Color.drip` members used, the `drip*`
font helpers, `EditorialRule`, and `CoachRead.confidence.level.rawValue`.

What the first build will still catch: everything else.

**The four new files must be added to the Xcode project.** They do not
compile by existing on disk.

---

## 6 · Order to bring it up

1. Add the new files to the Xcode target; build; fix whatever I got wrong.
2. Confirm `AskBar` renders at the foot of Trends. With no backend deployed
   the rail stays empty and says so — that is the correct degraded state.
3. `supabase db push` the `analysis_queries` migration, deploy `ask`.
4. Tap a chip. First real answer.
5. Only then consider flipping `freeTextEnabled`, and record the
   `ask-narration` cassettes before you do.
