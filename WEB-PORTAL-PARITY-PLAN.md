# Web Portal → App Parity Plan

**Goal:** bring `web/` (Next 16, Vercel) to match the iOS `RunningLog` app's
IA, surfaces, and editorial system — so the portal is the same product on a
bigger screen, not a different one.

**Status as of 2026-08-06.** Written against verified code, not the briefs.
Where the briefs and the code disagree, the code wins and it's noted.

---

## 0. Before anything else: production is four months stale

The live portal (`web-tau-pearl-55.vercel.app`) is serving commit `df61605`
— **14 Apr 2026**. The 3 Jul deployment was a *redeploy of that same build*,
not new code. Six commits touching `web/` have never shipped:

| Commit | Date | Stranded |
|---|---|---|
| `36809a6` | Jun 10 | env.server boundary, rate-limited API routes, pace chart on canonical ladder |
| `d886977` | Jun 10 | supabase-js import unification, edge TS fixes |
| `d1fd780` | Jul 12 | adaptive plan builder — coach AI guidance + athlete preview rail |
| `fdbf503` | Jul 17 | workout drawer redesign + coach-workout-read |
| `a4080df` | Jul 18 | workout-detail + fitness-predictor fixes |
| `0ac693e` | Jul 31 | trends v2 |

161 files, ~27k insertions. **Slice 0 is redeploying from HEAD** — otherwise
every parity slice below lands on top of an invisible baseline and we can't
tell parity work from deploy drift. Same failure mode as the edge-function
drift; check the deploy before believing a web feature is live.

Also on the Vercel project: no custom domain, only `.vercel.app` aliases.
`postrundrip.com` still resolves to the old WordPress site.

---

## 1. Canonical sources

| What | Where |
|---|---|
| Design system (voice, color, type, IA, honesty rules) | `outputs/post-run-drip-design-system-copy-2026-07-13.md` |
| Pace ramp source of truth | `RunningLog/RunningLog/Workouts/PaceSpectrum.swift` |
| Tab wiring (the real IA) | `RunningLog/RunningLog/App/RunningLogApp.swift` `MainTabView` |
| Tab bar | `RunningLog/RunningLog/App/DripTabBar.swift` |
| Web tokens (already mirrored) | `web/src/app/globals.css` |
| Design HTML/JSX mocks | `design-system/` |

**IA correction.** The design-system doc specifies a 4-tab beta IA
(`LOG · TRENDS · TRAIN · COACH`). The shipped app is **3 tabs — `LOG ·
TRENDS · TRAIN`**. Coach/The Read was removed as a tab on 2026-07-28
(`RunningLogApp.swift`, Tab 2 comment); `CoachReadView` still exists at
`Coaching/Read/CoachReadView.swift`, unlinked, so it can come back as a tab
or a pushed screen. The comment there says the **web coach portal remains
canonical for coach work**.

So parity means 3 athlete surfaces, and the web keeps its coach portal as a
deliberate web-only extra.

**And there's a fourth surface that isn't a tab: Ask.** Added 2026-08-05, it
is the analysis half of the retired Coach tab, opened as a sheet from the
foot of Trends (`RunningLog/Analysis/AskView.swift`). Trends shows the shape
of the block; Ask interrogates it. Its architecture is strict and worth
matching rather than reinventing:

- **Layer 0 route** — free text → analyzer id from a *closed enum*
  (`supabase/functions/ask/index.ts`). Chips skip this layer.
- **Layer 1 analyze** — deterministic, no model, emits `FactLine[]` +
  `Coverage` + optional chart spec (`_shared/analyzers/`).
- **Layer 2 narrate** — two sentences over the fact lines and nothing else;
  every numeric token is checked against them
  (`_shared/narration-guard.ts`).

**The rule that makes it safe: if a number is not in `facts`, it does not
exist.** Degradation is the design — no key, rejected number, exhausted
quota all yield `narration: null` with the analysis intact.

Adding an analyzer is one file plus one line in its `index.ts`; the chip rail
is built from the server's `__catalog__`. **A web Ask client is therefore
mostly free** — the whole backend is already deployed and app-release-
independent. That reframes the Read decision (§6).

