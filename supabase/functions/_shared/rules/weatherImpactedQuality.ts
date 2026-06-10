/**
 * Rule 4 — weather_impacted_quality
 *
 * Fires when the athlete's most recent quality session (last 3 days) was hit
 * with significant heat AND they reported subjective struggle, AND the heat
 * penalty was real (not just nominal).
 *
 * Conditions (all must be true):
 *   - Most recent quality session in last 3 days
 *   - Quality type: tempo / threshold / interval / long_run / MP / race
 *   - Weather actual is present
 *   - Dewpoint >= 65°F (severe-impact threshold for runners)
 *   - Heat-adjusted pace delta >= 10 sec/mi (real performance impact)
 *   - Athlete mood in { tired, struggling, injured }
 *
 * → severity: med, action: suggest_extra_recovery
 *
 * Why these thresholds:
 *   - Dewpoint dominates heat penalty for runners; temp alone misses the cost
 *     of humid 75°F more than dry 90°F. 65°F dewpoint is the threshold where
 *     fit runners start measurably losing pace at MP+ effort.
 *   - 10 sec/mi delta is "real" — below that, attributing the slowdown to
 *     heat introduces too much noise (could be fatigue, terrain, etc.).
 *   - Subjective struggle is the gating signal. Athlete who ran the same heat
 *     and felt fine doesn't need a recovery push.
 *
 * Spec: docs/specs/coachable_moment.md, rule 4
 */

import {
  LOW_MOOD_LABELS,
  QUALITY_WORKOUT_TOKENS,
  type CoachableMomentInsert,
  type RuleContext,
  type RuleEvaluator,
  type WeatherActual,
  type WeatherAwareTrainingLogRow,
} from "./types.ts";

const RECENT_WINDOW_DAYS = 3;
const SEVERE_DEWPOINT_F = 65;
const REAL_HEAT_DELTA_SEC_PER_MILE = 10;

function daysAgo(now: Date, days: number): Date {
  const d = new Date(now);
  d.setUTCDate(d.getUTCDate() - days);
  return d;
}

function isQualityType(workoutType: string | null | undefined): boolean {
  if (!workoutType) return false;
  const t = workoutType.toLowerCase();
  return QUALITY_WORKOUT_TOKENS.some((token) => t.includes(token));
}

function readNumber(value: unknown): number | null {
  if (value === null || value === undefined) return null;
  const n = typeof value === "number" ? value : Number(value);
  return Number.isFinite(n) ? n : null;
}

function extractWeatherFields(
  raw: WeatherAwareTrainingLogRow["weather_actual"],
): { dewpoint: number | null; temp: number | null } {
  if (!raw || typeof raw !== "object") return { dewpoint: null, temp: null };
  const w = raw as WeatherActual;
  // Defensive about field-name variants — different ingestion paths may
  // use _f suffix or not, may store as dewpoint or dew_point, etc.
  const dewpoint =
    readNumber(w.dewpoint_f) ??
    readNumber((w as Record<string, unknown>).dewpoint) ??
    readNumber((w as Record<string, unknown>).dew_point) ??
    readNumber((w as Record<string, unknown>).dewPoint);
  const temp =
    readNumber(w.temp_f) ??
    readNumber((w as Record<string, unknown>).temp) ??
    readNumber((w as Record<string, unknown>).temperature) ??
    readNumber((w as Record<string, unknown>).temperature_f);
  return { dewpoint, temp };
}

export const weatherImpactedQuality: RuleEvaluator = (
  ctx: RuleContext,
): CoachableMomentInsert | null => {
  const { athleteUserId, coachId, now, logs } = ctx;

  // ─── Find the most recent quality session in the recent window ──────────
  const cutoff = daysAgo(now, RECENT_WINDOW_DAYS);

  // logs are passed in newest-first; find first match
  const candidate = logs.find((log) => {
    if (!log.workout_date) return false;
    const d = new Date(log.workout_date);
    if (d < cutoff || d > now) return false;
    return isQualityType(log.workout_type);
  });

  if (!candidate) return null;

  // ─── Weather gating ──────────────────────────────────────────────────────
  const { dewpoint, temp } = extractWeatherFields(candidate.weather_actual);
  if (dewpoint === null || dewpoint < SEVERE_DEWPOINT_F) return null;

  const heatDelta = readNumber(
    candidate.weather_adjusted_pace_delta_seconds_per_mile,
  );
  if (heatDelta === null || heatDelta < REAL_HEAT_DELTA_SEC_PER_MILE) return null;

  // ─── Subjective gating ───────────────────────────────────────────────────
  const mood = (candidate.mood ?? "").toLowerCase().trim();
  if (!LOW_MOOD_LABELS.has(mood)) return null;

  // ─── Build moment ────────────────────────────────────────────────────────
  const dateStr = candidate.workout_date
    ? new Date(candidate.workout_date).toISOString().slice(0, 10)
    : "recent";
  const tempPart = temp !== null ? `${Math.round(temp)}°F / ` : "";
  const workoutLabel = candidate.workout_type ?? "quality";

  const summary =
    `${dateStr} ${workoutLabel} session ran in ${tempPart}${Math.round(dewpoint)}°F dewpoint ` +
    `with ~${Math.round(heatDelta)}s/mi heat penalty. ` +
    `Athlete reported "${mood}" — honest physiology, not a fitness regression. ` +
    `Recommend protecting recovery: 24-48h easy buffer, defer next quality if residual fatigue. ` +
    `Source: 1 voice log, 1 workout.`;

  return {
    athlete_user_id: athleteUserId,
    coach_id: coachId,
    rule_id: "weather_impacted_quality",
    severity: "med",
    action_type: "suggest_extra_recovery",
    summary,
    source_log_ids: [candidate.id],
  };
};
