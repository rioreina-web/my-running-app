/**
 * suggest-workout-progression — advisory LLM layer for the coach portal's
 * "smart duplicate" flow.
 *
 * The client generates progression candidates DETERMINISTICALLY (closed
 * move set, pace zone never changes — see web workout-helpers.ts:
 * generateProgressionCandidates). This function asks Gemini to do exactly
 * two things with that fixed menu:
 *   1. rank the candidates (most → least natural next step)
 *   2. write a one-sentence advisory note per candidate
 *
 * The model may only reorder/annotate the PROVIDED candidates. Its output
 * is validated against the input candidate ids; any parse or validation
 * failure falls back to the deterministic order with no notes
 * (`annotated: false`). No step structures are ever accepted from — or
 * returned by — the model, so it cannot invent workouts by construction.
 *
 * AI advises, never acts: nothing here writes to the DB. The coach picks
 * a candidate in the editor (or none) and saves explicitly.
 *
 * Request body:
 *   {
 *     sourceWorkout: { name: string, summary?: string | null },
 *     candidates: [{ id: string, label: string, detail?: string | null }]
 *   }
 *
 * Response:
 *   { success: true, annotated: boolean,
 *     suggestions: [{ id: string, note?: string }] }
 */

import { GoogleGenerativeAI } from "https://esm.sh/@google/generative-ai@0.24.0";
import { getAuthenticatedUser, unauthorizedResponse } from "../_shared/auth.ts";
import { enforceFeatureRateLimit, enforceMonthlyCap } from "../_shared/rateLimit.ts";
import { loadPrompt } from "../_shared/prompt-library.ts";
import { corsHeaders } from "../_shared/cors.ts";

const MAX_CANDIDATES = 6;
const MAX_NOTE_CHARS = 160;

interface CandidateInput {
  id: string;
  label: string;
  detail?: string | null;
}

interface Suggestion {
  id: string;
  note?: string;
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

/** Deterministic fallback — input order, no notes. */
function fallbackSuggestions(candidates: CandidateInput[]): Suggestion[] {
  return candidates.map((c) => ({ id: c.id }));
}

/**
 * Parse + validate the model output. Returns null on ANY violation —
 * unparseable JSON, unknown ids, duplicates, non-string notes — so the
 * caller falls back to the deterministic order. Candidates the model
 * skipped are appended in deterministic order without notes.
 */
function validateRanking(
  text: string,
  candidates: CandidateInput[],
): Suggestion[] | null {
  let raw = text.trim();
  // Tolerate a markdown fence around the JSON (same lenience as
  // reschedule-plan's extractor) — but nothing beyond that.
  const fenced = raw.match(/```(?:json)?\s*([\s\S]*?)```/);
  if (fenced) raw = fenced[1].trim();

  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return null;
  }
  if (!parsed || typeof parsed !== "object") return null;
  const ranking = (parsed as { ranking?: unknown }).ranking;
  if (!Array.isArray(ranking) || ranking.length === 0) return null;

  const knownIds = new Set(candidates.map((c) => c.id));
  const seen = new Set<string>();
  const out: Suggestion[] = [];

  for (const entry of ranking) {
    if (!entry || typeof entry !== "object") return null;
    const { id, note } = entry as { id?: unknown; note?: unknown };
    // The model referenced a candidate we never gave it → reject wholesale.
    if (typeof id !== "string" || !knownIds.has(id)) return null;
    if (seen.has(id)) return null;
    seen.add(id);
    const cleanNote =
      typeof note === "string" && note.trim().length > 0
        ? note.trim().slice(0, MAX_NOTE_CHARS)
        : undefined;
    out.push({ id, note: cleanNote });
  }

  // Anything the model skipped keeps its deterministic slot at the end.
  for (const c of candidates) {
    if (!seen.has(c.id)) out.push({ id: c.id });
  }
  return out;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const userId = await getAuthenticatedUser(req);
    if (!userId) return unauthorizedResponse(corsHeaders);

    const rlBlocked = await enforceFeatureRateLimit(userId, "workout_progression", corsHeaders);
    if (rlBlocked) return rlBlocked;
    const monthlyCapped = await enforceMonthlyCap(userId, "workout_progression", corsHeaders);
    if (monthlyCapped) return monthlyCapped;

    const body = await req.json().catch(() => null);
    const sourceWorkout = body?.sourceWorkout as { name?: unknown; summary?: unknown } | undefined;
    const rawCandidates = body?.candidates as unknown;

    if (
      !sourceWorkout ||
      typeof sourceWorkout.name !== "string" ||
      !Array.isArray(rawCandidates) ||
      rawCandidates.length === 0
    ) {
      return jsonResponse(
        { error: "Missing required fields: sourceWorkout.name, candidates[]" },
        400,
      );
    }

    const candidates: CandidateInput[] = [];
    for (const c of rawCandidates.slice(0, MAX_CANDIDATES)) {
      if (!c || typeof c !== "object") continue;
      const { id, label, detail } = c as Record<string, unknown>;
      if (typeof id !== "string" || id.length === 0) continue;
      if (typeof label !== "string" || label.length === 0) continue;
      candidates.push({
        id,
        label,
        detail: typeof detail === "string" ? detail : null,
      });
    }
    if (candidates.length === 0) {
      return jsonResponse({ error: "No valid candidates supplied" }, 400);
    }

    const sourceLine = `${sourceWorkout.name}${
      typeof sourceWorkout.summary === "string" && sourceWorkout.summary.length > 0
        ? ` — ${sourceWorkout.summary}`
        : ""
    }`;
    const candidateLines = candidates
      .map((c, i) => `${i + 1}. ${c.id} | ${c.label}${c.detail ? ` | ${c.detail}` : ""}`)
      .join("\n");

    const prompt = loadPrompt("suggest-workout-progression.v1", {
      sourceWorkout: sourceLine,
      candidates: candidateLines,
    });

    const apiKey = Deno.env.get("GEMINI_API_KEY");
    if (!apiKey) {
      // Advisory layer only — degrade to deterministic order rather than
      // failing the duplicate flow over a missing key.
      console.error("suggest-workout-progression: GEMINI_API_KEY not configured");
      return jsonResponse({
        success: true,
        annotated: false,
        suggestions: fallbackSuggestions(candidates),
      });
    }

    let suggestions: Suggestion[] | null = null;
    try {
      const genAI = new GoogleGenerativeAI(apiKey);
      const model = genAI.getGenerativeModel({ model: "gemini-2.5-flash" });
      const result = await model.generateContent({
        contents: [{ role: "user", parts: [{ text: prompt }] }],
        generationConfig: {
          temperature: 0.2,
          maxOutputTokens: 1024,
        },
      });
      suggestions = validateRanking(result.response.text(), candidates);
    } catch (llmError) {
      console.error("suggest-workout-progression: LLM call failed", llmError);
      suggestions = null;
    }

    if (!suggestions) {
      return jsonResponse({
        success: true,
        annotated: false,
        suggestions: fallbackSuggestions(candidates),
      });
    }

    return jsonResponse({ success: true, annotated: true, suggestions });
  } catch (error) {
    console.error("suggest-workout-progression error:", error);
    return jsonResponse(
      { error: "Failed to suggest progressions", details: String(error) },
      500,
    );
  }
});
