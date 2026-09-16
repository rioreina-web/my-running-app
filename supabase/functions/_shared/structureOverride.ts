// ============================================================================
// Athlete-facing structure correction (override).
//
// When the auto-parser mis-segments a workout (e.g. a warmup+tempo merged into
// one 5500m block, or two interval sets collapsed into one 1800m blob), the
// athlete can correct the rep breakdown by hand. That correction is stored back
// into `training_logs.parsed_structure` with an `edited_by_user: true` marker.
//
// Why reuse `parsed_structure` rather than a new column: every consumer already
// reads `parsed_structure` (iOS rep chart, Coach Read narrative, athlete-state
// load math). Reusing it means the correction is honored EVERYWHERE for free —
// no per-consumer precedence wiring. The single hard requirement is that the
// auto-parser must NEVER clobber a correction; `isUserEdited()` is the guard it
// checks before writing. See parse-workout-structure/index.ts.
//
// Pure, dependency-free, unit-testable (see structureOverride.test.ts). No I/O.
// ============================================================================

const METERS_PER_MILE = 1609.344;

// Roles a block may carry. Mirrors the parser's OUTPUT shape (parse-workout-
// structure.v2 prompt) so a correction is shape-compatible with an auto-parse.
export const BLOCK_ROLES = [
  "warmup",
  "work_rep",
  "recovery",
  "cooldown",
  "steady",
] as const;
export type BlockRole = (typeof BLOCK_ROLES)[number];

// Roles that count as a quality rep for the work summary.
const WORK_ROLES: ReadonlySet<string> = new Set(["work_rep"]);

export interface StructureBlock {
  role: BlockRole;
  rep_num: number | null;
  distance_miles: number;
  duration_s: number;
  avg_pace_per_mile: string | null; // "M:SS" — set for jog recoveries too, not just reps
  avg_hr: number | null;
  recovery_style?: "jog" | "standing"; // only on recovery blocks
}

export interface StructureOverride {
  // Carried through from the auto-parse when present (the athlete corrects
  // geometry; the workout's type/equivalent-pace stay unless they change them).
  type?: string | null;
  intent_pattern?: string | null;
  blocks: StructureBlock[];
  work?: Record<string, unknown> | null;
  equivalent_race_pace?: unknown;
  subjective?: unknown;
  confidence?: number | null;
  // Correction markers — the parser guard reads `edited_by_user`.
  edited_by_user?: boolean;
  edited_at?: string;
}

/** The guard the auto-parser checks: never overwrite a human correction. */
export function isUserEdited(parsedStructure: unknown): boolean {
  return (
    typeof parsedStructure === "object" &&
    parsedStructure !== null &&
    (parsedStructure as { edited_by_user?: unknown }).edited_by_user === true
  );
}

const PACE_RE = /^\d{1,3}:[0-5]\d$/;

/**
 * Validate + normalize a client-supplied correction into a clean
 * `parsed_structure` object. Throws `Error(message)` on anything structurally
 * invalid so the edge function can return a 400 with a useful message. Clamps
 * soft issues (rounds distances, recomputes rep numbers + work summary) so the
 * stored object is always internally consistent regardless of client sloppiness.
 *
 * `existing` is the current auto-parse (or prior override); its non-geometry
 * fields (type, equivalent_race_pace, subjective) are carried forward unless the
 * client overrides them.
 */
