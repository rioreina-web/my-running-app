# What Runners Want From an AI Running App — and What They Don't Know

Research synthesis · 2026-06-25 · tied to the Maya wedge

This is a secondary-research brief: what the market and the literature
already tell us about runner demand, the gaps in today's AI running apps,
and the blind spots runners have. It's framed against our canonical
persona, Maya (self-coached, race-history-anchored, wants honest
observation without prescription). A short interview guide is at the end
so you can validate these claims with real runners before betting on them.

---

## The two questions, answered in one line each

**What are users *looking for*?** A plan that bends to their real life and
body — plus the accountability, motivation, and reassurance a human coach
gives. They ask for *personalization* and *adaptation*.

**What do they *not know*?** That the plan was never the hard part.
Runners don't know how to read their own training (easy vs. hard, load
vs. recovery), they conflate *data* with *insight*, and they
systematically underrate rest. The biggest value is in interpretation and
honesty, not in another generated schedule — and most of them can't
articulate that want yet.

---

## Part 1 — What runners say they want (stated needs)

### 1. Adaptation to real life, not a fixed calendar
The loudest, most consistent complaint about every incumbent. Pre-built
plans "assume you know how a training block will unfold before it even
begins." Garmin's own users describe the feeling as *"here's what Coach
Jeff thinks you should do,"* not *"here's what you need based on how
you've been running lately."* Even adaptive tools fail the opposite way —
Garmin's suggested workouts "can change overnight," so runners can't plan
their week. The wanted middle ground: a plan that reads fitness, recovery,
and life stress and **adapts around life rather than treating life as a
barrier.**

> Directly validates our journey-centric framing. `activePlan == nil` as a
> first-class state, and Train showing past + planned together, is the
> structural answer to "the calendar is rigid." This is our wedge, and the
> market is actively complaining about its absence.

### 2. Specificity they can trust
Runners like knowing *exactly* what a session is and why — numbers, paces,
purpose. Runna's strongest reviews praise this. But specificity cuts both
ways (see blind spots): false precision erodes trust the moment a runner
beats a "projected" number by a minute.

> This is why our **range + confidence** rule (no `3:09:30 PROJECTED
> FINISH`) is a feature, not a hedge. Honest specificity is rarer than
> specificity.

### 3. The things a plan *can't* give: accountability, motivation, reassurance
When you ask why runners hire human coaches, the plan is rarely the top
answer. They pay for *skin in the game* (someone expects them to show up),
for a *sounding board* during hard patches, for help *finding the joy*,
and to **offload the mental load of deciding.** "Many runners simply don't
want to think about the details." Coaches reduce decision fatigue and
provide emotional steadiness — *"training should enhance your life, not
become another source of stress."*

> This is the part almost no AI running app delivers, and it's our Coach
> surface's actual job: feeling-first, warm, reads life context, ends in
> soft questions. The market gap isn't "better algorithm" — it's "a
> coach's posture."

### 4. Injury & illness handling that actually exists
A recurring concrete complaint about Runna: no clean way to **pause for
sickness or injury**, or to bail on a workout and restart. Runners feel
trapped by a plan that doesn't acknowledge they're human.

> Our Niggles surface (detection-not-diagnosis) and the "AI advises, never
> acts" stance is the safe version of this. Note the live tension below.

### 5. Boring-but-decisive: reliability and fair billing
Glitchy syncs (especially Garmin), slow data, and surprise auto-renewals
show up in review after review. Table stakes — but they sink trust fast.

---

## Part 2 — What runners *don't* know (latent needs / blind spots)

This is where the real product opportunity is, because nobody is asking
for these things by name.

### A. They don't know easy should be easy
Most recreational runners run every session at the same medium-hard
effort. ~80% of mileage should be conversational; instead runners "think
every run should feel hard to be effective," which leaves them too tired
to hit the genuinely hard sessions and too fatigued to recover. They will
not ask you for "polarization." They *will* respond to an app that gently
shows them they ran their easy day at tempo pace again.

