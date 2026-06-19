import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { buildMoodTrend, type MoodCheckIn, type MoodLogRow } from "./buildMoodTrend.ts";

const ci = (mood: string, at: string): MoodCheckIn => ({ mood, created_at: at });

Deno.test("null below 4 sources (guards the empty-older-window bug)", () => {
  assertEquals(buildMoodTrend([], []), null);
  assertEquals(
    buildMoodTrend([ci("tired", "2026-06-03"), ci("tired", "2026-06-02"), ci("tired", "2026-06-01")], []),
    null,
  );
});

Deno.test("improving: recent 3 well above older", () => {
  const checkIns = [
    ci("energized", "2026-06-06"),
    ci("energized", "2026-06-05"),
    ci("positive", "2026-06-04"),
    ci("struggling", "2026-06-03"),
    ci("tired", "2026-06-02"),
  ];
  assertEquals(buildMoodTrend(checkIns, []), "improving");
});

Deno.test("declining: recent 3 well below older", () => {
  const checkIns = [
    ci("struggling", "2026-06-06"),
    ci("tired", "2026-06-05"),
    ci("tired", "2026-06-04"),
    ci("energized", "2026-06-03"),
    ci("positive", "2026-06-02"),
  ];
  assertEquals(buildMoodTrend(checkIns, []), "declining");
});

Deno.test("stable: recent and older within ±0.5", () => {
  const checkIns = [
    ci("neutral", "2026-06-06"),
    ci("neutral", "2026-06-05"),
    ci("neutral", "2026-06-04"),
    ci("neutral", "2026-06-03"),
  ];
  assertEquals(buildMoodTrend(checkIns, []), "stable");
});

Deno.test("voice-log moods are unioned with check-ins and sorted by date desc", () => {
  // 3 check-ins + 1 voice-log = 4 sources. Most recent 3 are positive-ish,
  // oldest (the log) is low → improving.
  const checkIns = [
    ci("energized", "2026-06-06"),
    ci("positive", "2026-06-05"),
    ci("positive", "2026-06-04"),
  ];
  const logs: MoodLogRow[] = [{ mood: "struggling", workout_date: "2026-06-01" }];
  assertEquals(buildMoodTrend(checkIns, logs), "improving");
});

Deno.test("logs without mood or date are ignored", () => {
  const checkIns = [
    ci("neutral", "2026-06-06"),
    ci("neutral", "2026-06-05"),
    ci("neutral", "2026-06-04"),
  ];
  const logs: MoodLogRow[] = [
    { mood: null, workout_date: "2026-06-03" },
    { mood: "tired", workout_date: undefined },
  ];
  // Only 3 valid sources → null.
  assertEquals(buildMoodTrend(checkIns, logs), null);
});

Deno.test("unknown mood label scores as neutral (3)", () => {
  const checkIns = [
    ci("zen", "2026-06-06"),
    ci("zen", "2026-06-05"),
    ci("zen", "2026-06-04"),
    ci("zen", "2026-06-03"),
  ];
  // All unknown → all 3 → stable.
  assertEquals(buildMoodTrend(checkIns, []), "stable");
});
