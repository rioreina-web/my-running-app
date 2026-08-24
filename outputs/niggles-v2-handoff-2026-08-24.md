# Niggles v2 — handoff & design-system alignment

**Date:** 2026-08-24
**Branch:** `claude/niggles-dashboard-prototype-w7bib4`
**PR:** [#6](https://github.com/rioreina-web/my-running-app/pull/6) (draft, CI green)
**Companion doc:** `outputs/niggles-v2-dashboard-2026-08-23.md` (schema + extraction contract)

Read this one for **where the work stands and what blocks it**. Read the
companion for the data model.

---

## 0. Status — rebranded, 2026-08-24

The July redesign was confirmed as the direction, so §4 has been carried
out on branch **`design/niggles-v2-rebrand`**, which is the four niggles
commits replayed onto `origin/design/log-detail-editorial` (the redesign
line, 113 commits ahead of `main`). One conflict, in
`web/src/app/design/page.tsx` — both branches prepended a design-index
entry; resolved by keeping both.

Done: §4 steps 2, 3, 4 and 5. Not done: §4 step 1 is now moot, and
nothing has been pushed — the branch is local, and PR #6 still points
`claude/niggles-dashboard-prototype-w7bib4` → `main`.

**§4 step 3 was not mechanical, and the reason matters.** Rules R3/R4
tell you to "use a tracking token utility" and "use the type scale" —
*neither existed*. There were no `tracking-*` or `text-*` token
utilities anywhere in `web/`, which is why all 101 `tracking-[]` and 291
`text-[]` callsites the gate cites as "existing debt" are arbitrary: the
gate has been forbidding a pattern without ever shipping its
replacement. The scale now exists in `web/src/app/globals.css`, lifted
verbatim from `design-system/colors_and_type.css` (8 size steps, 3
tracking steps) plus one documented web-only step (`--text-display-2xl`,
56px) for preview-page headlines that have no mobile equivalent. Every
surface in `web/` can now pay its debt down against real tokens; the
niggles prototype is the first to do so.

**A palette violation this doc missed.** `resolved` status rendered in
`--color-success` (#2D8A4E), which is an alias of `--mood-energized`.
Under the three-palette rule green is mood-only — a resolved niggle is
not a mood. Status is now coral for `active` (it is genuinely an alert)
and ink weight + *form* for the other two: a resolved dot is hollow, a
quiet thread trails off dashed. That is also better for accessibility
than a colour-only encoding, per the foundations' VoiceOver note.

**One honesty fix, unprompted.** The in-progress week's overlay bar was
drawn in the *darker* of the two greys, so an incomplete week read as
more solid than a finished one. It is now the lighter wash.

**Gotcha for anyone re-running the gate locally:**
`check_design_tokens.py` diffs `<base>...HEAD`, so it cannot see working-
tree edits. Stage first and run `--staged`, or it will report violations
on lines you already fixed.

---

## 1. What shipped

A niggles-primary dashboard prototype at `/design/niggles` — mock data,
no Supabase wiring. Training is a *switchable overlay*, not the subject.

| Commit | What |
|---|---|
| `6fb2271` | The prototype + design doc + design-index entry |
| `b8355bf` | Every colour routed through `globals.css` tokens (no hex literals left) |
| `7715227` | Phone-width rework of the timeline |

**Files**

- `web/src/app/design/niggles/niggles-data.ts` — mock rows shaped like the
  proposed `body_mentions` schema, plus thread/status/recurrence derivation
- `web/src/app/design/niggles/niggles-client.tsx` — the dashboard
- `web/src/app/design/niggles/page.tsx` — server wrapper (metadata)
- `outputs/niggles-v2-dashboard-2026-08-23.md` — the design doc

**Sections:** Fig. 01 tiles (active / quiet / resolved / returns) ·
Fig. 02 timeline with the training overlay · Fig. 03 co-occurrence
tallies · Fig. 04 per-thread cards (recurrence, resolution, verbatim log).

**Verified:** `tsc --noEmit` clean, `eslint` clean, `next build` succeeds
and the route prerenders static. Driven in Chromium at 1280px and at
393pt (iPhone 16 Pro): overlay switching, thread scoping, dot selection
and scoped tallies all behave; no page errors.

---

## 2. The finding: a July redesign exists, and it is not on `main`

`outputs/ui-redesign/` — commit **`79ed171`, 2026-07-12** — carries six
briefs: `00-foundations.md`, `log.md`, `training.md`, `trends.md`,
`read.md`, `plan.md`. Alongside them: `prototypes/post-run-drip-beta.html`,
`outputs/trends-metrics-spec-2026-07-10.md`, and
`design-system/ui_kits/ios_app/tokens.css`.

It is **absent from `main`** (still at `7c2934d`) and present on six
branches:

```
origin/design/log-detail-editorial
origin/feat/adaptive-plan-builder-phase-2-5
origin/feature/coach-dashboard-phase1
origin/fix/account-deletion-uuid-owners
origin/fix/trunk-typecheck-build-athlete-profile
origin/wip/session-fixes-2026-07-18
```

All six carry the identical commit, so it was branched from a common
point and never merged down.

This is almost certainly what "old branding" meant. The prototype was
built against the **May** design system (`design-system/README.md`,
`CLAUDE.md`), which is what `main` documents, while a **July** revision
sat on a side branch.

**The name did not change.** It is still Post Run Drip. What changed is
the colour discipline and the information architecture.

---

## 3. Three concrete conflicts with the prototype

### 3.1 Colour — the three-palette rule

The July foundations doc specifies:

> Three-palette color, no exceptions. Blue depth ramp = pace/intensity;
> warm = mood; coral = alert + one-per-cluster punctuation. Green is
> mood-only; coral is never a pace fill.

The prototype uses coral as the general mention colour and neutral
paper-grey for the training overlay bars. Under this system the training
overlay is intensity data and belongs on the **blue depth ramp**; coral
should retract to alert plus single-punctuation use.

The remediation is cheap because of `b8355bf`: colours already resolve
through CSS variables, so this is a token repoint, not a sweep. The
target token source is `design-system/ui_kits/ios_app/tokens.css`
(`--pace-easy-text` is `#5E93BE`, for reference).

### 3.2 IA — the timeline already has a home, and it is not a page

`trends.md` restructures Trends into a `Effort · Fitness · Signal`
segmented sub-nav. The **niggle timeline lives in Signal**, as a
*collapsed expandable summary card*: one 44pt row (label · number ·
delta · sparkline · `▸`) that expands **in place** to the full chart plus
its read. The brief is explicit that this is the core structural fix —
it converts eight full-bleed charts into eight scannable rows.

The what-changed strip at the top of Trends even uses a niggle as its
worked example:

```
┌────────┐
│ CALF   │
│quiet 9d│
└────────┘
```

Substantively this is good news: the derived `quiet` status and its
day-count are exactly the brief's own language, arrived at
independently. Structurally, though, the prototype is a standalone
four-figure page, which is a different object from an expandable card
inside a group.

### 3.3 CI — a design-token gate the prototype would fail

Those branches carry `.github/scripts/check_design_tokens.py`, a
ratcheting lint gate modelled on the eval-coverage gate. Web rules:

- **R3** no arbitrary `tracking-[…]` — use a tracking token utility
- **R4** no arbitrary `text-[Npx]` — use the type scale

It checks **added lines only**, so the repo's existing debt (the script
cites 101 web `tracking-[]` and 291 web `text-[]`) is exempt. Every line
in the prototype is new, and it contains:

| Rule | Violations in `web/src/app/design/niggles/*.tsx` |
|---|---|
| R3 `tracking-[…]` | 19 |
| R4 `text-[Npx]` | 41 |

The gate is not on `main`, which is the only reason PR #6 is green. If
the redesign branch merges down, this PR goes red.

---

## 4. The rebase — done 2026-08-24

1. ~~**Confirm the branch is live.**~~ Confirmed; the redesign is the
   direction.
2. ~~**Repoint the palette.**~~ Training overlay moved onto the blue
   depth ramp (`--color-pace-easy`, washed to 34% — 16% for the
   in-progress week) and off the neutral paper-greys it was borrowing.
   Coral retracted to alert-only in ten places: the overlay switcher's
   selected state, the clear-filter link, the selected row label, the
   today line and its axis label, the dot-selection ring, the readout
   eyebrow, the recurrence day-count, and the session tallies (which are
   training data, so they moved to the blue ramp too). What still earns
   coral: an active mention and its legend key, the active-thread tile,
   the section eyebrows, the readout's 2px left-bar (that is the
   coach-quote primitive), and the co-occurrence headline number.
