# Niggles v2 — handoff & design-system alignment

**Date:** 2026-08-24
**Branch:** `claude/niggles-dashboard-prototype-w7bib4`
**PR:** [#6](https://github.com/rioreina-web/my-running-app/pull/6) (draft, CI green)
**Companion doc:** `outputs/niggles-v2-dashboard-2026-08-23.md` (schema + extraction contract)

Read this one for **where the work stands and what blocks it**. Read the
companion for the data model.

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

## 4. Proposed rebase, if the redesign is the direction

1. **Confirm the branch is live, not abandoned.** Everything below is
   wasted if `design/log-detail-editorial` was a dead end. This is the
   decision that gates the rest.
2. **Repoint the palette** to `design-system/ui_kits/ios_app/tokens.css`;
   move the training overlay onto the blue depth ramp; retract coral to
   alert + one-per-cluster.
3. **Replace arbitrary type classes** with the token utilities the gate
   expects — clears all 60 violations and makes the prototype gate-clean
   ahead of the merge.
4. **Reframe as a Signal card.** Keep the current page as the *expanded*
   state; add the collapsed one-row summary (`L. ACHILLES · 7 · active ·
   sparkline · ▸`) that it expands from.
5. **Re-verify** at 393pt and 1280px, then update PR #6.

Steps 2–3 are mechanical. Step 4 is a genuine design call and should
follow a read of `trends.md` in full.

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
