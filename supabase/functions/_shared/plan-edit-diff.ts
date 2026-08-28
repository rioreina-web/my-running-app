/**
 * Turns a RESOLVED plan edit into a before/after line for the approval UI.
 *
 * Deliberately textual, not a full `workout_data` regeneration. Producing
 * the actual replacement steps for `scale_distance` or `retarget_pace` needs
 * the same step-scaling logic the workout editor uses, and belongs in the
 * apply path (`edit-scheduled-workout`) once this is wired up — see the
 * module doc in `plan-edit-resolver.ts`. This layer's job is showing the
 * coach an honest one-line diff to approve or reject before that happens.
 */

import { lighterForm, type LibrarySession } from "./session-library.ts";
import { describeWorkout, resolveDayHint } from "./plan-edit-resolver.ts";
import type { ResolvedPlanEdit } from "./plan-edit-resolver.ts";

export interface PlanEditDiff {
  workoutId: string;
  day: string;
  before: string;
  after: string;
}

const DAY_ABBR: Record<number, string> = {
  1: "Mon", 2: "Tue", 3: "Wed", 4: "Thu", 5: "Fri", 6: "Sat", 7: "Sun",
};

function findLibraryMatch(text: string, library: LibrarySession[]): LibrarySession | undefined {
  return library.find((s) => s.text.trim().toLowerCase() === text.trim().toLowerCase());
}

export function describePatch(edit: ResolvedPlanEdit, library: LibrarySession[]): PlanEditDiff {
  const { op, target } = edit;
  const day = DAY_ABBR[target.dayOfWeek] ?? "?";
  const base: Pick<PlanEditDiff, "workoutId" | "day" | "before"> = {
    workoutId: target.id,
    day,
    before: target.text,
  };

  switch (op.kind) {
    case "schedule_easy":
      return { ...base, after: "Easy run — same distance as before" };

    case "schedule_rest":
      return { ...base, after: "Rest day" };

    case "lighten": {
      const source = findLibraryMatch(target.text, library);
      const light = source ? lighterForm(source) : null;
      return { ...base, after: light ?? "Easy run — same distance as before" };
    }

    case "scale_distance":
      return { ...base, after: `Same session, scaled to ${op.toMiles}mi` };

    case "retarget_pace": {
      const zone = op.paceZone ?? "the same pace";
      const adj = op.adjustment
        ? ` ${op.adjustment.value > 0 ? "+" : ""}${op.adjustment.value}${op.adjustment.type === "percent" ? "%" : "s/mi"}`
        : "";
      return { ...base, after: `Same session, retargeted to ${zone}${adj}` };
    }

    case "swap_session":
      // Only reached once a question has been answered — the option VALUE
      // is the chosen library session's text, carried back as replacementHint.
      return { ...base, after: op.replacementHint ?? "(swap target not yet chosen)" };

    case "move_session": {
      const dayNum = resolveDayHint(op.toDayHint);
      const label = dayNum != null ? DAY_ABBR[dayNum] : op.toDayHint;
      return { ...base, after: `Moved to ${label} — ${target.text}` };
    }
  }
}

export function describeWeekChange(edit: ResolvedPlanEdit, library: LibrarySession[]): string {
  const d = describePatch(edit, library);
  return `${d.day}: "${describeWorkout(edit.target).replace(/^[A-Za-z]+ · /, "")}" → ${d.after}`;
}
