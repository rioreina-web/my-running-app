/**
 * Parse Workout Shorthand
 *
 * Parses coach-language workout descriptions into structured PlannedWorkout steps.
 * No AI call — pure deterministic grammar parsing. Fast (<10ms).
 *
 * Supported vocabulary:
 *   Distances: 400m, 800m, 1200m, 1600m, 1mi, 2mi, 3mi, 5K, 10K, half, marathon
 *   Paces: @ easy, @ MP, @ marathon pace, @ half pace, @ 10K pace, @ 5K pace, @ mile pace
 *   Range paces: @ 5K-10K pace, @ marathon-to-half pace
 *   Repeats: Nx for simple, 3x(4x400 @ mile pace / 200 jog) for nested
 *   Recoveries: / 60s rest, / 400 jog, / 2min walk, / 200m jog
 *   Segments: wu, cd, warmup, cooldown
 *   Progressions: progressive, descending, cut-down, alternating
 *
 * Example inputs:
 *   "2mi wu, 6x800 @ 5K pace / 90s jog, 2mi cd"
 *   "3x1600 @ 10K pace / 400 jog"
 *   "20min @ marathon pace"
 *   "Progressive 10mi: 6mi easy, 2mi @ marathon pace, 2mi @ half pace"
 *   "Alternating 8mi: 1mi @ 10K pace / 1mi easy"
 *   "3x(3x400 @ mile pace / 200 jog) / 800 jog between sets"
 *
 * Returns { steps[], totalDistanceMiles, estimatedDurationMinutes, errors[] }
 */

import { corsHeaders } from "../_shared/cors.ts";

// ── Types ──────────────────────────────────────────────────────

export interface ParsedStep {
  stepType: "warmup" | "active" | "recovery" | "cooldown" | "rest";
  durationType: "distance_miles" | "distance_meters" | "time_seconds";
  durationValue: number;
  paceReference: string | null;     // "easy", "marathon", "half", "10k", "5k", "mile"
  paceRangeHigh: string | null;     // for range paces like "5k-10k"
  pacePercentage: number | null;    // approximate % of race pace (for legacy compat)
  notes: string | null;
  order: number;
  repCount: number | null;          // null = single, N = repeat count
  recoveryType: string | null;      // "jog", "rest", "walk"
}

interface ParseResult {
  steps: ParsedStep[];
  totalDistanceMiles: number;
  estimatedDurationMinutes: number | null;
  workoutType: string;
  name: string;
  description: string;
  errors: string[];
  raw: string;
}

// ── Distance Parsing ───────────────────────────────────────────

const DISTANCE_PATTERNS: Array<{ pattern: RegExp; toMiles: (match: RegExpMatchArray) => number; toMeters: (match: RegExpMatchArray) => number; label: (match: RegExpMatchArray) => string }> = [
  { pattern: /^(\d+(?:\.\d+)?)\s*mi(?:les?)?$/i, toMiles: m => parseFloat(m[1]), toMeters: m => parseFloat(m[1]) * 1609.34, label: m => `${m[1]}mi` },
  { pattern: /^(\d+(?:\.\d+)?)\s*(?:k|km)$/i, toMiles: m => parseFloat(m[1]) / 1.60934, toMeters: m => parseFloat(m[1]) * 1000, label: m => `${m[1]}km` },
  { pattern: /^(\d+)\s*m$/i, toMiles: m => parseInt(m[1]) / 1609.34, toMeters: m => parseInt(m[1]), label: m => `${m[1]}m` },
  { pattern: /^half$/i, toMiles: () => 13.109, toMeters: () => 21097, label: () => "half marathon" },
  { pattern: /^marathon$/i, toMiles: () => 26.219, toMeters: () => 42195, label: () => "marathon" },
  { pattern: /^(\d+)\s*K$/i, toMiles: m => parseInt(m[1]) / 1.60934, toMeters: m => parseInt(m[1]) * 1000, label: m => `${m[1]}K` },
];

function parseDistance(token: string): { miles: number; meters: number; label: string } | null {
  const cleaned = token.trim();
  for (const { pattern, toMiles, toMeters, label } of DISTANCE_PATTERNS) {
    const match = cleaned.match(pattern);
    if (match) return { miles: toMiles(match), meters: toMeters(match), label: label(match) };
  }
  return null;
}

// ── Duration Parsing ───────────────────────────────────────────

