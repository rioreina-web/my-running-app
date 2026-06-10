# Coach surfaces audit — May 2026

**Purpose:** before shipping the Daily Read (Phase 4.3 swap), audit every
existing surface in the codebase that produces "what the coach is
thinking" output for an athlete. Identify what overlaps with the new
Read, what's stale, what should consolidate, what should stay separate.

**Why now:** the Daily Read replaces the Coach tab's chat UI, but the
codebase has accumulated four other coach-output surfaces over the past
six months. Without an audit, we risk shipping a fifth surface that
duplicates the existing four — which is exactly the crowding complaint
that surfaced the question. The right time to consolidate is before
launch, not after.

**Scope:** athlete-facing surfaces only. The web coach-portal
(`web/src/app/(app)/coach-portal/*`) is the coach's tooling for
viewing athlete data — out of scope for this audit. Same for
`AthleteRosterView` and other dyad/coach-mode iOS views.

---

## TL;DR — three moves before Phase 4 ships

1. **Delete the Training-tab `CoachReadCard`** once the new Daily Read
   is in production. It's a strict subset of what the new Read does,
   with weaker editorial voice and no citation pattern. It also reads
   from a deprecated table (`coaching_adjustments`) that was replaced
   by `plan_adjustments` two months ago. Keeping it is actively
   confusing.

