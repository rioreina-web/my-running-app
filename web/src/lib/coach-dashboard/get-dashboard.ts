import "server-only";

import type {
  DashboardData,
  DashboardDay,
  MoodSummary,
  Mood,
  NiggleGroup,
} from "./types";
import {
  mayaAcwr,
  mayaDays,
  mayaHeader,
  mayaMoments,
  mayaOverlayRead,
  mayaProgression,
  mayaResolvedNiggles,
  mayaWatchList,
  mayaWeeklyVolume,
} from "./fixtures";

const MOOD_ORDER: Mood[] = [
  "energized",
  "positive",
  "neutral",
  "tired",
  "struggling",
  "injured",
];

/**
 * Group the daily body-mentions into per-area niggle rows (verbatim quote,
 * count, recency, recurrence flag), then append any resolved items from
 * outside the window. Recurrence = 3+ mentions (mirrors the watch-list rule).
 *
 * In production this is `body_mentions` grouped by `body_area` joined to
 * `athlete_state_niggle_recurrence` and `niggle_resolutions` — see the spec's
 * §2.4 and §3. Same output shape, so the components don't change.
 */
function deriveNiggles(days: DashboardDay[]): NiggleGroup[] {
  const byArea = new Map<string, DashboardDay[]>();
  for (const d of days) {
    if (!d.niggle) continue;
    const arr = byArea.get(d.niggle.area);
    if (arr) arr.push(d);
    else byArea.set(d.niggle.area, [d]);
  }

  const groups: NiggleGroup[] = [];
  for (const [area, list] of byArea) {
    // list is oldest → newest (days is ordered)
    const latest = list[list.length - 1];
    groups.push({
      area,
      mentions: list.length,
      latestDate: latest.dateLabel,
      latestQuote: latest.niggle!.quote,
      otherDates: list.slice(0, -1).map((d) => d.dateLabel),
      recurrence: list.length >= 3,
      linkDayId: latest.id,
    });
  }

  groups.sort((a, b) => b.mentions - a.mentions);
  return [...groups, ...mayaResolvedNiggles];
}

/**
 * Last 28 days as a mood strip, plus a whole-window distribution.
 * In production: `training_logs.mood` over the window (a TEXT label — never
 * coerced to a number).
 */
function deriveMood(days: DashboardDay[]): MoodSummary {
  const strip = days.slice(-28).map((d) => ({
    date: d.date,
    dateLabel: d.dateLabel,
    mood: d.mood,
  }));

  const counts = new Map<Mood, number>();
  for (const d of days) counts.set(d.mood, (counts.get(d.mood) ?? 0) + 1);
  const distribution = MOOD_ORDER.filter((m) => counts.get(m)).map((m) => ({
    mood: m,
    count: counts.get(m)!,
  }));

  return {
    strip,
    distribution,
    caption:
      "**Mostly positive.** The two **struggling** days landed on the two hardest sessions. No injured days this cycle.",
  };
}

/**
 * The single entry point the dashboard reads from. Returns everything the UI
 * needs for one athlete.
 *
 * TODAY: returns Maya fixtures (no DB). The `athleteId` is accepted so the
 * signature already matches the real read.
 *
 * TO WIRE LIVE (Phase 1 data): replace the fixture assembly below with the
 * reads the existing page already does, plus the two new ones the spec calls
 * out. Sketch, using the server client (`@/lib/supabase/server`):
 *
 *   const supabase = await createClient();
 *   // gate: coach owns a plan_template the athlete is active-subscribed to
 *   //   (athlete_plan_subscriptions → plan_templates.coach_id === current_coach_id())
 *   const [{ data: state }, { data: logs }, { data: mentions }, { data: moments }] =
 *     await Promise.all([
 *       supabase.from("athlete_state").select(
 *         "fitness_prediction, fitness_trend, fitness_vs_6mo_ago_label, acwr, monotony_7d, strain_7d, last_mood, mood_trend, confirmed_races, goal_time_seconds"
 *       ).eq("user_id", athleteId).maybeSingle(),                         // service-role path
 *       supabase.from("training_logs").select(
 *         "id, workout_date, workout_distance_miles, workout_pace_per_mile, workout_type, mood, cleaned_notes"
 *       ).eq("user_id", athleteId).gte("workout_date", windowStart).order("workout_date"),
 *       supabase.from("body_mentions").select(                            // verify coach RLS / service-role (spec §3)
 *         "id, training_log_id, body_area, verbatim_quote, mentioned_at"
 *       ).eq("user_id", athleteId).gte("mentioned_at", ninetyDaysAgo),
 *       supabase.from("coachable_moments").select(
 *         "id, rule_id, severity, summary, source_log_ids, triggered_at"
 *       ).eq("athlete_user_id", athleteId).eq("status", "open"),
 *     ]);
 *   // then map each result into the DashboardData shape below (the mapping is
 *   // 1:1 with the fixtures — DashboardDay ← training_logs + scheduled_workouts
 *   // prescription, FitnessPrediction ← athlete_state.fitness_prediction, etc.)
 *
 * Because the components render only from DashboardData, none of them change
 * when this function starts returning real rows.
 */
export async function getAthleteDashboard(
  athleteId: string,
): Promise<DashboardData> {
  void athleteId; // fixtures ignore it; the real read keys on it

  return {
    header: mayaHeader,
    watchList: mayaWatchList,
    moments: mayaMoments,
    days: mayaDays,
    overlayRead: mayaOverlayRead,
    progression: mayaProgression,
    weeklyVolume: mayaWeeklyVolume,
    acwr: mayaAcwr,
    niggles: deriveNiggles(mayaDays),
    mood: deriveMood(mayaDays),
  };
}
