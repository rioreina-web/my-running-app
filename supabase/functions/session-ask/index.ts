/**
 * Session Ask
 *
 * Answers ONE question the athlete asked about ONE session in their log.
 *
 * ── Why this is its own function ──
 *
 * It is a sibling of `generate-workout-insight`, NOT a branch inside
 * `coaching-agent` (SESSION-ASK-APPLY.md §0.5, §5.3). Two reasons, one of
 * them a documented failure:
 *
 *   1. A coach in this product is a person — `coach_id`, the web coach
 *      portal, "one unread note from the athlete's coach". This surface reads
 *      training and reports what's in it. It doesn't own the decision or the
 *      relationship, so it doesn't get a coach persona and doesn't route
 *      through the chat agent.
 *   2. `HistoryDetailViewModel.swift:795` records what happened the last time
 *      a workout question went to that agent: handed almost no quantitative
 *      context, it followed its ask-vs-answer design and kept defaulting to
 *      "I need more info — what's your weekly mileage?". The fix then was to
 *      call a purpose-built endpoint by `training_log_id`. This belongs to
 *      that lineage.
 *
 * ── Context priority (§5.3) ──
 *
 * Fed to `assembleWithBudget`, never hand-concatenated. The note at
 * `coaching-agent/index.ts:1430` records why that assembler exists: 22 blocks
 * unconditionally concatenated, with no review-time signal when someone added
 * a 23rd.
 *
 *   athlete state  required   — without it the answer is fluent and useless
 *   this session   required   — what she is asking about
 *   recent logs    preferred  — her own words over ~28 days
 *
 * The athlete block is NOT the one to trim. A box that answers "was I holding
 * back?" without her volume, phase, goal and history reproduces the failure
 * above.
 *
 * Auth:
 *   - User JWT only. There is no service-role path: nothing enqueues this,
 *     an athlete asks it. `buildSessionBlock` enforces ownership itself
 *     (`.eq("user_id", userId)`), so another athlete's log is indistinguishable
 *     from one that doesn't exist — both 404.
 *
 * Status-code contract:
 *   200 — answered
 *   400 — bad request (missing question, non-UUID training_log_id)
 *   401 — no / invalid auth
 *   404 — training log not found, or not the caller's
 *   429 — daily or monthly rate limit hit
 *   502 — Gemini upstream failure
 *
 * Body:
 *   { question: string, training_log_id: string }
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { GoogleGenerativeAI } from "npm:@google/generative-ai@0.21.0";
import { corsHeaders } from "../_shared/cors.ts";
import { requireAuthOrServiceRole } from "../_shared/auth.ts";
import { enforceFeatureRateLimit, enforceMonthlyCap } from "../_shared/rateLimit.ts";
import { llmBudgetAllows, llmBudgetBlockedResponse } from "../_shared/llm-budget.ts";
import { loadPrompt } from "../_shared/prompt-library.ts";
import { captureException, flushSentry } from "../_shared/sentry.ts";
import {
  assembleWithBudget,
  buildAthleteStateBlock,
  buildSessionBlock,
  COMPLEXITY_CONTEXT_BUDGETS,
  type PromptBlock,
} from "../_shared/context.ts";
import { pickQuestions, RAIL_SIZE } from "../_shared/session-questions.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const geminiApiKey = Deno.env.get("GEMINI_API_KEY")!;

const adminClient = createClient(supabaseUrl, supabaseServiceKey);
const genAI = new GoogleGenerativeAI(geminiApiKey);

// Same tier as the insight it sits beside. This is a structured,
// context-grounded read, which is what Flash is good at; the answer is short
// prose with no tool use and no multi-step reasoning.
const SESSION_ASK_MODEL = "gemini-2.5-flash";

// Gemini 2.5 spends thinking tokens from this SAME budget before emitting
// text. Too low and the thinking pass swallows it whole, `.text()` throws and
// the caller sees a 502 with no answer — the failure that bricked voice-log
// insights on 2026-06-17. Generous ceiling; the answer is short, so this
// raises the thinking+answer headroom without padding normal-case cost.
const MAX_OUTPUT_TOKENS = 8192;

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// A question is free text from the athlete. Cap it so a paste-bomb can't
// blow the prompt budget or the bill; 500 chars is far past any real question.
const MAX_QUESTION_CHARS = 500;

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

/**
 * The provenance line (§3). Built from what the BUILDER actually loaded and
 * what the BUDGETER actually kept — a string assembled here, never a model
 * output, so it cannot claim a source that wasn't read.
 */
