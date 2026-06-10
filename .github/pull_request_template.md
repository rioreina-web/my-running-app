<!-- Keep this short — describe the change, then walk the checklist. -->

## What

<!-- 1-3 sentences. The "why" matters more than the "what." -->

## Test plan

- [ ]
- [ ]

## Schema / RLS

If this PR adds or alters a table, follow the
[RLS checklist](../docs/conventions/rls-checklist.md). Tick or strike through:

- [ ] No new tables touched, OR
- [ ] New / altered table ships with RLS in the same migration
- [ ] Inserts to `coachable_moments` go through a service-role edge function
      (no client-side INSERT policy)
- [ ] `current_coach_id()` used for coach-scoped policies (no direct
      subqueries against `coach_profiles` — they cause recursion)

## Prompts / LLM

- [ ] No LLM-touching change, OR
- [ ] Prompt diff reviewed against `docs/coaching/principles.md`
- [ ] Eval harness run (once it exists)
