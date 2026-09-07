# Trends & Analytics Audit — 2026-08-05

Scope: the live Trends tab (`TrendsV2View`), the DEBUG-only legacy tab, and the satellite analytics surfaces (Race Prediction, Fitness Predictor, Pace Signal, Signal Lab, Head-to-Head Compare). Every claim below was checked against the current source; file references are included so a coding agent can act on them directly. This builds on your 2026-08-03 audit rather than repeating it — where that audit's fixes shipped, they're credited.

---

## 1. Overall verdict

**The live Trends page is the best-designed version this app has ever had — and it ships with its centerpiece metric mathematically broken, while most of the app's analytics horsepower is unreachable in a release build.**

| Surface | Rating | One-line verdict |
|---|---|---|
| The Read (headline + chips) | **7/10** | Honest, well-written, but its deltas are biased by partial weeks |
| Five Signals lanes | **8/10** | The strongest chart in the app; accessibility and week drill-down are the gaps |
| Recovery Score ledger | **5/10** | Best *transparency pattern* in the product; the arithmetic it discloses is wrong, and the fix sits unwired in the same folder |
| What Lines Up (findings) | **7/10** | Careful, small-n-honest; only three findings, all correlational |
| Race Prediction | **5/10** | A data-fetch bug can make "today's" trend show your oldest history; ships without the PR your own hard rule #7 requires |
| Fitness Predictor | **6/10** | Rich and reachable, but explains a range it no longer shows, and can contradict Race Prediction's number |
| Pace Signal (spectrum/over-time) | **6/10** | Good viz; timezone split-brain, a broken custom range, and a 20-mile clipping ceiling |
| Signal Lab | **n/a** | Genuinely good content with **zero call sites** — no user has ever seen it |
| Head-to-Head Compare | **6/10** | Clever, coach-like; unreachable in release |
| **Overall** | **6.5/10** | Design maturity ~8, metric correctness ~5, release-build breadth ~4 |

The structural story: the 08-03 audit's headline pathology — "47% of the tab can't be reached in a release build" — was fixed by shipping v2, and then **immediately recurred at larger scale**. The Trends+Analysis folders are now ~16,500 lines (up from 3,912 at the last audit), and the majority is orphaned: two dead Trends generations, an unreachable Signal Lab, sample-data files, and a corrected recovery-score implementation that nothing calls. A release-build user opening Trends sees *no pace, no heart rate, and no race prediction anywhere on the tab.*

---

## 2. The live Trends page, section by section

### 2.1 The Read — 7/10

What's right: a computed headline with an explicit noise guard ("inside the week-to-week noise… Nothing is proven here yet", `TrendsSignalModels.swift:753`) is rare product honesty, and the five verdict chips give the page a spine.

What's wrong:

- **Partial-week bias (the biggest correctness issue on the page).** At 6-month/1-year grain, `weekBuckets` includes the leading partial week and the current in-progress week with no exclusion or normalization (`TrendsSignalModels.swift:445-503`). The Read then compares raw back-half vs front-half means (`:788-796`), so the first bucket (usually a 2–3 day stub) deflates the front mean and this week's stub deflates the back mean. "Load's climbing" can print because of calendar arithmetic, not training. The dead `LoadRead` in `TrendsBlockModels.swift:64-66` solved exactly this ("Full weeks only — a three-day tail week would drag the mean") — the live surface didn't inherit it. Same bias hits the Miles delta chip. At day grain, *today* counts as a full day, so a morning check-in reads a 0-mile "rest day" into the stats.
- **Modal mood tie-break is alphabetical** (`:311`): a month split 5 "energized" / 5 "injured" reads ENERGIZED because E < I. Break ties by severity or recency instead.
- Score precision contradicts its own noise rule: the Recovery section shows "+3 vs yesterday" while The Read declares <3-point recovery moves noise.

### 2.2 Five Signals lanes — 8/10

The shared-axis five-lane Canvas (mileage / key work / recovery / mood / niggles) with scrub + day drill-down is the best chart in the app, and the drag-threshold fix that keeps the page scrollable is documented right in the file. Remaining issues:

