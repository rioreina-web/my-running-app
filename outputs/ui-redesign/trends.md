# Trends — UI design brief

*2026-07-11 · the analysis surface. Companion to `00-foundations.md` (read that first — voice, three-palette rule, shared components, `data_depth`, honesty states all live there and are not restated here). Metrics defined in `trends-metrics-spec-2026-07-10.md`. Tested against Maya.*

---

## 1. The one job

**Is it working?** Trends reads the training back to Maya so she can *watch the build* — pace, load, durability, consistency, and what the body's saying — without waiting on a race prediction. It aggregates; it does not capture (Log) or narrate (Read).

## 2. Current state & problems

The prototype (`renderTrends`) stacks: hero + 3 stat tiles → 12-week overlay (volume · workload · mood · niggles on one axis, layer chips, Over-time/Spectrum switch, inline "read") → pace-progression chart → niggle timeline → race-fitness card → paces table. The separate mockup then adds an **Effort model** (per-run Effort, weekly Effort-load, felt-vs-measured) and **six progressions** (efficiency, best efforts, durability, consistency, easy discipline, total volume).

Concatenated, that is **~12 full-bleed chart sections** — a punishing scroll where every chart shouts equally and Maya can't find the one that moved. Concrete faults:

- **No 5-second answer.** The question is "is it working?" and she has to scroll a screen and a half to infer it.
- **Flat hierarchy.** The overlay (a synthesis object) sits at the same weight as the paces reference table.
- **Hover readouts.** `mousemove`/`mouseleave` tooltips (`buildOverlay`, `buildSpectrum`) don't exist on touch; the readout is dead on a phone.
- **Cramped charts.** 7–8px axis labels, sub-44pt hit targets, five series crammed on one 258px-tall SVG.
- **Effort + six progressions have nowhere to go** without doubling the scroll.

## 3. Target layout

Four stacked regions; the deep metrics live inside a 3-group sub-nav so only one group renders at a time. Top→bottom:

- **A · Header + "This week" strip** — plate strip, eyebrow, display headline, then a horizontally-scrolling row of 3 delta micro-cards (one per group: the single most-moved metric). *The 5-second view.*
- **B · Pinned** (optional) — Maya's watch-list. Any deep card can be pinned here so it survives group swaps (durability before a marathon, say).
- **C · Overview overlay** — the signature 12-week chart kept as the one always-visible headline (volume + load-band + mood + niggle markers), layer chips, Over-time/Spectrum switch, one AI "read" + soft question.
- **D · Deep-dives, grouped** — a segmented sub-nav `Effort · Fitness · Signal`. Each group is a stack of **collapsed summary cards** (one-line: label + number + delta + sparkline); tap a card to expand the full chart + its read + a pin control. Default collapsed → a group is ~4–8 scannable rows, not 8 charts.

