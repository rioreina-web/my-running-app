# The threshold check — Trends section 05 · apply notes

*Written 2026-08-18. Math validated on real exported data **before** the design
was fixed (§V) — and validation killed two of the three estimators I started
with. What ships is what survived.*
*Follows the repo's `APPLY-NOTES.md` additive-new-files convention.*

Section 04 draws the band. Section 05 asks the only question section 04 can't:
**is the band still right?** It answers from evidence, states its confidence,
names what it cannot test — and never moves the band. The athlete moves the
band. That is the whole contract.

**No backend work. No deploy. No migration. No new fetch.** Every input is
already on the `trends-timeline` payload: `TrendsService.fastSegments.sessions`
(`FastSession` carries `decouplingPct`, `isContinuous`, `neutralPaceSec`,
`avgHr`, `fastMiles`, `feelsF`), `keySessions`, and `bandLaps`.

---

## 1 · The diagnosis

The band is the load-bearing setting of the whole app: section 04 counts
against it, `KeyPaceCard` anchors to it, the efficiency index reads out at it.
It is anchored on a race prediction and it is a **setting the athlete moves by
hand**. Nothing in the app ever tells her whether it still matches the runner
she is today. A band anchored on a 1:08 half in March is a photograph, and in
August she is still being measured against the photograph.

Every competitor "solves" this by silently re-estimating threshold from an
opaque model and moving the number under the athlete. That is the one thing
this app must not do (`CLAUDE.md`: observation, never prescription; one band,
athlete-owned). So the check reports evidence and lets her decide.

---

## 2 · The evidence, and what each is allowed to conclude

### E1 · Sustained tests — the only estimator that can move the verdict

A `FastSession` qualifies iff **all** hold:

| Gate | Value | Why |
|---|---|---|
| `isContinuous` | true | Reps have rest; decoupling is meaningless across a rest interval (`FastSegmentModels.swift`: `repCount <= 1`). |
| duration | ≥ 20 min | Below this, drift hasn't had time to appear. Duration is `fastMiles × avgPaceSec`. |
| pace deviation from the band anchor | ≤ ±5% | **The gate that matters.** Decoupling on a run 15% slower than the band tests sustainability *there*, not at threshold. See §V. |
| `decouplingPct` | present | No number, no test. |

Pace is `neutralPaceSec` (heat-neutral) when present, else `avgPaceSec` — the
same correction every other surface applies.

Each qualifying effort reads one of three ways:

- **held** — decoupling ≤ 5%: the band was sustainable that day.
- **failed** — decoupling ≥ 8%: it was not.
- **inconclusive** — between, and it says so rather than rounding to a side.

**Two agreeing efforts** are required for a verdict. One session is a day, not
a trend.

### E2 · Efficiency at band pace — context only, never a verdict

Reuses the validated curve from `EfficiencyIndexBuilder` (m/beat ≈ speed +
heat severity, ±2.3 pts LOO — see `HR-EFFICIENCY-INDEX-APPLY.md` §V). Fit the
first and second halves of the window separately, evaluate both at the band
pace, report the change.

**It reports a direction only when a full jackknife of both halves excludes
zero.** On real data the point estimate was −0.2% with a jackknife spread of
−2.0%…+1.2% — a sign that flips is noise, and the honest output is *"no change
beyond ±2%"*, not *"you're 0.2% worse"*. A null with a stated resolution is a
finding. A direction pulled out of noise is a lie.

Refuses entirely when the band pace sits outside either half's fitted speed
range — no extrapolation, same rule as the index's threshold stat.

### E3 · Anchor age — context

Days since the band's anchor pace last *changed* in the `bandLaps` ladder
sequence. "Your band has read 5:11 for 11 weeks" is a fact about the setting,
and it is often the most useful line on the surface.

---

## 3 · The verdicts

| Verdict | When |
|---|---|
| **UNTESTED** | Fewer than 2 qualifying efforts. Names what's missing — and this is the honest answer for most athletes most of the time (§V). |
| **CONSISTENT** | ≥ 2 efforts, majority *held*, none *failed*. |
| **BAND MAY BE FAST** | ≥ 2 efforts, majority *failed*. |
| **BAND MAY BE SLOW** | ≥ 2 efforts, all *held*, and every one of them by a margin (decoupling ≤ 3%) — comfortably sustainable at band pace means the band may be conservative. |
| **HEAT CONFOUNDED** | A *may-be-fast* verdict whose failing efforts were **all** run in heat. Heat inflates cardiac drift; calling a band too fast on hot-day drift manufactures a harsh verdict out of weather. Demoted, and the words say why. |

The heat rule fails in the conservative direction, mirroring the efficiency
index: **heat can prevent a harsh verdict, never create one.**

---

## 4 · Invariants

