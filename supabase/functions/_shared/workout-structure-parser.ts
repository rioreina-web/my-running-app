// ============================================================================
// Declared-workout parser — the athlete's words → a structured workout.
//
// The athlete states what the session WAS, in a voice memo or notes
// ("8mi alternation, mile at 104% MP / mile at 90% MP", "2×3mi at threshold",
// "6×800m @ 5K w/ 90s jog"). This parser turns that free text into a structured
// `DeclaredWorkout`. That declared structure is the source of truth for *what
// the workout was*; the lap segmentation (workoutSegmentation.ts) stays the
// source of truth for *what was actually executed*. The two are shown together
// (declared vs executed), so an alternation reads as an alternation even when
// the auto-detector can't infer it from averaged splits.
//
// Deterministic + dependency-free so it's unit-testable and runs server-side.
// Messy free-form voice transcripts can be normalized by the LLM memo parser
// first; this parses the canonical/edited form an athlete (or that LLM) emits,
// and the common spoken patterns directly.
// ============================================================================

const METERS_PER_MILE = 1609.344;

// Pace reference, normalized. Zones mirror workoutSegmentation.Zone naming.
export type PaceZoneName =
  | "mile" | "3k" | "5k" | "10k" | "threshold" | "mp" | "steady" | "moderate" | "easy" | "recovery";

export type PaceSpec =
  | { kind: "zone"; zone: PaceZoneName }
  | { kind: "pct"; ofZone: PaceZoneName; pct: number }            // "104% MP"
  | { kind: "relative"; ofZone: PaceZoneName; deltaSec: number; faster: boolean } // "10s faster than MP"
  | { kind: "explicit"; secPerMile: number }                      // "5:07"
  | { kind: "effort"; label: string };                            // unparsed fallback

export interface DeclaredSegment {
  distanceMeters?: number;
  durationSeconds?: number;
  pace?: PaceSpec;
}

export interface DeclaredWorkout {
  raw: string;
  kind:
    | "alternation" | "intervals" | "threshold" | "tempo"
    | "progression" | "long_run" | "easy" | "recovery" | "race" | "unknown";
  reps: number;                 // how many times the block repeats (1 for continuous)
  block: DeclaredSegment[];     // one entry, or two+ for an alternation cycle
  recovery?: DeclaredSegment;   // jog/standing rest between reps, if stated
  totalDistanceMeters?: number;
  confidence: "high" | "medium" | "low";
  note?: string;                // anything we couldn't fully parse
}

// ── Token parsers ───────────────────────────────────────────────

const ZONE_SYNONYMS: Array<[RegExp, PaceZoneName]> = [
  [/\b(marathon\s*pace|marathon|mp)\b/, "mp"],
  [/\b(half\s*marathon\s*pace|half\s*marathon|hmp|hm)\b/, "threshold"],
  [/\b(threshold|tempo|lt|cv|cruise)\b/, "threshold"],
  [/\b(10\s*k|10k)\b/, "10k"],
  [/\b(5\s*k|5k)\b/, "5k"],
  [/\b(3\s*k|3k)\b/, "3k"],
  [/\b(mile\s*pace|mile\s*repeat|1500|1600|vo2\s*max|vo2)\b/, "mile"],
  [/\b(steady)\b/, "steady"],
  [/\b(moderate|mod)\b/, "moderate"],
  [/\b(recovery|recov)\b/, "recovery"],
  [/\b(easy|aerobic|conversational)\b/, "easy"],
];

function parseZoneName(text: string): PaceZoneName | null {
  return matchZone(text)?.zone ?? null;
}

/**
 * Like `parseZoneName`, but reports the substring that matched. The bare
 * `.test()` version is what let modifiers vanish: "MP+5%" contains `\bmp\b`,
 * so it came back as a plain `mp` zone and the "+5%" was dropped on the floor.
 */
