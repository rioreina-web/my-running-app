# Log — UI redesign brief

*2026-07-11 · the capture front door. Reads with `00-foundations.md` (template, tokens, cross-cutting states) and the design-system README (voice). Foundations are assumed, not restated. Tested against Maya.*

---

## 1. The one job

**What did I just do, and how did it feel?** Log captures raw signal — voice, text, mood, niggles — as fast and warmly as possible, then gets out of the way. It records; it never analyzes. The same niggle it captures here is aggregated in Trends and narrated in Read. If a screen is doing math, it isn't Log.

## 2. Current state & problems

The prototype: a `Log run / Check in` toggle, a pulsing coral record disc, an "or type notes" textarea, and a flat 2-week journal feed (weekday · date · pace-label · distance, an italic first-person quote, a mood pill, one niggle chip). Tapping a row opens that day in Training.

Where it falls short:

- **Recording ends into a void.** Stop → the memo vanishes. No transcript to read or fix, no chance to confirm the classifier's mood, no way to tag or untag niggles. Capture without structure — the single biggest gap.
- **Check-in captures no mood.** The screen asks *"How are you feeling?"* and offers no answer control. Mood only appears later, retroactively, on a journal row.
- **The run link is undercooked.** "Linked to" exists in the JSX but never auto-suggests the run HealthKit just imported; the athlete links by hand or not at all.
- **The journal doesn't scale.** Flat 2-week feed, no search, no filter, no grouping. Maya has ~2 years of history — this is unnavigable at depth 3.
- **Thin cards.** One niggle max, legacy workout labels (`TEMPO`, `INTERVALS`), no linked-run surfaced, no key-session mark.
- **Coral competes.** Record disc *plus* the voice indicator *plus* `SAVE ↗` / `CHANGE ↗` all pull coral in one cluster — the one-loud-accent rule isn't enforced.
- **No offline story.** Recording silently assumes connectivity for transcription.

## 3. Target layout

Top → bottom: plate strip · mode toggle · capture hero (headline + record button, the one loud accent) · context row (Linked-to for runs / mood radio for check-ins) · type-notes fallback · journal header (search + filter) · week-grouped feed. Stopping a recording raises the **confirm/transcribe sheet** (its own region, right).

```
┌────────────────────────────────────────────┐   ┌─── confirm sheet ───────────┐
│ RUNNING LOG · LOG             FIG. 09 · JUL  │   │ Before you save.            │
├──────────────────────┬──────────────────────┤   │ TRANSCRIPT      ◗ 2:34  ▷    │
│  Log run             │      Check in         │   │ [ "Hit splits within two    │
│  ▔▔▔▔▔▔▔ (coral rail)│                       │   │   seconds either way…"  ]   │  editable
├────────────────────────────────────────────┤   │ MOOD                        │
│                Log your run.                 │   │ ○energized ●positive ○tired │  radio, pre-set
│           Tap to record your memo.           │   │ ○neutral ○struggling ○inj.  │
│                                              │   │ NIGGLES                     │
│                  (   ●   )  ← the ONE accent │   │ [calf ×] [+ add body part]  │  closed vocab
│                 TAP TO RECORD                │   │ "calf was quiet today"      │  verbatim
│                                              │   │ LINKED TO           CHANGE  │
│  LINKED TO                     CHANGE ↗      │   │ May 5 · 7.0 mi · MP 7 mi    │  auto-suggested
│  May 5 · 7.00 mi · 44:08                     │   │ Not medical advice. If any- │
│  6:18 / mi · APPLE WATCH                     │   │ thing sharpens, see a clin. │
├────────────────────────────────────────────┤   │            Save entry ↗     │
│  OR · TYPE NOTES                      SAVE   │   └─────────────────────────────┘
│  How did your run feel today?                │
├────────────────────────────────────────────┤
│  JOURNAL · 128 ENTRIES         ⌕   FILTER ↗  │
│  ── THIS WEEK · 32 mi ───────────────────    │  sticky mono group header
│  ┃ Tuesday             ◗ VOICE · 2:34    ★   │  ┃ = mood rail · ★ = key session
│  ┃ MAY 5 · MP 7 mi · 7.0 mi                  │
│  ┃ "Hit splits within two seconds either…"   │
│  ┃ POSITIVE   niggle · calf                  │
│  ── LAST WEEK · 41 mi ───────────────────    │
│  ┃ Sunday              ◗ VOICE · 3:18        │
└────────────────────────────────────────────┘
```

## 4. Components

