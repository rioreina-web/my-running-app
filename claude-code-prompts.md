# Claude Code Prompts — RunningLog Code Review Fixes

Run these one at a time. Each is scoped to a single concern.

---

## Critical (do these first)

### 1. iOS — Move hardcoded credentials to Secrets.xcconfig

```
In RunningLog/RunningLog/Services/Supabase.swift (lines 16-23), the Supabase URL and anon key are hardcoded. In Health/VitalManager.swift (lines 20-27), the Vital API key is hardcoded. In Services/SentryService.swift (line 23), the Sentry DSN is hardcoded.

Move all three to Secrets.xcconfig and read them via Bundle.main.infoDictionary. Make sure Secrets.xcconfig is in .gitignore. Add a Secrets.xcconfig.example with placeholder values.
```

### 2. Web — Verify .env.local is gitignored

```
Check if web/.env.local is committed to git history. If so, remove it from tracking with git rm --cached. Verify it's in .gitignore. The file contains real Supabase and Vital API keys that need to be rotated — add a TODO comment in web/.env.example noting the keys were exposed and need rotation.
```

### 3. Supabase — Re-enable JWT verification on edge functions

```
In supabase/config.toml, find all edge functions with verify_jwt = false. Set verify_jwt = true for admin-sql, coaching-agent, and any debug functions. If any of these functions need to be called without a user JWT (e.g., from a service role), add a comment explaining why and validate the service role key manually inside the function instead.
```

---

## High Priority (before next release)

### 4. Web — Switch API routes from anon key to service role key

```
In web/src/app/api/, the route handlers for weekly-report, assign-plan, coach, and retry-processing call Supabase Edge Functions using the anon key in the Authorization header. These are server-side routes that already authenticate the user — they should use SUPABASE_SERVICE_ROLE_KEY instead. Update each route.ts file. Make sure SUPABASE_SERVICE_ROLE_KEY is in .env.example (but not .env.local committed to git).
```

### 5. Web — Add zod input validation to all API routes

```
Add zod input validation to all API route handlers in web/src/app/api/. Install zod if not already present. For each route, define a schema matching the expected request body shape (check what fields each route destructures from the body), parse with schema.safeParse(), and return 400 with a clear error if validation fails. Don't change any business logic — just add the validation layer.
```

### 6. Web — Sanitize blog HTML to prevent XSS

```
In web/src/app/(public)/blog/[slug]/page.tsx around line 57, blog content is rendered with dangerouslySetInnerHTML without sanitization. Install isomorphic-dompurify and sanitize the HTML before rendering. Also in web/src/components/blog/portable-text-renderer.tsx (lines 54-67), links from Sanity CMS aren't validated — add a check that href uses http: or https: protocol only, rejecting javascript: and data: URIs.
```

### 7. Web — Tighten CSP policy

```
In web/next.config.ts around lines 34-35, the Content Security Policy allows 'unsafe-inline' and 'unsafe-eval' for scripts. Remove both. If inline scripts break, switch to nonce-based CSP using Next.js's built-in nonce support. Test that the site still loads correctly after the change.
```

### 8. iOS — Fix silent SwiftData save failures

```
In RunningLog/RunningLog/Services/OfflineQueue.swift, there are multiple instances of try? context.save() that silently swallow errors. Find all of them and replace with do { try context.save() } catch { Log.app.error("SwiftData save failed: \(error)") }. For saves that affect user data (workout uploads, voice logs), also call ErrorReporter.shared.report() so failures surface to the user.
```

### 9. iOS — Fix auth session refresh handling

```
In RunningLog/RunningLog/Auth/AuthManager.swift around lines 52-63, a failed session refresh immediately signs the user out. Instead: retry the refresh once with a 2-second delay before signing out. If offline (check NetworkMonitor), keep the existing session and queue a refresh for when connectivity returns. Log the failure but don't force re-authentication for transient network issues.
```

### 10. iOS — Fix @unchecked Sendable on KeychainAuthStorage

```
In RunningLog/RunningLog/Services/Supabase.swift line 32, KeychainAuthStorage is marked @unchecked Sendable which bypasses thread-safety checks. Add a private serial DispatchQueue for all Keychain operations (store, retrieve, remove) and dispatch synchronously on it. Then remove the @unchecked annotation.
```

### 11. ML Service — Add JWT issuer validation

```
In ml-service/app/auth.py around line 33, JWT validation checks the audience claim but not the issuer. Add issuer verification — the issuer should match your Supabase project URL (e.g., https://<project-ref>.supabase.co/auth/v1). Add verify_iss: True to the decode options.
```

---

## Medium Priority (next sprint)

### 12. Web — Upgrade to distributed rate limiting

```
In web/src/lib/rate-limit.ts, the rate limiter is in-memory and only works per-instance. Replace with @upstash/ratelimit using Vercel KV or Upstash Redis. Keep the same rate limits already configured per route (check each API route for its current limit). Add the UPSTASH_REDIS_REST_URL and UPSTASH_REDIS_REST_TOKEN to .env.example.
```

### 13. Web — Add retry logic to Vital API calls

```
In web/src/lib/vital.ts, the fetch calls to the Vital API have no retry logic. Create a fetchWithRetry wrapper that retries up to 3 times with exponential backoff (1s, 2s, 4s) on 5xx errors or network failures. Apply it to all fetch calls in that file. Don't retry on 4xx errors.
```

### 14. iOS — Fix error body swallowing in Supabase service

```
In RunningLog/RunningLog/Services/Supabase.swift around lines 131-136, HTTP error responses (4xx/5xx) are returned without parsing the error body. Update the error handling to read the response body, parse it as JSON if possible, and log the error details. Return a meaningful error message to callers instead of a generic failure.
```

### 15. Supabase — Add missing database indexes

```
Create a new Supabase migration that adds composite indexes on (user_id, created_at DESC) for the coaching_feedback and goal_outcomes tables. Check if any other tables used in coach queries are missing similar indexes.
```

### 16. ML Service — Add rate limiting to endpoints

```
In ml-service/app/main.py, add rate limiting using slowapi. Limit /predict-fitness and /injury-risk to 10 requests per minute per user (use the JWT sub claim as the key). Limit /training-summary to 30 per minute. Return 429 with a clear message when exceeded.
```

### 17. iOS — Fix force unwrap crash risk

```
In RunningLog/RunningLog/Services/WorkoutSyncService.swift around lines 61-62, segments is force-unwrapped with segments! after only checking that paceSplits is not empty. Add a guard that checks segments is non-nil and non-empty before the unwrap. Fall back to classifyWorkout() if segments is unavailable.
```
