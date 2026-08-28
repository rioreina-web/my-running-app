/**
 * Resolves a plan-edit operation's `targetHint` against the coach's actual
 * scheduled week, and turns anything unresolved into a tappable question.
 *
 * Pure and deterministic on purpose — this is the layer that decides whether
 * "the workout" means one thing or several, and that decision must never be
 * made by the model. The pattern mirrors `workout-clarify.ts`: ask once per
 * distinct ambiguity, offer only real answers (rows that exist in the week,
 * or the coach's own light variant — never an invented one).
 */

import type { DayRole, LibrarySession } from "./session-library.ts";
import { classifyKind, selectSessions, lighterForm } from "./session-library.ts";
import type { PlanEditOp, ScheduledWorkoutRef } from "./plan-edit-schema.ts";
import { PACE_ZONE_SET, type PaceZone } from "./workout-step-validator.ts";

const WEEKDAY_NAMES: Record<string, number> = {
  monday: 1, mon: 1,
  tuesday: 2, tue: 2, tues: 2,
  wednesday: 3, wed: 3,
  thursday: 4, thu: 4, thur: 4, thurs: 4,
  friday: 5, fri: 5,
  saturday: 6, sat: 6,
  sunday: 7, sun: 7,
};

const DAY_ABBR: Record<number, string> = {
  1: "Mon", 2: "Tue", 3: "Wed", 4: "Thu", 5: "Fri", 6: "Sat", 7: "Sun",
};

const DAY_ROLE: Record<number, DayRole> = {
  1: "monday", 2: "tuesday", 3: "wednesday", 4: "thursday",
  5: "friday", 6: "saturday", 7: "sunday",
};

const STOP_WORDS = new Set([
  "the", "workout", "session", "this", "that", "next", "week", "day",
  "make", "change", "move", "swap", "cut", "please", "instead", "with",
]);

export interface Resolution {
  status: "resolved" | "ambiguous" | "not_found";
  matches: ScheduledWorkoutRef[];
}

/**
 * Narrow a week down to the row(s) `hint` refers to. Layered filters, each
 * applied only when it actually narrows the pool — a filter that would zero
 * it out is skipped rather than trusted, so a hint that doesn't quite match
 * this week's wording still surfaces its best candidates instead of nothing.
 */
export function resolveTarget(hint: string, week: ScheduledWorkoutRef[]): Resolution {
  const h = hint.toLowerCase().trim();
  const editable = week.filter((w) => !w.isPast);
  let pool = editable;

  // An explicit weekday name is authoritative, unlike the softer heuristics
  // below. "friday" with nothing scheduled that Friday must be not_found —
  // silently ignoring the day and matching across the whole pool would be
  // exactly the kind of guess this resolver exists to prevent.
  const dayEntry = Object.entries(WEEKDAY_NAMES).find(([name]) => new RegExp(`\\b${name}\\b`).test(h));
  if (dayEntry) {
    pool = pool.filter((w) => w.dayOfWeek === dayEntry[1]);
    if (pool.length === 0) return { status: "not_found", matches: [] };
  }

  if (/\blong run\b|\blong one\b|\bthe long\b/.test(h)) {
    const byLong = pool.filter(
      (w) => w.dayOfWeek === 6 || classifyKind(w.text, DAY_ROLE[w.dayOfWeek] ?? "saturday") === "long_run",
    );
    if (byLong.length) pool = byLong;
  }

  if (/\bworkout\b|\bquality\b|\bspeed\b|\binterval/.test(h)) {
    const byQuality = pool.filter((w) => !/^easy\b|\brest\b/i.test(w.text));
    if (byQuality.length && byQuality.length < pool.length) pool = byQuality;
  }

  if (pool.length > 1) {
    const words = contentWords(h);
    if (words.length) {
      const byContent = pool.filter((w) => words.some((cw) => w.text.toLowerCase().includes(cw)));
      if (byContent.length) pool = byContent;
    }
  }

  if (pool.length === 0) return { status: "not_found", matches: [] };
  if (pool.length === 1) return { status: "resolved", matches: pool };
  return { status: "ambiguous", matches: pool };
}

