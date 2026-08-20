/**
 * mcp — the Ask registry, exposed to the athlete's own Claude.
 *
 * WHAT THIS IS
 *
 * A Model Context Protocol server over Streamable HTTP. An athlete adds its
 * URL as a custom connector in Claude, and every analyzer in
 * `_shared/analyzers/index.ts` becomes a tool their Claude can call against
 * their own training data. The reasoning happens in their Claude, on their
 * subscription; this function does what `ask` Layer 1 does and nothing more.
 *
 * THE THREE LAYERS, AND WHICH ONE THIS IS
 *
 *   Layer 0 · ROUTE    Claude does this. It reads the tool list and picks.
 *                      No Gemini call, no `FAST_ROUTES` table, no cost to us.
 *   Layer 1 · ANALYZE  THIS FUNCTION. Identical to `ask`: registry lookup,
 *                      `coerceParams`, `analyzer.run`, fact lines out.
 *   Layer 2 · NARRATE  Claude does this, inside the athlete's own client —
 *                      which means `narration-guard.ts` IS NOT IN THE PATH.
 *
 * That last line is the honest cost of this surface and it is not hidden
 * anywhere else in this file. In-app, the guard mechanically drops any
 * narration containing a number absent from `facts`; over MCP the narrator is
 * a model we do not host and cannot post-process. What we have instead is
 * instruction: `SERVER_INSTRUCTIONS` at handshake, `RESULT_DISCIPLINE` on
 * every single tool result. Both restate the rule the guard enforces. That is
 * strictly weaker than the guard and should be described that way to
 * athletes — see README.md, "What this gives up".
 *
 * What is NOT weaker: the facts themselves. `factLinesToStrings` is the same
 * seam `ask` narrates from, so the strings Claude sees here are byte-identical
 * to the strings the in-app narrator is licensed to. There is no second
 * serialization to drift.
 *
 * AUTH
 *
 * The credential is a path segment, because Claude's custom-connector UI
 * cannot send a custom `Authorization` header (anthropics/claude-ai-mcp#112)
 * and does not speak Supabase JWTs:
 *
 *     POST https://<ref>.supabase.co/functions/v1/mcp/prd_<43 chars>
 *
 * `verify_jwt = false` in config.toml — the gateway cannot check this
 * credential, so we do, against `mcp_access_tokens` (sha256, never plaintext).
 * See that migration's header for the posture this implies.
 *
 * SCOPE: READ. Every analyzer query is `.eq("user_id", ctx.userId)` by the
 * registry's own construction, nothing in `_shared/analyzers` writes, and the
 * only insert here is the `analysis_queries` audit row. "AI advises, never
 * acts" holds across this boundary: there is no tool here that can touch
 * `coachable_moments`, `plan_adjustments`, or a plan.
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

import { captureException, flushSentry } from "../_shared/sentry.ts";
import {
  ANALYZERS,
  ANALYZER_IDS,
  coerceParams,
  factLinesToStrings,
  getAnalyzer,
  type Analyzer,
  type AnalyzerCtx,
  type AnalyzerResult,
  type ParamSpec,
  type ParamsSchema,
} from "../_shared/analyzers/index.ts";
import { fetchZones, LOG_COLUMNS } from "../_shared/analyzers/data.ts";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

// ── Constants ────────────────────────────────────────────────────

const SERVER_NAME = "post-run-drip";
const SERVER_TITLE = "Post Run Drip";
const SERVER_VERSION = "0.1.0";

/**
 * Every analyzer tool is `running_<analyzer id>`. The prefix is not
 * decoration: a connector's tools land in a namespace shared with whatever
 * else the athlete has connected, and `efficiency` or `decoupling` on their
 * own read as generic. The mapping is a string strip, so the registry stays
 * the single source of truth — add an analyzer to `ANALYZERS` and a tool
 * appears here with no edit to this file.
 */
const TOOL_PREFIX = "running_";
const LIST_WORKOUTS_TOOL = `${TOOL_PREFIX}list_recent_workouts`;

/** Newest first. `initialize` echoes the client's choice when we know it. */
const SUPPORTED_PROTOCOL_VERSIONS = ["2025-06-18", "2025-03-26", "2024-11-05"];
const PREFERRED_PROTOCOL_VERSION = SUPPORTED_PROTOCOL_VERSIONS[0];