| Invariant | How it survives |
|---|---|
| **Observation, never prescription** (`CLAUDE.md`) | The surface reports what happened and what is untested. It never writes a band value, never offers a "fix it" button, and the copy never contains a workout instruction. Naming the *evidence the instrument lacks* ("nothing in this window ran within 5% of your band") is a statement about the instrument, which is the same move `NOT YET — 3 of 5 hot sessions` already makes. |
| **One band** (`TrendsBandSettings.swift:180`) | Anchor read from `BandSettingsStore.shared` via the ladder, exactly as `KeyPaceModels.steps(ladders:anchor:)` does. Nothing new persists. Move the band and this section re-reads. |
| **No em-dashes as placeholders** (hard rule #8) | Every absent figure is words — UNTESTED, NOT YET — or the row is omitted. |
| **No mock data** | Every figure derives from `TrendsService`. |
| **ONE time control** (`TrendsSignalModels.swift:12`) | Reads the host's `window`. No control of its own. |
| **Three-palette rule** (`CLAUDE.md:355`) | Verdict is carried by **words and weight, not hue**. Coral marks the verdict line only, once, and only because it is the "now" of this surface. No green "good band" / red "bad band" — that would be a grade. |

---

## 5 · Files

| File | Contents |
|---|---|
| `Trends/ThresholdCheckModels.swift` | `ThresholdEffort`, `ThresholdVerdict`, `EfficiencyDrift`, `ThresholdCheckRead`, `ThresholdCheckBuilder`, `ThresholdCheckProse`. No SwiftUI. |
| `Trends/ThresholdCheckSection.swift` | `ThresholdCheckView` — verdict line, evidence ledger, context rows, prose. Routes empty to `EmptyStateView`. |
| `RunningLogTests/ThresholdCheckTests.swift` | 14 tests, §7. |
| `Trends/EfficiencyIndexModels.swift` | **Edited**: eligibility extracted to `classify(_:)` so the check and the card cannot drift on what counts as a scoreable session, plus `eligiblePoints(_:)` and `driftAtBand(...)`. |
| `Trends/TrendsV2View.swift` | **Edited**: one new section child (8 → 9, under the ViewBuilder limit of 10). |

---

## 7 · Tests

- Effort gating: reps rejected; < 20 min rejected; > ±5% off band rejected;
  missing decoupling rejected; heat-neutral pace used for the deviation.
- Verdicts: 2 held → CONSISTENT; 2 failed → MAY BE FAST; 2 held-by-margin →
  MAY BE SLOW; 1 effort → UNTESTED; 0 efforts → UNTESTED with the reason.
- Heat rule: 2 failed efforts, both hot → HEAT CONFOUNDED, not MAY BE FAST;
  one of them cool → MAY BE FAST stands.
- Drift: sign reported only when the jackknife excludes zero; band outside
  the fitted range → no drift figure at all.
- Anchor age: counts to the last *change*, not the last session.

---

## V · Validation — 2026-08-18, real exported data

Run on `key-sessions-data.json` (21 sessions, May 5 → Jul 25) before the design
was fixed. **Two of three estimators died here.**

**1 · Decoupling cannot locate threshold on its own — killed the naive design.**
The athlete's continuous efforts are long runs at 6:20–6:50/mi; his band sits
at 5:11/mi. The closest continuous effort was **15% slower than the band**, so
zero efforts clear the ±5% gate. Worse, regressing decoupling on pace across
those runs gives R² 0.09 — it is driven by **duration** (R² 0.20; the 2-hour
run decoupled most at 7.25%) and heat, not by proximity to threshold. Fitting a
"decoupling crosses 5% at pace X" curve on that data would have produced a
confident, wrong threshold. Hence the ±5% band gate and the UNTESTED verdict as
a first-class outcome.

**2 · The rep-HR regression was overfit garbage — killed outright.**
"HR at band pace over time, controlling for heat and pace deviation" fit R²
0.775 and reported a tidy **−5.8 bpm/30 days** (which would have read as "your
band is slow"). It has 5 observations and 4 parameters — 1 residual degree of
freedom. Leave-one-out swings the coefficient from **−19 to +70 bpm/30d**; the
sign flips. Cut entirely rather than shipped with a caveat.

**3 · Efficiency-at-band survived, demoted to context with a null result.**
Split-window fit: −0.2% change at band pace, jackknife −2.0%…+1.2%. Sign
unstable → reports *"no change beyond ±2%"*. This is the shipped behaviour.

**What the check says about this athlete today:** UNTESTED. Nothing in the
window ran within 5% of his band; efficiency at band pace shows no change
beyond ±2%; the band rests on a 1:08 half. Every one of those is true and
useful, and none of them pretends to a threshold estimate.

**Honesty note, stated plainly:** the E1 verdict paths (CONSISTENT / MAY BE
FAST / MAY BE SLOW / HEAT CONFOUNDED) are **validated only against synthetic
fixtures**, because this athlete's log contains no effort that clears the gate.
They rest on a conventional reading of aerobic decoupling (≤5% sustainable,
≥8% not) and on the gates above, not on evidence from this data set. The first
beta athlete who runs 20+ minutes at band pace is the real test. The gates are
deliberately strict so the surface stays silent until then.

---

## 8 · Warts, named now

- **Decoupling is a whole-effort number.** `FastSession.decouplingPct` comes
  from the backend's first-half/second-half split. A negative-split tempo and
  an even one are not distinguished beyond that.
- **±5% is a judgement call.** Wide enough that a real tempo session counts,
  narrow enough that a long run cannot. It is a constant in one place.
- **Heat is binary here** (`neutralPaceSec != avgPaceSec`), not the five-step
  ladder the index uses, because `FastSession` carries `feelsF` rather than a
  category. Enough for the conservative demotion rule; not enough to grade.
- **The check is silent for athletes who only run intervals.** That is
  correct — their log genuinely does not test their threshold — but it means
  the surface will read UNTESTED for a long time for some people. The words
  carry that, and section 04 above it still draws.
