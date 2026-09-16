/**
 * Athlete Signature — grammar v1 (addendum §4.1, §9).
 *
 * ≈ 8 antecedents × 7 lags × 6 outcomes. The cross-product is the "open
 * discovery" space: nobody enumerates the CONCLUSIONS, the grammar generates
 * the HYPOTHESES. Extending discovery = adding one object to a list here, each
 * a pure predicate — no redesign (addendum §4.1, closing paragraph).
 *
 * The medical line (§ principle 6, §7): any hypothesis whose OUTCOME is a
 * niggle mention is categorized `niggle_assoc`, which routes it through the
 * niggle gate before it can ever reach an athlete. Category is resolved from
 * the outcome domain first, antecedent second (see resolveCategory).
 */

import type {
  Antecedent,
  AthleteDay,
  Category,
  Hypothesis,
  Lag,
  Outcome,
} from "./types.ts";

// ── Shared classifiers ────────────────────────────────────────────────────────

/** Low-mood labels — matches _shared/rules/types.ts LOW_MOOD_LABELS. */
const LOW_MOOD: ReadonlySet<string> = new Set(["tired", "struggling", "injured"]);

/** A long run for antecedent purposes. Athlete-relative refinement is S4. */
const LONG_RUN_MILES = 16;

// ── Antecedents (8) ───────────────────────────────────────────────────────────

export const ANTECEDENTS: readonly Antecedent[] = [
  {
    key: "rest_day",
    label: "a full rest day",
    category: "recovery",
    exposed: (d) => d.restDay,
  },
  {
    key: "long_run",
    label: `a long run (≥ ${LONG_RUN_MILES} mi)`,
    category: "load_response",
    exposed: (d) => d.ran && (d.isLongRun || (d.distanceMiles ?? 0) >= LONG_RUN_MILES),
  },
  {
    key: "intensity_jump",
    label: "a week with an intensity jump (≥ 15%)",
    category: "load_response",
    exposed: (d) => d.intensityJumpWeek,
  },
  {
    key: "b2b_quality",
    label: "back-to-back quality days",
    category: "load_response",
    // Fires on the SECOND quality day; the day-before context is pre-tagged by
    // tagDerivedAntecedents so this stays a pure single-day predicate.
    exposed: (d) => d.isQuality && d._b2bQuality === true,
  },
  {
    key: "bike_day",
    label: "a bike/swim cross-training day",
    category: "schedule",
    exposed: (d) => d.crossTrain,
  },
  {
    key: "down_week",
    label: "a down week (volume < 80% of the 4-week average)",
    category: "load_response",
    exposed: (d) => d.downWeek,
  },
  {
    key: "start_pm",
    label: "an evening start",
    category: "environment",
    sameDayOnly: true,
    exposed: (d) => d.startPeriod === "pm",
    baseline: (d) => d.startPeriod === "am",
  },
  {
    key: "heat_oppressive",
    label: "an oppressive heat band",
    category: "environment",
    sameDayOnly: true,
    exposed: (d) => d.heatBand === "oppressive",
    baseline: (d) => d.heatBand === "comfortable",
  },
];

// ── Lags (7) ──────────────────────────────────────────────────────────────────

export const LAGS: readonly Lag[] = [
  { key: "same_day", label: "the same day", offset: [0, 0] },
  { key: "+1d", label: "the next day", offset: [1, 1] },
  { key: "+2d", label: "two days later", offset: [2, 2] },
  { key: "+3d", label: "three days later", offset: [3, 3] },
  { key: "4-7d", label: "four to seven days later", offset: [4, 7] },
  { key: "same_week", label: "later that week", offset: [0, 6] },
  { key: "next_week", label: "the following week", offset: [7, 13] },
];

// ── Outcomes (6) ──────────────────────────────────────────────────────────────

