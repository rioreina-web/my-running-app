# Runner analytics — candidate menu

Working brainstorm for Post Run Drip. Your six, sharpened, plus eight more.

Each entry: **what it says → why Maya cares → what data it needs → beta or later.**

House rules this list is written against (from `CLAUDE.md`): AI advises, never
acts. Detection, not diagnosis. Niggles are surfaced, never interpreted. Every
observation cites a number. Cross-training stays out of running-fitness math.

---

## Your six, sharpened

### 1. HR drift — long runs and fast segments

**Says:** How much your heart rate climbs across a run at steady pace. First-half
vs second-half HR:pace ratio. Above roughly 5% drift = the aerobic system is
being taxed harder than the pace suggests.

**Why she cares:** This is the single cleanest read on whether the aerobic base
is actually building. A long run where drift falls from 8% to 4% over a training
block is fitness, even if pace never changed.

**Data:** HR stream + pace stream + a steady-state segment detector (you need to
exclude hills, stops, and the surge at the end). Grade-adjust the pace or drift
on hills will read as fatigue.

**Watch out:** Optical wrist HR is noisy at the start of runs (cold arms, cadence
lock). Consider gating this metric on chest-strap or high-confidence data, or
show it with a confidence tier the way you do race predictions.

**Beta.** You already have the fast-segments prototype.

---

### 2. Session spike vs 30-day longest run — the 10% line

**Says:** Was today's run more than 10% longer than the longest run in the
previous 30 days? Flag as a spike, sized by magnitude.

