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
  for (const [re, zone] of ZONE_SYNONYMS) if (re.test(text)) return zone;
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

  // Bare zone
  const zone = parseZoneName(t);
  if (zone) return { kind: "zone", zone };

  return null;
}

/** Parse a distance phrase → meters. "800m", "1k", "1mi", "3 mile", "mile". */
export function parseDistanceMeters(text: string): number | null {
  const t = text.toLowerCase();
  const km = t.match(/(\d+(?:\.\d+)?)\s*(?:k|km)\b/);
  if (km) return Number(km[1]) * 1000;
  const mi = t.match(/(\d+(?:\.\d+)?)\s*(?:mi|mile|miles)\b/);
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
  const z = pace && pace.kind === "zone" ? pace.zone : pace && pace.kind === "pct" ? pace.ofZone : null;
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
  const z = pace && pace.kind === "zone" ? pace.zone : null;
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
function matchSimple(text: string): DeclaredWorkout | null {
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
    if (r) return { ...r, raw: input };
  }
  return { raw: input, kind: "unknown", reps: 0, block: [], confidence: "low", note: "no structure recognized" };
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
