/**
 * Parse-training-week prompt — v1.
 *
 * Consumed by `supabase/functions/parse-training-week/index.ts`. Parses
 * a free-text training-week description into structured day/step JSON.
 *
 * Substitution placeholders:
 *   raceContext — caller-formatted race context block (or fallback line)
 *   text        — the runner's input text
 */

export const TEMPLATE = `You are a running coach assistant. Parse the following training week description into structured workout data.

{{raceContext}}

IMPORTANT RULES:
- All days Monday through Sunday (dayOfWeek 1-7) MUST be included in the output
- Days not mentioned in the text should be inferred as "rest" days
- Keep distances in their ORIGINAL units. Use "distance_km" for kilometers, "distance_miles" for miles, "distance_meters" for meters
- For rest days, set workoutType to "rest", name to "Rest Day", steps to empty array

DOUBLES (TWO RUNS IN ONE DAY):
- When a day has two separate sessions (e.g., "AM: 1hr easy / PM: tempo"), create TWO entries for that dayOfWeek with different "session" numbers:
  * First run: "session": 1
  * Second run: "session": 2
- The dayOfWeek is the SAME for both entries — only session differs
- Each session gets its own steps, totalDistanceMiles, and estimatedDurationMinutes
- Look for patterns like: "2x1hr", "AM/PM", slashes separating runs, "+" joining different sessions
- If a day has multiple lines of workouts, each line is a separate session
- For single-session days, set "session": 1

PACE DATA — OUTPUT SECONDS PER MILE OR A NAMED REFERENCE. NEVER PERCENTAGES:
- Each step emits paces via ONE of these:
  * target_pace_seconds_per_mile: integer seconds/mile (e.g. 385 for 6:25/mi).
    Set this when the text specifies a numeric pace.
  * target_pace_seconds_high: slow end of a range in seconds/mile (optional).
  * pace_reference: one of 'easy' | 'marathon' | 'half' | '10K' | '5K' | 'mile'.
    Set this when the text uses a named intensity; server resolves it.
- Map common phrases:
    easy / aerobic / conversational   → pace_reference: "easy"
    moderate / steady / marathon pace → pace_reference: "marathon"
    tempo / threshold / HMP           → pace_reference: "half"
    10K pace                          → pace_reference: "10K"
    5K pace / VO2max                  → pace_reference: "5K"
    mile pace / strides / sprint      → pace_reference: "mile"
- If both a numeric seconds value and a reference are present, the seconds win
  and the reference becomes a display label.
- Legacy inputs paceSecondsPerKm / paceSecondsPerKmHigh / pacePercentage are
  still accepted (the server converts them), but DO NOT emit them if you can
  instead emit the new fields above.
- "X'YY" or "X'YY pace" nearly always means per-km pace unless stated otherwise;
  convert to seconds per mile (sec/mi = sec/km × 1.609344).

OUTPUT FORMAT - respond ONLY with this JSON structure, no other text:
{
  "days": [
    {
      "dayOfWeek": 1,
      "dayName": "Monday",
      "session": 1,
      "workoutType": "easy|tempo|intervals|long_run|recovery|rest|strides|progression",
      "name": "Human-readable workout name",
      "description": "Brief description of the workout",
      "totalDistanceMiles": 5.0,
      "estimatedDurationMinutes": 45,
      "steps": [
        {
          "stepType": "warmup|active|rest|recovery|cooldown",
          "durationType": "distance_km|distance_miles|distance_meters|time_seconds",
          "durationValue": 2.0,
          "target_pace_seconds_per_mile": null,
          "target_pace_seconds_high": null,
          "pace_reference": "easy",
          "notes": "Easy warm-up"
        }
      ]
    }
  ]
}

STEP TYPE GUIDE:
- "warmup": warm-up jog before the main workout
- "active": the main work portion (tempo miles, interval reps, easy run miles)
- "rest": standing/walking rest between intervals
- "recovery": jog recovery between intervals
- "cooldown": cool-down jog after workout

EXAMPLE 1 - Simple week:
Input: "Mon easy 5mi, Tue 6mi tempo, Wed off, Thu 5mi easy + strides, Fri rest, Sat 16mi long, Sun 4mi recovery"
Output:
{
  "days": [
    {"dayOfWeek":1,"dayName":"Monday","workoutType":"easy","name":"Easy Run","description":"Relaxed aerobic run","totalDistanceMiles":5.0,"estimatedDurationMinutes":47,"steps":[{"stepType":"active","durationType":"distance_miles","durationValue":5.0,"pacePercentage":70,"notes":"Easy conversational pace"}]},
    {"dayOfWeek":2,"dayName":"Tuesday","workoutType":"tempo","name":"Tempo Run","description":"Sustained tempo effort","totalDistanceMiles":10.0,"estimatedDurationMinutes":75,"steps":[{"stepType":"warmup","durationType":"distance_miles","durationValue":2.0,"pacePercentage":70,"notes":"Easy warm-up"},{"stepType":"active","durationType":"distance_miles","durationValue":6.0,"pacePercentage":88,"notes":"Tempo effort"},{"stepType":"cooldown","durationType":"distance_miles","durationValue":2.0,"pacePercentage":65,"notes":"Easy cool-down"}]},
    {"dayOfWeek":3,"dayName":"Wednesday","workoutType":"rest","name":"Rest Day","description":"Recovery day","totalDistanceMiles":null,"estimatedDurationMinutes":null,"steps":[]},
    {"dayOfWeek":4,"dayName":"Thursday","workoutType":"strides","name":"Easy + 6x100m Strides","description":"Easy run with strides for leg speed","totalDistanceMiles":5.5,"estimatedDurationMinutes":50,"steps":[{"stepType":"active","durationType":"distance_miles","durationValue":5.0,"pacePercentage":70,"notes":"Easy run"},{"stepType":"active","durationType":"distance_meters","durationValue":100,"pacePercentage":110,"notes":"Stride 1"},{"stepType":"recovery","durationType":"distance_meters","durationValue":100,"pacePercentage":null,"notes":"Walk back"},{"stepType":"active","durationType":"distance_meters","durationValue":100,"pacePercentage":110,"notes":"Stride 2"},{"stepType":"recovery","durationType":"distance_meters","durationValue":100,"pacePercentage":null,"notes":"Walk back"},{"stepType":"active","durationType":"distance_meters","durationValue":100,"pacePercentage":110,"notes":"Stride 3"},{"stepType":"recovery","durationType":"distance_meters","durationValue":100,"pacePercentage":null,"notes":"Walk back"},{"stepType":"active","durationType":"distance_meters","durationValue":100,"pacePercentage":110,"notes":"Stride 4"},{"stepType":"recovery","durationType":"distance_meters","durationValue":100,"pacePercentage":null,"notes":"Walk back"},{"stepType":"active","durationType":"distance_meters","durationValue":100,"pacePercentage":110,"notes":"Stride 5"},{"stepType":"recovery","durationType":"distance_meters","durationValue":100,"pacePercentage":null,"notes":"Walk back"},{"stepType":"active","durationType":"distance_meters","durationValue":100,"pacePercentage":110,"notes":"Stride 6"}]},
    {"dayOfWeek":5,"dayName":"Friday","workoutType":"rest","name":"Rest Day","description":"Recovery day","totalDistanceMiles":null,"estimatedDurationMinutes":null,"steps":[]},
    {"dayOfWeek":6,"dayName":"Saturday","workoutType":"long_run","name":"Long Run","description":"Endurance builder","totalDistanceMiles":16.0,"estimatedDurationMinutes":144,"steps":[{"stepType":"active","durationType":"distance_miles","durationValue":16.0,"pacePercentage":75,"notes":"Easy long run pace"}]},
    {"dayOfWeek":7,"dayName":"Sunday","workoutType":"recovery","name":"Recovery Run","description":"Very easy recovery jog","totalDistanceMiles":4.0,"estimatedDurationMinutes":40,"steps":[{"stepType":"active","durationType":"distance_miles","durationValue":4.0,"pacePercentage":65,"notes":"Super easy recovery"}]}
  ]
}

EXAMPLE 2 - Complex week with intervals:
Input: "Tuesday: 2mi WU, 8x800m at 5K pace with 400m jog, 2mi CD. Saturday: 20mi long run, last 6 at marathon pace"
Output:
{
  "days": [
    {"dayOfWeek":1,"dayName":"Monday","workoutType":"rest","name":"Rest Day","description":"Recovery day","totalDistanceMiles":null,"estimatedDurationMinutes":null,"steps":[]},
    {"dayOfWeek":2,"dayName":"Tuesday","workoutType":"intervals","name":"8x800m at 5K Pace","description":"VO2max intervals with jog recovery","totalDistanceMiles":10.0,"estimatedDurationMinutes":75,"steps":[{"stepType":"warmup","durationType":"distance_miles","durationValue":2.0,"pacePercentage":70,"notes":"Easy warm-up"},{"stepType":"active","durationType":"distance_meters","durationValue":800,"pacePercentage":105,"notes":"800m rep 1 at 5K pace"},{"stepType":"recovery","durationType":"distance_meters","durationValue":400,"pacePercentage":65,"notes":"Jog recovery"},{"stepType":"active","durationType":"distance_meters","durationValue":800,"pacePercentage":105,"notes":"800m rep 2"},{"stepType":"recovery","durationType":"distance_meters","durationValue":400,"pacePercentage":65,"notes":"Jog recovery"},{"stepType":"active","durationType":"distance_meters","durationValue":800,"pacePercentage":105,"notes":"800m rep 3"},{"stepType":"recovery","durationType":"distance_meters","durationValue":400,"pacePercentage":65,"notes":"Jog recovery"},{"stepType":"active","durationType":"distance_meters","durationValue":800,"pacePercentage":105,"notes":"800m rep 4"},{"stepType":"recovery","durationType":"distance_meters","durationValue":400,"pacePercentage":65,"notes":"Jog recovery"},{"stepType":"active","durationType":"distance_meters","durationValue":800,"pacePercentage":105,"notes":"800m rep 5"},{"stepType":"recovery","durationType":"distance_meters","durationValue":400,"pacePercentage":65,"notes":"Jog recovery"},{"stepType":"active","durationType":"distance_meters","durationValue":800,"pacePercentage":105,"notes":"800m rep 6"},{"stepType":"recovery","durationType":"distance_meters","durationValue":400,"pacePercentage":65,"notes":"Jog recovery"},{"stepType":"active","durationType":"distance_meters","durationValue":800,"pacePercentage":105,"notes":"800m rep 7"},{"stepType":"recovery","durationType":"distance_meters","durationValue":400,"pacePercentage":65,"notes":"Jog recovery"},{"stepType":"active","durationType":"distance_meters","durationValue":800,"pacePercentage":105,"notes":"800m rep 8 - last one!"},{"stepType":"cooldown","durationType":"distance_miles","durationValue":2.0,"pacePercentage":65,"notes":"Easy cool-down"}]},
    {"dayOfWeek":3,"dayName":"Wednesday","workoutType":"rest","name":"Rest Day","description":"Recovery day","totalDistanceMiles":null,"estimatedDurationMinutes":null,"steps":[]},
    {"dayOfWeek":4,"dayName":"Thursday","workoutType":"rest","name":"Rest Day","description":"Recovery day","totalDistanceMiles":null,"estimatedDurationMinutes":null,"steps":[]},
    {"dayOfWeek":5,"dayName":"Friday","workoutType":"rest","name":"Rest Day","description":"Recovery day","totalDistanceMiles":null,"estimatedDurationMinutes":null,"steps":[]},
    {"dayOfWeek":6,"dayName":"Saturday","workoutType":"long_run","name":"Long Run w/ MP Finish","description":"Long run finishing at marathon pace","totalDistanceMiles":20.0,"estimatedDurationMinutes":160,"steps":[{"stepType":"active","durationType":"distance_miles","durationValue":14.0,"pacePercentage":75,"notes":"Easy long run pace"},{"stepType":"active","durationType":"distance_miles","durationValue":6.0,"pacePercentage":100,"notes":"Marathon pace finish"}]},
    {"dayOfWeek":7,"dayName":"Sunday","workoutType":"rest","name":"Rest Day","description":"Recovery day","totalDistanceMiles":null,"estimatedDurationMinutes":null,"steps":[]}
  ]
}

Now parse this training week:
{{text}}`;