function matchZone(text: string): { zone: PaceZoneName; matched: string; index: number } | null {
  for (const [re, zone] of ZONE_SYNONYMS) {
    const m = text.match(re);
    // `m.index`, never `indexOf(m[0])`: "2mi tempo (MP-5)" contains "mp" inside
    // "tempo" at an earlier offset, so indexOf pointed at the wrong token and
    // the suffix came back as "o (mp-5)" — the offset was invisible again.
    if (m && m.index != null) return { zone, matched: m[0], index: m.index };
  }
  return null;
}

/** Parse a pace phrase like "104% MP", "10s faster than MP", "5:07", "5K pace". */
export function parsePace(text: string): PaceSpec | null {
  const t = text.toLowerCase().trim();

  // Percent of a zone: "104% mp", "90 % marathon pace"
  const pct = t.match(/(\d{2,3})\s*%\s*(of\s*)?([a-z0-9 ]+)/);
  if (pct) {
    const zone = parseZoneName(pct[3]);
    if (zone) return { kind: "pct", ofZone: zone, pct: Number(pct[1]) };
  }

  // Relative: "10s faster than MP", "20 sec slower than marathon pace"
  const rel = t.match(/(\d{1,3})\s*(?:s|sec|seconds)?\s*(faster|slower)\s*(?:than\s*)?([a-z0-9 ]+)/);
  if (rel) {
    const zone = parseZoneName(rel[3]);
    if (zone) return { kind: "relative", ofZone: zone, deltaSec: Number(rel[1]), faster: rel[2] === "faster" };
  }

  // Explicit pace "5:07" (optionally "/mi")
  const exp = t.match(/\b(\d):(\d{2})\b/);
  if (exp) return { kind: "explicit", secPerMile: Number(exp[1]) * 60 + Number(exp[2]) };

  // Zone, with whatever is glued to it.
  //
  // THIS IS THE BRANCH THAT USED TO LOSE PACES. `parseZoneName` tested for the
  // zone token anywhere in the string and returned it, so "MP+5%" came back as
  // a plain `mp` and the "+5%" was discarded — an alternation's fast and float
  // legs stored as the same pace, at confidence "high", with no note. The rule
  // now: match the zone, then the suffix must be either nothing, or an offset
  // we actually decoded. Never anything else.
  //
  // MINUS MEANS FASTER — the coach's own shorthand, all over
  // `session-library.json` ("8-12m alternations (MP-10/MP+30)", "4-6x2m @ MP-5
  // w/800 float MP+1'"). Suffix sets the unit: none/" = seconds, ' = minutes,
  // % = percent. The percent form maps onto `pct`, which is a percentage of
  // zone SPEED (see pace-engine.ts), so the reciprocal is correct: 5% slower
  // *pace* is 100/1.05 = 95.2% of MP speed, not 95%.
  const zm = matchZone(t);
  if (zm) {
    const after = t.slice(zm.index + zm.matched.length);
    const off = after.match(/^\s*(?:([+-])|\b(plus|minus)\b)\s*(\d{1,3}(?:\.\d+)?)\s*(%|'|")?/);
    // A PLUS ALSO JOINS SEGMENTS. "4mi at MP + 2 x 1mi @ HM" and "15' LT + 6x1k
    // @ 10k" are two blocks glued with a plus, not MP+2 and LT+6. A rep marker
    // or a distance unit straight after the number means concatenation, so only
    // a bare number (or one with a %/'/" suffix) is an offset. Without this the
    // offset decode invented a pace on 14 of the 59 offset-shaped corpus rows.
    const isOffset = !!off && (!!off[4] ||
      !/^\s*(?:[x×]|mi\b|m\b|k\b|km\b|mile)/.test(after.slice(off[0].length)));
    if (off && isOffset) {
      const faster = off[1] === "-" || off[2] === "minus";
      const n = Number(off[3]);
      if (off[4] === "%") {
        const paceFactor = faster ? 1 - n / 100 : 1 + n / 100;
        return { kind: "pct", ofZone: zm.zone, pct: Math.round((100 / paceFactor) * 10) / 10 };
      }
      return { kind: "relative", ofZone: zm.zone, deltaSec: off[4] === "'" ? n * 60 : n, faster };
    }
    // ATTACHED SIGN = OPERATOR, SPACED HYPHEN = PUNCTUATION.
    //
    // The coach writes "MP+5%" glued, but also "2 x 4mi hilly steady -
    // Lollipop", where " - " introduces a route name. Firing on any sign
    // flagged those as unparsed paces; requiring a digit made the guard
    // unreachable. So: a sign touching the zone token is an operator we failed
    // to read; a spaced hyphen is a dash. A concatenating plus is neither.
    if (!off && /^[+-]/.test(after)) {
      return { kind: "effort", label: text.trim() };
    }
    return { kind: "zone", zone: zm.zone };
  }

  return null;
}

/** Parse a distance phrase → meters. "800m", "1k", "1mi", "3 mile", "mile". */
export function parseDistanceMeters(text: string): number | null {
  const t = text.toLowerCase();
  // A leading decimal point must not be dropped: athletes write ".25 mile
  // recoveries", and `(\d+(\.\d+)?)` cannot match ".25" so the regex fell
  // through to the bare digits and read TWENTY-FIVE MILES. Seen in prod on a
  // real note — "six miles, starting at marathon pace ... with .25 mile
  // recoveries" was parsed as a 40 km block, at high confidence.
  const km = t.match(/(\d+(?:\.\d+)?|\.\d+)\s*(?:k|km)\b/);
  if (km) return Number(km[1]) * 1000;
  const mi = t.match(/(\d+(?:\.\d+)?|\.\d+)\s*(?:mi|mile|miles)\b/);
  if (mi) return Number(mi[1]) * METERS_PER_MILE;
  const m = t.match(/(\d{2,5})\s*m\b/);
  if (m) return Number(m[1]);
  // Bare "mile" = 1 mile.
  if (/\bmile\b/.test(t)) return METERS_PER_MILE;
  return null;
}

/** Parse a duration phrase → seconds. "90s", "2 min", "20 minute". */
export function parseDurationSeconds(text: string): number | null {
  const t = text.toLowerCase();
  const min = t.match(/(\d+(?:\.\d+)?)\s*(?:min|minute|minutes|')\b/);
  if (min) return Math.round(Number(min[1]) * 60);
  const sec = t.match(/(\d{1,3})\s*(?:s|sec|secs|seconds|")\b/);
  if (sec) return Number(sec[1]);
  return null;
}

// ── Matchers (tried in priority order) ──────────────────────────

const ALT_RE = /\balt(?:ernation|ernating|s)?\b/;
// Spaces required around the slash so "w/ 90s jog" isn't read as a separator.
const ALT_SPLIT = /\s+\/\s+|\s+then\s+/;
const RECOVERY_RE = /(?:w\/|with)\s*([^,;]*?(?:jog|rest|recovery|standing|float|easy)[^,;]*)/;

function parseRecovery(text: string): DeclaredSegment | undefined {
  const m = text.match(RECOVERY_RE);
  if (!m) return undefined;
  const seg = m[1];
  const dur = parseDurationSeconds(seg);
  const dist = parseDistanceMeters(seg);
  if (dur == null && dist == null) return undefined;
  return { durationSeconds: dur ?? undefined, distanceMeters: dist ?? undefined };
}

/** One alternation leg: take the distance token immediately before "@/at" (so
 *  a leading total like "8mi" isn't mistaken for the leg distance). */
function parseLeg(leg: string): { dist: number | null; pace: PaceSpec | null } {
  const m = leg.match(/([\d.]+\s*(?:mi|mile|miles|k|km|m)\b|mile)\s*(?:@|at)\s+([^/)]+)/);
  if (m) return { dist: parseDistanceMeters(m[1]), pace: parsePace(m[2]) ?? parsePace(leg) };
  return { dist: parseDistanceMeters(leg), pace: parsePace(leg) };
}

/** A stated total distance: "8mi alternation", "for 8k", "over 6 miles". */
function detectTotalMeters(text: string): number | null {
  const m =
    text.match(/(\d+(?:\.\d+)?\s*(?:mi|mile|miles|k|km))\s*(?:of\s+)?(?:alt|alternation|alternating)/) ||
    text.match(/(?:for|over|total(?:\s*of)?)\s+(\d+(?:\.\d+)?\s*(?:mi|mile|miles|k|km))/);
  return m ? parseDistanceMeters(m[1]) : null;
}

/**
 * Alternation: two paces alternating, continuous. Forms:
 *   "4x(1mi @ HMP / 1mi @ MP)"
 *   "8mi alternation, mile at 104% MP / mile at 90% MP"
 *   "alternating, 1k at 10k / 1k at MP for 8k"
 */
function matchAlternation(text: string): DeclaredWorkout | null {
  if (!ALT_SPLIT.test(text)) return null; // need two halves
  const halves = text.split(ALT_SPLIT);
  if (halves.length < 2) return null;
  const a = parseLeg(halves[0]);
  const b = parseLeg(halves[1]);
  if (!a.pace || !b.pace) return null;

  const aDist = a.dist ?? METERS_PER_MILE;
  const bDist = b.dist ?? aDist;
  const block: DeclaredSegment[] = [
    { distanceMeters: aDist, pace: a.pace },
    { distanceMeters: bDist, pace: b.pace },
  ];
  const cycle = aDist + bDist;

  let reps: number;
  let total: number | undefined;
  const nx = text.match(/(\d+)\s*[x×]\s*\(/);
  if (nx) {
    reps = Number(nx[1]);
    total = reps * cycle;
  } else {
    const t = detectTotalMeters(text);
    if (t && t > cycle) {
      total = t;
      reps = Math.max(1, Math.round(t / cycle));
    } else {
      reps = 1;
    }
  }

  return {
    raw: text,
    kind: "alternation",
    reps,
    block,
    totalDistanceMeters: total,
    confidence: nx || total ? "high" : "medium",
  };
}

/**
 * The zone a pace is expressed *relative to*, for kind inference.
 *
 * `zone`, `pct` and `relative` all name a zone; only `explicit` (a clock pace)
 * and `effort` (unparsed) do not. Omitting `relative` here is what made
 * "4 x 3mi @ MP-5 w/800m easy" classify as intervals instead of threshold —
 * the pace WAS marathon pace, just offset. Any new zone-bearing PaceSpec
 * variant must be added here too.
 */
function zoneOf(pace: PaceSpec | undefined | null): PaceZoneName | null {
  if (!pace) return null;
  switch (pace.kind) {
    case "zone": return pace.zone;
    case "pct":
    case "relative": return pace.ofZone;
    default: return null;
  }
}

/**
 * Reps: "6x800m @ 5K w/ 90s jog", "5×1mi at 10k", "9x1k @ 5:07",
 * "2x3mi at threshold". Optional recovery clause.
 */
function matchReps(text: string): DeclaredWorkout | null {
  const m = text.match(/(\d+)\s*[x×]\s*(\d+(?:\.\d+)?\s*(?:m|k|km|mi|mile|miles)?)/);
  if (!m) return null;
  const reps = Number(m[1]);
  const dist = parseDistanceMeters(m[2]) ?? parseDistanceMeters(text);
  if (!dist) return null;

  // Pace = first pace phrase AFTER the rep token (so "2x3mi" isn't read as pace).
  const afterRep = text.slice((m.index ?? 0) + m[0].length);
  const pace = parsePace(afterRep) ?? parsePace(text) ?? undefined;
  const recovery = parseRecovery(text);

  const repMiles = dist / METERS_PER_MILE;
  const longRep = repMiles >= 0.95;
  // A "rep" workout with no recovery and long reps at threshold/MP reads as a
  // cruise/threshold; with recovery + short reps it's intervals.
  let kind: DeclaredWorkout["kind"] = "intervals";
  const z = zoneOf(pace);
  if (longRep && (z === "threshold" || z === "10k" || z === "mp")) kind = "threshold";

  return {
    raw: text,
    kind,
    reps,
    block: [{ distanceMeters: dist, pace }],
    recovery,
    totalDistanceMeters: dist * reps,
    confidence: pace ? "high" : "medium",
  };
}

/** Continuous: "4 mile tempo at MP", "20 min tempo", "3mi @ threshold". reps=1. */
function matchContinuous(text: string): DeclaredWorkout | null {
  const pace = parsePace(text);
  const dist = parseDistanceMeters(text);
  const dur = parseDurationSeconds(text);
  if (!pace && !/tempo|threshold|progression/.test(text)) return null;
  if (dist == null && dur == null) return null;
  // Aerobic-only ("easy 6 miles") is not a tempo — let matchSimple handle it.
  const aerobicOnly = pace && pace.kind === "zone" &&
    ["easy", "recovery", "steady", "moderate"].includes(pace.zone);
  if (aerobicOnly && !/tempo|threshold|progression/.test(text)) return null;

  const isProg = /\bprogression\b/.test(text);
  // tempo/threshold continuous block
  let kind: DeclaredWorkout["kind"] = isProg ? "progression" : "tempo";
  const z = zoneOf(pace);
  if (!isProg && (z === "threshold" || z === "10k")) kind = "threshold";

  return {
    raw: text,
    kind,
    reps: 1,
    block: [{ distanceMeters: dist ?? undefined, durationSeconds: dur ?? undefined, pace: pace ?? undefined }],
    totalDistanceMeters: dist ?? undefined,
    confidence: pace && (dist != null || dur != null) ? "high" : "medium",
  };
}

/** Simple aerobic: "easy 6 miles", "16 mile long run", "recovery 4 miles". */
/**
 * Words that mean the session HAS work structure, so it cannot be an easy or
 * recovery run however its rest is described.
 *
 * Without this, `matchSimple` claimed any text containing "recovery" or "easy"
 * — including when those words describe the REST. Real notes it got wrong, all
 * at high confidence:
 *
 *   "1 mile at a 6-minute pace … with 400m recovery"  → a recovery run
 *   "a threshold session with 5x4 min, jog recovery"  → a recovery run
 *   "2 × ~2mi tempo/threshold, standing recovery"     → a recovery run
 *   "4 x 3mi @ MP-5 w/800m easy"                      → an easy run
 *
 * Judging those sessions against recovery pace would have been worse than not
 * parsing them at all.
 */
const HAS_WORK_STRUCTURE =
  /\b(\d+\s*[x×]|sets?|reps?|intervals?|repeats?|tempo|threshold|fartlek|progression|alternation|marathon\s*pace|half\s*marathon|mp|hmp|lt|cruise|at\s+\d+:\d{2}|@\s*\d+:\d{2})\b/;

function matchSimple(text: string): DeclaredWorkout | null {
  if (HAS_WORK_STRUCTURE.test(text)) return null;
  const dist = parseDistanceMeters(text);
  const miles = dist ? dist / METERS_PER_MILE : null;
  if (/\blong\s*run\b/.test(text) || (miles != null && miles >= 11 && /\beasy|long\b/.test(text))) {
    return { raw: text, kind: "long_run", reps: 1, block: [{ distanceMeters: dist ?? undefined, pace: { kind: "zone", zone: "easy" } }], totalDistanceMeters: dist ?? undefined, confidence: dist ? "high" : "low" };
  }
  if (/\brecovery\b/.test(text)) {
    return { raw: text, kind: "recovery", reps: 1, block: [{ distanceMeters: dist ?? undefined, pace: { kind: "zone", zone: "recovery" } }], totalDistanceMeters: dist ?? undefined, confidence: dist ? "high" : "low" };
  }
  if (/\beasy\b/.test(text)) {
    return { raw: text, kind: "easy", reps: 1, block: [{ distanceMeters: dist ?? undefined, pace: { kind: "zone", zone: "easy" } }], totalDistanceMeters: dist ?? undefined, confidence: dist ? "high" : "low" };
  }
  return null;
}

/**
 * Parse an athlete's stated workout into a structured DeclaredWorkout.
 * Returns `kind: "unknown"` (never throws) when nothing matches, so callers
 * degrade to the auto-detected structure.
 */
export function parseDeclaredWorkout(input: string): DeclaredWorkout {
  const text = input.toLowerCase().replace(/\s+/g, " ").trim();
  const matchers = [matchAlternation, matchReps, matchSimple, matchContinuous];
  for (const m of matchers) {
    const r = m(text);
    if (r) return flagUnparsedPaces({ ...r, raw: input });
  }
  return { raw: input, kind: "unknown", reps: 0, block: [], confidence: "low", note: "no structure recognized" };
}

/**
 * A segment whose pace came back as `effort` carries no number. The STRUCTURE
 * may still be perfect — "1k @ MP+5% / 1k @ MP-5% for 20k" gets the 10 cycles
 * and the 20 km right — so the workout is not discarded; but it must not claim
 * "high", or a consumer reading paces gets a confident answer built on a pace
 * nobody decoded.
 */
function flagUnparsedPaces(w: DeclaredWorkout): DeclaredWorkout {
  const unparsed = w.block.filter((b) => b.pace?.kind === "effort");
  if (unparsed.length === 0) return w;
  const labels = [...new Set(unparsed.map((b) => (b.pace as { label: string }).label))];
  return {
    ...w,
    confidence: w.confidence === "high" ? "medium" : w.confidence,
    note: [w.note, `unparsed pace: ${labels.join(", ")}`].filter(Boolean).join("; "),
  };
}

// ── Canonical formatter (display / store) ───────────────────────

function fmtDist(meters?: number): string {
  if (!meters) return "";
  const miles = meters / METERS_PER_MILE;
  if (Math.abs(miles - Math.round(miles)) / Math.max(1, Math.round(miles)) < 0.06 && miles >= 1) {
    return `${Math.round(miles)}mi`;
  }
  for (const m of [400, 600, 800, 1000, 1200, 1600, 2000, 3000]) {
    if (Math.abs(meters - m) / m < 0.06) return m % 1000 === 0 ? `${m / 1000}K` : `${m}m`;
  }
  return `${(miles).toFixed(1)}mi`;
}

function fmtPace(p?: PaceSpec): string {
  if (!p) return "";
  switch (p.kind) {
    case "zone": return p.zone === "threshold" ? "threshold" : p.zone.toUpperCase();
    case "pct": return `${p.pct}% ${p.ofZone.toUpperCase()}`;
    case "relative": return `${p.deltaSec}s ${p.faster ? "faster" : "slower"} than ${p.ofZone.toUpperCase()}`;
    case "explicit": return `${Math.floor(p.secPerMile / 60)}:${String(p.secPerMile % 60).padStart(2, "0")}`;
    case "effort": return p.label;
  }
}

function fmtSeg(s: DeclaredSegment): string {
  const d = s.distanceMeters ? fmtDist(s.distanceMeters) : s.durationSeconds ? `${Math.round(s.durationSeconds / 60)}min` : "";
  const p = fmtPace(s.pace);
  return [d, p && `@ ${p}`].filter(Boolean).join(" ");
}

/** Human/canonical label, e.g. "4×(1mi @ 104% MP / 1mi @ 90% MP) — alternation". */
export function formatDeclared(w: DeclaredWorkout): string {
  if (w.kind === "unknown" || w.block.length === 0) return w.raw;
  if (w.kind === "alternation") {
    const cycle = w.block.map(fmtSeg).join(" / ");
    return `${w.reps}×(${cycle}) — alternation`;
  }
  const seg = fmtSeg(w.block[0]);
  if (w.reps > 1) {
    const rec = w.recovery
      ? ` w/ ${w.recovery.durationSeconds ? `${w.recovery.durationSeconds}s` : fmtDist(w.recovery.distanceMeters)} ${w.recovery.distanceMeters ? "jog" : "rest"}`
      : "";
    return `${w.reps}×${seg}${rec} (${w.kind})`;
  }
  return `${seg} (${w.kind})`;
}