2. **Decide what `weekly_coaching_reports` is for.** Right now it
   competes with the Daily Read for the same editorial-narrative niche.
   The defensible split: weekly reports are a *retrospective* (last
   week's metrics + alerts + adjustments), the Daily Read is *current
   state*. If we accept that split, the weekly report should narrow
   to backward-looking analysis only and probably move out of the
   Coach tab entirely (Training tab → "block review" surface).

3. **Standardize `ai_insights` consumption.** Three different insight
   types (`run_reconciliation`, `injury_warning`, `injury_analysis`)
   feed three different UI patterns (CoachReadCard banner, niggles
   surface, modal sheet). The Daily Read should absorb the
   reconciliation type — that's literally what "the model reads my
   recent runs" is. Injury types stay separate because they're a
   safety surface with different rendering needs.

Everything else either serves a distinct purpose or is already on a
deletion path in the existing doc.

---

## Per-surface analysis

### Group A: surfaces the Daily Read replaces or absorbs

#### `CoachView.swift` — chat-based Coach tab (LEGACY)

| | |
|---|---|
| What it is | The current Coach tab. Chat UI with "Hey, I'm Coach" welcome card, suggestion chips, message thread. Calls `coaching-agent` on submit. |
| What it produces | Ephemeral chat responses, not stored. |
| Where it surfaces | Coach tab, self-coached path. |
| Overlap with Read | Total. The Read is its replacement. |
| Action | **DELETE in Phase 5** as the doc already specifies. Kept around through Phase 4.3 swap as a rollback target. |
| Severity | Already on the deletion path. Not new work. |

#### `CoachReadCard.swift` (Training/) — adjustment / insight / heat aggregator

| | |
|---|---|
| What it is | Top-of-Training-tab card that aggregates four sources into a list of "CoachNote" items: recent plan adjustments, post-run reconciliations, heat warnings on upcoming quality sessions, missed workouts. Dismissible via UserDefaults. |
| What it produces | A list view of 0-N notes per athlete, sortable by priority. |
| Where it surfaces | Training Plan view (Training tab). |
| Overlap with Read | **High.** Three of the four note kinds (weekly review, last run delta, heat warning) are exactly the kind of observation the Daily Read makes inline. The fourth (missed workout) is a coachable moment, which has its own surface. |
| Action | **DELETE after Phase 4 ships.** The Daily Read is the editorial version of this card. Same data, better voice, citation pattern, single artifact instead of an N-item list. |
| Severity | **High** — this is the source of the naming collision earlier and the closest near-duplicate to what we built. Also: it queries `coaching_adjustments`, which appears to be a deprecated table (see Group D). |

#### `coach_insight` field on `training_logs`

| | |
|---|---|
| What it is | Per-workout one-sentence coaching reading. Generated async via `coach_insight_jobs` outbox by `generate-workout-insight`. |
| What it produces | Single sentence per workout row. |
| Where it surfaces | Training tab DayDetailSheet, sometimes inline in workout lists. |
| Overlap with Read | **Medium.** The Daily Read aggregates across workouts and is daily; `coach_insight` is per-workout. Different cadence and grain. But the same model is essentially being asked to do two jobs: write a sentence about this one run, and write a paragraph about this week. |
| Action | **Keep for now.** Workout-level insights survive when a user is browsing history ("what did the coach say about that Wednesday tempo three weeks ago?"). But there's a future consolidation move: the Read could *generate* the per-workout insight as a side effect, eliminating the separate `generate-workout-insight` function. Not now. |
| Severity | **Medium** — keep but flag as a future consolidation candidate. |

### Group B: surfaces serving a distinct purpose

#### `weekly_coaching_reports` + `WeeklyCoachingReportSheet`

| | |
|---|---|
| What it is | Monday-morning weekly retrospective. Narrative + structured alerts + adjustments + focus areas for next week. Generated by `weekly-coaching-report` edge function via Sunday cron. |
| What it produces | A 3-5 paragraph narrative + 1-3 action items, displayed in a modal sheet. |
| Where it surfaces | Triggered from Coach tab or Training tab. |
| Overlap with Read | **Medium-high.** Both narrative. Both editorial. Weekly is past-tense scope, Daily is current-state scope, but the line is fuzzy — a Monday Daily Read could easily say "last week was your best three-tempo block yet" and overlap entirely. |
| Action | **Narrow the scope.** Keep weekly reports as a *block-level retrospective* surface (Training tab, not Coach tab). Move the "what happened last week" framing out of the Daily Read. Restrict the weekly to: metrics summary, alert pattern across the week, suggested adjustments for next week. The Daily Read handles current state and trend signal in real time. |
| Severity | **High strategic call** — both surfaces will exist; the question is whether the line between them is clean enough that an athlete can tell at a glance which one tells them what. |

#### `coachable_moments` + `evaluate-coachable-moment`

| | |
|---|---|
| What it is | Rule-fired alerts for the coach (not the athlete). Closed vocabulary of rules (`loadSpikePlusInjury`, `lowMoodStreak`, `missedWorkouts`). Surfaced in coach-mode inbox only. |
| What it produces | Templated alert rows (severity + summary + evidence ids). |
| Where it surfaces | Coach mode inbox (CoachView, when isCoachMode=true). |
| Overlap with Read | **None.** Different audience (coach vs athlete), different format (alert vs editorial), different intent (action signal vs daily briefing). |
| Action | **Keep.** This is the dyad's nervous-system feature CLAUDE.md emphasizes. The Daily Read might *cite* coachable moments for the athlete ("worth flagging to your coach: you've mentioned the calf twice this week"), but the coach-facing inbox is its own surface. |
| Severity | **Low** — keep as-is. |

#### `ai_insights.injury_warning` + `injury-early-warning`

| | |
|---|---|
| What it is | Safety-critical injury risk surface. Fires when post-log risk score ≥ 3. Stored separately so it can be retained even when other insights expire. |
| What it produces | Risk score + LLM narrative about the risk. |
| Where it surfaces | Niggles section + Coach tab when coached. |
| Overlap with Read | **Low.** The Daily Read mentions niggles in the paragraph (via the closed body-part vocabulary), but doesn't make injury risk calls. Safety has its own rendering for a reason. |
| Action | **Keep.** Safety surfaces deserve a dedicated channel with their own visibility rules — buried in a paragraph isn't enough. |
| Severity | **Low** — keep as-is. |

#### `plan_adjustments` + `PlanAdjustmentsView`

| | |
|---|---|
| What it is | Granular per-decision plan mutations (soften, swap quality, flag for review). Each row is one adjustment with accept/revert affordances. |
| What it produces | A feed of plan mutations, not narrative. |
| Where it surfaces | Coach tab or Training tab nested view. |
| Overlap with Read | **Low.** The Daily Read might cite an adjustment ("Tuesday's tempo moved to Wednesday — heat") but doesn't replace the feed view. |
| Action | **Keep.** Different artifact (action vs narrative). |
| Severity | **Low** — keep as-is. |

### Group C: surfaces that should consolidate into Read

#### `ai_insights.run_reconciliation` + `post-run-reconciliation` + `post-run-analysis`

| | |
|---|---|
| What it is | Post-run pace delta analysis. Compares prescribed pace to executed pace, factors heat adjustment. |
| What it produces | A short paragraph stored in `ai_insights.content`, type `run_reconciliation`. |
| Where it surfaces | Training tab DayDetailSheet, AND in CoachReadCard's lastRunDelta note kind. |
| Overlap with Read | **High.** This is literally "what the model says about your last run." The Daily Read does this in its paragraph, with workout citation chips, after a quality session re-render. |
| Action | **Stop writing to `ai_insights.run_reconciliation`** once the Daily Read's workout-trigger re-render is reliable. Existing rows become read-only history. DayDetailSheet can fall back to `coach_insight` for per-workout view. |
| Severity | **High** — consolidate. The current state has two model-generated post-run paragraphs being written for the same event into two different tables. |

### Group D: stale, delete now (not future)

#### `coaching_adjustments` table (deprecated)

| | |
|---|---|
| Status | Replaced by `plan_adjustments` in migration `20260417600000`. |
| Still in use? | **Yes — actively read by `CoachReadCard.fetchRecentAdjustments`** (line 184). This is a real bug: the card is showing adjustments from a deprecated table that hasn't been written to in months. |
| Action | Once `CoachReadCard` is deleted (Group A), drop the old table in a migration. |
| Severity | **High** — there's a live UI reading from a dead table. |

#### `TodayHomeView.swift`

| | |
|---|---|
| Status | "Still on disk" per CLAUDE.md. Today tab was removed from active nav. |
| Still in use? | No active references that I found, but didn't audit exhaustively. |
| Action | Delete after grep confirms no callers. Not blocking the Daily Read. |
| Severity | **Low** — orphan file, no urgency. |

#### Legacy `(app)/coach` web route (per CLAUDE.md)

| | |
|---|---|
| Status | CLAUDE.md says "legacy, 207 lines, slated for removal." |
| Still in use? | **Does not exist in the file system.** Already gone. CLAUDE.md is stale on this point. |
| Action | Update CLAUDE.md to remove the reference. |
| Severity | **Low** — documentation hygiene. |

#### Stale `.claude/worktrees/`

| | |
|---|---|
| Status | CLAUDE.md says "read-only artifacts. Do not source files from them." |
| Still in use? | Empty / not present in current scan. |
| Action | Already handled. |
| Severity | **None.** |

---

## Strategic questions to resolve before Phase 4.3

These aren't audit findings; they're product calls the audit surfaces.

**Q1: Is the Coach tab for the AI or for the human coach?**
Today the Coach tab branches on `isCoachMode`: athletes see chat, coaches see roster + inbox. The new Daily Read replaces the chat side for athletes. But athletes who *have* a human coach also see chat today. Where do they see their coach's actual messages? Currently nowhere — coach-to-athlete messaging isn't an app surface. If that's intentional, fine. If not, the Coach tab needs a third mode and the Daily Read fits into it differently.

**Q2: Daily Read vs weekly report — what's the editorial line?**
Both narrative, both editorial, both written by the same model. The defensible split is "current state vs retrospective" — but the Daily Read prompt (v2) doesn't explicitly forbid past-tense summary, and the weekly report's `coaching_narrative` field could easily say "tomorrow's tempo." The prompt for each surface should explicitly tell the model what tense and scope it owns.

**Q3: Is `generate-workout-insight` worth keeping separate from the Daily Read?**
The single-sentence per-workout insight serves "browsing history" use cases. The Daily Read serves "this morning, what's up." If the Daily Read's hydration cache exposes the per-workout context to history views, the separate `coach_insight` field becomes redundant. Worth measuring: how often do athletes actually browse the per-workout insight outside of "today's run just finished"?

**Q4: Should weekly reports move to the Training tab?**
Right now they're triggered from Coach tab modally. If the Daily Read becomes the Coach tab, the weekly retrospective is conceptually a block-review surface — closer to other Training tab artifacts. Moving it would tighten the Coach tab to one thing.

---

## Recommended sequence

1. **Now (before Phase 3.3):** read this audit, decide on Q1-Q4.
2. **Phase 4.3 swap:** new Daily Read replaces `CoachView` on the
   Coach tab. Old chat UI stays on disk as rollback target.
3. **Two weeks of bake.** Verify the Daily Read works for the three
   audiences (plan / coached / self-coached) in production.
4. **Phase 5 cleanup (this audit drives, not the original doc):**
   - Delete `CoachView.swift`, `CoachChatViewModel.swift`, `WelcomeCard`,
     `SuggestionChip` (original doc's scope)
   - Delete `Training/CoachReadCard.swift` and its `CoachReadService`
     (audit's addition — high-confidence delete)
   - Drop `coaching_adjustments` table after confirming no other
     callers (audit's addition)
   - Stop writing to `ai_insights.run_reconciliation` (audit's
     addition — keep the table, retire the write path)
   - Update `weekly-coaching-report` prompt to scope retrospective only
     (audit's addition)
   - Delete `TodayHomeView.swift` after grep confirms it's an orphan
   - Update CLAUDE.md to remove the stale `(app)/coach` route mention
5. **Future (own decision, not this audit):**
   - Consider merging `generate-workout-insight` into the Daily Read's
     hydration path
   - Consider moving weekly report from Coach tab to Training tab

---

## What this audit doesn't cover

- The `coachable_moments` rule set and whether the dyad surface needs
  expansion (separate question; CLAUDE.md treats it as core)
- The coach-portal web surface — out of scope (coach tooling, not
  athlete-facing)
- Whether the four-tab nav itself is right — bigger product question
- Eval harness for the Daily Read — already flagged as a P0 blocker
  in CLAUDE.md