export function normalizeOverride(
  input: unknown,
  existing: unknown = null,
): StructureOverride {
  if (typeof input !== "object" || input === null) {
    throw new Error("override must be an object");
  }
  const raw = input as Record<string, unknown>;
  if (!Array.isArray(raw.blocks)) {
    throw new Error("override.blocks must be an array");
  }
  if (raw.blocks.length === 0) {
    throw new Error("override.blocks must not be empty");
  }
  if (raw.blocks.length > 60) {
    throw new Error("override.blocks too long (max 60)");
  }

  const ex = (typeof existing === "object" && existing !== null)
    ? (existing as Record<string, unknown>)
    : {};

  let repNum = 0;
  const blocks: StructureBlock[] = raw.blocks.map((b, i) => {
    if (typeof b !== "object" || b === null) {
      throw new Error(`block ${i} is not an object`);
    }
    const blk = b as Record<string, unknown>;
    const role = String(blk.role ?? "").toLowerCase();
    if (!BLOCK_ROLES.includes(role as BlockRole)) {
      throw new Error(
        `block ${i} has invalid role "${blk.role}" (expected one of ${BLOCK_ROLES.join(", ")})`,
      );
    }
    const distRaw = Number(blk.distance_miles ?? 0);
    if (!isFinite(distRaw) || distRaw < 0 || distRaw > 100) {
      throw new Error(`block ${i} distance_miles out of range`);
    }
    const durRaw = Number(blk.duration_s ?? 0);
    if (!isFinite(durRaw) || durRaw < 0 || durRaw > 86_400) {
      throw new Error(`block ${i} duration_s out of range`);
    }
    let pace: string | null = null;
    if (typeof blk.avg_pace_per_mile === "string" && PACE_RE.test(blk.avg_pace_per_mile.trim())) {
      pace = blk.avg_pace_per_mile.trim();
    } else if (distRaw > 0 && durRaw > 0) {
      // Re-derive a clean pace from the block's own distance + time when the
      // client didn't supply a valid one (e.g. after a split).
      pace = fmtPace(durRaw / distRaw);
    }
    const hrRaw = blk.avg_hr == null ? null : Number(blk.avg_hr);
    const hr = hrRaw != null && isFinite(hrRaw) && hrRaw > 0 && hrRaw < 260
      ? Math.round(hrRaw)
      : null;

    const isWork = WORK_ROLES.has(role);
    // A recovery is its own segment: a jog carries its measured pace; a standing
    // rest does not. Default to jog when it moved, standing when it didn't.
    let recoveryStyle: "jog" | "standing" | undefined;
    if (role === "recovery") {
      const declared = String(blk.recovery_style ?? "").toLowerCase();
      recoveryStyle = declared === "jog" || declared === "standing"
        ? (declared as "jog" | "standing")
        : (pace != null && distRaw > 0.01 ? "jog" : "standing");
    }
    return {
      role: role as BlockRole,
      rep_num: isWork ? ++repNum : null,
      distance_miles: round2(distRaw),
      duration_s: Math.round(durRaw),
      avg_pace_per_mile: pace,
      avg_hr: hr,
      ...(recoveryStyle ? { recovery_style: recoveryStyle } : {}),
    };
  });

  if (repNum === 0) {
    throw new Error("override must contain at least one work_rep block");
  }

  // Recompute the work summary from the corrected work_rep blocks so reps/pace
  // stay consistent with what the athlete actually laid out.
  const workBlocks = blocks.filter((b) => b.role === "work_rep");
  const totalWorkMiles = workBlocks.reduce((a, b) => a + b.distance_miles, 0);
  const totalWorkSeconds = workBlocks.reduce((a, b) => a + b.duration_s, 0);
  const work: Record<string, unknown> = {
    ...(typeof ex.work === "object" && ex.work !== null ? ex.work as Record<string, unknown> : {}),
    reps: workBlocks.length,
    total_work_distance_mi: round2(totalWorkMiles),
    actual_pace_per_mile: totalWorkMiles > 0
      ? fmtPace(totalWorkSeconds / totalWorkMiles)
      : null,
    // The athlete's correction is authoritative; an execution verdict computed
    // against the old geometry no longer applies.
    execution_quality: null,
  };

  const intentPattern = typeof raw.intent_pattern === "string" && raw.intent_pattern.trim().length > 0
    ? raw.intent_pattern.trim().slice(0, 300)
    : (typeof ex.intent_pattern === "string" ? ex.intent_pattern : null) ??
      (typeof ex.pattern === "string" ? ex.pattern : null);

  const type = typeof raw.type === "string" && raw.type.trim().length > 0
    ? raw.type.trim()
    : (typeof ex.type === "string" ? ex.type : null);

  return {
    type,
    intent_pattern: intentPattern,
    blocks,
    work,
    // Carry through fields the athlete didn't touch.
    equivalent_race_pace: ex.equivalent_race_pace ?? null,
    subjective: ex.subjective ?? null,
    confidence: typeof ex.confidence === "number" ? ex.confidence : null,
    edited_by_user: true,
    edited_at: new Date().toISOString(),
  };
}

function fmtPace(secPerMile: number): string | null {
  if (!isFinite(secPerMile) || secPerMile <= 0) return null;
  const t = Math.round(secPerMile);
  const m = Math.floor(t / 60);
  const s = t % 60;
  return `${m}:${String(s).padStart(2, "0")}`;
}

function round2(x: number): number {
  return Math.round(x * 100) / 100;
}

export const _internal = { METERS_PER_MILE, fmtPace, round2 };
