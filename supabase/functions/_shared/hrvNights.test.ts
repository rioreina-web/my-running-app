/**
 * Tests for the Junction/Vital HRV night aggregation.
 *
 * Run: deno test _shared/hrvNights.test.ts
 */

import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { hrvNightDate, nightlyHrv } from "./hrvNights.ts";

// Austin, UTC-5 (CDT) — the athlete's timezone. offset is seconds EAST of UTC.
const CDT = -5 * 3600;

/** A reading at a wall-clock time in a given zone, expressed as its UTC instant. */
function reading(localIso: string, offsetSec: number, value: number) {
  const utcMs = Date.parse(`${localIso}Z`) - offsetSec * 1000;
  return { timestamp: new Date(utcMs).toISOString(), timezone_offset: offsetSec, value };
}

Deno.test("a night that straddles UTC midnight files on the morning it ended", () => {
  // 23:40 local Aug 12 is 04:40 UTC Aug 13 — the raw UTC date is already wrong,
  // and the night ends on the morning of Aug 13 either way.
  assertEquals(hrvNightDate(reading("2026-08-12T23:40:00", CDT, 0).timestamp, CDT), "2026-08-13");
  assertEquals(hrvNightDate(reading("2026-08-13T03:10:00", CDT, 0).timestamp, CDT), "2026-08-13");
  assertEquals(hrvNightDate(reading("2026-08-13T06:55:00", CDT, 0).timestamp, CDT), "2026-08-13");
});

Deno.test("one night of readings collapses to a single averaged row", () => {
  const samples = [
    reading("2026-08-12T23:45:00", CDT, 40),
    reading("2026-08-13T00:50:00", CDT, 50),
    reading("2026-08-13T02:30:00", CDT, 60),
    reading("2026-08-13T05:15:00", CDT, 50),
  ];
  const out = nightlyHrv(samples);
  assertEquals(out.size, 1);
  assertEquals(out.get("2026-08-13"), 50);
});

Deno.test("consecutive nights stay separate", () => {
  const out = nightlyHrv([
    reading("2026-08-12T23:45:00", CDT, 40),
    reading("2026-08-13T04:00:00", CDT, 44),
    reading("2026-08-13T23:30:00", CDT, 60),
    reading("2026-08-14T03:00:00", CDT, 64),
  ]);
  assertEquals([...out.keys()].sort(), ["2026-08-13", "2026-08-14"]);
  assertEquals(out.get("2026-08-13"), 42);
  assertEquals(out.get("2026-08-14"), 62);
});

Deno.test("bucketing on raw UTC would split this night — the offset is what prevents it", () => {
  const samples = [
    reading("2026-08-12T23:45:00", CDT, 40), // 04:45 UTC Aug 13
    reading("2026-08-13T05:15:00", CDT, 60), // 10:15 UTC Aug 13
  ];
  // Same UTC date here, but the evening reading's LOCAL date is Aug 12. Bucketing
  // on local date alone (no +12h shift) would file it under Aug 12 and split the night.
  const naiveLocalDates = new Set(
    samples.map((s) => new Date(Date.parse(s.timestamp as string) + CDT * 1000).toISOString().slice(0, 10)),
  );
  assertEquals(naiveLocalDates.size, 2);
  assertEquals(nightlyHrv(samples).size, 1);
});

Deno.test("a positive (east-of-UTC) offset works the same way", () => {
  const CEST = 2 * 3600;
  const out = nightlyHrv([
    reading("2026-08-12T23:50:00", CEST, 30), // 21:50 UTC Aug 12
    reading("2026-08-13T05:20:00", CEST, 40), // 03:20 UTC Aug 13
  ]);
  assertEquals(out.size, 1);
  assertEquals(out.get("2026-08-13"), 35);
});

Deno.test("junk samples are skipped, not averaged in", () => {
  const good = reading("2026-08-13T02:00:00", CDT, 50);
  const out = nightlyHrv([
    good,
    { timestamp: good.timestamp, timezone_offset: CDT, value: null },
    { timestamp: good.timestamp, timezone_offset: CDT, value: "48" },
    { timestamp: good.timestamp, timezone_offset: CDT, value: Number.NaN },
    { timestamp: "not a date", timezone_offset: CDT, value: 999 },
    { timezone_offset: CDT, value: 999 },
  ]);
  assertEquals(out.size, 1);
  assertEquals(out.get("2026-08-13"), 50);
});

Deno.test("a missing timezone_offset degrades to UTC rather than dropping the night", () => {
  const out = nightlyHrv([
    { timestamp: "2026-08-13T02:00:00Z", value: 50 },
    { timestamp: "2026-08-13T03:00:00Z", timezone_offset: null, value: 60 },
  ]);
  assertEquals(out.get("2026-08-13"), 55);
});

Deno.test("no samples, or a non-array payload, yields no rows", () => {
  assertEquals(nightlyHrv([]).size, 0);
  assertEquals(nightlyHrv(null).size, 0);
  assertEquals(nightlyHrv(undefined).size, 0);
  assertEquals(nightlyHrv({ data: [] }).size, 0);
});

Deno.test("the mean is rounded to 0.1 ms", () => {
  const out = nightlyHrv([
    reading("2026-08-13T02:00:00", CDT, 41),
    reading("2026-08-13T03:00:00", CDT, 42),
    reading("2026-08-13T04:00:00", CDT, 44),
  ]);
  assertEquals(out.get("2026-08-13"), 42.3);
});
