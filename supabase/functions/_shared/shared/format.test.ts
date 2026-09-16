import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { formatPace, formatTime, formatTimeDelta } from "./format.ts";

Deno.test("formatPace: fractional input that rounds the seconds part to 60 carries to the minute", () => {
  // 479.6 → round to 480 → 8:00, NOT 7:60.
  assertEquals(formatPace(479.6), "8:00");
  assertEquals(formatPace(479.4), "7:59");
});

Deno.test("formatPace: ordinary integer and fractional inputs", () => {
  assertEquals(formatPace(450), "7:30");
  assertEquals(formatPace(305), "5:05");
  assertEquals(formatPace(60), "1:00");
});

Deno.test("formatTime: M:SS under an hour, H:MM:SS over", () => {
  assertEquals(formatTime(90), "1:30");
  assertEquals(formatTime(3 * 3600 + 8 * 60 + 5), "3:08:05");
});

Deno.test("formatTime: non-positive / falsy → '?'", () => {
  assertEquals(formatTime(0), "?");
  assertEquals(formatTime(-10), "?");
});

Deno.test("formatTimeDelta: sign, sub-minute, and over-minute formatting", () => {
  assertEquals(formatTimeDelta(0), "same");
  assertEquals(formatTimeDelta(45), "45s slower");
  assertEquals(formatTimeDelta(-30), "30s faster");
  assertEquals(formatTimeDelta(99), "1:39 slower");
  assertEquals(formatTimeDelta(-(2 * 60 + 5)), "2:05 faster");
});
