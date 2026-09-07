# Read — UI design brief

*2026-07-11 · the synthesis tab. Companion to `00-foundations.md` (read that first) and `design-system/README.md`. Tested against Maya. Assumes the foundations doc's principles, component inventory, and cross-cutting states — does not restate them.*

---

## 1. The one job

**What does it all mean today?** One AI paragraph, written fresh on demand, that reads the training arc back to Maya — feeling first, then workouts, then mileage — and leaves her with a question to sit with. Read narrates what Log captured and Trends aggregated. It never recomputes a metric another tab owns; it interprets.

## 2. Current state & problems

`renderRead` (prototype) shows: eyebrow date → display headline → four lens chips (This week · Since last cycle · The niggle · Mileage) that swap a pre-baked paragraph → bold-numbered prose → one soft italic question (coach-quote 2px coral bar) → optional liability line → signature footer. The empty state is correct. Problems:

- **It isn't on-demand.** The tab auto-renders a read on open. The product principle is the opposite: the read is *written when Maya asks*. There is no generate action and no pre-generation state.
- **No provenance.** The paragraph appears from nowhere. Maya can't see what run or journal entry it's drawing from, when it was written, or how much data it read. "Written fresh" is a promise the UI never shows.
- **No memory.** Yesterday's read is gone the moment today's renders. The arc has no history surface.
- **No depth gating.** A brand-new account gets the same full editorial paragraph as a 21-day one. Depth-1 needs a *short* read, not the full system.
- **Lenses are the only conversation.** Four fixed chips can't cover "how does this build compare to last winter?" There's no way to ask.
- **No save/share.** A read Maya wants to keep or send to a friend can't be kept.

## 3. Target layout

Top → bottom, two states share the frame (pre-gen vs. generated):

1. **Plate strip** — `— THE READ · v1`, figure no. + date right.
2. **Pre-generation** (no read written today): eyebrow `TODAY` → headline *"Today's read isn't written yet."* → a **delta line** (mono, ink-3) naming what's new since the last read → the primary **Write today's read ↗** action (the one coral element in this cluster).
3. **Generated read**: eyebrow (`WEEKDAY · date`) → display headline → **meta line** (generated time + inputs read) → **lens + ask row** → prose paragraph → **Drawn from** source link-cards → 1–2 **soft questions** (coach-quote bar) → optional liability → **Save ↗ / Share ↗** → signature footer.
4. **Editorial rule**, then **Earlier reads** — a collapsed list of past reads (date + headline), tap to reopen read-only.

```
┌──────────────────────────────────────┐
│ — THE READ · v1            FIG. 04·JUL│  plate strip
├──────────────────────────────────────┤
│ TUESDAY · JUL 11                      │  eyebrow (mono caps)
│ The legs came back.                   │  display headline (Crimson)
│ GENERATED 7:12 AM · 4 RUNS, 2 LOGS    │  meta line (mono, ink-3)
│                                       │
│ [This week][Since last cycle]         │  lens chips (re-read)
│ [The niggle][Mileage][ Ask… ]         │  + conversational Ask
│                                       │
│ You logged Sunday's long run tired    │  prose: feeling → workouts
│ and still found the last four miles…  │  → mileage. bold on numbers.
│ the MP eight locked in from mile two… │
│                                       │
│ DRAWN FROM                            │  eyebrow
│ ┌───────────────┐ ┌───────────────┐   │  source link-cards →
│ │ SUN · Long    │ │ THU · MP 8    │   │  tap → Log / Training
│ │ 18 mi · easy  │ │ 7:38 avg      │   │
│ └───────────────┘ └───────────────┘   │
│                                       │
│ ▌Does the quiet read as fresh, or as  │  soft question (coach bar,
│ ▌flat? Only you can feel it.          │  the coral in this cluster)
│                                       │
│  Save ↗    Share ↗                    │  editorial actions
│ — restraint as foundation, intensity… │  signature footer
│  ·····································  │  editorial rule
│ EARLIER READS                         │  history (collapsed)
│ JUL 8 · Fitter than the last build.   │  → tap reopens read-only
│ JUL 4 · The calf went quiet.          │
└──────────────────────────────────────┘
```

## 4. Components

Reused from the inventory: plate strip · eyebrow · display headline (period after) · **coach quote** (the soft question — the *legitimate* coach-voice use of the one colored left-bar; do not add a second) · filter chips (the lenses) · **link-card** (both the "Drawn from" sources and the Earlier-reads rows) · editorial rule · empty-state.

New patterns (define in foundations if adopted):
- **Pre-generation card** — the "not written yet" headline + delta line + generate action. Justified: an on-demand surface needs a first-class *invitation*, not the generic empty-state (which means "no data," a different thing).
- **Ask affordance** — an `Ask…` chip that opens a one-line prompt for a custom lens, and its answer treatment (a dismissible active pill). Justified: preset chips can't cover an open-ended lens.
- **Read meta line** — generated-timestamp + inputs-read count, mono/ink-3. Justified: provenance for the "written fresh" promise.

## 5. Interactions & states

