/**
 * buildLoadDistribution — the v2 volume×intensity load model (the ACWR
 * replacement). Pure function extracted verbatim from `rebuildAthleteState`
 * (refactor §3). Aggregates time-in-zone from `workout_features`, the single
 * pace-weighted load number, the WS3 load trend vs an 8-week chronic baseline,
 * and the recovery read (hard-day spacing + down-week).
 *
 * Returns `loadDistribution` plus `latestMonotony`/`latestStrain`, which the
 * caller also writes to the top-level state fields.
 */

export type FeatureRow = Record<string, unknown>;

export interface LoadDistribution {
  window_days: number;
  volume_x_intensity_7d: number;
  volume_x_intensity_28d: number;
  minutes_7d: { easy: number; moderate: number; threshold: number; hard: number };
  minutes_28d: { easy: number; moderate: number; threshold: number; hard: number };
  zone_pct_7d: { easy: number; moderate: number; threshold: number; hard: number };
  effort_distribution: string | null;
  intensity_score_latest: number | null;
  monotony_7d: number | null;
  strain_7d: number | null;
  hr_pace_efficiency: number | null;
  load_trend: "building" | "holding" | "spiking" | "backing_off" | null;
  chronic_window_days: number;
  load_vs_chronic_pct: number | null;
  recovery_read: {
    avg_days_between_hard: number | null;
    hard_sessions_28d: number;
    down_week: boolean;
  } | null;
}

export interface LoadDistributionResult {
  loadDistribution: LoadDistribution | null;
  latestMonotony: number | null;
  latestStrain: number | null;
}

