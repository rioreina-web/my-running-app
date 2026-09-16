/**
 * Tests for the shared body-part vocabulary.
 *
 * Run: deno test _shared/bodyVocabulary.test.ts
 *
 * Covers the detection-not-diagnosis contract (CLAUDE.md hard rule #2):
 * synonym mapping, laterality extraction, rejection of diagnosis names
 * and unknown terms, longest-match precedence, and severity mapping.
 */

import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  normalizeBodyMention,
  severityHintFromText,
  severityHintFromWord,
} from "./bodyVocabulary.ts";

// ── Synonym mapping ──────────────────────────────────────

Deno.test("maps a plain body part to its canonical key", () => {
  assertEquals(normalizeBodyMention("knee"), { body_area: "knee", side: null });
});

// §4 drift fix: the canonical key is `plantar` (matches the iOS BodyArea
// case). `arch` and the plantar-fascia location terms are synonyms mapping
// onto it — a stored `arch` no longer fails to decode on iOS.
Deno.test("§4: plantar/arch/plantar-fascia all map to canonical 'plantar'", () => {
  assertEquals(normalizeBodyMention("plantar"), { body_area: "plantar", side: null });
  assertEquals(normalizeBodyMention("arch"), { body_area: "plantar", side: null });
  assertEquals(normalizeBodyMention("plantar fascia"), { body_area: "plantar", side: null });
});

Deno.test("maps a synonym onto the canonical key", () => {
  assertEquals(normalizeBodyMention("calves"), { body_area: "calf", side: null });
  assertEquals(normalizeBodyMention("hammy"), { body_area: "hamstring", side: null });
  assertEquals(normalizeBodyMention("kneecap"), { body_area: "knee", side: null });
});

Deno.test("maps the IT band location (not a diagnosis) correctly", () => {
  assertEquals(normalizeBodyMention("IT band"), { body_area: "it band", side: null });
  assertEquals(normalizeBodyMention("itband"), { body_area: "it band", side: null });
});

Deno.test("subtalar maps to ankle (synonym table says so)", () => {
  assertEquals(normalizeBodyMention("subtalar joint"), { body_area: "ankle", side: null });
});

Deno.test("newly-added gaps are covered (groin, soleus, peroneal, toe, SI joint)", () => {
  assertEquals(normalizeBodyMention("groin"), { body_area: "groin", side: null });
  assertEquals(normalizeBodyMention("soleus"), { body_area: "soleus", side: null });
  assertEquals(normalizeBodyMention("peroneal"), { body_area: "peroneal", side: null });
  assertEquals(normalizeBodyMention("big toe"), { body_area: "toe", side: null });
  assertEquals(normalizeBodyMention("sacroiliac"), { body_area: "si joint", side: null });
});

// ── Side extraction ──────────────────────────────────────

Deno.test("extracts left/right from full words", () => {
  assertEquals(normalizeBodyMention("left knee"), { body_area: "knee", side: "left" });
  assertEquals(normalizeBodyMention("right calf"), { body_area: "calf", side: "right" });
});

Deno.test("extracts side from L/R abbreviations", () => {
  assertEquals(normalizeBodyMention("R achilles"), { body_area: "achilles", side: "right" });
  assertEquals(normalizeBodyMention("L hamstring"), { body_area: "hamstring", side: "left" });
});

Deno.test("possessive + side + filler still resolves", () => {
  assertEquals(normalizeBodyMention("my right calf"), { body_area: "calf", side: "right" });
});

Deno.test("both/bilateral is recognized but recorded unsided", () => {
  assertEquals(normalizeBodyMention("both knees"), { body_area: "knee", side: null });
  assertEquals(normalizeBodyMention("bilateral shins"), { body_area: "shin", side: null });
});

// ── Rejection of diagnoses ───────────────────────────────

Deno.test("rejects pure diagnosis tokens with no location", () => {
  assertEquals(normalizeBodyMention("ITBS"), null);        // acronym, no anatomical token
  assertEquals(normalizeBodyMention("tendinitis"), null);  // condition, no location
  assertEquals(normalizeBodyMention("shin splints"), { body_area: "shin", side: null }); // location survives
});

Deno.test("a location word buried in diagnosis phrasing still surfaces the LOCATION only", () => {
  // "sprained ankle" → ankle (location); the diagnosis word is discarded, never emitted.
  assertEquals(normalizeBodyMention("sprained ankle"), { body_area: "ankle", side: null });
});

// ── Rejection of unknown terms ───────────────────────────

Deno.test("drops unknown / uncatalogued terms rather than inventing", () => {
  assertEquals(normalizeBodyMention("spleen"), null);
  assertEquals(normalizeBodyMention("subtalar"), { body_area: "ankle", side: null }); // known synonym
  assertEquals(normalizeBodyMention("vibes"), null);
});

Deno.test("empty / junk input returns null", () => {
  assertEquals(normalizeBodyMention(""), null);
  assertEquals(normalizeBodyMention("   "), null);
  assertEquals(normalizeBodyMention("left"), null); // side but no area
});

// ── Longest-match precedence ─────────────────────────────

Deno.test("longest synonym wins (multi-word beats its substring)", () => {
  assertEquals(normalizeBodyMention("hip flexor"), { body_area: "hip flexor", side: null });
  assertEquals(normalizeBodyMention("lower back"), { body_area: "lower back", side: null });
  assertEquals(normalizeBodyMention("hip"), { body_area: "hip", side: null });
  assertEquals(normalizeBodyMention("back"), { body_area: "back", side: null });
});

// ── Case / whitespace tolerance ──────────────────────────

Deno.test("tolerates case and extra whitespace", () => {
  assertEquals(normalizeBodyMention("  Left   KNEE "), { body_area: "knee", side: "left" });
  assertEquals(normalizeBodyMention("AcHiLLeS"), { body_area: "achilles", side: null });
});

// ── Severity mapping ─────────────────────────────────────

Deno.test("severityHintFromWord maps the athlete's word to a closed hint", () => {
  assertEquals(severityHintFromWord("cranky"), "tight");
  assertEquals(severityHintFromWord("sharp"), "sharp");
  assertEquals(severityHintFromWord("sore"), "sore");
  assertEquals(severityHintFromWord("strained"), "pain");
  assertEquals(severityHintFromWord("whatever"), null);
  assertEquals(severityHintFromWord(null), null);
});

Deno.test("severityHintFromText picks the strongest hint present", () => {
  assertEquals(severityHintFromText("felt a deep ache when I push off"), "sore");
  assertEquals(severityHintFromText("sharp pain on the descent"), "sharp"); // sharp beats pain
  assertEquals(severityHintFromText("nice and loose"), null);
});
