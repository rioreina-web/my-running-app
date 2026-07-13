// Natural-language workout parser.
//
// Turns a coach's shorthand ("2mi wu, 6x800 @ 5k w/ 400m jog, 2mi cd") into
// structured WorkoutStep[]. Ported from the interactive prototype
// `prototypes/workout-builder.html` (parseNL + its helpers) — the prototype
// is the design reference; when this disagrees with it, the prototype wins.
//
// This is a PURE module (no "use client", no React) so it can be unit-tested
// directly and imported by both server and client components.
//
// Two layers:
//   1. The prototype grammar, ported almost verbatim, producing an internal
//      `ParsedStep` shape that mirrors the prototype's own step objects.
//   2. An adapter (`toWorkoutSteps`) that maps `ParsedStep` → the web
//      `WorkoutStep` type, collapsing features the web model doesn't have:
//        - ranges ("4-6 x 800", "10-12k")   → midpoint
//        - sets   ("2 sets of 6 x 400")      → repeats = sets × reps
//        - target time ("800 in 2:30")       → exactPaceSecPerMile
//        - compound sets ("(600 @ 5k / 400 @ 3k)") → UNSUPPORTED (v1), the
//          text is returned in `unparsed` so the coach can add it by hand.

import { paceShort, type PaceZone, type WorkoutStep, type PaceAdjustment } from "./workout-helpers";

const KM_PER_MILE = 1.609344;
const METERS_PER_MILE = 1609.344;

// ── Internal (prototype-shaped) types ────────────────────

type ProtoDurationType = "mi" | "km" | "m" | "time";
type ProtoPaceMode = "zone" | "pace" | "time" | "none";

interface Off {
  kind: "sec" | "pct";
  v: number; // negative = faster, positive = slower (matches web convention)
}

interface Duration {
  durationType: ProtoDurationType;
  durationValue: number;
  durationValueMax?: number;
}

interface Recovery {
  durationType: ProtoDurationType;
  durationValue: number;
  style: "jog" | "rest";
}

interface MiniSegment {
  durationType: ProtoDurationType;
  durationValue: number;
  paceMode: "pace" | "zone";
  zone: PaceZone;
  paceSec: number | null;
  zoneOff: Off | null;
}

interface ParsedStep {
  kind: "warmup" | "cooldown" | "reps" | "block" | "rest";
  reps: number;
  repsMax: number | null;
  sets: number;
  setRestSec: number | null;
  durationType: ProtoDurationType;
  durationValue: number;
  durationValueMax: number | null;
  paceMode: ProtoPaceMode;
  zone: PaceZone | null;
  zoneOff: Off | null;
  paceSec: number | null;
  timeSec: number | null;
  recovery: Recovery | null;
  segments: MiniSegment[] | null;
}

// ── Formatting / parsing primitives ──────────────────────

function parseClockStr(raw: string): number | null {
  const s = (raw || "").trim();
  let m = s.match(/^(\d{1,2}):(\d{2})$/);
  if (m) return +m[1] * 60 + +m[2];
  m = s.match(/^(\d{1,2}):(\d{2}):(\d{2})$/);
  if (m) return +m[1] * 3600 + +m[2] * 60 + +m[3];
  m = s.match(/^(\d+(?:\.\d+)?)$/);
  if (m) return +m[1];
  return null;
}

// Zone words → PaceZone key. Order matters (longest/most specific first).
const ZONE_WORDS: Array<[RegExp, PaceZone]> = [
  [/^(?:5k)$/i, "fiveK"],
  [/^(?:10k)$/i, "tenK"],
  [/^(?:3k)$/i, "threeK"],
  [/^(?:mile|1500m?)$/i, "mile"],
  [/^(?:mp|marathon)$/i, "mp"],
  [/^(?:hmp|hm|half)$/i, "hm"],
  [/^(?:lt|threshold|thr)$/i, "threshold"],
  [/^(?:rec|recovery)$/i, "recovery"],
  [/^(?:easy)$/i, "easy"],
  [/^(?:mod|moderate)$/i, "moderate"],
  [/^(?:steady)$/i, "steady"],
  [/^(?:long)$/i, "longRun"],
];

