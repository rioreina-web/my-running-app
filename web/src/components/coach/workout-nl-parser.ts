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
//        - compound sets ("(600 @ 5k / 400 @ 3k)") → expanded leg by leg,
//          since the flat format can express them even though `repeats` can't.

import { paceShort, type PaceZone, type WorkoutStep, type PaceAdjustment } from "./workout-helpers";

const KM_PER_MILE = 1.609344;
const METERS_PER_MILE = 1609.344;

// A bare "m" is ambiguous in coach shorthand: "800m" is track meters but
// "7m moderate" and "3x3m @ MP" are MILES. Audited against 139 real workouts
// across six seasons of this coach's plans — every bare-m value below this
// threshold was miles, every value at or above it was meters. Spelled-out
// "meters" and "mi" are never ambiguous and bypass this rule.
const BARE_M_MILES_MAX = 100;

// Number fragment that also accepts leading-dot decimals — coaches write
// ".5 float" and ".25 float". The old `\d+(?:\.\d+)?` skipped the dot and
// matched the 5 alone, turning a half-mile float into a five-mile float.
const NUM = String.raw`\d+(?:\.\d+)?|\.\d+`;
const re = (body: string, flags = "i") => new RegExp(body, flags);

// A hyphenated pair is only a range if it ascends. "1200-300 - 10k" is two
// reps written back to back; reading it as a 300→10 span produced a 155km step.
const ascends = (a: string, b: string) => parseFloat(b) > parseFloat(a);

// Zone words as a regex alternation, for the places that need to spot a pace
// token inside free text rather than match one exactly.
const ZONE_ALT = "MP|HMP?|LT|5k|10k|3k|mile|marathon|threshold|tempo|easy|steady|moderate|medium|recovery";

// "at" means "@" ONLY when a pace or a clock follows it. A blanket rewrite
// turned "(rest 4' at halfway)" into "(rest 4' @ halfway)", which read as a
// paced rep and expanded one workout into ten phantom 4-minute steps.
const AT_AS_PACE = new RegExp(`\\bat\\s+(?=(?:${ZONE_ALT}|\\d))`, "gi");

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
  /**
   * A leg inside a compound set. "rest" legs are the recoveries written
   * between reps ("1' rest") — they become the preceding rep's `recovery`
   * rather than steps of their own.
   */
  kind: "rep" | "rest";
  /** Reps of THIS leg inside one set: the 5 in "2k@HM / 5x400m@5k". */
  reps: number;
  durationType: ProtoDurationType;
  durationValue: number;
  paceMode: "pace" | "zone";
  /** null when the coach gave no pace — never guess one. */
  zone: PaceZone | null;
  paceSec: number | null;
  zoneOff: Off | null;
  /** rest legs only: jogged or stood. */
  style?: "jog" | "rest";
  /** rep legs only: a recovery written onto the leg itself ("5x400 w/1' rest"). */
  ownRecovery?: Recovery | null;
}

interface ParsedStep {
  /** Text the flat model can't encode structurally: "progress to HM", or a
   *  parenthetical instruction to the athlete. Rendered as the step's note. */
  note: string | null;
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
  // "tempo" is this coach's most-used word for threshold work and was missing
  // entirely — 18 of 139 audited workouts prescribed tempo and silently
  // resolved to Easy, inverting the session's whole intent.
  [/^(?:lt|threshold|thr|tempo)$/i, "threshold"],
  [/^(?:rec|recovery)$/i, "recovery"],
  [/^(?:easy)$/i, "easy"],
  [/^(?:mod|moderate|medium)$/i, "moderate"],
  [/^(?:steady)$/i, "steady"],
  [/^(?:long)$/i, "longRun"],
];

function matchZoneWord(raw: string): PaceZone | null {
  // "MP effort", "10k pace", "threshold effort" all name the zone itself.
  const s = raw.trim().replace(/\s*(?:pace|effort)$/i, "").replace(/\s+marathon$/i, "");
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
  // ranges first: "10-12k", "30-40 min", "4-6 mi", "600-800m". Each requires
  // an ascending pair — see `ascends`.
  let m = s.match(re(`(${NUM})\\s*[-–]\\s*(${NUM})\\s*(?:min\\b|mins\\b|minutes\\b|')`));
  if (m && ascends(m[1], m[2])) return { durationType: "time", durationValue: +m[1] * 60, durationValueMax: +m[2] * 60 };
  m = s.match(re(`(${NUM})\\s*[-–]\\s*(${NUM})\\s*(?:miles|mile|mi)\\b`));
  if (m && ascends(m[1], m[2])) return { durationType: "mi", durationValue: +m[1], durationValueMax: +m[2] };
  m = s.match(re(`(${NUM})\\s*[-–]\\s*(${NUM})\\s*(?:km|k)\\b`));
  if (m && ascends(m[1], m[2])) return { durationType: "km", durationValue: +m[1], durationValueMax: +m[2] };
  m = s.match(/(\d{3,4})\s*[-–]\s*(\d{3,4})\s*(?:meters|meter|m)?\b/);
  if (m && +m[1] >= 200 && ascends(m[1], m[2])) return { durationType: "m", durationValue: +m[1], durationValueMax: +m[2] };
  // bare-m range below the meters threshold reads as miles: "8-12m alternations"
  m = s.match(re(`(${NUM})\\s*[-–]\\s*(${NUM})\\s*m\\b`));
  if (m && ascends(m[1], m[2]) && parseFloat(m[2]) < BARE_M_MILES_MAX) {
    return { durationType: "mi", durationValue: +m[1], durationValueMax: +m[2] };
  }
  // seconds: 45", 45 sec, 90s
  m = s.match(re(`(${NUM})\\s*(?:"|″|s\\b|sec\\b|secs\\b|seconds\\b)`));
  if (m) return { durationType: "time", durationValue: parseFloat(m[1]) };
  // minutes: "40 min", "40'"
  m = s.match(re(`(${NUM})\\s*(?:min\\b|mins\\b|minutes\\b|'|′)`));
  if (m) return { durationType: "time", durationValue: parseFloat(m[1]) * 60 };
  // distance: order matters — miles before meters
  m = s.match(re(`(${NUM})\\s*(?:miles|mile|mi)\\b`));
  if (m) return { durationType: "mi", durationValue: parseFloat(m[1]) };
  m = s.match(re(`(${NUM})\\s*(?:km|k)\\b`));
  if (m) return { durationType: "km", durationValue: parseFloat(m[1]) };
  // A bare "m" splits by magnitude — see BARE_M_MILES_MAX. Spelled-out
  // "meters"/"meter" is always meters.
  m = s.match(re(`(${NUM})\\s*(meters|meter|m)\\b`));
  if (m) {
    const v = parseFloat(m[1]);
    const bare = m[2].toLowerCase() === "m";
    return bare && v < BARE_M_MILES_MAX
      ? { durationType: "mi", durationValue: v }
      : { durationType: "m", durationValue: v };
  }
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
  let m = s.match(re(`(${NUM})\\s*(?:"|″|sec\\b|secs\\b|seconds\\b)`));
  if (m) return { durationType: "time", durationValue: parseFloat(m[1]), style };
  // apostrophe in a recovery clause: 5' reads as minutes, 45' as seconds
  m = s.match(re(`(${NUM})\\s*(?:'|′)`, ""));
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
      else {
        // Unitless decimal in a recovery clause is miles: "w/.5 float",
        // "w/.25 float". Whole numbers stay ambiguous and fall through —
        // "w/800 float" is meters and parseDuration already claimed it.
        const bare = s.match(/(?:^|\s|\/)(\.\d+|\d\.\d+)(?!\d)/);
        if (bare) dur = { durationType: "mi", durationValue: parseFloat(bare[1]) };
      }
    }
  }
  if (!dur) return null;
  return { durationType: dur.durationType, durationValue: dur.durationValue, style };
}

