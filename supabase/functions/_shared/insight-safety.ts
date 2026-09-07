/**
 * Runtime safety guard for AI coaching output — CLAUDE.md hard rule #2:
 * "AI never recommends stopping training, diagnosing injuries, or making
 * medical claims."
 *
 * Prompts instruct the model to surface (not diagnose) and to leave rest/
 * medical decisions to the athlete, but instructions slip. This module is the
 * ENFORCED net: scan generated text before it's persisted or shown. A flagged
 * output should be regenerated once under INSIGHT_STRICT_SUFFIX; if it still
 * trips, the caller must NOT show it (fall back to a deterministic read).
 *
 * Patterns are high-precision on purpose — the cost of a false positive is
 * silently dropping a fine coaching observation, so we only match clear
 * diagnoses, medical referrals, and stop/rest directives, not every mention
 * of a body part or the word "rest".
 *
 * Shared so every AI surface (workout insight, daily read, injury warning,
 * check-in) can enforce the same rule. Pure + dependency-free → unit tested in
 * insight-safety.test.ts.
 */

export const INSIGHT_BANNED: Array<{ label: string; re: RegExp }> = [
  // Named clinical diagnoses — surface the body part, never name a condition.
  {
    label: "diagnosis",
    re: /\b(ITBS|IT band syndrome|tendin(itis|opathy)|plantar fasciitis|stress fracture|shin splints|runner'?s knee|diagnos\w*)\b/i,
  },
  // "see / consult / seek a doctor / physio / medical professional".
  {
    label: "medical-referral",
    re: /\b(see|consult|seek|visit)\b[^.]{0,30}\b(doctor|physician|physio(therapist)?|physical therapist|medical|healthcare|specialist)\b/i,
  },
  { label: "medical-referral", re: /\bseek\s+medical\b/i },
  // Directives to stop or rest the running (advice, not observation).
  { label: "stop-training", re: /\b(stop|cease|quit)\s+(running|training)\b/i },
  {
    label: "stop-training",
    re: /\b(tak(e|ing)|get(ting)?|need(s|ing)?|consider(ing)?|recommend|suggest)\b[^.]{0,20}\b(time off|days?\s+off|rest days?)\b/i,
  },
  {
    label: "stop-training",
    re: /\b(you should|i'?d?\s*(recommend|suggest|advise))\b[^.]{0,20}\brest(ing)?\b/i,
  },
];

/** Rule-#2 categories the text trips, or [] when clean. */
export function insightSafetyViolations(text: string): string[] {
  const hits = new Set<string>();
  for (const { label, re } of INSIGHT_BANNED) {
    if (re.test(text)) hits.add(label);
  }
  return [...hits];
}

/** Appended to the prompt on the one stricter retry after a guard trip. */
export const INSIGHT_STRICT_SUFFIX =
  "STRICT SAFETY: Do not name or imply any medical condition or injury " +
  "diagnosis, do not advise rest/time off/stopping running, and do not " +
  "suggest seeing a doctor, physio, or medical professional. If a niggle is " +
  'relevant, note only what was observed (e.g. "the calf you mentioned") ' +
  "and leave the decision to the athlete. Rewrite as a pure observation.";