function buildReadFrom(
  parts: { splitsBlock: string; pacesBlock: string; conditionsBlock: string; recentLogs: string },
  present: Set<string>,
  athleteStateBlock: string,
): string {
  const bits: string[] = [];

  if (present.has("session")) {
    bits.push(parts.splitsBlock ? "this session's splits" : "this session");
    if (parts.pacesBlock) bits.push("your pace zones");
    if (parts.conditionsBlock) bits.push("the conditions on the day");
  }
  if (present.has("athleteState") && athleteStateBlock) {
    bits.push("your recent load and training context");
  }
  if (present.has("recentLogs") && parts.recentLogs) {
    bits.push("your notes from the last 28 days");
  }

  if (bits.length === 0) return "";
  if (bits.length === 1) return `Read from ${bits[0]}.`;
  return `Read from ${bits.slice(0, -1).join(", ")} and ${bits[bits.length - 1]}.`;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const startTime = Date.now();

  try {
    const body = await req.json().catch(() => ({}));

    // ── Auth ──
    // No `bodyUserId` is passed: this endpoint has no service-role caller, so
    // the subject is always the JWT's own user. Passing a body-supplied id
    // would only create a field to forge.
    const auth = await requireAuthOrServiceRole(req, null, corsHeaders);
    if ("response" in auth) return auth.response;
    const { userId } = auth;

    // ── Input ──
    const rawQuestion = (body as { question?: unknown }).question;
    if (typeof rawQuestion !== "string" || rawQuestion.trim().length === 0) {
      return jsonResponse({ error: "question is required" }, 400);
    }
    const question = rawQuestion.trim().slice(0, MAX_QUESTION_CHARS);

    const trainingLogId = (body as { training_log_id?: unknown }).training_log_id;
    if (typeof trainingLogId !== "string" || !UUID_RE.test(trainingLogId)) {
      return jsonResponse({ error: "training_log_id must be a UUID" }, 400);
    }

    // ── Rate limits ──
    // Daily bucket, then the hard monthly ceiling. Both come before any
    // context load: unlike the insight there is no cached-answer short-circuit
    // to sit behind, because every question is a different question.
    const rlBlocked = await enforceFeatureRateLimit(
      userId,
      "session_ask",
      corsHeaders,
      { isServiceRole: false },
    );
    if (rlBlocked) return rlBlocked;

    const capped = await enforceMonthlyCap(userId, "session_ask", corsHeaders, {
      isServiceRole: false,
    });
    if (capped) return capped;

    // App-wide budget guard — deliberately NOT keyed on the training log.
    //
    // `per_subject_24h_ceiling` is 6, and it exists to catch the Aug-11
    // signature: ONE row reprocessed in a loop by an idempotent job. That
    // reasoning fits `coach_insight`, which is fire-once per log, so a second
    // call on the same subject is already suspicious.
    //
    // This surface is the opposite by design — the rail offers five questions
    // and ten more behind the disclosure (§2), all about the SAME session.
    // Keying on the log would refuse an athlete's seventh question with a
    // budget error and make the feature's own rail a trap. A curious athlete
    // and a runaway loop are not the same event and must not share a counter.
    //
    // The brake is still on: the global daily ceiling applies (the migration
    // notes a NULL subject is "covered by the global ceiling only"), and the
    // per-user daily + monthly gates above bound any single athlete.
    if (!(await llmBudgetAllows("session_ask", { userId }))) {
      return llmBudgetBlockedResponse("session_ask", corsHeaders);
    }

    // ── Context ──
    // Ownership is enforced inside buildSessionBlock, so a log belonging to
    // someone else is indistinguishable from a missing one.
    const session = await buildSessionBlock(adminClient, userId, trainingLogId);
    if (!session) {
      return jsonResponse({ error: "Workout not found" }, 404);
    }

    const athleteStateBlock = await buildAthleteStateBlock(adminClient, userId);

    const blocks: PromptBlock[] = [
      { name: "athleteState", content: athleteStateBlock, priority: "required" },
      { name: "session", content: session.block, priority: "required" },
      { name: "recentLogs", content: session.parts.recentLogs, priority: "preferred" },
    ];
    const assembled = assembleWithBudget(blocks, COMPLEXITY_CONTEXT_BUDGETS.moderate);

    // `included` is whole blocks; `truncated` ones are partially present and
    // are still real provenance, so both count as "was read from".
    const present = new Set([...assembled.included, ...assembled.truncated]);

    console.log(
      `[session-ask] log=${trainingLogId} budget=${assembled.budget} used=${assembled.used} ` +
        `included=[${assembled.included.join(",")}] dropped=[${assembled.dropped.join(",")}] ` +
        `truncated=[${assembled.truncated.join(",")}]`,
    );

    // A block the budgeter dropped must not reach the prompt through one of
    // the per-part placeholders — that would make `read_from` a lie about
    // what was actually read.
    const sessionPresent = present.has("session");
    const blank = (v: string, ok: boolean) => (ok ? v : "");

    const prompt = loadPrompt("session-ask.v1", {
      question,
      workoutType: session.parts.workoutType,
      distance: session.parts.distance,
      pace: session.parts.pace,
      duration: session.parts.duration,
      mood: session.parts.mood,
      // The memo is a BLOCK here, not the `- Athlete notes:` bullet v6 still
      // takes (§5.5). It carries the note, the reported RPE and the verbatim
      // pull quote, so "how hard was this, really?" can read their own effort
      // rating instead of inferring one from pace and heart rate.
      memoBlock: blank(session.parts.memoBlock, sessionPresent),
      pacesBlock: blank(session.parts.pacesBlock, sessionPresent),
      classificationLine: blank(session.parts.classificationLine, sessionPresent),
      splitsBlock: blank(session.parts.splitsBlock, sessionPresent),
      prescribedBlock: blank(session.parts.prescribedBlock, sessionPresent),
      progressionBlock: blank(session.parts.progressionBlock, sessionPresent),
      keySessionLine: blank(session.parts.keySessionLine, sessionPresent),
      athleteState: blank(athleteStateBlock, present.has("athleteState")),
      recentLogs: blank(session.parts.recentLogs, present.has("recentLogs")),
      recentSummary: session.parts.recentSummary,
    });

    // ── Model ──
    let answer = "";
    try {
      const model = genAI.getGenerativeModel({
        model: SESSION_ASK_MODEL,
        generationConfig: { temperature: 0.7, maxOutputTokens: MAX_OUTPUT_TOKENS },
      });

      const result = await Promise.race([
        model.generateContent(prompt),
        new Promise<never>((_, reject) =>
          setTimeout(() => reject(new Error("Gemini timeout")), 45_000)
        ),
      ]);

      const response = (result as Awaited<ReturnType<typeof model.generateContent>>).response;
      const finishReason = response.candidates?.[0]?.finishReason;

      // `.text()` THROWS when the candidate carries no text part — the whole
      // budget went to thinking tokens (MAX_TOKENS), or a safety stop. Say
      // WHY rather than collapsing to a silent 502.
      try {
        answer = (response.text() ?? "").trim();
      } catch (textErr) {
        console.error(`[session-ask] no text part (finishReason=${finishReason}):`, textErr);
        answer = "";
      }

      if (!answer) {
        console.error(`[session-ask] empty answer (finishReason=${finishReason})`);
        return jsonResponse({ error: "Upstream model failure" }, 502);
      }
    } catch (err) {
      console.error("[session-ask] model call failed:", err);
      captureException(err, { fn: "session-ask", trainingLogId });
      return jsonResponse({ error: "Upstream model unavailable" }, 502);
    }

    // ── Response ──
    // The rail ships in the RESPONSE, not the binary (§2, §8): changing what
    // a long run asks is a server edit, not an App Store release.
    const suggested = pickQuestions(session.shape).map((q) => ({ id: q.id, text: q.text }));

    const readFrom = buildReadFrom(
      {
        splitsBlock: session.parts.splitsBlock,
        pacesBlock: session.parts.pacesBlock,
        conditionsBlock: session.parts.conditionsBlock,
        recentLogs: session.parts.recentLogs,
      },
      present,
      athleteStateBlock,
    );

    try {
      await adminClient.from("usage_tracking").insert({
        user_id: userId,
        feature: "session_ask",
        model_used: SESSION_ASK_MODEL,
        cached: false,
      });
    } catch (_) {
      /* never block the answer on telemetry */
    }

    return jsonResponse({
      answer,
      read_from: readFrom,
      suggested,
      rail_size: RAIL_SIZE,
      training_log_id: trainingLogId,
      model: "session-ask.v1",
      provider: "gemini",
      processingTime: Date.now() - startTime,
    });
  } catch (err) {
    console.error("[session-ask] unhandled:", err);
    captureException(err, { fn: "session-ask" });
    return jsonResponse({ error: "Internal error" }, 500);
  } finally {
    await flushSentry();
  }
});
