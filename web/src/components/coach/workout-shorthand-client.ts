// Client seam for coach-shorthand parsing.
//
// The local grammar in `workout-nl-parser.ts` still runs FIRST and still
// answers alone whenever it consumed the whole input cleanly — that is 61 of
// this coach's 137 real workouts, instant and free, with no network involved.
// Only the remainder goes to `parse-workout-shorthand`, whose model layer
// reads the things a grammar structurally cannot: a "cutdown" implying a
// progression, an effort word that means one zone here and another there, a
// parenthetical addressed to a person rather than to the parser.
//
// Measured over the full corpus (`web/tests/eval/layered-shorthand-eval.ts`):
//   grammar alone   61/137 clean, 130/137 build something
//   layered         93/137 clean, 135/137 build something
//
// Every failure path returns the grammar's answer. No key, no budget, offline,
// a timeout, a 500 — the button keeps working and simply resolves less. That
// is deliberate: this coach lost voice memos for two days to depleted Gemini
// credits, and a plan builder that stops building is worse than one that asks
// a few more questions.

import { createClient } from "@/lib/supabase/client";
import {
  parseWorkoutText,
  uncoveredPaceOffsets,
  type ParseOptions,
  type ParseWorkoutResult,
  type UnresolvedReason,
} from "./workout-nl-parser";
import type { PaceZone, WorkoutStep } from "./workout-helpers";

/** Shape returned by `_shared/workout-step-validator.ts`. */
interface RemoteStep {
  stepType: "warmup" | "active" | "recovery" | "rest" | "cooldown";
  durationType: "distance_miles" | "distance_km" | "distance_meters" | "time_seconds";
  durationValue: number;
  paceZone: PaceZone | null;
  paceAdjustment?: { type: "seconds_per_mile" | "percent"; value: number };
  exactPaceSecPerMile?: number;
  repeats?: number;
  recovery?: { durationType: RemoteStep["durationType"]; durationValue: number; isJog: boolean };
  note: string;
  /** Reason code from the shared validator, or null when the pace is known. */
  unresolvedReason: UnresolvedReason | null;
}

interface RemoteResponse {
  structuredSteps?: RemoteStep[];
  warnings?: string[];
  unparsed?: string[];
  workoutNote?: string | null;
  source?: string;
}

export interface ShorthandResult extends ParseWorkoutResult {
  /** Which layer answered. Shown to nobody; useful in logs and tests. */
  source: "grammar" | "model";
}

let idCounter = 0;
const nextId = () => `sh-${Date.now().toString(36)}-${++idCounter}`;

function toWorkoutStep(r: RemoteStep): WorkoutStep {
  const step: WorkoutStep = {
    id: nextId(),
    stepType: r.stepType,
    durationType: r.durationType,
    durationValue: r.durationValue,
    // `paceZone` is non-null in the web type, so an unresolved pace lands on
    // `easy` — the conservative direction — and the warning carries the truth.
    // Erring slow is recoverable; erring fast is not.
    paceZone: r.paceZone ?? "easy",
    notes: r.note || "",
  };
  if (r.exactPaceSecPerMile != null) step.exactPaceSecPerMile = r.exactPaceSecPerMile;
  else if (r.paceAdjustment) step.paceAdjustment = r.paceAdjustment;
  if (r.repeats && r.repeats > 1) step.repeats = r.repeats;
  if (r.recovery) {
    step.recovery = {
      durationType: r.recovery.durationType,
      durationValue: r.recovery.durationValue,
      paceZone: r.recovery.isJog ? "easy" : undefined,
    };
  }
  return step;
}

/**
 * Parse coach shorthand, escalating to the server only when the local grammar
 * left something unresolved. Never rejects.
 */
