# Roadmap

Living checklist of what needs to happen between today's state and a real
product coaches will pay for. Treat this as a working document — check items
off, edit thresholds, add what we missed, prune what we abandoned.

**Created:** 2026-05-07
**Last updated:** 2026-05-08
**Current version:** v0.2

---

## Strategic frame (the why behind the what)

The product is a force multiplier for human coaches working with serious
runners. The wedge is the coach-athlete dyad. The differentiator is fusing
quantitative training data with qualitative voice-log signal into actionable
**coachable moments** that human coaches act on.

Core principle, applied everywhere: **AI advises, never acts.** Coaches own
decisions. The product is a force multiplier, not an AI replacement.

---

## Phase 0 — this week (close the loop on what shipped)

The coachable_moments V1 system is built but not verified end-to-end. Until
that's green, don't add new code on top.

- [ ] Apply migration `20260428100000_create_coachable_moments.sql` to local
- [ ] Apply migration `20260502100000_add_suggest_extra_recovery_action.sql` to local
- [ ] Apply both migrations to remote DB
- [ ] Run `docs/specs/coachable_moments_test_data.sql` seed
- [ ] Verify sanity check returns expected counts (8 / 15 / 2)
- [ ] Curl `evaluate-coachable-moment` against the seed athlete
- [ ] Confirm 4 moments fire, one per rule
- [ ] Verify `handled_at` auto-stamps when status flips to `handled`
- [ ] Verify re-fire suppression returns suppressed list, doesn't double-insert
- [ ] Verify RLS — coach sees own moments, others don't
- [ ] **Decide: web vs iOS for the coach client.** This is the biggest
      strategic blocker. Ask 3 prospective coaches if they'd prefer phone or
      laptop for between-session athlete checks.
- [ ] Delete or archive the loser client's coach surfaces
- [x] `git worktree remove` the 7 stale worktrees in `.claude/` (2026-05-07)
- [x] Move or delete `strava-test-pull` out of the production functions path (2026-05-07 — function + iOS debug UI + config.toml entry deleted; Strava credentials still need rotating in dashboard since they remain in git history)
- [ ] **Rotate the Strava OAuth credentials in the Strava developer dashboard** — they were committed to git history before deletion, so deletion alone doesn't invalidate them. Generate fresh client_id + secret, update Supabase secrets, never re-commit.

---

## Phase 1 — next 2-3 weeks (foundations that unblock everything else)

### Operational discipline

- [ ] Adopt RLS-first checklist (already at `docs/conventions/rls-checklist.md`)
- [x] Add link to RLS checklist in PR template (2026-05-07 — `.github/pull_request_template.md` created with Schema/RLS, Prompts/LLM, and Test plan sections)
- [ ] Migration audit — reconcile drift between local and remote
- [ ] Edge function consolidation — merge worst overlap clusters:
  - [ ] `parse-training-plan` + `parse-training-week` + `parse-workout-shorthand` + `parse-workout-structure` → single `parse-training-input` with input-type switch
  - [ ] `adapt-plan` + `adaptive-workout` + `reschedule-plan` + `revert-plan-adjustment` → single `adjust-plan` state machine
  - [ ] `post-run-analysis` + `post-run-reconciliation` → single `process-workout-upload`

### Coaching philosophy (founder work, not engineering)

- [ ] Fill in `docs/coaching/principles.md` sections 1-7:
  - [ ] How I think about training intensity
  - [ ] How I scale by athlete profile
  - [ ] When I deload, and the signals that drive it
  - [ ] How I handle injury mentions
  - [ ] How I handle reported fatigue or low mood
  - [ ] Things I would NEVER tell a recreational runner
  - [ ] Communication voice + 3-5 example messages
- [ ] Add 2-3 forcing questions specific to your coaching practice
- [ ] Bump `principles.md` to v1.0 in the changelog
- [ ] AI prompts can begin referencing the full document (not just the
      forcing-questions section)

### AI eval harness

- [ ] Hand-label 50 voice-log → coaching-insight gold-standard pairs
  - Three are already drafted from tonight's session: tempo+intervals,
    heat-tanked MP run, knee-mention LR
- [ ] Build the harness script: pipeline runs against eval set, scores output
- [ ] Establish baseline score on current production prompts
- [ ] Make eval-no-regress a required CI gate for any prompt change

### Prompt centralization