3. ~~**Replace arbitrary type classes.**~~ All 60 gone — 41 `text-[Npx]`
   and 19 `tracking-[…]`. See §0: the utilities had to be *defined*
   first. Four sizes snapped to a neighbouring step rather than matching
   exactly (9.5→10, 13.5→13, 17→15, 38→40); the 17→15 one is the only
   visible loss, on the readout's verbatim quote, which no longer
   outranks body copy. Worth a look before this ships.
4. ~~**Reframe as a Signal card.**~~ `SummaryCard` + `Sparkline` built to
   the `trends.md` spec: collapsed is one 44pt row
   (`NIGGLE TIMELINE · 5 body areas · 15 mentions · 16 weeks · 2 ACTIVE ·
   ▸`) that expands in place. `Timeline` grew a `framed` prop so the
   expanded state sheds its own card chrome — the brief is explicit that
   this must not be a card inside a card. It mounts open on this study
   page and ships closed in Trends.
5. ~~**Re-verify.**~~ `tsc --noEmit` clean, `eslint` clean, `next build`
   succeeds with `/design/niggles` still prerendering static, and the
   design-token gate passes. Driven in Chromium at 1280×900 and 393×852:
   the summary row measures exactly 44px on desktop and 58px stacked on
   a phone, dot hit areas stay 30px, `scrollWidth == innerWidth` (no
   horizontal overflow), all four overlay modes cycle, dot-tap opens the
   readout, thread scoping works, and the console is clean.

