/**
 * Body-part vocabulary — single source of truth for niggle detection.
 *
 * Both niggle writers use this module: the memo-pipeline classifier
 * (process-training-memo) and the regex backfill scan (athlete-state).
 * Pure functions, no I/O — trivially testable, trivially bundled.
 *
 * The contract (CLAUDE.md hard rule #2 — detection, not diagnosis):
 *   - `BODY_AREAS` is a CLOSED vocabulary. Free text maps to a canonical
 *     key or is dropped. Unknown terms are never invented; diagnosis
 *     names ("ITBS", "tendinitis") are rejected, not mapped — only the
 *     anatomical LOCATION survives.
 *   - `SEVERITY_HINTS` is a CLOSED vocabulary: tight | sore | pain | sharp.
 *   - `normalizeBodyMention` extracts left/right laterality and the
 *     canonical area, returning null for anything unmappable.
 *
 * Nothing here interprets, diagnoses, or recommends. It reports WHAT was
 * said and WHERE. That contract is enforced in code (this module), not
 * trusted to the LLM.
 */

/** Closed severity vocabulary, highest-priority first. */
export const SEVERITY_HINT_VALUES = ["sharp", "pain", "sore", "tight"] as const;
export type SeverityHint = typeof SEVERITY_HINT_VALUES[number];

/**
 * Word → severity-hint mapping. Ordered most-severe first: when several
 * words appear near a mention, the strongest one wins. Mirrors the
 * historical scan in athlete-state.ts so behavior is unchanged for the
 * regex-backfill path.
 */
export const SEVERITY_HINTS: Array<[RegExp, SeverityHint]> = [
  [/\b(sharp|stabbing|burning|shooting|sudden)\b/i, "sharp"],
  [/\b(pain|painful|hurts?|hurting|injured|injury|strained?|pulled|tear|torn|pop(?:ped)?)\b/i, "pain"],
  [/\b(sore|soreness|ache|aching|achy|stiff|stiffness|nagging|niggle|niggly|bother(?:ing|ed)?)\b/i, "sore"],
  [/\b(tight|tightness|tweak|tweaky|tweaked|cranky|fatigued?)\b/i, "tight"],
];

/**
 * Closed body-part vocabulary. Each entry is a canonical key plus the
 * accepted synonyms that map ONTO it. Diagnoses are deliberately absent:
 * "IT band" (the location) is present; "ITBS" (the condition) is not, so
 * it falls through to null. Add a synonym to broaden mapping without a
 * migration — the DB stores the canonical key, not this table.
 *
 * Synonyms are matched as whole words/phrases (word-boundary), and the
 * LONGEST matching synonym wins so "lower back" beats "back" and
 * "hip flexor" beats "hip".
 */
export const BODY_AREAS: Record<string, string[]> = {
  "achilles": ["achilles", "achilles tendon", "achilles heel"],
  "calf": ["calf", "calves", "gastroc", "gastrocnemius"],
  "soleus": ["soleus"],
  "shin": ["shin", "shins", "tibia", "tibialis", "tib", "shin splint", "shin splints"],
  "peroneal": ["peroneal", "peroneals", "peroneus"],
  "ankle": ["ankle", "ankles", "subtalar", "malleolus"],
  "heel": ["heel", "heels"],
  "plantar": ["plantar", "plantar fascia", "plantar fasciia", "arch", "arches", "instep"],
  "foot": ["foot", "feet", "metatarsal", "midfoot", "forefoot"],
  "top of foot": ["top of foot", "top of the foot", "top of my foot", "dorsal foot"],
  "toe": ["toe", "toes", "big toe", "sesamoid"],
  "knee": ["knee", "knees", "kneecap", "patella", "patellar"],
  "quad": ["quad", "quads", "quadricep", "quadriceps", "thigh", "front of thigh"],
  "hamstring": ["hamstring", "hamstrings", "hammy", "hammies", "back of thigh"],
  "adductor": ["adductor", "adductors", "inner thigh", "groin muscle"],
  "groin": ["groin"],
  "hip flexor": ["hip flexor", "hip flexors", "psoas"],
  "hip": ["hip", "hips", "hip labrum", "labrum"],
  "glute": ["glute", "glutes", "gluteal", "buttock", "buttocks", "butt"],
  "piriformis": ["piriformis"],
  "it band": ["it band", "itband", "iliotibial band", "iliotibial", "it-band"],
  "si joint": ["si joint", "s.i. joint", "sacroiliac", "sacrum", "sacral"],
  "lower back": ["lower back", "low back", "lumbar"],
  "back": ["back", "upper back", "mid back", "spine"],
  "neck": ["neck", "cervical"],
  "shoulder": ["shoulder", "shoulders", "trap", "traps", "trapezius"],
};

/** All (canonical, synonym) pairs, sorted longest-synonym-first. */
const SYNONYM_INDEX: Array<{ canonical: string; synonym: string }> = Object
  .entries(BODY_AREAS)
  .flatMap(([canonical, syns]) => syns.map((synonym) => ({ canonical, synonym })))
  .sort((a, b) => b.synonym.length - a.synonym.length);

