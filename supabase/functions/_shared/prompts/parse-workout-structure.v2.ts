/**
 * Parse-workout-structure prompt — v2.
 *
 * Consumed by `supabase/functions/parse-workout-structure/index.ts`.
 * Synthesizes structure + execution + subjective state from up to FOUR sources
 * (typed notes, voice transcript, GPS stream, and a deterministic
 * recovery-segmentation of that stream).
 *
 * v1 → v2 change:
 *   - Adds {{workBoutsBlock}}: pre-computed, recovery-bounded work bouts from
 *     `detectWorkBouts` (shared/workBouts.ts). The stream is segmented BY
 *     RECOVERIES before the model sees it, so the model no longer has to guess
 *     where one rep ends and the next begins from a raw pace timeline.
 *   - Adds the core rule: a rep is bounded by a RECOVERY, not by a distance
 *     marker. Consecutive fast running with no recovery between is ONE
 *     continuous rep — two fast 1-mile splits with no jog are a single 2-mile
 *     rep, not two reps.
 *
 * v1 stays on disk for eval comparison.
 *
 * Substitution placeholders:
 *   distanceMiles     — toFixed(2) of total distance
 *   durationMinutes   — toFixed(1) of total minutes
 *   moodLabel         — mood string or "(none)"
 *   workoutNotesBlock — `"…"` or "(none)"
 *   voiceTranscriptBlock — `"…"` or "(none)"
 *   workBoutsBlock    — recovery-segmented bouts, or "(no stream to segment)"
 *   timelineStr       — caller-formatted GPS timeline (or "(no GPS stream available)")
 */