- [x] Build a thin loader that reads + registers prompts (2026-05-07 — `supabase/functions/_shared/prompt-library.ts` with strict `{{placeholder}}` substitution, 7 unit tests)
- [x] Store prompts as `_shared/prompts/<name>.v<n>.ts` files exporting a `TEMPLATE` string (2026-05-07 — switched from `.txt` after realizing Supabase's edge-function bundler traces ES imports, not arbitrary disk reads; `.ts` files bundle atomically with the function)
- [ ] Move every inline LLM prompt out of edge functions (17/26 done as of 2026-05-08 — fully migrated: extracted to `_shared/prompts/<name>.v1.ts`, registered in `prompt-library.ts` REGISTRY, edge-function call site refactored to `loadPrompt(...)`):
  - biomechanics-analysis, block-review, fitness-predictor, injury-analysis, post-run-analysis, race-readiness, weekly-plan-review, injury-early-warning, process-check-in, race-intel, reschedule-plan, training-analysis, form-check-analysis, generate-workout-insight, parse-workout-structure, parse-training-week, weekly-coaching-report
  - **Remaining (9 prompts across 6 functions):** parse-training-plan (1), custom-plan-builder (1), generate-training-plan (2), process-training-memo (1), coaching-agent (4)
  - Note: parse-* and adapt-* are slated for consolidation per Phase 1 § "Edge function consolidation"; migrating each prompt now still pays — the consolidated function ships with versioned prompts from day one
- [ ] Update each edge function to load via the loader (covered above — when a prompt's row is checked, both extraction AND loader-wiring are complete)

### LLM observability

- [ ] Wrap LLM clients in a logging layer (prompt, output, model, latency, cost)
- [ ] Write to a new `llm_calls` table
- [ ] Weekly query: cost-per-athlete, fallback frequency, error rate
- [ ] Alerting on cost spikes or error rate increases

---

## Phase 2 — next month (AI quality lift)

### Memory + theme system

- [ ] Wire `extractMemories()` into `process-check-in` so voice logs feed memory
      (the "Fix 1" — small, high-leverage)
- [ ] Add `recurring_themes` field to `athlete_state` migration
- [ ] Build `extract-recurring-themes` edge function
  - [ ] Input: athlete_user_id, window_days (default 14), source (cron|on_demand)
  - [ ] Pulls voice logs in window, calls Sonnet for theme extraction
  - [ ] Writes to `athlete_state.recurring_themes`
  - [ ] Returns themes in response
- [ ] Schedule weekly cron Monday 6am UTC over all active athletes
- [ ] Wire coaching-agent intent classifier to call it on-demand for
      self-reflection questions
- [ ] Add pain-timing detection to `extractMemories` regex
      (during-run / end-of-run / morning-after — three different injuries)

### Coaching-agent quality

- [ ] Switch `complex` (and likely `moderate`) path off Gemini Flash Lite
      to Claude Sonnet or GPT-4-class
- [ ] Verify `athlete_state` freshness — query `last_updated_at` distribution
- [ ] Fix any state-update events that aren't firing reliably
- [ ] Add few-shot examples to system prompt drawn from filled-in `principles.md`
      (especially the forcing-questions section)
- [ ] Audit which context blocks fire empty vs full
- [ ] Trim the kitchen-sink concatenation to 4-6 most-relevant blocks
- [ ] Add output validation post-pass:
  - Catch "stop training" / "see a doctor" / hallucinated paces
  - Route flagged outputs to coach review instead of athlete
  - Hard cap response length (180 words)

---

## Phase 3 — coach surface (parallel track, weeks 2-6)

Note: gated on Phase 0's coach client decision.

- [ ] Triage dashboard MVP on chosen client
  - [ ] Roster table: `Athlete | Attention Score | Last Signal | Last Workout | Days Since Check-in`
  - [ ] Sorted by attention score descending
  - [ ] Severity color stripe
- [ ] Coachable moment card UI: severity, summary, "Take Action" + "Dismiss"
- [ ] Athlete detail view with source logs highlighted (linked via `source_log_ids`)
- [ ] Real-time triggering: Postgres trigger on `training_logs` INSERT that
      auto-fires the evaluator (or daily cron, or both)
- [ ] Coach-side notification surface (push / email / inbox badge) for `high` severity
- [ ] Track coach actions per moment (handled / dismissed / ignored) — the
      eval signal for rule quality

---

## Phase 4 — athlete surface (after coach surface stabilizes)

- [ ] Daily Card: one screen, today's workout, coach note, weather, paces
- [ ] Voice log onboarding flow that hand-holds the first 3 logs
- [ ] Athlete-facing weekly lookback (their version of the coach report —
      emotional vocabulary, not data dump)
- [ ] "I noticed" loop: 1-2 athlete-facing pattern observations per week,
      surfaced as reflection prompts (not advice)
- [ ] Coach voice notes: athlete voice-logs → coach gets card → coach
      records 30-second reply → athlete hears it in coach's voice
- [ ] Race-day ribbon / countdown surface
- [ ] Mood-effort calibration mirror (when subjective and objective disagree)

---

## Phase 5 — GPS parsing + Terra (bigger bet, weeks 4-10)

- [ ] Terra account setup, webhook registered, signing secret stored in vault
- [ ] New `terra-webhook` edge function:
  - [ ] HMAC signature verify (non-negotiable)
  - [ ] Idempotent insert into new `terra_raw_activities` table
- [ ] New `parse-terra-activity` function:
  - [ ] Layer 1: segment detection (trust FIT laps when present, fallback algorithmic)
  - [ ] Layer 2: workout type classification
- [ ] Decide: new `parsed_workouts` table vs extend `training_logs`
- [ ] Layer 3: plan reconciliation — compare segments to scheduled workout
- [ ] Layer 4: fitness inference — feed parsed data into `fitness-predictor`
- [ ] New rule: `workout_execution_drift` — fires when prescribed pace
      missed by >5% on key sessions, or recovery drift > 50%
- [ ] Athlete onboarding flow: connect Garmin/Strava via Terra OAuth
- [ ] Migrate or deprecate `strava-test-pull`

---

## Phase 6 — tech debt cleanup (run alongside feature work)

- [ ] Edge function consolidation 40 → ~20 (covered partially in Phase 1)
- [ ] Test coverage: unit test on each rule, integration test on full evaluator
- [ ] `athlete_state` / `athlete_profiles` / `athlete_pace_profiles` boundary
      audit — merge or document
- [ ] Mood column: keep TEXT or migrate to numeric — decide
- [ ] Convert any remaining "Allow all" RLS policies to real policies
- [ ] Delete `_archived/` and `_deprecated/` directories once stable

---

## Pre-design-partner gates

Must clear all of these before showing to coaches.

- [ ] One coach client committed; the other archived (Phase 0)
- [ ] Triage dashboard live with real data (Phase 3)
- [ ] Coachable_moments fires correctly against 30+ days of real production
      data (calibration verified — not just seed)
- [ ] AI quality eval has a baseline score (Phase 1)
- [ ] Coaching philosophy doc at v1.0 — your real content, not skeleton (Phase 1)
- [ ] 3-5 coaches identified to recruit, each with 5-15 athletes
- [ ] Onboarding flow for design partners: how a coach links athletes, sees
      their roster, takes action on first moment
- [ ] Privacy/consent language clear for athletes whose voice logs feed
      coach moments

---

## Pre-paying-customer gates

Must clear all of these before charging money.

- [ ] At least 2 design partner pilots completed (8-12 weeks each)
- [ ] Coaches report concrete value: at least one example each of "I caught
      X because of this tool"
- [ ] Athlete retention measurable: athletes who use the tool log more
      consistently than control
- [ ] AI quality eval score above defined bar (define bar once baseline exists)
- [ ] Production reliability tracked and acceptable: uptime, error rates,
      cost per athlete
- [ ] Pricing model decided (per coach, per athlete, freemium, hybrid)
- [ ] Coach billing flow built
- [ ] Cancel / refund flow built
- [ ] Customer support channel established
- [ ] Terms of service + privacy policy reviewed

---

## Sequencing reality

- **Phase 0 → demo-able state in 3-4 weeks.** Coach can sign in, see real
  cards from real data on a chosen client. The product becomes a thing
  you can put in front of someone.
- **Phase 1 + Phase 2 → AI quality good enough for design partners** — another
  3-4 weeks beyond Phase 0. Coaching philosophy filled in, eval harness
  running, AI no longer feels generic.
- **Phase 3 + Phase 4 → coach + athlete surfaces real and coherent** — runs
  in parallel; targets shipping ahead of design partner pilots.
- **Phase 5 (GPS parsing) is the moat work.** 6-10 weeks parallel; do not
  gate design partner pilots on it. The richer pace-strategy / execution
  context lands in v2 of the design partner experience.
- **Phase 6 (tech debt) is continuous.** Don't carve out separate sprints
  for it; bake into every feature week.

---

## Changelog

- **v0.2** (2026-05-08) — Reconciled with actual work shipped. Phase 0:
  worktrees cleaned, `strava-test-pull` deleted (credential rotation added
  as a follow-up item — deletion ≠ invalidation when secrets are in git
  history). Phase 1: PR template live with Schema/RLS + Prompts/LLM + Test
  plan sections; `prompt-library.ts` shipped with strict `{{placeholder}}`
  substitution and 7 unit tests; prompt storage convention switched from
  `.txt` to `.ts` (Supabase edge-function bundler traces ES imports, not
  arbitrary disk reads — `.ts` bundles atomically with the function).
  Prompt extraction now at 9/22; 4 registered in `prompt-library.ts`,
  5 extracted but pending registration.
- **v0.1** (2026-05-07) — Initial roadmap committed. Captures everything
  discussed through coachable_moments V1 + AI quality + coach UX + GPS
  parsing + design partner gates. Phase 0 verification still outstanding.
