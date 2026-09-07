/**
 * ask — the analysis surface inside Coach.
 *
 * Three layers, one path. Chips and free text differ only in who fills in
 * `{analyzer_id, params}`:
 *
 *   Layer 0 · ROUTE    free text → an id from the registry's closed enum.
 *                      Chips skip this layer entirely (no model, no cost).
 *   Layer 1 · ANALYZE  `_shared/analyzers/<id>.ts` runs real math over real
 *                      rows and emits fact lines. Deterministic, auditable.
 *   Layer 2 · NARRATE  `ask-narration.v1` writes two sentences over the fact
 *                      lines and nothing else. Every numeric token is checked
 *                      against them; one violation drops the whole narration.
 *
 * The invariant: **the facts always render; the narration is a bonus, never a
 * dependency.** A missing API key, a malformed response, a hallucinated
 * number — all degrade to `annotated: false` with the analysis intact.
 *
 * Generalized from `compare-workouts`, which established this two-layer shape
 * for a single question. AI advises, never acts: nothing here writes to
 * `coachable_moments`, `plan_adjustments`, or any plan table. The only insert
 * is the `analysis_queries` audit row.
 *
 * Rate limiting is deliberately asymmetric. Layer 1 is free — chips cost
 * nothing and the rail should feel free to touch. The `analysis` bucket is
 * charged only when a Layer-2 model call is actually made.
 *
 * Request:
 *   { question?, analyzer_id?, params?, narrate?, context?: { workout_id? } }
 * Response:
 *   { success, mode, annotated, analyzer_id, facts, series, coverage,
 *     narration, followups, conversational, catalog?, disambiguation? }
 *
 * `conversational: true` tells the client this answer is incomplete on its own
 * — it should also ask `coaching-agent` and lead with that reply, rendering
 * any computed card beneath it. Always false for chips. See UNBOUND_ANSWERS.
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { GoogleGenerativeAI } from "https://esm.sh/@google/generative-ai@0.24.0";

import { corsHeaders } from "../_shared/cors.ts";
import { getAuthenticatedUser, unauthorizedResponse } from "../_shared/auth.ts";
import { enforceFeatureRateLimit, enforceMonthlyCap } from "../_shared/rateLimit.ts";
import { llmBudgetAllows, llmBudgetBlockedResponse } from "../_shared/llm-budget.ts";
import { loadPrompt } from "../_shared/prompt-library.ts";
import { captureException, flushSentry } from "../_shared/sentry.ts";
import { validateLength } from "../_shared/validation.ts";
import {
  describeScope,
  validateNarration,
  type AnalysisScope,
  type Narration,
} from "../_shared/narration-guard.ts";
import {
  ANALYZERS,
  analyzerCatalog,
  coerceParams,
  factLinesToStrings,
  getAnalyzer,
  type AnalyzerCtx,
  type AnalyzerResult,
} from "../_shared/analyzers/index.ts";
import { fetchZones } from "../_shared/analyzers/data.ts";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

const MAX_QUESTION_CHARS = 400;

// ── UNBOUND (beta, 2026-08-10) ───────────────────────────────────
//
// Two deliberate relaxations for the first release of chat into the app. Both
// are single constants so re-binding is a one-line change, not an archaeology
// exercise. Flip either to `false` to restore the pre-2026-08-10 behaviour.
//
//   UNBOUND_ANSWERS — the registry is no longer the ceiling for free text.
//     Previously a typed question could only be answered if the router matched
//     one of the ~50 analyzers; anything else came back as an empty `prose`
//     shell that the client had to re-ask elsewhere. Now every typed question
//     is answered conversationally, and a matched analyzer rides along as
//     *evidence under* that answer rather than instead of it.
//
//     What this costs: prose is not number-guarded. Layer 2 narration over
//     analyzer facts still cannot speak a number that isn't in `facts` — that
//     guard is untouched — but the conversational answer beside it can. The
//     no-medical-claims and no-diagnosis rails are unaffected; they live in
//     `coaching-agent`'s prompt, not here.
//
//   UNBOUND_USAGE — no per-feature rate limit and no monthly cap on the
//     `analysis` bucket, so the surface never refuses a question while it's
//     the thing being lived on. Layer 1 was always free; this makes Layer 2
//     free too.
//
// Chips are untouched by both: they skip Layer 0 entirely and stay computed-
// only, deterministic, and free.
const UNBOUND_ANSWERS = true;
const UNBOUND_USAGE = true;

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// ── Layer 0 · route ──────────────────────────────────────────────

/**
 * Deterministic pre-router. Cheap, obvious keyword hits resolve without a
 * model call at all — the majority of typed questions are a chip the athlete
 * didn't see. Anything ambiguous falls through to the classifier.
 *
 * These patterns are a fast path, never the only path: a miss costs one Groq-
 * tier call, not a wrong answer.
 */