**Why she cares:** [Frandsen et al., BJSM 2025](https://pubmed.ncbi.nlm.nih.gov/40623829/)
— 5,205 runners, 588,071 sessions, 18 months. 35% got an overuse injury. Risk
rose meaningfully once a single session exceeded 10% of the 30-day longest run,
and climbed steeply from there. This is the best-evidenced load rule in
recreational running right now, and it's *per session*, which makes it far more
actionable than a weekly ratio.

**Data:** Just distance + date. Cheapest high-value metric on this list.

**Design note:** This is also a *prospective* metric, not just retrospective —
"your ceiling this week is 14.3 mi" is more useful than "you went 22% over on
Sunday." Show the ceiling before the run, the spike after.

**Beta. Do this one first.** It's the highest value-to-effort ratio here.

**Related:** worth showing your ACWR next to it with humility. ACWR has taken a
real methodological beating — see the [2025 systematic review and
meta-analysis](https://pmc.ncbi.nlm.nih.gov/articles/PMC12487117/) and
[Impellizzeri et al. on its conceptual pitfalls](https://www.researchgate.net/publication/341936245_AcuteChronic_Workload_Ratio_Conceptual_Issues_and_Fundamental_Pitfalls).
It's a reasonable rhythm indicator, a poor injury predictor. The session-spike
rule has better evidence behind it; consider making that the headline number and
ACWR the supporting context, not the reverse.

---

### 3. HR at pace zones — the efficiency curve

**Says:** For each zone (Easy / MP / HMP / LT), your average HR at that pace,
tracked over weeks. Falling HR at fixed pace = aerobic fitness. Rising = fatigue,
heat, or illness.

**Why she cares:** It's the one chart that answers "am I actually getting fitter?"
without needing a race. It also catches overreaching early — HR at MP creeping
up over three weeks while pace holds is a real signal.

**Data:** HR + pace + your existing 10-zone taxonomy. Needs enough samples per
zone; Easy will have dozens, Mile will have three. Only plot zones with real
density, and gate it on `data_depth ≥ 2`.

**Be careful:** heat and sleep move this line as much as fitness does. Which is
why #5 and #12 aren't optional extras — they're the correction terms that make
this chart honest.

**Beta.**

---

### 4. Workload summary — load, mood, niggles together

**Says:** One weekly strip: volume, load change, mood distribution, niggle
mentions. Not three charts — one aligned timeline.

**Why she cares:** The value is *co-occurrence*, and it's the thing no other
running app can do because no other app has her voice logs. "Left calf mentioned
four times in the ten days after your two biggest weeks" is a sentence Strava
structurally cannot write.

**Data:** You have all of it — `body_mentions`, mood labels, volume.

**Framing rule:** state the co-occurrence, never the causal claim. "Mentioned
four times following your two biggest weeks" is fine. "Your calf pain is caused
by the volume jump" violates hard rule #2. Let the timeline do the arguing.

**Beta.** This is your differentiator.

---

### 5. Heat and humidity — the honesty correction

**Says:** Pace and HR adjusted for conditions, so a 78°F/85% humidity run isn't
logged as a fitness decline. Plus heat acclimation tracking: your HR penalty at
a given temp should shrink over ten to fourteen days of exposure.

**Why she cares:** Summer training reads as regression on every uncorrected
chart. Runners quit blocks over this. A metric that says "you're 18s/mi slower
but 0s/mi slower once adjusted — that's conditions, not you" is genuinely
protective of morale, and it's true.

**Data:** You have `fetch-workout-weather`. Temperature + dew point (dew point
matters more than relative humidity). A published heat-pace adjustment table
gets you most of the way.

**Hydration/nutrition:** I'd separate this. Sweat-rate estimation needs
pre/post weight, which she won't log reliably. What *is* feasible for beta:
sweat-loss estimate from duration + temp + body weight, expressed as a fluid
target for runs over 90 minutes, and a carb target (roughly 60–90 g/hr for long
efforts). That's a calculator, not an analytic — treat it as such.

**Beta for the pace correction. Later for the fueling side.**

---

### 6. Easy vs quality — the intensity distribution

**Says:** Weekly split of time (not mileage — time) across effort bands. The
polarized/pyramidal target is roughly 80% easy, 20% hard.

**Why she cares:** The most common self-coached failure mode is running easy days
too hard and hard days too easy, which produces a grey middle that builds
nothing. Seeing "62% easy" in a week she thought was easy is a genuinely
uncomfortable, genuinely useful number.

**Data:** Time-in-zone from your pace spectrum. Use *time*, not distance —
distance under-weights the slow stuff and the whole point is what the body
experienced.

**Sharpen it:** Split into two separate numbers, because they're different
problems:

- **Session mix** — how many key sessions vs easy runs (your #6)
- **Easy-run discipline** — of the miles you *intended* easy, what % actually
  landed in the Easy band? This is #10 below and it's the more actionable half.

**Beta.**

---

## Eight more

### 7. Felt vs measured — the gap

**Says:** Where her subjective read diverges from the objective data. Sessions
where HR and pace say "routine easy run" but the voice log says "that was
brutal." Tracked as a running gap, not a one-off.

**Why she cares:** This is the earliest overreaching warning that exists. RPE
rises before HR does, before pace does, before performance drops. A three-run
streak of "harder than the numbers say" is a real flag — days before ACWR
notices anything.

**Data:** Voice-log sentiment/effort language + mood label, against HR-at-pace
for that session. You'll need to extract a coarse effort read from the transcript
(easy / normal / hard / brutal), which is a small classifier not unlike the
niggles one — closed vocabulary, quote verbatim.

**Why it matters strategically:** every other metric on this list is available
in Garmin Connect, TrainingPeaks, or Runalyze. This one is only possible if you
have the athlete's voice, and you do. If you build one thing from this list that
isn't the 10% rule, build this.

**Beta. This is the moat.**

---

### 8. Durability — what happens after 90 minutes

**Says:** Not "how fast can you run" but "how much of that speed survives two
hours of prior work." Measured as the decline in speed at a fixed HR (or the
rise in HR at fixed pace) between the first and last quarter of long runs, and
as the pace decay across the closing miles.

**Why she cares:** This is the marathon question. Maya's 5K fitness predicts a
3:12; her legs at mile 22 deliver 3:28. The gap *is* durability, and it's
trainable separately from VO2max. It's also the hottest area in endurance
physiology right now — see Hunter et al. 2025 on
[durability during marathons](https://www.tandfonline.com/doi/full/10.1080/02640414.2025.2567780)
and the [methodological considerations paper](https://pmc.ncbi.nlm.nih.gov/articles/PMC12576026/)
on how to actually index it.

**Data:** Long-run HR + pace streams, split by elapsed time (not distance).
Grade-adjust. Needs runs over ~75 minutes to mean anything, so it's a
long-run-only metric.

**Distinct from #1:** HR drift is a within-run cardiac measure across any steady
effort. Durability is specifically about *reserve after accumulated load* — what
the legs have at 90+ minutes. Related, not the same. Show them together on the
long-run detail view.

**Beta-feasible, and it's a genuinely differentiated headline metric.**

---

### 9. Speed-vs-endurance profile

**Says:** Plot every race and time trial on one equivalence curve. If her 5K
predicts a 3:12 marathon and her half predicts 3:22, she's speed-rich and
endurance-poor. The shape of the curve tells her what to train.

**Why she cares:** It converts "what should I work on" from a guess into a
reading. It's also the most natural home for your race-anchor system —
`confirmed_races` already exists and this is the chart that makes it earn its
keep.

**Data:** `confirmed_races` + your existing race-equivalence ratios in
`workout-helpers.ts`. Almost no new math.

**Presentation:** per hard rule #7, single number + confidence tier + lifetime PR
alongside. Don't ship a band.

**Beta.**

---

### 10. Easy-run discipline

**Says:** Of the miles she *intended* to be easy, what percentage actually landed
in the Easy band? Plus the average overshoot in seconds per mile.

**Why she cares:** "Your easy runs averaged 8:42 this month. Your Easy band tops
out at 9:05." That's a specific, fixable, ego-bruising fact. Chronic easy-day
overshoot is why blocks stall, and almost nobody self-diagnoses it.

**Data:** Planned workout type + actual time-in-zone. You have both.

**Beta. Cheap and high-impact.**

---

### 11. Key-session execution — rep decay

**Says:** For a structured session (5×1km at 5K pace): did she hit the target,
and how did rep pace and HR move across reps? Positive split across reps =
started too hot or underfueled. Flat = well-judged. Negative = held back, or
strong.

**Why she cares:** Pacing judgment is a trainable skill and this is the only
mirror for it. Over a block, "your rep decay went from 6s to 2s across reps"
is a fitness signal that's independent of absolute pace.

**Data:** Lap/interval detection from HealthKit workout segments, matched
against the planned workout. You have `key-sessions-prototype.html` already
pointed this direction.

**Beta.**

---

### 12. Recovery signal — resting HR, HRV, sleep vs load

**Says:** 7-day rolling resting HR and HRV against training load. A sustained
RHR elevation of 5+ bpm over baseline following a load spike is a real
overreaching flag.

**Why she cares:** It closes the loop on pillar 3. It also gives the "push or
pull today" question an actual input rather than a vibe.

**Data:** HealthKit already gives you RHR, HRV (SDNN), and sleep. No new
integration.

**Careful:** HRV is famously noisy night to night and misused constantly. Never
show a daily HRV number as a verdict. Rolling 7-day baseline, deviation bands,
and no "readiness score" — a single composite number invites exactly the
prescriptive posture your hard rule #2 forbids.

**v1.5, matching your pillar sequencing.**

---

### 13. Consistency and the long-run ratio

**Says:** Two simple things nobody surfaces well.

- **Consistency:** longest unbroken training streak, weeks hitting planned
  volume, gaps over four days, and the down-week rhythm (is she actually
  backing off every 3rd or 4th week, or just claiming to?).
- **Long-run ratio:** long run as a % of weekly volume, and as a % of goal race
  distance. Above ~35% of weekly volume in one run is the classic
  "one big Sunday, nothing else" pattern.

**Why she cares:** Consistency beats peak weeks for marathon outcome, and it's
the least glamorous, least-tracked thing in the sport. Also: the down-week check
is the one place a self-coached runner reliably lies to herself.

**Data:** Distance + date. Trivial.

**Beta. Nearly free.**

---

### 14. Cadence and form drift under fatigue

**Says:** Cadence in the last third of long runs vs the first third. A drop of
4+ spm is a mechanical fatigue signal — stride collapsing, ground contact
lengthening.

**Why she cares:** It's the closest thing to an injury-mechanism signal you can
get without video, and it pairs directly with the niggles timeline. Cadence
collapse and calf mentions in the same fortnight is a pattern worth her seeing.

**Data:** HealthKit cadence. Available, underused.

**Careful:** this is exactly where hard rule #2 bites. Show the number and the
co-occurrence. Never say "your form is breaking down" or "this is causing your
shin pain."

**Later. Nice-to-have, not beta-critical.**

---

## If you can only build four for beta

1. **#2 session spike vs 30-day longest** — best evidence, cheapest data, works
   from day one with zero HR requirement
2. **#7 felt vs measured** — nobody else can build it
3. **#3 HR at pace zones** — the "am I getting fitter" chart, with #5's heat
   correction applied so it doesn't lie in July
4. **#10 easy-run discipline** — cheap, specific, immediately actionable

Everything else layers on top of those without rework, which matters given you
want the beta to grow into the real product rather than be thrown away.

## Two structural notes for a beta that has to grow

**Compute metrics from stored streams, not on the fly.** Store the raw HR/pace/
cadence streams per run and derive metrics in a separate layer. When you change
the drift formula in six months you want to recompute history, not lose it.

**Every metric needs a confidence tier from day one.** You already do this for
race predictions. The same discipline applied to drift (chest strap vs wrist),
heat adjustment (weather station distance), and zone density (three samples vs
thirty) is what keeps the product honest as data quality varies. Retrofitting
confidence later is painful; designing for it now is nearly free.
