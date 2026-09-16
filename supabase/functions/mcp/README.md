# Connect your own Claude

**Status: beta, not shipped.** This directory is built and type-checked but has
never run against a live Claude connector. Read "Before you ship this" at the
bottom before you turn it on for anyone but yourself.

---

## What this is, in one paragraph

Right now, when an athlete asks the app a question, we pay for the answer: the
app calls Gemini, and every token is on our bill. This does the opposite. It
turns the analyzer registry — the ~50 questions in `_shared/analyzers/` that
compute real math over real rows — into **tools that the athlete's own Claude
can call**. They connect Post Run Drip inside their Claude account, ask "how's
my threshold pace trending?" there, and Claude calls our analyzer, gets the
computed facts back, and writes the answer using their Claude subscription. We
serve numbers. They pay for prose.

This is the version of "sync your own Claude" that is actually allowed.
Anthropic banned third-party apps from authenticating as a user's Claude
subscription in February 2026 — an app that logs in as you and spends your quota
is against their usage policy. This is the inverse and it is fine: their Claude
client connects out to us, on their credentials, in their app.

## What it does *not* do

It does not make the app cheaper. The in-app Coach still calls Gemini exactly as
it does today; nothing in this directory changes `ask`, `coaching-agent`, or any
prompt. This is an additional surface, not a replacement one.

---

## The pieces

| File | What it is |
| --- | --- |
| `index.ts` | The server. Speaks MCP over HTTP, checks the athlete's token, runs analyzers. |
| `../../migrations/20260819120000_mcp_access_tokens.sql` | The token table + the function that mints one. |
| `[functions.mcp]` in `supabase/config.toml` | `verify_jwt = false`, because Claude cannot send a Supabase JWT. |

Nothing else in the repo changed.

### The tools an athlete's Claude sees

One per analyzer, generated from the registry at startup. `ANALYZERS` is still
the only source of truth — **add an analyzer to `_shared/analyzers/index.ts` and
a tool appears here with no edit to `index.ts`.** That was the point of building
the registry the way you built it, and it pays off exactly here.

```
running_load_balance            "Am I ramping too fast?"
running_current_fitness         "Where's my fitness right now?"
running_zone_trend              "Is my LT pace improving?"
running_efficiency              …
running_decoupling              …
running_race_projection         …
running_race_pace_specificity   …
running_heat_effect             …
running_mood_trend              …
running_niggle_timeline         …
running_compare_session         …
running_list_recent_workouts    ← the one hand-written tool
```

`running_list_recent_workouts` exists for a specific reason: `compare_session`
takes a `workout_id`, and without a way to *get* one, Claude would either fail
or invent a UUID. A closed parameter schema is only closed if the values in it
are reachable.

---

## Setting it up

### 1. Run the migration

```bash
supabase db push
```

Creates `mcp_access_tokens` and the `create_mcp_access_token()` function, and
widens the `analysis_queries.source` check to allow `'mcp'`.

### 2. Deploy the function

```bash
supabase functions deploy mcp
```

`config.toml` already sets `verify_jwt = false` for it. **That is not a
mistake** — see "How the token works" below for why, and what protects it
instead.

### 3. Mint yourself a token

The migration ships a Postgres function. Run this as *your logged-in athlete
account* (SQL editor won't work — it has no `auth.uid()`; use the app, or a
`supabase.rpc()` call with your own JWT):

```ts
const { data, error } = await supabase.rpc('create_mcp_access_token', {
  p_name: 'My laptop',
});
// data[0].token  ← this is the ONLY time you will ever see it
```

The plaintext is returned once and never stored — the table keeps only
`sha256(token)`. If you lose it, delete the row and mint another. That is the
correct cost of a credential that cannot be recovered from a database dump.

### 4. Build the URL

```
https://<your-project-ref>.supabase.co/functions/v1/mcp/<the token>
```

### 5. Add it in Claude

Settings → Connectors → Add custom connector → paste the URL.

---

## How the token works, and why it's in the URL