function contentWords(text: string): string[] {
  return text.toLowerCase().split(/\s+/).filter((w) => w.length > 3 && !STOP_WORDS.has(w));
}

export function describeWorkout(w: ScheduledWorkoutRef): string {
  const day = DAY_ABBR[w.dayOfWeek] ?? "?";
  const text = w.text.length > 58 ? w.text.slice(0, 58).trimEnd() + "…" : w.text;
  return `${day} · ${text}`;
}

export function resolveDayHint(hint: string): number | null {
  const h = hint.toLowerCase();
  const entry = Object.entries(WEEKDAY_NAMES).find(([name]) => new RegExp(`\\b${name}\\b`).test(h));
  return entry ? entry[1] : null;
}

// ── Questions ─────────────────────────────────────────────

export interface PlanEditOption {
  label: string;
  /** scheduled_workouts id for a target choice; a pace zone key for a pace
   *  choice; a library session's text for a swap choice. */
  value: string;
}

export interface PlanEditQuestion {
  id: string;
  question: string;
  op: PlanEditOp;
  options: PlanEditOption[];
}

/** One resolved op, ready to show as a diff line — see `describePatch`. */
export interface ResolvedPlanEdit {
  op: PlanEditOp;
  target: ScheduledWorkoutRef;
}

export interface PlanEditPlan {
  resolved: ResolvedPlanEdit[];
  questions: PlanEditQuestion[];
  /** ops whose targetHint matched nothing in the week at all. */
  notFound: PlanEditOp[];
}

/**
 * Resolve every op against the week. Each op becomes exactly one of:
 * resolved (unambiguous target AND no missing op-specific parameter),
 * a question (ambiguous target, or a target we found but a parameter we
 * cannot guess), or not-found (no candidate at all — surfaced, not dropped).
 */
export function planEdits(
  ops: PlanEditOp[],
  week: ScheduledWorkoutRef[],
  library: LibrarySession[],
): PlanEditPlan {
  const resolved: ResolvedPlanEdit[] = [];
  const questions: PlanEditQuestion[] = [];
  const notFound: PlanEditOp[] = [];

  ops.forEach((op, i) => {
    const r = resolveTarget(op.targetHint, week);

    if (r.status === "not_found") {
      notFound.push(op);
      return;
    }

    if (r.status === "ambiguous") {
      questions.push({
        id: `target-${i}`,
        question: `Which workout do you mean by "${op.targetHint}"?`,
        op,
        options: r.matches.map((w) => ({ label: describeWorkout(w), value: w.id })),
      });
      return;
    }

    const target = r.matches[0];

    if (target.isRaceWeek) {
      questions.push({
        id: `race-week-${i}`,
        question: `${describeWorkout(target)} is in a confirmed race week. Change it anyway?`,
        op,
        options: [{ label: "Yes, change it", value: target.id }, { label: "Leave it", value: "__skip__" }],
      });
      return;
    }

    const paramQuestion = unresolvedParameter(op, target, library, i, week);
    if (paramQuestion) {
      questions.push(paramQuestion);
      return;
    }

    resolved.push({ op, target });
  });

  return { resolved, questions, notFound };
}

/**
 * Op-specific parameters the resolver — not the model — must fill or ask
 * about. Mirrors the parser's rule: a missing pace never defaults, it asks.
 */