---

## 2. Where the web already matches

Genuinely more aligned than it looks — don't rebuild these.

- **IA skeleton is right.** Sidebar primary group is Log · Trends · Train
  (`src/components/layout/sidebar.tsx:30-32`). `/dashboard` → `/trends` and
  `/plan` → `/train` are already redirects with the IA decision recorded in
  the comments.
- **Train's three modes exist** — CURRENT · CALENDAR · HISTORY
  (`src/components/train/train-tabs.tsx`), explicitly mirroring the iOS
  segmenter.
- **The design tokens are already the app's.** `globals.css` carries the
  ten-stop blue pace ramp keyed to `PaceSpectrum.swift`, the warm mood
  palette, coral-as-only-accent, and the three-palette rule written into the
  comments. Crimson Pro + PT Serif self-hosted via `next/font/local`.
- **UI primitives exist**: `eyebrow`, `drop-cap`, `editorial-divider`,
  `mood-badge`, `narrative-stat`, `plate-strip`, `zone-dot`, `stat-card`.
- Mood (44 files) and niggle (22 files) concepts are threaded through.

---

## 3. The gaps

### 3.1 Log is read-only — no capture front door
iOS Log (`Workouts/VoiceLogView.swift`, 1675 lines) is *the capture front
door*: record button + voice/manual toggle on top, journal below. Web has
zero capture — no `MediaRecorder`, no `getUserMedia` anywhere in `src/`. The
empty state literally reads *"Record a voice memo or log a run from the
app"* (`log/journal-view.tsx:219`).

The journal half is decent (week grouping, mood hues, VOICE/CHECK-IN
badges, processing states, inline edit). It's the input half that's missing.

### 3.2 No athlete workout detail
iOS has the three-act workout view; the rep receipt alone is 1804 lines
(`Workouts/WorkoutRepReceiptView.swift`). On web, journal rows only expand
inline — there is **no athlete-facing workout route at all**. The only
workout detail is coach-side:
`(app)/coach-portal/athletes/[id]/workouts/[logId]/page.tsx`.

### 3.3 Trends has no PATTERNS
The spec's centerpiece for Trends — 1–3 AI-surfaced qual × quant
correlations, each citing numbers, stating confidence, ending in a soft
italic question. On web, `PATTERNS` appears only in
`components/coach/dashboard/signal-band.tsx` (coach side). Athlete
`/trends` (647 lines) is Volume · Niggles · Mood · Upcoming · Recent
Workouts — the lanes, but not the read on them.

### 3.4 `data_depth` is not implemented
Honesty rule 4 gates editorial register on 0–3 data depth. On web
`data_depth` appears exactly once — a **comment in `globals.css:101`**.
Nothing reads it. Full editorial voice renders regardless of how little data
an athlete has.

### 3.5 Race prediction presentation is partial
`confidence` exists on the pace-chart surfaces
(`pace-chart/page.tsx:15,23`) but the presentation rule isn't enforced as a
shared component. Any surface that prints a prediction must go through one.

**The rule is NOT a range** — hard rule #7 was revised 2026-07-18. A
confidence-scaled band read as too wide to be useful (a 13-minute marathon
window whose fast end beat the athlete's PR was worse than one honest
number). Ship: **midpoint as the projection + HIGH/MEDIUM/LOW tier +
demonstrated lifetime PR alongside.** Round marathon/half to the minute.
Never a bare projection with no tier and no PR context.

The design-system doc's "range + confidence" language (§7 rule 1) predates
this and is superseded. `outputs/marathon-prediction-honesty.md` still holds
for the *rationale*, not the presentation.

### 3.6 The new load model is absent
`stress_load`, `effort_load`, `density_pct` — **0 hits** in `web/src`. The
per-workout stress load and the effort/density model exist in the DB and
edge functions; the portal doesn't know about them. (Note: both backfills
are still unrun, so the columns are largely NULL — the web work should
tolerate nulls rather than wait.)

### 3.7 The Read has no athlete surface
No `/coach` route. Given Coach is no longer an iOS tab, this is a **decision
point, not an automatic build** — see §6.