### B. They systematically underrate rest
Runners "do not rest enough," feel *guilty* about rest days, and fear
losing fitness — when the opposite is true. There's a subtle trap too:
the moment recovery becomes a checklist item, "it becomes a stress." So
the answer isn't a Recovery to-do list; it's reframing rest as part of the
work. This is a voice/tone problem as much as a feature.

### C. They confuse data with insight
Garmin/Strava already give runners oceans of numbers. The frustration in
the reviews isn't *missing data* — it's that "the software doesn't evolve
at the same pace as the data collection." Runners don't need more metrics;
they need someone to **tell them what the metrics mean for them this
week.** Interpretation is the unmet need hiding behind the request for
"personalization."

### D. They can't see their own load spikes
The injury literature is blunt: ACWR above ~1.5 raises injury risk
sharply (up to ~50% higher at ≥1.8); the safe band is 0.8–1.3; the "10%
rule" exists because runners reliably ramp too fast. Runners get hurt from
**training error**, not bad luck — and they can't feel a load spike
happening. The wave of "I got injured following an AI plan" posts is
exactly this blind spot, automated.

> Our `loadSpikePlusInjury` rule and ACWR surfacing target this directly.
> The catch: surfacing it for a *self-coached* runner (no coach in the
> loop) without tipping into medical/stop-training advice is the hard
> design problem. See open question 2.

### E. What they're really buying is *consistency*, and apps lose them anyway
80% of fitness-app users quit within 3 months; ~70% within 100 days;
day-30 retention is often 3–12%. People quit at plateaus, after a missed
streak, or from "choice paralysis" (too many options on open). What
keeps them: low-friction habit, a sense of progress, and — notably —
apps with **social/streak features retain ~5x better** than solo models.
Runners think they want a plan; what they need is something that survives
the missed week without making them feel like a failure.

> Implication: the "missed week" moment is the most important screen in
> the product, and it's usually the worst one in competitors (a red broken
> streak). Our empty-state discipline and warm voice are retention
> features, not polish.

---

## Part 3 — The synthesis: where the gap actually is

Stack the findings and a clear picture emerges. Today's AI running apps
compete on **plan generation**, which is now commoditized and, worse,
actively hurting people who can't read the plans. The genuinely unmet
needs cluster somewhere else:

1. **Interpretation over generation** — "what does my data mean for me
   right now," in plain language.
2. **A coach's posture** — accountability, reassurance, joy, decision-
   relief — the emotional layer no algorithm currently occupies.
3. **Honesty** — ranges not false precision; surfacing load risk without
   alarmism or diagnosis.
4. **Surviving the messy middle** — illness, injury, missed weeks, life —
   without punishment.

That is almost exactly the product described in CLAUDE.md: voice-log
signal fused with quantitative data, "coachable moments," AI advises
never acts, feeling-first Coach Read. **The research says the wedge is
real and largely uncontested.** The risk is not the idea; it's execution
on the two hard tensions below.

---

## Part 4 — Two tensions the research surfaces for *our* product

**1. "Honest observation without prescription" may frustrate before it
delights.** Runners are *trained by incumbents* to expect "do this
workout." A product that observes and asks soft questions can read as
"it didn't tell me what to do." The non-prescription stance is right and
differentiated — but onboarding has to *teach the value of it*, or early
users churn confused. Worth testing explicitly.