function parseDuration(token: string): { seconds: number; label: string } | null {
  const cleaned = token.trim();
  // "90s", "90sec", "90 seconds"
  let m = cleaned.match(/^(\d+)\s*(?:s|sec(?:onds?)?)$/i);
  if (m) return { seconds: parseInt(m[1]), label: `${m[1]}s` };
  // "2min", "2 min", "2 minutes"
  m = cleaned.match(/^(\d+)\s*(?:min(?:utes?)?)$/i);
  if (m) return { seconds: parseInt(m[1]) * 60, label: `${m[1]}min` };
  // "1:30" (mm:ss)
  m = cleaned.match(/^(\d+):(\d{2})$/);
  if (m) return { seconds: parseInt(m[1]) * 60 + parseInt(m[2]), label: cleaned };
  return null;
}

// ── Pace Reference Parsing ─────────────────────────────────────

const PACE_MAP: Record<string, { ref: string; pct: number }> = {
  "easy": { ref: "easy", pct: 70 },
  "recovery": { ref: "easy", pct: 65 },
  "moderate": { ref: "moderate", pct: 80 },
  "steady": { ref: "steady", pct: 85 },
  "mp": { ref: "marathon", pct: 100 },
  "marathon pace": { ref: "marathon", pct: 100 },
  "marathon": { ref: "marathon", pct: 100 },
  "hmp": { ref: "half", pct: 103 },
  "half pace": { ref: "half", pct: 103 },
  "half marathon pace": { ref: "half", pct: 103 },
  "half": { ref: "half", pct: 103 },
  "10k pace": { ref: "10k", pct: 107 },
  "10k": { ref: "10k", pct: 107 },
  "5k pace": { ref: "5k", pct: 112 },
  "5k": { ref: "5k", pct: 112 },
  "mile pace": { ref: "mile", pct: 118 },
  "mile": { ref: "mile", pct: 118 },
  "threshold": { ref: "half", pct: 103 },
  "tempo": { ref: "half", pct: 100 },
  "lt": { ref: "half", pct: 103 },
  "vo2max": { ref: "5k", pct: 112 },
  "vo2": { ref: "5k", pct: 112 },
};

function parsePaceRef(token: string): { ref: string; rangeHigh: string | null; pct: number } | null {
  const cleaned = token.trim().toLowerCase().replace(/\s+/g, " ");

  // Range paces: "5k-10k pace", "marathon-to-half pace"
  const rangeMatch = cleaned.match(/^(\w+)\s*(?:-|to)\s*(\w+)\s*(?:pace)?$/);
  if (rangeMatch) {
    const lo = PACE_MAP[rangeMatch[1]] || PACE_MAP[rangeMatch[1] + " pace"];
    const hi = PACE_MAP[rangeMatch[2]] || PACE_MAP[rangeMatch[2] + " pace"];
    if (lo && hi) {
      return { ref: lo.ref, rangeHigh: hi.ref, pct: Math.round((lo.pct + hi.pct) / 2) };
    }
  }

  // Direct lookup
  const direct = PACE_MAP[cleaned] || PACE_MAP[cleaned.replace(/\s*pace$/, "")];
  if (direct) return { ref: direct.ref, rangeHigh: null, pct: direct.pct };

  return null;
}

// ── Segment Parsing ────────────────────────────────────────────

interface RawSegment {
  type: "work" | "recovery" | "warmup" | "cooldown";
  distance: { miles: number; meters: number; label: string } | null;
  duration: { seconds: number; label: string } | null;
  pace: { ref: string; rangeHigh: string | null; pct: number } | null;
  reps: number | null;
  recoveryType: string | null; // "jog", "rest", "walk"
  raw: string;
}

function classifySegmentType(text: string): "warmup" | "cooldown" | "work" {
  const lower = text.toLowerCase().trim();
  if (/^(?:wu|warm\s*up|warmup)$/i.test(lower)) return "warmup";
  if (/^(?:cd|cool\s*down|cooldown)$/i.test(lower)) return "cooldown";
  return "work";
}

