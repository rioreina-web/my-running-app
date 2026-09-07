/**
 * Pace readback guard — the free-prose counterpart of narration-guard.
 *
 * narration-guard protects the two-sentence Ask narration by checking every
 * numeric token against fact lines. coaching-agent's conversational answers
 * (what the Ask tab leads with for typed questions, per UNBOUND_ANSWERS)
 * have no such check, and that is exactly where wrong paces shipped: the
 * model, handed a run's segment paces, presented a single rep's pace as the
 * run's pace ("5:36/mi" for a run whose true average was 5:48 — and, worse,
 * 8:27), then compounded it with a self-computed heat adjustment.
 *
 * The contract here is narrower than narration-guard's, because coaching
 * prose legitimately derives numbers (deltas, weekly sums). This guard
 * checks only PACE CLAIMS — "M:SS/mi", "M:SS per mile", "M:SS pace" — and
 * licenses them against the set of M:SS tokens that actually appear in the
 * prompt. Session averages, segment paces, zone paces, and (since the
 * 2026-09-01 fix) code-computed effort-equivalent paces are all printed in
 * context, so any honest pace claim is licensed. An unlicensed pace claim
 * means the model did arithmetic of its own — the one thing it must not do.
 *
 * Pure functions, no I/O. The caller decides the retry/serve policy.
 */

/** A pace-shaped claim in prose: the M:SS immediately tied to a per-mile unit
 *  or the word "pace". Bare times ("43:20", "2:37 marathon") do not match —
 *  durations and race times are outside this guard's scope. */
const PACE_CLAIM_RE =
  /(\d{1,2}:[0-5]\d)\s*(?:\/\s*mi(?:le)?\b|(?:min(?:ute)?s?\s+)?per\s+mile\b|\s+(?:mile\s+)?pace\b)/gi;

/** Any M:SS token — used to build the licensed set from the prompt. Looser on
 *  purpose: a duration in context licensing an identical-looking pace claim is
 *  a harmless coincidence, while a pace in context failing to license itself
 *  is a false positive. */
const TIME_TOKEN_RE = /\b(\d{1,2}):([0-5]\d)\b/g;

/** Every M:SS token in the text the model was shown. */
export function licensedTimeTokens(promptText: string): Set<string> {
  const out = new Set<string>();
  for (const m of promptText.matchAll(TIME_TOKEN_RE)) {
    out.add(`${parseInt(m[1], 10)}:${m[2]}`);
  }
  return out;
}

/** Pace claims in `response` whose M:SS token never appeared in the prompt.
 *  Deduplicated, in order of first appearance. */
export function findUnlicensedPaces(
  response: string,
  licensed: Set<string>,
): string[] {
  const offenders: string[] = [];
  const seen = new Set<string>();
  for (const m of response.matchAll(PACE_CLAIM_RE)) {
    const token = m[1].replace(/^0(?=\d:)/, "");
    const normalized = `${parseInt(token.split(":")[0], 10)}:${token.split(":")[1]}`;
    if (!licensed.has(normalized) && !seen.has(normalized)) {
      offenders.push(m[1]);
      seen.add(normalized);
    }
  }
  return offenders;
}

/** One-line correction appended to the prompt for the retry. Names the
 *  offending figures so the model can see its own error, and restates the
 *  licensing rule rather than trusting it was absorbed the first time. */
export function paceCorrectionNote(offenders: string[]): string {
  return (
    `\n\nIMPORTANT CORRECTION — your previous draft stated pace figures ` +
    `(${offenders.join(", ")}) that do not appear anywhere in the athlete's ` +
    `data above. That is a factual error the athlete will see. Rewrite your ` +
    `answer using ONLY pace figures printed in the context. A run's overall ` +
    `pace is its "(session avg)" figure; heat-adjusted effort is the printed ` +
    `"effort-equivalent" figure. If a figure you need is not in the context, ` +
    `say so plainly instead of estimating one.`
  );
}
