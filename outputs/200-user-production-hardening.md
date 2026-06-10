# ADR: Minimum-viable production hardening for 200 users

**Status:** Proposed
**Date:** 2026-05-22
**Deciders:** Rio (founder); backend lead

## Context

The product is moving from internal beta toward opening the gates to ~200
coach-athlete dyads. CLAUDE.md and `outputs/production-readiness-rundown.md`
enumerate the known production blockers; addressing all of them is several
weeks of work the team doesn't have. The question is: what is the **minimum
set of changes** that lets 200 users on without risking (a) irreversible
data loss, (b) a security incident, or (c) silent degradation of the wedge
("AI advises, never acts").

**Forces at play:**

- 200 users is well under any raw-load ceiling on Supabase Pro. Scale isn't
  the problem; quality and reliability are.
- The wedge depends on testable AI behavior on a small number of high-stakes
  prompts (niggles classifier; `reschedule-plan`). A regression here causes
  athlete harm, not embarrassment.
- Data continuity *is* the value proposition. A bad migration without PITR
  loses days of voice logs and training logs.
- Hard rule #3 forbids LLM prompt changes without eval coverage. The harness
  doesn't exist. This is currently unenforced — a foot-gun whose blast
  radius grows linearly with users.
- Hard rule #4 requires all `coachable_moments` inserts to go through
  service-role edge functions. That only holds if the service key isn't
  bundled where a curious athlete can find it.
- Team is small. Cosmetic improvements (pooler swap, edge function
  consolidation, full CI) deepen the moat but don't block launch at this
  user count.

## Decision

Ship the six changes below before opening to 200 users. Defer everything
else, but record tripwires so the deferred list stays honest.

> Caveat: this ADR is drafted off CLAUDE.md, not a repo audit. A 30-minute
> verification pass should confirm none of these are already shipped.

### Tier 0 — data integrity & security (this week, ~1 dev-day total)

**1. Enable Supabase PITR.** Tier up to Pro if not already, turn on
point-in-time recovery. Without it, the worst-case rollback is last night's
snapshot, which costs a day of `voice_logs` and `training_log` — the rawest
form of the product's value.

**2. Audit service-role key exposure.** Grep every repo for
`SUPABASE_SERVICE_ROLE`. It must appear only in `supabase/functions/*` envs
and the Railway ML service env. If it's anywhere a client bundle reaches
(iOS, Next.js client code, a committed `.env.local`), rotate today. Without
this, hard rule #4 is theater.

**3. Verify `current_coach_id()` hardening.** Confirm
`SET search_path = public, pg_temp` is pinned on the function and that it's
owned by `postgres`, not `authenticator`. A misconfigured SECURITY DEFINER
function is a privilege escalation surface.

### Tier 1 — wedge integrity (this month, ~1 dev-week total)

**4. Thin eval harness for the two prompts that can cause harm.**

- Niggles classifier: ~20 golden inputs. Asserts: closed body-part
  vocabulary respected; no diagnosis terms (no "ITBS", "tendinitis",
  etc.); no action recommendations ("rest", "ice"); athlete's wording
  preserved verbatim.
- `reschedule-plan`: ~20 golden inputs. Asserts: every emitted code is in
  `WORKOUT_CODES_BY_DAY`; output writes only to `plan_adjustments` with
  `auto_applied: false`; respects the once-per-day rate limit.

Runs on every PR that touches `_shared/rules/*`, prompt strings, or
function source. This unblocks hard rule #3. It does not need to be
elegant — it needs to **exist**.

**5. Add the missing real-time synthesis trigger.** One migration: on
`training_log` insert, fire `evaluate-coachable-moment`. Mirror the existing
`generate-workout-insight` trigger from `20260428110000`. Without this,
the coachable-moments inbox — the surface the entire wedge points at —
silently drifts off-fresh as data volume grows.

**6. Lock auth defaults.** Require email confirmation; enable password-reset
rate limiting; sanity-check JWT expiry. 30 minutes in the Supabase
dashboard. None of this blocks anything; all of it removes a class of
abuse-vector that gets more attractive as the product gets more public.

## Options considered

### Option A: Minimum-viable hardening (this proposal)

| Dimension | Assessment |
|---|---|
| Complexity | Low — 3 config changes, 1 small migration, 1 small test harness |
| Effort | ~1 dev-day Tier 0, ~1 dev-week Tier 1 |
| Coverage | Closes irreversible failure modes; leaves reversible ones |
| Scalability headroom | None added — 200 users fits in the current envelope |