- **Accessibility is effectively zero.** The whole five-lane Canvas is one static `accessibilityLabel` (`TrendsSignalLanes.swift:82`) — no per-column values, no `AXChartDescriptor` (audio graph). Mood is also color-only, on adjacent warm hues. For a beta with real users this is the kind of thing App Review and testers will hit.
- **Recovery lane advertises a band no one can reach** (green "Clear" top band, `:400-409` — see §3), and its y-mapping starts at 10 while the score clamps at 8, so floor scores plot below the lane.
- Week-grain gridlines detect month starts by string-prefix on the ISO date (`:238`) — months get zero or double gridlines depending on where Mondays fall. Only 3 x-axis labels across a 53-column year.
- Weekly buckets have no drill-down ("rather than offering a dead tap" — honest, but "show me that week" is the expected affordance and the data is already there).

### 2.3 Recovery Score ledger — 5/10

The receipt pattern — base 50, five factors with evidence lines and the arithmetic string — is the single best idea in the app's analytics. Ship the pattern everywhere. But:

- **The top band is mathematically unreachable.** Live factor maxima sum to 50+10+5+0+4+0 = **69**, against a "Clear" band that starts at **75** (`TrendsSignalModels.swift:610-733`). The scale presents as 8–96 but lives in 9–69. No athlete, however fresh, has ever seen Clear. Your own fix — `TrendsRecoveryFactors.swift`, dated **today**, with 7-day recency-weighted mood, "Clear days" credits, and a max of 78 — **has zero callers**. This is a one-line wiring job away from being the most impactful fix in this report.
- **Mood counts only if logged today** (`:619-627`) — most days the biggest signal in the score is silently zero. (The unwired fix addresses this too.)
- **The footer overclaims:** "four of five inputs are your own words" (`TrendsSignalSections.swift:235`) — it's two of five (Mood, Body mentions); Recent load, Load vs baseline, and Days on are all miles-derived. For a product whose brand is honesty, fix the copy today.
- "Days on" can only subtract (`:717-729`) — a factor that punishes consistency and never rewards it reads as a bug to the athlete staring at the receipt.

### 2.4 What Lines Up — 7/10

The niggle↔key-day linkage with a 60% threshold and full enumeration under small n is well judged. It's just thin: three findings, none of which touch pace, HR, or sleep, because the live page has none of those signals to correlate.

### 2.5 Plumbing (affects every section)

- **The tab caches forever.** `TrendsService.refresh()` is a no-op once loaded (`TrendsService.swift:81-82`) — a run logged after the first tab visit never appears until app restart. For beta users who log a run and immediately check Trends, the page looks broken. Add invalidation on new-workout / on-foreground with a TTL.
- **Custom window is off by up to a day for any non-UTC user.** DatePicker local-midnight dates are compared against UTC-midnight day keys (`TrendsSignalModels.swift:362-372`). You're in America/Chicago — you can reproduce this yourself at the range edges.
- **Recomputation:** `bucketSet` is a computed var that rebuilds everything including the full-history recovery ledger (O(days × 56)), and one render evaluates it at least 3× (`TrendsV2View.swift:65-71, 124, 228, 236`). Memoize keyed on `(window, days.count)`. Fine at 30 days; it will hurt at 1 year on older phones.
- If a forced refresh fails after data has loaded, stale data renders with no staleness indicator (`lastError` set but the non-empty chart wins).

---

## 3. The satellite analytics

### Race Prediction — 5/10

- **Data bug: the snapshot query orders ascending with `.limit(60)`** (`RacePredictionViews.swift:118-123`). Once you have >60 fitness snapshots, this fetches the *oldest* 60, then labels the last of them "TODAY" and snaps it to today's midpoint. The sparkline, "LAST N READS," and delta line silently show ancient history as current. Fix: `ascending: false` + re-sort (or date floor).
- **The file's own header states the retired policy** ("predictions ship as a RANGE + CONFIDENCE, never a single point," `:14-18`) while the code ships a midpoint — and the revised hard rule #7's requirement (lifetime PR alongside) isn't rendered anywhere in the modal, despite a comment claiming it is (`:194-195`).
- The confidence chip renders in mood-green at every tier — "LOW CONF" in the same affirming green as HIGH (`:203-210`), a double violation (tier-invariant + green is mood-only per your palette rule).
- Outlier filtering (±20% of median) silently deletes snapshots with no annotation, and the delta line is a first-vs-last two-point claim — the same class of claim the legacy tab's epitaph bans.

### Fitness Predictor — 6/10