export async function parseShorthand(
  text: string,
  opts: ParseOptions = {},
): Promise<ShorthandResult> {
  const local = parseWorkoutText(text, opts);
  // `unresolved` counts. A step the grammar built but could not pace is not a
  // clean read — it is a wrong answer wearing a complete-looking step list,
  // and it is the shape that escalation exists for. Leaving it out meant
  // "16 x K alternating MP-3% & MP+5%" returned 16 easy kilometres without
  // the model ever being asked, because nothing landed in `unparsed` or
  // `warnings` to say the prescription had been dropped.
  // ...and `uncoveredPaceOffsets` counts too, because every condition above is
  // the grammar GRADING ITSELF. That question is worthless against the failure
  // this parser actually produces: a confident wrong answer. "16 x K
  // alternating MP-3% & MP +5%" came back as sixteen steps, no warnings, no
  // unparsed text, nothing unresolved — and half of them had silently lost
  // their offset. It passed every check here, so the model was never asked,
  // and the coach got a workout they had not prescribed.
  //
  // This one checks the work instead of taking its word: an offset written in
  // the source that no step is carrying means something was dropped in
  // transit, whatever the parser claims. Measured at 4 of 68 clean parses on
  // the real corpus, so it escalates rarely and does not turn every workout
  // into a paid call.
  const dropped = uncoveredPaceOffsets(text, local.steps);

  const localClean =
    local.steps.length > 0 &&
    local.unparsed.length === 0 &&
    local.warnings.length === 0 &&
    Object.keys(local.unresolved).length === 0 &&
    dropped.length === 0;

  if (localClean) return { ...local, source: "grammar" };

  try {
    const supabase = createClient();
    const { data, error } = await supabase.functions.invoke<RemoteResponse>(
      "parse-workout-shorthand",
      { body: { input: text, useModel: true } },
    );
    if (error || !data?.structuredSteps?.length) return { ...local, source: "grammar" };

    const steps = data.structuredSteps.map(toWorkoutStep);
    const warnings = data.warnings ?? [];
    const unparsed = data.unparsed ?? [];

    // Carry the server's per-step reason codes across on the SAME step ids we
    // just minted, so the UI asks about the right rows.
    const unresolved: Record<string, UnresolvedReason> = {};
    data.structuredSteps.forEach((r, i) => {
      if (r.unresolvedReason) unresolved[steps[i].id] = r.unresolvedReason;
    });

    // Only take the server's answer if it left LESS unresolved than the
    // grammar did. The model is better on the tail but occasionally worse on
    // a shape the grammar already nails, and there is no reason to lose that.
    // Same accounting on both sides, `unresolved` included — otherwise a
    // model answer that paced every step loses to a grammar answer that
    // paced none of them, on a tie neither of them actually tied.
    // `dropped` counts on the LOCAL side, and leaving it out is what made this
    // comparison hand the coach a wrong workout.
    //
    // The grammar's failure mode is a confidently wrong answer: on
    // "16xk alternating between MP-3% & MP+5%" it returns ONE step at MP-3%
    // with no warnings, nothing unparsed and nothing unresolved — a local
    // residue of ZERO. The model then returns sixteen correct alternating legs
    // plus any warning at all, scores 1, loses 1 > 0, and its correct answer is
    // discarded in favour of a session the coach never wrote. The check that
    // caught the drop and triggered the escalation was not consulted again when
    // deciding which answer to keep, so the escalation was pure cost.
    const remoteDropped = uncoveredPaceOffsets(text, steps);
    const remoteResidue =
      warnings.length + unparsed.length + Object.keys(unresolved).length + remoteDropped.length;
    const localResidue =
      local.warnings.length +
      local.unparsed.length +
      Object.keys(local.unresolved).length +
      dropped.length;
    if (remoteResidue > localResidue && local.steps.length > 0) {
      return { ...local, source: "grammar" };
    }

    if (data.workoutNote) warnings.push(`note from the text: "${data.workoutNote}"`);
    return { steps, warnings, unparsed, unresolved, source: "model" };
  } catch {
    return { ...local, source: "grammar" };
  }
}
