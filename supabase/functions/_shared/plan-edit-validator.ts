/**
 * Turns whatever a model returned into typed, bounded PlanEditOp[] — the
 * plan-edit sibling of `workout-step-validator.ts`. Same job: the model's
 * output is untyped JSON on the wire, and nothing downstream should trust a
 * field until this has looked at it.
 *
 * Bounds here are deliberately tight. A plan edit is not a new workout being
 * authored from scratch — it is a mutation of something a coach already
 * built, so a proposed change that is itself absurd (a "long run" scaled to
 * 80 miles, a pace offset of an hour) is refused rather than shown as if it
 * were a real option.
 */

import { PACE_ZONE_SET, type PaceZone } from "./workout-step-validator.ts";
import type { PlanEditOp, PlanEditOpKind, RawPlanEditResponse } from "./plan-edit-schema.ts";

export const MAX_SCALE_MILES = 30;
export const MAX_PACE_OFFSET_SEC = 180;
export const MAX_PACE_OFFSET_PCT = 25;
export const MAX_OPS = 12;

const KNOWN_KINDS = new Set<PlanEditOpKind>([
  "schedule_easy", "schedule_rest", "lighten", "scale_distance",
  "retarget_pace", "swap_session", "move_session",
]);

export interface RawOp {
  kind?: unknown;
  targetHint?: unknown;
  toMiles?: unknown;
  paceZone?: unknown;
  adjustmentType?: unknown;
  adjustmentValue?: unknown;
  replacementHint?: unknown;
  toDayHint?: unknown;
}

const str = (v: unknown): string | null => (typeof v === "string" && v.trim() ? v.trim() : null);
const num = (v: unknown): number | null => (typeof v === "number" && Number.isFinite(v) ? v : null);

export interface PlanEditValidationResult {
  ops: PlanEditOp[];
  unparsed: string[];
  warnings: string[];
}

export function validatePlanEditOps(raw: unknown, opts: { unparsed?: string[] } = {}): PlanEditValidationResult {
  const warnings: string[] = [];
  const unparsed = [...(opts.unparsed ?? [])];
  const ops: PlanEditOp[] = [];

  if (!Array.isArray(raw)) return { ops: [], unparsed, warnings: ["no operations returned"] };

  for (const [i, item] of raw.slice(0, MAX_OPS).entries()) {
    const r = (item ?? {}) as RawOp;
    const where = `op ${i + 1}`;

    const kind = str(r.kind);
    if (!kind || !KNOWN_KINDS.has(kind as PlanEditOpKind)) {
      warnings.push(`${where} had an unknown operation "${kind ?? "?"}" and was dropped`);
      continue;
    }

    const targetHint = str(r.targetHint);
    if (!targetHint) {
      warnings.push(`${where} (${kind}) named no target and was dropped`);
      continue;
    }

    const op = buildOp(kind as PlanEditOpKind, targetHint, r, warnings, where);
    if (op) ops.push(op);
  }

  if (raw.length > MAX_OPS) {
    warnings.push(`only the first ${MAX_OPS} operations were kept (${raw.length} proposed)`);
  }

  return { ops, unparsed, warnings };
}

function buildOp(
  kind: PlanEditOpKind,
  targetHint: string,
  r: RawOp,
  warnings: string[],
  where: string,
): PlanEditOp | null {
  switch (kind) {
    case "schedule_easy":
      return { kind, targetHint };
    case "schedule_rest":
      return { kind, targetHint };

    case "lighten":
      return { kind, targetHint };

    case "scale_distance": {
      const toMiles = num(r.toMiles);
      if (toMiles == null || toMiles <= 0) {
        warnings.push(`${where} (scale_distance) had no usable distance and was dropped`);
        return null;
      }
      if (toMiles > MAX_SCALE_MILES) {
        warnings.push(`${where} asked for ${toMiles}mi — over the ${MAX_SCALE_MILES}mi sanity cap, dropped`);
        return null;
      }
      return { kind, targetHint, toMiles: Math.round(toMiles * 10) / 10 };
    }

    case "retarget_pace": {
      const zoneRaw = str(r.paceZone);
      const paceZone = zoneRaw && PACE_ZONE_SET.has(zoneRaw) ? (zoneRaw as PaceZone) : null;
      if (zoneRaw && !paceZone) {
        warnings.push(`${where} named an unknown pace "${zoneRaw}" — treated as unspecified`);
      }
      const op: import("./plan-edit-schema.ts").RetargetPaceOp = { kind, targetHint, paceZone };

      const adjType = str(r.adjustmentType);
      const adjValue = num(r.adjustmentValue);
      if (adjType && adjValue != null && adjValue !== 0) {
        if (adjType === "seconds_per_mile" && Math.abs(adjValue) <= MAX_PACE_OFFSET_SEC) {
          op.adjustment = { type: "seconds_per_mile", value: Math.round(adjValue) };
        } else if (adjType === "percent" && Math.abs(adjValue) <= MAX_PACE_OFFSET_PCT) {
          op.adjustment = { type: "percent", value: adjValue };
        } else {
          warnings.push(`${where} had an out-of-range pace offset and it was ignored`);
        }
      }
      return op;
    }

    case "swap_session":
      return { kind, targetHint, replacementHint: str(r.replacementHint) };

    case "move_session": {
      const toDayHint = str(r.toDayHint);
      if (!toDayHint) {
        warnings.push(`${where} (move_session) named no destination day and was dropped`);
        return null;
      }
      return { kind, targetHint, toDayHint };
    }
  }
}

export function validateRawResponse(raw: RawPlanEditResponse | null): PlanEditValidationResult {
  if (!raw) return { ops: [], unparsed: [], warnings: ["model returned nothing usable"] };
  return validatePlanEditOps(raw.ops as unknown[], { unparsed: raw.unparsed });
}