/** Don't write `last_used_at` on every call — once per window is the signal. */
const TOUCH_INTERVAL_MS = 5 * 60 * 1000;

const MAX_WORKOUT_ROWS = 50;
const DEFAULT_WORKOUT_ROWS = 20;

/**
 * The endpoint is called server-to-server by Anthropic, not by a browser, and
 * its credential lives in the URL rather than in a cookie — so a permissive
 * ACAO grants nothing a caller doesn't already hold. Deliberately NOT
 * `_shared/cors.ts`: that module pins the origin to the app, which is right
 * for every function the app calls and wrong for a public protocol endpoint.
 */
const CORS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, content-type, mcp-protocol-version, mcp-session-id, accept, last-event-id",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Expose-Headers": "mcp-protocol-version",
  "Access-Control-Max-Age": "86400",
};

const JSON_HEADERS = { ...CORS, "Content-Type": "application/json" };

// ── The rules, stated where the model will read them ─────────────

/**
 * Returned in the `initialize` result. Claude reads this once per session and
 * it frames every subsequent call. It is the closest thing this surface has
 * to `narration-guard.ts`, and it is not close — it persuades, it does not
 * enforce. Written as rules rather than as prose because a rule survives
 * summarization into a long conversation better than a paragraph does.
 */
const SERVER_INSTRUCTIONS =
  `These tools return one athlete's own running analysis, computed server-side from the sessions they have logged. Three rules govern how to use them.

1. EVERY NUMBER YOU STATE MUST APPEAR IN THE TOOL OUTPUT. The tools return \`facts\` — pre-formatted labels and values that were computed, not estimated. Do not derive new figures from them: no percentage of a percentage, no projected finish time, no weekly total you added up yourself, no unit you converted. If a value is missing, say it is missing; do not supply a typical one. If a number is not in the facts, it does not exist.

2. REPORT THE COVERAGE. Every result carries how many sessions and how many days it was built on, its confidence tier, and what was missing from that window. An answer resting on 3 sessions with no heart-rate data is not the same answer as one resting on 12 complete ones, and the athlete should be able to tell which they got. Lead with the finding, but never omit what it rests on.

3. OBSERVE, DO NOT DIAGNOSE. These tools describe what the training data shows. They are not a medical or diagnostic instrument. Do not name an injury, rate the severity of a symptom, prescribe rest, or tell the athlete to stop training on medical grounds. "A calf niggle has been logged on 9 of the last 14 days, and easy pace over that window is 12s/mi slower" is reporting. "That's a likely strain, take a week off" is not, and is outside what this data can support. Point them at a physio for the second kind of question.

When a tool returns an empty state, relay it. The athlete needs more data and the nudge says what kind. Answering anyway from general running knowledge, in a reply framed as their data, is the specific failure this surface is built to avoid.`;

/**
 * Appended to every tool result. The handshake instruction is read once and
 * competes with everything said since; this rides along with the numbers it
 * governs, at the moment they enter the context.
 */
const RESULT_DISCIPLINE =
  `— Use only the numbers printed above; they were computed, not estimated. Do not derive new figures from them and do not fill a gap with a typical value. Carry the coverage line into your answer. Describe what the data shows; do not diagnose, rate severity, or prescribe rest.`;

// ── JSON-RPC plumbing ────────────────────────────────────────────

type JsonRpcId = string | number | null;

interface JsonRpcRequest {
  jsonrpc?: unknown;
  id?: unknown;
  method?: unknown;
  params?: unknown;
}

const RPC_PARSE_ERROR = -32700;
const RPC_INVALID_REQUEST = -32600;
const RPC_METHOD_NOT_FOUND = -32601;
const RPC_INVALID_PARAMS = -32602;
const RPC_INTERNAL_ERROR = -32603;

function rpcResult(id: JsonRpcId, result: unknown, status = 200): Response {
  return new Response(JSON.stringify({ jsonrpc: "2.0", id, result }), {
    status,
    headers: JSON_HEADERS,
  });
}

function rpcError(
  id: JsonRpcId,
  code: number,
  message: string,
  status = 200,
): Response {
  return new Response(
    JSON.stringify({ jsonrpc: "2.0", id, error: { code, message } }),
    { status, headers: JSON_HEADERS },
  );
}

