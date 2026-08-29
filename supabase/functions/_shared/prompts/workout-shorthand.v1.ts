/**
 * Coach shorthand → structured workout steps — v1.
 *
 * Layer 1 of `parse-workout-shorthand`. The deterministic grammar in that
 * function handles the head of the distribution in <10ms for free; this prompt
 * exists for the tail it structurally cannot reach — progressions, alternating
 * efforts, ladders, parenthetical asides written to a human, and any dialect
 * the grammar has not been taught.
 *
 * THE ONE RULE: never invent a pace. A previous version of the web parser
 * defaulted a missing pace zone to 5K, which silently rewrote 28 of 137 real
 * workouts into sessions the coach never prescribed. Nothing about the output
 * looked wrong, so nobody noticed for months. This prompt inherits that scar:
 * a step with no pace in the source MUST come back with `paceZone: null` and
 * an `unresolved` reason, and the UI asks the coach. An unanswered question is
 * always cheaper than a confident wrong answer.
 *
 * The same rule read from the other side: never turn a number INTO a zone. A
 * coach who writes "@ 6:00" has deliberately opted out of race-pace
 * equivalents, and folding that into "mp" because the athlete's marathon pace
 * is currently 6:00 re-introduces exactly the drift they were avoiding. That
 * is what `exactPaceSecPerMile` is for; the validator treats it as a full
 * alternative to a zone, not a hint.
 *
 * Every field is schema-constrained at the API layer (`responseSchema`), so
 * the model cannot emit prose, a stray unit, or a zone outside the enum.
 * Whatever survives that is then re-checked by the pure validator in
 * `_shared/workout-step-validator.ts` before it can reach a step. The model is
 * the translator, never the last word.
 *
 * The DIALECT block below is not general running knowledge — it is mined from
 * 137 real workouts across six seasons of this coach's plans (Fall23, Fall24,
 * Spring24, SoS24, Spring25, Spring26). "m" meaning miles and "tempo" meaning
 * threshold are this coach's usage, and telling the model outright beats
 * asking it to guess per call.
 *
 * NOT a golden family under hard rule #3 (coach-facing, not athlete-facing,
 * and it prescribes nothing on its own — a human approves every step before it
 * saves). Cassettes are still worth recording: the corpus fixture at
 * `web/tests/fixtures/coach-shorthand-corpus.json` is 137 ready-made inputs.
 *
 * Substitution placeholders:
 *   input       — the coach's raw shorthand, verbatim
 *   zoneList    — the pace-zone enum, comma separated
 *   todayHint   — optional extra context ("this athlete's plan targets a
 *                 marathon"), or the empty string
 */