function matchZoneWord(raw: string): PaceZone | null {
  const s = raw.trim().replace(/\s*pace$/i, "").replace(/\s+marathon$/i, "");
  for (const [re, key] of ZONE_WORDS) if (re.test(s)) return key;
  return null;
}

// "MP-10", "5k pace -3%", "LT + 15s" → { zone, off }
function parseZoneWithOffset(str: string): { zone: PaceZone; off: Off | null } | null {
  let s = str.trim().replace(/−|–/g, "-");
  let off: Off | null = null;
  const m = s.match(/([+-])\s*(\d+(?:\.\d+)?)\s*(%|s|sec|secs)?\s*$/i);
  if (m) {
    const sign = m[1] === "+" ? 1 : -1;
    off = { kind: m[3] === "%" ? "pct" : "sec", v: sign * parseFloat(m[2]) };
    s = s.slice(0, m.index);
  }
  const zone = matchZoneWord(s);
  return zone ? { zone, off } : null;
}

function parseDuration(s: string): Duration | null {
  // ranges first: "10-12k", "30-40 min", "4-6 mi", "600-800m"
  let m = s.match(/(\d+(?:\.\d+)?)\s*[-–]\s*(\d+(?:\.\d+)?)\s*(?:min\b|mins\b|minutes\b|')/i);
  if (m) return { durationType: "time", durationValue: +m[1] * 60, durationValueMax: +m[2] * 60 };
  m = s.match(/(\d+(?:\.\d+)?)\s*[-–]\s*(\d+(?:\.\d+)?)\s*(?:miles|mile|mi)\b/i);
  if (m) return { durationType: "mi", durationValue: +m[1], durationValueMax: +m[2] };
  m = s.match(/(\d+(?:\.\d+)?)\s*[-–]\s*(\d+(?:\.\d+)?)\s*(?:km|k)\b/i);
  if (m) return { durationType: "km", durationValue: +m[1], durationValueMax: +m[2] };
  m = s.match(/(\d{3,4})\s*[-–]\s*(\d{3,4})\s*(?:meters|meter|m)?\b/);
  if (m && +m[1] >= 200) return { durationType: "m", durationValue: +m[1], durationValueMax: +m[2] };
  // seconds: 45", 45 sec
  m = s.match(/(\d+(?:\.\d+)?)\s*(?:"|″|sec\b|secs\b|seconds\b)/i);
  if (m) return { durationType: "time", durationValue: parseFloat(m[1]) };
  // minutes: "40 min", "40'"
  m = s.match(/(\d+(?:\.\d+)?)\s*(?:min\b|mins\b|minutes\b|'|′)/i);
  if (m) return { durationType: "time", durationValue: parseFloat(m[1]) * 60 };
  // distance: order matters — miles before meters
  m = s.match(/(\d+(?:\.\d+)?)\s*(miles|mile|mi)\b/i);
  if (m) return { durationType: "mi", durationValue: parseFloat(m[1]) };
  m = s.match(/(\d+(?:\.\d+)?)\s*(km|k)\b/i);
  if (m) return { durationType: "km", durationValue: parseFloat(m[1]) };
  m = s.match(/(\d+(?:\.\d+)?)\s*(meters|meter|m)\b/i);
  if (m) return { durationType: "m", durationValue: parseFloat(m[1]) };
  // bare number ≥ 200 → meters (track shorthand: "8 x 400")
  m = s.match(/(?:^|\s)(\d{3,4})(?:\s|$)/);
  if (m && +m[1] >= 200) return { durationType: "m", durationValue: +m[1] };
  // bare unit word → one of it ("3 x mile", "10-12 x k")
  if (!/\d/.test(s)) {
    if (/\b(?:km|k)\b/i.test(s)) return { durationType: "km", durationValue: 1 };
    if (/\b(?:miles|mile|mi)\b/i.test(s)) return { durationType: "mi", durationValue: 1 };
  }
  return null;
}

function parseRecovery(s: string): Recovery | null {
  const style: "jog" | "rest" = /rest|walk|standing/i.test(s) ? "rest" : "jog";
  // explicit seconds first
  let m = s.match(/(\d+(?:\.\d+)?)\s*(?:"|″|sec\b|secs\b|seconds\b)/i);
  if (m) return { durationType: "time", durationValue: parseFloat(m[1]), style };
  // apostrophe in a recovery clause: 5' reads as minutes, 45' as seconds
  m = s.match(/(\d+(?:\.\d+)?)\s*(?:'|′)/);
  if (m) {
    const v = parseFloat(m[1]);
    return { durationType: "time", durationValue: v > 15 ? v : v * 60, style };
  }
  let dur = parseDuration(s);
  if (!dur) {
    const c = s.match(/(\d{1,2}):(\d{2})/);
    if (c) dur = { durationType: "time", durationValue: +c[1] * 60 + +c[2] };
    else {
      const secs = s.match(/(\d+)\s*(?:s|sec|secs|seconds)\b/i);
      if (secs) dur = { durationType: "time", durationValue: +secs[1] };
    }
  }
  if (!dur) return null;
  return { durationType: dur.durationType, durationValue: dur.durationValue, style };
}

// "5' b/t sets" / "5 min between sets" → seconds of rest between sets
const SET_REST_RE =
  /(\d+(?::\d{2})?(?:\.\d+)?)\s*('|′|"|″|min\b|mins\b|minutes\b|sec\b|secs\b|seconds\b)?\s*(?:b\/t|btw|between)\s*sets?/i;
function parseSetRest(s: string): number | null {
  const m = s.match(SET_REST_RE);
  if (!m) return null;
  if (m[1].includes(":")) return parseClockStr(m[1]);
  const v = parseFloat(m[1]);
  if (m[2] && /"|″|sec/i.test(m[2])) return v;
  return v * 60;
}

// A single rep inside a compound set: "600 @ 5k pace", "1 min @ 6:00"
function parseMiniSegment(str: string): MiniSegment | null {
  const s = str.replace(/\bat\b/gi, "@").trim();
  let zone: PaceZone | null = null;
  let paceSec: number | null = null;
  let zoneOff: Off | null = null;
  const at = s.indexOf("@");
  let main = s;
  let pp: string | null = null;
  if (at >= 0) {
    main = s.slice(0, at);
    pp = s.slice(at + 1).trim();
  }
  if (pp) {
    const clock = pp.match(/(\d{1,2}):(\d{2})(?:\s*\/?\s*(mi|mile|km|k))?/);
    if (clock) {
      paceSec = +clock[1] * 60 + +clock[2];
      if (clock[3] && /k/i.test(clock[3])) paceSec = paceSec * KM_PER_MILE;
    } else {
      const zo = parseZoneWithOffset(pp);
      if (zo) {
        zone = zo.zone;
        zoneOff = zo.off;
      }
    }
  }
  const dur = parseDuration(main);
  if (!dur) return null;
  return {
    durationType: dur.durationType,
    durationValue: dur.durationValue,
    paceMode: paceSec != null ? "pace" : "zone",
    zone: zone || "fiveK",
    paceSec,
    zoneOff,
  };
}

function parseSegment(seg: string): ParsedStep | null {
  let s = seg.trim();
  if (!s) return null;
  s = s.replace(/\bat\b/gi, "@"); // "10' tempo at HM" reads like "@ HM"
  let kind: ParsedStep["kind"] | null = null;
  if (/\b(?:wu|warm[\s-]?up)\b/i.test(s)) kind = "warmup";
  if (/\b(?:cd|cool[\s-]?down)\b/i.test(s)) kind = "cooldown";

  // in-segment set rest: "... 5' b/t sets"
  let setRestSec: number | null = null;
  if (SET_REST_RE.test(s)) {
    setRestSec = parseSetRest(s);
    s = s.replace(SET_REST_RE, " ");
  }

  // sets prefix: "2 sets of 6 x 400m"
  let sets = 1;
  const setsMatch = s.match(/^(\d+)\s*sets?\s*(?:of\s*)?/i);
  if (setsMatch) {
    sets = +setsMatch[1];
    s = s.slice(setsMatch[0].length);
  }

  // compound set: "(600 @ 5k / 400 @ 3k)" — alternating reps
  let segments: MiniSegment[] | null = null;
  const parenMatch = s.match(/\(([^)]*)\)/);
  if (parenMatch) {
    const parts = parenMatch[1].split(/\/|&|\s\+\s/).map((t) => t.trim()).filter(Boolean);
    const parsed = parts.map(parseMiniSegment).filter((x): x is MiniSegment => x != null);
    if (parsed.length) {
      segments = parsed;
      s = s.replace(parenMatch[0], " ");
    }
  }

  // recovery clause: "w/ 400m jog", "w/45' rest"
  let recovery: Recovery | null = null;
  const recMatch = s.match(/\b(?:w\/|with)\s*(.+)$/i);
  if (recMatch) {
    recovery = parseRecovery(recMatch[1]);
    s = s.slice(0, recMatch.index);
  }

  // reps — supports ranges: "4-6 x 800"
  let reps = 1;
  let repsMax: number | null = null;
  const repsMatch = s.match(/^(\d+)(?:\s*[-–]\s*(\d+))?\s*[x×]\s*/i);
  if (repsMatch) {
    reps = +repsMatch[1];
    repsMax = repsMatch[2] ? +repsMatch[2] : null;
    s = s.slice(repsMatch[0].length);
  }

  if (segments) {
    const S = Math.max(sets, reps);
    return {
      kind: "reps",
      reps: 1,
      repsMax: null,
      sets: S,
      setRestSec,
      segments,
      durationType: "m",
      durationValue: 0,
      durationValueMax: null,
      paceMode: "zone",
      zone: "fiveK",
      paceSec: null,
      timeSec: null,
      recovery,
      zoneOff: null,
    };
  }

  // target time: "in 3:00", "in 78"
  let timeSec: number | null = null;
  const inMatch = s.match(/\bin\s+(\d{1,2}:\d{2}|\d+)\b/i);
  if (inMatch) {
    timeSec = parseClockStr(inMatch[1]);
    s = s.replace(inMatch[0], " ");
  }

  // pace clause after @
  let zone: PaceZone | null = null;
  let paceSec: number | null = null;
  let zoneOff: Off | null = null;
  const atIdx = s.indexOf("@");
  let mainPart = s;
  let pacePart: string | null = null;
  if (atIdx >= 0) {
    mainPart = s.slice(0, atIdx);
    pacePart = s.slice(atIdx + 1).trim();
  }
  if (pacePart) {
    const clock = pacePart.match(/(\d{1,2}):(\d{2})(?:\s*\/?\s*(mi|mile|km|k))?/);
    if (clock) {
      paceSec = +clock[1] * 60 + +clock[2];
      if (clock[3] && /k/i.test(clock[3])) paceSec = paceSec * KM_PER_MILE;
    } else {
      const zo = parseZoneWithOffset(pacePart);
      if (zo) {
        zone = zo.zone;
        zoneOff = zo.off;
      }
    }
  }

  const dur = parseDuration(mainPart);
  if (!dur && timeSec == null) return null;

  // bare zone word without @ ("40 min easy")
  if (!zone && paceSec == null && timeSec == null) {
    const words = mainPart.replace(/\b(?:wu|warm[\s-]?up|cd|cool[\s-]?down)\b/gi, " ").trim().split(/\s+/);
    for (const w of words) {
      const z = matchZoneWord(w);
      if (z) {
        zone = z;
        break;
      }
    }
  }

  // standalone rest: "5' rest", "3 min rest" — no pace, just stand there
  if (
    !kind &&
    /\brest\b/i.test(seg) &&
    !zone &&
    paceSec == null &&
    timeSec == null &&
    reps === 1 &&
    sets === 1 &&
    !recovery &&
    dur &&
    dur.durationType === "time"
  ) {
    kind = "rest";
  }
  if (!kind) kind = reps > 1 || sets > 1 ? "reps" : "block";
  if ((kind === "warmup" || kind === "cooldown") && !zone && paceSec == null && timeSec == null) {
    zone = "easy";
  }

  const step: ParsedStep = {
    kind,
    reps,
    repsMax,
    sets,
    setRestSec,
    durationType: dur ? dur.durationType : "m",
    durationValue: dur ? dur.durationValue : 400,
    durationValueMax: dur && dur.durationValueMax ? dur.durationValueMax : null,
    paceMode: timeSec != null ? "time" : paceSec != null ? "pace" : "zone",
    zone: zone || (kind === "reps" ? "fiveK" : "easy"),
    zoneOff,
    paceSec: paceSec || null,
    timeSec: timeSec || null,
    recovery,
    segments: null,
  };
  if (kind === "rest") {
    step.paceMode = "none";
    step.zone = null;
  }
  return step;
}

// Split on , ; newline + "then" — but never inside ( ), and never on the "+"
// of an offset like MP+15 (attached + is an offset, spaced + separates).
function splitSegments(text: string): string[] {
  const out: string[] = [];
  let cur = "";
  let depth = 0;
  for (const ch of text) {
    if (ch === "(") depth++;
    if (ch === ")") depth = Math.max(0, depth - 1);
    const plusIsOffset = ch === "+" && cur.length > 0 && !/\s/.test(cur.slice(-1));
    if (depth === 0 && !plusIsOffset && (ch === "," || ch === ";" || ch === "\n" || ch === "+")) {
      out.push(cur);
      cur = "";
    } else {
      cur += ch;
    }
  }
  out.push(cur);
  return out.flatMap((p) => p.split(/\bthen\b/i)).map((t) => t.trim()).filter(Boolean);
}

interface ParseNLResult {
  steps: ParsedStep[];
  unparsed: string[];
}

function parseNL(text: string): ParseNLResult {
  // "w/ 200m jogs between reps 2mi cd" — cut the recovery clause at "between
  // reps" so whatever follows becomes its own step.
  const prepped = text.replace(/\b(?:between|b\/t|btw)\s+reps?\b/gi, "b/t-reps,");
  const segs = splitSegments(prepped);
  const steps: ParsedStep[] = [];
  const unparsed: string[] = [];
  for (const seg of segs) {
    const st = parseSegment(seg);
    if (st) {
      steps.push(st);
      continue;
    }
    // orphan "5' b/t sets" segment → attach to the last multi-set step
    const sr = parseSetRest(seg);
    if (sr != null) {
      const target = [...steps].reverse().find((x) => (x.sets || 1) > 1) || steps[steps.length - 1];
      if (target) {
        target.setRestSec = sr;
        continue;
      }
    }
    unparsed.push(seg);
  }
  return { steps, unparsed };
}

// ── Adapter: ParsedStep → web WorkoutStep ────────────────

let idCounter = 0;
function nextId(): string {
  idCounter += 1;
  return `nl-${Date.now().toString(36)}-${idCounter}`;
}

function mapDurationType(t: ProtoDurationType): WorkoutStep["durationType"] {
  switch (t) {
    case "mi": return "distance_miles";
    case "km": return "distance_km";
    case "m": return "distance_meters";
    case "time": return "time_seconds";
  }
}

// Collapse a value + optional max to a single number (midpoint), rounded to a
// sensible precision for its unit. The web model has no range fields.
function collapseValue(t: ProtoDurationType, value: number, max: number | null): number {
  const v = max ? (value + max) / 2 : value;
  if (t === "mi" || t === "km") return Math.round(v * 10) / 10;
  return Math.round(v); // meters, seconds
}

function offToAdjustment(off: Off | null): PaceAdjustment | undefined {
  if (!off || off.v === 0) return undefined;
  return off.kind === "pct"
    ? { type: "percent", value: off.v }
    : { type: "seconds_per_mile", value: off.v };
}

function protoDurToMiles(t: ProtoDurationType, v: number): number {
  if (t === "mi") return v;
  if (t === "km") return v / KM_PER_MILE;
  if (t === "m") return v / METERS_PER_MILE;
  return 0; // time-based: unknown distance
}

function mapRecovery(rec: Recovery): WorkoutStep["recovery"] {
  return {
    durationType: mapDurationType(rec.durationType),
    durationValue: collapseValue(rec.durationType, rec.durationValue, null),
    // A jog recovery runs at easy pace; a standing/walk rest has no pace zone.
    paceZone: rec.style === "jog" ? "easy" : undefined,
  };
}

const KIND_TO_STEP_TYPE: Record<ParsedStep["kind"], WorkoutStep["stepType"]> = {
  warmup: "warmup",
  cooldown: "cooldown",
  rest: "rest",
  reps: "active",
  block: "active",
};

export interface ParseWorkoutResult {
  /** Structured steps ready for the editor. */
  steps: WorkoutStep[];
  /** Fragments the parser couldn't turn into a step (surface to the coach). */
  unparsed: string[];
}

/**
 * Parse coach shorthand into WorkoutStep[]. Anything that can't be represented
 * (unparseable fragments, or compound "(a / b)" sets which the web model
 * doesn't support yet) is returned in `unparsed` so the UI can tell the coach
 * to add it by hand rather than silently dropping it.
 */
export function parseWorkoutText(text: string): ParseWorkoutResult {
  const { steps: parsed, unparsed } = parseNL(text);
  const steps: WorkoutStep[] = [];
  const unsupported: string[] = [...unparsed];

  for (const p of parsed) {
    // Compound alternating sets have no flat-model equivalent — v1 drops them
    // and reports the fragment for manual entry.
    if (p.segments && p.segments.length > 0) {
      const desc = p.segments
        .map((sg) => `${sg.durationValue}${sg.durationType === "m" ? "m" : sg.durationType} @ ${paceShort(sg.zone)}`)
        .join(" / ");
      unsupported.push(`(${desc})`);
      continue;
    }

    // "sets of reps" flattens to total repeats (set-rest is dropped in v1).
    const reps = collapseReps(p);
    const totalRepeats = Math.max(1, reps * Math.max(1, p.sets));

    // Target time ("800 in 2:30") → an exact per-mile pace.
    let exactPaceSecPerMile: number | undefined;
    if (p.paceMode === "time" && p.timeSec != null) {
      const miles = protoDurToMiles(p.durationType, collapseValue(p.durationType, p.durationValue, p.durationValueMax));
      if (miles > 0) exactPaceSecPerMile = Math.round(p.timeSec / miles);
    } else if (p.paceMode === "pace" && p.paceSec != null) {
      exactPaceSecPerMile = Math.round(p.paceSec);
    }

    const step: WorkoutStep = {
      id: nextId(),
      stepType: KIND_TO_STEP_TYPE[p.kind],
      durationType: mapDurationType(p.durationType),
      durationValue: collapseValue(p.durationType, p.durationValue, p.durationValueMax),
      // paceZone is required by the type; for rest/exact-pace steps it's a
      // harmless filler that the renderer ignores in favor of stepType/exact.
      paceZone: p.zone ?? "easy",
      notes: "",
    };
    if (exactPaceSecPerMile != null) {
      step.exactPaceSecPerMile = exactPaceSecPerMile;
    } else {
      const adj = offToAdjustment(p.zoneOff);
      if (adj) step.paceAdjustment = adj;
    }
    if (totalRepeats > 1) step.repeats = totalRepeats;
    if (p.recovery) step.recovery = mapRecovery(p.recovery);

    steps.push(step);
  }

  return { steps, unparsed: unsupported };
}

// reps range ("4-6 x 800") → midpoint rep count.
function collapseReps(p: ParsedStep): number {
  if (p.repsMax && p.repsMax > p.reps) return Math.round((p.reps + p.repsMax) / 2);
  return p.reps || 1;
}