Reachable from three places (`RunningLogApp.swift:365`, `InsightsView.swift:216`, `CoachView.swift:577`) — this is where release users actually get predictions. Issues: the footnote still explains the 80% range that was retired on 07-18 (`FitnessPredictorView.swift:120` vs `:289-291`) — users read an explanation of a number that isn't on screen; "give or take a few seconds" under-states marathon uncertainty; the trend chart applies **no** outlier filter while Race Prediction cleans ±20%, and the two surfaces read from different sources — the same athlete can see **two different marathon numbers** in one session. Pick one prediction source and one presentation, and make the other a view of it.

### Pace Signal — 6/10 (DEBUG-only)

Good spectrum viz with real statistical care (miles-weighted percentile bounds). But: it buckets days in *local* time while everything else on the same page uses UTC (`SignalService.swift:168,188`) — one run, two days, one screen; the custom range **ignores its own dates** and just shows the last N days (`PaceSignalView.swift:192-222`); daily bars clip silently at a hardcoded 20 mi/day (`:625,694`); cross-training is filtered by substring blacklist ("elliptical", "hike", "walk" leak through); its query lacks the explicit `user_id` filter its sibling has; and it still grades ACWR as "safe zone"/"outside" — the framing the rest of the product dismantled.

### Signal Lab — unreachable

Five well-built sections (drift, threshold, HR efficiency, mood×load, heat impact) — exactly the HR-based content the live tab lacks — and **nothing in the entire app constructs it** (verified by repo-wide grep). Its header claims it opens "from the foot of the Trends tab"; that link was never made. This is the cheapest big win in the codebase: one navigation link away from doubling the live tab's analytical depth. (Caveats before linking it: fix the heat copy that misreports why sessions were excluded, and the 160 bpm threshold HR floor calibrated on 19 of your own sessions needs to become zone-relative before other beta users see it.)

### Head-to-Head Compare — 6/10 (unreachable in release)

The deterministic "FROM YOUR COACH" read is a great pattern. But the legacy call site hardwires heat+hills adjustment with no toggle, so every pace shown is conditions-adjusted with only a tiny hint; and the 08-03 audit's "move it to workout detail" never happened — it moved nowhere.

---

## 4. Systemic inconsistencies (the beta-risk layer)

These are the things that make two parts of the app disagree in front of a user:

1. **Load has ~5 definitions** — SignalService's miles-only ACWR, VolumeDetailView's projected-acute ACWR (a big Tuesday can "project" you out of the sweet spot by Wednesday), TrendsBlockModels' week-over-4-week ratio, the ledger's 7-day-vs-8-week, and RecoveryWeekModel's variant. Two can disagree *on the same legacy screen*. Pick one canonical ratio (server-side `athlete_state.acwr` is the obvious candidate) and make everything else render it.
2. **Three recovery philosophies coexist:** the live 8–96 ledger, the legacy readiness /100 tile, and the dead convergence-no-number card — with files literally asserting "there is no 0–100 readiness number and there never will be" (`TrendsRecoveryView.swift:5-8`) in the same folder as the shipped number.
3. **Both pace-axis orientations ship, each citing "the house rule"** — threshold and race charts draw faster-up; ladder and zone detail draw faster-down, and both sides' comments claim theirs is the rule. Decide once, write it in CLAUDE.md, fix the losers.
4. Duplicated logic drift: 5+ pace-zone→color maps (with different fallbacks), 2 severity vocabularies *with different orderings* (calendar ranks sore < tight; canonical ranks tight < sore), 2 mood-color helpers, ~8 ISO-day parsers, 4 month-abbreviation tables, 2 pace formatters. Each duplicate is a future contradiction.
5. Day/mood resolution differs by surface: UTC vs local days; server hardest-session mood vs first-log-wins vs latest-in-window vs modal.
6. **No metric units anywhere.** Every surface is miles and sec/mi, no min/km, no preference. Table stakes before any non-US beta user.

---

## 5. What's missing

Measured against your own docs (runner-analytics-menu 08-02, trends-v2-spec, catalog) and against what an analytics-literate runner expects from a Strava/Garmin/Runalyze-class product:

**Missing and already flagged "do this first" in your own menu:**
- **#2 Session spike vs 30-day longest run** — the menu calls it the best-evidenced, cheapest, most injury-relevant metric ("Do this one first"). Not implemented anywhere. Meanwhile ACWR — which the same doc demotes — still renders on two DEBUG surfaces.
- **#7 Felt vs measured** (mood/voice vs pace/HR divergence) — the menu calls this "the moat"; it's the thing Strava can't copy because they don't have your voice logs. Not implemented.

