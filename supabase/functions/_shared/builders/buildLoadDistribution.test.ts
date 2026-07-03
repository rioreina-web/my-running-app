import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { buildLoadDistribution, type FeatureRow } from "./buildLoadDistribution.ts";

const NOW = new Date("2026-06-18T12:00:00Z");
const daysAgo = (n: number) => new Date(NOW.getTime() - n * 86400000).toISOString();
const WIN = { sevenDaysAgo: daysAgo(7), twentyEightDaysAgo: daysAgo(28), now: NOW };

function feat(over: Partial<FeatureRow> & { workout_date: string }): FeatureRow {
  return { easy_seconds: 0, moderate_seconds: 0, threshold_seconds: 0, hard_seconds: 0, intensity_score: 0, total_duration_seconds: 0, ...over };
}

Deno.test("empty → null distribution, null monotony/strain", () => {
  const r = buildLoadDistribution({ featureRows: [], ...WIN });
  assertEquals(r.loadDistribution, null);
  assertEquals(r.latestMonotony, null);
  assertEquals(r.latestStrain, null);
});

Deno.test("zone minutes + percentages over the 7d window", () => {
  const rows: FeatureRow[] = [
    feat({ workout_date: daysAgo(1), easy_seconds: 3600, threshold_seconds: 600, intensity_score: 5, total_duration_seconds: 4200, monotony_7d: 1.4, strain_7d: 320, effort_distribution: "polarized", hr_pace_efficiency: 0.9 }),
    feat({ workout_date: daysAgo(2), easy_seconds: 1800, intensity_score: 2, total_duration_seconds: 1800 }),
  ];
  const { loadDistribution: ld, latestMonotony, latestStrain } = buildLoadDistribution({ featureRows: rows, ...WIN });
  assert(ld !== null);
  assertEquals(ld!.minutes_7d.easy, 90);       // (3600+1800)/60
  assertEquals(ld!.minutes_7d.threshold, 10);  // 600/60
  // total7 = 6000s; easy 5400 → 90.0%, threshold 600 → 10.0%
  assertEquals(ld!.zone_pct_7d.easy, 90);
  assertEquals(ld!.zone_pct_7d.threshold, 10);
  // latest row (index 0) drives monotony/strain + passthroughs
  assertEquals(latestMonotony, 1.4);
  assertEquals(latestStrain, 320);
  assertEquals(ld!.effort_distribution, "polarized");
  // vxi7 = 5*4200/60 + 2*1800/60 = 350 + 60 = 410
  assertEquals(ld!.volume_x_intensity_7d, 410);
});

Deno.test("load_trend = holding when recent ≈ chronic", () => {
  // One equal-load row in each of weeks 0..7.
  const rows: FeatureRow[] = [];
  for (let w = 0; w < 8; w++) {
    rows.push(feat({ workout_date: daysAgo(w * 7 + 1), intensity_score: 10, total_duration_seconds: 600, easy_seconds: 600 }));
  }
  const { loadDistribution: ld } = buildLoadDistribution({ featureRows: rows, ...WIN });
  assertEquals(ld!.load_trend, "holding");
  assertEquals(ld!.load_vs_chronic_pct, 0);
});

Deno.test("load_trend = spiking when recent ≫ chronic", () => {
  const rows: FeatureRow[] = [];
  // recent weeks (0,1): big load
  for (const w of [0, 1]) rows.push(feat({ workout_date: daysAgo(w * 7 + 1), intensity_score: 10, total_duration_seconds: 1200, easy_seconds: 1200 }));
  // chronic weeks (2..7): small load
  for (const w of [2, 3, 4, 5, 6, 7]) rows.push(feat({ workout_date: daysAgo(w * 7 + 1), intensity_score: 10, total_duration_seconds: 600, easy_seconds: 600 }));
  const { loadDistribution: ld } = buildLoadDistribution({ featureRows: rows, ...WIN });
  assertEquals(ld!.load_trend, "spiking"); // recent 200 vs chronic 100 → +100%
});

Deno.test("load_trend null when there's no chronic baseline", () => {
  // Only recent (within 7d) rows → chronicWeekly 0 → null trend, null pct.
  const rows: FeatureRow[] = [feat({ workout_date: daysAgo(1), intensity_score: 10, total_duration_seconds: 1200, easy_seconds: 1200 })];
  const { loadDistribution: ld } = buildLoadDistribution({ featureRows: rows, ...WIN });
  assert(ld !== null);
  assertEquals(ld!.load_trend, null);
  assertEquals(ld!.load_vs_chronic_pct, null);
});

Deno.test("recovery_read: hard-day spacing + count over 28d", () => {
  const rows: FeatureRow[] = [
    feat({ workout_date: daysAgo(2), threshold_seconds: 300, easy_seconds: 600, intensity_score: 6, total_duration_seconds: 900 }),  // hard (≥240)
    feat({ workout_date: daysAgo(6), hard_seconds: 300, easy_seconds: 600, intensity_score: 8, total_duration_seconds: 900 }),       // hard
    feat({ workout_date: daysAgo(10), easy_seconds: 1800, intensity_score: 2, total_duration_seconds: 1800 }),                       // not hard
  ];
  const { loadDistribution: ld } = buildLoadDistribution({ featureRows: rows, ...WIN });
  assert(ld!.recovery_read !== null);
  assertEquals(ld!.recovery_read!.hard_sessions_28d, 2);
  assertEquals(ld!.recovery_read!.avg_days_between_hard, 4); // daysAgo(6)→daysAgo(2) = 4 days apart
});
