# Design remediation plan — Post Run Drip

*2026-06-16. Consolidates and re-bases the two May-20 audits
(`design-parity-audit-2026-05-20.md`, `design-system-audit-2026-05-20.md`)
against the code as it actually ships today, adds the June findings
(Trends ⇄ Training overlap), and sequences everything — including the two
strategy calls that gate pixel work — into one prioritized, effort-tagged
work plan.*

This doc does not supersede the May audits; it points at them for the
per-surface and per-token detail and stays focused on **what to do, in
what order, and roughly how much it costs.**

---

## TL;DR

The design *vision* is top-decile; the *execution* is uneven because there
is no enforcement layer (tokens + lint) and the IA isn't settled. The
bottleneck is not talent, taste, or documentation — you have more design
docs than most teams twice your size. It is **enforcement and a settled
information architecture.**

The May system audit scored it **58/100**. A month later the score is
roughly the same, but for a more encouraging reason: real fixes shipped
(MoodBadge, PlateStrip adoption), and at the same time new surface area
appeared (the revived Trends tab, the rebuilt Read) that re-opened the IA
question. Net: the team *can* close these — the issue is that drift is
created as fast as it is cleaned because nothing mechanical holds the line.

Three strategy decisions (Wave 0) gate everything. Then one wave of
**token/enforcement** work converts the written spec into something a
linter can defend. Only then is per-surface polish worth doing.

---

## What changed since the May audits (verified in code today)