/**
 * A FAILED TOOL IS NOT A FAILED REQUEST. MCP puts tool-level failure inside a
 * successful result with `isError: true`, so the model can see what went
 * wrong and try something else — a JSON-RPC error is a protocol fault and
 * Claude cannot recover from it in-conversation. Every message here should
 * therefore name the next move, not just the problem.
 */
function toolFailure(message: string): Record<string, unknown> {
  return { content: [{ type: "text", text: message }], isError: true };
}

// ── Auth ─────────────────────────────────────────────────────────

async function sha256Hex(input: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(input),
  );
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

/**
 * Pull the token out of the path. Scanned from the right and shape-checked
 * rather than read from a fixed index, because the deployed path
 * (`/functions/v1/mcp/<token>`) and the locally-served one (`/mcp/<token>`)
 * differ in depth, and a token that lands at the wrong index reads as "no
 * credential" — a 401 that looks like a bad token rather than a bad route.
 */
function extractToken(pathname: string): string | null {
  const segments = pathname.split("/").filter(Boolean);
  for (let i = segments.length - 1; i >= 0; i--) {
    const seg = segments[i];
    if (seg.startsWith("prd_") && seg.length >= 20 && seg.length <= 80) {
      return seg;
    }
  }
  return null;
}

interface TokenIdentity {
  userId: string;
  tokenId: string;
  stale: boolean;
}

async function authenticate(token: string): Promise<TokenIdentity | null> {
  const hash = await sha256Hex(token);

  const { data, error } = await supabase
    .from("mcp_access_tokens")
    .select("id, user_id, expires_at, last_used_at")
    .eq("token_hash", hash)
    .maybeSingle();

  if (error) {
    console.error("mcp: token lookup failed", error.message);
    return null;
  }
  if (!data) return null;

  if (new Date(data.expires_at as string).getTime() <= Date.now()) {
    console.log(`mcp: expired token presented (id=${data.id})`);
    return null;
  }

  const lastUsed = data.last_used_at
    ? new Date(data.last_used_at as string).getTime()
    : 0;

  return {
    userId: data.user_id as string,
    tokenId: data.id as string,
    stale: Date.now() - lastUsed > TOUCH_INTERVAL_MS,
  };
}

/** Best-effort. A failed touch must never cost the athlete their answer. */
async function touchToken(tokenId: string): Promise<void> {
  try {
    await supabase
      .from("mcp_access_tokens")
      .update({ last_used_at: new Date().toISOString() })
      .eq("id", tokenId);
  } catch (err) {
    console.error("mcp: last_used_at touch failed", err);
  }
}

// ── Tool schemas, generated from the registry ────────────────────

function propertySchema(spec: ParamSpec): Record<string, unknown> {
  if (spec.type === "number") {
    return {
      type: "number",
      description: spec.describe,
      ...(spec.min != null ? { minimum: spec.min } : {}),
      ...(spec.max != null ? { maximum: spec.max } : {}),
    };
  }
  if (spec.type === "workout_id") {
    return {
      type: "string",
      description:
        `${spec.describe} This is an id from ${LIST_WORKOUTS_TOOL} — call that first if you do not already have one. Never invent or guess an id.`,
    };
  }
  return {
    type: "string",
    description: spec.describe,
    ...(spec.enum ? { enum: spec.enum } : {}),
  };
}

/**
 * `ParamsSchema` → JSON Schema. The registry's param spec is deliberately
 * tiny ("a routing contract, not JSON Schema") and this is the widening.
 *
 * `additionalProperties: false` mirrors `coerceParams`, which drops unknown
 * keys. Stating the closure in the schema means Claude is told the boundary
 * up front instead of discovering it by having a parameter silently ignored.
 */
function inputSchemaFor(params: ParamsSchema): Record<string, unknown> {
  const properties: Record<string, unknown> = {};
  const required: string[] = [];

  for (const [key, spec] of Object.entries(params)) {
    properties[key] = propertySchema(spec);
    if (!spec.optional) required.push(key);
  }

  return {
    type: "object",
    properties,
    ...(required.length > 0 ? { required } : {}),
    additionalProperties: false,
  };
}

const FACT_SCHEMA = {
  type: "object",
  properties: {
    key: { type: "string" },
    label: { type: "string" },
    value: { type: "string" },
    unit: { type: ["string", "null"] },
    delta: { type: ["string", "null"] },
    tone: { type: "string", enum: ["neutral", "good", "watch"] },
  },
  required: ["key", "label", "value"],
  additionalProperties: true,
};

