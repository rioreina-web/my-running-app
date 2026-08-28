/**
 * Behavioural tests for `_shared/auth.ts` — the authorization gate that 64 of
 * the 68 edge functions delegate to.
 *
 * WHY THIS FILE EXISTS (2026-08-26)
 *
 * Until now nothing executed this module. The two contract tests that mention
 * `requireAuthOrServiceRole` only *grep other files' source* for the string,
 * which proves a call site exists and says nothing about what the gate does
 * when it runs. For the single point of authorization in the backend, "the
 * gate is present" is a much weaker claim than "a bare service-role key with
 * no user_id gets a 400" — and the second is the one that keeps an audit
 * trail honest.
 *
 * WHAT IS NOT COVERED HERE, AND WHY
 *
 * The user-JWT branch (`supabase.auth.getUser`) needs a live GoTrue, so any
 * token carrying a real `sub` claim would put a network call in the suite.
 * That leaves the JWT-matches-body-user_id 403 untested here; it wants an
 * integration test against a real project. Everything reachable without the
 * network — the header parsing, the service-role branch, the constant-time
 * compare, and the missing-`sub` short circuit — is covered below, and that
 * is where the whole authorization decision is actually made for machine
 * callers.
 */

import {
  assert,
  assertEquals,
  assertNotEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  getAuthenticatedUser,
  requireAuthOrServiceRole,
  requireServiceRole,
  unauthorizedResponse,
} from "./auth.ts";

const CORS = { "Access-Control-Allow-Origin": "https://app.example.test" };
const SERVICE_KEY = "sb_secret_test_key_0123456789abcdef";
const USER = "11111111-1111-1111-1111-111111111111";
const OTHER = "22222222-2222-2222-2222-222222222222";

/** Run `fn` with SUPABASE_SERVICE_ROLE_KEY set to `key` (or unset), restoring after. */
async function withServiceKey(
  key: string | null,
  fn: () => Promise<void> | void,
): Promise<void> {
  const prev = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (key === null) Deno.env.delete("SUPABASE_SERVICE_ROLE_KEY");
  else Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", key);
  try {
    await fn();
  } finally {
    if (prev === undefined) Deno.env.delete("SUPABASE_SERVICE_ROLE_KEY");
    else Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", prev);
  }
}

