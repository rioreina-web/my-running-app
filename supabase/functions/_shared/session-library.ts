/**
 * The coach's own session vocabulary, as a selectable library.
 *
 * WHY THIS EXISTS. `reschedule-plan` picks replacement sessions from a
 * hardcoded taxonomy of synthetic codes — "RSPS_2 8x800m", "GE_7 1hr
 * progression", percentages of an unnamed reference. That is textbook
 * vocabulary, and it is the thing `docs/coaching/principles.md` and the
 * no-Daniels/no-Pfitzinger rule exist to keep out of the product. This coach
 * writes "8 x 800 @ 10k w/1' rec". A swap the coach does not recognise as
 * their own is a swap they have to re-read, re-check and usually rewrite.
 *
 * So the library is mined from what they have actually prescribed: 148
 * sessions across six seasons (Fall23, Fall24, Spring24, SoS24, Spring25,
 * Spring26), each kept VERBATIM alongside a parse of its structure.
 *
 * The `lightVariant` field is the valuable part and it is not derived — the
 * Fall24 sheet carries a "Lower Volume Variant" column where the coach wrote
 * the scaled-down version of each Tuesday session themselves. That is a
 * ready-made, in-voice answer to "this week needs to be easier", written by
 * the person whose judgement we are trying not to replace.
 *
 * Selection is deterministic and lives here rather than in a prompt. A model
 * may be asked to CHOOSE among candidates this returns; it is never asked to
 * invent one. Same division as everywhere else in this codebase: rules decide
 * whether and what is eligible, the model picks, a human applies.
 */

export type DayRole =
  | "monday" | "tuesday" | "tuesday_light" | "wednesday"
  | "thursday" | "friday" | "saturday" | "sunday";

/**
 * What a session trains. Deliberately coarse — this is for matching a
 * replacement to the hole in the week, not for describing physiology.
 */
export type SessionKind =
  | "intervals"      // short reps at 3k-10k
  | "threshold"      // tempo / LT / HM-pace continuous or long reps
  | "marathon_pace"  // MP and MP-offset work
  | "progression"    // gets faster within the session
  | "alternation"    // fast/float or fast/steady alternating
  | "long_run"       // the weekend distance session
  | "moderate"       // aerobic, no quality
  | "hills"
  | "strides"
  | "other";

export interface LibrarySession {
  /** The coach's text, untouched. This is what a swap should show them. */
  text: string;
  /** Which sheet it came from — provenance, and a rough age signal. */
  sheet: string;
  /** The slot it was written for. */
  day: DayRole;
  kind: SessionKind;
  /** Total prescribed distance in miles, when the parse could total it. */
  totalMiles: number | null;
  /** Miles of actual work — reps and tempo, excluding wu/cd and recoveries. */
  qualityMiles: number | null;
  /** Pace zones the session touches, most-specific first. */
  zones: string[];
  /** The coach's own scaled-down version, where they wrote one. */
  lightVariant?: string;
}

// ── Classification ───────────────────────────────────────
//
// Order matters: the first matching rule wins, so the most specific
// descriptions come first. These read the coach's words, not a parse tree —
// "cutdown" and "alternations" are intent, and intent survives in the text
// even when the structure parse is partial.