| May finding | Status 2026-06-16 |
|---|---|
| `MoodBadge` ships SF Symbol faces (emoji-rule violation) | ✅ **Fixed.** Now a 5px mood-color dot + mono label. |
| `PlateStrip` only on `CoachReadView` | ✅ **Much improved.** Now on 11 surfaces; a real `dripEyebrow` mono primitive exists. |
| `Font.dripCaption(_:)` is PT Serif, not mono | 🔴 **Still open — but bigger and subtler than May implied.** A real `dripEyebrow` mono primitive now exists; `dripCaption` is documented as PT Serif for *sentence-case* hints/errors. So a blanket flip to mono is **wrong** (it would mono-ize legitimate error/hint text). The real fix is migrating only the *uppercase-label* callsites to `dripEyebrow` — and there are **723 `dripCaption` callsites** across dozens of files. This is a scoped migration, not an afternoon. See revised 1.1. |
| Em-dash empty-state placeholders (rule #8) | 🟢 **Re-scoped — not the violation it looked like.** All 9 `Text("—")` sites are *inline no-data tokens* (delta chips, a 40px HR column, race-prediction delta cells; one is intentional per adaptive-plan rules). None is a section-level empty-state placeholder, so rule #8's fix (eyebrow + nudge + CTA) doesn't apply. Zero true section-level violations found. See revised 1.3. |
| `Color.drip.electric` misnamed (should be `coralDeep`) | ✅ **Fixed 2026-06-16.** Renamed to `coralDeep` with a token doc-comment; 2 callsites migrated; `electric` kept as a `@available(deprecated)` alias. |
| No `DripSpacing` tokens on iOS | 🔴 **Still open.** |
| iOS↔web type split (Crimson/PT Serif/SF Mono vs Playfair/DM Sans/JetBrains) | 🔴 **Still open.** Confirmed in `web/src/app/layout.tsx`. |
| Today tab orphaned → "open as sheet from Log" (decided 2026-05-21) | ⚠️ Decision made; verify it shipped. |
| Tab count | ⚠️ **Drifted further.** Now 5 (`Log · Training · The Read · Plan · Trends`); target is 4; Trends + Training now overlap. |

The takeaway: the *cheap, mechanical* items (MoodBadge, PlateStrip) got
done. The *structural* items (token enforcement, IA, type system) did not —
exactly the items that require a decision or a sweep rather than a
one-file edit. This plan front-loads those.

---

## Wave 0 — Three decisions that gate pixel work

Do not start surface polish before these. Fixing surfaces without these
guarantees re-drift, because the surfaces sit inside an unsettled frame.

### Decision 1 — Settle the tab IA (4 tabs) and resolve Trends ⇄ Training

**Problem.** Three sources disagree: code ships **5** tabs
(`Log · Training · The Read · Plan · Trends`), the design system documents
`LOG · TRAIN · TRENDS · COACH · RUNS`, and the roadmap target is **4**
(`Log · Trends · Train · Coach`). Worse, `TrainingTabView`'s own header
comment says it "replaces the old Train + Trends tabs," yet Trends was
revived as a separate chart tab — so today you ship **two analytics
surfaces** with overlapping volume-by-intensity data and *two different
time vocabularies* (Trends: `4WK · 12WK · 6MO`; Training: `WEEK · MONTH ·
BLOCK`).

**Options.**

- **(A) Two analytics tabs, distinct jobs.** Trends = *the arc over time*
  (the longitudinal unified timeline, no aggregate stat strips). Train =
  *this period, decomposed* (the WEEK/MONTH/BLOCK cross-section). Unify the
  time vocabulary across both, and make Trends' "GO DEEPER · Volume"
  navigate *into* Train's volume detail instead of its own
  `VolumeDetailView`.
- **(B) Fold into one analytics tab (matches the 4-tab target).** Trends'
  timeline becomes the hero at the top of Train; the WEEK/MONTH/BLOCK
  decomposition scrolls beneath it. Plan collapses into Train as the
  roadmap already specifies. Result: `Log · Train · Coach` + Plan-as-mode.

**Recommendation: (B).** It's what the roadmap and the `TrainingTabView`
comment already imply, it removes the duplicate volume chart and the
double time-vocabulary, and it gets you to the 4-tab target. (A) is the
fallback if the timeline and the decomposition prove too tall to live on
one scroll. *Effort: decision is free; (B) implementation ≈ 1 week incl.
de-duping detail destinations.*

### Decision 2 — iOS↔web type system: two-on-purpose, or unify

**Problem.** Colors match to the hex across platforms; **fonts share not a
single family.** iOS: Crimson Pro / PT Serif / SF Mono. Web:
Playfair Display / DM Sans / JetBrains Mono — and the body slot even flips
*serif (iOS) vs sans (web)*. The brand reads as two products.

**Options.**

- **(A) Unify on the iOS families** (Crimson Pro / PT Serif / mono).
  Migrate web. Highest brand payoff; the iOS families are the ones the
  README treats as canonical ("Type is the visual identity").
- **(B) Keep two, on purpose, and document why** (e.g. licensing, web
  performance, or the coach portal being a different audience). Legitimate
  — but then say so in the spec so it stops reading as an accident.

**Recommendation: (A) for the athlete-facing web, (B) tolerated for the
coach portal** (different audience, per the May audit's own note). The
body serif↔sans flip is the most jarring; fixing just that recovers most
of the coherence. *Effort: depends on font licensing; budget 1–2 days for
the swap + visual sweep once the license question is answered.*

### Decision 3 — Commit the design-system source into the repo

**Problem.** `colors_and_type.css` and the JSX plate mockups are referenced
by every audit *by path* but historically lived **outside the tree**, so
"the spec" is a moving target nobody can diff against. (The
`design-system/` folder now appears in the working copy — confirm it's
actually committed, not just present locally.)

**Recommendation:** commit it, and make it the single source the lint
rules in Wave 1 read from. *Effort: half a day. Unblocks everything
downstream.*

---

## Wave 1 — Token & enforcement foundation

This is the highest impact-per-effort wave. It converts the written spec
into something mechanical. Without it, Wave 4 polish re-drifts in six
weeks (the May audit's exact prediction, now borne out).

| # | Task | Why it matters | Effort |
|---|---|---|---|
| 1.1 | **Migrate `dripCaption`'s uppercase-label callsites to `dripEyebrow`** (do **not** flip `dripCaption`'s body — keep it PT Serif for sentence-case hints/errors). Restores the typewriter cadence on every mislabeled eyebrow. | The May audit's "single biggest reason the app reads as the old version" — but it's 723 callsites mixing uppercase labels and sentence-case meta, so it needs classification, not a one-line flip. | 🟡 **Re-scoped to ~1–2 days** (was billed as ~1h). Best done file-by-file with a visual pass; a compiler/preview is required to verify. |
| 1.2 | **Add `DripSpacing` tokens** (`xs=4 … xxxl=32`) and sweep the off-grid `14/10/6/22` paddings toward the 8pt grid. | iOS has *zero* spacing tokens — ~1,100 hand-typed paddings. No token = guaranteed drift. | 🟡 ~1 day + sweep |
| 1.3 | **Define an inline "no-data" convention** (a muted micro-token) and a *separate* section-level empty-state audit. The 9 `Text("—")` sites are inline cells, not rule-#8 section placeholders — leave them until the convention exists. | Rule #8 targets empty *surfaces*, not 40px numeric cells. Swapping inline dashes for `EmptyStateView` would break dense layouts. The honest gap is the absence of a sanctioned inline empty token. | 🟢 design decision, ~2h to spec |
| 1.4 | ~~**Rename `electric` → `coralDeep`.**~~ | Value was right; name read like a Stripe color. | ✅ **Done 2026-06-16** |
| 1.5 | **Extract remaining inline primitives** (`Eyebrow`, `EyebrowCoral`, `DripSpacing`) and delete any leftover private `EditorialRule` duplicates. | Stops every new surface from re-rolling its own eyebrow with a drifting tracking value. Pairs naturally with 1.1. | 🟡 ~0.5 day |
| 1.6 | ~~**Add a lint gate**~~ that fails on: `Color.drip.electric` (deprecated), hardcoded `#hex` in iOS views, and (web) arbitrary `tracking-[Npx]` / `text-[Npx]` literals. | This is the actual fix for "drift outpaces cleanup." Everything above stays fixed only if a machine defends it. | ✅ **Done 2026-06-16** — `.github/scripts/check_design_tokens.py` + `design-tokens` CI job. Ratcheting (diff-aware), so it starts green over existing debt. |

**Reality check after touching the code:** of the three items billed as
"same-day wins," only 1.4 (`electric`) survived contact unchanged — it's
done. 1.1 is real but ~1–2 days, not an hour (723 callsites, and the
blanket flip the May audit suggested is actually wrong now that
`dripEyebrow` exists). 1.3 dissolved on inspection — those em-dashes are
legitimate inline tokens, and the true rule-#8 work is defining an inline
no-data convention. The pattern holds: the items needing judgment or a
sweep are exactly the ones still open.

---

## Wave 2 — IA consolidation (executes Decision 1)

| # | Task | Effort |
|---|---|---|
| 2.1 | Implement the chosen tab structure (recommend 4-tab: fold Trends timeline into the top of Train; Plan becomes a mode of Train). | 🟡 ~1 week |
| 2.2 | Unify the time vocabulary across the timeline and the decomposition (one set of range labels). | 🟢 included in 2.1 |
| 2.3 | Collapse duplicate detail destinations — one volume-detail screen, one mood/niggle renderer — reached from both the timeline and the decomposition. | 🟡 ~1 day |
| 2.4 | Make the timeline an *index into Log*: scrubbing a week exposes "see the runs behind this →" deep-linking into a filtered Log; attribute each verbatim voice quote back to its Log entry. | 🟡 ~2 days |
| 2.5 | Stop deepening the three non-canonical Coach surfaces (iOS `Coaching/`, web `(app)/coach`, `(app)/coach-portal/*`) until the dyad-vs-Maya persona call is made. | 🟢 freeze, not work |

---

## Wave 3 — Cross-platform parity (executes Decision 2)

| # | Task | Effort |
|---|---|---|
| 3.1 | Resolve the body serif↔sans flip first (the most jarring single mismatch). | 🟡 0.5 day once licensing is known |
| 3.2 | Migrate athlete-facing web to the canonical families (or formally document the two-system split). | 🟡 1–2 days |
| 3.3 | Extract `PlateStrip` / `PlateFooter` / `CoachQuote` to web `components/ui/` (they exist inline already — promote). | 🟡 ~1 day |
| 3.4 | Pull the 16 web chart files' hardcoded `#hex` to tokens (`mood-heatmap`, `pace-trend-chart`, `injury-timeline`, `compliance-chart`, `workout-type-donut`). | 🟡 ~1 day |

---

## Wave 4 — Per-surface polish (only after Waves 0–1)

Pulled from the May parity audit; still valid, now unblocked. Each is
small once the tokens and primitives underneath are real.

- **Today:** coral `TUESDAY` eyebrow (restore the active-day signal),
  italic-serif header aside, card-wrap the fitness chart, mood-radio
  capsules instead of bare dots.
- **Sign-in:** "Welcome back." display headline + italic tagline; fix the
  lowercase toggle copy; reconcile the 8/10/12px radii to the input/button
  tokens; button label → Crimson Pro.
- **Workout Detail:** combined pace×HR overlay chart; 4-stat top strip;
  verify fastest-mile coral highlight.
- **Injuries:** lift stat labels off the 8px sub-floor; consider
  mentions-as-score; resolve the two-coral-per-cluster violation
  (severity score *and* EASING trend both coral).
- **Trends/Train insights:** make derived sentences ("quality pace 6:58 →
  6:41") tappable into the relevant decomposition section rather than
  restating the data.

---

## Effort / impact summary

| Wave | Theme | Gating? | Rough cost |
|---|---|---|---|
| 0 | Three strategy decisions | **Yes — do first** | Decisions are free; they unlock the rest |
| 1 | Token & enforcement foundation | Partially gating | ~3–4 days (much of it 1-hour wins) |
| 2 | IA consolidation | After Decision 1 | ~1.5 weeks |
| 3 | Cross-platform parity | After Decision 2 | ~3–4 days + licensing answer |
| 4 | Per-surface polish | After Waves 0–1 | ~1 week, parallelizable |

**If you do only three things:** (1.1) `dripCaption` → mono, (1.3) sweep
the em-dashes, (Decision 3) commit the design-system source. That's one
afternoon and it moves the brand coherence and the enforcement story more
than any amount of new design.

---

## Don't redo / don't do yet

- **Don't re-fix MoodBadge or re-chase PlateStrip adoption** — both
  largely landed since May. Verify, don't rebuild.
- **Don't deepen the Coach portal** until the persona/IA call is made.
- **Don't add new chart primitives** until the existing chart `#hex`
  literals are tokenized (3.4) — new charts will copy the pattern.
- **Don't write more design specs.** The bottleneck is enforcement, not
  documentation.

---

## Progress log

**2026-06-16**

- ✅ **1.4 `electric` → `coralDeep`** — token renamed with a spec
  doc-comment; 2 callsites migrated; deprecated alias retained.
- ✅ **1.1 (started) — Log front door migrated.** Uppercase-label
  `dripCaption` callsites swapped to the mono `dripEyebrow` on
  `LogView` (2: `LOG` eyebrow, date rail) and `VoiceLogView` (6:
  `COACH HAS A CHECK-IN WAITING`, `OR · TYPE NOTES`, two `SAVE`,
  `JOURNAL …`, `LINK TO WORKOUT`). Sentence-case hints, units (`/mi`),
  and prose were deliberately left as PT Serif. `TodayPlate18` was
  already all-`dripEyebrow`; `TodayHomeView`'s lone `dripCaption` is
  the title-case `MoodLabel` pill — **deferred** because making it mono
  forces a title→uppercase decision and a reconciliation with the
  parallel `MoodBadge`.
- ⏳ **1.1 remaining:** ~715 `dripCaption` callsites across `Workouts/`,
  `Training/`, `Analysis/`, `Shared/`. Needs per-callsite classification
  and an Xcode build/preview between batches (mono is wider than PT Serif
  at the same point size — width-sensitive layouts must be eyeballed).
- ✅ **1.6 lint gate shipped.** `.github/scripts/check_design_tokens.py`
  + a `design-tokens` `pull_request` job in `ci.yml`, mirroring the
  existing eval-coverage gate. It is **diff-aware and ratcheting**: it
  fails only on violations a PR *introduces* — deprecated
  `Color.drip.electric`, hardcoded `Color(hex:)` in iOS views (the token
  source `DesignSystem.swift` is exempt), and web arbitrary `tracking-[]`
  / `text-[Npx]`. Verified against planted violations (all four rules fire
  with correct line numbers + GitHub annotations) and against the current
  tree + recent history (green). This is the enforcement layer the whole
  plan argues is the real bottleneck — today's `electric` rename and every
  future cleanup now stay fixed by machine.

> **Verification owed:** these edits were made without a compiler. Build
> the iOS target and visually check the Log tab + voice/manual entry sheet
> before merging — the changes are font-family swaps on short labels (low
> risk), but mono width shifts can nudge tight HStacks.

## Files & sources

- `outputs/design-parity-audit-2026-05-20.md` — per-surface iOS drift (predecessor)
- `outputs/design-system-audit-2026-05-20.md` — system/token-level gaps + 58/100 baseline
- `design-system/README.md`, `design-system/colors_and_type.css` — spec source of truth
- `RunningLog/RunningLog/App/DesignSystem.swift` — iOS tokens/primitives (`dripCaption` L130, `electric` L23)
- `RunningLog/RunningLog/Training/Analytics/TrainingTabView.swift` — analytics Training tab
- `RunningLog/RunningLog/Trends/TrendsTabView.swift` — revived chart tab (the overlap)
- `RunningLog/RunningLog/App/RunningLogApp.swift` — current 5-tab wiring
- `web/src/app/layout.tsx` — web font stack (Playfair / DM Sans / JetBrains)
</content>
</invoke>
