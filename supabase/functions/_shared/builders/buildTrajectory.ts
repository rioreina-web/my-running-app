/**
 * buildTrajectory — ego-safe trajectory framing, training phase, and experience
 * inference. Three pure functions extracted verbatim from `rebuildAthleteState`
 * (refactor §3, builder split). Behavior is identical to the inline logic.
 */

export interface InjuryHistoryRow {
  status: string;
  resolved_at?: string | null;
}

export interface TrajectoryPlan {
  target_time_seconds?: number | null;
  end_date?: string | null;
}

export interface TrajectoryInput {
  rolling7dMiles: number;
  rolling28dMiles: number;
  hardSessions7d: number;
  fitnessTrend: string | null;
  /** Count of currently-active/monitoring injuries. */
  activeInjuryCount: number;
  injuryHistory: InjuryHistoryRow[];
  plan: TrajectoryPlan | null;
  now: Date;
}

/**
 * Returns the ego-safe trajectory framing + a one-line rationale.
 * Rules (conservative; bias toward "maintaining" when uncertain):
 *   returning: recent vol < 50% of prior AND (recent injury resolved OR active)
 *   declining: recent vol < 70% of prior AND no active injury
 *   peaking:   recent vol ≥ 90% of prior AND ≥2 hard/wk AND race in (0, 8wk]
 *   building:  recent vol > 110% of prior AND fitness improving
 *   maintaining: default
 * Prior 3-week weekly average = (28d total − last 7d) / 3 weeks.
 */
export function buildTrajectory(
  input: TrajectoryInput,
): { framing: string; reason: string } {
  const { rolling7dMiles, rolling28dMiles, hardSessions7d, fitnessTrend, activeInjuryCount, injuryHistory, plan, now } = input;

  const priorBlockAvg = (rolling28dMiles - rolling7dMiles) / 3;
  const recentVsPrior = priorBlockAvg > 0 ? rolling7dMiles / priorBlockAvg : 1;
  const recentlyResolvedInjury = injuryHistory.some((i) =>
    i.status === "resolved" && i.resolved_at &&
    new Date(i.resolved_at).getTime() > now.getTime() - 45 * 86400000
  );
  const hasActiveInjury = activeInjuryCount > 0;

  let framing = "maintaining";
  let reason = "volume stable near recent average";
  if (rolling7dMiles < priorBlockAvg * 0.5 && (recentlyResolvedInjury || hasActiveInjury)) {
    framing = "returning";
    reason = `volume at ${Math.round(rolling7dMiles)}mi is ${Math.round(recentVsPrior * 100)}% of recent avg; ${hasActiveInjury ? "active" : "recently resolved"} injury`;
  } else if (rolling7dMiles < priorBlockAvg * 0.7 && !hasActiveInjury) {
    framing = "declining";
    reason = `volume dropped to ${Math.round(recentVsPrior * 100)}% of recent avg, no injury reason`;
  } else if (
    recentVsPrior >= 0.9 && hardSessions7d >= 2 && plan?.target_time_seconds &&
    // Race must be in the future AND within 8 weeks — otherwise it's a build,
    // not a peak. (v1 fired "peaking" for any active goal, race months out.)
    plan?.end_date &&
    (new Date(plan.end_date as string).getTime() - now.getTime()) > 0 &&
    (new Date(plan.end_date as string).getTime() - now.getTime()) <= 56 * 86400000
  ) {
    const weeksOut = Math.max(
      1,
      Math.round((new Date(plan.end_date as string).getTime() - now.getTime()) / (7 * 86400000)),
    );
    framing = "peaking";
    reason = `high volume + ${hardSessions7d} hard sessions, race ~${weeksOut}wk out`;
  } else if (recentVsPrior > 1.1 && fitnessTrend === "improving") {
    framing = "building";
    reason = `volume up ${Math.round((recentVsPrior - 1) * 100)}% vs recent avg, fitness improving`;
  }
  return { framing, reason };
}

/**
 * Derives the training phase from volume + quality. `historicalAvg` falls back
 * to the 28-day weekly average when the profile has no lifetime average.
 */
export function derivePhase(input: {
  rolling7dMiles: number;
  hardSessions7d: number;
  weeklyAvg28d: number;
  profile: Record<string, unknown> | null;
}): string {
  const { rolling7dMiles, hardSessions7d, weeklyAvg28d, profile } = input;
  const historicalAvg = (profile as Record<string, unknown> | null)?.lifetime_weekly_avg as number
    ?? weeklyAvg28d;
  if (rolling7dMiles < historicalAvg * 0.3 && hardSessions7d === 0) {
    return "off_season";
  } else if (rolling7dMiles < historicalAvg * 0.6 && hardSessions7d <= 1) {
    return "recovery";
  } else if (hardSessions7d >= 3 && rolling7dMiles >= historicalAvg * 1.1) {
    return "peak";
  } else if (rolling7dMiles >= historicalAvg * 1.0 && hardSessions7d >= 2) {
    return "build";
  }
  return "base";
}

/**
 * Experience level: the profile value when present, else inferred from volume
 * + easy pace. Returns null when there's no profile value and no volume signal.
 */
export function deriveExperience(input: {
  profile: { experience_level?: unknown } | null;
  weeklyAvg28d: number;
  easyPaceSec: number;
}): string | null {
  const { profile, weeklyAvg28d, easyPaceSec } = input;
  let derived = (profile?.experience_level as string) ?? null;
  if (!derived) {
    if (weeklyAvg28d >= 50 && easyPaceSec > 0 && easyPaceSec < 480) {
      derived = "advanced";
    } else if (weeklyAvg28d >= 25) {
      derived = "intermediate";
    } else if (weeklyAvg28d > 0) {
      derived = "beginner";
    }
  }
  return derived;
}
