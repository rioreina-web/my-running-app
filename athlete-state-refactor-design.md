# athlete-state.ts — Refactor Design

**Companion to:** `adaptive-plan-loop-design.md`, `training-system-design-v2.md`
**Source module:** `supabase/functions/_shared/athlete-state.ts` (1,481 LOC)
**Backing table:** `athlete_state` (migration `20260410200000_create_athlete_state.sql`)
**Consumers:** 12 edge functions read via `getOrBuildAthleteState` → `stateToPromptContext`.

---

## 1. Framing

Today, `athlete-state.ts` is a single file doing four distinct jobs that shouldn't share a function body: (a) DB access, (b) slice computation (10+ distinct algorithmic concerns), (c) orchestration + caching, (d) prompt rendering. The audit identified 12 risks. Three of them are **correctness bugs** I'd ship *this week* regardless of any refactor; the rest fall naturally out of a proper split.

The design below separates these concerns, adds event-driven invalidation (the V2 plan called for it; it never landed), aligns pace zones with the newly-shipped `athlete_pace_profiles` table, and removes a silently-conflicting feature (race-history inference).

---

## 2. Requirements

### Functional
- Provide a read-only `AthleteState` object to any edge function, on demand, within ~50ms p50.
- Keep state fresh after ingestion events: training log insert, check-in, pace-profile update, injury update, scheduled-workout change, goal change.
- Render a bounded prompt block (≤400 tokens) for LLM consumption.

### Non-functional
- **No tenant leakage.** Ever. (Today: goal filter risk — P0.)
- **Idempotent rebuilds.** A race between callers cannot corrupt state. (Today: 10-parallel-rebuild thundering herd.)
- **Event-driven** invalidation, not a 60-minute wall clock.
- **Testable.** Each slice builder is a pure function of its inputs.
- **Aligned with other V2 systems.** Pace zones come from `athlete_pace_profiles`, not hardcoded multipliers.

### Constraints
- Supabase Edge Functions (Deno TS). Postgres 15+. No new infra beyond what's already in the stack.
- 12 consumers already wired; API surface must stay compatible during migration.

---

## 3. Target Architecture

```
supabase/functions/_shared/athlete-state/
├── index.ts                      # public surface, barrel export
├── types.ts                      # AthleteState interface (single source of truth)
├── service.ts                    # getAthleteState, getOrBuild*, update*
├── orchestrator.ts               # rebuild() — runs needed builders, upserts
├── lock.ts                       # pg_advisory_xact_lock wrapper
├── invalidation.ts               # event → dirty slices mapping
├── prompt.ts                     # stateToPromptContext, with token budget
├── queries/                      # DB reads, one per slice's needs
│   ├── trainingLogs.ts
│   ├── injuries.ts
│   ├── fitnessSnapshots.ts
│   ├── goals.ts
│   ├── plans.ts
│   └── scheduled.ts
├── builders/                     # pure fn: (raw inputs) → slice
│   ├── buildIdentity.ts          # profile, goal, phase
│   ├── buildLoadMetrics.ts       # 7d/28d, ACWR, monotony, strain
│   ├── buildMoodTrend.ts         # check-ins + voice logs
│   ├── buildPaceZones.ts         # reads athlete_pace_profiles (v2)
│   ├── buildRecentWorkouts.ts
│   ├── buildScheduled.ts
│   ├── buildPossibleInjuries.ts  # keyword scan with guardrails
│   ├── buildBlocks.ts            # 4-week rollups
│   ├── buildTrajectory.ts        # fitness_trend enum
│   └── (buildRaceHistory — REMOVED, see §4.3)
├── shared/
│   ├── dedup.ts                  # cross-source dedup (ONE implementation)
│   ├── sessions.ts               # groupIntoSessions
│   └── format.ts                 # pace/time formatters
└── __tests__/                    # one file per builder, pure-fn tests
```