const FAST_ROUTES: Array<[RegExp, string]> = [
  // ORDER IS THE ALGORITHM — first match wins, so the most specific
  // vocabularies go first. A body part is unambiguous; the word "pace" is not.
  [
    /\b(knee|calf|calves|achilles|shin|hamstring|quad|hip|glute|foot|feet|ankle|plantar|it band|itb|niggle|sore|soreness|tight|twinge)\b/i,
    "niggle_timeline",
  ],
  [/\b(mood|how (i've|i have) been feeling|motivation|motivated|flat|burnt out|burned out)\b/i, "mood_trend"],
  [/\b(heat|dew ?point|humid|humidity|hot|temperature|weather|conditions)\b/i, "heat_effect"],
  [
    /\b(efficien\w*|met(er|re)s per heartbeat|m\/beat|per heartbeat|aerobic efficiency)\b/i,
    "efficiency",
  ],
  [/\b(decoupl\w*|cardiac drift\w*|(hr|heart rate) drift\w*|durabilit\w*|fade late|late.race fade)\b/i, "decoupling"],
  // "goal pace" is specificity; "on track" / "what will I run" is projection.
  // Both mention the goal, so keep them apart explicitly rather than letting
  // one swallow the other.
  [/\b(goal pace|race pace|at pace|specific\w*|marathon pace work)\b/i, "race_pace_specificity"],
  [
    // "on pace for 2:20" / "how close am I to 2:20" are the goal-gap question
    // in an athlete's own words — both fell through to prose in the audit log
    // (2026-08-08) because neither phrasing was here and the model router
    // declined them.
    /\b(on track|on pace|how close|close (am i|to)|project\w*|predict\w*|what (will|would|can) i run|race time|goal time|shape for|fit enough|sub[- ]?\d)\b/i,
    "race_projection",
  ],
  [/\b(compare|similar|stack up|versus|vs\.?|head to head)\b/i, "compare_session"],
  [
    // Bare "volume" / "mileage" land here too ("how's my volume breakdown
    // doing?" — audit log 2026-08-08, fell to prose). Load balance is the
    // card that answers volume questions; zone_trend's patterns below are
    // pace-shaped, so this does not shadow them.
    /\b(ramp\w*|acwr|acute|too (fast|much|hard)|volume|mileage|weekly miles|(mileage|volume|miles)\s+jump\w*|jump\w*\s+(my\s+)?(mileage|volume|miles)|overtrain\w*|build\w* too|monotony)\b/i,
    "load_balance",
  ],
  [/\b(lt|threshold|mp|marathon pace|5k|10k|tempo)\b.*\b(pace|improv|trend|faster|progress)/i, "zone_trend"],
  [/\b(pace)\b.*\b(improv|trend|faster|progress|better|coming down)/i, "zone_trend"],
];

interface RouteResult {
  analyzerId: string | null;
  params: Record<string, unknown>;
  ambiguous: boolean;
  /** The 2-3 readings the router was torn between. Empty unless ambiguous. */
  candidates: string[];
}

function fastRoute(question: string): string | null {
  for (const [re, id] of FAST_ROUTES) {
    if (re.test(question)) return id;
  }
  return null;
}

/** The router's view of the registry — ids and their closed param schemas. */
function routerCatalog(): string {
  return Object.values(ANALYZERS)
    .map((a) => {
      const params = Object.entries(a.params)
        .map(([k, s]) => {
          const enumPart = s.type === "string" && s.enum ? ` one of [${s.enum.join(", ")}]` : "";
          return `      ${k} (${s.type}${s.optional ? ", optional" : ""}${enumPart}): ${s.describe}`;
        })
        .join("\n");
      return `  - ${a.id} — answers: "${a.label}"\n${params || "      (no parameters)"}`;
    })
    .join("\n");
}

async function routeWithModel(question: string): Promise<RouteResult> {
  const apiKey = Deno.env.get("GEMINI_API_KEY");
  if (!apiKey) return { analyzerId: null, params: {}, ambiguous: false, candidates: [] };

  const prompt =
    `You route a runner's question to exactly one analysis tool, or to none.

AVAILABLE TOOLS:
${routerCatalog()}

THE QUESTION: ${question}

Reply with ONLY this JSON:
{"analyzer_id":"<id from the list above, or null>","params":{},"ambiguous":false,"candidates":[]}

Rules:
- "analyzer_id" MUST be one of the ids listed above, or null. Never invent one.
- Only fill "params" with keys declared for that tool. Omit anything you are unsure of.
- Set "ambiguous" true when the question could reasonably mean two different tools, and list exactly those ids in "candidates" (2 or 3, most likely first). Do not fill "candidates" otherwise.
- Use null when no tool genuinely answers it — an open-ended or off-topic question, a request for advice, anything about nutrition, gear, or how to feel. Guessing is worse than declining.
- A paraphrase still counts as a match. Athletes rarely use a tool's exact label:
  - "Am I on pace for 2:20?" / "How close am I to my goal?" / "Will I break 3?" → race_projection
  - "How's my volume?" / "Is my mileage where it should be?" → load_balance
  - "Is my tempo pace coming down?" / "Am I getting faster?" → zone_trend
  - "How did that workout stack up?" → compare_session
  Decline only when the question is truly outside every tool's territory, not because the wording is casual.`;

  try {
    const genAI = new GoogleGenerativeAI(apiKey);
    const model = genAI.getGenerativeModel({
      model: "gemini-2.5-flash-lite",
      // Gemini 2.5 spends "thinking" tokens out of `maxOutputTokens` before it
      // emits a single visible character. A 256-token ceiling with thinking
      // left on can burn the entire budget and return empty text, which lands
      // here as a JSON parse failure and silently drops routing to the
      // regex fast path. Routing is a lookup in a closed list, not a reasoning
      // problem — zero the thinking budget and give the JSON real room.
      // Mirrors parse-workout-structure / correct-workout-structure; the cast
      // is because @google/generative-ai 0.24.0 has no `thinkingConfig` typing.
      generationConfig: {
        temperature: 0,
        maxOutputTokens: 1024,
        thinkingConfig: { thinkingBudget: 0 },
      } as Record<string, unknown>,
    });
    const result = await model.generateContent({
      contents: [{ role: "user", parts: [{ text: prompt }] }],
    });

    let raw = result.response.text().trim();
    const fenced = raw.match(/```(?:json)?\s*([\s\S]*?)```/);
    if (fenced) raw = fenced[1].trim();
    const parsed = JSON.parse(raw) as {
      analyzer_id?: unknown;
      params?: unknown;
      ambiguous?: unknown;
      candidates?: unknown;
    };

    const id = typeof parsed.analyzer_id === "string" ? parsed.analyzer_id : null;
    return {
      // The closed enum, enforced here rather than trusted: an id that isn't
      // in the registry is treated as "no match", never as an error.
      analyzerId: id && ANALYZERS[id] ? id : null,
      params: (parsed.params && typeof parsed.params === "object")
        ? parsed.params as Record<string, unknown>
        : {},
      ambiguous: parsed.ambiguous === true,
      // Closed enum here too: a candidate the registry doesn't have is dropped
      // rather than offered as a chip that would 404 on tap.
      candidates: Array.isArray(parsed.candidates)
        ? parsed.candidates
          .filter((c): c is string => typeof c === "string" && ANALYZERS[c] != null)
          .slice(0, 3)
        : [],
    };
  } catch (err) {
    console.error("ask: router failed, falling through to prose", err);
    return { analyzerId: null, params: {}, ambiguous: false, candidates: [] };
  }
}

// ── Layer 2 · narrate ────────────────────────────────────────────

interface NarrationOutcome {
  narration: Narration | null;
  guardTripped: boolean;
  modelUsed: string | null;
}

async function narrate(
  question: string,
  result: AnalyzerResult,
  scope: AnalysisScope,
): Promise<NarrationOutcome> {
  const apiKey = Deno.env.get("GEMINI_API_KEY");
  if (!apiKey) {
    console.error("ask: GEMINI_API_KEY not configured — serving bare facts");
    return { narration: null, guardTripped: false, modelUsed: null };
  }

  const factLines = factLinesToStrings(result);
  const modelName = "gemini-2.5-flash";

  try {
    const genAI = new GoogleGenerativeAI(apiKey);
    const model = genAI.getGenerativeModel({
      model: modelName,
      // Same trap as the router, and this one was live: every Ask answer came
      // back with `narration: null`, `guard_tripped: false`, `model_used:
      // gemini-2.5-flash` — the call was made and returned nothing usable.
      // Gemini 2.5 draws thinking tokens from `maxOutputTokens`, so a 512
      // ceiling was consumed before any prose existed, and the empty body
      // failed `validateNarration` on shape rather than on a bad number.
      //
      // Narration is two sentences over facts that are already computed; there
      // is nothing here to reason about, and reasoning is exactly what the
      // number guard exists to prevent. Budget zero, and leave room for the
      // JSON envelope. Cast per the 0.24.0 typings gap.
      generationConfig: {
        temperature: 0.2,
        maxOutputTokens: 2048,
        thinkingConfig: { thinkingBudget: 0 },
      } as Record<string, unknown>,
    });
    const prompt = loadPrompt("ask-narration.v1", {
      question,
      factLines: factLines.join("\n"),
      scope: describeScope(scope),
      confidence: result.coverage.confidence,
    });
    const gen = await model.generateContent({
      contents: [{ role: "user", parts: [{ text: prompt }] }],
    });

    const raw = gen.response.text();
    const validated = validateNarration(raw, factLines, {}, scope);

    if (!validated.ok) {
      // This log is the early-warning system for prompt drift. A rising rate of
      // `disallowed_number` means the prompt has started reasoning past its
      // evidence, which is exactly the failure the guard exists to catch.
      console.error(
        `ask: narration rejected. reason=${validated.reason} offending=${
          validated.offendingNumber ?? validated.offendingScope ?? "n/a"
        } rawLen=${raw.length}`,
      );
      return {
        narration: null,
        // `unlicensed_scope` counts as a tripped guard for the same reason
        // `disallowed_number` does: both mean the prompt spoke past its
        // evidence, and a rising rate of either is prompt drift.
        guardTripped: validated.reason === "disallowed_number" ||
          validated.reason === "unlicensed_scope",
        modelUsed: modelName,
      };
    }

    return { narration: validated.narration, guardTripped: false, modelUsed: modelName };
  } catch (err) {
    console.error("ask: narration call failed", err);
    return { narration: null, guardTripped: false, modelUsed: modelName };
  }
}

// ── Audit ────────────────────────────────────────────────────────

/**
 * Log the query. Best-effort: an audit failure must never cost the athlete
 * their answer, so this swallows its own errors.
 *
 * This table earns its keep three ways — it feeds promote-to-cassette, it is
 * the honest answer to "what do people actually ask?" before v2 of the chip
 * library, and `guard_tripped` is the alarm for a drifting prompt.
 */
async function logQuery(row: Record<string, unknown>): Promise<void> {
  try {
    const { error } = await supabase.from("analysis_queries").insert(row);
    if (error) console.error("ask: audit insert failed", error.message);
  } catch (err) {
    console.error("ask: audit insert threw", err);
  }
}

// ── Handler ──────────────────────────────────────────────────────

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const startedAt = Date.now();

  try {
    const userId = await getAuthenticatedUser(req);
    if (!userId) return unauthorizedResponse(corsHeaders);

    const body = await req.json().catch(() => null) as {
      question?: unknown;
      analyzer_id?: unknown;
      params?: unknown;
      narrate?: unknown;
      context?: { workout_id?: unknown };
    } | null;

    // The catalog request — how the client builds its chip rail without
    // hardcoding a list that drifts from the registry.
    if (body?.analyzer_id === "__catalog__") {
      return jsonResponse({ success: true, mode: "catalog", catalog: analyzerCatalog() });
    }

    const question = typeof body?.question === "string" ? body.question.trim() : "";
    if (question) {
      const lengthError = validateLength(question, "question", MAX_QUESTION_CHARS);
      if (lengthError) return jsonResponse({ error: lengthError }, 400);
    }

    // ── Layer 0 ──
    let analyzerId: string | null = null;
    let rawParams: Record<string, unknown> = {};
    let source: "chip" | "text" = "chip";
    let ambiguous = false;
    let candidates: string[] = [];

    if (typeof body?.analyzer_id === "string") {
      analyzerId = body.analyzer_id;
      rawParams = (body.params && typeof body.params === "object")
        ? body.params as Record<string, unknown>
        : {};
    } else if (question) {
      source = "text";
      const fast = fastRoute(question);
      if (fast) {
        analyzerId = fast;
      } else {
        // Global spend brake. Independent of UNBOUND_USAGE: that flag governs
        // the per-user quota (fairness), this governs the day's total spend
        // (solvency). Subject stays null — the per-subject ceiling is a loop
        // detector for one row reprocessed, which a typed question is not, so
        // this imposes no per-athlete question cap.
        if (!(await llmBudgetAllows("ask_route", { userId }))) {
          return llmBudgetBlockedResponse("ask_route", corsHeaders);
        }
        const routed = await routeWithModel(question);
        analyzerId = routed.analyzerId;
        rawParams = routed.params;
        ambiguous = routed.ambiguous;
        candidates = routed.candidates;
      }
    } else {
      return jsonResponse(
        { error: "Provide either a question or an analyzer_id" },
        400,
      );
    }

    // Context flows into params without overriding an explicit value.
    const ctxWorkoutId = body?.context?.workout_id;
    if (typeof ctxWorkoutId === "string" && rawParams.workout_id == null) {
      rawParams.workout_id = ctxWorkoutId;
    }

    const analyzer = getAnalyzer(analyzerId);

    // No analyzer fits → the prose fallthrough. The client sends this on to
    // `coaching-agent`, which is today's behaviour. The worst case for free
    // text is the product as it already is, never a wrong number.
    if (!analyzer) {
      await logQuery({
        user_id: userId,
        source,
        raw_question: question || null,
        analyzer_id: null,
        params: {},
        mode: ambiguous && candidates.length > 0 ? "ambiguous" : "prose",
        annotated: false,
        latency_ms: Date.now() - startedAt,
      });
      return jsonResponse({
        success: true,
        mode: ambiguous ? "ambiguous" : "prose",
        annotated: false,
        analyzer_id: null,
        facts: [],
        series: null,
        coverage: null,
        narration: null,
        followups: [],
        // Nothing computed fits, so the conversational answer IS the answer.
        // Under UNBOUND_ANSWERS the client no longer treats this as a dead end
        // to be reported ("NO ANALYZER") — it asks the agent and renders the
        // reply as a first-class answer.
        conversational: UNBOUND_ANSWERS && source === "text",
        // Disambiguation offers the 2-3 readings the router was actually torn
        // between. Returning the FULL catalog here — which is what this did
        // when the registry was three analyzers — is not disambiguation, it is
        // handing back the menu and asking the athlete to route their own
        // question. With ten analyzers that is a wall of chips.
        ...(ambiguous && candidates.length > 0
          ? {
            disambiguation: candidates
              .map((id) => ANALYZERS[id])
              .filter((a): a is NonNullable<typeof a> => a != null)
              .map((a) => ({ id: a.id, label: a.label })),
          }
          : {}),
      });
    }

    const params = coerceParams(analyzer, rawParams);

    // ── Layer 1 · always free, always runs ──
    const { zones, zoneTable } = await fetchZones(supabase, userId);
    const ctx: AnalyzerCtx = {
      userId,
      supabase,
      zones,
      zoneTable,
      now: new Date(),
    };
    const result = await analyzer.run(params, ctx);

    // ── Layer 2 · charged, and only when there is something to narrate ──
    // An empty state has no facts, so there is nothing a model could add that
    // wouldn't be invention. Skip it and keep the athlete's quota.
    const wantsNarration = body?.narrate !== false && result.empty == null &&
      result.facts.length > 0;

    let narration: Narration | null = null;
    let guardTripped = false;
    let modelUsed: string | null = null;

    if (wantsNarration) {
      // UNBOUND_USAGE: skip the meter entirely rather than calling it and
      // ignoring the verdict — the buckets stay unspent, so re-binding later
      // doesn't inherit a beta's worth of phantom consumption.
      const rlBlocked = UNBOUND_USAGE
        ? false
        : await enforceFeatureRateLimit(userId, "analysis", corsHeaders);
      const capped = rlBlocked || UNBOUND_USAGE
        ? null
        : await enforceMonthlyCap(userId, "analysis", corsHeaders);
      // Global spend brake, checked last so an already-blocked call does not
      // consume a ledger row. Degrades to bare facts rather than 429ing: the
      // facts are computed and free, and Layer 2 is the only paid part here.
      const budgetBlocked = (rlBlocked || capped)
        ? false
        : !(await llmBudgetAllows("ask_narrate", { userId }));
      if (rlBlocked || capped || budgetBlocked) {
        // Out of narration budget is NOT out of answer. Serve the facts.
        const why = budgetBlocked ? "global LLM budget" : "per-user quota";
        console.log(`ask: narration blocked by ${why} for ${userId} — serving bare facts`);
      } else {
        // `result.title` before `analyzer.label`: the standing label is a fixed
        // string ("Is my LT pace improving?") while the run may have resolved
        // to another band. Seeding the narrator with the label made it write
        // "your LT pace is improving" over facts that all said 10K — the guard
        // never caught it because it checks numbers, not zone names. The
        // resolved title is the only phrasing guaranteed to match the facts.
        const outcome = await narrate(
          question || result.title || analyzer.label,
          result,
          {
            sessionsUsed: result.coverage.sessionsUsed,
            windowDays: result.coverage.windowDays,
            params,
          },
        );
        narration = outcome.narration;
        guardTripped = outcome.guardTripped;
        modelUsed = outcome.modelUsed;
      }
    }

    const followups = result.related
      .map((id) => ANALYZERS[id])
      .filter((a): a is NonNullable<typeof a> => a != null)
      .map((a) => ({ id: a.id, label: a.label }));

    await logQuery({
      user_id: userId,
      source,
      raw_question: question || null,
      analyzer_id: analyzer.id,
      params,
      mode: "analyzed",
      annotated: narration != null,
      confidence: result.coverage.confidence,
      facts: result.facts,
      narration: narration?.text ?? null,
      latency_ms: Date.now() - startedAt,
      model_used: modelUsed,
      guard_tripped: guardTripped,
    });

    return jsonResponse({
      success: true,
      mode: "analyzed",
      annotated: narration != null,
      analyzer_id: analyzer.id,
      analyzer_label: analyzer.label,
      // Present only when the analyzer resolved to something narrower than
      // its standing label (zone_trend picking 10K over LT, say). The client
      // prefers this for the card headline so the title cannot contradict the
      // facts underneath it.
      resolved_title: result.title ?? null,
      facts: result.facts,
      series: result.series ?? null,
      coverage: result.coverage,
      empty: result.empty ?? null,
      // Other parameterizations of THIS analyzer, for the on-card switcher.
      // Re-run by posting {analyzer_id, params} from the chosen variant.
      variants: result.variants ?? null,
      narration,
      followups,
      // UNBOUND_ANSWERS: a matched analyzer no longer ENDS a typed question.
      // The athlete asked in prose and gets prose; this card renders beneath it
      // as the receipts. Chips stay computed-only — they asked for the card,
      // so handing them a paragraph would be answering a question they didn't
      // ask (and paying for a model call they didn't need).
      conversational: UNBOUND_ANSWERS && source === "text",
    });
  } catch (error) {
    console.error("ask error:", error);
    captureException(error, { fn: "ask" });
    await flushSentry();
    const message = error instanceof Error ? error.message : String(error);
    return jsonResponse({ error: "Failed to run analysis", details: message }, 500);
  }
});