export const TEMPLATE = `You are synthesizing a running workout from up to FOUR sources. Each source has different reliability for different things — use them together.

═══════════════════════════════════════════════════════════════
SOURCE PRIORITY (when sources conflict, follow this order):
═══════════════════════════════════════════════════════════════

For STRUCTURE / INTENT (rep count, target paces, rest format):
  1. Workout notes (typed) — most explicit statement of intent
  2. Voice memo transcript — usually narrative but reliable
  3. Detected work bouts — where the recoveries actually fell
  4. GPS stream — last resort, structure inferred from pace bursts

For EXECUTION (actual paces hit, HR, did they nail it):
  1. GPS stream / detected work bouts — ground truth of what happened
  2. Voice memo (athlete's self-report of execution)
  3. Workout notes (intent, not execution)

For SUBJECTIVE state (mood, body, weather, conditions):
  1. Voice memo — most detailed
  2. Mood label
  3. Notes (rare)

═══════════════════════════════════════════════════════════════
SOURCES PROVIDED
═══════════════════════════════════════════════════════════════

Total distance: {{distanceMiles}} mi
Total duration: {{durationMinutes}} min
Mood label: {{moodLabel}}

Workout notes (TYPED — most reliable for structure/intent):
{{workoutNotesBlock}}

Voice memo transcript (SPOKEN — most detailed):
{{voiceTranscriptBlock}}

Detected work bouts (RECOVERY-SEGMENTED — continuous efforts already merged,
recoveries shown between them; this is where the reps actually break). Each bout
shows BOTH lenses — "by distance ≈" and "by time ≈" — because a rep may be
prescribed either way:
{{workBoutsBlock}}

GPS timeline (downsampled, one point per ~10-30s):
{{timelineStr}}

═══════════════════════════════════════════════════════════════
RULES
═══════════════════════════════════════════════════════════════

1. A REP IS BOUNDED BY A RECOVERY, NOT BY A DISTANCE MARKER. This holds for ALL
   intervals, not any one distance. Consecutive fast running with no recovery
   between it is ONE continuous rep, however far it goes: two fast 1-mile splits
   with no jog/stop are a single 2-mile rep; three continuous km are one 3k rep.
   The "Detected work bouts" block has already merged continuous efforts and
   split only on real recoveries — trust its boundaries over per-mile/per-km lap
   markers, and never re-fragment one continuous bout into several reps just
   because it crossed mile/km lines.

1a. THE SPLIT UNIT IS NOT THE REP UNIT. How the watch lapped (miles or km) says
   nothing about the interval's unit. A bout that measures ~1.0 km is a 1k rep
   even if the watch auto-lapped every mile; a ~1.6 km bout is a 1-mile rep even
   if the watch recorded km splits. Take the rep distance from the bout's true
   length (the "by distance ≈" label) and the athlete's typed intent — NOT from
   the split unit. Workouts commonly mix them (mile splits, k reps). When a snap
   shows "(±)" or "ragged", let the typed note decide the unit and count.

1b. REPS MAY BE TIME-BASED, NOT DISTANCE-BASED. Tempo/threshold work is often
   prescribed by duration — "10'", "5' on", "3 × 8 min". Each bout shows a
   "by time ≈" snap for this. Decide distance-rep vs time-rep from the athlete's
   typed/voice intent: "4 × 1k" → distance reps (use by-distance); "3 × 10'" →
   time reps (use by-time, put the duration in rep_distance_label e.g. "10'").
   If intent is silent, prefer whichever lens snaps cleanly (no "(±)"/"ragged");
   if both are clean, prefer distance for short reps (≤2k) and time for long
   tempo blocks (≥5 min).

2. EXECUTION IS THE SOURCE OF TRUTH FOR WHAT IS REPORTED. The detected work
   bouts (i.e. the recoveries the athlete actually took) define the reps — their
   COUNT, their distances, and the block list. Report what was RUN, not what was
   planned. The typed/voice note supplies INTENT only: target paces and the
   prescription. It does NOT override the executed structure.
   - work.reps = the number of executed work bouts (not the prescribed count).
   - rep_distance_label = the executed rep distance; when reps are different
     lengths (e.g. a 2k then two 1ks), use "mixed".
   - blocks = the executed bouts and recoveries, one work_rep per detected bout.
   - intent_pattern = the athlete's OWN stated structure, echoed back. It is
     NULL unless the athlete typed or said a workout in the notes/voice. NEVER
     write your own description of a structure you inferred from GPS/bouts into
     this field — "4 work bouts with varying distances and paces" is YOUR
     summary, not their words, and it must never appear here. When they did
     state a workout, echo it, grouped if there's a clean pattern (e.g.
     "2 × (2k + 2×1k)"). Only append a
     "[prescribed …]" note when the athlete EXPLICITLY stated a prescription in
     the typed/voice note AND it differs from execution — quote their stated
     target, e.g. "2 × (2k + 2×1k) [prescribed 8×1k @ 3:15, 80s rec — first reps
     run continuous]". If no prescription was stated, OMIT the bracket entirely.
     NEVER infer, guess, synthesize, or round a prescription the athlete did not
     give. Do NOT turn "10 reps, the 7th and 8th run shorter" into
     "[prescribed 10×8k]" — no target distance was stated, so there is no
     prescription to note.
   - target_pace_per_mile comes from the note's prescription; actual_pace and
     execution_quality come from the bouts/stream.
   Worked example: note says "8×1000m @ 3:15 w/ 80s rec" but the bouts show
   2k, 1k, 1k, 2k, 1k, 1k (the athlete ran two pairs continuous) → report reps=6,
   rep_distance_label="mixed", six work_rep blocks (two ~2k, four ~1k), and
   intent_pattern="2 × (2k + 2×1k) [prescribed 8×1k]". Do NOT report 8 reps.

3. NEVER invent structure not supported by sources. If notes say "easy 6mi" and
   the stream is flat with no recoveries, return type=easy — one steady block.
   Don't pattern-match a fast bit into a "tempo."

3a. A PAUSE IS NOT A RECOVERY. The bout detector splits on any velocity drop, so
   a continuous run where you STOPPED (water fountain, traffic light, watch
   auto-pause) and then RESUMED THE SAME PACE gets sliced into several "bouts."
   That is a continuous run with pauses — NOT an interval session. Tell them
   apart by intensity contrast:
   - Real reps: fast work bouts separated by DISTINCTLY SLOWER recoveries (a jog
     or rest that is clearly easier than the reps). The work is HARD.
   - Continuous run with pauses: the "bouts" are all at roughly the SAME
     easy/moderate pace, separated only by brief full stops. No hard/easy
     contrast.
   When the bouts show no real work/recovery intensity contrast, IGNORE the
   detector's split: return type=easy/long_run (or progression if a clear
   negative split) with ONE steady block, reps=null, equivalent_race_pace=null.
   Hard giveaways it's continuous, not intervals: a single "rep" longer than
   ~3 miles (a 9-mile rep is impossible), "reps" of wildly mismatched distances
   at the same easy pace, or a total that only reconciles as one continuous
   effort. When in doubt, a run is CONTINUOUS, not an invented workout.

4. WHEN STRUCTURE IS DECLARED (notes/voice say "4×1mi @ 5:00"):
   - Trust it for INTENT only — target paces and the prescription string.
   - Reps, count, and rep distances still come from the executed bouts (rule 2),
     NOT from the declared count.
   - Use the detected bouts / stream to extract ACTUAL paces hit.
   - Output BOTH target_pace (from the declaration) and actual_pace (from bouts).

5. WHEN NO WORKOUT IS DECLARED IN NOTES/VOICE (the notes are just an auto-import
   like "Morning Run · Avg pace: 6:47/mi", or empty): DO NOT manufacture interval
   or tempo structure from the stream. Structure comes from what the athlete
   SAID or what the watch RECORDED as laps — never from GPS bursts alone.
   - Default to the continuous type (easy / long_run / recovery; progression
     only on a clear, sustained negative split). type=interval/tempo requires a
     declaration OR an unmistakable hard/easy contrast (see 3a).
   - The detected bouts inform EXECUTION paces only — they do NOT create reps.
   - reps=null, one steady (or progression) block, intent_pattern=null,
     equivalent_race_pace=null. Confidence cap 0.6.
   Better an honest continuous run than a fabricated workout the athlete never did.

6. CONSOLIDATE blocks. An easy run = ONE "steady" block, not 8 mile-splits.
   A continuous rep = ONE work_rep block (with its true distance), not one per
   mile. Aim for ≤20 blocks total even on rep workouts.

7. EQUIVALENT RACE PACE — ONLY from a SUSTAINED, CONTINUOUS race-effort bout:
   a single continuous effort ≥ ~2mi held at race effort, a time trial, or a
   declared race. Return null for everything else — most importantly for
   INTERVAL / REP sessions (short reps with recoveries) and easy runs.
   WHY THIS MATTERS: reps are run FASTER than you can race. The average pace of
   8×800 with jog recoveries is NOT a 5K race pace — treating it as one invents
   a near-elite race that never happened and corrupts the athlete's fitness
   estimate. Interval fitness is modeled elsewhere in the app; do not
   manufacture a race result from reps here.
   - 20min continuous tempo @ 6:40/mi → ~half-marathon effort, pace_per_mile 6:40
   - 4mi continuous time trial @ 5:35/mi → ~10K effort
   - 8×800 @ 2:30 with 400m jog recoveries → null  (reps, not a race)
   - 6×1mi @ 5:20 with rest → null  (reps, not a race)
   Never emit a pace_per_mile FASTER than the athlete's own sustained running in
   this same session — a race pace cannot beat the pace they held continuously.

8. SUBJECTIVE — capture mood/body/weather/conditions ONLY if mentioned in voice
   memo or notes. Don't infer from pace.

═══════════════════════════════════════════════════════════════
OUTPUT (strict JSON, no markdown, no commentary)
═══════════════════════════════════════════════════════════════

{
  "type": "interval" | "tempo" | "progression" | "long_run" | "easy" | "recovery" | "race" | "unclear",
  "intent_pattern": "human-readable structure as stated by user, e.g. '2mi WU + 4×1mi @ 5:00 (2min rest) + 2mi CD'" | null,
  "blocks": [
    {
      "role": "warmup" | "work_rep" | "recovery" | "cooldown" | "steady",
      "rep_num": number | null,
      "distance_miles": number,
      "duration_s": number,
      "avg_pace_per_mile": "M:SS",
      "avg_hr": number | null
    }
  ],
  "work": {
    "reps": number | null,
    "rep_distance_mi": number | null,
    "rep_distance_label": "1mi" | "800m" | "400m" | "5K" | "2mi" | "1k" | "10'" | "5'" | "—" | null,
    "target_pace_per_mile": "M:SS" | null,
    "actual_pace_per_mile": "M:SS" | null,
    "rest_format": "string e.g. '2 min standing', '90s jog', '400m float'" | null,
    "execution_quality": "hit paces" | "faded" | "negative split" | "even" | "missed" | "—" | null,
    "total_work_distance_mi": number | null
  } | null,
  "equivalent_race_pace": {
    "distance_key": "mile" | "fiveK" | "tenK" | "halfMarathon" | "marathon",
    "pace_per_mile": "M:SS",
    "estimated_time": "MM:SS" | "H:MM:SS",
    "reasoning": string
  } | null,
  "subjective": {
    "mood": string | null,
    "body": string | null,
    "weather": string | null,
    "notes_quotes": [string] | null
  },
  "confidence": number
}`;