// "5' b/t sets" / "5 min between sets" → seconds of rest between sets
// The `(?:rest|jog|...)` group matters: coaches write "4' rest b/t sets", and
// without it the clause failed to match, so the set rest was both dropped AND
// unreported — the worst of both.
const SET_REST_RE =
  /(\d+(?::\d{2})?(?:\.\d+)?)\s*('|′|"|″|min\b|mins\b|minutes\b|sec\b|secs\b|seconds\b)?\s*(?:rest|jog|recovery|rec|walk)?\s*(?:b\/t|btw|between)\s*sets?/i;
function parseSetRest(s: string): number | null {
  const m = s.match(SET_REST_RE);
  if (!m) return null;
  if (m[1].includes(":")) return parseClockStr(m[1]);
  const v = parseFloat(m[1]);
  if (m[2] && /"|″|sec/i.test(m[2])) return v;
  return v * 60;
}

// "MP > HM", "HMP>10k", "MP > HM-5" — a progression from one zone to another.
// The flat model holds one zone per step, so the step takes the STARTING zone
// and the destination is written into the step's note. Lossy but honest: the
// alternative was dropping the whole segment, which is what used to happen.
function parseProgression(str: string): { zone: PaceZone; off: Off | null; toward: string } | null {
  const m = str.match(/^(.+?)\s*(?:>|->|\u2192|\bto\b)\s*(.+)$/i);
  if (!m) return null;
  const from = parseZoneWithOffset(m[1]);
  const to = parseZoneWithOffset(m[2]);
  if (!from || !to) return null;
  return { zone: from.zone, off: from.off, toward: m[2].trim() };
}

// A ladder written as parallel lists: "600/400 @ 5k/3k", "3m/3m/2m - MP/MP-10/MP-20".
// Each distance is zipped to the pace in the same position. One pace for many
// distances applies to all of them.
function parseParallelLists(main: string, pacePart: string | null): MiniSegment[] | null {
  const distParts = main.split("/").map((t) => t.trim()).filter(Boolean);
  if (distParts.length < 2) return null;
  const legs = distParts.map(parseMiniSegment);
  if (legs.some((l) => l == null || l.kind !== "rep")) return null;
  const reps = legs as MiniSegment[];

  if (pacePart) {
    // Trim a trailing recovery or rest off the pace list — "5k/3k - 200j",
    // "10k/3k pace 2' rec" — so the last zone still parses.
    const cleanedPace = pacePart
      .replace(/\s*[-\u2013]\s*\d+\s*(?:j|jog|rest|rec|recovery|float)\b.*$/i, "")
      .replace(/\s+\d+['\u2032"]?\s*(?:j|jog|rest|rec|recovery|float)\b.*$/i, "")
      .replace(/\s*\bpace\b\s*$/i, "");
    const paceParts = cleanedPace.split("/").map((t) => t.trim()).filter(Boolean);
    const zones = paceParts.map((t) => parseZoneWithOffset(t));
    if (zones.every((z) => z != null)) {
      if (zones.length === reps.length) {
        reps.forEach((leg, i) => {
          if (leg.zone == null) { leg.zone = zones[i]!.zone; leg.zoneOff = zones[i]!.off; }
        });
      } else if (zones.length === 1) {
        reps.forEach((leg) => {
          if (leg.zone == null) { leg.zone = zones[0]!.zone; leg.zoneOff = zones[0]!.off; }
        });
      }
    }
  }
  return reps;
}

// A single rep inside a compound set: "600 @ 5k pace", "1 min @ 6:00"
function parseMiniSegment(str: string): MiniSegment | null {
  // Classify BEFORE the at->@ rewrite. "(rest 4' at halfway)" is a note about
  // a rest; rewriting first turned its "at" into an "@", which made the clause
  // look like a paced rep and expanded a whole workout into ten 4' steps.
  const raw = str.trim();
  const restWord = /\b(?:rest|jog|walk|float|recovery|rec|standing|slow)\b/i.test(raw);
  const hasPaceTarget = /@/.test(raw) || /\bat\s+(?:MP|HMP?|LT|5k|10k|3k|mile|marathon|threshold|tempo|easy|steady|moderate)\b/i.test(raw);

  let s = str.replace(AT_AS_PACE, "@ ").trim();
  let zone: PaceZone | null = null;
  let paceSec: number | null = null;
  let zoneOff: Off | null = null;

  // A leg with a rest word and no pace target is the recovery between reps,
  // not a rep: "1' rest", "400m jog", "200 slow jog". It attaches to the leg
  // before it rather than becoming a step.
  if (restWord && !hasPaceTarget) {
    s = raw;
    const rec = parseRecovery(s);
    if (rec) {
      return {
        kind: "rest",
        reps: 1,
        durationType: rec.durationType,
        durationValue: rec.durationValue,
        paceMode: "zone",
        zone: null,
        paceSec: null,
        zoneOff: null,
        style: rec.style,
        ownRecovery: null,
      };
    }
  }

  // A leg can carry its own recovery: "5x400m@5k w/1' rest". Pull it off
  // before the @ split, or it lands in the pace clause and the zone is lost.
  let ownRecovery: Recovery | null = null;
  const ownRec = s.match(/\b(?:w\/|with)\s*(.+)$/i);
  if (ownRec) {
    ownRecovery = parseRecovery(ownRec[1]);
    if (ownRecovery) s = s.slice(0, ownRec.index).trim();
  }

  // reps of this leg inside one set: the 5 in "2k@HM / 5x400m@5k"
  let reps = 1;
  const repsMatch = s.match(/^(\d+)\s*[x\u00d7]\s*/i);
  if (repsMatch) {
    reps = +repsMatch[1];
    s = s.slice(repsMatch[0].length);
  }

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

  // Bare zone word with no "@": "10' steady", "2' easy". parseSegment has
  // always done this for whole segments; legs inside a set need it too.
  if (!zone && paceSec == null) {
    const durFromBareUnit = !/\d/.test(main);
    for (const w of main.trim().split(/\s+/)) {
      if (durFromBareUnit && /^(?:miles?|mi|k|km)$/i.test(w)) continue;
      const z = matchZoneWord(w);
      if (z) { zone = z; break; }
      const zo = parseZoneWithOffset(w);
      if (zo) { zone = zo.zone; zoneOff = zo.off; break; }
    }
  }

  return {
    kind: "rep",
    reps,
    ownRecovery,
    durationType: dur.durationType,
    durationValue: dur.durationValue,
    paceMode: paceSec != null ? "pace" : "zone",
    zone,
    paceSec,
    zoneOff,
  };
}

// ── Alternations ─────────────────────────────────────────
//
// This coach writes the same session six different ways, and until now not
// one of them parsed:
//
//   "16 x K alternating MP-3% & MP+5%"
//   "8-12m alternations (MP-10/MP+30)"
//   "8-10m of alternations MP-10/MP+10"
//   "7mi alternations (1m at MP-10/1mi at MP +20)"
//   "10 mi Alternations- (1 mi at MP-10/1 mi at MP+30)"
//   "Alternating 8mi: 1mi @ 10k / 1mi easy"
//
// The word carries the whole structure, and the grammar had no token for it.
// So the paces fell out — into a parenthetical note, or out of the string
// entirely — and a marathon-pace session came back as a flat block at EASY:
// the exact inversion the rest of this file spends two hundred lines
// guarding against.
//
// Nothing new is needed downstream. An alternation IS a compound set with two
// legs, and the adapter has expanded those leg by leg since v2. This function
// only has to find the two numbers that decide the shape, which each form
// writes differently:
//
//   · a REP COUNT plus a unit ("16 x K")  → exactly 16 legs of 1km
//   · a TOTAL distance ("8-12m", "7mi")   → total ÷ leg length, legs
//
// An odd total is not a mistake to round away: "7mi alternations" of 1-mile
// legs is four fast and three float. It must stay seven steps.
const ALTERNATION_RE = /\balternat(?:ing|ions?|es?|ed)\b/i;

/** Half a leg's tolerance, so 7 miles of 1-mile legs is 7 legs and not 8. */
function legsForTotal(totalMiles: number, template: MiniSegment[]): number {
  let acc = 0;
  let n = 0;
  while (n < MAX_EXPANDED_STEPS) {
    const leg = template[n % template.length];
    const legMiles = protoDurToMiles(leg.durationType, leg.durationValue);
    if (legMiles <= 0) return 0;
    if (acc + legMiles / 2 > totalMiles) break;
    acc += legMiles;
    n += 1;
  }
  return n;
}

/**
 * The same session with the word left out: "16 x K @ MP-3% & MP+5%". One rep
 * count, one distance, TWO paces — which in this dialect can only mean the
 * reps alternate between them.
 *
 * Gated hard, because a slash after a pace usually introduces a RECOVERY
 * ("6x800 @ 5k / 400 jog"), not a second work pace. Both sides must read as
 * a zone, and at least one must carry an explicit offset — which is how this
 * coach writes every alternation and how nobody writes a float. Anything
 * looser starts eating recoveries and turning them into work.
 */
function parseWordlessAlternation(s0: string): ParsedStep | null {
  const at = s0.indexOf("@");
  if (at < 0) return null;
  const head = s0.slice(0, at).trim();
  const tail = s0.slice(at + 1).trim();
  if (!re(`^(${NUM})(?:\\s*-\\s*(${NUM}))?\\s*[x×]\\s`).test(head + " ")) return null;
  const parts = tail.split(/\/|&|\bvs\.?\b/i).map((t) => t.trim()).filter(Boolean);
  if (parts.length < 2) return null;
  const zones = parts.map(parseZoneWithOffset);
  if (!zones.every((z) => z != null)) return null;
  if (!zones.some((z) => z!.off != null)) return null;
  return parseAlternation(`${head} alternating ${parts.join(" / ")}`);
}

function parseAlternation(seg: string): ParsedStep | null {
  const s0 = seg.replace(/−|–/g, "-").trim();
  const alt = s0.match(ALTERNATION_RE);
  if (!alt || alt.index == null) return parseWordlessAlternation(s0);

  let head = s0.slice(0, alt.index).trim();
  let tail = s0
    .slice(alt.index + alt[0].length)
    // "Alternations- (…)", "alternations: …", "alternations - …"
    .replace(/^\s*[-:,]\s*/, "")
    .trim();
  // "of" is left behind by "8-10m of alternations".
  head = head.replace(/\bof\b\s*$/i, "").trim();
  const paren = tail.match(/^\(([\s\S]*)\)$/);
  if (paren) tail = paren[1].trim();

  // "Alternating 8mi: 1mi @ 10k / 1mi easy" puts the total AFTER the word.
  if (!head) {
    const lead = tail.match(/^([^:,]+?)\s*[:,]\s*(.+)$/);
    if (!lead) return null;
    head = lead[1].trim();
    tail = lead[2].trim();
  }
  if (!tail) return null;

  // A rep count is decisive when present: "16 x K" is sixteen legs, whatever
  // the arithmetic on the legs would otherwise say.
  const repsMatch = head.match(re(`(${NUM})(?:\\s*-\\s*(${NUM}))?\\s*[x×]\\s*(.*)$`));
  const headDur = parseDuration(repsMatch ? repsMatch[3] : head);

  const parts = tail.split(/\/|&|\bvs\.?\b|\band\b/i).map((t) => t.trim()).filter(Boolean);
  if (parts.length < 2) return null;

  // Two ways to write the legs. Explicit ("1m at MP-10") carries its own
  // distance; pace-only ("MP-10") borrows it from the header's unit.
  const explicit = parts.map(parseMiniSegment);
  let template: MiniSegment[];
  if (explicit.every((l) => l != null && l.kind === "rep" && (l.zone != null || l.paceSec != null))) {
    template = explicit as MiniSegment[];
  } else {
    const zones = parts.map(parseZoneWithOffset);
    // Never claim an alternation whose paces we could not read. Falling
    // through leaves the old (wrong but flagged) path to report it, which is
    // better than emitting confident halves of a session.
    if (!zones.every((z) => z != null)) return null;
    if (!headDur || (headDur.durationType !== "mi" && headDur.durationType !== "km")) return null;
    // Pace-only legs are one of whatever unit the header is counting in:
    // "16 x K" → 1km each, "8-12m alternations" → 1 mile each.
    const legUnit: ProtoDurationType = repsMatch ? headDur.durationType : headDur.durationType;
    const legValue = repsMatch ? headDur.durationValue : 1;
    template = zones.map((z) => ({
      kind: "rep" as const,
      reps: 1,
      durationType: legUnit,
      durationValue: legValue,
      paceMode: "zone" as const,
      zone: z!.zone,
      paceSec: null,
      zoneOff: z!.off,
      ownRecovery: null,
    }));
  }

  let legCount: number;
  if (repsMatch) {
    legCount = repsMatch[2]
      ? Math.round((parseFloat(repsMatch[1]) + parseFloat(repsMatch[2])) / 2)
      : Math.round(parseFloat(repsMatch[1]));
  } else {
    if (!headDur) return null;
    const totalMiles = protoDurToMiles(
      headDur.durationType,
      headDur.durationValueMax ? (headDur.durationValue + headDur.durationValueMax) / 2 : headDur.durationValue,
    );
    if (totalMiles <= 0) return null;
    legCount = legsForTotal(totalMiles, template);
  }
  if (legCount < 2 || legCount > MAX_EXPANDED_STEPS) return null;

  const segments: MiniSegment[] = [];
  for (let i = 0; i < legCount; i++) segments.push({ ...template[i % template.length] });

  return {
    note: null,
    kind: "reps",
    reps: 1,
    repsMax: null,
    sets: 1,
    setRestSec: null,
    segments,
    durationType: "m",
    durationValue: 0,
    durationValueMax: null,
    paceMode: "zone",
    zone: null,
    zoneOff: null,
    paceSec: null,
    timeSec: null,
    recovery: null,
  };
}

function parseSegment(seg: string): ParsedStep | null {
  let s = seg.trim();
  if (!s) return null;
  // Before anything else: the alternation forms encode their structure in a
  // word, not in punctuation, so none of the syntactic paths below can see it.
  const alternation = parseAlternation(s);
  if (alternation) return alternation;
  s = s.replace(AT_AS_PACE, "@ "); // "10' tempo at HM" reads like "@ HM"
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
  const setsMatch = s.match(/^(\d+)(?:\s*[-\u2013]\s*(\d+))?\s*sets?\s*(?:of\s*)?/i);
  if (setsMatch) {
    // "2-3 sets" takes the midpoint, matching how rep ranges collapse. Without
    // the range group this matched nothing and every ranged set became one set.
    sets = setsMatch[2] ? Math.round((+setsMatch[1] + +setsMatch[2]) / 2) : +setsMatch[1];
    s = s.slice(setsMatch[0].length);
  }

  let parenNote: string | null = null;

  // A recovery written ABOUT THE SET rather than about one leg:
  // "… & 600 @ 10k w/1' between reps". It has to come off before the legs are
  // split, because the split hands the tail to whichever leg happens to be
  // last and `parseMiniSegment` then claims it as that leg's own recovery —
  // so "7 sets of 1k @ HM & 600 @ 10k w/1' between reps" produced seven
  // recoveries instead of fourteen. Half the rest in the session, dropped
  // with no warning, on a session where the rest IS the prescription.
  //
  // "between reps"/"b/t each" is the marker that makes it set-wide. A bare
  // "w/1' rest" on a leg stays that leg's, which is what "5x400 w/1' rest"
  // inside a compound set means.
  //
  // The separator before the noun must allow a HYPHEN, not just a space:
  // normalisation upstream rewrites "between reps" to "b/t-reps" before this
  // sees it, so a `\s+` here silently never fires.
  let setWideRecovery: Recovery | null = null;
  const setWideRec = s.match(
    /\s*\b(?:w\/|with)\s*(.+?)[\s-]+(?:between|b\/t)[\s-]+(?:reps?|each|every|legs?|intervals?)\s*$/i,
  );
  if (setWideRec) {
      setWideRecovery = parseRecovery(setWideRec[1]);
    if (setWideRecovery) s = s.slice(0, setWideRec.index).trim();
    }

  // compound set: "(600 @ 5k / 400 @ 3k)", "(1k @ hm - 1' rest - 600m @ 10k)"
  //
  // Legs separate on "/", "&", "+", "then", "," or a SPACED hyphen. The space
  // matters: "MP-5" is an offset and must stay one token, while "1k @ hm - 1'
  // rest" is two legs. An en/em dash counts either way since no offset uses one.
  let segments: MiniSegment[] | null = null;
  const parenMatch = s.match(/\(([^)]*)\)/);
  if (parenMatch) {
    // "w/" and "b/t" carry the same slash that separates legs, so shield them
    // before splitting - otherwise "5x400m@5k w/1' rest" tears in half and the
    // "@5k" leaves with the tail, costing the leg its pace.
    const inner = parenMatch[1].trim();
    const parts = parenMatch[1]
      .replace(/\bw\//gi, SHIELD.w)
      .replace(/\bb\/t\b/gi, SHIELD.bt)
      .split(/\s+[-\u2013\u2014]\s+|\/|&|\s\+\s|\bthen\b|,/i)
      .map((t) => t.split(SHIELD.w).join("w/").split(SHIELD.bt).join("b/t").trim())
      .filter(Boolean);
    // Try the PACE reading first. "(MP > 10k)" and "(5k)" are pace clauses,
    // but parseMiniSegment happily reads "10k" as a 10-kilometre duration, so
    // testing for legs first turned "7 x mile cutdown (MP > 10k)" into seven
    // 10km reps — a 43-mile session. A whole-content pace match is decisive;
    // a genuine set like "(600 @ 5k / 400 @ 3k)" matches neither and falls
    // through to the leg reading below.
    const wholeAsPace = parseZoneWithOffset(inner) || parseProgression(inner);
    const parsed = wholeAsPace
      ? []
      : parts.map(parseMiniSegment).filter((x): x is MiniSegment => x != null);
    // A set with no runnable leg is not a set — let it fall through to the
    // ordinary grammar rather than emitting a rest-only "workout".
    if (parsed.some((x) => x.kind === "rep")) {
      segments = parsed;
      s = s.replace(parenMatch[0], " ");
    } else {
      // Not a set. A parenthetical is either the pace for what precedes it —
      // "800 (5k)", "6m progression (MP > HM-5)" — or a note to a human,
      // "(rest 4' at halfway)", "(3M will do only through 400s)". Promote the
      // first, drop the second; never let either become phantom steps.
      const asPace = wholeAsPace;
      s = asPace
        ? s.replace(parenMatch[0], ` @ ${inner} `)
        : s.replace(parenMatch[0], " ");
      if (!asPace) parenNote = inner;
    }
  } else if (sets > 1 && (s.match(/@/g)?.length ?? 0) >= 2) {
    // The same compound set, written without brackets:
    //   "8 sets of 600 @ 5k - 200m jog - 400m @ 3k - 200m jog"
    //
    // This used to fall through to the ordinary grammar, which read the first
    // leg and threw the rest away — silently, with no `unparsed` entry. The
    // coach got "8 × 600m @ easy": the wrong distance, the wrong pace, and a
    // third of the volume, with nothing on screen to say so.
    //
    // The gate is TWO OR MORE "@" markers. That is what leg-by-leg notation
    // looks like, and it is what separates this from the list form that
    // already parses — "5 sets of 1200/400 - 10k/3k pace 2' rec" carries no
    // "@" at all, so it keeps its existing path untouched.
    const parts = s
      .replace(/\bw\//gi, SHIELD.w)
      .replace(/\bb\/t\b/gi, SHIELD.bt)
      .split(/\s+[-–—]\s+|\/|&|\s\+\s|\bthen\b|,/i)
      .map((t) => t.split(SHIELD.w).join("w/").split(SHIELD.bt).join("b/t").trim())
      .filter(Boolean);
    const parsed = parts
      .map(parseMiniSegment)
      .filter((x): x is MiniSegment => x != null);
    // Only claim it when the split actually accounted for the whole clause and
    // found real work in it. A partial read here would be the same silent
    // truncation in a new place.
    if (parsed.length === parts.length && parsed.some((x) => x.kind === "rep")) {
      segments = parsed;
      s = "";
    }
  }

  // recovery clause: "w/ 400m jog", "w/45' rest"
  let recovery: Recovery | null = null;
  // Coaches write the float three ways: "w/ 400m float", "with 400m float",
  // and — most commonly on a whiteboard — "6 x mile @ HM pace /400m float".
  // Only the first two were matched, so the bare-slash form parsed as reps
  // with NO recovery and the float vanished without a warning. The coach then
  // had to enter it by hand, which is how a 400m float became 25 miles.
  //
  // The slash can't be claimed unconditionally. It separates the legs of a
  // compound set ("600 @ 5k / 400 @ 3k"), it sits inside every written pace
  // ("7:10/mi"), and it appears twice in a ladder ("5 sets of 1200/400 -
  // 10k/3k pace 2' rec"). So the tail is only read as a recovery when it is
  // EXACTLY a quantity, an optional unit, and a rest word — nothing else to
  // the end of the string.
  //
  // Anything looser fails on the ladder above. Its tail "/3k pace 2' rec"
  // both starts with a digit and ends in "rec", so a permissive test claims
  // it and the second leg silently loses its 3k pace.
  const recMatch =
    s.match(/\b(?:w\/|with)\s*(.+)$/i) ??
    s.match(
      /\/\s*(\d+(?:\.\d+)?\s*(?:m|mi|km|k|s|sec|secs|min|mins|'|′|"|″)?\s*(?:jog|float|rest|rec|recovery|walk|standing))\s*$/i,
    );
  if (recMatch) {
    // "5 x 3m w/.5 float MP-5" — the pace trails the recovery clause. `(.+)$`
    // ate it, which cost the step its zone. Split the trailing pace back off
    // and re-attach it as an "@" clause for the normal pace path to find.
    let recText = recMatch[1];
    let trailingPace: string | null = null;
    const trail = recText.match(
      /\s*[-\u2013]?\s*((?:MP|HMP?|LT|5k|10k|3k|mile|marathon|threshold|tempo|easy|steady|moderate)\b[^,;]*)$/i,
    );
    if (trail && trail.index != null && trail.index > 0) {
      trailingPace = trail[1].trim();
      recText = recText.slice(0, trail.index);
    }
    recovery = parseRecovery(recText);
    s = s.slice(0, recMatch.index) + (trailingPace ? ` @ ${trailingPace}` : "");
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

  // "7-8 x mile cutdown MP > 10k" — with no "@", the bare unit word straight
  // after the rep count IS the rep distance. Without this, parseDuration
  // skipped it (no leading number) and grabbed the "10k" from the PACE clause,
  // while the zone scan then claimed "mile" — inverting the two and turning
  // 8 x 1 mile into 8 x 10km, a 49.7-mile session.
  let repUnitDur: Duration | null = null;
  if (repsMatch) {
    const bareUnit = s.match(/^(miles?|mi|km|k)\b\s*/i);
    if (bareUnit) {
      const u = bareUnit[1].toLowerCase();
      repUnitDur = /^(k|km)$/.test(u)
        ? { durationType: "km", durationValue: 1 }
        : { durationType: "mi", durationValue: 1 };
      s = s.slice(bareUnit[0].length);
    }
  }

  // Both the parenthesised set and the parallel-list ladder end up here.
  const compoundStep = (): ParsedStep => {
    const S = Math.max(sets, reps);
    return {
      note: parenNote,
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
      zone: null,
      paceSec: null,
      timeSec: null,
      // A set-wide "between reps" clause outranks nothing — it IS the set's
      // recovery. `recovery` here is the clause written after the set
      // ("7 x (1k @ hm / 600 @ 10k) w/1' rec"), which the adapter applies to
      // every leg that has no nearer recovery of its own.
      recovery: recovery ?? setWideRecovery,
      zoneOff: null,
    };
  };

  if (segments) return compoundStep();

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
    // Trim a trailing recovery off the pace clause. "@ MP > 10k  2' rec" would
    // otherwise fail BOTH the zone and the progression reading — the "2' rec"
    // rides along to the end of the string — and the step silently fell back
    // to easy. Same cleanup the ladder path already does for its pace list.
    pacePart = s
      .slice(atIdx + 1)
      // The `(?::\d{2})?` matters: without it the pattern latched onto the
      // "30" of "2:30 rest" and left "10k - 2:", which parses as no zone at all.
      .replace(/\s*[-\u2013]?\s*\d+(?::\d{2})?\s*['\u2032"]?\s*(?:j|jog|rest|rec|recovery|float|walk)\b.*$/i, "")
      .trim();
  }
  let progressTo: string | null = null;
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
      } else {
        const prog = parseProgression(pacePart);
        if (prog) {
          zone = prog.zone;
          zoneOff = prog.off;
          progressTo = prog.toward;
        }
      }
    }
  }

  // Ladder written as parallel lists — "600/400 @ 5k/3k". Reuses the compound
  // set machinery: zip the two lists into legs and let the adapter expand them.
  if (!segments && mainPart.includes("/")) {
    // With no "@", a spaced hyphen separates the two lists:
    // "5 sets of 1200/400 - 10k/3k pace 2' rec".
    let ladderMain = mainPart;
    let ladderPace = pacePart;
    if (!ladderPace) {
      const dash = mainPart.match(new RegExp(`^(.*?)\\s+[-\\u2013]\\s+((?:${ZONE_ALT})\\b.*)$`, "i"));
      if (dash) {
        ladderMain = dash[1];
        ladderPace = dash[2];
      }
    }
    const ladder = parseParallelLists(ladderMain, ladderPace);
    if (ladder) {
      segments = ladder;
      return compoundStep();
    }
  }

  const dur = repUnitDur ?? parseDuration(mainPart);
  if (!dur && timeSec == null && !segments) return null;

  // bare zone word without @ ("40 min easy")
  if (!zone && paceSec == null && timeSec == null) {
    // "6-7 x mile threshold" — `mile` already supplied the DISTANCE via the
    // bare-unit-word branch of parseDuration, so it must not also be read as
    // the pace zone. That misread assigned mile race pace to a threshold
    // session. When the duration came from a bare unit word (the only case
    // where mainPart holds no digits), that word is spoken for.
    const durFromBareUnit = !/\d/.test(mainPart);
    const words = mainPart.replace(/\b(?:wu|warm[\s-]?up|cd|cool[\s-]?down)\b/gi, " ").trim().split(/\s+/);
    for (const w of words) {
      if (durFromBareUnit && /^(?:miles?|mi|k|km)$/i.test(w)) continue;
      const z = matchZoneWord(w);
      if (z) {
        zone = z;
        break;
      }
      // "16 x 1k MP-3%" — an offset pace written with no "@" in front of it.
      // `matchZoneWord` anchors on the whole token, so the offset made the
      // zone invisible: the step lost the only pace the coach wrote and fell
      // back to easy. The `@` path has read this shape since day one; the
      // no-`@` path is the same sentence with one character missing.
      const zo = parseZoneWithOffset(w);
      if (zo) {
        zone = zo.zone;
        zoneOff = zo.off;
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

  const noteParts = [progressTo ? `progress to ${progressTo}` : null, parenNote].filter(Boolean);

  const step: ParsedStep = {
    note: noteParts.length ? noteParts.join(" \u00b7 ") : null,
    kind,
    reps,
    repsMax,
    sets,
    setRestSec,
    durationType: dur ? dur.durationType : "m",
    durationValue: dur ? dur.durationValue : 400,
    durationValueMax: dur && dur.durationValueMax ? dur.durationValueMax : null,
    paceMode: timeSec != null ? "time" : paceSec != null ? "pace" : "zone",
    // Deliberately NOT defaulted here. A missing pace used to become 5K for
    // rep steps, which invented a zone the coach never wrote (28 of 139
    // audited workouts). The adapter picks a conservative fallback AND
    // reports it so the coach is asked rather than silently overruled.
    zone,
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
// of an offset like MP+15.
//
// "Attached + is an offset, spaced + separates" was the old rule, and it was
// wrong in a way that destroyed alternations: coaches write "MP +5%" as often
// as "MP+5%", and the space made this split the leg into "MP" and "5%". The
// offset vanished, so "16 x K alternating MP-3% & MP +5%" came back as sixteen
// reps at plain MP — or at `easy`, once nothing resolved. The minus form never
// had the bug (it is not a separator), which is why only half of every
// alternation looked wrong.
//
// The real discriminator is what sits on either side, not the whitespace:
// a "+" is an offset when a PACE ZONE ends the text before it and a DIGIT
// follows immediately. That keeps every genuine separator intact —
// "4mi + 2x1mi" (no zone before) and "15' @ MP + 8-10x400" (space after the
// +, so the 8 is a new segment, not an offset).
const ZONE_BEFORE_PLUS = new RegExp(`(?:${ZONE_ALT})\\s*$`, "i");

function splitSegments(text: string): string[] {
  const out: string[] = [];
  let cur = "";
  let depth = 0;
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (ch === "(") depth++;
    if (ch === ")") depth = Math.max(0, depth - 1);
    const plusIsOffset =
      ch === "+" &&
      /\d/.test(text[i + 1] ?? "") &&
      ZONE_BEFORE_PLUS.test(cur.trimEnd());
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

// Sanity bounds. Anything outside these is a parse artifact, not a workout a
// human would write — a 2:30/mi "pace" (a rest interval misread as a target
// time) or a 155km "rep" (a descending pair misread as a range). We keep the
// step but strip the impossible field and say so.
const MIN_PLAUSIBLE_PACE_SEC_PER_MILE = 240;  // 4:00/mi — faster than the WR mile
const MAX_PLAUSIBLE_PACE_SEC_PER_MILE = 1200; // 20:00/mi — slower than walking
const MAX_PLAUSIBLE_STEP_MILES = 30;
// Expanding a compound set writes every leg out. Past this the editor becomes
// unusable and the coach is better off building it by hand.
const MAX_EXPANDED_STEPS = 60;

// Placeholders used while splitting a compound set's legs. Both tokens
// contain the "/" that also separates legs, so they are swapped out and
// back around the split.
const SHIELD = { w: "\u0001", bt: "\u0002" } as const;

/**
 * Why a step's pace could not be determined. A CLOSED set, matching
 * `UNRESOLVED_REASONS` in `supabase/functions/_shared/workout-step-validator.ts`
 * — the UI turns each one into a different question, so this cannot be free
 * text on either side of the wire.
 */
export type UnresolvedReason =
  | "no_pace_written"
  | "effort_word_not_a_zone"
  | "progression_without_paces"
  | "ambiguous";

export interface ParseWorkoutResult {
  /** Structured steps ready for the editor. */
  steps: WorkoutStep[];
  /** Fragments the parser couldn't turn into a step (surface to the coach). */
  unparsed: string[];
  /**
   * Steps that WERE built but rest on an assumption the coach never wrote —
   * a missing pace, a dropped set-rest, a value we had to discard as
   * impossible. These are the dangerous ones: they look complete in the
   * editor, so the UI must show them as needing confirmation before save.
   */
  warnings: string[];
  /**
   * Step id → why its pace is unknown. This is what lets the UI ask a real
   * question ("what pace for the 6 x 1km?") instead of printing a warning the
   * coach has to act on themselves.
   */
  unresolved: Record<string, UnresolvedReason>;
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
  const warnings: string[] = [];
  // Deduped: an expanded set repeats the same leg many times, and one warning
  // per rep would bury the message it is trying to send.
  const unresolvedLegs = new Set<string>();
  const unresolved: Record<string, UnresolvedReason> = {};

  for (const p of parsed) {
    // Compound sets — "6 sets of (1k @ HM - 1' rest - 600m @ 10k - 1' rest)".
    //
    // The flat model has no nested container, so these used to be dropped
    // outright. But `repeats` is only a COMPRESSION of the flat format, not
    // the only encoding of it: writing the legs out in order expresses the
    // same workout, and both the step editor and the iOS reader already
    // handle that shape (see `groupStepsIntoSections`, which documents the
    // flat "800m, 2min, 800m, 2min" format as supported). So expand.
    //
    // Each rep leg carries the rest that follows it as its own `recovery`,
    // which keeps the step count at sets × reps rather than sets × legs.
    if (p.segments && p.segments.length > 0) {
      const sets = Math.max(1, p.sets);
      const repLegs = p.segments.filter((sg) => sg.kind === "rep");
      const emitted = sets * repLegs.reduce((n, sg) => n + Math.max(1, sg.reps), 0);

      if (emitted > MAX_EXPANDED_STEPS) {
        const desc = p.segments
          .map((sg) => `${sg.durationValue}${sg.durationType === "m" ? "m" : sg.durationType} @ ${sg.zone ? paceShort(sg.zone) : "?"}`)
          .join(" / ");
        unsupported.push(`(${desc})`);
        warnings.push(`that set expands to ${emitted} steps — too many to build automatically, add it by hand`);
        continue;
      }

      for (let setIdx = 0; setIdx < sets; setIdx++) {
        p.segments.forEach((sg, legIdx) => {
          if (sg.kind !== "rep") return;
          // The rest immediately after this leg becomes its recovery.
          const next = p.segments![legIdx + 1];
          const followingRest = next && next.kind === "rest" ? next : null;
          // Nearest wins: a recovery written onto the leg, then a rest leg
          // sitting after it, then the SET'S recovery clause.
          //
          // That last fallback was missing, so "7 x (1k @ hm / 600 @ 10k)
          // w/1' rec" built fourteen legs with no rest at all and reported
          // itself clean — the 1' was parsed, stored on the step, and then
          // never read. Set-level rest is the most common way this coach
          // writes a compound set, so it was the most common thing to lose.
          const rest = sg.ownRecovery
            ? { ...sg.ownRecovery, kind: "rest" as const }
            : followingRest ??
              (p.recovery ? { ...p.recovery, kind: "rest" as const } : null);

          for (let r = 0; r < Math.max(1, sg.reps); r++) {
            const legStep: WorkoutStep = {
              id: nextId(),
              stepType: "active",
              durationType: mapDurationType(sg.durationType),
              durationValue: collapseValue(sg.durationType, sg.durationValue, null),
              paceZone: sg.zone ?? "easy",
              notes: "",
            };
            if (sg.paceSec != null) {
              legStep.exactPaceSecPerMile = Math.round(sg.paceSec);
            } else {
              const adj = offToAdjustment(sg.zoneOff);
              if (adj) legStep.paceAdjustment = adj;
              if (sg.zone == null) {
                unresolvedLegs.add(fmtDuration(sg.durationType, sg.durationValue));
                unresolved[legStep.id] = "no_pace_written";
              }
            }
            if (rest) {
              legStep.recovery = mapRecovery({
                durationType: rest.durationType,
                durationValue: rest.durationValue,
                style: rest.style ?? "jog",
              });
            }
            steps.push(legStep);
          }
        });
      }

      if (p.setRestSec != null) {
        warnings.push(
          `set rest (${Math.round(p.setRestSec / 60)}') couldn't be kept — the ${sets} ${sets === 1 ? "set is" : "sets are"} written out back to back`,
        );
      }
      continue;
    }

    // "sets of reps" flattens to total repeats — the rest BETWEEN sets has
    // nowhere to live in the flat model, so say it out loud rather than
    // quietly shipping a workout with no set break.
    const reps = collapseReps(p);
    const totalRepeats = Math.max(1, reps * Math.max(1, p.sets));
    if (p.sets > 1 && p.setRestSec != null) {
      warnings.push(
        `set rest (${Math.round(p.setRestSec / 60)}') couldn't be kept — ${p.sets} sets flattened to ${totalRepeats} reps`,
      );
    }

    // Target time ("800 in 2:30") → an exact per-mile pace.
    let exactPaceSecPerMile: number | undefined;
    if (p.paceMode === "time" && p.timeSec != null) {
      const miles = protoDurToMiles(p.durationType, collapseValue(p.durationType, p.durationValue, p.durationValueMax));
      if (miles > 0) exactPaceSecPerMile = Math.round(p.timeSec / miles);
    } else if (p.paceMode === "pace" && p.paceSec != null) {
      exactPaceSecPerMile = Math.round(p.paceSec);
    }
    if (
      exactPaceSecPerMile != null &&
      (exactPaceSecPerMile < MIN_PLAUSIBLE_PACE_SEC_PER_MILE || exactPaceSecPerMile > MAX_PLAUSIBLE_PACE_SEC_PER_MILE)
    ) {
      warnings.push(`ignored an implausible pace (${fmtPace(exactPaceSecPerMile)}) — check this step's pace by hand`);
      exactPaceSecPerMile = undefined;
    }

    const durationValue = collapseValue(p.durationType, p.durationValue, p.durationValueMax);
    const stepMiles = protoDurToMiles(p.durationType, durationValue);
    if (stepMiles > MAX_PLAUSIBLE_STEP_MILES) {
      warnings.push(`a ${Math.round(stepMiles)}mi step came out of "${text.trim().slice(0, 40)}" — almost certainly misread`);
    }

    // The pace fallback. `easy`, NOT the old `fiveK`: when we genuinely don't
    // know, erring slow is recoverable and erring fast is not. Either way the
    // coach is told, because a silent default is how a threshold session
    // became an easy run 18 times in the audited corpus.
    const zoneUnresolved = p.kind !== "rest" && p.zone == null && exactPaceSecPerMile == null;

    const step: WorkoutStep = {
      id: nextId(),
      stepType: KIND_TO_STEP_TYPE[p.kind],
      durationType: mapDurationType(p.durationType),
      durationValue,
      // paceZone is required by the type; for rest/exact-pace steps it's a
      // harmless filler that the renderer ignores in favor of stepType/exact.
      paceZone: p.zone ?? "easy",
      notes: p.note ?? "",
    };
    if (exactPaceSecPerMile != null) {
      step.exactPaceSecPerMile = exactPaceSecPerMile;
    } else {
      const adj = offToAdjustment(p.zoneOff);
      if (adj) step.paceAdjustment = adj;
    }
    if (totalRepeats > 1) step.repeats = totalRepeats;
    if (p.recovery) step.recovery = mapRecovery(p.recovery);
    // Recorded against the step id rather than described in prose, so the UI
    // can attach a question to this exact row.
    if (zoneUnresolved) unresolved[step.id] = "no_pace_written";

    steps.push(step);
  }

  return { steps, unparsed: unsupported, warnings, unresolved };
}

// ── Small formatters used in warning copy ────────────────

function fmtPace(secPerMile: number): string {
  const m = Math.floor(secPerMile / 60);
  const s = Math.round(secPerMile % 60);
  return `${m}:${String(s).padStart(2, "0")}/mi`;
}

function fmtDuration(t: ProtoDurationType, v: number): string {
  if (t === "time") return v >= 60 ? `${Math.round(v / 60)}'` : `${Math.round(v)}s`;
  if (t === "m") return `${Math.round(v)}m`;
  return `${v}${t}`;
}

// reps range ("4-6 x 800") → midpoint rep count.
function collapseReps(p: ParsedStep): number {
  if (p.repsMax && p.repsMax > p.reps) return Math.round((p.reps + p.repsMax) / 2);
  return p.reps || 1;
}