export const OUTCOMES: readonly Outcome[] = [
  {
    key: "work_pace",
    label: "work-segment pace",
    kind: "continuous",
    category: "performance",
    // Segment rule (§4.1): quality only, and always work-segment pace.
    present: (d) => d.isQuality && d.workSegmentPaceMps != null,
    value: (d) => d.workSegmentPaceMps,
  },
  {
    key: "work_hr",
    label: "heart rate at work pace",
    kind: "continuous",
    category: "performance",
    present: (d) => d.isQuality && d.workSegmentHr != null,
    value: (d) => d.workSegmentHr,
  },
  {
    key: "easy_effort",
    label: "easy-run effort per km",
    kind: "continuous",
    category: "performance",
    present: (d) => d.ran && !d.isQuality && d.easyEffortPerKm != null,
    value: (d) => d.easyEffortPerKm,
  },
  {
    key: "long_fade",
    label: "long-run fade",
    kind: "continuous",
    category: "performance",
    present: (d) => d.isLongRun && d.longRunFadeSecPerMile != null,
    value: (d) => d.longRunFadeSecPerMile,
  },
  {
    key: "mood",
    label: "a low-mood log",
    kind: "rate",
    category: "mood",
    present: (d) => d.moodLabel != null,
    event: (d) => d.moodLabel != null && LOW_MOOD.has(d.moodLabel),
  },
  {
    key: "niggle",
    label: "a niggle mention",
    kind: "rate",
    category: "niggle_assoc",
    present: (d) => d.ran, // any run day could carry a mention
    event: (d) => d.niggleMentioned,
  },
];

// ── Category resolution ───────────────────────────────────────────────────────

/**
 * The outcome domain wins when it carries a safety meaning: a niggle outcome is
 * always `niggle_assoc` (routes through the §7 gate) and a mood outcome is
 * always `mood`, no matter what the antecedent is. Otherwise the antecedent's
 * category describes the pattern.
 */
export function resolveCategory(antecedent: Antecedent, outcome: Outcome): Category {
  if (outcome.key === "niggle") return "niggle_assoc";
  if (outcome.key === "mood") return "mood";
  return antecedent.category;
}

/** Canonical machine form, e.g. `rest_day->work_pace@+2d` (addendum §5). */
export function patternKey(h: Hypothesis): string {
  return `${h.antecedent.key}->${h.outcome.key}@${h.lag.key}`;
}

// ── Enumeration ───────────────────────────────────────────────────────────────

/**
 * The full hypothesis space for this athlete. Condition contrasts (AM/PM, heat)
 * only pair with the same-day lag — a "PM start three days later" is nonsense.
 * Event antecedents pair with every lag.
 */
export function enumerateHypotheses(): Hypothesis[] {
  const out: Hypothesis[] = [];
  for (const antecedent of ANTECEDENTS) {
    const lags = antecedent.sameDayOnly
      ? LAGS.filter((l) => l.key === "same_day")
      : LAGS;
    for (const lag of lags) {
      for (const outcome of OUTCOMES) {
        out.push({ antecedent, lag, outcome });
      }
    }
  }
  return out;
}

/**
 * Pre-tag back-to-back quality days. The b2b_quality antecedent needs to know
 * whether the PREVIOUS calendar day was also a quality day; we compute that
 * once here and stash it on a private field, keeping the antecedent predicate
 * a pure function of a single day.
 */
export function tagDerivedAntecedents(days: AthleteDay[]): AthleteDay[] {
  const byDate = new Map(days.map((d) => [d.date, d]));
  for (const d of days) {
    const prev = byDate.get(shiftDate(d.date, -1));
    d._b2bQuality = Boolean(d.isQuality && prev?.isQuality);
  }
  return days;
}

/** Add `deltaDays` to an ISO `YYYY-MM-DD` date, returning ISO. UTC-safe. */
export function shiftDate(iso: string, deltaDays: number): string {
  const t = Date.parse(`${iso}T00:00:00Z`);
  return new Date(t + deltaDays * 86_400_000).toISOString().slice(0, 10);
}

/** Whole-day difference between two ISO dates (b − a). */
export function dayDiff(a: string, b: string): number {
  return Math.round(
    (Date.parse(`${b}T00:00:00Z`) - Date.parse(`${a}T00:00:00Z`)) / 86_400_000,
  );
}
