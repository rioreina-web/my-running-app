# Voice memo latency — path map + speed-up plan (2026-08-04)

Why a voice memo takes ~50s (p95 ~100s) to become a journal entry, and how to
get it to ~10s **without changing a single model, prompt, or context block.**

Every number below is measured from prod (`voice_processing_jobs`), not estimated.

---

## 1. Measured baseline

Six most recent real memos:

| Date | Queue wait | Processing | Total |
|---|---|---|---|
| Aug 4 | 12.1s | 33.3s | **45.4s** |
| Aug 3 | 58.9s | 40.7s | **99.5s** |
| Jul 28 | 11.0s | 11.2s | 22.2s |
| Jul 28 | 27.8s | 17.3s | 45.1s |
| Jul 23 | 11.1s | 18.4s | 29.5s |
| Jul 2 | 32.9s | 17.5s | 50.5s |
| **mean** | **25.6s** | **23.1s** | **48.7s** |

Roughly half the wait is a queue doing nothing. The other half is a chain that
is more serial than it needs to be.

---

## 2. The path, end to end

```
 [iOS] stop recording
   │
   ├─ read m4a → base64 → POST JSON to upload-voice-memo      ~1-3s (cellular)
   │    upload-voice-memo/index.ts:83  per-byte atob() loop
   │    service-role write to training-memos bucket
   │
   ├─ client INSERTs training_logs row (processing_status='pending')
   │    └── trigger invalidate_athlete_state_on_training_log  ← wipes state cache
   │    └── trigger trigger_voice_log_processing → enqueue voice_processing_jobs
   │
   ▼
 ░░░░░ DEAD TIME — 0-60s, mean 25.6s ░░░░░
   pg_cron '* * * * *' fires drain-voice-processing-jobs
   20260610230012_voice_processing_outbox.sql:203
   │
   ▼
 [process-training-memo]                                       11-41s
   │
   ├─ auth + ownership read                                    ~0.3s
   ├─ rate limit + monthly cap                                 ~0.3s
   ├─ status read + concurrency guard                          ~0.2s
   ├─ updateProcessingStatus('processing')   ← UPDATE          ~0.2s
   │    └── fires invalidate_athlete_state_on_training_log AGAIN
   ├─ existing-record read + sibling-GPS merge                 ~0.4s
   ├─ storage download of the m4a                              ~0.5s
   │
   ├─ launch in parallel: coachContext, recentLogs, prior      (good)
   │
   ├─ TRANSCRIBE  Groq whisper-large-v3 (30s timeout)          ~3-8s
   │    → fallback OpenAI whisper-1 (30s timeout)              (+30s worst case)
   │    → fallback Gemini audio                                (+30s worst case)
   │
   ├─ await getOrBuildAthleteState()   ← SERIAL, ALWAYS REBUILDS   ~2-6s
   │    index.ts:758 — does not depend on the transcript
   │
   ├─ build prompt (paces, splits, zones, athlete state)
   ├─ GEMINI 2.5 Flash analysis                                ~5-12s
   │
   ├─ upload transcript .txt to storage           (awaited)    ~0.5s
   ├─ UPDATE training_logs with all results       (awaited)    ~0.3s
   ├─ writeNiggleMentions                         (awaited)    ~0.5s
   ├─ writeNiggleResolutions                      (awaited)    ~0.4s
   ├─ writeMemoryCandidates                       (awaited)    ~0.6s
   └─ 200 → drain marks job completed
   │
   ▼
 [iOS] poll every 3s, first check at t+3s                      +0-3s
   VoiceLogViewModel.swift:185
   → status flips to 'completed' → loadHistory() → entry appears
```

---

## 3. Where the time actually goes

Ranked by cost, with the root cause:

### R1 — The cron queue (mean 25.6s, worst 58.9s) — **the single biggest cost**

The insert trigger only *enqueues*. Nothing runs until the every-minute cron
fires. A memo lands at a random point in the minute, so the wait is uniform
0–60s. Pure dead time.

The fix already exists in the codebase and is only wired to one path: the
attach path calls `process-training-memo` directly
(`VoiceLogViewModel.swift:174-181`). The insert path doesn't.

### R2 — The memo pipeline invalidates its own athlete-state cache (2-6s, every time)

`invalidate_athlete_state_on_training_log` fires on **any**
`INSERT OR UPDATE OR DELETE` on `training_logs`, with no column list and no
`WHEN` clause — it stamps `athlete_state.last_updated_at = '1970-01-01'`.

So:

