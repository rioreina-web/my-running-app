/**
 * Builds `supabase/functions/_shared/session-library.json` from the coach's
 * own plans.
 *
 * Each session keeps its verbatim text and gains a measured shape — total
 * distance, quality distance, the zones it touches — by running it through
 * the shorthand parser. Sessions the parser cannot total keep `null` rather
 * than a guess, and `selectSessions` treats null as "unknown, still eligible"
 * so the less machine-legible sessions are not quietly dropped from every
 * suggestion.
 *
 * Run:  cd web && npx tsx tests/eval/build-session-library.ts
 *
 * Re-run whenever a new season is added to the source spreadsheets.
 */

import { readFileSync, writeFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

import { parseWorkoutText } from "../../src/components/coach/workout-nl-parser";
import { classifyKind, type DayRole, type LibrarySession } from "../../../supabase/functions/_shared/session-library";
import type { WorkoutStep } from "../../src/components/coach/workout-helpers";

const HERE = dirname(fileURLToPath(import.meta.url));
const SRC = process.argv[2] ?? "/private/tmp/claude-501/-Users-rioreina/0e29733f-5619-4c05-a2d8-2a2be334a19b/scratchpad/sessions-raw.json";
const OUT = join(HERE, "..", "..", "..", "supabase", "functions", "_shared", "session-library.json");

interface Raw { sheet: string; day: DayRole; text: string; lightVariant?: string }
const raw: Raw[] = JSON.parse(readFileSync(SRC, "utf8"));

const MILES_PER: Record<WorkoutStep["durationType"], number> = {
  distance_miles: 1,
  distance_km: 1 / 1.609344,
  distance_meters: 1 / 1609.344,
  time_seconds: 0, // unknown distance; contributes nothing to a total
};

const stepMiles = (s: WorkoutStep) =>
  s.durationValue * MILES_PER[s.durationType] * (s.repeats && s.repeats > 1 ? s.repeats : 1);

// Recovery distance counts toward the total but never toward quality.
const recoveryMiles = (s: WorkoutStep) => {
  if (!s.recovery) return 0;
  const per = s.recovery.durationValue * MILES_PER[s.recovery.durationType];
  return per * (s.repeats && s.repeats > 1 ? s.repeats : 1);
};

const QUALITY_ZONES = new Set(["mp", "hm", "threshold", "tenK", "fiveK", "threeK", "mile"]);

const library: LibrarySession[] = raw.map((r) => {
  const parsed = parseWorkoutText(r.text);
  const steps = parsed.steps;

  // A total is only honest when the parse is CLEAN. A partial parse still
  // sums to a plausible-looking number and that number is badly wrong:
  // "7mi alternations (1m at MP-10/1mi at MP+20)" parses to the two 1-mile
  // legs and totals 2.0, so a 12-mile cap surfaced a 7-mile session as small.
  // Wrong volume in an adjustment tool is worse than absent volume.
  const anyTimeBased = steps.some((s) => s.durationType === "time_seconds");
  const cleanParse =
    steps.length > 0 &&
    parsed.unparsed.length === 0 &&
    parsed.warnings.length === 0 &&
    Object.keys(parsed.unresolved).length === 0 &&
    !anyTimeBased;

  // When the parse is partial, fall back to a total the coach stated outright:
  // a leading "7mi ...", "10 mi ...", "8-12m ..." is the session's own volume.
  const headline = r.text.match(/^\s*(\d+(?:\.\d+)?)(?:\s*[-\u2013]\s*(\d+(?:\.\d+)?))?\s*(?:mi|miles?|m)\b/i);
  const headlineMiles = headline
    ? (headline[2] ? (+headline[1] + +headline[2]) / 2 : +headline[1])
    : null;

  const summed = steps.reduce((n, s) => n + stepMiles(s) + recoveryMiles(s), 0);

  // The decisive check. A parse can be "clean" — no warnings, no unparsed —
  // and still have missed the session's container: "7mi alternations (1m at
  // MP-10/1mi at MP+20)" yields the two 1-mile legs and sums to 2.0. When the
  // coach stated a total LARGER than we summed, the parse is incomplete and
  // neither figure is trustworthy, so report nothing. Where the leading
  // distance is just the first step ("4mi warmup + 4-6x2m @ MP-5"), the sum
  // exceeds it and is kept.
  const parseUndershotStatedTotal = headlineMiles != null && summed < headlineMiles;
  const total = cleanParse && !parseUndershotStatedTotal ? summed : null;

  const quality = cleanParse
    ? steps
        .filter((s) => s.stepType === "active" && s.paceZone && QUALITY_ZONES.has(s.paceZone))
        .reduce((n, s) => n + stepMiles(s), 0)
    : null;

  const zones = [...new Set(steps.map((s) => s.paceZone).filter(Boolean))] as string[];

  const entry: LibrarySession = {
    text: r.text,
    sheet: r.sheet,
    day: r.day,
    kind: classifyKind(r.text, r.day),
    totalMiles: total != null ? Math.round(total * 10) / 10 : null,
    qualityMiles: quality != null ? Math.round(quality * 10) / 10 : null,
    zones,
  };
  if (r.lightVariant) entry.lightVariant = r.lightVariant;
  return entry;
});

writeFileSync(OUT, JSON.stringify(library, null, 1));

const byKind = library.reduce<Record<string, number>>((a, s) => {
  a[s.kind] = (a[s.kind] ?? 0) + 1;
  return a;
}, {});
const measured = library.filter((s) => s.totalMiles != null).length;

console.log(`${library.length} sessions → ${OUT}`);
console.log(`  measurable total distance : ${measured}`);
console.log(`  with the coach's own light variant : ${library.filter((s) => s.lightVariant).length}`);
console.log(`  by kind:`);
for (const [k, v] of Object.entries(byKind).sort((a, b) => b[1] - a[1])) {
  console.log(`    ${String(v).padStart(3)}  ${k}`);
}