const ANALYZER_OUTPUT_SCHEMA = {
  type: "object",
  properties: {
    question: { type: "string" },
    analyzer_id: { type: "string" },
    facts: { type: "array", items: FACT_SCHEMA },
    coverage: {
      type: "object",
      properties: {
        sessionsUsed: { type: "number" },
        windowDays: { type: "number" },
        missing: { type: "array", items: { type: "string" } },
        confidence: { type: "string", enum: ["high", "moderate", "low"] },
      },
      required: ["sessionsUsed", "windowDays", "missing", "confidence"],
      additionalProperties: true,
    },
  },
  required: ["facts", "coverage"],
  additionalProperties: true,
};

const WORKOUTS_OUTPUT_SCHEMA = {
  type: "object",
  properties: {
    workouts: {
      type: "array",
      items: {
        type: "object",
        properties: {
          workout_id: { type: "string" },
          date: { type: "string" },
          type: { type: ["string", "null"] },
          distance_miles: { type: ["number", "null"] },
          duration_minutes: { type: ["number", "null"] },
        },
        required: ["workout_id", "date"],
        additionalProperties: true,
      },
    },
    count: { type: "number" },
  },
  required: ["workouts", "count"],
  additionalProperties: true,
};

/** Every tool here reads. None of them mutate anything, ever. */
const READ_ONLY_ANNOTATIONS = {
  readOnlyHint: true,
  destructiveHint: false,
  idempotentHint: true,
  openWorldHint: false,
};

interface McpTool {
  name: string;
  title: string;
  description: string;
  inputSchema: Record<string, unknown>;
  outputSchema: Record<string, unknown>;
  annotations: Record<string, boolean>;
}

function describeAnalyzer(analyzer: Analyzer): string {
  return [
    `Answers the athlete's question: "${analyzer.label}" (training principle: ${analyzer.group}).`,
    ``,
    `Computes over the athlete's own logged sessions and returns pre-formatted fact lines plus the coverage they rest on. Returns an empty state, with a nudge explaining what data would make the answer possible, when there is not enough to answer honestly — relay that rather than answering from general running knowledge.`,
    ``,
    `Speak only the numbers this returns.`,
  ].join("\n");
}

const ANALYZER_TOOLS: McpTool[] = ANALYZER_IDS.map((id) => {
  const analyzer = ANALYZERS[id];
  return {
    name: `${TOOL_PREFIX}${analyzer.id}`,
    title: analyzer.label,
    description: describeAnalyzer(analyzer),
    inputSchema: inputSchemaFor(analyzer.params),
    outputSchema: ANALYZER_OUTPUT_SCHEMA,
    annotations: READ_ONLY_ANNOTATIONS,
  };
});

/**
 * The one hand-written tool, and it exists for a specific reason:
 * `compare_session` takes a `workout_id`, and without this there is no way
 * for Claude to obtain one — it would either fail or, worse, invent a UUID.
 * A closed param schema is only closed if the values in it are reachable.
 */
const WORKOUTS_TOOL: McpTool = {
  name: LIST_WORKOUTS_TOOL,
  title: "Recent runs",
  description: [
    `Lists the athlete's recently logged runs, newest first, with the workout id for each.`,
    ``,
    `Call this to obtain a \`workout_id\` for any tool that takes one, and to orient yourself on what the athlete has actually been doing before asking a more specific question. This is a log listing, not an analysis — the distances and durations are as recorded, and the analytical tools are what turn them into an answer.`,
  ].join("\n"),
  inputSchema: {
    type: "object",
    properties: {
      limit: {
        type: "number",
        description:
          `How many runs to return, newest first. Default ${DEFAULT_WORKOUT_ROWS}, maximum ${MAX_WORKOUT_ROWS}.`,
        minimum: 1,
        maximum: MAX_WORKOUT_ROWS,
      },
      days: {
        type: "number",
        description:
          "Only return runs from the last N days. Omit for no date filter.",
        minimum: 1,
        maximum: 730,
      },
    },
    additionalProperties: false,
  },
  outputSchema: WORKOUTS_OUTPUT_SCHEMA,
  annotations: READ_ONLY_ANNOTATIONS,
};