- **On-demand.** Tab opens to the pre-gen card unless a read was already written today, in which case it opens to that read with generate available as a quiet re-run. **Generate → skeleton in the read's card shape** (headline bar + 4 prose lines + question bar; no spinner) → fade headline, then prose. Wired to the `daily-read` golden family — voice guardrails live at the prompt + eval layer (hard rule #3, recorded cassette), not only in UI.
- **Rate limit.** One read per day by default (mirrors the reschedule once-per-day discipline — honesty over slot-machine refreshes). A *fresh* read is offered only when material data lands after generation (a run logged, a niggle mentioned).
- **Lenses** re-read through a lens: headline + prose + question swap, eyebrow + meta persist, prose animates. Lenses that need history (Since last cycle, Mileage) are hidden below depth 2; the niggle lens appears only when there's a `body_mention` to narrate.
- **Ask** → inline single-line field → submit → read region swaps to the answer, the custom lens becomes an active pill you can dismiss.
- **Life context.** When weather/sleep/work-stress signal is present the read may lean on it; when it's missing the thread is dropped *silently* — never fabricate "you slept poorly" (foundations: mark missing, don't fake).
- **Depth-0** — empty-state (state the absence + what fills it), CTA to Log. No generate.
- **Depth-1** — a *short* read: 1–2 plain sentences, feeling only, no bold pull-numbers, single question, only the "This week" lens.
- **Depth-3** — full editorial system: headline + full feeling→workouts→mileage arc, bold numbers, all applicable lenses, source cards, 1–2 questions, save/share, history.
- **Reduced motion** — no prose draw-in; keep the fade.

## 6. Improvements (prioritized)

**P0**
- Ship the **pre-generation state + explicit generate action**; stop auto-rendering. The read is on-demand — the delta line ("3 runs and 2 voice logs since Sunday's read") is the reason to tap.
- **Depth gating**: short plain read at depth 1, full editorial at depth 3, empty-state at 0. Don't show cycle/mileage lenses before history exists.
- **Source citation** — "Drawn from" link-cards back to the exact runs/journal entries. Grounds the synthesis; kills the black-box feel and hands off (never copies) to Log/Training.
- **Voice guardrails** enforced end-to-end: no greeting, no cheerleading, no emoji, anchors/goal carried silently, feeling→workouts→mileage order — at prompt + eval, surfaced verbatim in the UI copy spec below.

**P1**
- **Ask affordance** — conversational custom lens on top of the preset chips.
- **Earlier reads** — collapsed history below the fold; reopen any past read read-only, so the arc keeps its own memory.
- **Save / Share** — Save pins a read to a kept collection; Share renders it as a plate-strip card image (the signature footer already makes it look printed).

**P2**
- **Answer the question in Log** — tapping a soft question opens the Log recorder pre-seeded with it (hand-off, not a new capture surface here).
- **Read-with meta chip** — `READ WITH · WEATHER · SLEEP` so Maya sees what was considered, without the read ever explaining the math.
- **VoiceOver** — "Drawn from" cards and active-lens state announce; the paragraph already reads cleanly.

## 7. Voice & copy

- Eyebrow (generated): `TUESDAY · JUL 11`. Meta: `GENERATED 7:12 AM · 4 RUNS, 2 VOICE LOGS READ`.
- Pre-gen: headline *"Today's read isn't written yet."* · delta *"3 runs and 2 voice logs since Sunday's read."* · action **Write today's read ↗**.
- Headlines (Crimson, period after): *"The legs came back." · "Fitter than the last build." · "The calf went quiet." · "Right where the ramp wants it."*
- Depth-1 read: *"Two runs in and the easy days are landing easy. Early, but the rhythm's there."* → *"How did the week actually feel in the legs?"*
- Soft questions (italic, coach bar): *"Does the quiet in the legs read as fresh, or as flat?"* · *"If the fitness is ahead of last cycle, is 3:16 still the right target — or a conservative one?"*
- Ask placeholder: *"Ask about your training…"* (e.g. *"How does this build compare to last winter?"*).
- Empty-state (depth-0): eyebrow `The read` → *"Nothing to read yet."* → *"The read needs a few runs first. Once you've logged a week or so, this becomes a short, honest paragraph on how your training is actually going."* → **Start logging ↗**.
- Liability (niggle lens only, italic secondary): *"Not medical advice. If anything gets sharper, see a clinician."*
- Signature: `— restraint as foundation, intensity as accent`.
- **Never:** *"Good morning, Maya"* (greeting) · *"Great week — you crushed it!"* (cheerlead) · any emoji · *"Your ACWR is 1.2"* (explaining the math; anchors and goal stay silent).

## 8. Open questions

- **Re-generate policy** — hard one-per-day, or allow a rewrite when new data lands? Leaning: one read/day, auto-offer a fresh one only on material change.
- **Do Asks count against the daily gate**, and where does Ask history live — inline in Earlier reads, or its own list?
- **Auto-nudge** — the read is on-demand, but is a once-a-week *"a lot has changed — worth a read"* prompt allowed without becoming auto-daily? Where's the line?
- **Soft-question loop** — should answering a question route to a Log voice memo (hand-off), or stay in Read?
- **Coach-dyad case** — when a human coach is in the loop, does Read defer, blend, or stay athlete-only? (Read is Maya's surface; leaning athlete-only, coach note lives in Coach.)
