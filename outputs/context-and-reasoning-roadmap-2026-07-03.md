# Roadmap — from fused context to a coach that reasons

**Date:** 2026-07-03
**Framing:** the vision (all qualitative + quantitative in context, with
long-term memory) is ~80% built *architecturally* — three legs feed one fused
`athlete_state`. The remaining scope is no longer "add more signals." It's two
frontiers: **(1) data coverage** (so the context isn't thin in practice) and
**(2) principled reasoning** (turn the fused context into judgment). Plus a
short "finish what's in flight" phase.

Ownership tags: **[you]** = your coaching philosophy / decisions only you can
make; **[eng]** = code; **[both]**. Rough sizes: S / M / L.

---

## Phase 0 — Finish what's already in flight (days)

0.1 **[eng, S]** Commit the Ask-the-Coach iOS fix (hunk-aware — the two files
    are contended) and cut a new app build. Fix is applied; only a build ships
    it to the device.

0.2 **[eng, S]** Confirm the three committed migrations + `compute-fitness-
    snapshot` + `coaching-agent` are deployed and healthy. *(Verified live this
    session — snapshots regenerating nightly, 400 fixed. Just keep an eye on it.)*

0.3 **[eng, S]** Wire `buildReadiness` into `athlete_state` + the Coach Read
    prompt as a "push / hold / pull" read. The pure function + tests exist;
    it's not consumed yet. This is the first reasoning output the coach shows.

0.4 **[eng, S]** Land the memory subsystem the parallel workstream is building
    (consolidation cron, quota selection, year-ago arc) — mostly done; make
    sure it's committed + deployed, not stranded uncommitted.

---

## Frontier 1 — Data coverage (make the context real, not thin)

*Today the signals exist but barely populate: one test athlete, and memos
rarely fill stress / illness / travel. Thin data caps how much any reasoning
can matter.*

1.1 **[both, M]** Improve memo extraction coverage. The memo prompt already
    asks for sleep/stress/illness/felt-vs-looked, but they seldom come back
    populated. Tighten the extraction prompt and/or gently prompt the athlete
    for the missing dimensions — without ever inventing them. Measure coverage
    before/after against real memos.

1.2 **[eng, M]** Niggle pipeline rework (audit Hole #2). Move body-mention
    detection into the memo pipeline (use the LLM's own parse + closed vocab +
    laterality + verbatim quotes), keep regex only as manual-note backfill.
    Today it re-derives with regex and ignores the model's output.

1.3 **[eng, M]** Memories from voice memos (audit Hole #4). Memory extraction
    currently leans on chat; the athlete's richest durable signal is in their
    memos. Feed `extractMemories` from memo transcripts too. *(Partly overlaps
    the in-flight memory work — coordinate.)*

1.4 **[eng, L]** Device recovery data (audit Hole #6 — the biggest coverage
    gap). There is **no** sleep / resting-HR / HRV ingestion anywhere. Readiness
    and the whole Recovery pillar are running on self-report alone. Wire
    HealthKit sleep + HR recovery into the state. This is the single highest-
    value coverage add for the readiness reasoning.

1.5 **[eng, M]** HealthKit history backfill + race auto-detect (audit Hole #4 /
    roadmap Phase 2). The product promises 2 years; the state sees ~24 weeks.
    Backfill on signup so the coach actually "knows the athlete's history."

1.6 **[you, ongoing]** Real users. The flywheel: more athletes → more memo
    coverage → reasoning that matters. Not code, but the true unlock. (Your
    beta-recruiting docs already exist.)

---

## Frontier 2 — Principled reasoning (turn context into judgment)

*This is what makes it "somewhat smart, within reason." Reasoning lives in
tested code + a bounded, grounded LLM; both anchored to written principles.*

2.1 **[you, M] — HIGHEST LEVERAGE.** Fill in `docs/coaching/principles.md`. It
    is ~90% empty template. It is *simultaneously* the AI's prompt grounding,
    the eval rubric, and the code-review standard — so it caps both reasoning
    and evaluation. Sections to write (in your voice, concrete): intensity
    philosophy, scaling by athlete, deload signals, the injury monitor→modify→
    refer tree, fatigue vs life-stress handling, "things I'd never tell a
    runner," communication voice + example messages. I can interview you
    section by section and draft each — I can't invent your philosophy (that's
    the fabrication we're avoiding).

2.2 **[eng, M]** More reasoning builders, same pattern as `buildReadiness`
    (pure, tested, observation-framed), each grounded in a 2.1 principle:
    - **Load verdict** — appropriate / creeping / spiking (ACWR + monotony bands).
    - **Phase / periodization** — where in the cycle, does this week match it.
    - **Workout spacing** — hard days need easy days around them.
    - **Race-readiness vs goal** — fitness prediction vs goal vs weeks-out.

2.3 **[eng, M]** Bounded LLM reasoning in the prompt. Let the model reason
    *over* the code-computed verdicts (structured: phase → load → readiness →
    conclusion), grounded in the state + RAG docs, output-bounded to
    observations / soft questions / ranges — never free prescriptions. This is
    the "thinks on its own, within reason" piece.

2.4 **[eng, M]** Principle guardrail checks — deterministic pure functions that
    assert coach output obeys the hard rules (no diagnosis, no rest Rx, no
    medication/treatment, no race-day changes ≤7 days out, no false-precision
    finish times). Dual use: runtime output validator **and** eval check. The 4
    hard rules in `principles.md` are already defined enough to build these now.

2.5 **[both, L]** Real evaluation (not cassettes). Cassettes detect regressions;
    they don't measure quality. Build: **scenario fixtures** (overreaching,
    mid-taper, niggle-return, thin-data athletes), a **rubric** derived from
    2.1, an **LLM-as-judge** graded against `principles.md`, plus the 2.4
    deterministic checks. Depends on 2.1 having real content to grade against.
    The harness already has rubric primitives + custom checks — extend, don't
    start over.

---

## Suggested sequence (highest leverage first)

1. **2.1 — fill in principles.md** (unlocks reasoning *and* evals; needs you).
2. **0.3 — wire readiness** + **0.1 ship the ask fix** (close the loop on
   what's built).
3. **1.4 — device recovery data** (biggest coverage add for readiness).
4. **2.4 + 2.5 — guardrail checks + real evals** (so you can safely turn
   reasoning up).
5. **2.2 / 2.3 — more reasoning builders + bounded LLM reasoning.**
6. **1.1–1.3, 1.5 — coverage: memo quality, niggles, memories-from-memos,
   history backfill** (parallelizable; some overlaps the in-flight memory work).

The two things gating everything: **your principles** (2.1) and **real data
coverage** (Frontier 1). Neither is a model problem. Both are the fixable kind.