const TOOLS: McpTool[] = [WORKOUTS_TOOL, ...ANALYZER_TOOLS];

// ── Rendering ────────────────────────────────────────────────────

function renderAnalyzerResult(
  analyzer: Analyzer,
  result: AnalyzerResult,
): string {
  const heading = result.title ?? analyzer.label;
  const lines: string[] = [heading, ""];

  if (result.empty) {
    lines.push(
      `Not enough data yet — ${result.empty.eyebrow}`,
      "",
      result.empty.nudge,
    );
    if (result.empty.cta) {
      lines.push("", `Suggested next step: ${result.empty.cta.label}`);
    }
  } else {
    // The SAME seam `ask` narrates from. Not a second serialization — if this
    // ever diverges from `factLinesToStrings`, the connector and the app are
    // licensing different numbers for the same question.
    lines.push(...factLinesToStrings(result));
  }

  const otherVariants = (result.variants ?? []).filter((v) => !v.active);
  if (otherVariants.length > 0) {
    lines.push(
      "",
      `Same question, other parameterizations of this tool: ${
        otherVariants
          .map((v) =>
            `${v.label} → ${JSON.stringify(v.params)} (${v.sessions} sessions)`
          )
          .join("; ")
      }`,
    );
  }

  const related = result.related
    .map((id) => ANALYZERS[id])
    .filter((a): a is Analyzer => a != null);
  if (related.length > 0) {
    lines.push(
      "",
      `Related tools: ${
        related.map((a) => `${TOOL_PREFIX}${a.id} ("${a.label}")`).join("; ")
      }`,
    );
  }

  lines.push("", RESULT_DISCIPLINE);
  return lines.join("\n");
}

// ── Audit ────────────────────────────────────────────────────────

/**
 * Same ledger as `ask`, `source: 'mcp'`. Best-effort: an audit failure must
 * never cost the athlete their answer.
 *
 * `annotated` is always FALSE here and that is not a gap in the data — Layer 2
 * ran inside the athlete's Claude where we cannot see it, so the row asserts
 * "these facts were served" and nothing about what was said over them. Read
 * `guard_tripped` rates against app sources only; this source has no guard to
 * trip. (Migration 20260819120000 says the same thing at the schema.)
 *
 * `list_recent_workouts` is deliberately NOT logged: `mode` is constrained to
 * analyzer outcomes, and a log listing is not one. Padding the ledger with
 * rows that answer no question would corrupt the "what do people actually
 * ask?" read this table exists for.
 */
async function logQuery(row: Record<string, unknown>): Promise<void> {
  try {
    const { error } = await supabase.from("analysis_queries").insert(row);
    if (error) console.error("mcp: audit insert failed", error.message);
  } catch (err) {
    console.error("mcp: audit insert threw", err);
  }
}

// ── Tools ────────────────────────────────────────────────────────

async function runListWorkouts(
  userId: string,
  args: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  const rawLimit = typeof args.limit === "number" ? args.limit : DEFAULT_WORKOUT_ROWS;
  const limit = Math.min(MAX_WORKOUT_ROWS, Math.max(1, Math.floor(rawLimit)));

  let query = supabase
    .from("training_logs")
    .select(LOG_COLUMNS)
    .eq("user_id", userId)
    .order("workout_date", { ascending: false })
    .limit(limit);

  if (typeof args.days === "number" && args.days > 0) {
    const since = new Date(Date.now() - args.days * 86_400_000);
    query = query.gte("workout_date", since.toISOString().slice(0, 10));
  }

  const { data, error } = await query;
  if (error) {
    return toolFailure(
      `Could not read the training log: ${error.message}. This is a server-side failure, not a missing-data one — do not answer from general knowledge instead; tell the athlete the log could not be reached.`,
    );
  }

  const rows = (data ?? []) as Array<Record<string, unknown>>;
  const workouts = rows.map((r) => ({
    workout_id: r.id as string,
    date: r.workout_date as string,
    type: (r.workout_type ?? null) as string | null,
    distance_miles: (r.workout_distance_miles ?? null) as number | null,
    duration_minutes: (r.workout_duration_minutes ?? null) as number | null,
  }));

  if (workouts.length === 0) {
    return {
      content: [{
        type: "text",
        text:
          "No runs logged in this window. Say so plainly — there is nothing here to analyse, and the analytical tools will return empty states for the same reason.",
      }],
      structuredContent: { workouts: [], count: 0 },
    };
  }

  const text = [
    `${workouts.length} most recent run${workouts.length === 1 ? "" : "s"}, newest first:`,
    "",
    ...workouts.map((w) => {
      const distance = w.distance_miles != null
        ? `${w.distance_miles} mi`
        : "distance not recorded";
      const duration = w.duration_minutes != null
        ? `${w.duration_minutes} min`
        : "duration not recorded";
      return `${w.date} · ${w.type ?? "unlabelled"} · ${distance} · ${duration} · id=${w.workout_id}`;
    }),
    "",
    RESULT_DISCIPLINE,
  ].join("\n");

  return {
    content: [{ type: "text", text }],
    structuredContent: { workouts, count: workouts.length },
  };
}

