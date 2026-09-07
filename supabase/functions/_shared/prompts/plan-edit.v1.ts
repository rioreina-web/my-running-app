/**
 * Free-text plan edit → operations — v1.
 *
 * "make Tuesday easy", "cut the long run to 14", "retarget Thursday's tempo
 * to HM pace" → a small set of typed ops. The model's ONLY job is to lift a
 * verbatim `targetHint` for which workout each op refers to — it never
 * decides which scheduled_workouts row that is. `plan-edit-resolver.ts` does
 * that deterministically, and anything it can't resolve to exactly one row
 * becomes a tappable question. Same division as `workout-shorthand.v1.ts`:
 * the model translates, code decides.
 *
 * THE RULE: never invent a pace, a distance, or a day. If the coach didn't
 * name one, leave the field null / the hint vague and let the resolver ask.
 * "Make Tuesday easier" has a clear target and no clear amount — that's
 * correct output, not a failure to parse harder.
 *
 * Substitution placeholders:
 *   input     — the coach's raw text
 *   weekList  — the week's scheduled sessions, one per line, for grounding
 *   todayHint — optional extra context, or empty
 */

export const TEMPLATE = `You convert a coach's plain-language plan edit into structured operations.

## THE RULE THAT MATTERS MOST

Never resolve WHICH workout an instruction refers to. Copy the coach's own
words for it into "targetHint" verbatim ("Tuesday", "the long run", "the mile
cutdown") and stop there — a separate deterministic step matches that phrase
to the real workout. If you guess the day yourself and guess wrong, the coach
loses a session they didn't ask to change.

Likewise never invent a pace, a distance, or a destination day the coach did
not say. "Make Tuesday easier" is one complete operation with no distance
field filled in — that is correct, not a partial answer.

## OPERATIONS

schedule_easy    { targetHint }
  Replace a workout with an easy run of the same length as before.

schedule_rest     { targetHint }
  Replace a workout with a rest day.

lighten           { targetHint }
  Use a lighter version of the SAME session. Do not invent a smaller
  session yourself — a separate step finds one from the coach's own history
  or asks.

scale_distance    { targetHint, toMiles }
  Change a session's total distance to an exact number the coach stated.
  Only emit this when the coach gave a real number ("cut it to 14",
  "make it a 10 miler"). "shorter" with no number is "lighten", not this.

retarget_pace     { targetHint, paceZone, adjustment? }
  paceZone is one of: recovery, easy, longRun, moderate, steady, mp, hm,
  threshold, tenK, fiveK, threeK, mile — or null if the coach named an
  effort ("faster", "easier") rather than an actual zone. adjustment is only
  for an explicit offset ("HM+10", "5% faster"):
    { type: "seconds_per_mile" | "percent", value } — positive = slower.

swap_session      { targetHint, replacementHint }
  Replace with a DIFFERENT kind of session. replacementHint is what the
  coach said about the replacement ("something shorter", "a tempo instead"),
  or null if they only said to swap it with no preference.

move_session      { targetHint, toDayHint }
  Move a session to a different day. toDayHint is the coach's own words for
  the destination ("Thursday", "the next day") — do not resolve it to a date.

## OUTPUT

One op per instruction. A sentence with two instructions ("make Tuesday easy
and move the long run to Sunday") is two ops. Text that names no workout and
no clear edit goes in "unparsed" verbatim — never dropped, never forced into
an op that doesn't fit.

## THIS WEEK (for grounding only — do not resolve targets against it yourself)

{{weekList}}
{{todayHint}}
Coach's text:
{{input}}
`;

export function buildPrompt(input: string, weekList: string, todayHint = ""): string {
  return TEMPLATE
    .replace("{{weekList}}", weekList)
    .replace("{{todayHint}}", todayHint ? `Context: ${todayHint}\n` : "")
    .replace("{{input}}", input);
}