function unresolvedParameter(
  op: PlanEditOp,
  target: ScheduledWorkoutRef,
  library: LibrarySession[],
  i: number,
  week: ScheduledWorkoutRef[],
): PlanEditQuestion | null {
  if (op.kind === "retarget_pace" && op.paceZone == null) {
    return {
      id: `pace-${i}`,
      question: `What pace for ${describeWorkout(target)}?`,
      op,
      options: [...PACE_ZONE_SET].map((z) => ({ label: z, value: z })),
    };
  }

  if (op.kind === "lighten") {
    const source = library.find((s) => s.text.trim().toLowerCase() === target.text.trim().toLowerCase());
    const light = source ? lighterForm(source) : null;
    if (light) return null; // resolved — the diff uses the coach's own variant

    // No light variant on file for this exact session. Offer real, smaller
    // sessions from the same slot rather than asking an open question —
    // showing candidates beats making the coach describe what "lighter" means.
    const day = DAY_ROLE[target.dayOfWeek];
    const candidates = selectSessions(library, {
      day,
      maxMiles: (source?.totalMiles ?? 999) * 0.7,
      limit: 4,
    });
    const options: PlanEditOption[] = candidates.map((c) => ({ label: c.text, value: c.text }));
    options.push({ label: "Swap to an easy day instead", value: "__easy__" });
    return {
      id: `lighten-${i}`,
      question: `No lighter version on file for ${describeWorkout(target)}. Use one of these, or go easy?`,
      op,
      options,
    };
  }

  if (op.kind === "swap_session") {
    // A replacementHint is prose ("something shorter"), not a chosen session
    // — it narrows the candidates, it never resolves the op by itself. The
    // coach still taps the actual replacement, same as `lighten`.
    const day = DAY_ROLE[target.dayOfWeek];
    const kind = classifyKind(target.text, day);
    let candidates = selectSessions(library, { day, kinds: [kind], exclude: [target.text], limit: 8 });
    if (op.replacementHint) {
      const words = contentWords(op.replacementHint);
      const smaller = /shorter|easier|light|less|smaller/i.test(op.replacementHint);
      if (smaller) {
        const source = library.find((s) => s.text.trim().toLowerCase() === target.text.trim().toLowerCase());
        candidates = selectSessions(library, {
          day, kinds: [kind], exclude: [target.text],
          maxMiles: (source?.totalMiles ?? 999) * 0.85,
          limit: 8,
        });
      } else if (words.length) {
        const byWord = candidates.filter((c) => words.some((w) => c.text.toLowerCase().includes(w)));
        if (byWord.length) candidates = byWord;
      }
    }
    // A same-kind, same-day pool can be thin — some (day, kind) pairs have
    // only one or two real sessions across six seasons. Rather than offer a
    // single possibly-irrelevant candidate, broaden to any session for the
    // day once the pool is too small to be a real choice. The coach still
    // reads the verbatim text before tapping, so a broader pool costs
    // nothing in honesty — it just gives them more of their own words to
    // choose from.
    if (candidates.length < 2) {
      const broader = selectSessions(library, { day, exclude: [target.text], limit: 6 });
      const seen = new Set(candidates.map((c) => c.text));
      for (const c of broader) if (!seen.has(c.text)) { candidates.push(c); seen.add(c.text); }
    }
    return {
      id: `swap-${i}`,
      question: op.replacementHint
        ? `Swap ${describeWorkout(target)} for ${op.replacementHint} — which one?`
        : `Swap ${describeWorkout(target)} for which?`,
      op,
      options: candidates.slice(0, 4).map((c) => ({ label: c.text, value: c.text })),
    };
  }

  if (op.kind === "move_session") {
    const day = resolveDayHint(op.toDayHint);
    if (day == null) {
      return {
        id: `move-day-${i}`,
        question: `Move ${describeWorkout(target)} to which day?`,
        op,
        options: Object.entries(DAY_ABBR).map(([n, label]) => ({ label, value: n })),
      };
    }
    const conflict = week.find((w) => w.dayOfWeek === day && w.id !== target.id && !w.isPast && !/^rest\b/i.test(w.text));
    if (conflict) {
      return {
        id: `move-conflict-${i}`,
        question: `${DAY_ABBR[day]} already has "${conflict.text.slice(0, 40)}" — what should happen to it?`,
        op,
        options: [
          { label: `Swap the two`, value: "__swap__" },
          { label: `Move it out too`, value: "__bump__" },
          { label: `Cancel the move`, value: "__cancel__" },
        ],
      };
    }
  }

  return null;
}