### 3.8 Housekeeping
Four `.fuse_hidden*` files are committed under `src/app/(app)/log/` and
`src/app/(app)/coach-portal/athletes/[id]/`. Delete them; add to
`.gitignore`.

---

## 4. Parity matrix

| Surface | iOS | Web today | Gap |
|---|---|---|---|
| **Log** — capture | `VoiceLogView` record + toggle | none | **Full build** |
| **Log** — journal | `JournalLogRow`, week groups, niggle chips | `journal-view.tsx` | Small — parity on chips/labels |
| **Trends** — lanes | `TrendsV2View`, signal lanes | volume/mood/niggle sections | Medium — restructure to lanes |
| **Trends** — PATTERNS | signal sections | none (athlete) | **Full build** |
| **Trends** — prediction | range + confidence | partial, pace-chart only | Medium |
| **Train** — CURRENT | `TrainingTabView` | `train/page.tsx` | Small — conditions readout, week footer |
| **Train** — CALENDAR | month/block grid, plan overlay | `train-calendar.tsx` | Medium |
| **Train** — HISTORY | Workouts & Reps archive, 80/20 | `pace-volume-distribution` | Medium |
| **Workout detail** | 3 acts, rep receipt | none (athlete) | **Full build** |
| **Coach / The Read** | removed as tab, view retained | none (athlete) | Decision |
| **Coach portal** | n/a | 12 routes, 24 components | Web-only, keep |

---

## 5. Build order

Tab-by-tab, tight slices, build-verify-pause — the same rhythm that worked
on iOS Log.