export function buildLoadDistribution(input: {
  /** workout_features rows over the 84-day window, ordered workout_date desc. */
  featureRows: FeatureRow[];
  sevenDaysAgo: string;
  twentyEightDaysAgo: string;
  now: Date;
}): LoadDistributionResult {
  const { featureRows, sevenDaysAgo, twentyEightDaysAgo, now } = input;

  const sumZones = (rows: FeatureRow[]) => {
    const z = { easy: 0, moderate: 0, threshold: 0, hard: 0 };
    for (const r of rows) {
      z.easy += Number(r.easy_seconds ?? 0);
      z.moderate += Number(r.moderate_seconds ?? 0);
      z.threshold += Number(r.threshold_seconds ?? 0);
      z.hard += Number(r.hard_seconds ?? 0);
    }
    return z;
  };
  // featureRows now spans 84 days (WS3) — slice explicitly per window.
  const rows7 = featureRows.filter((r) => String(r.workout_date ?? "") >= sevenDaysAgo);
  const rows28 = featureRows.filter((r) => String(r.workout_date ?? "") >= twentyEightDaysAgo);
  const z7 = sumZones(rows7);
  const z28 = sumZones(rows28);
  const toMin = (s: number) => Math.round(s / 60);
  const total7 = z7.easy + z7.moderate + z7.threshold + z7.hard;
  const total28 = z28.easy + z28.moderate + z28.threshold + z28.hard;
  const pct = (part: number, total: number) =>
    total > 0 ? Math.round((part / total) * 1000) / 10 : 0;
  const latestF = featureRows[0] as FeatureRow | undefined;
  const num = (v: unknown): number | null => (v == null ? null : Number(v));
  const latestMonotony = num(latestF?.monotony_7d);
  const latestStrain = num(latestF?.strain_7d);
  // ── Volume × Intensity total — the single pace-weighted load number ──
  // Σ(intensity_score × duration / 60) per workout = weighted minutes.
  // This is what "matches paces to volume": a hard mile counts ~5× an
  // easy mile (intensity_score is the per-segment pace-weighted average).
  // Same math as computeWeightedLoadForLog.
  const sumVolumeXIntensity = (rows: FeatureRow[]) =>
    rows.reduce((s, r) => {
      const isc = Number(r.intensity_score ?? 0);
      const durSec = Number(r.total_duration_seconds ?? 0);
      return s + (isc > 0 && durSec > 0 ? (isc * durSec) / 60 : 0);
    }, 0);
  const vxi7 = Math.round(sumVolumeXIntensity(rows7));
  const vxi28 = Math.round(sumVolumeXIntensity(rows28));

  // ── WS3: load trend + recovery read (the ACWR replacement) ──
  // Weekly weighted-load over 12 weeks; "recent" = last 2 weeks averaged,
  // "chronic" = the prior 6 weeks (weeks 3–8) averaged. The trend is the
  // recent week vs that chronic norm, in plain language.
  const CHRONIC_WINDOW_DAYS = 56; // 8 weeks
  const weekLoad = (weekIdx: number): number => {
    const start = new Date(now.getTime() - (weekIdx + 1) * 7 * 86400000).toISOString();
    const end = new Date(now.getTime() - weekIdx * 7 * 86400000).toISOString();
    return sumVolumeXIntensity(
      featureRows.filter((r) => {
        const d = String(r.workout_date ?? "");
        return d >= start && d < end;
      }),
    );
  };
  const recentWeekly = (weekLoad(0) + weekLoad(1)) / 2; // last 2 weeks
  const chronicWeeks = [2, 3, 4, 5, 6, 7].map(weekLoad); // weeks 3–8
  const chronicWeekly = chronicWeeks.reduce((s, w) => s + w, 0) / chronicWeeks.length;
  const loadVsChronicPct = chronicWeekly > 0
    ? Math.round(((recentWeekly - chronicWeekly) / chronicWeekly) * 100)
    : null;
  let loadTrend: "building" | "holding" | "spiking" | "backing_off" | null = null;
  if (chronicWeekly > 0 && recentWeekly >= 0) {
    if (loadVsChronicPct! >= 40) loadTrend = "spiking";
    else if (loadVsChronicPct! >= 12) loadTrend = "building";
    else if (loadVsChronicPct! <= -25) loadTrend = "backing_off";
    else loadTrend = "holding";
  }
  // Recovery read: hard-day spacing over 28d + whether this is a down week.
  const QUALITY_FLOOR_SEC = 240;
  const hardDates = rows28
    .filter((r) => Number(r.threshold_seconds ?? 0) + Number(r.hard_seconds ?? 0) >= QUALITY_FLOOR_SEC)
    .map((r) => String(r.workout_date ?? "").slice(0, 10))
    .filter(Boolean)
    .sort();
  let avgDaysBetweenHard: number | null = null;
  if (hardDates.length >= 2) {
    let gapSum = 0;
    for (let i = 1; i < hardDates.length; i++) {
      gapSum += (new Date(hardDates[i]).getTime() - new Date(hardDates[i - 1]).getTime()) / 86400000;
    }
    avgDaysBetweenHard = Math.round((gapSum / (hardDates.length - 1)) * 10) / 10;
  }
  const downWeek = loadVsChronicPct != null && loadVsChronicPct <= -30;
  const recoveryRead = total28 > 0 ? {
    avg_days_between_hard: avgDaysBetweenHard,
    hard_sessions_28d: hardDates.length,
    down_week: downWeek,
  } : null;
  const loadDistribution: LoadDistribution | null = total28 > 0 ? {
    window_days: 28,
    // The single number: volume scaled by pace intensity (weighted minutes).
    volume_x_intensity_7d: vxi7,
    volume_x_intensity_28d: vxi28,
    minutes_7d: { easy: toMin(z7.easy), moderate: toMin(z7.moderate), threshold: toMin(z7.threshold), hard: toMin(z7.hard) },
    minutes_28d: { easy: toMin(z28.easy), moderate: toMin(z28.moderate), threshold: toMin(z28.threshold), hard: toMin(z28.hard) },
    zone_pct_7d: {
      easy: pct(z7.easy, total7),
      moderate: pct(z7.moderate, total7),
      threshold: pct(z7.threshold, total7),
      hard: pct(z7.hard, total7),
    },
    effort_distribution: (latestF?.effort_distribution as string) ?? null,
    intensity_score_latest: num(latestF?.intensity_score),
    monotony_7d: latestMonotony,
    strain_7d: latestStrain,
    hr_pace_efficiency: num(latestF?.hr_pace_efficiency),
    load_trend: loadTrend,
    chronic_window_days: CHRONIC_WINDOW_DAYS,
    load_vs_chronic_pct: loadVsChronicPct,
    recovery_read: recoveryRead,
  } : null;

  return { loadDistribution, latestMonotony, latestStrain };
}
