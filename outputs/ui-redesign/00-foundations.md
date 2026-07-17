# UI redesign — foundations (read first)

*2026-07-10 · design briefs for a better Log · Training · Trends · Read · Plan. Companion to the working prototype (`prototypes/post-run-drip-beta.html`) and the Post Run Drip design system (`design-system/README.md`). Tested against Maya.*

These briefs describe **how each tab should look and behave**, not the data science (that's `outputs/trends-metrics-spec-2026-07-10.md`). Every tab brief follows the same template (below) so they read as one system.

---

## The mental model

Five tabs, one loop: **input → observe → analyze → synthesize → plan.**

| Tab | The one question | Register |
|---|---|---|
| **Log** | What did I just do / how did it feel? | Capture. Fast, warm, first-person. |
| **Training** | What have I done, day by day? | Ledger. Calendar drill-down + workout detail. |
| **Trends** | Is it working? | Analysis. Charts, progressions, the Effort model. |
| **Read** | What does it all mean today? | Synthesis. One AI paragraph, feeling first. |
| **Plan** | What am I supposed to do? | Forecast. Calendar forward + goal. |

Each tab should do *its* job and hand off to the next — never duplicate. Same datum at different altitudes: a niggle is captured in **Log**, aggregated in **Trends**, narrated in **Read**. Cross-links, not copies.

---

## Post Run Drip, applied

- **Voice is the product.** Editorial diary, coach in the room. Spare, declarative, feeling before math. Never cheerlead. See design-system README "Content fundamentals."
- **Type carries the brand.** Crimson Pro (display), PT Serif (body/italic quotes), monospaced (every uppercase label + all numerals, `tabular-nums`).
- **Three-palette color, no exceptions.** Blue depth ramp = pace/intensity; warm = mood; coral = alert + one-per-cluster punctuation. Green is mood-only; coral is never a pace fill.
- **Flat, editorial surfaces.** Warm paper `#F5F3F0`, white cards, 12px radius, hairline `#E8E4E0`, `shadow-card` only. No gradients, glass, or images-as-background.
- **The editorial rule** (`line · dot · line`) is the section break — not an `<hr>`.
- **Motion restrained.** 300ms easeInOut, fade for tab transitions, the record button is the one loud accent (1800ms pulse). Honor `prefers-reduced-motion`.

---

## Shared component inventory (use these, don't reinvent)

Plate strip · eyebrow (mono caps, coral for active) · display headline (period after: "May 5th.") · stat tile · mood pill · niggle chip · **segmented control** (Block/Month/Week/Day; Daily/Weekly/Monthly; Over-time/Spectrum) · **pace-volume chart** (stacked-by-zone, easy/hard hatch, target caps, now-ring, tap readout) · sparkline · **splits table** · **key-session star** · filter chips · coach quote (2px coral left-bar) · editorial rule · **empty-state** (eyebrow + italic nudge + optional CTA) · breadcrumb · link-card (cross-tab hand-off).

If a new pattern is needed, define it here first.

---

## Cross-cutting states

- **`data_depth` 0–3 gates the register.** 0 empty (plain UI text, no pull-quotes) → 3 full (editorial system, pull-quotes must cite a number). Every screen designs the depth-0 and depth-3 versions.
- **Empty states**: state the absence, then what fills it. Italic, secondary, no illustration, **never an em-dash placeholder**. e.g. *"No runs logged yet. When you do, your last entry lands here."*
- **Loading**: skeleton in card shape, no spinners on content; the record button may pulse.
- **Missing conditions data** (weather/grade backfill pending): show the metric without the adjustment and mark it — never fake precision.
- **Predictions/fitness/Effort**: range + confidence, whole-minute rounding. No seconds-precision projections.

---

## Accessibility & ergonomics

- Contrast ≥ 4.5:1 for text; the pale Easy blue uses `--pace-easy-text` (`#5E93BE`) for small text.
- Tap targets ≥ 44×44pt; chips and calendar cells included.
- Support Dynamic Type; numerals stay `tabular-nums` so columns don't jitter.
- VoiceOver: every chart has a text summary; mood is a labeled pill, never color-only; the niggle timeline reads as "3 mentions, easing."
- `prefers-reduced-motion`: kill the pulse and chart draw-in; keep fades.

---

## Per-tab brief template

Each of `log.md`, `training.md`, `trends.md`, `read.md`, `plan.md` uses these headings:

1. **The one job** — the question it answers, in a sentence.
2. **Current state & problems** — what the prototype does, where it falls short.
3. **Target layout** — top→bottom regions + a small ASCII wireframe.
4. **Components** — which inventory pieces, and any new one (justified).
5. **Interactions & states** — drill/scroll/tap, depth-0 vs depth-3, loading/empty.
6. **Improvements (prioritized)** — P0/P1/P2, concrete and buildable.
7. **Voice & copy** — sample eyebrows, headlines, empty-state lines.
8. **Open questions** — decisions to make.

---

## Global do / don't

**Do:** one coral element per visual cluster · numbers in pull-quotes at depth 2+ · hand off with link-cards · lead with feeling, follow with data · keep the pace ramp the only "spectrum."

**Don't:** stack cards inside cards · use coral as a pace fill · diagnose a body signal · show a single false-precise finish time · greet the user ("Good morning, Maya") · add a metric that another tab already owns.