function b64url(o: unknown): string {
  return btoa(JSON.stringify(o)).replace(/\+/g, "-").replace(/\//g, "_")
    .replace(/=+$/, "");
}

/** A JWT-shaped token. Signature is never verified here — the gateway did that. */
function jwt(payload: Record<string, unknown>): string {
  return `${b64url({ alg: "HS256", typ: "JWT" })}.${b64url(payload)}.sig`;
}

/** What a Supabase API key looks like: a `role` claim and NO subject. */
const API_KEY_SHAPED = jwt({ role: "service_role", iss: "supabase" });

function req(auth?: string): Request {
  return new Request("http://localhost/fn", {
    method: "POST",
    headers: auth ? { Authorization: auth } : {},
  });
}

// ── Header parsing ───────────────────────────────────────────────────

Deno.test("auth: no Authorization header → 401", async () => {
  const r = await requireAuthOrServiceRole(req(), USER, CORS);
  assert("response" in r);
  assertEquals(r.response.status, 401);
});

Deno.test("auth: non-Bearer scheme → 401", async () => {
  const r = await requireAuthOrServiceRole(req(`Basic ${SERVICE_KEY}`), USER, CORS);
  assert("response" in r);
  assertEquals(r.response.status, 401);
});

Deno.test("auth: Bearer with an empty token → 401", async () => {
  const r = await requireAuthOrServiceRole(req("Bearer    "), USER, CORS);
  assert("response" in r);
  assertEquals(r.response.status, 401);
});

Deno.test("auth: the 401 carries the caller's CORS headers, not '*'", async () => {
  const r = await requireAuthOrServiceRole(req(), USER, CORS);
  assert("response" in r);
  assertEquals(
    r.response.headers.get("Access-Control-Allow-Origin"),
    "https://app.example.test",
  );
});

// ── Service-role branch ──────────────────────────────────────────────

Deno.test("auth: service-role key + body user_id → acts as that user", async () => {
  await withServiceKey(SERVICE_KEY, async () => {
    const r = await requireAuthOrServiceRole(req(`Bearer ${SERVICE_KEY}`), USER, CORS);
    assert(!("response" in r), "service-role call should be accepted");
    assertEquals(r.userId, USER);
    assertEquals(r.isServiceRole, true);
  });
});

Deno.test("auth: service-role key with NO user_id → 400, not a silent accept", async () => {
  // The audit trail is the point: a machine caller must name its subject.
  await withServiceKey(SERVICE_KEY, async () => {
    for (const missing of [undefined, null, ""]) {
      const r = await requireAuthOrServiceRole(
        req(`Bearer ${SERVICE_KEY}`),
        missing as string | null | undefined,
        CORS,
      );
      assert("response" in r, `bodyUserId=${JSON.stringify(missing)} must be rejected`);
      assertEquals(r.response.status, 400);
    }
  });
});

Deno.test("auth: service-role branch does NOT verify the user exists", async () => {
  // Documents real behaviour rather than wishing it away: a service caller
  // naming any string becomes that user. The protection is the secrecy of the
  // key, so anything that can leak it (see the env-probe finding) is total.
  await withServiceKey(SERVICE_KEY, async () => {
    const r = await requireAuthOrServiceRole(
      req(`Bearer ${SERVICE_KEY}`),
      "not-even-a-uuid",
      CORS,
    );
    assert(!("response" in r));
    assertEquals(r.userId, "not-even-a-uuid");
  });
});

// ── Constant-time compare ────────────────────────────────────────────

Deno.test("auth: a token differing by one character is rejected", async () => {
  await withServiceKey(SERVICE_KEY, async () => {
    const nearMiss = SERVICE_KEY.slice(0, -1) + "X";
    assertEquals(nearMiss.length, SERVICE_KEY.length, "same length, one char off");
    assertNotEquals(nearMiss, SERVICE_KEY);
    const r = await requireAuthOrServiceRole(req(`Bearer ${nearMiss}`), USER, CORS);
    assert("response" in r);
    assertEquals(r.response.status, 401);
  });
});

Deno.test("auth: a prefix of the service key is rejected", async () => {
  await withServiceKey(SERVICE_KEY, async () => {
    const r = await requireAuthOrServiceRole(
      req(`Bearer ${SERVICE_KEY.slice(0, 10)}`),
      USER,
      CORS,
    );
    assert("response" in r);
    assertEquals(r.response.status, 401);
  });
});

Deno.test("auth: fails closed when SUPABASE_SERVICE_ROLE_KEY is unset", async () => {
  // An unset key must never make the compare vacuously true.
  await withServiceKey(null, async () => {
    const r = await requireAuthOrServiceRole(req(`Bearer ${SERVICE_KEY}`), USER, CORS);
    assert("response" in r);
    assertEquals(r.response.status, 401);
  });
});

// ── Missing-`sub` short circuit (the 2026-08-07 GoTrue stall) ────────

Deno.test("auth: an API-key-shaped token that isn't OUR key → 401 without GoTrue", async () => {
  // This is the service-key-drift case. If it ever reached the network branch
  // the test would hang or throw on a socket, so passing offline IS the
  // assertion that the short circuit still fires.
  await withServiceKey(SERVICE_KEY, async () => {
    const r = await requireAuthOrServiceRole(req(`Bearer ${API_KEY_SHAPED}`), USER, CORS);
    assert("response" in r);
    assertEquals(r.response.status, 401);
  });
});

Deno.test("auth: malformed tokens never reach the network", async () => {
  await withServiceKey(SERVICE_KEY, async () => {
    for (const bad of ["garbage", "a.b", "a.b.c.d", "...", "a.!!!.c"]) {
      const r = await requireAuthOrServiceRole(req(`Bearer ${bad}`), USER, CORS);
      assert("response" in r, `${bad} must be rejected`);
      assertEquals(r.response.status, 401);
    }
  });
});

Deno.test("auth: a token whose sub is empty is treated as subject-less", async () => {
  await withServiceKey(SERVICE_KEY, async () => {
    const r = await requireAuthOrServiceRole(req(`Bearer ${jwt({ sub: "" })}`), USER, CORS);
    assert("response" in r);
    assertEquals(r.response.status, 401);
  });
});

// ── requireServiceRole (strict gate, no user) ────────────────────────

Deno.test("requireServiceRole: correct key → null (proceed)", async () => {
  await withServiceKey(SERVICE_KEY, () => {
    assertEquals(requireServiceRole(req(`Bearer ${SERVICE_KEY}`), CORS), null);
  });
});

Deno.test("requireServiceRole: user JWT is not enough", async () => {
  // A logged-in athlete must not be able to drive a cron-only endpoint.
  await withServiceKey(SERVICE_KEY, () => {
    const res = requireServiceRole(req(`Bearer ${jwt({ sub: OTHER })}`), CORS);
    assert(res !== null);
    assertEquals(res.status, 401);
  });
});

Deno.test("requireServiceRole: missing header and unset key both 401", async () => {
  await withServiceKey(SERVICE_KEY, () => {
    const res = requireServiceRole(req(), CORS);
    assert(res !== null);
    assertEquals(res.status, 401);
  });
  await withServiceKey(null, () => {
    const res = requireServiceRole(req(`Bearer ${SERVICE_KEY}`), CORS);
    assert(res !== null, "unset key must fail closed");
    assertEquals(res.status, 401);
  });
});

// ── getAuthenticatedUser ─────────────────────────────────────────────

Deno.test("getAuthenticatedUser: no header, empty token, or no sub → null", async () => {
  assertEquals(await getAuthenticatedUser(req()), null);
  assertEquals(await getAuthenticatedUser(req("Bearer ")), null);
  assertEquals(await getAuthenticatedUser(req(`Bearer ${API_KEY_SHAPED}`)), null);
  assertEquals(await getAuthenticatedUser(req("Bearer garbage")), null);
});

Deno.test("getAuthenticatedUser: the service-role key names no user", async () => {
  // Documented contract: no service-role bypass in this helper.
  await withServiceKey(SERVICE_KEY, async () => {
    assertEquals(await getAuthenticatedUser(req(`Bearer ${SERVICE_KEY}`)), null);
  });
});

// ── unauthorizedResponse shape ───────────────────────────────────────

Deno.test("unauthorizedResponse: 401, JSON body, CORS merged", async () => {
  const res = unauthorizedResponse(CORS);
  assertEquals(res.status, 401);
  assertEquals(res.headers.get("Content-Type"), "application/json");
  assertEquals(
    res.headers.get("Access-Control-Allow-Origin"),
    "https://app.example.test",
  );
  assertEquals((await res.json()).error, "Authentication required");
});