**PR #6 is untouched.** Retargeting it means changing both its head and
its base, which is a call for whoever owns the branch.

---

## 5. Open decisions

1. **Is `design/log-detail-editorial` the live direction?** Blocks §4.
2. **Does Maya see the co-occurrence tallies at all?**
   (`niggles-v2-dashboard-2026-08-23.md` §7.1.) Counting is observation,
   not diagnosis — but a self-coached runner may act on "6 / 7 after long
   runs" without a clinician. Recommendation: ship it, with a minimum
   mention count so single data points never read as a pattern.
3. **Row-tap or dot-tap as the primary touch interaction?** At 19.4px per
   week a dot is tappable, but precise dot-tapping is a poor primary
   gesture. Suggest row-tap opens the thread's mention list, dot-tap
   stays a convenience. Settle before the Swift Charts version.
4. **Should the July redesign be merged to `main`?** It is stranded on
   six branches. Independent of niggles, `main`'s documented design
   system is two months stale, and the token gate isn't defending
   anything while it sits unmerged.

---

## 6. Continuing locally

The prototype route sits behind auth in `web/src/middleware.ts` (as
`/design/training-summary` already does), so viewing it on a deployment
needs a logged-in session. Locally, `npm run dev` in `web/` and visit
`/design/niggles`.

To read the redesign without switching branches:

```bash
git show origin/design/log-detail-editorial:outputs/ui-redesign/00-foundations.md
git show origin/design/log-detail-editorial:outputs/ui-redesign/trends.md
```

Nothing in the niggles branch depends on the redesign yet, so the two can
be reconciled whenever the direction is settled.