const KIND_RULES: Array<[RegExp, SessionKind]> = [
  [/\balternation|\bfloat\b|fast\s*\/|\/\s*\d+'?\s*(?:easy|moderate|medium)/i, "alternation"],
  [/\bcutdown\b|\bcut-?down\b|\bprogression\b|\bprogressive\b|>/i, "progression"],
  [/\bstrides?\b/i, "strides"],
  [/\bhill/i, "hills"],
  // An EXPLICIT intent word outranks inferred structure. "2mi tempo + 4x400m
  // @ 10k" is a tempo session with a sharpener on the end; classifying it as
  // intervals because it contains "x400m" buries it among the track sessions.
  // Sessions that genuinely mix the two (e.g. "15' LT + 8x800 @ 10k") are
  // ambiguous under any single label — they land in `threshold`, which keeps
  // them next to their nearest neighbours for selection purposes.
  [/\btempo\b|\bLT\b|\bthreshold\b|@\s*HMP?\b/i, "threshold"],
  [/@\s*(?:3k|5k|mile|800)\b|x\s*(?:200|300|400|600)m?\b/i, "intervals"],
  [/@\s*MP\b|@\s*MP[+-]/i, "marathon_pace"],
  [/\blong\b|\b(?:1[5-9]|2[0-6])\s*(?:mi|m)\b/i, "long_run"],
  [/\bmoderate\b|\beasy\b|\bsteady\b/i, "moderate"],
];

export function classifyKind(text: string, day: DayRole): SessionKind {
  for (const [re, kind] of KIND_RULES) if (re.test(text)) return kind;
  // A Saturday entry with no quality markers is the long run by position.
  if (day === "saturday") return "long_run";
  return "other";
}

// ── Selection ────────────────────────────────────────────

export interface SelectOpts {
  /** The slot being filled. `tuesday_light` also matches `tuesday`. */
  day?: DayRole;
  /** Restrict to these kinds. Empty or omitted means any. */
  kinds?: SessionKind[];
  /** Cap total distance — the lever for "this week needs to be smaller". */
  maxMiles?: number;
  /** Cap quality volume specifically, for backing off intensity not distance. */
  maxQualityMiles?: number;
  /** Exclude sessions whose text matches any of these (e.g. what they just did). */
  exclude?: string[];
  limit?: number;
}

/**
 * Candidate sessions for a slot, most-relevant first. Pure and synchronous —
 * no model, no network — so it is testable and so a caller can show the coach
 * the same list the model was offered.
 */
export function selectSessions(
  library: LibrarySession[],
  opts: SelectOpts = {},
): LibrarySession[] {
  const { day, kinds, maxMiles, maxQualityMiles, exclude = [], limit = 12 } = opts;
  const excluded = new Set(exclude.map((t) => t.trim().toLowerCase()));

  const eligible = library.filter((s) => {
    if (excluded.has(s.text.trim().toLowerCase())) return false;
    if (day && !dayMatches(s.day, day)) return false;
    if (kinds?.length && !kinds.includes(s.kind)) return false;
    // A session with no parseable total is NOT excluded by a volume cap —
    // dropping it would silently hide the coach's less machine-legible
    // sessions, which are often the interesting ones.
    if (maxMiles != null && s.totalMiles != null && s.totalMiles > maxMiles) return false;
    if (maxQualityMiles != null && s.qualityMiles != null && s.qualityMiles > maxQualityMiles) return false;
    return true;
  });

  // Prefer sessions we could fully measure, then smaller ones — when the
  // caller asked for a cap they are backing off, so nearer the cap is safer.
  return eligible
    .sort((a, b) => {
      const known = Number(b.totalMiles != null) - Number(a.totalMiles != null);
      if (known !== 0) return known;
      return (a.totalMiles ?? 0) - (b.totalMiles ?? 0);
    })
    .slice(0, limit);
}

function dayMatches(sessionDay: DayRole, wanted: DayRole): boolean {
  if (sessionDay === wanted) return true;
  // The light column is still a Tuesday session.
  if (wanted === "tuesday" && sessionDay === "tuesday_light") return true;
  if (wanted === "tuesday_light" && sessionDay === "tuesday") return true;
  return false;
}

/**
 * The scaled-down form of a session: the coach's own light variant when they
 * wrote one, otherwise null. Deliberately does NOT synthesise a lighter
 * version — inventing "do 4 instead of 6" is a prescription, and prescriptions
 * belong to the coach.
 */
export function lighterForm(s: LibrarySession): string | null {
  return s.lightVariant ?? null;
}

/**
 * Render candidates for a prompt. Verbatim text first so the model selects on
 * the coach's own words; the derived numbers are context, not the identity.
 */
export function formatForPrompt(sessions: LibrarySession[]): string {
  return sessions
    .map((s) => {
      const vol = s.totalMiles != null ? ` (~${s.totalMiles.toFixed(1)}mi)` : "";
      const light = s.lightVariant ? `\n     lighter: ${s.lightVariant}` : "";
      return `  - ${s.text}${vol}  [${s.kind}]${light}`;
    })
    .join("\n");
}
