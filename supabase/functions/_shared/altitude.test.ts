/**
 * Unit tests for the altitude adjustment model.
 *
 * Run: deno test --allow-all _shared/altitude.test.ts
 */

import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  altitudeAdjustmentPct,
  altitudeFields,
  MAX_ALTITUDE_ADJUSTMENT,
} from "./altitude.ts";

Deno.test("sea level and the floor credit nothing", () => {
  assertEquals(altitudeAdjustmentPct(0), 0);
  assertEquals(altitudeAdjustmentPct(500), 0);   // Austin
  assertEquals(altitudeAdjustmentPct(3000), 0);  // exactly the floor
});

Deno.test("linear above the floor: 1.5% per 1000ft", () => {
  assertEquals(altitudeAdjustmentPct(4000), 0.015);
  assertEquals(altitudeAdjustmentPct(5280), 0.0342);  // Denver
  assertEquals(altitudeAdjustmentPct(7000), 0.06);    // Flagstaff
});

Deno.test("capped at MAX_ALTITUDE_ADJUSTMENT", () => {
  assertEquals(altitudeAdjustmentPct(20000), MAX_ALTITUDE_ADJUSTMENT);
});

Deno.test("null / non-finite elevation credits nothing", () => {
  assertEquals(altitudeAdjustmentPct(null), 0);
  assertEquals(altitudeAdjustmentPct(undefined), 0);
  assertEquals(altitudeAdjustmentPct(NaN), 0);
});

Deno.test("altitudeFields: stored even below the floor, empty when unknown", () => {
  // Austin at ~150m: elevation recorded, adjustment zero — a stated fact.
  assertEquals(altitudeFields(150), { elevation_ft: 492, altitude_adjustment_pct: 0 });
  // Flagstaff at ~2100m.
  const flag = altitudeFields(2100);
  assertEquals(flag.elevation_ft, 6890);
  assertEquals(flag.altitude_adjustment_pct, 0.0584);
  // Unknown elevation leaves no trace.
  assertEquals(altitudeFields(null), {});
  assertEquals(altitudeFields(NaN), {});
});