**2. Self-coached + load-spike detection is a safety tightrope.** With no
coach in the loop, who catches Maya before an injury? Our rules stay
"observe, don't prescribe / don't diagnose." The research shows the need
is real (training-error injuries are the #1 cause) but also that runners
*don't perceive the spike themselves*. Surfacing "your last 7 days are a
sharp jump from your norm" is observation; "take a rest day" is
prescription. The line is narrow and worth pressure-testing with real
runners and, ideally, a coach advisor.

---

## Part 5 — Validate before you build: a 5-runner interview guide

Don't take this brief as truth — it's the market's *aggregate*, not your
users. Five to eight 30-minute interviews with self-coached runners who
have race history (Maya-shaped) will confirm or kill the assumptions
cheaply. Recruit from running subreddits, local clubs, or Strava.

**Warm-up (5 min)** — Tell me about your running right now. What are you
training for, if anything?

**Current behavior (10 min)** — no leading questions
- Walk me through how you decided what to run this week.
- What apps/tools are open when you do that? What do you actually look at?
- Last time you felt off or tired — what did you do? How did you decide?
- Tell me about the last time you got injured or had a niggle. What
  happened in the weeks before?

**Probe the blind spots (10 min)** — listen for whether they surface
these *unprompted* before you ask
- How do you know if an easy run was actually easy enough?
- How do you decide when to take a rest day? How does taking one feel?
- When you look at your data, what do you wish it told you that it doesn't?
- Have you ever followed a plan that didn't fit your week? What did you do?

**Reaction (10 min)** — show the concept, watch the face
- React to: an app that *observes and asks questions* instead of telling
  you what to do. First gut reaction? (This tests Tension #1.)
- React to: "your fitness is somewhere between a 3:08 and 3:14 marathon,
  high confidence" vs. "projected finish 3:11:30." Which do you trust?
- React to: a voice memo after a run that the app reads back to you
  weeks later alongside your numbers.

**Wrap (5 min)** — If a coach friend texted you one thing each week, what
would you want it to be? Anything I didn't ask about that matters?

**What to listen for:** Do they describe *interpretation* hunger
(blind spot C) without prompting? Do they defend running easy days hard
(blind spot A)? Does the non-prescriptive concept relieve or frustrate
them (Tension #1)? Those three answers should shape the roadmap more than
any feature request.

---

## Sources

- [Best AI Running Coach Apps 2026 — The Running Genie](https://therunninggenie.com/blog/best-ai-running-coach-apps)
- [Runna App Store reviews](https://apps.apple.com/us/app/runna-running-plans-coach/id1594204443?see-all=reviews) · [Runna on Trustpilot](https://www.trustpilot.com/review/runna.com)
- [Are AI training apps like Runna putting you at risk of injury? — TechRadar](https://www.techradar.com/health-fitness/are-ai-training-apps-like-runna-putting-you-at-risk-of-injury-i-asked-a-real-life-running-coach)
- [Garmin has all my data — so why did Runna build me a better plan? — UX Collective](https://uxdesign.cc/garmin-has-all-my-data-so-why-did-runna-build-me-a-better-training-plan-915f4ff316b5)
- [AI Running Plans: Pros, Cons — None to Run](https://www.nonetorun.com/blog/ai-running-plans-pros-cons)
- [Why Training Plans Don't Work — Miles and Mountains Coaching](https://www.milesandmountainscoaching.com/post/why-training-plans-dont-work)
- [Why do users abandon fitness apps? — Autentika](https://autentika.com/blog/why-do-users-abandon-fitness-apps)
- [Retention Metrics for Fitness Apps — Lucid.now](https://www.lucid.now/blog/retention-metrics-for-fitness-apps-industry-insights/)
- [Why Most Fitness Apps Lose 80% of Users in 30 Days](https://vocal.media/01/why-most-fitness-apps-lose-80-of-users-in-30-days)
- [When and Why Adults Abandon Lifestyle/Mental Health Apps — NCBI](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC11694054/)
- [Acute-to-Chronic Training Ratio for runners — Full Speed Performance](https://www.fullspeed-performance.com/using-the-acute-to-chronic-training-ratio-for-runners-prevent-or-predict-injuries/)
- [Train Smarter: Training Load & ACWR — PFM Coaching](https://www.pfmcoaching.co.uk/blog/reduce-injury-risk-with-the-acute-chronic-workload-ratio)
- [The When, How, and Why of Hiring a Running Coach — Bakline](https://www.bakline.nyc/blogs/legwork/05-the-when-how-and-why-of-hiring-a-running-coach)
- [What Does a Running Coach Do? — ISSA](https://www.issaonline.com/blog/post/what-does-a-running-coach-do)
- [Your Easy Days are Ruining Your Training — Runners Connect](https://runnersconnect.net/easy-days-easy/)
- [You Avoid Junk Miles. But Your Rest Days Are Junk, Too — Outside](https://run.outsideonline.com/training/you-avoid-junk-miles-but-your-rest-days-are-junk-too/)
