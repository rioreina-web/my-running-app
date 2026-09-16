/**
 * Deterministic validation for parsed workout steps.
 *
 * Sits between ANY parser — the regex grammar, the LLM, a future one — and the
 * step editor. The parser proposes; this decides what is allowed through.
 *
 * The bounds are not arbitrary. Each one is a real defect found by running 137
 * of this coach's workouts through the regex parser in August 2026:
 *
 *   - a rest interval ("1600 @ 10k - 2:30 rest") read as a target pace,
 *     producing a 2:30/mile step — faster than the world record mile.
 *   - "1200-300 - 10k/mile" read as a descending range and collapsed into a
 *     single 155 km rep.
 *   - a missing pace defaulted to 5K, silently rewriting 28 workouts.
 *
 * A model can make all three mistakes too, and unlike the regex it will make
 * them non-deterministically, so they will not reproduce when you go looking.
 * That is precisely why this layer is pure, synchronous and model-free.
 *
 * Nothing here throws. Bad fields are stripped and reported, because a step
 * the coach is asked to fix beats a request that fails outright.
 */

export type PaceZone =
  | "recovery" | "easy" | "longRun" | "moderate" | "steady"
  | "mp" | "hm" | "threshold" | "tenK" | "fiveK" | "threeK" | "mile";

export const PACE_ZONE_SET: ReadonlySet<string> = new Set<PaceZone>([
  "recovery", "easy", "longRun", "moderate", "steady",
  "mp", "hm", "threshold", "tenK", "fiveK", "threeK", "mile",
]);

export type DurationType =
  | "distance_miles" | "distance_km" | "distance_meters" | "time_seconds";

export const DURATION_TYPE_SET: ReadonlySet<string> = new Set<DurationType>([
  "distance_miles", "distance_km", "distance_meters", "time_seconds",
]);

export type StepType = "warmup" | "active" | "recovery" | "rest" | "cooldown";

const STEP_TYPE_SET: ReadonlySet<string> = new Set<StepType>([
  "warmup", "active", "recovery", "rest", "cooldown",
]);

export interface ValidatedStep {
  stepType: StepType;
  durationType: DurationType;
  durationValue: number;
  /** null is legal and meaningful: the coach wrote no pace. Never defaulted. */
  paceZone: PaceZone | null;
  paceAdjustment?: { type: "seconds_per_mile" | "percent"; value: number };
  exactPaceSecPerMile?: number;
  repeats?: number;
  recovery?: {
    durationType: DurationType;
    durationValue: number;
    isJog: boolean;
  };
  note: string;
  /** Why the pace is null, in the coach's terms. Rendered as-is. */
  unresolved: string | null;
  /**
   * The same fact as a closed code. The client turns this into a question with
   * tappable answers, which prose cannot support.
   */
  unresolvedReasonCode: UnresolvedReasonCode | null;
}

export type UnresolvedReasonCode =
  | "no_pace_written"
  | "effort_word_not_a_zone"
  | "progression_without_paces"
  | "ambiguous";

export interface ValidationResult {
  steps: ValidatedStep[];
  /** Things the coach must look at before saving. */
  warnings: string[];
  /** Source text no parser could place. */
  unparsed: string[];
}

// ── Bounds ───────────────────────────────────────────────

export const MIN_PACE_SEC_PER_MILE = 240;   // 4:00/mi, inside the mile WR
export const MAX_PACE_SEC_PER_MILE = 1200;  // 20:00/mi, slower than walking
export const MAX_STEP_MILES = 30;           // longer than a marathon rep
export const MAX_STEPS = 80;
export const MAX_REPEATS = 60;

const MILES_PER: Record<DurationType, number> = {
  distance_miles: 1,
  distance_km: 1 / 1.609344,
  distance_meters: 1 / 1609.344,
  time_seconds: 0,
};

export function stepMiles(durationType: DurationType, durationValue: number): number {
  return durationValue * MILES_PER[durationType];
}

const MIN_DURATION: Record<DurationType, number> = {
  distance_miles: 0.05,
  distance_km: 0.05,
  distance_meters: 20,
  time_seconds: 5,
};

/** Anything the model or grammar might hand us, before we trust any of it. */
export interface RawStep {
  stepType?: unknown;
  durationType?: unknown;
  durationValue?: unknown;
  paceZone?: unknown;
  paceAdjustmentType?: unknown;
  paceAdjustmentValue?: unknown;
  exactPaceSecPerMile?: unknown;
  repeats?: unknown;
  recoveryDurationType?: unknown;
  recoveryDurationValue?: unknown;
  recoveryIsJog?: unknown;
  note?: unknown;
  unresolved?: unknown;
}

/**
 * The closed set of reasons a pace can be missing, and how each reads to a
 * coach. Closed rather than free text because free text is where a model
 * loops; see the schema note in `workout-shorthand-llm.ts`.
 */