async function runAnalyzerTool(
  userId: string,
  analyzer: Analyzer,
  args: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  const startedAt = Date.now();

  // The same closed-schema coercion the app uses: unknown keys and
  // out-of-range values are DROPPED, not rejected, so a model that guesses a
  // parameter degrades to the analyzer's defaults instead of erroring at the
  // athlete.
  const params = coerceParams(analyzer, args);

  const { zones, zoneTable } = await fetchZones(supabase, userId);
  const ctx: AnalyzerCtx = {
    userId,
    supabase,
    zones,
    zoneTable,
    now: new Date(),
  };

  const result = await analyzer.run(params, ctx);

  await logQuery({
    user_id: userId,
    source: "mcp",
    raw_question: null,
    analyzer_id: analyzer.id,
    params,
    mode: "analyzed",
    annotated: false,
    confidence: result.coverage.confidence,
    facts: result.facts,
    narration: null,
    latency_ms: Date.now() - startedAt,
    model_used: null,
    guard_tripped: false,
  });

  return {
    content: [{ type: "text", text: renderAnalyzerResult(analyzer, result) }],
    structuredContent: {
      question: result.title ?? analyzer.label,
      analyzer_id: analyzer.id,
      facts: result.facts,
      coverage: result.coverage,
      series: result.series ?? null,
      empty: result.empty ?? null,
      variants: result.variants ?? null,
      related: result.related,
    },
  };
}

async function callTool(
  userId: string,
  name: string,
  args: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  if (name === LIST_WORKOUTS_TOOL) {
    return await runListWorkouts(userId, args);
  }

  const analyzerId = name.startsWith(TOOL_PREFIX)
    ? name.slice(TOOL_PREFIX.length)
    : name;
  const analyzer = getAnalyzer(analyzerId);

  if (!analyzer) {
    return toolFailure(
      `No tool named "${name}". The available tools are: ${
        TOOLS.map((t) => t.name).join(", ")
      }. Pick the one whose question matches, or tell the athlete this surface cannot answer what they asked.`,
    );
  }

  return await runAnalyzerTool(userId, analyzer, args);
}

// ── Method dispatch ──────────────────────────────────────────────

function negotiateProtocolVersion(requested: unknown): string {
  if (
    typeof requested === "string" &&
    SUPPORTED_PROTOCOL_VERSIONS.includes(requested)
  ) {
    return requested;
  }
  return PREFERRED_PROTOCOL_VERSION;
}

