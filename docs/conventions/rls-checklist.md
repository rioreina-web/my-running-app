# RLS Checklist for New Tables

Every new table ships with RLS in the same migration that creates it.
**No exceptions.** This file exists because we accumulated 9 RLS-fix
migrations in 2 months by treating RLS as something we'd "add later."
We will not repeat that pattern.

---

## Required steps for any new table

Run through this list in order. The migration is not done until every box
is checked.

- [ ] `ALTER TABLE <table> ENABLE ROW LEVEL SECURITY;` is in the same
      migration as `CREATE TABLE`.
- [ ] At least one explicit SELECT policy exists. **No "Allow all" policies
      in production code paths.** ("Allow all" is acceptable only in seed /
      dev migrations that are clearly labeled as such.)
- [ ] If users mutate this table, an explicit UPDATE policy exists,
      scoped to the right principal.
- [ ] If the table has a delete-from-app path, an explicit DELETE policy
      exists. Otherwise omit (no DELETE policy = no deletes from clients).
- [ ] If edge functions write to the table, a `Service role full access`
      policy exists.
- [ ] If the policy involves a subquery against another RLS-enabled table,
      verify it does not cause recursion. **Use `current_coach_id()` (or a
      similar SECURITY DEFINER helper) instead of inline subqueries against
      `coach_profiles`.**
- [ ] Manually test the RLS by querying as a non-owner user. Should return
      empty.

---

## Principal scoping cheat sheet

Pick the right `USING` clause for the right principal type.

### User-owned data (athlete reads their own rows)

```sql
CREATE POLICY "Owner reads" ON <table> FOR SELECT
  USING (user_id = auth.uid()::text OR auth.uid() IS NULL);
```

The `OR auth.uid() IS NULL` fallback matches the existing convention in
this repo (preserves service-role and unauthenticated dev access). Drop it
if you want stricter behavior.

### Coach-owned data (coach reads their own rows)

```sql
CREATE POLICY "Coach reads own" ON <table> FOR SELECT
  USING (coach_id = current_coach_id() OR auth.uid() IS NULL);
```

Use `current_coach_id()` from
`20260311120000_fix_coach_rls_recursion.sql`. Do NOT inline a subquery
against `coach_profiles` — that path causes recursion.

### Coach-reads-of-athlete data (cross-table check)

```sql
CREATE POLICY "Coach reads athletes" ON <table> FOR SELECT
  USING (
    athlete_user_id IN (
      SELECT athlete_user_id FROM coach_athlete_relationships
       WHERE coach_id = current_coach_id() AND status = 'active'
    )
    OR auth.uid() IS NULL
  );
```

### Service-role unconditional access (for edge function writes)

```sql
CREATE POLICY "Service role full access" ON <table>
  FOR ALL USING (auth.role() = 'service_role')
       WITH CHECK (auth.role() = 'service_role');
```

---

## Anti-patterns we have learned the hard way

- **Subquery against `coach_profiles` from `coach_athlete_relationships`
  policy → recursion.** Fixed in `20260311120000_fix_coach_rls_recursion.sql`.
  Always use `current_coach_id()` from coach-scoped policies.
- **`Allow all` policies in production code paths.** They look fine in dev,
  silently leak data in prod. Several of our older tables had these and
  required dedicated lockdown migrations
  (`20260221_fix_all_rls_fallbacks.sql`, `20260313100000_lock_down_rls.sql`).
- **Adding a column without re-checking RLS.** If a new column changes the
  ownership semantics (e.g., adding `coach_id` to a previously user-owned
  table), the existing policies may no longer scope correctly.
- **Forgetting `WITH CHECK` on UPDATE / INSERT policies.** A `USING` clause
  alone does not stop a user from inserting a row that fails the same
  predicate.

---

## Reference patterns

When in doubt, read one of these as a model.

- **Coach-scoped table:** `coachable_moments` migration
  (`20260428100000_create_coachable_moments.sql`)
- **User-owned table:** `ai_insights` migration
  (`20260319120000_create_ai_insights.sql`)
- **Coach + athlete linkage:** `coach_athlete_relationships` block in
  `20260312_coach_training_plans.sql`
- **The recursion fix that made coach RLS sane:**
  `20260311120000_fix_coach_rls_recursion.sql`

---

## Before merging the migration

- [ ] PR description explicitly answers: "Who can SELECT? UPDATE? DELETE?
      INSERT?" If you can't answer in one sentence per verb, the policy
      isn't right yet.
- [ ] Manual RLS test executed. Result pasted in PR description.
- [ ] Reviewer has read this checklist and confirms the policies match
      one of the patterns above (or there's a written justification for
      deviating).