function parseSegment(text: string): RawSegment {
  const trimmed = text.trim();
  const seg: RawSegment = {
    type: "work",
    distance: null,
    duration: null,
    pace: null,
    reps: null,
    recoveryType: null,
    raw: trimmed,
  };

  // Check for warmup/cooldown markers
  const typeMatch = trimmed.match(/^(wu|cd|warmup|cooldown|warm\s*up|cool\s*down)\b/i);
  if (typeMatch) {
    seg.type = classifySegmentType(typeMatch[1]);
  }

  // Check for reps: "6x800", "3x1600"
  const repMatch = trimmed.match(/^(\d+)\s*x\s*/i);
  if (repMatch) {
    seg.reps = parseInt(repMatch[1]);
  }

  // Extract pace: "@ 5K pace", "@ easy"
  const paceMatch = trimmed.match(/@\s*(.+?)(?:$|\s*\/)/);
  if (paceMatch) {
    seg.pace = parsePaceRef(paceMatch[1]);
  } else {
    // Check for implicit pace: "2mi easy", "800 @ 5K pace"
    const implicitPace = trimmed.match(/\b(easy|recovery|moderate|steady|tempo|threshold)\b/i);
    if (implicitPace) {
      seg.pace = parsePaceRef(implicitPace[1]);
      if (seg.type === "work" && implicitPace[1].toLowerCase() === "easy") {
        // "2mi easy" is not warmup unless explicitly marked
      }
    }
  }

  // Extract distance/duration
  // Strip reps prefix and pace suffix to find the quantity
  let quantityStr = trimmed
    .replace(/^\d+\s*x\s*/i, "")           // strip reps
    .replace(/@\s*.+$/, "")                 // strip pace
    .replace(/^(?:wu|cd|warmup|cooldown|warm\s*up|cool\s*down)\s*/i, "")  // strip type markers
    .replace(/\b(?:easy|recovery|moderate|steady|tempo|threshold)\b/i, "") // strip implicit pace
    .trim();

  // Try distance first, then duration
  const dist = parseDistance(quantityStr);
  if (dist) {
    seg.distance = dist;
  } else {
    const dur = parseDuration(quantityStr);
    if (dur) seg.duration = dur;
  }

  return seg;
}

function parseRecovery(text: string): RawSegment {
  const trimmed = text.trim();
  const seg: RawSegment = {
    type: "recovery",
    distance: null,
    duration: null,
    pace: null,
    reps: null,
    recoveryType: "rest",
    raw: trimmed,
  };

  // "90s rest", "90s jog", "400 jog", "2min walk", "200m jog"
  const recTypeMatch = trimmed.match(/\b(jog|rest|walk|easy|standing)\b/i);
  if (recTypeMatch) {
    seg.recoveryType = recTypeMatch[1].toLowerCase();
    if (seg.recoveryType === "standing") seg.recoveryType = "rest";
    if (seg.recoveryType === "easy") seg.recoveryType = "jog";
  }

  // Extract the quantity
  const quantityStr = trimmed.replace(/\b(?:jog|rest|walk|easy|standing|between\s*sets?)\b/gi, "").trim();
  const dist = parseDistance(quantityStr);
  if (dist) {
    seg.distance = dist;
  } else {
    const dur = parseDuration(quantityStr);
    if (dur) seg.duration = dur;
  }

  return seg;
}

// ── Main Parser ────────────────────────────────────────────────

