import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { buildTrajectory, derivePhase, deriveExperience } from "./buildTrajectory.ts";

const NOW = new Date("2026-06-18T12:00:00Z");
const inDays = (n: number) => new Date(NOW.getTime() + n * 86400000).toISOString();

function traj(over: Partial<Parameters<typeof buildTrajectory>[0]> = {}) {
  return buildTrajectory({
    rolling7dMiles: 40,
    rolling28dMiles: 160,
    hardSessions7d: 1,
    fitnessTrend: null,
    activeInjuryCount: 0,
    injuryHistory: [],
    plan: null,
    now: NOW,
    ...over,
  }).framing;
}

Deno.test("trajectory: maintaining is the default (stable volume, no plan)", () => {
  assertEquals(traj(), "maintaining");
});

Deno.test("trajectory: returning when volume <50% of prior AND an active injury", () => {
  // priorBlockAvg = (70-5)/3 ≈ 21.7; 5 < 10.8 → returning (active injury present)
  assertEquals(traj({ rolling7dMiles: 5, rolling28dMiles: 70, activeInjuryCount: 1 }), "returning");
});

Deno.test("trajectory: returning via recently-resolved injury (no active)", () => {
  assertEquals(
    traj({
      rolling7dMiles: 5,
      rolling28dMiles: 70,
      activeInjuryCount: 0,
      injuryHistory: [{ status: "resolved", resolved_at: inDays(-10) }],
    }),
    "returning",
  );
});

Deno.test("trajectory: declining when volume <70% of prior and no active injury", () => {
  // priorBlockAvg = (70-10)/3 = 20; 10 < 14 → declining
  assertEquals(traj({ rolling7dMiles: 10, rolling28dMiles: 70 }), "declining");
});

Deno.test("trajectory: peaking when high volume + 2 hard + race within 8 weeks", () => {
  assertEquals(
    traj({
      rolling7dMiles: 40,
      rolling28dMiles: 160,
      hardSessions7d: 2,
      plan: { target_time_seconds: 10800, end_date: inDays(28) },
    }),
    "peaking",
  );
});

Deno.test("trajectory: NOT peaking when race is months out (>8 weeks)", () => {
  assertEquals(
    traj({
      rolling7dMiles: 40,
      rolling28dMiles: 160,
      hardSessions7d: 2,
      plan: { target_time_seconds: 10800, end_date: inDays(120) },
    }),
    "maintaining",
  );
});

Deno.test("trajectory: building when volume up >10% and fitness improving", () => {
  // priorBlockAvg = (80-30)/3 ≈ 16.7; recentVsPrior ≈ 1.8 > 1.1
  assertEquals(traj({ rolling7dMiles: 30, rolling28dMiles: 80, fitnessTrend: "improving" }), "building");
});

Deno.test("phase: off_season / recovery / build / peak / base", () => {
  const base = { weeklyAvg28d: 40, profile: { lifetime_weekly_avg: 40 } };
  assertEquals(derivePhase({ ...base, rolling7dMiles: 5, hardSessions7d: 0 }), "off_season");
  assertEquals(derivePhase({ ...base, rolling7dMiles: 20, hardSessions7d: 1 }), "recovery");
  assertEquals(derivePhase({ ...base, rolling7dMiles: 45, hardSessions7d: 3 }), "peak");
  assertEquals(derivePhase({ ...base, rolling7dMiles: 40, hardSessions7d: 2 }), "build");
  assertEquals(derivePhase({ ...base, rolling7dMiles: 30, hardSessions7d: 1 }), "base");
});

Deno.test("phase: historicalAvg falls back to weeklyAvg28d when no profile lifetime avg", () => {
  assertEquals(
    derivePhase({ rolling7dMiles: 5, hardSessions7d: 0, weeklyAvg28d: 40, profile: null }),
    "off_season",
  );
});

Deno.test("experience: profile value wins; else inferred from volume + easy pace", () => {
  assertEquals(
    deriveExperience({ profile: { experience_level: "elite" }, weeklyAvg28d: 5, easyPaceSec: 600 }),
    "elite",
  );
  assertEquals(deriveExperience({ profile: null, weeklyAvg28d: 55, easyPaceSec: 450 }), "advanced");
  assertEquals(deriveExperience({ profile: null, weeklyAvg28d: 55, easyPaceSec: 520 }), "intermediate"); // pace too slow for advanced
  assertEquals(deriveExperience({ profile: null, weeklyAvg28d: 30, easyPaceSec: 0 }), "intermediate");
  assertEquals(deriveExperience({ profile: null, weeklyAvg28d: 10, easyPaceSec: 0 }), "beginner");
  assertEquals(deriveExperience({ profile: null, weeklyAvg28d: 0, easyPaceSec: 0 }), null);
});
