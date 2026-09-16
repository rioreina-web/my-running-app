/**
 * _shared/athleteNoteText.ts — is this notes value the athlete talking?
 *
 * A notes column on `training_logs` is not reliably athlete voice. On rows
 * imported from Strava/HealthKit it holds the provider's activity name or its
 * stat dump, copied forward into `cleaned_notes` by the ingest path. Measured
 * on the primary athlete (2026-08-18): `cleaned_notes` is non-empty on 49 of 49
 * logs over 28 days, and on most of them its entire content is "Morning Run",
 * "Afternoon Run" or "Treadmill".
 *
 * That distinction only started to matter when the workout-insight prompt began
 * quoting recent logs back to the model (v6). One boilerplate title on the
 * current run is survivable; forty of them bury the two or three real memos in
 * a block that is supposed to be the athlete's own words, and invite the model
 * to read an activity name as commentary.
 */

/**
 * Activity titles that are not commentary. Exact-match by design: a real short
 * note ("Legs felt heavy today", "knee is back") is precisely the signal the
 * recent-log block exists to carry, and any length or word-count threshold big
 * enough to catch "Morning Run" would discard those too.
 */
const ACTIVITY_TITLE_RE =
  /^(?:(?:early |late )?(?:morning|afternoon|evening|lunch|lunchtime|midday|night)\s+(?:run|ride|walk|workout|swim|activity|jog)|treadmill(?:\s+run)?|indoor\s+run|outdoor\s+run|run|running|jog|workout|activity|untitled)$/i;

/**
 * True when `note` carries no athlete voice — an empty value, a bare activity
 * title, or the provider's imported stat block
 * ("Morning Run\nDistance: 6.01 mi\nDuration: 44:04\nAvg pace: 7:20").
 */
export function isBoilerplateNote(note: string | null | undefined): boolean {
  const t = (note ?? "").trim();
  if (!t) return true;
  if (ACTIVITY_TITLE_RE.test(t)) return true;
  // Imported stat dump: a title line followed by Distance:/Duration: fields.
  return /\bDistance:\s/i.test(t) && /\bDuration:\s/i.test(t);
}

/**
 * The first of `candidates` that is actually the athlete talking, whitespace
 * collapsed, or "" when none is.
 *
 * Checks each in turn rather than null-coalescing then filtering: on an
 * imported row `cleaned_notes` is a bare title while `workout_notes` may hold
 * a real parsed description, and `a ?? b` would stop at the title and throw
 * the useful one away.
 */
export function firstAthleteNote(
  ...candidates: Array<string | null | undefined>
): string {
  for (const c of candidates) {
    const t = (c ?? "").trim();
    if (t && !isBoilerplateNote(t)) return t.replace(/\s+/g, " ");
  }
  return "";
}