### Public API (unchanged surface, new implementation)
```ts
export type { AthleteState } from "./types.ts";
export { getAthleteState } from "./service.ts";
export { getOrBuildAthleteState } from "./service.ts";
export { updateAthleteState } from "./service.ts";
export { rebuildAthleteState } from "./orchestrator.ts";
export { stateToPromptContext } from "./prompt.ts";
```

Every current consumer imports through `index.ts`, so the split is transparent.

### Data flow — cold read (cache miss)

```
edge fn
  │
  ▼
service.getOrBuildAthleteState(user_id)
  │
  ├─► queries.getState(user_id) ──► athlete_state ──► null (miss)
  │
  ▼
orchestrator.rebuild(user_id, dirty_slices=ALL)
  │
  ├─► lock.acquire("athlete_state_" + user_id)    # pg_advisory_xact_lock
  │
  ├─► parallel: run only needed query batches
  │
  ├─► parallel: run builders for dirty slices, each pure:
  │     (raw rows, existing_state) => Partial<AthleteState>
  │
  ├─► merge slices into full state
  │
  ├─► queries.upsert(state)
  │
  └─► lock.release
```

### Data flow — event-driven invalidation

```
training_logs INSERT trigger
  │
  └─► pg_net → /athlete-state-invalidate { user_id, event: 'log.insert' }
       │
       ▼
      invalidation.ts  maps event → slices:
         load_metrics, recent_workouts, trajectory,
         blocks, possible_injuries
       │
       ▼
      queries.markDirty(user_id, slices)   # UPSERT to athlete_state_dirty
       │
       ▼
      orchestrator.rebuild(user_id, dirty_slices)
       (runs ONLY the invalidated builders)
```

New table:
```sql
CREATE TABLE athlete_state_dirty (
  user_id uuid PRIMARY KEY REFERENCES auth.users,
  slices text[] NOT NULL,        -- array of slice names
  updated_at timestamptz NOT NULL DEFAULT now()
);
```

Rebuild clears its slices atomically at the end (`UPDATE … SET slices = array_remove(slices, each) …`).

---

## 4. Risk-by-Risk Decisions

### P0 — correctness bugs (ship this week, before any refactor)

**R3. Goal filter admits `user_id IS NULL` rows.**
Single-line fix. Add `.not('user_id', 'is', null)` to the user_goals query. Then audit every other shared query for the same pattern. This is a tenant-leak class bug; it gets fixed *today*.

