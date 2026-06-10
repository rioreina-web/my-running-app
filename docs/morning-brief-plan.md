# The Morning Brief

Working doc. Edit in place. When you want something executed, point at a
section.

The daily ritual. 60–90 seconds of coach voice that primes the athlete for
the day. Voice + text. Opens the app, the coach is there.

Highest-retention feature on the roadmap. Cheapest feature to demo.
Touches every moat: voice, adaptive loop, pace ladder, weather, coach
voice. If the app has a soul, this is where it lives.

---

## 1. The problem this solves

Today the athlete opens the app and sees a calendar. A row with "Easy 6mi
@ 7:00." That's a schedule, not coaching. It doesn't tell them:

- Why today is what it is (glass-box)
- How yesterday affects today ("you're coming in legal")
- Whether heat/dew point changes the ask
- If any pattern the coach would flag is creeping in (pace drift, fatigue)
- What tomorrow asks (so today's effort is in service of something)

A real coach doing email-based coaching sends a morning note. *"Here's
what I want today. You looked a little flat on Wednesday so take the easy
6 actually easy. Saturday's long run matters — don't steal from it."* We
can ship that automatically, grounded in real data, in the coach's voice.

---

## 2. What the brief is

### Shape

- 60–90 seconds of spoken audio (or readable in ~20 seconds)
- ~60–100 words of text
- Three to five short sentences
- Appears as a card at the top of the Plan view the first time the
  athlete opens the app that day
- Card has: title ("This morning · Fri"), text block, a single audio play
  button, three action buttons (Start workout, Log feeling, Move day)
- Dismissable — swipe-to-collapse into a subtle strip ("Brief → ") that
  can be re-expanded

### Voice and tone

Brand voice applies (see `brand-voice.md` if it exists; otherwise: warm,
direct, measured, no hype, no emojis, no "awesome"). Examples encode the
voice better than rules:

**Quality day:**
> Morning. Today's the 5×1mi tempo you've been pointing at — 5:52 pace,
> 90s jog rest. Yesterday's long run came in steady, so you're coming in
> legal. Dew point is 58°F, no adjustment. First rep will feel off. That's
> normal. Settle into pace on rep 2 and you've got it.

**Easy day after a quality:**
> Morning. 6 easy today, and let's make sure it's actually easy. Your last
> two easy runs ran 8 seconds per mile faster than target, so keep it 7:30
> or slower. Legs will tell you. Tomorrow's the medium long, 10 at 6:40.

**Rest day:**
> Today's the rest day. Sleep in if you can. Yesterday's tempo came in
> on target, and there's a long run Saturday. Protect the legs. Nothing
> to do today besides exist.

**Heat shift:**
> Morning. Heat's up — 75°F with a 68° dew point when you'd normally run.
> That's a 25s/mi bump on today's 8 easy. Target is 7:55, not 7:30.
> Effort over pace.

**Missed yesterday:**
> Morning. Yesterday slipped — it happens. Today's still the tempo, and
> looking at the week, you've got enough room to hit it. Don't try to make
> up yesterday inside today. Run the workout as written.

**Race-week:**
> Eight days out. Today is 40 minutes easy with 4 strides at the end.
> Nothing to prove. Your taper's doing its job even when the runs feel
> too short. Trust the work that's already behind you.

### What the brief never does

- Motivational hype ("you've got this!", "crush it!", "you're unstoppable")
- Generic pleasantries ("hope you're well!")
- Data dumps ("your ACWR is 1.14, your TSB is -8, your CTL is 72")
- Emoji
- Questions ("how are you feeling?") — there are other places to ask
- Lectures about missed workouts
- Predictions ("you'll feel great today!") — we don't know
- Social comparisons ("faster than 80% of users")

---

## 3. Data model

### New table: `morning_briefs`

One row per (user, date). Generated on first access of the day, cached
for the rest of the day.

```sql
create table morning_briefs (
  id                 uuid primary key default gen_random_uuid(),
  user_id            uuid not null references auth.users(id) on delete cascade,
  brief_date         date not null,                  -- local date, not UTC
  brief_text         text not null,                  -- 60-100 words, the displayed copy
  audio_url          text,                           -- null = use device TTS; non-null = pre-rendered
  context_snapshot   jsonb not null,                 -- the structured inputs used to generate (for audit + regen)
  context_hash       text not null,                  -- sha256 of relevant context fields
  generated_at       timestamptz not null default now(),
  opened_at          timestamptz,                    -- when athlete first viewed
  played_at          timestamptz,                    -- when athlete tapped audio play
  dismissed_at       timestamptz,                    -- when collapsed to strip
  model_used         text,                           -- e.g. 'claude-sonnet-4-6'
  prompt_version     text not null default 'v1',
  unique (user_id, brief_date)
);

create index idx_morning_briefs_user_date on morning_briefs(user_id, brief_date desc);
```

RLS: user can read their own briefs, their coach can read briefs for
their athletes (same pattern as scheduled_workouts).

### `context_snapshot` shape

Structured record of everything that fed into the brief. Audit trail +
enables regeneration when context changes materially (e.g. coach edits a
workout after the brief was generated, or weather shifts significantly).

```ts
interface BriefContext {
  today: {
    date: string;                    // "2026-04-25"
    weekday: string;                 // "Friday"
    workout_type: string | null;     // "tempo" | "easy" | "long_run" | "rest" | null
    distance_mi: number | null;
    target_pace_sec_per_mi: number | null;
    workout_name: string | null;     // "5x1mi tempo"
    rationale_short: string | null;  // from scheduled_workouts.rationale_short
    is_rest_day: boolean;
    is_quality: boolean;
    is_race_day: boolean;
  };
  yesterday: {
    completed: boolean;
    workout_type: string | null;
    distance_mi: number | null;
    actual_pace_sec_per_mi: number | null;
    target_pace_sec_per_mi: number | null;
    voice_memo_summary: string | null;  // short sentiment/text snippet
    notes: string | null;
  } | null;
  week_context: {
    weekly_miles_completed: number;
    weekly_mileage_target: number;
    easy_pace_drift_sec: number | null; // negative = faster than target
    days_since_last_quality: number;
    recent_injury_mentions: string[];    // e.g. ["left calf", "left calf"]
    missed_session_count_this_week: number;
  };
  plan_context: {
    plan_name: string;
    week_of_plan: number;
    total_weeks: number;
    phase: string | null;                // "base" | "build" | "specific" | "taper" | null
    goal_race_name: string | null;
    goal_race_date: string | null;
    days_to_race: number | null;
  } | null;
  weather: {
    temp_f: number | null;
    dew_point_f: number | null;
    heat_pace_adjustment_sec_per_mi: number;  // 0 if none
    source: "open-meteo" | "user-set" | null;
  } | null;
  coach_note: string | null;  // optional note the coach left via coach portal
}
```

### Why cache, not regenerate on every open

- One LLM call per user per day instead of per open
- Athlete sees the same brief if they re-open (no "wait, it changed?")
- Audit trail for coach review
- Costs stay bounded: ~$0.002/user/day ≈ $0.73/user/year

Regenerate only when `context_hash` changes (coach edited today's workout,
weather changed by > 3°F dew point, etc.).

---

## 4. Edge function — `generate-morning-brief`

### Contract

```
POST /generate-morning-brief
body: { user_id: uuid, brief_date?: "YYYY-MM-DD" }  // brief_date defaults to user's local today
auth: user JWT OR service role (for cron)
```

### Logic

1. Resolve the athlete's local date (see §7 Q1 — timezone).
2. Check `morning_briefs` for an existing row for (user, date).
3. If exists, compute current `context_hash`. If hash unchanged, return cached brief.
4. If no row OR hash changed materially, assemble `BriefContext`:
   - `today`: lookup `scheduled_workouts` where `scheduled_date = brief_date`
   - `yesterday`: lookup yesterday's scheduled + training_log
   - `week_context`: aggregate last 7 days of training_logs + athlete_pace_profile
   - `plan_context`: lookup active `training_plans` + week math
   - `weather`: call Open-Meteo via `_shared/weather.ts`, compute adjustment via `_shared/pace-heat-adjustment.ts`
   - `coach_note`: lookup `coach_notes` (new table? or reuse `plan_adjustments` for now)
5. Build the LLM prompt (see §5 prompt architecture).
6. Call the multi-model router. Target latency < 2s. Preferred model: Claude Sonnet (voice consistency) with Gemini fallback for cost.
7. Parse response, validate word count (50–120), validate no emoji.
8. Upsert `morning_briefs` row.
9. Return brief.

### Prompt architecture

System prompt (v1 — iterate):

```
You are the coach of a competitive distance runner. Write a short morning
brief — 60 to 100 words, three to five sentences. The athlete will hear
you speak this in 60-90 seconds.

Voice: warm, direct, measured. You know this athlete's training.
You do not motivate with hype. You do not use emoji. You do not use
"awesome", "crush it", "you've got this". You do not ask questions.
You do not moralize about missed workouts.

You mention:
- What today asks of them, in one sentence
- One piece of context from yesterday or this week that matters for
  how to approach today
- Any heat adjustment if the dew point warrants it
- Where today fits (tomorrow's session, or the race, or the block)

You do not mention every data point. You pick the one or two that matter.
You write like the athlete's coach would text them, if the coach had all
the context the app has.
```

User prompt: the `BriefContext` serialized as structured JSON plus any
coach notes verbatim.

Keep prompt_version versioned so we can A/B over time.

### Trigger modes

**v1: Lazy (on-demand).** iOS/web hits the edge fn on first open of the
day. Simple, works from day one, no timezone scheduling needed.

**v2: Eager (cron).** Pre-generate for all active users at their local 5am
via `pg_cron`. Eliminates the 1–2s loading state on app open. Requires
knowing each user's timezone (see §7 Q1).

Start lazy. Move to eager when latency complaints arrive.

---

## 5. iOS + web UI

### iOS — Plan tab header card

Placement: top of the Plan view, above everything else, when
`morning_briefs.opened_at` for today is null OR within the last 4 hours.

```
┌─────────────────────────────────────────┐
│ THIS MORNING · FRI                   ⌄  │
│                                         │
│ Today's the 5×1mi tempo you've been     │
│ pointing at — 5:52 pace, 90s jog rest.  │
│ Yesterday's long run came in steady,    │
│ so you're coming in legal. First rep    │
│ will feel off. That's normal.           │
│                                         │
│ ▶ Play  (1:07)                          │
│                                         │
│ [ Start workout ]  [ Log feeling ]      │
└─────────────────────────────────────────┘
```

After first read, card collapses to a one-line strip:
```
┌─────────────────────────────────────────┐
│ This morning · Fri               ⌃      │
└─────────────────────────────────────────┘
```

Tap to re-expand. Strip disappears at local midnight.

### Web — `/plan` header

Same shape, card at the top of the This Week view. Collapses the same
way. Shared React component; iOS implementation is a SwiftUI mirror.

### Audio playback

- **v1: Native TTS.** iOS `AVSpeechSynthesizer` with a warm female voice (or athlete-picked). Free, offline, instant. Robotic but acceptable.
- **v2: ElevenLabs-rendered audio.** Pre-generated at brief creation time, stored in Supabase Storage, URL in `morning_briefs.audio_url`. Better voice quality. Costs money. Gate behind premium tier.
- **v3: User voice picker.** Choose from 3–5 coach voices (measured, brisk, warm). Persona stays consistent across briefs.

Start with v1. ElevenLabs is a premium upgrade, not a launch requirement.

---

## 6. Phases

### Phase 1 — foundation (DB + edge fn)
- [ ] Migration for `morning_briefs` table
- [ ] `_shared/brief-context.ts` — assembles `BriefContext` from DB
- [ ] `generate-morning-brief` edge function
- [ ] Lazy trigger: call on demand, cache per day
- [ ] Tests: happy path, rest day, missed yesterday, first day of plan, race day

### Phase 2 — iOS surface
- [ ] `MorningBriefCard` SwiftUI component at top of Plan view
- [ ] Collapse/expand interaction
- [ ] Native TTS playback
- [ ] Track `opened_at`, `played_at`, `dismissed_at` via PATCH to `/api/morning-brief/:id`
- [ ] Handle 3 edge states: no active plan, no brief yet today, brief loading

### Phase 3 — web surface
- [ ] React `<MorningBriefCard>` in the `/plan` page header
- [ ] Same shape, same copy, same interactions

### Phase 4 — polish + signal
- [ ] Eager cron at local 5am for users with active plans + known timezones
- [ ] Coach can leave a per-week note that gets woven into briefs
- [ ] Prompt v2 with A/B split to measure "played_at" rate
- [ ] Sentiment of the brief logged for retrospective review

### Phase 5 — ElevenLabs voice
- [ ] Voice persona selection in athlete settings
- [ ] Pre-render at brief generation, store in Storage
- [ ] Fallback to native TTS on failure
- [ ] Rate-limit to 1 regeneration per day per user

### Phase 6 — coach visibility
- [ ] Coach portal: see any athlete's brief for today
- [ ] Coach can "flag for review" if a brief was off-base
- [ ] Flagged briefs go into a feedback loop for prompt tuning

---

## 7. Open questions

1. **Timezone.** Where does the athlete's local morning come from? Options: (a) `user_profiles.timezone` explicitly set during onboarding, (b) inferred from HealthKit workout timestamps, (c) passed from the client on every call. Proposal: (a) with (c) as fallback. Needs a one-line onboarding question.

2. **"Morning" definition.** 4am–11am local? What about night-shift workers or athletes who run at 9pm? Proposal: brief appears from 4am local and stays available until midnight. Don't assume they'll open the app at 6am.

3. **Rest days.** Does the brief fire? Proposal: yes, with a different structure — shorter, more about recovery and tomorrow. Examples already include a rest-day sample.

4. **First day of plan.** No yesterday to reference. Proposal: brief acknowledges it — "First day of the build. Let's start clean."

5. **HealthKit sync lag.** Yesterday's run might not be synced when the brief fires. Proposal: check sync state; if yesterday's workout is "scheduled but not completed" AND the user has a HealthKit run matching the date, wait up to 60s for sync OR include a line "your run yesterday isn't synced yet — check it fed in."

6. **Coach note weaving.** If the coach leaves a note ("take Friday easy, we're pushing the tempo to Sat"), does the LLM quote it verbatim, paraphrase it, or simply surface it as a separate quoted block? Proposal: the brief paraphrases in its voice, and a small "Coach's note" pill below shows the raw coach text.

7. **Regeneration policy.** When does a brief get regenerated? Proposal: only if today's `scheduled_workout.rationale_short` changed, or dew point shifted > 3°F, or a new coach note appeared. Otherwise serve cached. Limit to max 3 regenerations per day.

8. **Voice persona vs coach persona.** If an athlete has a real coach, does the brief voice match the coach's tone? Hard problem. v1: single voice across all athletes. v2: coach can set a voice for their athletes. v3: coach actually records templates and we TTS with their voice (ElevenLabs voice clone, consent-gated).

9. **Quality audit loop.** How do we catch bad briefs? Proposal: athlete dismiss-without-play is a soft signal; coach "flag for review" is a hard signal; weekly sample of briefs reviewed by Rio for voice drift.

10. **What if there's no workout today and no plan?** Proposal: no brief. Don't manufacture one.

11. **Privacy.** The brief contains the athlete's mileage + pace. Is the audio URL guessable? Proposal: signed URL scoped to the authenticated user, expires after 24h.

12. **Model choice.** Claude Sonnet for voice consistency, Gemini for cost. Proposal: A/B split 80/20 and measure `played_at` + dismissal rate. Iterate.

---

## 8. Immediate next step

Pick one:

**(a) Phase 1 — ship the DB + edge fn.** Migration for `morning_briefs` + context assembler + edge function with prompt v1. No UI yet. Can be tested via curl. ~3 hrs. Unblocks phases 2–5.

**(b) Write 20 example briefs in your voice.** Before the LLM writes any, you write 20 across the spectrum (rest, easy, quality, long run, race, race week, missed yesterday, travel, etc.). Those become the prompt's few-shot examples AND the quality bar. No code. ~1 hr. Highest leverage of any step because voice lives or dies here.

**(c) Pick the onboarding question.** Add "what timezone are you in" and "what's your usual run start time" to onboarding. Small, unblocks eager generation in phase 4. ~30 min.

**(d) Build the iOS card UI without the edge fn.** Mock the brief with a local string, wire the expand/collapse/play/dismiss interactions, ship to TestFlight, feel the UX before committing to the backend shape. ~2 hrs.

**My recommendation: (b) first.** Voice is the whole feature. Until you've written 20 examples in your actual voice, the LLM has no target. Then (a), then (d) with a real brief.

---

*Companion docs: `docs/athlete-plan-ux.md`, `pace-system-rework.md`,
`docs/build-adaptive-plan-suspension.md`, `brand-voice.md` (to be written
if not yet).*
