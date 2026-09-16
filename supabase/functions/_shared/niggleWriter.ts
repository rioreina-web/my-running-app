/**
 * Niggle writer — the memo pipeline's body-mentions classifier
 * (audit fix #2, 2026-07-02).
 *
 * Splits into a PURE transform (`buildNiggleRows`) and a thin I/O wrapper
 * (`writeNiggleMentions`). The pure function carries all the logic worth
 * testing: it runs the LLM's `soreness` entries through the CLOSED
 * body-part vocabulary (`bodyVocabulary.ts`), drops anything unmappable
 * (detection-not-diagnosis — never invent a body_area), and dedupes to
 * one row per area (worst severity wins), since the `body_mentions`
 * unique index is (user_id, training_log_id, body_area) and can't hold
 * laterality in its key.
 *
 * Lives in `_shared/` (not inside the edge function) so it's importable
 * by tests without booting the function's `Deno.serve`.
 */

import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  normalizeBodyMention,
  SEVERITY_ORDER,
  severityHintFromText,
  severityHintFromWord,
} from "./bodyVocabulary.ts";

/** A row shaped for the `body_mentions` table. */
export interface NiggleRow {
  user_id: string;
  training_log_id: string;
  body_area: string;
  side: "left" | "right" | null;
  verbatim_quote: string;
  severity_hint: string;
  mentioned_at: string;
  source: string;
  updated_at: string;
}

/** One normalized soreness entry (v2 object shape, or coerced from a string). */
interface SorenessEntry {
  location: string;
  their_words: string;
  severity_word: string;
}

/** Coerce the LLM's `soreness` (array of objects or bare strings) to entries. */
function coerceSorenessEntries(raw: unknown): SorenessEntry[] {
  if (!Array.isArray(raw)) return [];
  return raw
    .map((e): SorenessEntry => {
      if (typeof e === "string") return { location: e, their_words: e, severity_word: "" };
      if (e && typeof e === "object") {
        const o = e as Record<string, unknown>;
        return {
          location: typeof o.location === "string" ? o.location : "",
          their_words: typeof o.their_words === "string" ? o.their_words : "",
          severity_word: typeof o.severity_word === "string" ? o.severity_word : "",
        };
      }
      return { location: "", their_words: "", severity_word: "" };
    })
    .filter((e) => e.location.trim().length > 0);
}

/**
 * PURE: turn `extracted_data.soreness` into `body_mentions` rows. Unmappable
 * locations are dropped (returned separately for logging). One row per
 * body_area (worst severity kept), since the upsert conflict key can't
 * include side.
 */
export function buildNiggleRows(
  userId: string,
  trainingLogId: string,
  mentionedAt: string,
  extracted: Record<string, unknown> | null | undefined,
  nowIso: string = new Date().toISOString(),
): { rows: NiggleRow[]; dropped: string[] } {
  const dropped: string[] = [];
  if (!extracted) return { rows: [], dropped };

  const entries = coerceSorenessEntries(extracted.soreness);
  const byArea = new Map<string, NiggleRow>();

  for (const e of entries) {
    const mapped = normalizeBodyMention(e.location);
    if (!mapped) {
      dropped.push(e.location);
      continue;
    }
    const severityHint =
      severityHintFromWord(e.severity_word) ??
      severityHintFromText(e.their_words) ??
      "sore"; // honest floor: a body part was named in a soreness context
    const verbatim = (e.their_words.trim() || e.location.trim()).slice(0, 400);
    const row: NiggleRow = {
      user_id: userId,
      training_log_id: trainingLogId,
      body_area: mapped.body_area,
      side: mapped.side,
      verbatim_quote: verbatim,
      severity_hint: severityHint,
      mentioned_at: mentionedAt.slice(0, 10),
      source: "memo_llm",
      updated_at: nowIso,
    };
    const prev = byArea.get(mapped.body_area);
    if (!prev || (SEVERITY_ORDER[severityHint] ?? 0) > (SEVERITY_ORDER[prev.severity_hint] ?? 0)) {
      byArea.set(mapped.body_area, row);
    }
  }

  return { rows: [...byArea.values()], dropped };
}

/** A row shaped for the `niggle_resolutions` table. */
export interface NiggleResolutionRow {
  user_id: string;
  training_log_id: string | null;
  body_area: string;
  side: "left" | "right" | null;
  resolved_at: string;
  source: string;
  verbatim_quote: string | null;
}