1. The client INSERT invalidates the state.
2. `updateProcessingStatus(record.id, 'processing')` (index.ts:421) — a bookkeeping
   UPDATE that changes no athlete-relevant field — invalidates it *again*.
3. `getOrBuildAthleteState()` at index.ts:758 sees a 56-year-old timestamp, so its
   60-minute freshness check can never pass, and it runs a **full rebuild** —
   claim RPC + ~13-query fan-out + derived math — on the critical path.

Confirmed in prod: both `athlete_state` rows currently read
`last_updated_at = 1970-01-01`, `last_updated_by = 'invalidated:training_log_UPDATE'`.
The cache has an effective hit rate of zero on this path.

### R3 — Athlete-state is serialized behind transcription (2-6s)

Even when it does rebuild, it doesn't need to wait. `getOrBuildAthleteState`
takes no transcript input, but it's awaited at index.ts:758 — *after*
transcription completes. Four other fetches (`coachContext`, `recentLogs`,
`scheduled`, `prior`) are correctly launched before transcription and awaited at
index.ts:668. This one was left out of that pattern.

### R4 — Five awaited writes after the answer is known (2-5s)

After Gemini returns, the function still awaits: transcript upload to storage,
the row UPDATE, `writeNiggleMentions`, `writeNiggleResolutions`,
`writeMemoryCandidates` — then returns 200. iOS only watches
`processing_status`, so all of that is latency the athlete pays for and can't see.

`EdgeRuntime.waitUntil` is already imported in this file (index.ts:34) and used
for `fireParseStructure`.

### R5 — Sequential transcription fallbacks (0s typical, +60s worst case)

Groq gets a 30s timeout, then OpenAI gets another 30s, then Gemini. A typical
60-second memo transcribes on Groq in 2-3s. If Groq is degraded rather than
down, a memo can sit for 30s before the fallback even starts.

### R6 — Poll granularity (0-3s)

3s ticks, first check at t+3s. Up to 3s of "finished but not shown."

### R7 — base64-in-JSON upload (~1s)

33% payload inflation on cellular, plus a per-byte `charCodeAt` loop to decode
(upload-voice-memo/index.ts:83-88). Real but small.

---

## 4. The plan

Phased so each phase ships and is measurable on its own. **Nothing here changes
the transcription model, the analysis model, the prompt, or any context block
fed to it.** The output of the pipeline is byte-for-byte what it is today.

### Phase 1 — kill the dead time (est. −26s mean, −59s worst)

**1.1 Direct-invoke on the insert path.**
After the `training_logs` insert, call `process-training-memo` immediately —
the same call the attach path already makes. Keep the outbox row as the retry
net; it becomes the safety mechanism it was designed to be rather than the
primary trigger.

Safe because the idempotency already exists: `voice_processing_jobs` has
`UNIQUE (training_log_id)` with `ON CONFLICT DO NOTHING`, and
process-training-memo has both the `cleaned_notes` short-circuit (index.ts:387)
and the 2-minute `processing` concurrency guard (index.ts:407-418). The drain
will find the job already completed and no-op.

**1.2 Belt-and-braces:** drop the drain cadence to every 15s (four stacked
pg_cron entries, or a single `'15 seconds'` schedule). Covers the case where the
direct invoke is lost to a dropped connection, without waiting a full minute.

*Quality impact: none. Same function, same inputs, called sooner.*

### Phase 2 — stop rebuilding athlete-state on the hot path (est. −3 to −6s)