```
┌────────────────────────────────────┐
│ RUNNING LOG — TRENDS · ANALYSIS     │ plate strip
│ ANALYSIS · 12 WEEKS           coral │ eyebrow
│ Is it working?                      │ display headline
├────────────────────────────────────┤
│ THIS WEEK            ‹ swipe ›       │ A · what-changed strip
│ ┌────────┐┌────────┐┌────────┐      │  3 cards · 1 per group
│ │EFFICI. ││ LOAD   ││ CALF   │  →   │  tap → jump+expand
│ │+35s@145││backing ││quiet 9d│      │
│ └────────┘└────────┘└────────┘      │
├────────────────────────────────────┤
│ ★ PINNED                            │ B · optional watch-list
│ │ Durability   fade −0:12    ▸ │    │
├────────────────────────────────────┤
│ OVERVIEW · 12 WK    [Time|Spectrum] │ C · headline overlay
│  miles/wk ▓▓▒▓▓▒▓▓▒▓ (stack/zone)   │  volume + load + mood
│  workload ╌╌╌╌●╌╌╌╌ safe band       │  + niggle markers
│  mood     ▪▪▪▪▪▪▪▪▪▪                 │  tap column → readout
│  [Vol][Load][Mood][Niggles]         │  layer chips
│  THE READ  one paragraph + ?        │
├────────────────────────────────────┤
│ [  Effort  ·  Fitness  ·  Signal  ] │ D · group sub-nav
├────────────────────────────────────┤
│ FITNESS & PROGRESS                  │  active group
│ │ Race fitness  3:08–3:14   ▸ │     │  collapsed summary cards
│ │ Efficiency    +35s ▲      ▾ │     │  ▾ = expanded:
│ │   [ pace @ 145 bpm chart ]  │     │    full chart
│ │   The read… + ☆ pin         │     │    + read + pin
│ │ Best efforts  5K PR       ▸ │     │
│ │ Durability    neg-split   ▸ │     │
│ │ Consistency   11 / 12     ▸ │     │
│ │ Easy discip.  held        ▸ │     │
│ │ Total volume  512 mi      ▸ │     │
│ │ Paces (reference)         ▸ │     │
└────────────────────────────────────┘
     LOG · TRAIN · TRENDS · READ · PLAN
```

**Group contents** (each metric lands in exactly one home):
- **Effort & Load** (the cost) — per-run Effort, weekly Effort-load vs chronic (Building/Holding/Backing-off words, no fake TSB number), felt-vs-measured, workload/ACWR band.
- **Fitness & Progress** (the build) — race-anchored fitness (range+confidence), the six progressions, pace-progression, spectrum, paces reference.
- **Signal** (the body & mood) — niggle timeline, mood arc, plus a cross-link to felt-vs-measured when the gap is active.

## 4. Components

Reuse from the inventory: plate strip · eyebrow · display headline · **segmented control** (does double duty as the group sub-nav *and* the Time/Spectrum switch) · **pace-volume chart** (the overlay) · sparkline (summary-card previews) · stat tile · niggle chip · coach quote (the italic "read" + soft question) · editorial rule · empty-state · link-card (hand-offs).

New patterns (define here, justified):
- **What-changed strip** — a horizontal row of ≤4 micro-delta cards: label + value + signed delta + honesty mark. Justified: nothing in the kit answers "what moved this week" in one glance; it is the anti-scroll device at the top.
- **Expandable summary card** — collapsed = one 44pt row (label · number · delta · mini-sparkline · `▸`); expanded = the full chart + read + pin. Justified: converts a group of 8 charts into 8 scannable rows; the core structural fix. Not a nested card — it expands *in place*, no card-on-card.
- **Pin control** — a small `☆`/`★` on an expanded card that lifts its summary into region B. Justified: Maya tracks 1–2 metrics per block; pinning beats re-finding them across group swaps.

## 5. Interactions & states

- **Drill:** strip card → switches sub-nav to that group and auto-expands the matching summary card (deep-link). Summary card `▸` → expands the chart in place. Chart → tap a column/bar/point for a readout; a deeper tap on a day opens Training's workout detail (link-card, not a copy).
- **Tap, never hover.** Every readout is tap/long-press with an explicit dismiss (tap-elsewhere); replaces all `mousemove` handlers. Readout is a positioned card with ≥180px width, tabular-nums, dismissable — legible at 360px.
- **Sub-nav is swap, not scroll.** One group mounts at a time; the overlay + strip stay pinned above. Selected tab eyebrow goes coral (one coral per cluster).
- **`data_depth`:** 0 → empty state only ("Nothing to analyze yet.") no strip/sub-nav; 1 → strip shows 1 item, overview only, groups empty-stated; 2 → strip + groups populate, trend deltas allowed; 3 → full reads per expanded card, every pull-quote cites a number.
- **Loading:** card-shaped skeletons in the collapsed rows; charts draw in on expand (killed under `prefers-reduced-motion`). No spinners.
- **Honesty (per foundations):** fitness + Effort show range + confidence, whole-minute rounding — never a seconds-precise finish. When weather/grade backfill is missing, Effort renders *without* the adjustment and carries a `CONDITIONS PENDING` tag; the confidence band widens rather than faking precision.
- **VoiceOver:** each chart ships a text summary ("MP pace, 12 weeks, down 15s"); the niggle timeline reads "calf — 3 mentions, easing"; mood is a labeled pill, never color-only.