const UNRESOLVED_REASONS: Record<UnresolvedReasonCode, string> = {
  no_pace_written: "no pace written for this step",
  effort_word_not_a_zone: "the text names an effort, not a pace zone",
  progression_without_paces: "a progression with no paces given",
  ambiguous: "the pace here is ambiguous",
};

const num = (v: unknown): number | null =>
  typeof v === "number" && Number.isFinite(v) ? v : null;

const str = (v: unknown): string | null =>
  typeof v === "string" && v.trim() ? v.trim() : null;

/**
 * Validate a proposed step list. Steps that cannot be repaired are dropped and
 * named; steps that can be are repaired and flagged.
 */
export function validateSteps(
  raw: unknown,
  opts: { source: string; unparsed?: string[] } = { source: "parser" },
): ValidationResult {
  const warnings: string[] = [];
  const unparsed: string[] = [...(opts.unparsed ?? [])];
  const steps: ValidatedStep[] = [];

  if (!Array.isArray(raw)) {
    return { steps: [], warnings: [`${opts.source} returned no steps`], unparsed };
  }

  if (raw.length > MAX_STEPS) {
    warnings.push(`only the first ${MAX_STEPS} steps were kept (${raw.length} proposed)`);
  }

  for (const [i, item] of raw.slice(0, MAX_STEPS).entries()) {
    const r = (item ?? {}) as RawStep;
    const where = `step ${i + 1}`;

    const durationType = str(r.durationType);
    const durationValue = num(r.durationValue);
    if (!durationType || !DURATION_TYPE_SET.has(durationType) || durationValue == null) {
      warnings.push(`${where} had no usable duration and was dropped`);
      continue;
    }
    const dt = durationType as DurationType;

    if (durationValue < MIN_DURATION[dt]) {
      warnings.push(`${where} was too short to be real (${durationValue}) and was dropped`);
      continue;
    }

    const miles = stepMiles(dt, durationValue);
    if (miles > MAX_STEP_MILES) {
      warnings.push(`${where} came out as ${Math.round(miles)}mi — almost certainly misread, dropped`);
      continue;
    }

    const stepTypeRaw = str(r.stepType);
    const stepType = (stepTypeRaw && STEP_TYPE_SET.has(stepTypeRaw) ? stepTypeRaw : "active") as StepType;

    // The pace. null is a legitimate answer and must survive untouched.
    const zoneRaw = str(r.paceZone);
    let paceZone: PaceZone | null = null;
    if (zoneRaw) {
      if (PACE_ZONE_SET.has(zoneRaw)) {
        paceZone = zoneRaw as PaceZone;
      } else {
        warnings.push(`${where} named an unknown pace "${zoneRaw}" — set it by hand`);
      }
    }

    // A parser that names a pace AND says the pace is unknown is contradicting
    // itself, and the admission is the reliable half — observed in the wild,
    // the model set paceZone "threshold" while stating no pace was specified.
    //
    // But only three of the four reasons mean "I don't know the pace".
    // `progression_without_paces` is different: "MP > 10k" genuinely HAS a
    // starting zone, and the marker only says the intermediate reps are
    // unspecified. Clearing that one threw away correct paces and cost 24
    // workouts their clean parse.
    const reasonKey = str(r.unresolved);
    if (paceZone != null && reasonKey && reasonKey !== "progression_without_paces") {
      warnings.push(`${where} named ${paceZone} while flagging the pace as unknown — cleared`);
      paceZone = null;
    }

    const step: ValidatedStep = {
      stepType,
      durationType: dt,
      durationValue: dt === "distance_meters" || dt === "time_seconds"
        ? Math.round(durationValue)
        : Math.round(durationValue * 100) / 100,
      paceZone,
      note: str(r.note) ?? "",
      unresolved: null,
      unresolvedReasonCode: null,
    };

    const exact = num(r.exactPaceSecPerMile);
    if (exact != null) {
      if (exact < MIN_PACE_SEC_PER_MILE || exact > MAX_PACE_SEC_PER_MILE) {
        warnings.push(`${where} claimed an impossible pace (${fmtPace(exact)}) — ignored`);
      } else {
        step.exactPaceSecPerMile = Math.round(exact);
      }
    }

    const adjType = str(r.paceAdjustmentType);
    const adjValue = num(r.paceAdjustmentValue);
    if (adjType && adjValue != null && adjValue !== 0) {
      if (adjType === "seconds_per_mile" && Math.abs(adjValue) <= 180) {
        step.paceAdjustment = { type: "seconds_per_mile", value: Math.round(adjValue) };
      } else if (adjType === "percent" && Math.abs(adjValue) <= 25) {
        step.paceAdjustment = { type: "percent", value: adjValue };
      } else {
        warnings.push(`${where} had an out-of-range pace offset (${adjValue}) — ignored`);
      }
    }

    const repeats = num(r.repeats);
    if (repeats != null && repeats > 1) {
      step.repeats = Math.min(MAX_REPEATS, Math.round(repeats));
      if (repeats > MAX_REPEATS) warnings.push(`${where} capped at ${MAX_REPEATS} reps (${Math.round(repeats)} proposed)`);
    }

    const recType = str(r.recoveryDurationType);
    const recValue = num(r.recoveryDurationValue);
    if (recType && DURATION_TYPE_SET.has(recType) && recValue != null && recValue > 0) {
      const rdt = recType as DurationType;
      if (stepMiles(rdt, recValue) <= MAX_STEP_MILES) {
        step.recovery = {
          durationType: rdt,
          durationValue: rdt === "distance_meters" || rdt === "time_seconds"
            ? Math.round(recValue)
            : Math.round(recValue * 100) / 100,
          isJog: r.recoveryIsJog !== false,
        };
      } else {
        warnings.push(`${where} had an implausible recovery and it was ignored`);
      }
    }

    // The rule the whole audit was built around: a pace-less active step is
    // allowed, but it is never silent.
    const needsPace = stepType !== "rest" && step.paceZone == null && step.exactPaceSecPerMile == null;
    if (needsPace) {
      const code: UnresolvedReasonCode =
        reasonKey && reasonKey in UNRESOLVED_REASONS
          ? (reasonKey as UnresolvedReasonCode)
          : "no_pace_written";
      step.unresolvedReasonCode = code;
      step.unresolved = UNRESOLVED_REASONS[code];
      warnings.push(`${where} (${describe(step)}) — ${step.unresolved}; set it before saving`);
    }

    steps.push(step);
  }

  if (steps.length === 0 && unparsed.length === 0) {
    warnings.push(`${opts.source} could not build any steps from this text`);
  }

  return { steps, warnings, unparsed };
}

