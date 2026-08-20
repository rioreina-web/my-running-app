# Will the cards be accurate? — an honest risk assessment

**Authored:** 2026-08-20 · assessment only, nothing applied
**Question asked:** *"for these cards — will they actually be able to be generated
accurately? I've had major issues with that."*
**Short answer:** **Not reliably, not yet — and the reason is not the analyzers.**

---

## 1 · The defence is real, and it is guarding the wrong layer

`narration-guard.ts` is genuinely good. It rejects the **whole** response if the
model speaks a number Layer 1 didn't print. After a real failure on 2026-08-08 it
also grew `firstUnlicensedScopeClaim`, which stops a narration asserting a filter
the analyzer never applied.

But read what it defends against: **the model inventing a number.**

It has no opinion whatsoever about whether the number Layer 1 computed is
**right**. A wrong value in `facts` passes the guard perfectly, gets narrated
with total confidence, and — because of the design in `WEEKLY-READ-APPLY.md` —
arrives with a **provenance sheet attached**.

> `WEEK-TAB-APPLY.md §0`, rule 2: *"Never add provenance to a number you
> invented. That makes a false number more convincing, not less."*

The same logic applies to a number that is *computed wrongly* rather than
invented. The prototype's tappable sources are an accuracy **multiplier**: right
numbers get more trustworthy, wrong ones get more dangerous.

## 2 · The test suite confirms it

`analyzers.test.ts` — 26 tests. Sorted by what they actually assert:

| What is tested | Count |
|---|---|
| The guard (invented numbers, caveats, fenced JSON, length, shape) | 7 |
| Param coercion (unknown keys, enums, ranges, id shape) | 5 |
| Formatters (`fmtPaceSec`, `fmtSecDelta`, `fmtDelta`, `weekStart`, confidence tiers) | 5 |
| The seam (`factLinesToStrings`, coverage line always present) | 3 |
| Registry hygiene | 2 |
| **Analyzer behaviour** | **3** |

And all three of those are **empty-state tests**: `zone_trend` with no pace
anchor, `zone_trend` with nothing logged, `load_balance` with too little history.

**There is not one test that asserts an analyzer computes a correct number from
known input.** Every analyzer test checks that it *declines* correctly. None
checks that it *computes* correctly.

That is the gap, stated precisely: **the plumbing is well tested, the arithmetic
is untested.**

## 3 · It has already happened twice, in production, in this repo

Both recorded in the code's own comments — neither found by a test.

**`currentFitness`, first day in production.** Read `ranges["10k"]` against a
stored key of `"10K"`, "and silently rendered no capacity at all — a lowercase
miss that compiled fine." (`analyzers/athleteState.ts`)

**`heat_effect`, 2026-08-08.** An athlete asked about long runs over 12 miles.
The analyzer has one param (`window_days`) and applied **no distance filter** —
it read all 127 runs in 90 days. The narration came back *"Your long runs over
12 miles show a significant impact from heat"* and the number guard waved it
through, **because 12 legitimately appears in the facts as "12 s/mi."**

The guard's own header calls this "worse than a wrong number, because the
athlete has no way to detect it." Correct. And it was found by an athlete, not
by CI.

## 4 · The bigger cause is upstream, and it is specifically corrupting *your* data

`INGESTION-AUDIT-2026-08-12.md` scores ingestion **4.5 / 10** — "the design is
well above average… the wiring is where it falls down."

Every analyzer in `ANALYZER-PROMOTION-APPLY.md` reads `workout_features`,
`training_logs` or `body_mentions`. All three sit downstream of this:

| Path | Score | Effect on a weekly card |
|---|---|---|
| Cross-source dedup | **3/10** | **Deletes genuine second runs of the day** |
| Reconciliation | 3/10 | Two rival reconcilers reading a deleted table |
| Apple HealthKit | 4/10 | Sync dies permanently for sub-3×/week runners |
| Strava | 5/10 | Drops data past 100 activities |
| File import | 0/10 | No history import exists |

**The dedup one is not hypothetical for this account.** From the audit, line 108:

> *"Genuine doubles get deleted. A 5.1mi AM + 5.2mi PM both bucket to 5.0, both
> are lapless (HealthKit rows structurally cannot have laps), so the second is
> dropped. `LogDedup.swift:83-88` deliberately preserves this exact case. The
> client and server are in direct opposition, and the server wins because it
> deletes."*