**Pros.** Ships fast. Each item is independently shippable. Restores the
integrity of the two hard rules (#3, #4) currently being honored on faith.
Buys time without buying problems.

**Cons.** No CI safety net for non-LLM regressions. No connection pool
headroom for a surge. No log drain — incident forensics still painful.
The strategic coach-client question is still open.

### Option B: Full production-readiness pass

| Dimension | Assessment |
|---|---|
| Complexity | High — CI infra, log drain, pooler migration, edge function consolidation, strategic coach-client call |
| Effort | 4–6 dev-weeks |
| Coverage | Closes everything `outputs/production-readiness-rundown.md` flags |
| Scalability headroom | 6–12 months before re-evaluation |

**Pros.** Sustainable. Fewer "next time we hit this" surprises. Team
velocity improves once CI exists.

**Cons.** Delays the 200-user milestone by months. Several items (pooler
swap, function consolidation) aren't load-justified at 200 users — they're
load-justified at 2,000. Doing them now is optimizing for a problem you
don't have yet, while the wedge feature ships untested.

### Option C: Open the gates now, fix forward

| Dimension | Assessment |
|---|---|
| Complexity | None up front |
| Effort | Zero up front; very high per-incident |
| Coverage | None |
| Scalability headroom | Negative — incidents compound |

**Pros.** Fastest.

**Cons.** One bad migration costs a week of training data with no rollback.
One service-role leak exposes every athlete. One niggles classifier
regression and a coach reads "ITBS" as authoritative. Reputation cost on
any of these is not recoverable. Asymmetric to the upside of "ship now."

## Trade-off analysis

The real choice is A vs B. Option C fails on the irreversibility
asymmetry: a day enabling PITR vs. losing a week of athlete data is not a
close call.

Option B is what you'd do with a series-A team. With the current team it
means another quarter of pre-launch. The value of having 200 athletes
generating real signal — for the wedge product, for the coachable-moments
rules library, for actually validating "AI advises, never acts" in
production — is higher than the marginal reliability gain of pooler + log
drain + edge function consolidation at this user count.

The non-obvious risk of Option A is that the deferred list grows teeth
silently. The hedge is **tripwires**: every deferred item gets a metric or
threshold that, when crossed, surfaces it for re-evaluation. See
*Tripwires for deferred items* below.

## Consequences

**What becomes easier**
- Hard rules #3 and #4 enforceable for the first time.
- "Worst-case data loss" goes from days to minutes.
- Shipping LLM prompt changes becomes confident, not nerve-wracking.

**What becomes harder**
- The eval harness has to be maintained. Adding it without a culture of
  writing golden cases creates a graveyard.
- Non-LLM regressions can still ship — there's still no CI.

**What we'll need to revisit**
- Coach client consolidation (iOS `Coaching/` vs web `(app)/coach` vs
  `(app)/coach-portal/*`). Strategic call, not config.
- Edge function `parse-*` cluster. Cosmetic until it isn't.
- Real CI (typecheck + RLS smoke test) once team capacity allows.
- Web → transaction-mode pooler URL when SSR latency dictates.
- Log retention upgrade or drain to Axiom/Datadog when an incident makes
  the 1-day default painful.

## Tripwires for deferred items

| Deferred item | Tripwire that revives it |
|---|---|
| CI / typecheck | First time a typo migration ships to prod |
| Web pooler swap | Web SSR P95 latency > 800ms three days running, or `remaining connection slots` errors |
| Edge function consolidation | When `parse-*` has > 5 functions, or two of them diverge in shared logic |
| Log retention | First incident where 1-day window isn't enough |
| Coach client consolidation | Next deep feature on the coach surface — make the call before writing the spec |

## Action items

| # | Item | Owner | Effort |
|---|---|---|---|
| 1 | Verify nothing on this list is already done (repo audit) | Rio | 30 min |
| 2 | Enable PITR on Supabase (tier up if needed) | Rio | 15 min |
| 3 | Grep `SUPABASE_SERVICE_ROLE` across repos; rotate if leaked | Rio | 30 min |
| 4 | Verify `current_coach_id()` `search_path` + ownership | Rio | 30 min |
| 5 | Write `niggles_classifier.golden.json` + harness runner | Backend | 1 day |
| 6 | Write `reschedule_plan.golden.json` + harness runner | Backend | 1 day |
| 7 | Wire GitHub Action: run harness on PR touching prompts/rules | Backend | half-day |
| 8 | Migration: `training_log` insert → `evaluate-coachable-moment` | Backend | 2 hours |
| 9 | Lock auth: email confirm, rate limits, JWT expiry sanity | Rio | 30 min |
| 10 | Document tripwires for deferred items (this ADR's table) | Rio | done |

## What is explicitly not in this ADR

- CI beyond the LLM eval harness
- Pooler migration
- Edge function consolidation
- Log retention upgrade / log drain
- Coach client consolidation decision
- Public landing page rewrite
- Legal docs cleanup

These are real and need owning. They are not necessary at 200 users.