**Missing on the live tab (exists only in dead/unreachable code):**
- Any heart-rate signal (drift, efficiency, HR-at-pace) — all locked in Signal Lab/dead files.
- Any pace/speed trend — spectrum, threshold miles, pace bands are all DEBUG-only.
- Race prediction and the promised fitness curve with race-anchor markers and a goal line (the goal line is an acknowledged follow-up at `RacePredictionViews.swift:20`).

**Missing entirely:**
- **Sleep/HRV/RHR** — `RecoveryBiometrics` is preview-only; the 08-04 status doc says migrations are written and UI designed, but nothing shipped. Notably `TrendsRecoveryFactors.swift` (today's) contains *no* Overnight/Sleep factor, so the plan and today's code have already diverged.
- **PRs / best efforts** — no lifetime PRs (required next to predictions by your own hard rule #7), no season bests, no best-efforts detection.
- **Period-over-period comparison** — this block vs last block, YoY; the only live comparison is front-half vs back-half of one window.
- Race markers on any timeline, plan-vs-actual compliance (computed server-side, never shown), streak/consistency surfaces, elevation anywhere in trends, export/share, VoiceOver audio graphs, trend fit-quality disclosure (threshold slope prints with no R² from as few as 3 points).

---

## 6. Prioritized roadmap

### Now (this week — correctness, mostly small diffs)
1. **Wire `TrendsRecoveryFactors` into the live ledger** (or port its arithmetic). Unreachable-Clear + today-only mood both die in one change. Update the lane's band drawing and y-floor to match.
2. **Fix The Read's partial weeks:** exclude the leading stub week and normalize/exclude the current week (day grain: exclude today or pro-rate). Steal the dead `LoadRead` logic.
3. **Fix `TrendsService` caching:** invalidate on new workout + on-foreground TTL.
4. **Fix Race Prediction's snapshot fetch** (`ascending: false`) and add the lifetime PR row rule #7 requires.
5. **Fix custom-window UTC/local mismatch** (both v2 and Pace Signal's ignored dates).
6. Copy fixes: ledger footer ("two of five inputs"), Fitness Predictor's retired-range footnote, confidence chip color by tier.

### Next (the beta differentiators)
7. **Link Signal Lab from the foot of the Trends page** (after its heat-copy and HR-floor caveats). Cheapest depth you can add — the code is done.
8. **Build menu #2 (session spike)** as a sixth ledger factor or a Read finding — your own docs rank it first.
9. **Units preference (mi/km)** across all trend surfaces.
10. Give the speed content a release-build home: promote threshold miles + spectrum into a "Speed" section of v2 (with the one window control), or ship the "destination screen" the tab host comment promises. Right now the release answer to "am I getting faster?" is: not on Trends.
11. **One load ratio, one zone-color map, one severity ramp, one ISO parser** — consolidation pass before drift compounds further.
12. Accessibility pass: `AXChartDescriptor` on the lanes, per-column labels, shape/pattern channel for mood.

### Later (the moat)
13. Sleep/HRV wiring per the 08-04 plan → new ledger factors, on the receipt like everything else.
14. **Felt vs measured (#7)** — the defensible feature; you have the data no one else has.
15. Fitness curve with race anchors + goal line; period-over-period compare; PRs/best-efforts.
16. **Delete the dead ~8–10k lines** (both dead Trends generations, sample-data files, `TrendsEfficiencyView`, orphaned components). Every one carries a comment confidently asserting a rule the live code contradicts — they're not just weight, they're active misinformation for the next coding agent that greps the folder.

---

## 7. What's genuinely good (keep doing this)

- The receipt/ledger transparency pattern — extend it to every score in the product.
- Noise-guard headlines and small-n honesty ("only three days — named in full").
- The one-window-controls-everything discipline in v2 (the 08-03 audit's core demand, delivered).
- Empty states that name what they're waiting for.
- Code comments that record *why* decisions were made — the epitaphs in `TrendsLegacyTabView` and the audit-citation in `TrendsSignalLanes` are exactly how a solo founder's codebase should talk to its future agents. The failure mode isn't the comments — it's that dead code keeps its old comments, so the folder argues with itself. Delete the losers and the comments become an asset again.
