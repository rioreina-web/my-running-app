# Edge Functions — Shared Modules & Security Rules

## SUPABASE_SERVICE_ROLE_KEY usage

The service role key bypasses RLS. Every use must follow this rule:

**Never use the service role key to read or write user data without first authenticating the user.**

### Correct patterns

1. **Edge function with `verify_jwt = false` + internal auth:**
   The iOS app sends the anon key (not a user JWT) as the Authorization bearer.
   Functions with `verify_jwt = false` call `getAuthenticatedUser(req)` from `auth.ts`
   to extract the real user from the token. The service role client is then used for
   operations that need cross-table access, but **always scoped to the authenticated
   user's ID** (e.g., `.eq("user_id", userId)`).

2. **Web API route (Next.js) with forwarded user context:**
   The web server authenticates the user via `supabase.auth.getUser()`, then calls
   an edge function with the service role key in the Authorization header, passing
   `userId: user.id` in the request body. The edge function trusts this because
   only the web server has the service role key.

### What NOT to do

- Do not use the service role key to query data without validating ownership.
- Do not accept `user_id` from an unauthenticated request body.
- Do not use the service role key to skip RLS for convenience — if RLS blocks
  a query, fix the policy or add a new one.

### Audit checklist for new edge functions

- [ ] Does the function call `getAuthenticatedUser(req)` or receive `userId` from an authenticated web route?
- [ ] Are all DB queries scoped to the authenticated user's ID?
- [ ] Is `verify_jwt` set correctly in `config.toml`?
- [ ] If the function uses the service role client, is there a comment explaining why?

## Shared modules

| File | Purpose |
|---|---|
| `auth.ts` | `getAuthenticatedUser()` — JWT extraction and verification |
| `rateLimit.ts` | Per-user rate limiting via Upstash Redis |
| `cors.ts` | Standard CORS headers |
| `router.ts` | Multi-model LLM routing (Anthropic / Gemini / Groq) |
| `cache.ts` | Semantic cache for LLM responses |
| `context.ts` | Coaching context builder (training logs, goals, history) |
| `athlete-state.ts` | Athlete state singleton |
| `athleteProfile.ts` | Profile data access |
| `dataAnalysis.ts` | Workout data analysis utilities |
| `injuries.ts` | Injury tracking helpers |
| `memory.ts` | User memory / conversation persistence |
| `profile.ts` | Profile utilities |
| `validation.ts` | Input validation helpers |
| `weeklyAnalytics.ts` | Weekly report aggregation |
| `workoutSelection.ts` | Workout selection / filtering |
| `aiInsights.ts` | AI insight generation utilities |