**Slice 0 — Redeploy from HEAD.** `npm run build` locally first (27k lines
haven't been through a production build), then ship. Delete the
`.fuse_hidden` files. *Nothing else starts until the baseline is real.*

**Slice 1 — Workout detail route.** `(app)/workouts/[logId]`, three acts,
Act 3 collapsed. Highest value: it's the deepest screen, it's entirely
missing, and the coach-side drawer already proves the data queries. Journal
rows and Train rows both get a destination.

**Slice 2 — Log capture.** `MediaRecorder` + upload to the same pipeline the
iOS app uses, plus the manual-entry form. Reuses existing processing status
UI. Watch the dedup contract — cross-source merges happen at insert via
`session_key`, not at read.

**Slice 3 — Trends restructure.** THIS WEEK strip → range segmenter →
stacked lanes (volume colored by pace depth, mood dots, coral niggle dots).
Structural, mostly reorganizing what's already queried.

**Slice 4 — PATTERNS.** The AI correlation band. Needs an edge function or a
route reusing the coach `signal-band` logic. Every pattern cites numbers,
states confidence, ends in an italic question.

**Slice 5 — Train polish.** Conditions readout per completed run
(temp · dewpoint · heat-adj · climb), week footer aggregates, the quiet
recovery observation line, calendar plan overlay + phase tag bar.

**Slice 6 — Honesty infrastructure.** `data_depth` gate (0–3 table in
`CLAUDE.md`) + a single shared `<Prediction>` component enforcing
midpoint + tier + PR. Arguably belongs earlier, but it's a refactor across
surfaces — cheaper once the surfaces exist.

**Slice 7 — Ask client.** Chip rail from `__catalog__`, fact lines, chart,
coverage, narration on top. Backend already ships; this is a client.

---

## 6. Decisions

**Resolved 2026-08-06:**

1. **Deploy** — ship from the current branch (`fix/audit-2026-08-06`).
   *Blocked:* the stored Vercel CLI token is invalid and `vercel login` needs
   an interactive browser flow. Run `npx vercel login` then
   `npx vercel --prod` from `web/`. Local production build passes clean
   (exit 0, 33 routes).
2. **The Read on web** — yes, build it as a web-only surface. **But** see
   §1: iOS replaced the Read's analysis half with **Ask**, whose backend is
   deployed and client-agnostic. Recommend splitting the decision — build
   the **Ask client (Slice 7) first** since it's nearly free and is what iOS
   actually ships today, then decide whether the narrative Read still earns
   its own surface on top. Flagging rather than assuming.
3. **Voice capture on web** — yes, full parity. Slice 2 proceeds as written.

**Still open:**

4. **Custom domain.** Portal is on `.vercel.app`; `postrundrip.com` still
   points at WordPress. Where should the portal actually live?

---

## 7. Rules that bind every slice

From the design system §7 and standing project principles:

1. Predictions ship as **midpoint + HIGH/MEDIUM/LOW tier + lifetime PR**
   (hard rule #7, revised 2026-07-18 — *not* a range; the band read as too
   wide). Round marathon/half to the minute. Never a bare projection with no
   tier and no PR alongside.
2. **Niggles**: closed body-part vocabulary, athlete's words verbatim,
   surface-never-interpret. No diagnoses, no severity scoring, no "rest/ice."
3. AI never recommends stopping training, never makes medical claims.
4. `data_depth` gates register: plain UI text under ~7 days; full editorial
   only at 21+ days or a set goal. Pull-quotes at depth 2+ cite a number.
5. Cross-training shows in the journal, stays out of running-fitness math.
6. Race anchor beats goal time for pace zones.
7. **No hardcoded pace defaults** — every pace from real data.
8. **Plans are optional** — `activePlan == nil` is first-class, not an error.
9. **AI advises, never acts** — no silent writes; the athlete accepts every
   change.
10. **No invented facts** — every prompt forbids inventing races, results,
    stats, or dates not in context.
11. Sort by **workout date**, not created-at.
12. Time deltas ≥60s format as `1:39 slower`, never `99 seconds`.
13. Three-palette rule: blue = pace, warm = mood, coral = alert. Never share
    hues. A "safe zone" band is neutral gray, never green.
14. Always label workouts via the shared label helper (iOS:
    `WorkoutLabel.display(_:)`) — TEMPO/THRESHOLD retire to LT.

### Web-specific

- **Pace zones come from `derivePaceTableFromGoal`** in
  `src/components/coach/workout-helpers.ts`. Do **not** reintroduce the
  legacy seconds-offset ladder — it was a bug, already fixed once, and it
  still exists in stale `.claude/worktrees/*`. Never source from those.
- **Workout labels are session-intent labels — NOT pace zones.** Reversed
  2026-08-10; an earlier version of this doc recorded the old rule and it is
  wrong. A pace zone describes a *segment's pace*; a workout type describes a
  *session's intent*. Collapsing them made an easy long run and a
  marathon-pace session compete for one vocabulary.
  - Canonical source: `RunningLog/App/WorkoutLabel.swift`. Web port:
    `web/src/lib/workout-label.ts` — **all four drifted web lists now delegate
    to it** (done 2026-08-18).
  - `tempo` folds to `threshold` on write. The old `threshold` → `lt` fold is
    GONE. `mp`/`hmp`/`lt`/`10k`/`5k`/`3k`/`mile` are no longer offered as
    workout types but still render on legacy rows.
  - The per-workout pace-zone label (auto-derived, athlete-overridable) is
    designed but **NOT built**. Until it ships nothing may derive one — the
    first version of `workout-detail.ts` did exactly that and had to be undone.
- **Empty states use `<EmptyState />`** (eyebrow + plain-prose nudge +
  optional CTA). Never an em-dash placeholder — hard rule #8.
- **Mood vocabulary is closed:**
  `energized | positive | neutral | tired | struggling | injured`. Stored as
  TEXT, never numeric.
- **Ask numbers may only come from `facts`.** If a web Ask client renders a
  number the analyzer didn't emit, that's a bug, not a formatting choice.

---

## 8. Local dev

```bash
cd /Users/rioreina/my-running-app/web && npm run dev   # → localhost:3000
```

`.env.local` holds **live** Supabase + Vital credentials — local dev is
pointed at production data. All app routes 307 to `/login` until you sign in.

Two pre-existing startup warnings, harmless: Next 16 deprecates the
`middleware` convention in favour of `proxy`, and Sentry wants an
`onRouterTransitionStart` export from `instrumentation-client.ts`.