async function dispatch(
  identity: TokenIdentity,
  id: JsonRpcId,
  method: string,
  params: Record<string, unknown>,
): Promise<Response> {
  switch (method) {
    case "initialize":
      return rpcResult(id, {
        protocolVersion: negotiateProtocolVersion(params.protocolVersion),
        capabilities: { tools: { listChanged: false } },
        serverInfo: {
          name: SERVER_NAME,
          title: SERVER_TITLE,
          version: SERVER_VERSION,
        },
        instructions: SERVER_INSTRUCTIONS,
      });

    case "ping":
      return rpcResult(id, {});

    case "tools/list":
      // No pagination: the registry is a few dozen tools and a `nextCursor`
      // the server never sets is a contract nobody exercises. If the registry
      // reaches the size where this matters, page it then.
      return rpcResult(id, { tools: TOOLS });

    case "tools/call": {
      const name = params.name;
      if (typeof name !== "string") {
        return rpcError(id, RPC_INVALID_PARAMS, "tools/call requires a string `name`");
      }
      const args = (params.arguments && typeof params.arguments === "object")
        ? params.arguments as Record<string, unknown>
        : {};
      try {
        const result = await callTool(identity.userId, name, args);
        return rpcResult(id, result);
      } catch (err) {
        // A thrown analyzer is OUR bug, not a protocol fault — report it as a
        // tool error so Claude can tell the athlete something useful and move
        // on, and capture it so we find out.
        console.error(`mcp: tool "${name}" threw`, err);
        captureException(err, { fn: "mcp", tool: name });
        return rpcResult(
          id,
          toolFailure(
            `The "${name}" analysis failed to run. This is a server-side error, not a lack of data — do not substitute an answer from general running knowledge. Tell the athlete this question could not be computed right now.`,
          ),
        );
      }
    }

    // We advertise no resources or prompts capability, so a spec-conformant
    // client will not call these. Some do anyway during discovery; an empty
    // list is a cheaper answer than a method-not-found the client has to
    // interpret.
    case "resources/list":
      return rpcResult(id, { resources: [] });
    case "resources/templates/list":
      return rpcResult(id, { resourceTemplates: [] });
    case "prompts/list":
      return rpcResult(id, { prompts: [] });

    default:
      return rpcError(id, RPC_METHOD_NOT_FOUND, `Unknown method: ${method}`);
  }
}

// ── Handler ──────────────────────────────────────────────────────

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS });
  }

  // Streamable HTTP allows a client to GET the endpoint to open a
  // server-initiated SSE stream. This server is stateless and has nothing
  // unsolicited to say, so 405 is the spec's own answer for that case.
  if (req.method !== "POST") {
    return new Response(null, {
      status: 405,
      headers: { ...CORS, Allow: "POST, OPTIONS" },
    });
  }

  try {
    const token = extractToken(new URL(req.url).pathname);
    if (!token) {
      return new Response(
        JSON.stringify({
          error:
            "Missing connector token. The URL must end in /mcp/<token> — generate one in the app under Settings → Connect Claude.",
        }),
        { status: 401, headers: JSON_HEADERS },
      );
    }

    const identity = await authenticate(token);
    if (!identity) {
      return new Response(
        JSON.stringify({
          error:
            "This connector token is not valid, or it has expired. Generate a new one in the app under Settings → Connect Claude and update the connector URL.",
        }),
        { status: 401, headers: JSON_HEADERS },
      );
    }

    if (identity.stale) {
      // Not awaited: `last_used_at` is an abuse signal for the athlete, not
      // part of answering the request.
      touchToken(identity.tokenId);
    }

    const body = await req.json().catch(() => null) as
      | JsonRpcRequest
      | JsonRpcRequest[]
      | null;

    if (body === null) {
      return rpcError(null, RPC_PARSE_ERROR, "Request body is not valid JSON");
    }

    if (Array.isArray(body)) {
      // Batching was removed from the protocol in 2025-06-18. Saying so beats
      // a generic invalid-request, because the fix is a client setting.
      return rpcError(
        null,
        RPC_INVALID_REQUEST,
        "JSON-RPC batching is not supported. Send one message per request.",
      );
    }

    const method = body.method;
    if (typeof method !== "string") {
      return rpcError(null, RPC_INVALID_REQUEST, "Missing `method`");
    }

    // No `id` means a notification (`notifications/initialized` and friends).
    // Nothing to answer, and the spec wants 202 with an empty body. Note that
    // `id: 0` is a legitimate request id, which is why this tests against
    // undefined and null rather than falsiness.
    const rawId = body.id;
    if (rawId === undefined || rawId === null) {
      return new Response(null, { status: 202, headers: CORS });
    }
    if (typeof rawId !== "string" && typeof rawId !== "number") {
      return rpcError(null, RPC_INVALID_REQUEST, "`id` must be a string or number");
    }

    const params = (body.params && typeof body.params === "object" && !Array.isArray(body.params))
      ? body.params as Record<string, unknown>
      : {};

    return await dispatch(identity, rawId, method, params);
  } catch (error) {
    console.error("mcp error:", error);
    captureException(error, { fn: "mcp" });
    await flushSentry();
    const message = error instanceof Error ? error.message : String(error);
    return rpcError(null, RPC_INTERNAL_ERROR, message, 500);
  }
});
