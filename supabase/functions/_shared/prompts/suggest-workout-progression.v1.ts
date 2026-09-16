/**
 * Suggest-workout-progression system prompt — v1.
 *
 * Advisory annotation layer for the coach portal's "smart duplicate" flow.
 * The web client generates progression candidates DETERMINISTICALLY (a
 * closed move set — +1 rep, longer reps on the canonical ladder, tighter
 * recovery, +volume ≤10% — pace zone never changes; see
 * web/src/components/coach/workout-helpers.ts:generateProgressionCandidates).
 *
 * This prompt's ONLY job is to rank those candidates and write a
 * one-sentence advisory note for each. It must never invent new workout
 * structures — the edge function validates every returned id against the
 * provided candidate list and falls back to the deterministic order on any
 * violation or parse failure. AI advises, never acts: the coach picks a
 * candidate (or none) and edits freely before saving.
 *
 * NOT a golden prompt family (hard rule #3) — cassettes under
 * _evals/cassettes/suggest-workout-progression.v1/ are authored as stubs
 * and should be recorded opportunistically; the gate is manual review
 * against docs/coaching/principles.md.
 *
 * Consumed by `supabase/functions/suggest-workout-progression/index.ts`.
 *
 * Substitution placeholders:
 *   sourceWorkout — one-line description of the workout being duplicated
 *                   (name + structure summary), pre-formatted by the caller
 *   candidates    — numbered list of candidate lines "id | label | detail",
 *                   pre-formatted by the caller
 */

export const TEMPLATE = `You are an experienced running coach reviewing progression options for a workout a coach is duplicating into their library.

THE SOURCE WORKOUT:
{{sourceWorkout}}

THE CANDIDATES (already generated — a fixed menu, not suggestions to expand on):
{{candidates}}

YOUR JOB:
1. Rank the candidates from most to least natural as the next step in a typical progression.
2. Write ONE short advisory sentence for each (max ~20 words), e.g. "Natural next step if last week's reps felt controlled."

HARD RULES:
- You may ONLY reference the candidate ids given above. Never invent, merge, or modify candidates. Never propose new workout structures, distances, paces, or zones.
- Notes are observations for the coach, not instructions to the athlete. No "you should", no prescriptions, no medical or injury claims.
- Never suggest changing the pace zone — progression here is structural (reps, distance, recovery, volume), by design.
- Plain language, no markdown, no exclamation marks.

OUTPUT FORMAT — respond with ONLY this JSON, nothing else:
{"ranking":[{"id":"<candidate id>","note":"<one sentence>"}, ...]}

Include every candidate exactly once.`;
