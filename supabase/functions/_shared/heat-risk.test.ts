import { assert, assertAlmostEquals, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  assessHeatRisk,
  describeHeatRisk,
  heatRiskFlag,
  vapourPressureHPa,
  wbgtF,
  WBGT_BLACK_F,
  WBGT_RED_F,
} from "./heat-risk.ts";
import { compositeScore } from "./pace-heat-adjustment.ts";

const risk = (t: number, d: number) => assessHeatRisk(compositeScore(t, d), t, d);

// ── The case this module exists for ────────────────────────────────────────

Deno.test("100F with low humidity is a red-flag day, not merely 'hot'", () => {
  // The dew-point chart scores this 130.3 → "hot" → 1.22% → +5 sec/mi on 7:00
  // pace, and can never call any dry day dangerous (at a 30F dew point that
  // would need 140F air). WBGT puts it just under the cancel line.
  const r = risk(100, 30);
  assertEquals(r.paceModelCategory, "hot"); // what the chart alone says
  assertEquals(r.flag, "red");
  assertEquals(r.category, "very_hot"); // floored by the flag
  assert(r.paceModelUnderReads, "the disagreement must be reported");
});

Deno.test("100F with a modest dew point reaches the cancel flag", () => {
  const r = risk(100, 40);
  assertEquals(r.flag, "black");
  assertEquals(r.category, "dangerous");
  assert(r.paceModelUnderReads);
  assert(r.meaning!.includes("cancel"));
});

Deno.test("the pace model is NOT flagged when the two agree", () => {
  // Humid heat is the Emy chart's home ground — it already reads this as
  // severe, so there is no extrapolation to warn about.
  const r = risk(85, 70);
  assertEquals(r.flag, "black");
  assertEquals(r.paceModelCategory, "very_hot");
  assertEquals(r.paceModelUnderReads, false);
});

Deno.test("humidity still dominates at comparable temperatures", () => {
  // The literature's headline: a humid 85F is worse than a dry 95F. The pace
  // model already encodes this and WBGT agrees — this module must not invert it.
  const humid85 = risk(85, 70);
  const dry95 = risk(95, 45);
  assert(
    humid85.wbgtF! > dry95.wbgtF!,
    `humid 85F (${humid85.wbgtF}) should outrank dry 95F (${dry95.wbgtF})`,
  );
});

Deno.test("but a wide temperature gap flips it — the equal weighting's blind spot", () => {
  // The dew-point composite ranks a muggy 70F dawn ABOVE a 100F desert
  // afternoon (144.9 vs 130.3). WBGT ranks them the other way.
  const desert = risk(100, 30);
  const muggyDawn = risk(70, 70);
  assert(compositeScore(70, 70) > compositeScore(100, 30), "composite ordering");
  assert(
    desert.wbgtF! > muggyDawn.wbgtF!,
    `WBGT should rank 100F/30 (${desert.wbgtF}) above 70F/70 (${muggyDawn.wbgtF})`,
  );
});

// ── A cool day stays cool ──────────────────────────────────────────────────

Deno.test("a perfect morning is green and nothing is escalated", () => {
  const r = risk(55, 45);
  assertEquals(r.flag, "green");
  assertEquals(r.paceModelCategory, "ideal");
  assertEquals(r.category, "ideal");
  assertEquals(r.paceModelUnderReads, false);
  assertEquals(describeHeatRisk(r).length, 1); // reports the flag, no warning
});

// ── Formula ────────────────────────────────────────────────────────────────

Deno.test("vapour pressure at the dew point matches Magnus", () => {
  // 0C dew → ~6.1 hPa, the textbook reference value.
  assertAlmostEquals(vapourPressureHPa(32), 6.105, 0.01);
  // Monotonic in dew point.
  assert(vapourPressureHPa(70) > vapourPressureHPa(50));
});

Deno.test("WBGT rises with both temperature and dew point", () => {
  assert(wbgtF(90, 50)! > wbgtF(80, 50)!);
  assert(wbgtF(80, 70)! > wbgtF(80, 50)!);
});

Deno.test("flag boundaries sit on the published thresholds", () => {
  assertEquals(heatRiskFlag(WBGT_BLACK_F + 0.1), "black");
  assertEquals(heatRiskFlag(WBGT_BLACK_F), "red"); // 82 is the top of red
  assertEquals(heatRiskFlag(WBGT_RED_F), "red");
  assertEquals(heatRiskFlag(WBGT_RED_F - 0.1), "amber");
  assertEquals(heatRiskFlag(64.9), "green");
});

// ── Degrading honestly ─────────────────────────────────────────────────────

Deno.test("no weather → no flag, and no guessed one", () => {
  const r = assessHeatRisk(140, null, null);
  assertEquals(r.wbgtF, null);
  assertEquals(r.flag, null);
  assertEquals(r.category, r.paceModelCategory); // unescalated
  assertEquals(r.paceModelUnderReads, false);
  assertEquals(describeHeatRisk(r), []);
});

Deno.test("dew point above air temperature is rejected, not modelled", () => {
  // Unphysical — a bad sensor or a bad join. Returning a number here would be
  // inventing one.
  assertEquals(wbgtF(60, 75), null);
  assertEquals(wbgtF(NaN, 50), null);
  // A degree of slack absorbs rounding at saturation.
  assert(wbgtF(70, 70) != null);
});

// ── Narration ──────────────────────────────────────────────────────────────

Deno.test("narration reports the flag and never instructs", () => {
  const lines = describeHeatRisk(risk(100, 40)).join(" ");
  assert(lines.includes("BLACK"));
  assert(lines.includes("extrapolation"), "must disclose the pace model's limit");
  // Reports the published meaning; issues no order to the athlete.
  for (const banned of ["you should", "do not run", "stop training", "must not"]) {
    assert(!lines.toLowerCase().includes(banned), `must not instruct: "${banned}"`);
  }
});