**R4. Rebuild races.**
Wrap `rebuildAthleteState` body in `pg_advisory_xact_lock(hashtext('athlete_state:' || user_id))`. Second caller on the same key blocks (ok — they'll pick up the finished state). Ten parallel edge-fn invocations stop clobbering.

**R6. TODOs shipping in prod with null outputs.**
Three fields promise data and deliver `null`/"maintaining":
- `monotony_7d`: well-defined formula (stdev / mean of daily TRIMP over 7 days). Implement in `buildLoadMetrics`.
- `strain_7d`: total weekly TRIMP. Implement.
- `week_compliance_pct`: `completed_count / scheduled_count` on the current week. Implement in `buildScheduled` by joining scheduled_workouts × training_logs.
- `fitness_trend`: implement in `buildTrajectory` as a proper enum projection of the existing trajectory framing.

If any of these is deferred, **remove the field from the schema and the prompt**. Never ship a field whose purpose is "LLM sees null and hallucinates something."

### P1 — structural (refactor body)

**R1. 1,000-LOC rebuild.** → split into 10 builders per §3.
**R2. Duplicate dedup loop.** → one `shared/dedup.ts` used in two places.
**R5. No event-driven invalidation.** → new `athlete_state_dirty` table + triggers, per §3.

### P2 — accuracy and safety

**R7. Hardcoded pace multipliers.**
`buildPaceZones` becomes:
1. Read `athlete_pace_profiles` for the user (now exists per `20260417100000_athlete_pace_profiles.sql`).
2. If present: use those paces directly. Done.
3. If absent: set `pace_zones = null` and add `pace_zones_unset: true` flag to state. `prompt.ts` surfaces "Athlete hasn't set goal yet — don't prescribe paces."
4. **Delete** the hardcoded 1.35/1.28/1.21/1.14/1.07 multipliers from the module. No fallback. This aligns with the no-hardcoded-paces memory.

**R8. Race-history regex spoofing.**
The feature itself conflicts with the no-race-inference constraint. Regex-matching notes will always be exploitable. **Remove `race_history` from the state entirely.** Replace with an explicit `confirmed_races` field sourced only from training_logs where `workout_type = 'race'` *and* a structured `race_result` field is populated. Notes-scan is out.

Migration implication: drop the `race_history` column (or leave it in schema and stop populating it, marked deprecated).

**R9. Weak trajectory approximation.**
`priorBlockAvg = weeklyAvg28d − rolling7d/4` is a napkin approximation. Replace with explicit windowed query: "average weekly miles between days 21 and 28 before now." One more query; marginal cost.

**R10. Magic condition adjustments.**
The +3% hot / +1.5% humid multipliers exist in isolation. Either:
- Port to the same Emy's-calculator logic we just ported for pace-heat adjustments (`_shared/pace-heat.ts` from Prompt 2.2 of the adaptive plan loop), and cite the composite-score source in comments.
- Or remove the adjusted_time_for_race feature entirely if race_history is being removed (R8) — this concern goes away.

**R11. Unbounded prompt context.**
Enforce a token budget in `prompt.ts`. Each section has a cap; sections are truncated or pruned in priority order:
```
Identity          40 tokens
Load              40
Fitness (paces)   40
Injury            40
Schedule (next 2) 40
Recent workouts   80   (top 3, truncated descriptions)
Mood trend        30
Trajectory        30
Blocks            40   (last 3 only)
Confirmed races   40   (last 3 only, if any)
─────────────────────
Total             420 tokens hard cap
```
`prompt.ts` measures output and drops lowest-priority sections if over budget. Log a warning in Sentry if truncation kicks in, because it means we've drifted from the stated envelope.

**R12. Race detection scope.**
If R8 is accepted (remove race regex entirely), R12 goes away. If not, it becomes a proper i18n + event-type issue worth a separate spec.

---

## 5. Migration Path

### Week 1 — P0 correctness
- [ ] Ship the goal user_id filter fix (R3). Hotfix priority.
- [ ] Add advisory lock around rebuild (R4).
- [ ] Implement monotony_7d, strain_7d, week_compliance_pct, fitness_trend. Or remove them from the schema + prompt.
- [ ] Add a regression test that two parallel `getOrBuildAthleteState` calls for the same user produce one `rebuild` invocation.

*Shippable after this week even if the refactor never happens: no more tenant leaks, no more thundering herd, no more silently-null promised fields.*

### Week 2 — Structural split (the "10-file" refactor)
- [ ] Create new folder structure per §3.
- [ ] Move `AthleteState` interface to `types.ts`.
- [ ] Extract shared helpers (`dedup`, `sessions`, `format`).
- [ ] Move each slice's compute into its own builder file, preserving behavior exactly.
- [ ] Write unit tests for each builder against recorded fixtures (1 per builder minimum).
- [ ] `orchestrator.rebuild(user_id, dirty=ALL)` replicates current behavior.
- [ ] Keep `index.ts` exports identical — zero consumer changes.

### Week 3 — Event-driven invalidation
- [ ] `athlete_state_dirty` table + RLS (service-role write only, users read their own if ever needed).
- [ ] Postgres triggers on: `training_logs` (insert/update), `injuries` (insert/update), `athlete_pace_profiles` (upsert), `scheduled_workouts` (insert/update/delete), `user_goals` (insert/update), `athlete_profiles` (update).
- [ ] Each trigger emits via `pg_net.http_post` to `athlete-state-invalidate` edge fn with `{ user_id, event }`.
- [ ] `invalidation.ts` maps events → slice names; `queries.markDirty` updates the table.
- [ ] `orchestrator.rebuild` now takes `dirty_slices`; runs only those builders; clears them on success.
- [ ] `getOrBuildAthleteState` first checks `athlete_state_dirty` — if any slices dirty, rebuild those; else serve cached state.
- [ ] Drop the 60-minute time-based staleness gate (keep as 24-hour safety net only).

### Week 4 — P2 cleanup
- [ ] Remove race-history regex (R8, R12). Drop `race_history` column or mark deprecated.
- [ ] Rewire `buildPaceZones` to `athlete_pace_profiles` (R7). Delete hardcoded multipliers.
- [ ] Replace trajectory approximation with an explicit query window (R9).
- [ ] Either port or remove condition-adjustment heuristics (R10).
- [ ] Implement `prompt.ts` token budget enforcement (R11).

---

## 6. Scale and Reliability

### Load
12 consumers × ~N daily calls per user × ~1K users at current scale = ~12K invocations/day of `getOrBuildAthleteState`. Vast majority hit cached state.

**After refactor:**
- Cached read: single `maybeSingle()` against `athlete_state` table. ~5-15ms.
- Dirty-slice rebuild: 1-3 builders run in parallel. ~50-150ms.
- Full cold rebuild: 10 builders, ~200-400ms. Rare.

Well within edge-function budgets.

### Reliability
- **Lock failure mode.** If advisory lock times out (shouldn't happen at this scale), caller falls back to stale state with a warning. Never throw.
- **Builder failure mode.** If one builder throws, log to Sentry, preserve the previous slice value in state (don't null it). The whole rebuild does not fail on one bad slice.
- **Trigger failure mode.** If `pg_net` invocation fails, the dirty row is still written — next natural rebuild will catch up. Eventually consistent.

### Monitoring
- Metric per builder: p50/p95 latency.
- Metric per slice: invalidation rate per user per day (is one event type causing storms?).
- Alert: `athlete_state_dirty` rows older than 2 hours (invalidation pipeline is broken).
- Alert: prompt budget truncation rate > 5% of calls (the state has drifted from envelope).

---

## 7. Trade-off Analysis

| Decision | Chosen | Alternative | Why |
|---|---|---|---|
| Split into file-per-builder | Yes | Keep monolith with internal region comments | Testability is the dominant concern. Monolith test story is hopeless. |
| Event-driven invalidation | Yes | Keep 60-min wall-clock staleness | V2 plan required event-driven; stale data is a silent quality killer; the plumbing cost is modest. |
| Remove race-history entirely | Yes | Add more keyword gates | Conflict with no-race-inference constraint is structural; regex hardening is a treadmill. |
| Pace zones from `athlete_pace_profiles` only | Yes | Fallback to hardcoded multipliers | No-hardcoded-paces constraint. Better to surface "unset" than to quietly prescribe wrong paces. |
| Advisory lock (not row lock) | Yes | `SELECT FOR UPDATE` on athlete_state | Rebuilds run before the row exists (cold state). Advisory is the cleanest semantic. |
| Dirty-slice table (not NOTIFY) | Yes | Postgres NOTIFY to a listener | Cowork/edge fns are stateless; no persistent listener. Dirty table survives restarts and is queryable. |
| Zero API-surface change | Yes | Break the API to force consumer migration | 12 consumers + ongoing feature work = too much surface for a refactor. Keep the surface; change the guts. |

### Non-goals at this stage
- Partial-slice reads (a consumer asking for only the load slice). Useful later; not needed to fix the P0 bugs.
- Replacing `athlete_state` with a projection view over other tables. Interesting long-term (would eliminate the cache entirely), but that's a materialized-view discussion and a larger architectural shift.
- Porting to a separate service. Not warranted at this scale.

---

## 8. Testing Strategy

### Unit (each builder)
- Snapshot: run builder with fixture input, assert output matches recorded snapshot.
- Edge cases per builder: empty inputs, missing optional rows, single-row, outlier values.
- Dedup: assert that overlapping log sources collapse to highest-priority source.
- Pace zones: assert that missing `athlete_pace_profiles` yields `null` + `pace_zones_unset = true`, not a fabricated zone.
- Trajectory: assert enum output against crafted load histories (returning / peaking / building / etc.).

### Integration
- Cold build: fresh user → full rebuild produces expected state in < 500ms against real-ish fixtures.
- Concurrent callers: 10 parallel `getOrBuildAthleteState` on the same user → exactly one rebuild runs; others block-then-serve.
- Invalidation flow: insert a `training_logs` row → dirty row appears within 2s → next call triggers a 3-slice rebuild, not a full one.
- Tenant isolation: fixture with orphaned `user_goals` (user_id=null) → does not appear in any user's state.

### Contract (consumer-facing)
- `AthleteState` interface: one test per consumer to assert the fields each actually reads are never missing from a populated state.
- `stateToPromptContext`: property test — no matter the input state, output is ≤ 420 tokens (measured with tokenizer).

---

## 9. Open Questions

1. **Race history deletion** — does any downstream feature read `race_history` today? If yes, we need a replacement (explicit `confirmed_races`) in place before removal. If no, pure deletion.
2. **Token budget enforcement at 420** — is that the right number for your coaching-agent's overall prompt budget? Should match whatever `coach_context` (Phase 1 of the v2 training design) reserves.
3. **Invalidation — synchronous vs. async.** A trigger → pg_net call adds ~10-50ms to every `training_logs` insert. Acceptable? Alternative: a periodic worker that polls `athlete_state_dirty` (adds latency to freshness, removes latency from inserts).
4. **Hardcoded condition adjustments (R10)** — do you want to keep the "race time with conditions" adjustment feature at all? If race_history is removed, this may be moot.
5. **Versioning the `AthleteState` schema.** When we remove `race_history`, do consumers get a deprecation warning, or a hard remove? I'd warn for one release, then hard-remove.

---

## 10. Execution Prompts (condensed — ready to hand to Claude Code)

**P1.1 (P0 hotfix):** *In `supabase/functions/_shared/athlete-state.ts` lines 1164-1167, add `.not('user_id', 'is', null)` to the user_goals query. Grep the file for all `.from('user_goals')` and `.from('athlete_profiles')` calls and add the same filter. Ship same day.*

**P1.2 (P0 hotfix):** *Wrap the body of `rebuildAthleteState` (lines 248-1251) in a `pg_advisory_xact_lock(hashtext('athlete_state:' || user_id))` via a Supabase RPC wrapper. Add an integration test that 10 parallel `getOrBuildAthleteState` calls for the same cold user result in exactly one rebuild.*

**P1.3 (P0 feature completion):** *Implement the four null-today fields: `monotony_7d`, `strain_7d`, `week_compliance_pct`, `fitness_trend`. Or, if deferring: remove them from `AthleteState` and the migration.*

**P2.1-P2.10 (structural refactor):** *Split the file per §3 of `athlete-state-refactor-design.md`. One PR per builder extraction. Each PR includes the builder's unit tests. Keep `index.ts` exports byte-identical; no consumer changes.*

**P3.1 (invalidation table):** *New migration: `athlete_state_dirty` table with (user_id, slices text[], updated_at).*

**P3.2 (triggers + edge fn):** *Postgres triggers on the 6 event sources; new edge fn `athlete-state-invalidate` that maps events to slices and UPSERTs to `athlete_state_dirty`.*

**P3.3 (orchestrator):** *Rewrite `orchestrator.rebuild(user_id, dirty_slices)` to run only the named builders. `getOrBuildAthleteState` checks dirty table first.*

**P4.1 (pace zones):** *Rewrite `buildPaceZones` to read `athlete_pace_profiles`. Delete hardcoded multipliers at old lines 541-550. Add `pace_zones_unset` flag when profile missing.*

**P4.2 (race history removal):** *Delete `buildRaceHistory` and remove `race_history` field from `AthleteState`. Drop column in a follow-up migration after one release cycle.*

**P4.3 (prompt budget):** *Add token counting to `stateToPromptContext`. Enforce 420-token cap with section truncation; log to Sentry on truncation.*

---

*End of design. Week 1 is the minimum bar — the three P0 bugs are live today, and two of them have real consequences (tenant leak + race clobber). Everything after week 1 is "should do for maintainability," not "must do for safety."*