function parseShorthand(input: string): ParseResult {
  const errors: string[] = [];
  const steps: ParsedStep[] = [];
  let order = 0;

  // Normalize input
  let text = input.trim();

  // Detect progression/alternating prefix
  let workoutModifier: string | null = null;
  const modifierMatch = text.match(/^(progressive|descending|cut-?down|alternating)\s+/i);
  if (modifierMatch) {
    workoutModifier = modifierMatch[1].toLowerCase();
    text = text.slice(modifierMatch[0].length);
  }

  // Split on commas and "then" (top-level segments)
  // But preserve parenthesized groups
  const topSegments = splitTopLevel(text);

  for (const segStr of topSegments) {
    const trimmed = segStr.trim();
    if (!trimmed) continue;

    // Check for set notation: "3x(4x400 @ mile pace / 200 jog)"
    const setMatch = trimmed.match(/^(\d+)\s*x\s*\((.+)\)(?:\s*\/\s*(.+))?$/i);
    if (setMatch) {
      const setCount = parseInt(setMatch[1]);
      const innerContent = setMatch[2];
      const betweenSetsRecovery = setMatch[3];

      for (let s = 0; s < setCount; s++) {
        // Parse inner content
        const innerParts = innerContent.split(/\s*\/\s*/);
        const workPart = parseSegment(innerParts[0]);
        const recPart = innerParts[1] ? parseRecovery(innerParts[1]) : null;

        const innerReps = workPart.reps || 1;
        for (let r = 0; r < innerReps; r++) {
          steps.push(buildStep(workPart, order++, 1));
          if (recPart && r < innerReps - 1) {
            steps.push(buildRecoveryStep(recPart, order++));
          }
        }

        // Between-sets recovery
        if (betweenSetsRecovery && s < setCount - 1) {
          const betweenRec = parseRecovery(betweenSetsRecovery);
          steps.push(buildRecoveryStep(betweenRec, order++));
        }
      }
      continue;
    }

    // Check for work/recovery pair: "6x800 @ 5K pace / 90s jog"
    const parts = trimmed.split(/\s*\/\s*/);
    const workSeg = parseSegment(parts[0]);
    const recSeg = parts[1] ? parseRecovery(parts[1]) : null;

    if (workSeg.type === "warmup" || workSeg.type === "cooldown") {
      steps.push(buildStep(workSeg, order++, 1));
    } else if (workSeg.reps && workSeg.reps > 1) {
      // Repeated segment
      for (let r = 0; r < workSeg.reps; r++) {
        steps.push(buildStep(workSeg, order++, 1));
        if (recSeg && r < workSeg.reps - 1) {
          steps.push(buildRecoveryStep(recSeg, order++));
        }
      }
    } else {
      steps.push(buildStep(workSeg, order++, workSeg.reps));
      if (recSeg) {
        steps.push(buildRecoveryStep(recSeg, order++));
      }
    }

    // Warn on unparseable quantities
    if (!workSeg.distance && !workSeg.duration && workSeg.type === "work") {
      errors.push(`Could not parse distance or duration from "${parts[0].trim()}"`);
    }
  }

  // Add progression notes if modifier present
  if (workoutModifier && steps.length > 0) {
    const workSteps = steps.filter(s => s.stepType === "active");
    if (workoutModifier === "progressive" || workoutModifier === "descending" || workoutModifier === "cut-down") {
      workSteps.forEach((s, i) => {
        s.notes = (s.notes || "") + ` [${workoutModifier} ${i + 1}/${workSteps.length}]`;
      });
    }
  }

  // Compute totals
  const totalMiles = steps.reduce((sum, s) => {
    if (s.durationType === "distance_miles") return sum + s.durationValue;
    if (s.durationType === "distance_meters") return sum + s.durationValue / 1609.34;
    return sum;
  }, 0);

  // Determine workout type
  const activeSteps = steps.filter(s => s.stepType === "active");
  const hasReps = activeSteps.some(s => (s.repCount || 0) > 1) || activeSteps.length > 3;
  const primaryPace = activeSteps[0]?.paceReference;
  let workoutType = "easy";
  if (hasReps && primaryPace && ["5k", "mile", "10k"].includes(primaryPace)) workoutType = "intervals";
  else if (primaryPace === "marathon" || primaryPace === "half") workoutType = "tempo";
  else if (totalMiles >= 10) workoutType = "long_run";
  else if (workoutModifier === "progressive") workoutType = "progression";

  // Build name
  const name = buildWorkoutName(steps, workoutModifier);

  return {
    steps,
    totalDistanceMiles: Math.round(totalMiles * 100) / 100,
    estimatedDurationMinutes: null, // would need pace context to compute
    workoutType,
    name,
    description: input.trim(),
    errors,
    raw: input,
  };
}

// ── Helpers ────────────────────────────────────────────────────

function splitTopLevel(text: string): string[] {
  // Split on commas, but not inside parentheses
  const result: string[] = [];
  let depth = 0;
  let current = "";

  // Also split on ": " for progressive-style descriptions
  // "Progressive 10mi: 6mi easy, 2mi @ MP" → the part after ":" is the segments
  const colonIdx = text.indexOf(":");
  if (colonIdx > 0 && colonIdx < 30) {
    // Check if before the colon is a distance (like "Progressive 10mi:")
    const beforeColon = text.slice(0, colonIdx).trim();
    const afterColon = text.slice(colonIdx + 1).trim();
    if (parseDistance(beforeColon.split(/\s+/).pop() || "")) {
      text = afterColon;
    }
  }

  for (const ch of text) {
    if (ch === "(") depth++;
    if (ch === ")") depth--;
    if (ch === "," && depth === 0) {
      result.push(current.trim());
      current = "";
    } else {
      current += ch;
    }
  }
  if (current.trim()) result.push(current.trim());
  return result;
}

