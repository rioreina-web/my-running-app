# Auth recovery — plan

**Why this exists.** On 2026-08-19 the project owner — with dashboard access,
a service-role key, and an AI assistant — could not get back into his own
account for the better part of an hour. A beta athlete would simply have been
locked out forever. This plan closes that.

The forgotten password was not one bug. It was **five independent failures
stacked**, each of which alone would have broken recovery.

---

## 1. What actually failed

| # | Failure | Evidence | Status |
|---|---|---|---|
| 1 | No "Forgot password?" anywhere in the UI | `login/page.tsx` had signin/signup only | **fixed** 2026-08-18 |
| 2 | No page to land on — reset links 404'd | no `/reset-password` route existed | **fixed** 2026-08-18 |
| 3 | Middleware bounced the reset page to `/login` | route returned 307; token stranded | **fixed** 2026-08-18 |
| 4 | **Nothing ever exchanged the PKCE code** | `exchangeCodeForSession` absent from the entire codebase; `@supabase/ssr` hardcodes `flowType: "pkce"` | **partly fixed** — reset page only |
| 5 | Built-in SMTP: rate-limited, members-only | `mail.send` OK to owner; "email rate limit exceeded" after 3 sends | **open** — config |

Failure 4 is the deep one. The link *worked* — auth logs show
`/verify 303 action=login` at 14:29:03 — and deposited a valid `?code=` on the
landing page, where no code read it. From the user's side: *"it sends me to the
website"* and nothing happens. No error, no clue.

Failure 5 compounds it: Supabase's built-in sender only delivers to **project
members**, so a real athlete gets no email at all, and its few-per-hour cap
means the debugging loop itself exhausts the quota.

---

## 2. The blast radius is bigger than passwords

`mailer_autoconfirm: false` and `disable_signup: false`, and there is **no
`/auth/callback` route**. So:

- **Every new signup is already broken.** Confirmation email → click → `?code=`
  lands on a page that ignores it → never confirmed → can never sign in.
- Magic links, email-change confirmation, and OAuth (if ever enabled) fail the
  same way, for the same reason.

Password recovery was the symptom that got noticed. The missing callback is the
disease, and it currently breaks the entire front door.

---

## 3. The fix

### Phase 1 — one callback route to own the whole flow (code)

Create `src/app/auth/callback/route.ts`: a Route Handler that exchanges
`?code=` server-side and redirects by intent (`type=recovery` →
`/reset-password`, everything else → `/trends`). Point every auth email at it
via a single `emailRedirectTo` / `redirectTo` constant.

Why server-side: the handler sets the session cookie directly, so the app is
authenticated on first paint instead of flashing a logged-out shell. It also
means one place handles every email type, rather than each page reinventing it.

Keep `RecoveryHashRedirect` as a safety net for links that land on the wrong
page (see Phase 2 — the allow-list is config we don't control from here), and
for legacy implicit-flow `#access_token=` links.

**PKCE caveat that must be designed around:** the exchange needs the
`code_verifier` stored in the browser that *requested* the reset. A link
generated in the Supabase dashboard has no verifier in the athlete's browser
and will always fail. Consequence: **support-initiated resets do not work** —
recovery must start from the app. Say so in the UI rather than letting it fail
silently.

### Phase 2 — configuration (dashboard; not code)

1. **Redirect allow-list** — add `http://localhost:3000/**` and the production
   origin. Without this Supabase silently falls back to the Site URL, which is
   how a valid link ended up on the marketing page.
2. **Custom SMTP (Resend)** — already scoped in
   `docs/deploy/h5-supabase-prod-config.md`, never done. This is the one that
   makes recovery work for anyone who isn't a project member. **Beta blocker.**
3. **Rate limits** — raise "emails per hour" off the shared-sender default.
4. **Site URL** — confirm it points where we think it does.

### Phase 3 — make failure legible (code)

Every dead end in this incident was silent. Minimum bar:

- Surface Supabase's own `error_description` verbatim, never a generic
  "invalid link." *(done on `/reset-password`)*
- Distinguish **expired** from **already used** — recovery links are
  single-use, and the second click looks identical to expiry. The owner hit
  exactly this: success at 14:29:03, `403 One-time token not found` at 14:29:11.
- Rate-limit errors must say *"too many requests, wait N minutes"*, not fail
  mutely.
- A "didn't get the email?" affordance with a resend that respects the cap.

### Phase 4 — prove it (verification)

Not "it compiles." An actual end-to-end run:

1. Sign up a throwaway address → confirm via the emailed link → land signed in.
2. Forgot password → email → set new password → sign in with it.
3. Click the same recovery link twice → second click says *used*, not *expired*.
4. Request 5 resets in a minute → clear rate-limit message.
5. Repeat 1–2 against the **deployed** site, not just localhost.

Add the callback to `tests/smoke/` so a future refactor can't silently delete
the exchange again.

---

## 4. Sequencing

| Order | Work | Blocked on |
|---|---|---|
| 1 | Phase 1 callback route | nothing — do first, unblocks signup too |
| 2 | Phase 2.1 redirect allow-list | dashboard access |
| 3 | Phase 3 error states | Phase 1 |
| 4 | Phase 2.2 Resend SMTP | Resend API key |
| 5 | Phase 4 verification | 1–4 |
| 6 | Deploy | production is 4 months stale — none of this is live until then |

Phase 1 + 2.1 together restore recovery for project members. **2.2 is what
makes it work for actual athletes** — until Resend is configured, every
non-member signup and reset silently sends nothing.

---

## 5. Open decisions

1. **Magic links instead of passwords?** The app is voice-first and mobile-
   first; a passwordless flow removes this entire failure class. It trades one
   dependency (SMTP) for another, but SMTP is required for signup confirmation
   anyway. Worth deciding before beta.
2. **Turn `mailer_autoconfirm` on for beta?** Removes the confirmation step
   while SMTP is unconfigured, at the cost of unverified addresses. A stopgap,
   not a fix — recovery still needs working email.
3. **Support path for a locked-out athlete.** Given the PKCE verifier
   constraint, dashboard resets can't work. Decide now what support actually
   does: a signed one-time link from our own endpoint, or admin-set temporary
   passwords.
