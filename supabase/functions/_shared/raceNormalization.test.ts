import { assert, assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  elevationCostFraction,
  normalizeRaceTime,
  pickAnchorIndex,
} from "./raceNormalization.ts";

// ============================================================================
// THE FIXTURE IS REAL: the athlete's two 2026 10Ks, with measured race-hour
// conditions (Open-Meteo archive, Austin, 2026-08-15 session).
//
//   Feb 7  · 31:20 (1880s) · 47°F / 36°F dew · flat          → the anchor
//   Apr 12 · 33:02 (1982s) · 69°F / 68°F dew · ~100m climb   → the Cap10K
//
// Raw, April reads as 102s of detraining. Normalized, most of that gap must
// dissolve — that dissolution is the contract under test.
// ============================================================================

const FEB = normalizeRaceTime(1880, "tenK", {
  tempF: 47,
  dewPointF: 36,
  elevationGainM: 20,
});
const CAP10K = normalizeRaceTime(1982, "tenK", {
  tempF: 69,
  dewPointF: 68,
  elevationGainM: 100,
});

Deno.test("the Feb race barely moves — cold flat mornings are the neutral case", () => {
  assertEquals(FEB.heatCostSeconds, 0); // 47/36 is below the dew chart entirely
  assert(FEB.elevationCostSeconds <= 8, `flat course: ${FEB.elevationCostSeconds}s`);
  assert(FEB.neutralSeconds >= 1870);
});

Deno.test("the Cap10K's gap to the anchor is mostly conditions, not fitness", () => {
  // Both terms must actually bite…
  assert(CAP10K.heatCostSeconds >= 30, `heat: ${CAP10K.heatCostSeconds}s`);
  assert(CAP10K.elevationCostSeconds >= 20, `hills: ${CAP10K.elevationCostSeconds}s`);
  // …and together close the majority of the raw 102s gap.
  const rawGap = CAP10K.rawSeconds - FEB.rawSeconds; // 102
  const normalizedGap = CAP10K.neutralSeconds - FEB.neutralSeconds;
  assert(
    normalizedGap <= rawGap * 0.45,
    `normalized gap ${normalizedGap}s should close >55% of the raw ${rawGap}s`,
  );
  // The models are DELIBERATELY conservative (net-elevation can't see rolling
  // profile), so the normalized time lands near — not necessarily under — the
  // anchor. Assert the honest band, not the flattering one.
  assert(
    CAP10K.neutralSeconds >= 1860 && CAP10K.neutralSeconds <= 1935,
    `neutral ${CAP10K.neutralSeconds}s (${Math.floor(CAP10K.neutralSeconds / 60)}:${String(CAP10K.neutralSeconds % 60).padStart(2, "0")})`,
  );
});

Deno.test("raw times are never overwritten — normalization must not mint PRs", () => {
  assertEquals(CAP10K.rawSeconds, 1982);
  assert(CAP10K.neutralSeconds < CAP10K.rawSeconds);
  // The breakdown must reconcile exactly, so a surface can show its work.
  assertEquals(
    CAP10K.rawSeconds - CAP10K.heatCostSeconds - CAP10K.elevationCostSeconds,
    CAP10K.neutralSeconds,
  );
});

Deno.test("missing conditions skip their term and say so — never guess", () => {
  const bare = normalizeRaceTime(1982, "tenK", null);
  assertEquals(bare.neutralSeconds, 1982);
  assertEquals(bare.missing, ["race-hour weather", "course elevation"]);

  const heatOnly = normalizeRaceTime(1982, "tenK", { tempF: 69, dewPointF: 68 });
  assertEquals(heatOnly.elevationCostSeconds, 0);
  assertEquals(heatOnly.missing, ["course elevation"]);
  assert(heatOnly.heatCostSeconds > 0);
});

Deno.test("elevation model: asymmetric, capped, conservative", () => {
  // 100m over 10km ≈ 2% mean grade on the climbing half.
  const f = elevationCostFraction(100, 10000);
  assert(f > 0.01 && f < 0.02, `fraction ${f}`);
  // Monotone in gain; capped at the same GRADE_MAX_PCT every grade read uses.
  assert(elevationCostFraction(200, 10000) > f);
  assertEquals(
    elevationCostFraction(5000, 10000),
    elevationCostFraction(10000, 10000),
  );
  // No gain / no distance → zero, never NaN.
  assertEquals(elevationCostFraction(0, 10000), 0);
  assertEquals(elevationCostFraction(100, 0), 0);
});

// ── The §1.3 anchor rule ─────────────────────────────────────────────────

Deno.test("anchor rule: the Cap10K does NOT displace the Feb anchor raw… ", () => {
  // Raw comparison (the old, wrong behaviour this module replaces): April is
  // 5.4% slower — even normalized it stays ~2% slower, inside the 3%
  // tolerance, so the NEWER race anchors. That is the rule working: April
  // corroborates February's fitness, so recency wins.
  const idx = pickAnchorIndex([
    { normalized: CAP10K, ageDays: 125 }, // newest first
    { normalized: FEB, ageDays: 189 },
  ]);
  assertEquals(idx, 0);
});

Deno.test("…but a genuinely slower new race yields the anchor to the older one", () => {
  // Same course conditions, but the athlete ran 36:00 — 15% off. No amount of
  // weather explains that; the older race remains the better capacity evidence.
  const slow = normalizeRaceTime(2160, "tenK", {
    tempF: 69,
    dewPointF: 68,
    elevationGainM: 100,
  });
  const idx = pickAnchorIndex([
    { normalized: slow, ageDays: 10 },
    { normalized: FEB, ageDays: 189 },
  ]);
  assertEquals(idx, 1);
});

Deno.test("anchor rule: empty input → null, single race anchors itself", () => {
  assertEquals(pickAnchorIndex([]), null);
  assertEquals(pickAnchorIndex([{ normalized: FEB, ageDays: 5 }]), 0);
});
