import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  aiBiometricsAllowed,
  aiSourcePolicyActive,
  excludedSources,
  rowsForAiContext,
  withheldCount,
} from "./aiSourcePolicy.ts";

type Row = { id: string; source?: string | null };

const ROWS: Row[] = [
  { id: "a", source: "strava" },
  { id: "b", source: "voice_log" },
  { id: "c", source: "auto_sync" },
  { id: "d", source: "strava_backfill" },
  { id: "e", source: null },
  { id: "f" },
  { id: "g", source: "" },
];

function withEnv(value: string | null, fn: () => void) {
  const had = Deno.env.get("AI_EXCLUDED_SOURCES");
  if (value === null) Deno.env.delete("AI_EXCLUDED_SOURCES");
  else Deno.env.set("AI_EXCLUDED_SOURCES", value);
  try {
    fn();
  } finally {
    if (had === undefined) Deno.env.delete("AI_EXCLUDED_SOURCES");
    else Deno.env.set("AI_EXCLUDED_SOURCES", had);
  }
}

// The whole point of shipping this: it must change nothing until someone
// decides it should. If this test ever fails, the default was flipped.
Deno.test("ships inert — no exclusions, every row passes", () => {
  withEnv(null, () => {
    assertEquals(excludedSources().size, 0);
    assertEquals(aiSourcePolicyActive(), false);
    assertEquals(rowsForAiContext(ROWS).length, ROWS.length);
    assertEquals(withheldCount(ROWS), 0);
  });
});

Deno.test("env override withholds exactly the named sources", () => {
  withEnv("strava,strava_backfill", () => {
    assert(aiSourcePolicyActive());
    const kept = rowsForAiContext(ROWS).map((r) => r.id);
    assertEquals(kept, ["b", "c", "e", "f", "g"]);
    assertEquals(withheldCount(ROWS), 2);
  });
});

Deno.test("whitespace and empty entries in the env var are ignored", () => {
  withEnv("  strava , , strava_backfill  ", () => {
    assertEquals([...excludedSources()].sort(), ["strava", "strava_backfill"]);
  });
  withEnv("", () => {
    assertEquals(excludedSources().size, 0);
    assertEquals(aiSourcePolicyActive(), false);
  });
});

// Unlabelled provenance is kept, deliberately. Dropping it would shrink the
// coach's context for a reason no log or UI would explain.
Deno.test("rows with null / undefined / empty source are kept", () => {
  withEnv("strava", () => {
    const kept = rowsForAiContext(ROWS).map((r) => r.id);
    assert(kept.includes("e"));
    assert(kept.includes("f"));
    assert(kept.includes("g"));
  });
});

Deno.test("excluding an unrelated source leaves everything alone", () => {
  withEnv("garmin_direct", () => {
    assertEquals(rowsForAiContext(ROWS).length, ROWS.length);
  });
});

Deno.test("empty and nullish inputs never throw", () => {
  withEnv("strava", () => {
    assertEquals(rowsForAiContext([]), []);
    assertEquals(rowsForAiContext(null), []);
    assertEquals(rowsForAiContext(undefined), []);
    assertEquals(withheldCount(null), 0);
  });
});

Deno.test("the filter copies — callers cannot mutate the source array", () => {
  withEnv(null, () => {
    const out = rowsForAiContext(ROWS);
    out.pop();
    assertEquals(ROWS.length, 7);
  });
});

// Fails closed: a missing settings row is not consent.
Deno.test("biometrics consent fails closed", () => {
  assertEquals(aiBiometricsAllowed(null), false);
  assertEquals(aiBiometricsAllowed(undefined), false);
  assertEquals(aiBiometricsAllowed({}), false);
  assertEquals(aiBiometricsAllowed({ ai_health_consent_at: null }), false);
  assertEquals(aiBiometricsAllowed({ ai_health_consent_at: "" }), false);
  assertEquals(
    aiBiometricsAllowed({ ai_health_consent_at: "2026-08-24T00:00:00Z" }),
    true,
  );
});