/** Escape a string for safe use inside a RegExp. */
function escapeRe(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

/** Whole-word/phrase test for a synonym inside a candidate string. */
function containsWord(haystack: string, needle: string): boolean {
  return new RegExp(`(?:^|[^a-z])${escapeRe(needle)}(?:$|[^a-z])`, "i").test(haystack);
}

/** Left/right side tokens. "both"/"bilateral" is recognized but not laterizable. */
const SIDE_PATTERNS: Array<[RegExp, "left" | "right" | "both"]> = [
  [/\b(left|lt|l\.?)\b/i, "left"],
  [/\b(right|rt|r\.?)\b/i, "right"],
  [/\b(both|bilateral|either)\b/i, "both"],
];

/**
 * Extract left/right laterality from free text. "both"/"bilateral" maps to
 * null (a single `side` column can't hold both; the mention is recorded
 * unsided rather than mislabeled). Returns the detected side and the text
 * with side/filler tokens stripped, ready for area matching.
 */
function extractSide(raw: string): { side: "left" | "right" | null; rest: string } {
  let side: "left" | "right" | null = null;
  for (const [re, label] of SIDE_PATTERNS) {
    if (re.test(raw)) {
      if (label === "left" || label === "right") side = label;
      break; // first match wins; "left and right" is unusual — take the first
    }
  }
  const rest = raw
    .replace(/\b(left|right|lt|rt|both|bilateral|either|l\.?|r\.?)\b/gi, " ")
    .replace(/\b(my|the|a|an|his|her|their|some|this|that|side)\b/gi, " ")
    .replace(/['’]s\b/gi, " ")
    .replace(/[^a-z ]+/gi, " ")
    .replace(/\s+/g, " ")
    .trim();
  return { side, rest };
}

/**
 * Map free text ("left knee", "R achilles", "my right calf", "sore IT band")
 * to the closed vocabulary. Returns null for anything unmappable — a
 * diagnosis with no location ("ITBS", "tendinitis"), an unknown term, or
 * empty input. The longest matching synonym wins so multi-word areas
 * ("lower back", "hip flexor") beat their single-word substrings.
 *
 * This is the enforcement point: the LLM proposes, this function disposes.
 * A location it can't place is dropped, never invented.
 */
export function normalizeBodyMention(
  raw: string,
): { body_area: string; side: "left" | "right" | null } | null {
  if (!raw || typeof raw !== "string") return null;
  const { side, rest } = extractSide(raw.toLowerCase());
  if (!rest) return null;
  for (const { canonical, synonym } of SYNONYM_INDEX) {
    if (containsWord(rest, synonym)) {
      return { body_area: canonical, side };
    }
  }
  return null;
}

/**
 * Map a single word (the LLM's `severity_word`, e.g. "cranky") to a closed
 * severity hint. Returns null when the word carries no severity signal —
 * callers decide the fallback (the writer defaults to "sore": a body part
 * was named in a soreness context, so "sore" is the honest floor).
 */
export function severityHintFromWord(word: string | null | undefined): SeverityHint | null {
  if (!word) return null;
  for (const [re, label] of SEVERITY_HINTS) {
    if (re.test(word)) return label;
  }
  return null;
}

/**
 * Scan free text for the strongest severity hint present. Used by the
 * regex-backfill path, where severity is inferred from words near a
 * body-part mention rather than from a structured field.
 */
export function severityHintFromText(text: string | null | undefined): SeverityHint | null {
  if (!text) return null;
  for (const [re, label] of SEVERITY_HINTS) {
    if (re.test(text)) return label;
  }
  return null;
}

/** Severity ordering for "worst wins" comparisons. sharp > pain > sore > tight. */
export const SEVERITY_ORDER: Record<string, number> = { sharp: 4, pain: 3, sore: 2, tight: 1 };

/** True when `area` is a canonical key in the closed body vocabulary. */
export function isKnownBodyArea(area: string): boolean {
  return typeof area === "string" && Object.prototype.hasOwnProperty.call(BODY_AREAS, area);
}

/**
 * Detect the laterality expressed in a span of free text (e.g. the window
 * around a body-part mention). Returns the first of left/right found, or
 * null. "both"/"bilateral" is intentionally not laterizable → null.
 * Used by the regex-backfill scan, which reads side from nearby words
 * rather than from a structured field.
 */
export function sideFromText(text: string): "left" | "right" | null {
  if (!text) return null;
  for (const [re, label] of SIDE_PATTERNS) {
    if ((label === "left" || label === "right") && re.test(text)) return label;
  }
  return null;
}

/**
 * Scan free text for closed-vocabulary body areas. Returns at most one
 * match per canonical area (the longest matching synonym, at its first
 * position), so the backfill scan reports areas — not raw synonyms — and
 * shares the exact vocabulary the memo classifier uses. `index` is the
 * position of the matched synonym in the original text, for the caller's
 * severity-window and excerpt logic.
 */
export function findBodyAreaMentions(
  text: string,
): Array<{ body_area: string; index: number; matched: string }> {
  if (!text) return [];
  const lower = text.toLowerCase();
  const seen = new Set<string>();
  const out: Array<{ body_area: string; index: number; matched: string }> = [];
  for (const { canonical, synonym } of SYNONYM_INDEX) {
    if (seen.has(canonical)) continue; // longest synonym already claimed this area
    const re = new RegExp(`(?<![a-z])${escapeRe(synonym)}(?![a-z])`, "i");
    const m = re.exec(lower);
    if (m) {
      seen.add(canonical);
      out.push({ body_area: canonical, index: m.index, matched: synonym });
    }
  }
  return out.sort((a, b) => a.index - b.index);
}
