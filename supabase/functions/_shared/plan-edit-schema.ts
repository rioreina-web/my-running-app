/**
 * Types for text-box plan edits — "make Tuesday easy", "cut the long run to
 * 14", "retarget Thursday's tempo to HM pace".
 *
 * Same division as the workout-shorthand path this reuses: the model maps
 * free text to a small set of typed OPERATIONS, a deterministic resolver
 * decides which real scheduled_workouts row(s) each operation refers to, and
 * anything the resolver cannot pin down to exactly one row becomes a
 * question with the candidates as tappable options — never a guess.
 *
 * The model NEVER resolves a target itself. It is given the week's rows as
 * context and asked to lift a `targetHint` verbatim from the coach's own
 * words ("Tuesday", "the long run", "the mile cutdown"); matching that hint
 * to an id is `plan-edit-resolver.ts`'s job, done the same way whichever
 * layer produced the hint. This keeps ambiguity handling deterministic and
 * testable independent of the model.
 */

import type { PaceZone } from "./workout-step-validator.ts";

export type PlanEditOpKind =
  | "schedule_easy"
  | "schedule_rest"
  | "lighten"
  | "scale_distance"
  | "retarget_pace"
  | "swap_session"
  | "move_session";

/** Minimal view of a scheduled_workouts row — enough to resolve, describe,
 *  and reason about a target without pulling in the full DB row shape. */
export interface ScheduledWorkoutRef {
  id: string;
  date: string; // YYYY-MM-DD
  dayOfWeek: number; // 1=Mon..7=Sun, matches shift-day's convention
  weekNumber: number | null;
  /** Best-effort verbatim workout text — from workout_data.notes/session, or
   *  the coach's own description. Used both for display and content matching. */
  text: string;
  workoutType: string | null;
  isKeySession: boolean;
  /** true when the row falls in a confirmed race week — edits there need
   *  the same explicit confirmation edit-scheduled-workout already requires. */
  isRaceWeek?: boolean;
  /** true when `date` is in the past — past workouts cannot be edited. */
  isPast?: boolean;
}

interface PlanEditOpBase {
  kind: PlanEditOpKind;
  /** Verbatim phrase from the coach's text naming which workout this op
   *  targets — "Tuesday", "the long run", "Saturday's session". Resolved
   *  against the week by `plan-edit-resolver.ts`, never by the model. */
  targetHint: string;
}

export interface ScheduleEasyOp extends PlanEditOpBase { kind: "schedule_easy" }
export interface ScheduleRestOp extends PlanEditOpBase { kind: "schedule_rest" }

/** Swap for the coach's OWN scaled-down version of this exact session, when
 *  one exists in the library. Never synthesises one — see session-library.ts. */
export interface LightenOp extends PlanEditOpBase { kind: "lighten" }

export interface ScaleDistanceOp extends PlanEditOpBase {
  kind: "scale_distance";
  toMiles: number;
}

export interface RetargetPaceOp extends PlanEditOpBase {
  kind: "retarget_pace";
  /** null when the coach named an effort ("easier") rather than a zone —
   *  same "never invent a pace" rule as the shorthand parser. Null forces a
   *  clarification instead of a guess. */
  paceZone: PaceZone | null;
  adjustment?: { type: "seconds_per_mile" | "percent"; value: number };
}

export interface SwapSessionOp extends PlanEditOpBase {
  kind: "swap_session";
  /** e.g. "something shorter", "another tempo" — narrows the library search.
   *  null means "pick anything of the same kind", left to the resolver. */
  replacementHint: string | null;
}

export interface MoveSessionOp extends PlanEditOpBase {
  kind: "move_session";
  toDayHint: string;
}

export type PlanEditOp =
  | ScheduleEasyOp
  | ScheduleRestOp
  | LightenOp
  | ScaleDistanceOp
  | RetargetPaceOp
  | SwapSessionOp
  | MoveSessionOp;

/**
 * What the model returns before validation — `ops` is untyped JSON at this
 * point, not yet PlanEditOp[]. `plan-edit-validator.ts` is the only thing
 * allowed to turn it into the typed union above.
 */
export interface RawPlanEditResponse {
  ops: unknown[];
  /** Text the model could not turn into any op at all — never dropped silently. */
  unparsed: string[];
}