/**
 * PURE: turn `extracted_data.resolved_niggles` into `niggle_resolutions`
 * rows — the athlete's all-clear signal. Same closed-vocabulary mapping as
 * mentions (unmappable locations dropped, never invented). One row per
 * body_area (the upsert conflict key). Side is carried so a "left knee is
 * fine" resolution clears the left knee specifically.
 */
export function buildNiggleResolutions(
  userId: string,
  trainingLogId: string,
  resolvedAt: string,
  extracted: Record<string, unknown> | null | undefined,
): { rows: NiggleResolutionRow[]; dropped: string[] } {
  const dropped: string[] = [];
  if (!extracted) return { rows: [], dropped };

  const raw = extracted.resolved_niggles;
  if (!Array.isArray(raw)) return { rows: [], dropped };

  const entries = raw
    .map((e): { location: string; their_words: string } => {
      if (typeof e === "string") return { location: e, their_words: e };
      if (e && typeof e === "object") {
        const o = e as Record<string, unknown>;
        return {
          location: typeof o.location === "string" ? o.location : "",
          their_words: typeof o.their_words === "string" ? o.their_words : "",
        };
      }
      return { location: "", their_words: "" };
    })
    .filter((e) => e.location.trim().length > 0);

  const byArea = new Map<string, NiggleResolutionRow>();
  for (const e of entries) {
    const mapped = normalizeBodyMention(e.location);
    if (!mapped) {
      dropped.push(e.location);
      continue;
    }
    byArea.set(mapped.body_area, {
      user_id: userId,
      training_log_id: trainingLogId,
      body_area: mapped.body_area,
      side: mapped.side,
      resolved_at: resolvedAt.slice(0, 10),
      source: "memo_llm",
      verbatim_quote: (e.their_words.trim() || e.location.trim()).slice(0, 400),
    });
  }
  return { rows: [...byArea.values()], dropped };
}

/**
 * I/O wrapper: record the athlete's all-clear signals from a memo. Never
 * throws — a resolution-write failure must not fail memo processing.
 */
export async function writeNiggleResolutions(
  supabaseClient: SupabaseClient,
  userId: string,
  trainingLogId: string,
  resolvedAt: string,
  extracted: Record<string, unknown> | null | undefined,
): Promise<number> {
  try {
    const { rows, dropped } = buildNiggleResolutions(userId, trainingLogId, resolvedAt, extracted);
    for (const loc of dropped) {
      console.log(`[niggleWriter] resolution dropped (unmappable location): "${loc}"`);
    }
    if (rows.length === 0) return 0;

    const { error } = await supabaseClient
      .from("niggle_resolutions")
      .upsert(rows, { onConflict: "user_id,training_log_id,body_area" });
    if (error) {
      console.warn(`[niggleWriter] niggle_resolutions upsert failed: ${error.message}`);
      return 0;
    }
    console.log(
      `[niggleWriter] recorded ${rows.length} niggle resolution(s): ` +
        rows.map((r) => `${r.side ? r.side + " " : ""}${r.body_area}`).join(", "),
    );
    return rows.length;
  } catch (e) {
    console.warn(`[niggleWriter] writeNiggleResolutions error: ${e instanceof Error ? e.message : String(e)}`);
    return 0;
  }
}

/**
 * I/O wrapper: build rows and upsert them to `body_mentions`. Runs
 * service-role (RLS is not the silent no-op it is on the athlete-state
 * rebuild path). Never throws — a niggle-write failure must not fail memo
 * processing. Returns the count written.
 */
export async function writeNiggleMentions(
  supabaseClient: SupabaseClient,
  userId: string,
  trainingLogId: string,
  mentionedAt: string,
  extracted: Record<string, unknown> | null | undefined,
): Promise<number> {
  try {
    const { rows, dropped } = buildNiggleRows(userId, trainingLogId, mentionedAt, extracted);
    for (const loc of dropped) {
      console.log(`[niggleWriter] dropped (unmappable location): "${loc}"`);
    }
    if (rows.length === 0) return 0;

    const { error } = await supabaseClient
      .from("body_mentions")
      .upsert(rows, { onConflict: "user_id,training_log_id,body_area" });
    if (error) {
      console.warn(`[niggleWriter] body_mentions upsert failed: ${error.message}`);
      return 0;
    }
    console.log(
      `[niggleWriter] wrote ${rows.length} niggle mention(s): ` +
        rows.map((r) => `${r.side ? r.side + " " : ""}${r.body_area}[${r.severity_hint}]`).join(", "),
    );
    return rows.length;
  } catch (e) {
    console.warn(`[niggleWriter] error: ${e instanceof Error ? e.message : String(e)}`);
    return 0;
  }
}