function buildStep(seg: RawSegment, order: number, repCount: number | null): ParsedStep {
  const step: ParsedStep = {
    stepType: seg.type === "warmup" ? "warmup" : seg.type === "cooldown" ? "cooldown" : "active",
    durationType: "distance_miles",
    durationValue: 0,
    paceReference: seg.pace?.ref ?? (seg.type === "warmup" || seg.type === "cooldown" ? "easy" : null),
    paceRangeHigh: seg.pace?.rangeHigh ?? null,
    pacePercentage: seg.pace?.pct ?? (seg.type === "warmup" || seg.type === "cooldown" ? 70 : null),
    notes: null,
    order,
    repCount: repCount && repCount > 1 ? repCount : null,
    recoveryType: null,
  };

  if (seg.distance) {
    step.durationType = seg.distance.meters < 1600 ? "distance_meters" : "distance_miles";
    step.durationValue = step.durationType === "distance_meters" ? seg.distance.meters : seg.distance.miles;
    step.notes = seg.distance.label;
  } else if (seg.duration) {
    step.durationType = "time_seconds";
    step.durationValue = seg.duration.seconds;
    step.notes = seg.duration.label;
  }

  return step;
}

function buildRecoveryStep(seg: RawSegment, order: number): ParsedStep {
  const step: ParsedStep = {
    stepType: "recovery",
    durationType: "distance_miles",
    durationValue: 0,
    paceReference: seg.recoveryType === "jog" ? "easy" : null,
    paceRangeHigh: null,
    pacePercentage: seg.recoveryType === "jog" ? 70 : null,
    notes: seg.recoveryType || "rest",
    order,
    repCount: null,
    recoveryType: seg.recoveryType,
  };

  if (seg.distance) {
    step.durationType = seg.distance.meters < 1600 ? "distance_meters" : "distance_miles";
    step.durationValue = step.durationType === "distance_meters" ? seg.distance.meters : seg.distance.miles;
  } else if (seg.duration) {
    step.durationType = "time_seconds";
    step.durationValue = seg.duration.seconds;
  }

  return step;
}

function buildWorkoutName(steps: ParsedStep[], modifier: string | null): string {
  const activeSteps = steps.filter(s => s.stepType === "active");
  if (activeSteps.length === 0) return "Workout";

  const prefix = modifier ? modifier.charAt(0).toUpperCase() + modifier.slice(1) + " " : "";

  // Simple repeat pattern: all active steps are the same
  if (activeSteps.length > 1 && activeSteps.every(s =>
    s.durationValue === activeSteps[0].durationValue &&
    s.durationType === activeSteps[0].durationType &&
    s.paceReference === activeSteps[0].paceReference
  )) {
    const distLabel = activeSteps[0].notes || `${activeSteps[0].durationValue}`;
    const paceLabel = activeSteps[0].paceReference ? ` @ ${activeSteps[0].paceReference} pace` : "";
    return `${prefix}${activeSteps.length}x${distLabel}${paceLabel}`;
  }

  // Mixed workout
  if (activeSteps.length <= 3) {
    return prefix + activeSteps.map(s => {
      const d = s.notes || `${s.durationValue}`;
      const p = s.paceReference ? ` ${s.paceReference}` : "";
      return `${d}${p}`;
    }).join(" + ");
  }

  return `${prefix}Workout (${activeSteps.length} segments)`;
}

// ── HTTP Handler ───────────────────────────────────────────────

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const body = await req.json();
    const { input, paceZones } = body;

    if (!input || typeof input !== "string") {
      return new Response(
        JSON.stringify({ error: "input string is required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const result = parseShorthand(input);

    // If pace zones provided, compute estimated duration
    if (paceZones && typeof paceZones === "object") {
      let totalSeconds = 0;
      let hasAllPaces = true;

      for (const step of result.steps) {
        const paceRef = step.paceReference;
        const paceSeconds = paceRef ? (paceZones[paceRef] as number) : null;

        if (step.durationType === "time_seconds") {
          totalSeconds += step.durationValue;
        } else if (paceSeconds) {
          let miles = step.durationValue;
          if (step.durationType === "distance_meters") miles = step.durationValue / 1609.34;
          totalSeconds += miles * paceSeconds;
        } else if (step.durationType === "distance_miles" || step.durationType === "distance_meters") {
          // Use easy pace as fallback
          const easyPace = (paceZones.easy as number) || 540; // 9:00/mi default
          let miles = step.durationValue;
          if (step.durationType === "distance_meters") miles = step.durationValue / 1609.34;
          totalSeconds += miles * easyPace;
        } else {
          hasAllPaces = false;
        }
      }

      if (totalSeconds > 0) {
        result.estimatedDurationMinutes = Math.round(totalSeconds / 60);
      }
    }

    return new Response(
      JSON.stringify(result),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (error) {
    console.error("[parse-workout-shorthand] Error:", error);
    return new Response(
      JSON.stringify({ error: String(error) }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