Claude's custom-connector setup cannot send a custom `Authorization: Bearer`
header — this is a known limitation
([anthropics/claude-ai-mcp#112](https://github.com/anthropics/claude-ai-mcp/issues/112)).
The options are full OAuth 2.1 or putting the credential in the URL. For a beta
run by one person, the URL is the right trade; OAuth is several days of auth
work with real security surface.

**Treat the URL like a password.** Anyone holding it can read that athlete's
training analysis. What limits the damage:

- **Read-only.** Nothing in `_shared/analyzers/` writes, and the only insert
  this function makes is an audit row. A leaked token cannot change a plan,
  cannot write a `coachable_moment`, cannot touch `plan_adjustments`. "AI
  advises, never acts" holds across this boundary.
- **One athlete.** Every analyzer query is `.eq("user_id", ctx.userId)` by the
  registry's own construction. The token names one athlete and reaches nothing
  else.
- **Hashed at rest.** A database dump contains no working URL.
- **Expires** after 180 days, and revoking is a `DELETE` — there is no flag to
  flip back.
- **Five per athlete**, so a compromised session can't quietly mint backdoors.

Revoke:

```sql
DELETE FROM mcp_access_tokens WHERE id = '<the id>';
```

The athlete's own RLS policy permits this, so a settings screen can do it
directly with no new endpoint.

---

## What this gives up

**Read this part twice. It is the real cost, and it is not obvious.**

Your whole Ask architecture rests on one rule: *if a number is not in `facts`,
it does not exist.* In the app, that rule is **mechanical**. `narration-guard.ts`
tokenizes every number the model emits, checks it against the fact lines, and
drops the entire narration on a single violation. `guard_tripped` in
`analysis_queries` is your alarm for the prompt drifting past its evidence.

Over MCP, **the narrator is Claude, in the athlete's own client, and the guard
is not in the path.** There is no response of ours to post-process. What this
function has instead is instruction:

- `SERVER_INSTRUCTIONS`, sent once at handshake, stating the three rules — only
  the numbers in `facts`, always report coverage, observe rather than diagnose.
- `RESULT_DISCIPLINE`, appended to *every single tool result*, restating the
  short version right next to the numbers it governs.

That is meaningfully weaker than the guard, and you should describe it that way
rather than letting it read as the same product. Two consequences worth holding:

1. **The no-diagnosis rail is softer here.** Hard rule #2 — no analyzer may
   diagnose, recommend rest, or assess severity — still holds for the *facts*,
   because it's enforced in the analyzers themselves and those are unchanged.
   But an athlete asking their Claude "is this a stress fracture?" over
   `running_niggle_timeline` data will get *something*, and it will not be
   filtered by your prompt rails, because your prompts aren't running.
   `SERVER_INSTRUCTIONS` addresses this directly and explicitly. It is still
   persuasion.

2. **`guard_tripped` rates are no longer comparable across sources.** MCP rows
   land in `analysis_queries` with `annotated = false` and `guard_tripped =
   false` always — not because nothing went wrong, but because nothing was
   checked. Filter to `source != 'mcp'` before reading guard drift, or the
   denominator quietly inflates and the rate quietly falls.

---

## Before you ship this

Ordered by how much they'd hurt.

1. **Test the handshake against real Claude.** This has been type-checked and
   its JSON-RPC shapes exercised locally, but never connected. Do this first,
   with your own account, before anything else on the list.
2. **Decide what you're comfortable with on #1 above.** Read the two
   consequences again with a real athlete in mind. If the diagnosis softening
   isn't acceptable to you, the fix is to *not expose* `running_niggle_timeline`
   and `running_mood_trend` over the connector — a one-line filter on
   `ANALYZER_TOOLS`. That is a legitimate answer.
3. **Add rate limiting.** There is none. The `analysis` bucket exists and
   `UNBOUND_USAGE` is currently `true` in `ask`, so the in-app path isn't
   metered either — but a public URL is a different exposure from an
   authenticated app. Per-token, per-minute, in Postgres.
4. **Build the settings screen.** Minting currently requires calling an RPC by
   hand. It needs: a "Connect Claude" button, the URL shown *once* with a copy
   control, a list of existing connectors by `token_prefix` and `last_used_at`,
   and a delete on each.
5. **Say what it is in the UI.** Something like "Claude will be able to read
   your training analysis. It cannot change your plan." The claim is true —
   keep it that way by never adding a write tool here.

---

## Testing it by hand

The whole protocol is JSON over POST, so `curl` is enough:

```bash
URL="https://<ref>.supabase.co/functions/v1/mcp/<token>"

# What tools does it expose?
curl -s -X POST "$URL" -H 'Content-Type: application/json' -d '{
  "jsonrpc":"2.0","id":1,"method":"tools/list"
}' | jq '.result.tools[].name'

# Run one.
curl -s -X POST "$URL" -H 'Content-Type: application/json' -d '{
  "jsonrpc":"2.0","id":2,"method":"tools/call",
  "params":{"name":"running_load_balance","arguments":{}}
}' | jq -r '.result.content[0].text'
```

A `401` means the token is wrong, expired, or deleted. Everything else comes
back as JSON-RPC with a `result` — including tool failures, which arrive as
`result.isError: true` rather than as protocol errors, so that Claude can read
what went wrong and try something else.