export const TEMPLATE = `You convert a running coach's shorthand into structured workout steps.

## THE RULE THAT MATTERS MOST

Never invent a pace. If the coach did not write a pace for a step, set
"paceZone": null and pick the matching "unresolved" reason. A step the coach is
asked to confirm is correct behaviour. A step with a pace they never wrote is
a defect, even if the pace is plausible.

"unresolved" is one of exactly these four values, and nothing else:
  no_pace_written            - the text gives no pace for this step
  effort_word_not_a_zone     - it says "fast"/"hard"/"medium", which name no zone
  progression_without_paces  - a cutdown or progression with no paces given
  ambiguous                  - you cannot tell which zone is meant
Set "unresolved" ONLY when "paceZone" is null. The one exception is a
progression: "6m @ MP > HM" has a real starting zone, so emit paceZone "mp",
put the destination in "note", and leave "unresolved" null. Do not explain
yourself anywhere in the JSON; the reason code is the whole answer.

The same applies to distances, rep counts and recoveries: transcribe what is
written. Do not round a session into a tidier one, and do not add a warmup or
cooldown that is not in the text.

## THIS COACH'S DIALECT

Units
- "m" after a number below 100 means MILES ("7m moderate" = 7 miles,
  "3x3m @ MP" = 3 x 3 miles). "m" after 100 or more means METRES
  ("800m", "1200m"). "mi", "M" and "mile"/"miles" are always miles.
- "k"/"K" after a number is kilometres ("10-12 x K" = reps of 1 km).
  Careful: "10k"/"5k"/"3k" AFTER an "@" is a race-pace zone, not a distance.
- "'" is minutes ("5'" = 5 minutes, "1'30" = 90 seconds). '"' is seconds.

Pace zones
- MP = marathon pace. HM / HMP = half-marathon pace. LT = threshold.
- "tempo" means threshold for this coach. Never read it as easy.
- 10k, 5k, 3k, mile = race-pace zones.
- "MP-10" is 10 seconds per mile FASTER than MP. "MP+20" is 20 slower.
  "-5%" / "+3%" are percentage offsets.
  An offset is NEVER dropped and NEVER folded into a different zone: emit the
  base zone plus paceAdjustmentType "seconds_per_mile" (MP-10 → -10) or
  "percent" (MP-3% → -3). Negative is faster in both. A step returned as bare
  "mp" when the coach wrote "MP-10" has lost the entire point of the rep.
Absolute paces — a written number IS the prescription
- A clock time after "@" that is not a zone is an ABSOLUTE pace or an
  absolute rep time. Put it in "exactPaceSecPerMile" (seconds per MILE) and
  leave paceZone null. Do NOT translate it into the nearest zone: "6:00" means
  six minutes a mile, not "MP" — for a 2:37 marathoner those happen to coincide
  today and will not next month, and the coach wrote the number precisely so it
  would stop moving.
- Decide between a PACE and a REP TIME by which one a human could run:
    "4mi @ 6:00"        -> 6:00 per mile. exactPaceSecPerMile 360.
                           (as a rep time, 4 miles in 6:00, it is impossible)
    "6x800 @ 3:00"      -> 800m in 3:00, which is 6:02 per mile.
                           exactPaceSecPerMile 362.
                           (as a pace, 3:00 per mile beats the world record)
  Exactly one reading is usually runnable — take it. When BOTH are runnable
  ("3x2mi @ 12:00"), a repeated distance under about 2 miles is a rep time and
  anything else is a pace. Say which you chose in "note".
- Explicit units always win over the rule above: "@ 6:00/mi", "@ 6:00 pace",
  "6:00 per mile" are paces. "in 3:00", "800 in 2:58" is a rep time.
- Convert rep times with the real distance: 1600m is 0.994 miles, not 1.
  400m in 75s is 75 / 0.2486 = 302 sec/mile.
- A zone and a number together ("@ MP, 6:00") is the zone plus the number as
  confirmation — emit the zone, and put the number in "note".
- ">" means a progression: "MP > HM" starts at MP and finishes at HM.
  Emit the STARTING zone and record the destination in "note".
- "cutdown" / "descending" means each rep is faster than the last. If no
  paces are given, that is a progression with an unresolved pace — say so.

Structure
- "wu"/"WU" = warmup, "cd"/"CD" = cooldown. Note that coaches typo these;
  transcribe what is written and do not silently correct it.
- "N sets of (A - B - C)" or "N x (A / B)" is a compound set. Write the legs
  out in order and REPEAT THE WHOLE GROUP N TIMES. "6 sets of (1k / 600m)" is
  twelve steps: 1k, 600m, 1k, 600m, ... six times through. Emitting one pass is
  wrong — it silently deletes five sixths of the session.
- A rest written INSIDE a set belongs to the leg before it, as that leg's
  recovery fields. Do NOT emit it as its own step. "1k @ HM - 1' rest" is ONE
  step: 1k at HM with a 60-second recovery.
- "600/400 @ 5k/3k" is a ladder: distances pair with paces by position.
- "b/t sets" = between sets. "w/" = with (introduces a recovery).
- "float", "j", "jog", "rec" = a RUNNING recovery. "rest", "standing" = not
  running.
- Ranges ("4-6 x 800", "10-12k", "2-3 sets") take the midpoint.

Words that are NOT pace zones
- "fast", "hard", "medium", "light", "progression", "alternations", "steady
  state" describe effort without naming a zone. Unless the text annotates them
  ("3' fast (HM effort)" — there the zone IS HM), leave paceZone null and
  explain in "unresolved". Do not guess.
- Place names are locations, not workout content: GN, Mueller, Zilker,
  Enfield, Lollipop Loop, Camp Mabry, BSP. Drop them.
- A parenthetical addressed to a person is a note, not a step:
  "(3M will do only through 400s)", "(rest 4' at halfway)", "(HM do 4)".
  Put it in "workoutNote" and emit no step for it.

## OUTPUT

- One entry in "steps" per rep group. Use "repeats" for a plain N x D set.
  Write compound-set legs out in order instead of using "repeats".
- "recovery" describes what happens BETWEEN reps of that step.
- Use "repeats" whenever consecutive reps are IDENTICAL — "10-12 x K" is ONE
  step with repeats:11, never eleven separate steps. Only write legs out
  individually when they differ from each other (a compound set or a ladder).
  Never emit more than 40 steps; if a session would exceed that, compress it
  with "repeats".
- ORDER IS PART OF THE WORKOUT. "repeats" may only group reps that actually
  run back to back. An ALTERNATION never groups: "16 x K alternating MP-3% &
  MP+5%" is sixteen steps that take turns, NOT one step of repeats:8 at MP-3%
  followed by one of repeats:8 at MP+5%. Those two have the same total volume
  and the same paces and are completely different sessions — the first is a
  workout, the second is eight hard kilometres and then a long float. Any
  input using "alternating"/"alternations", or giving TWO work paces for one
  distance, is written out leg by leg in the order the coach wrote them.
- "unparsed" is a LAST RESORT, not a way to avoid a hard case. If you can tell
  what the distances and structure are, emit the steps — even when the pace is
  unknown. A step with paceZone null is a correct answer; putting the same text
  in "unparsed" is not. Only use "unparsed" when you genuinely cannot tell what
  was prescribed at all.

## WORKED EXAMPLES

"2mi wu, 6x800 @ 5k w/ 400m jog, 2mi cd"
steps: [
 {stepType:"warmup",durationType:"distance_miles",durationValue:2,paceZone:"easy"},
 {stepType:"active",durationType:"distance_meters",durationValue:800,paceZone:"fiveK",
  repeats:6,recoveryDurationType:"distance_meters",recoveryDurationValue:400,recoveryIsJog:true},
 {stepType:"cooldown",durationType:"distance_miles",durationValue:2,paceZone:"easy"}]

"6-7 x mile cutdown (MP > 10k) 2' rec"   <- a range takes the midpoint; the
progression starts at MP and the destination goes in the note. NOT unparsed.
steps: [
 {stepType:"active",durationType:"distance_miles",durationValue:1,paceZone:"mp",
  repeats:7,note:"cutdown, progress to 10k",
  recoveryDurationType:"time_seconds",recoveryDurationValue:120,recoveryIsJog:true}]

"16 x K alternating MP-3% & MP+5%"   <- alternations take turns. Sixteen
legs, odd ones fast and even ones float; never two grouped blocks. The count
is TOTAL legs, so this is 16km of work, not 16 pairs.
steps: [
 {stepType:"active",durationType:"distance_km",durationValue:1,paceZone:"mp",
  paceAdjustmentType:"percent",paceAdjustmentValue:-3},
 {stepType:"active",durationType:"distance_km",durationValue:1,paceZone:"mp",
  paceAdjustmentType:"percent",paceAdjustmentValue:5},
 ... continuing to alternate, 16 steps in total]

"8-12m alternations (MP-10/MP+30)"   <- here the leading number is the TOTAL
distance, not a rep count, and a leg is one mile. The range takes its midpoint,
so this is ten 1-mile legs alternating MP-10 / MP+30 — in SECONDS per mile.
steps: [
 {stepType:"active",durationType:"distance_miles",durationValue:1,paceZone:"mp",
  paceAdjustmentType:"seconds_per_mile",paceAdjustmentValue:-10},
 {stepType:"active",durationType:"distance_miles",durationValue:1,paceZone:"mp",
  paceAdjustmentType:"seconds_per_mile",paceAdjustmentValue:30},
 ... continuing to alternate, 10 steps in total]

"2 sets of (1k @ hm - 1' rest - 600m @ 10k)"   <- legs written out in order,
the rest becomes the recovery of the leg before it.
steps: [
 {stepType:"active",durationType:"distance_km",durationValue:1,paceZone:"hm",
  recoveryDurationType:"time_seconds",recoveryDurationValue:60,recoveryIsJog:false},
 {stepType:"active",durationType:"distance_meters",durationValue:600,paceZone:"tenK"},
 {stepType:"active",durationType:"distance_km",durationValue:1,paceZone:"hm",
  recoveryDurationType:"time_seconds",recoveryDurationValue:60,recoveryIsJog:false},
 {stepType:"active",durationType:"distance_meters",durationValue:600,paceZone:"tenK"}]

"6 x 800m @ 3:00 w/2' recovery"   <- the number IS the pace. 800m in 3:00 is
6:02/mile, so exactPaceSecPerMile 362 and paceZone stays null. Reading this as
a zone would hand the athlete whatever their MP happens to be today.
steps: [
 {stepType:"active",durationType:"distance_meters",durationValue:800,paceZone:null,
  exactPaceSecPerMile:362,repeats:6,note:"800m in 3:00",
  recoveryDurationType:"time_seconds",recoveryDurationValue:120,recoveryIsJog:true}]

"4mi @ 6:00"   <- a clock time on a distance too long to be a rep time is a
pace per mile. Still no zone.
steps: [
 {stepType:"active",durationType:"distance_miles",durationValue:4,paceZone:null,
  exactPaceSecPerMile:360,note:"6:00/mi"}]

"6 sets of 3' fast/3' moderate"   <- "fast" names no zone, so paceZone is null
WITH a reason. Still emit every step; do not send this to unparsed.
steps: 12 entries alternating
 {stepType:"active",durationType:"time_seconds",durationValue:180,paceZone:null,
  unresolved:"\"fast\" is an effort, not a pace zone"}
 {stepType:"active",durationType:"time_seconds",durationValue:180,paceZone:"moderate"}

"5 sets of 600/400 @ 5k/3k - 200j"   <- ladder: distances pair with paces by
position, the jog recovery applies to each leg.
steps: 10 entries alternating
 {stepType:"active",durationType:"distance_meters",durationValue:600,paceZone:"fiveK",
  recoveryDurationType:"distance_meters",recoveryDurationValue:200,recoveryIsJog:true}
 {stepType:"active",durationType:"distance_meters",durationValue:400,paceZone:"threeK",
  recoveryDurationType:"distance_meters",recoveryDurationValue:200,recoveryIsJog:true}

## THE WORKOUT

Pace zones available: {{zoneList}}
{{todayHint}}
Coach's text:
{{input}}
`;

