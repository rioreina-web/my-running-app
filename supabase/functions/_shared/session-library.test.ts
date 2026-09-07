/**
 * Tests for the coach's session library and its selector.
 *
 * Runs against the REAL library JSON, not fixtures — the point of this module
 * is that it speaks in this coach's actual sessions, so a test on invented
 * data would check nothing that matters.
 *
 * Run: deno test --allow-read supabase/functions/_shared/session-library.test.ts
 */

import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  classifyKind,
  selectSessions,
  lighterForm,
  formatForPrompt,
  type LibrarySession,
} from "./session-library.ts";

const library: LibrarySession[] = JSON.parse(
  await Deno.readTextFile(new URL("./session-library.json", import.meta.url)),
);

Deno.test("the library is populated and every entry keeps the coach's text", () => {
  assert(library.length > 100, `expected the full corpus, got ${library.length}`);
  for (const s of library) {
    assert(s.text.trim().length > 0, "a session lost its text");
    assert(s.day, `${s.text} has no day role`);
    assert(s.kind, `${s.text} has no kind`);
  }
});

Deno.test("classification reads intent from the coach's own words", () => {
  assertEquals(classifyKind("6-7 x mile cutdown (MP > 10k) 2' rec", "tuesday"), "progression");
  // A plain recovery is not a float — this is MP work, not an alternation.
  assertEquals(classifyKind("7m moderate + 3x3m @ MP w/800 recovery", "saturday"), "marathon_pace");
  assertEquals(classifyKind("3 x 4m @ MP w/1mi float", "saturday"), "alternation");
  assertEquals(classifyKind("8-12m alternations (MP-10/MP+30)", "tuesday"), "alternation");
  assertEquals(classifyKind("2mi tempo + 4x400m @ 10k", "tuesday"), "threshold");
  assertEquals(classifyKind("12 x 400m @ mile", "tuesday"), "intervals");
  assertEquals(classifyKind("4 x 200m strides", "thursday"), "strides");
  assertEquals(classifyKind("hill sprints 10s", "tuesday"), "hills");
});

Deno.test("a Saturday entry with no quality markers is the long run by position", () => {
  assertEquals(classifyKind("18 miles", "saturday"), "long_run");
});

Deno.test("selecting for a day returns only that day's sessions", () => {
  const picks = selectSessions(library, { day: "saturday" });
  assert(picks.length > 0, "no Saturday sessions found");
  for (const p of picks) assert(p.day === "saturday", `${p.day} leaked into a Saturday pick`);
});

Deno.test("the light Tuesday column still counts as a Tuesday option", () => {
  const picks = selectSessions(library, { day: "tuesday", limit: 200 });
  assert(
    picks.some((p) => p.day === "tuesday_light"),
    "the coach's lower-volume Tuesdays should be offered for a Tuesday slot",
  );
});

Deno.test("a volume cap excludes bigger sessions but keeps unmeasured ones", () => {
  const cap = 8;
  const picks = selectSessions(library, { maxMiles: cap, limit: 200 });
  for (const p of picks) {
    if (p.totalMiles != null) {
      assert(p.totalMiles <= cap, `${p.text} is ${p.totalMiles}mi, over the ${cap}mi cap`);
    }
  }
  // Sessions we could not total must survive a cap — silently dropping them
  // would hide the coach's least machine-legible work from every suggestion.
  assert(
    picks.some((p) => p.totalMiles == null),
    "unmeasured sessions should remain eligible under a cap",
  );
});

Deno.test("exclusion keeps the athlete off a repeat of what they just did", () => {
  const [first] = selectSessions(library, { day: "tuesday" });
  const after = selectSessions(library, { day: "tuesday", exclude: [first.text], limit: 200 });
  assert(!after.some((p) => p.text === first.text), "excluded session came back");
});

Deno.test("kind filtering narrows to the right family", () => {
  const picks = selectSessions(library, { kinds: ["progression"], limit: 200 });
  assert(picks.length > 0);
  for (const p of picks) assertEquals(p.kind, "progression");
});

Deno.test("lighterForm returns the coach's own variant and never invents one", () => {
  const withVariant = library.find((s) => s.lightVariant);
  assert(withVariant, "the Fall24 sheet should contribute light variants");
  assertEquals(lighterForm(withVariant!), withVariant!.lightVariant);

  const without = library.find((s) => !s.lightVariant)!;
  assertEquals(lighterForm(without), null, "must not synthesise a lighter session");
});

Deno.test("prompt rendering leads with the verbatim session", () => {
  const rendered = formatForPrompt(selectSessions(library, { day: "tuesday", limit: 3 }));
  const picks = selectSessions(library, { day: "tuesday", limit: 3 });
  for (const p of picks) {
    assert(rendered.includes(p.text), `${p.text} missing from the rendered prompt`);
  }
  // No synthetic codes — that vocabulary is what this library replaces.
  assert(!/\bRSS_\d|\bRSPS_\d|\bGE_\d\b/.test(rendered), "synthetic workout codes leaked in");
});

Deno.test("selection is deterministic", () => {
  const a = selectSessions(library, { day: "tuesday", maxMiles: 10 });
  const b = selectSessions(library, { day: "tuesday", maxMiles: 10 });
  assertEquals(a.map((s) => s.text), b.map((s) => s.text));
});
