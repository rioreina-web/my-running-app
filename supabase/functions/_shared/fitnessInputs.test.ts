import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { mapWeather, numOrNull } from "./fitnessInputs.ts";
import { normalizeRaceTime } from "./raceNormalization.ts";

/**
 * `training_logs.weather_actual` carries TWO shapes, written by two different
 * backfills (G0-FINISH §2.2):
 *
 *   full   (open-meteo-archive-backfill): temp_f, dew_point_f, humidity,
 *                                         wind_mph, heat_category,
 *                                         adjustment_pct, composite_score
 *   sparse (open-meteo-backfill):         temp_f, dew_point_f          ← only
 *
 * The feared defect was that a reader preferring the stored `adjustment_pct`
 * would read the sparse shape as ZERO heat cost. `2026-04-12` is the only hot
 * race in the set AND the only one carrying the sparse shape, so a silent zero
 * there would have flattered every replay number in §1.1, §1.5 and §6.
 *
 * It does not happen, and these tests are why it stays that way: the predictor
 * never reads `adjustment_pct` at all. `WeatherInput` has exactly two fields,
 * and the correction is DERIVED from temp/dew every time. That is the
 * invariant under test — someone "optimizing" mapWeather to trust the stored
 * percentage would reintroduce the bug, and break these.
 */

const TEMP_F = 69.3;
const DEW_F = 67.6;

const SPARSE = { temp_f: TEMP_F, dew_point_f: DEW_F };
const FULL = {
  temp_f: TEMP_F,
  dew_point_f: DEW_F,
  humidity: 94,
  wind_mph: 5.1,
  heat_category: "moderate",
  adjustment_pct: 0.034,
  composite_score: 71.2,
};

// ── the mapping ─────────────────────────────────────────────────────────────

Deno.test("both weather_actual shapes map to the same WeatherInput", () => {
  assertEquals(mapWeather(SPARSE), mapWeather(FULL));
  assertEquals(mapWeather(SPARSE), { tempF: TEMP_F, dewPointF: DEW_F });
});

Deno.test("the stored adjustment_pct is not read — a wrong one changes nothing", () => {
  // If any reader ever starts trusting this field, this is the test that says so.
  const lying = { ...FULL, adjustment_pct: 0, composite_score: 0, heat_category: "cool" };
  assertEquals(mapWeather(lying), mapWeather(SPARSE));
});

Deno.test("weather is fail-CLOSED: a missing term yields null, never zero heat", () => {
  // null is "not on file" and is reported as missing downstream. Returning a
  // zero-heat reading instead would be a silent claim that the race was cool.
  assertEquals(mapWeather({ temp_f: TEMP_F }), null);
  assertEquals(mapWeather({ dew_point_f: DEW_F }), null);
  assertEquals(mapWeather({}), null);
  assertEquals(mapWeather(null), null);
  assertEquals(mapWeather("72F"), null);
});

Deno.test("string-typed jsonb numbers still parse; junk does not", () => {
  assertEquals(mapWeather({ temp_f: "69.3", dew_point_f: "67.6" }), { tempF: TEMP_F, dewPointF: DEW_F });
  assertEquals(mapWeather({ temp_f: "warm", dew_point_f: DEW_F }), null);
  assertEquals(numOrNull("NaN"), null);
});

// ── the correction itself ───────────────────────────────────────────────────

const conditionsFrom = (raw: unknown) => {
  const wx = mapWeather(raw);
  return wx ? { tempF: wx.tempF, dewPointF: wx.dewPointF, elevationGainM: null } : null;
};

Deno.test("THE §2.2 CASE — both shapes produce the SAME non-zero correction", () => {
  const raw = 1982; // 33:02, the 2026-04-12 10K
  const sparse = normalizeRaceTime(raw, "tenK", conditionsFrom(SPARSE));
  const full = normalizeRaceTime(raw, "tenK", conditionsFrom(FULL));

  assertEquals(sparse.neutralSeconds, full.neutralSeconds);
  // The whole point: 69.3°F at 67.6° dew is NOT a neutral day. A zero here is
  // the silent failure this test exists to catch.
  assert(sparse.neutralSeconds < raw, `expected a correction, got ${sparse.neutralSeconds} vs ${raw}`);
  assert(
    raw - sparse.neutralSeconds > 20,
    `69.3/67.6 should cost more than 20s over a 10K, got ${raw - sparse.neutralSeconds}s`,
  );
});

Deno.test("no weather on file is reported as missing, not corrected to itself", () => {
  const raw = 1982;
  const none = normalizeRaceTime(raw, "tenK", conditionsFrom({}));
  assertEquals(none.neutralSeconds, raw);
  assert(
    none.missing.some((m) => m.includes("weather")),
    `expected weather in missing[], got ${JSON.stringify(none.missing)}`,
  );
});