## 6. Improvements (prioritized)

**P0 — structure (the whole point of this brief):**
- Split the single scroll into Header + **This-week strip** + **Overview overlay** + **3-group sub-nav**; kill the flat 12-section stack.
- Make every deep metric a **collapsed summary card that expands on tap**, default collapsed. Effort's three surfaces + the six progressions slot in here without adding scroll.
- Replace all hover readouts with **tap/long-press readouts**; enlarge axis labels to ≥9px and all hit targets to ≥44pt.
- Enforce honesty marks: range+confidence on fitness/Effort, `CONDITIONS PENDING` on unadjusted Effort.

**P1:**
- Strip cards **deep-link** into group + auto-expand the target card.
- **Pinnable cards** → region B; persist per block.
- Per-card "read" renders **only on expand** (lazy, depth-gated) — keeps collapsed rows quiet.
- Surface **felt-vs-measured** as a Signal cross-link when *felt > measured* for several sessions ("felt harder than it measured, three runs running" — observe, don't diagnose).
- Full VoiceOver chart summaries.

**P2:**
- One-line **group digest** under each sub-nav tab ("Fitness — 5 of 6 progressing").
- **Cross-block compare** ("this cycle vs last") as a lens on any progression.
- **Conditions-adjusted fitness** toggle once weather lands.
- Demote **paces table** to a reference sheet via link-card if Training/Plan ends up owning it (see open Qs).

## 7. Voice & copy

- Eyebrows: `ANALYSIS · 12 WEEKS` · `THIS WEEK` · `EFFORT & LOAD` · `FITNESS & PROGRESS` · `SIGNAL` · `OVERVIEW · 12 WK`.
- Headlines (declarative, period): *"Is it working?"* (tab) · *"The load, honestly."* (Effort) · *"Proof it's building."* (Fitness) · *"What the body's saying."* (Signal).
- Strip cards: *"Efficiency · +35s/mi @ 145"* · *"Load · backing off"* · *"Calf · quiet 9 days."*
- Honesty lines (italic, secondary): *"A range, not a finish time — the seconds would be false precision."* · *"Heat data pending — Effort shown without the adjustment."*
- Reads carry a feeling before the math and end on a soft question: *"Do your easy miles still feel easy, or are they creeping faster than they should?"*
- Empty state: *"Nothing to analyze yet. Log a couple of weeks and this reads your training back to you — where the miles go, how mood tracks load, what the body's saying."*

## 8. Open questions

1. **Overlay vs strip redundancy.** If the This-week strip + group summaries answer "is it working?", does the 12-week overlay stay the headline, demote into the Effort group, or become a Spectrum-only object? (Leaning: keep as headline — it's the signature synthesis.)
2. **Paces ownership.** Trends currently shows the paces table, but Plan/Training also surface zones. Reference-only here, or hand off entirely?
3. **Signal vs Read boundary.** Trends *aggregates* niggles/mood; Read *narrates* them. Keep Signal to tiles + timeline and route all prose to Read?
4. **Sub-nav swap vs accordion.** Swapping hides two-thirds of the content (fast, scannable) vs one long accordion (complete, but back to a long scroll). Brief recommends swap; confirm against how often Maya cross-reads groups.
5. **Felt-vs-measured home** — Effort (it's Effort vs RPE) or Signal (it's an early-fatigue flag)? Currently: lives in Effort, cross-linked from Signal.
6. **Default group + pin count** on tab open — land on Fitness? Cap pins at 2?