/** Pace-zone enum. Mirrors PaceZone in web/src/components/coach/workout-helpers.ts. */
export const PACE_ZONES = [
  "recovery",
  "easy",
  "longRun",
  "moderate",
  "steady",
  "mp",
  "hm",
  "threshold",
  "tenK",
  "fiveK",
  "threeK",
  "mile",
] as const;

export function buildPrompt(input: string, todayHint = ""): string {
  return TEMPLATE
    .replace("{{zoneList}}", PACE_ZONES.join(", "))
    .replace("{{todayHint}}", todayHint ? `Context: ${todayHint}\n` : "")
    .replace("{{input}}", input);
}

/**
 * The response schema, exported so there is exactly ONE of it.
 *
 * It used to be duplicated: one copy in workout-shorthand-llm.ts (what ships)
 * and another inside web/tests/eval/layered-shorthand-eval.ts (what we
 * measured). They drifted — the eval still had the pace fields optional after
 * the shipping copy made them required — so the eval was scoring a contract
 * production no longer used, and would have reported the old broken numbers as
 * if they were current. An eval that measures something other than the
 * deployed behaviour is worse than no eval.
 */
export const RESPONSE_SCHEMA =  {
  type: "object",
  properties: {
    steps: {
      type: "array",
      items: {
        type: "object",
        properties: {
          stepType: { type: "string", enum: ["warmup", "active", "recovery", "rest", "cooldown"] },
          durationType: {
            type: "string",
            enum: ["distance_miles", "distance_km", "distance_meters", "time_seconds"],
          },
          durationValue: { type: "number" },
          paceZone: { type: "string", enum: [...PACE_ZONES], nullable: true },
          paceAdjustmentType: { type: "string", enum: ["seconds_per_mile", "percent"], nullable: true },
          paceAdjustmentValue: { type: "number", nullable: true },
          exactPaceSecPerMile: { type: "number", nullable: true },
          repeats: { type: "integer", nullable: true },
          recoveryDurationType: {
            type: "string",
            enum: ["distance_miles", "distance_km", "distance_meters", "time_seconds"],
            nullable: true,
          },
          recoveryDurationValue: { type: "number", nullable: true },
          recoveryIsJog: { type: "boolean", nullable: true },
          note: { type: "string", nullable: true, maxLength: 120 },
          // CLOSED vocabulary, deliberately. As free text this was where the
          // model looped: on "cutdown" inputs it wrote the same paragraph of
          // hedging over and over until it exhausted maxOutputTokens and
          // returned unterminated JSON. An enum makes that unrepresentable.
          unresolved: { type: "string", enum: ["no_pace_written", "effort_word_not_a_zone", "progression_without_paces", "ambiguous"], nullable: true },
        },
        // The pace fields are REQUIRED, not optional, and that is the fix for
        // the offset-dropping. They are still `nullable`, so "no offset here"
        // remains expressible — but the model must now emit the key and decide,
        // instead of quietly omitting it. Left optional, flash-lite returned
        // sixteen steps at plain MP on two runs of three and flash on every
        // run, always by OMISSION and never by getting the number wrong. That
        // asymmetry is the tell: it was skipping the field, not misreading it.
        required: [
          "stepType",
          "durationType",
          "durationValue",
          "paceZone",
          "paceAdjustmentType",
          "paceAdjustmentValue",
        ],
      },
    },
    workoutNote: { type: "string", nullable: true },
    unparsed: { type: "array", items: { type: "string" } },
  },
  required: ["steps"],
};