Reuse from inventory: plate strip · mode toggle (segmented control) · eyebrow · display headline · **record button** (the one loud accent) · **mood radio** (Primitives `MoodRadio`, 6 values) · mood pill · niggle chip · filter chips · key-session star · link-card (the Linked-to run, and the row's hand-off to Training) · empty-state · editorial rule.

New, justified (all assembly from existing primitives — no new visual language):
- **Confirm/transcribe sheet** — the structural fix. Opaque white over paper; eyebrow-labeled sections (TRANSCRIPT / MOOD / NIGGLES / LINKED TO) built from mood radio, niggle chips, link-card. Earns its place because capture *must* gain a confirm step.
- **Niggle picker** — the closed ~30-part body vocabulary as a searchable list. Maps "subtalar joint" → ankle or drops it; never invents an entity. Selected parts render as chips with the athlete's verbatim words quoted beneath.
- **Week-group header** — sticky mono-caps subhead with entry count + mileage subtotal (`THIS WEEK · 32 mi`). An eyebrow variant, not a new type ramp.

## 5. Interactions & states

- **Capture drill:** tap record → timer + pulse ring (the one motion break) → tap stop → confirm sheet. Save dismisses the sheet; the new row animates in at the top (fade, no toast, no praise).
- **Row tap → Training day** (link-card hand-off, per the mental model). Editing an entry is a separate affordance (small `EDIT` on the row) that re-opens its confirm sheet — an entry is never frozen.
- **depth-0 (brand-new):** hero fills the screen; journal is a single plain empty-state (no pull-quotes, per foundations). Linked-to is hidden until a run exists. Check-in is the likely first capture.
- **depth-3 (Maya):** journal grouped by week, sticky headers, 6-month default with infinite scroll for older (matches IA). Search + filter chips active; rows carry key-session stars and pace-zone labels. Editorial register stays out of the capture surface — the only "prose" here is the athlete's own verbatim quote.
- **Loading:** skeleton rows in card shape, no spinners. Recording is *never* gated on network.
- **Offline:** record + type work fully; audio and text queue locally. Row shows a `QUEUED` mono tag until sync; the confirm sheet works minus the auto-transcript. On reconnect the classifier runs and **merges without overwriting** the athlete's mood/niggle edits.

## 6. Improvements (prioritized)

**P0 — capture integrity**
1. **Confirm/transcribe sheet.** Edit transcript, confirm mood (radio pre-set by the classifier), add/remove niggles from the closed vocab, confirm the linked run. Classifier proposes, athlete disposes — nothing saves silently, nothing is diagnosed.
2. **Mood radio in check-in.** Wire the 6-value `MoodRadio` (`energized · positive · neutral · tired · struggling · injured`) under *"How are you feeling?"* — the prompt currently has no input.
3. **Offline capture.** Record + type with no network; queue audio, defer transcription, show `QUEUED`. Never lose a memo.
4. **Enforce one-loud-accent.** The record disc is the only coral in the capture cluster. Demote the voice indicator and `SAVE`/`CHANGE ↗` links to ink-2; coral returns only on active/hover.

**P1 — the run link + navigable journal**
5. **Auto-suggested Linked-to.** On run mode / sheet open, pre-fill the most recent unlogged HealthKit run (date · dist · pace-zone label · source). `Change` opens a recent-runs picker.
6. **Week-grouped journal** with sticky headers + mileage subtotals; 6-month default window (reconcile with the prototype's "Last 2 weeks" label).
7. **Richer cards:** multiple niggle chips, key-session star when the linked run was a key session, pace-zone workout labels (`MP 7 mi`, `LT 6 mi` — not `TEMPO`), clean voice / text / check-in kinds.
8. **Search + filter chips:** free-text over transcripts/notes; filter by kind, mood, and niggle body-part.

**P2 — polish**
9. **Live waveform** during recording (ink, not coral) so the athlete trusts capture; honor `prefers-reduced-motion`.
10. **Niggle-picker polish:** verbatim severity language preserved as a quote under the chip; no severity number, no diagnosis, ever.
11. **Note streaks / check-in cadence belong to Trends/Read** — hand off, don't build a summary here.

## 7. Voice & copy

- **Eyebrows:** `LINKED TO` · `OR · TYPE NOTES` · `JOURNAL · 128 ENTRIES` · `THIS WEEK · 32 MI` · `TRANSCRIPT` · `MOOD` · `NIGGLES` · `QUEUED` · `VOICE · 2:34` · `TEXT ONLY`.
- **Headlines:** *"Log your run."* · *"How are you feeling?"* (never reword the check-in prompt) · sheet: *"Before you save."*
- **Niggle helper:** *"Tap a body part you mentioned. We quote you, we don't diagnose."* Liability line, quiet italic: *"Not medical advice. If anything gets sharper, see a clinician."*
- **Empty-state (depth-0):** eyebrow `JOURNAL`; nudge *"No entries yet. Your first voice memo or note lands here."* (record button is the CTA — no button in the empty-state).
- **Offline:** *"Saved offline. Transcription finishes when you're back online."*
- **Never cheerlead.** Save is silent — the sheet dismisses and the row appears. No *"Nice run!"*, no emoji, no exclamation outside a quoted memo.

## 8. Open questions

- **Row tap target.** Row → Training day, with a separate `EDIT` → sheet? Or should tapping the quote itself edit in place? (Proposed: row → Training; explicit `EDIT` → sheet.)
- **Toggle framing.** Now that runs auto-import from HealthKit, is `Log run / Check in` still right, or are the real modes `Voice memo / Quick note` with the run-link orthogonal? Flag to IA.
- **Auto-link confidence.** Match the nearest HealthKit run by time — what threshold before we stop pre-filling and just show the picker?
- **Check-ins in the feed.** Same journal as runs (kind-tagged, filterable) or a separate stream? (Proposed: one feed.)
- **Default window.** 6 months (IA) vs. "Last 2 weeks" (prototype). Reconcile.