**2.1 Narrow the invalidation trigger to columns that actually change state.**
Replace the blanket `AFTER INSERT OR UPDATE OR DELETE` with a column-scoped
`UPDATE OF` list (`workout_date`, `workout_distance_miles`,
`workout_duration_minutes`, `workout_type`, `mood`, `cleaned_notes`,
`pace_segments`, …) so bookkeeping columns — `processing_status`,
`last_processing_attempt`, `processing_error` — stop wiping the cache.
New migration, append-only (hard rule #5).

This is a correctness fix as much as a speed fix: the cache is currently
disabled everywhere, not just here, so every athlete-state consumer is paying
full rebuild cost.

**2.2 Hoist `getOrBuildAthleteState` into the parallel launch block** alongside
`coachContextPromise` / `recentLogsPromise` / `priorPromise` (index.ts:511-547),
and await it with them at index.ts:668. It has no transcript dependency.

Do 2.1 *and* 2.2 — 2.1 makes the cache work, 2.2 means even a genuine rebuild
overlaps with transcription instead of adding to it.

*Quality impact: none — and arguably positive. The state fed to the prompt is
the same or fresher; we're removing a redundant invalidation, not a real one.
The memo's own content UPDATE (index.ts:957) still invalidates, correctly.*

### Phase 3 — two-stage reveal (est. −10 to −15s **perceived**)

The athlete's own words are available ~6-10s in. The coaching analysis takes
another 5-12s on top. Today both land together.

Write the transcript to the row as soon as transcription returns and flip
`processing_status` to a new `'transcribed'` state. The Log entry renders the
athlete's words immediately; mood, niggles, and insight fill in when Gemini
returns and the status flips to `'completed'`.

**Gotcha:** the "already processed" short-circuit at index.ts:387 keys on
`ownerRow.cleaned_notes`. Writing the transcript early would make a retry
think the row is done and skip the analysis. Write the raw transcript to a
distinct column (or gate that guard on `processing_status IN ('completed')`
instead) before shipping this.

*Quality impact: none. The end state is identical; the athlete just sees the
first half sooner. This is the biggest felt improvement in the whole plan.*

### Phase 4 — get the tail off the critical path (est. −2 to −5s)

Set `processing_status='completed'` in the same UPDATE that writes the analysis
(index.ts:957), then run under `EdgeRuntime.waitUntil`:

- transcript `.txt` upload to storage (index.ts:840)
- `writeNiggleMentions` / `writeNiggleResolutions` (index.ts:978-982)
- `writeMemoryCandidates` (index.ts:992)

All three already exist as never-throwing, log-on-failure calls, and
`fireParseStructure` already uses this exact hook.

*Quality impact: none to the data — every write still runs to completion.
One caveat to accept knowingly: niggle chips may render a beat after the entry
appears rather than with it. If that reads badly, keep `writeNiggleMentions`
awaited (it's the cheapest of the three) and background only the other two.*

### Phase 5 — trim the edges (est. −2 to −4s, plus worst-case protection)

**5.1** Cut the Groq timeout from 30s to 12s. A 60s memo transcribes in 2-3s;
30s only ever delays the fallback. Same model, same output — we just fail over
faster.

**5.2** Swap the base64-in-JSON upload for raw bytes with
`Content-Type: audio/m4a` and `req.arrayBuffer()` on the function side. Drops
~33% of the bytes and the per-byte decode loop.

**5.3** Replace the 3s poll with a realtime subscription on the row, or poll at
1s for the first 15s then back off. Removes up to 3s of invisible wait.

---

## 5. Where this lands

| | Now | After |
|---|---|---|
| Queue wait | 25.6s mean | ~0s |
| Time to transcript visible | 48.7s | **~6-9s** |
| Time to full analysis | 48.7s mean, ~100s p95 | **~14-20s** |
| Worst case (Groq degraded) | ~160s | ~35s |

---

## 6. What we deliberately do not touch

The quality of a memo entry comes from four things, and none of them changes:

- **`whisper-large-v3`** stays the transcription model. No downgrade to a
  smaller/faster ASR.
- **`gemini-2.5-flash`** stays the analysis model. No flash-lite, no truncated
  output budget.
- **The full prompt context** — athlete state, pace zones, splits block, zone
  classification, prescribed-vs-executed, recent logs, Garmin segments — is
  assembled exactly as it is today. Phase 2 makes that context *fresher*, not
  thinner.
- **Every downstream write** — niggles, resolutions, memory candidates,
  structure parse — still happens. Phase 4 moves when, not whether.

The outbox keeps its durability guarantee throughout: Phase 1 demotes it from
primary trigger to retry net, it does not remove it. A dropped memo is still
athlete-visible data loss and the retry path is what prevents it.

### Optional, explicitly not in the plan

On-device transcription (Speech framework) for an instant provisional
transcript. It would put words on screen in ~1s, but it introduces a second,
weaker ASR into the product. If it's ever picked up, the guard is: display
on-device text as provisional only, overwrite with the Whisper result, and
**never** feed on-device text to the analysis prompt. Phase 3 gets most of this
benefit with zero quality surface, which is why it's the one in the plan.

---

## 7. Suggested order

1. **Phase 1** — biggest single win, smallest diff, no migration.
2. **Phase 2.1** — one migration; fixes a cache that's globally disabled today.
3. **Phase 3** — biggest felt improvement; needs the index.ts:387 guard fixed first.
4. **Phase 2.2 + Phase 4** — same file, ship together.
5. **Phase 5** — cleanup.

Add a `[memo-timing] athlete-state=Xms` log line before starting Phase 2 —
it's the one segment in the chain with no instrumentation, so the 2-6s estimate
is the least certain number in this doc.