And from `WEEK-TAB-APPLY.md §0`, the real shape of this athlete's training:

> *"Doubles: **most days.** Mon 17 Aug: 6.0 + 4.0; Tue: 2.1 + 6.2 + 2.0."*

**A weekly mileage total, an easy-share percentage and a weekly load figure are
all sums over runs. If the server is deleting one run on most days, every one of
those numbers is wrong — and wrong in a way that looks completely plausible.**
This is very likely a large part of the "major issues" already experienced.

No amount of analyzer correctness survives this. `easy_discipline` computing 62%
flawlessly from a corrupted denominator is still a wrong card, delivered
confidently, with sources attached.

## 5 · So the build order is inverted

`ANALYZER-PROMOTION-APPLY.md §5` and `WEEKLY-READ-APPLY.md §7` both start with
analyzer work. **That is wrong given this.** Revised:

| # | Do this | Why |
|---|---|---|
| **0** | **Fix cross-source dedup.** Reconcile the six rules to one; make the server stop deleting; align it with `LogDedup.swift:83-88`, which already gets doubles right | Every weekly aggregate depends on it, and it is actively destroying this account's data |
| **0b** | The two security holes in the audit's "fix first" list | Unrelated to accuracy, worse than accuracy |
| 1 | **Golden-fixture tests** for the existing 11 analyzers (§6) | The arithmetic is currently unverified. Do this before adding four more |
| 2 | Reconciliation assertions inside analyzers (§7) | Catches corrupt input at the point of use |
| 3 | Then `long_run_share`, `easy_discipline`, and the rest | — |
| 4 | Then the weekly Read | It is a distribution surface; it can only be as accurate as what it distributes |

## 6 · Golden fixtures — the missing test class

For each analyzer, one hand-built week where the right answer is known by
construction, asserted end to end:

```
GIVEN   6 runs, zone-seconds hand-set so easy = 4,200s of 6,000s total
WHEN    easy_discipline runs
THEN    facts.easy_share_current.value === "70"
AND     tone === "good"
AND     factLinesToStrings() contains "70"
AND     coverage.sessionsUsed === 6
```

Three fixtures per analyzer catch the overwhelming majority of this bug class:

1. **A clean week** — the number is known by construction. Catches the arithmetic.
2. **A week with a double** — two runs on one date. Catches the dedup class *at
   the analyzer*, so a regression upstream fails a test instead of a card.
3. **A partial week** — some runs missing zone data. Asserts they are excluded
   **and named in `coverage.missing`**, never silently averaged over.

Fixture 2 is the one that would have caught §4. Write it first.

## 7 · Reconciliation assertions — cheap, and they catch corrupt input

An analyzer can check its own inputs for internal consistency and refuse rather
than compute. Two worth adding, both a few lines:

**Zone seconds must roughly equal duration.** `workout_features` stores both. If
`easy+moderate+threshold+hard` differs from `total_duration_seconds` by more
than ~5%, that run's classification is incomplete — exclude it and say so in
`coverage.missing`. Silent inclusion is how a wrong easy-share gets produced from
data that was visibly broken.

**Weekly totals must match the day rows.** `trends-timeline` already returns
per-day miles with doubles summed. If an analyzer's own sum over
`workout_features` disagrees with the timeline's total for the same week, that is
the dedup bug showing up in the only place it can be caught automatically.
**Surface the disagreement rather than picking a winner** — a card that says
"two sources disagree about this week, so this is not shown" is worth far more
than one that quietly picks the smaller number.

## 8 · What this does not change

The **architecture** is right, and it is why this is fixable rather than
hopeless. Facts computed deterministically, prose mechanically constrained to
them, coverage rendered under every answer, honest empty states instead of
placeholder dashes — that is a better foundation than most products in this
space have. `WEEK-TAB-APPLY.md §0` shows the instinct is already there.

What is missing is not design. It is **verification of the arithmetic, and
trustworthy inputs to it.** Both are ordinary work, and neither is large.

**The one thing not to do is ship the weekly Read on top of the current
ingestion.** It would take numbers that are wrong for a structural reason,
narrate them fluently, attach provenance, and deliver them every Monday morning
as a ritual. That is the most convincing possible wrapper around bad data.