function describe(s: ValidatedStep): string {
  const unit = s.durationType === "distance_meters" ? "m"
    : s.durationType === "distance_km" ? "km"
    : s.durationType === "distance_miles" ? "mi" : "s";
  const n = s.durationType === "time_seconds" && s.durationValue >= 60
    ? `${Math.round(s.durationValue / 60)}'`
    : `${s.durationValue}${unit}`;
  return s.repeats && s.repeats > 1 ? `${s.repeats} x ${n}` : n;
}

function fmtPace(secPerMile: number): string {
  const m = Math.floor(secPerMile / 60);
  const s = Math.round(secPerMile % 60);
  return `${m}:${String(s).padStart(2, "0")}/mi`;
}

// ── Did the answer keep what the coach wrote? ───────────────

/**
 * Pace offsets present in the source that no emitted step is carrying.
 *
 * The model is the reason this exists on the server side. Asked for
 * "16 x K alternating MP-3% & MP+5%" — a string written verbatim as a worked
 * example in its own prompt, with paceAdjustmentType/paceAdjustmentValue in a
 * constrained response schema — gemini-3.5-flash-lite returned sixteen steps at
 * plain MP on two runs out of three, and gemini-3.5-flash did the same. It
 * reports `errors: []` and no unresolved reason while doing it, so the caller
 * sees sixteen tidy steps and a session the coach never prescribed.
 *
 * Neither a better prompt nor a bigger model fixed it (both measured
 * 2026-08-28). So verify the output against the input instead of trusting
 * either layer's self-report: an offset written in the text that reached no
 * step means the answer is wrong however confident it looks.
 *
 * Mirrors `uncoveredPaceOffsets` in web/src/components/coach/workout-nl-parser.ts.
 * Two implementations because the web grammar runs in the browser and this runs
 * in Deno; they must stay in step.
 */
const ZONE_WORDS_RE = "MP|HMP?|LT|5k|10k|3k|mile|marathon|threshold|tempo|easy|steady|moderate|medium|recovery";

export function uncoveredOffsets(
  text: string,
  steps: ReadonlyArray<Pick<ValidatedStep, "paceAdjustment">>,
): string[] {
  // Sign glued to its number, so "MP + 2mi @ HM" (a separator) and "8-12m" (a
  // range) and "-5' rec" (a duration) are not read as offsets.
  const written = text.matchAll(
    new RegExp(`(?:${ZONE_WORDS_RE})?\\s*(?<![\\d])([+-])(\\d+(?:\\.\\d+)?)\\s*(%)?(?!['′"″\\d])`, "gi"),
  );
  const carried = steps.map((s) => {
    const a = s.paceAdjustment;
    if (!a) return null;
    return `${a.value > 0 ? "+" : "-"}${Math.abs(a.value)}${a.type === "percent" ? "%" : ""}`;
  });
  const missing: string[] = [];
  for (const m of written) {
    const want = `${m[1]}${m[2]}${m[3] ? "%" : ""}`;
    if (!carried.includes(want)) missing.push(want);
  }
  return [...new Set(missing)];
}
