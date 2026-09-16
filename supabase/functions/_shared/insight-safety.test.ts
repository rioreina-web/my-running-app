/**
 * Tests for the rule-#2 runtime safety guard. The guard is the enforced net
 * that keeps a diagnosis / "see a doctor" / "rest for a few days" out of the
 * athlete-facing insight even when the prompt slips.
 *
 * Run: deno test _shared/insight-safety.test.ts
 */
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { insightSafetyViolations } from "./insight-safety.ts";

// Normal coaching reads — must pass clean. These exercise the language a good
// insight actually uses (body-part mentions, "rest" as a noun, observed days
// off) so the guard doesn't muzzle legitimate output.
const CLEAN = [
  "Clean 6×800 threshold set — negative split, last two reps the fastest, HR steady. Strong given the load is spiking; worth noting the calf you mentioned.",
  "A touch quick for easy, but it's a down week so it's low-stakes. Legs sounded a little flat — fine for a shakeout.",
  "You got stronger through the reps and held form. Rested legs from the down week showed.",
  "Tempo sat right in your threshold band; the fade in rep 4 is normal in the heat.",
  "After two days off this week, the legs looked fresh — pace at the same HR was a touch quicker.",
];

// Rule-#2 violations — each must be caught with the expected category.
const VIOLATIONS: Array<{ text: string; expect: string }> = [
  { text: "Looks like ITBS — you should rest for a few days and see a physio.", expect: "diagnosis" },
  { text: "Consider taking some time off to let the knee recover.", expect: "stop-training" },
  { text: "I'd recommend resting until the soreness fades.", expect: "stop-training" },
  { text: "You should see a doctor about that pain.", expect: "medical-referral" },
  { text: "Stop running until it heals.", expect: "stop-training" },
  { text: "This pattern suggests early tendinopathy; seek medical evaluation.", expect: "diagnosis" },
  { text: "That's plantar fasciitis — get some rest days in.", expect: "diagnosis" },
];

Deno.test("safety guard: clean coaching reads pass", () => {
  for (const text of CLEAN) {
    assertEquals(
      insightSafetyViolations(text),
      [],
      `false positive on: ${text}`,
    );
  }
});

Deno.test("safety guard: rule-#2 violations are caught", () => {
  for (const { text, expect } of VIOLATIONS) {
    const hits = insightSafetyViolations(text);
    assert(hits.length > 0, `missed violation: ${text}`);
    assert(
      hits.includes(expect),
      `expected "${expect}" in [${hits.join(", ")}] for: ${text}`,
    );
  }
});
