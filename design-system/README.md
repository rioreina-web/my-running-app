# Post Run Drip — Design System

> *Restraint as foundation, intensity as accent.*

Post Run Drip (PRD) is a running app for serious athletes — half **diary**, half **cockpit**. The voice is editorial: think *The New York Times Magazine* sports section, not a tech-bro fitness tracker. The product is built around the idea that a runner's data should read like a story, with a coach's voice running through it.

The aesthetic is a *printed running log*. Warm paper. Black ink. One coral accent — used as restraint allows, never as decoration.

---

## Source material

This design system was extracted from one attached codebase:

- **`my-running-app/`** — local mounted folder containing:
  - **`RunningLog/`** — the iOS SwiftUI app (the actual product). Look first at:
    - `RunningLog/App/DesignSystem.swift` — color + type tokens, button, mood badge, stat card, section header, editorial rule
    - `RunningLog/App/TodayHomeView.swift` + `TodayPlate18.swift` — the diary+cockpit home tab (the canonical screen)
    - `RunningLog/Training/TrainingDashboardView.swift` — the Training tab (week strip, weekly mileage, coach plan)
    - `RunningLog/Workouts/WorkoutDetailPlate23.swift` — the "Pace, narrated" workout detail
    - `RunningLog/Analysis/InjuryPlate28.swift` — the "Active aches" injury tracker
    - `RunningLog/Assets.xcassets/Logo.imageset/` — primary logo art
    - `RunningLog/Fonts/` — Crimson Pro + PT Serif TTFs (shipped with the app)
  - **`design/`** — 29 PNG "plates" + a PDF (`trends_mockups.pdf`) of design direction. Read like a printed art-direction deck. Each plate is captioned ("Plate 18 / 29 · restraint as foundation, intensity as accent.") and they collectively define the editorial voice better than any single doc.
  - **`docs/coaching/principles.md`** — coaching voice / tone guide
  - **`docs/conventions/empty-states.md`** — copy patterns for empty states
  - **`supabase/`** — backend (LLM coaching agents — informs the *voice* of in-app coach copy)

There are also two outputs in this project that exist outside the codebase but came with it:
- `RunningLog/RunningLog/Shannon.mov` — onboarding intro video (not copied)
- `design/trends_mockups.pdf` — concatenated plates (not copied)

The codebase reader has access — assume the reader does not, and rely on this design system as the source of truth.

---

## What's in this folder

| Path | What |
|---|---|
| `colors_and_type.css` | Foundational CSS vars — color, type, spacing, radii, motion |
| `fonts/` | Crimson Pro variable + PT Serif (Regular/Italic/Bold) TTFs from the iOS app |
| `assets/` | PRD logo, brand marks, generic imagery |
| `preview/` | Design system tab cards — colors, type, components |
| `ui_kits/ios_app/` | iOS app recreation — TodayHome, Training, WorkoutDetail, Injuries, Sign-in |
| `slides/` | (none — no slide template was provided) |
| `SKILL.md` | Skill manifest for Claude Code compatibility |

---

## Content fundamentals

The voice is the heart of the product. Get this wrong and everything looks generic.

### Tone — "editorial diary, coach in the room"
- **Spare. Declarative. No throat-clearing.** "Tempo, 8 miles." not "Today's workout: Tempo run of 8 miles."
- **Coach voice is direct and second-person.** *"Consistent splits, not negative. Let the rhythm settle."* You is the athlete; the system never refers to "users."
- **Diary voice is first-person, past tense, in quotes.** *"Felt good through the warm-up — legs were heavy first mile but loosened up."*
- **Never cheerlead.** No "Great job!", no "You crushed it!", no emoji praise. Observation > congratulation.
- **The plate footers set the register.** *"Diary spine on top, cockpit's bottom half on the bottom. Strain/TSB tiles dropped — data not honest yet."* This is how the team talks internally; the app should sound the same.

### Casing & punctuation
- **Section labels: ALL CAPS + tracked**, monospaced. `TUESDAY`, `FROM YOUR COACH`, `ZONE SHIFTS · WEEK vs 4 WK AVG`.
- **Body & display: Sentence case.** "How are you feeling?" "Marathon block." "Pace, narrated."
- **Period after standalone headlines.** *"May 5th."* *"Today · Diary + Charts."*
- **Middle dot** (`·`, U+00B7) is the workhorse separator. `SUNDAY · APR 26`, `8.4 mi · 7:42 / mi · 64 min · TIRED`. *Never* use `|`, `—` or `/` as a separator in those positions.
- **En-dash for ranges and asides.** `6:24–6:56 / mi`, *"loosened up — Tempo blocks smoother."*
- **Em-dash for sentence breaks** in diary/coach copy: *"Hold splits, don't chase them — negative is fine, positive is not."*
- **Curly quotes** in body copy: `"Felt strong through 14, started to fade on the hills…"`
- **Lowercase paces and units.** `7:42 / mi`, `47 days out`, `11 mi.`, `1 mi CD`.
- **Numerals always.** `5 mi`, not `five miles`. `47 days`, not `forty-seven`.

### Pronouns
- **"You / your"** for the athlete in coach-voice. `From your coach`, `Your MP 5:32`.
- **First-person ("I / my")** appears *only* inside quoted voice-log entries — never in system copy.
- **No "we."** The app doesn't talk about itself.

### What we do *not* say
- No "AI-powered," no "smart," no "personalized." (The Coach is the personalization — let the voice carry it.)
- No "engage," "unlock," "discover," "journey," "wellness," "vibes."
- No exclamation points outside diary quotes.
- No emoji. (Mood is communicated through tracked uppercase pills + dot color, not faces.)
- No filler greetings. There is no "Good morning, Alex." The header is `TUESDAY` over `May 5th.`

### Empty states (from `docs/conventions/empty-states.md` patterns)
> *"No runs logged yet. When you do, your last entry lands here."*

The pattern: **state the absence, then say what will fill it.** Italic, secondary color, no illustration.

### Specific phrasings to lift
- *"How are you feeling?"* (the daily check-in prompt — never reworded)
- *"From your coach"* (eyebrow on coach notes)
- *"Mark complete ↗"* (primary action style — verb + arrow, underlined coral)
- *"Tomorrow's prescription"* / *"Yesterday's journal entry"* (relational, not date-stamp)
- *"Not medical advice. If anything gets sharper, see a clinician."* (the liability tone — quiet, italic, secondary)
- *"— restraint as foundation, intensity as accent"* (plate footer signature — repeats verbatim)

---

## Visual foundations

### Color — one accent, used like punctuation
PRD is a **monochromatic warm-paper system with a single coral hit**. Coral is *never* a fill across large surfaces — it's used the way italics or a colored capital is in a magazine: to point.

- **Surfaces** are warm paper `#F5F3F0` with white cards `#FFFFFF` and a slightly warmer elevated white `#FAFAF8`. The `#E8E4DF` deep paper appears in calendar wells.
- **Ink** is rich black-warm `#1A1815` (not pure `#000`), with `#6B6560` warm gray for meta and `#9B9590` for captions. Three text tones, no more.
- **Coral** `#D4592A` is the *only* accent. It appears as: the eyebrow color for the active section, the active-day dot in the week strip, the "Mark complete" underline, the orange line in HR-zone bars, the record button, and inline links. **One coral element per visual cluster, maximum.** If two would compete, drop one to ink-2.
- **Moods** are the only place additional hues appear, and they sit at low chroma — deep green, sage, amber, terracotta, deep rose, plum. Always rendered as a tracked uppercase pill at 12% wash, never as a full fill.

### Typography — three families, sharply assigned
- **Crimson Pro** (variable serif) — display headlines, button labels, section actions. Bold, tall, slightly condensed. Used for "May 5th.", "Marathon block.", "Active aches."
- **PT Serif** — body, paragraph copy, italic quotes. Warm and readable.
- **Monospaced** (`SF Mono` on iOS / `ui-monospace` on web) — *every* uppercase label, eyebrow, stat caption, plate strip. Tracked `+0.10em` to `+0.14em`. Numerals are also monospaced (`tabular-nums`) so columns of stats stay rectangular.

Type is the visual identity — not color, not shape. If you only got the type right, the brand would still read.

### Spacing & layout
- **8pt grid.** 4 / 8 / 12 / 16 / 20 / 24 / 32 / 40 / 56.
- **24px horizontal screen padding** on iOS surfaces. Sections separated by 24px vertical rhythm.
- **Cards are flat.** White, 12px radius, hairline shadow `0 2px 8px rgba(0,0,0,0.06)`. No card-on-card. No nested cards.
- **Editorial rule** (`thin line · 3px dot · thin line`) is the canonical section break. *Not* a horizontal `<hr>`. The rule is a *typesetting mark*, not a divider in the usual product-design sense.
- **Stat cards** lay out 1- or 2-up at full bleed. Never 3-up at this width — squeezes the numerals.
- **No glass, no blur, no overlay.** Sheets are opaque white over the paper background; protection is achieved by being on a card, not by gradient.

### Background treatments
- **No images as background.** Ever.
- **No gradients.** The product reads as ink-on-paper.
- **No textures, no grain.** The warmth comes from the paper-tone hex, not noise.
- **No repeating patterns.** The closest thing to "pattern" is the column of monospaced ALL-CAPS labels, which gives the design its visual rhythm.

### Animation
- **Restrained.** Default to `easeInOut 300ms`. The record button gets a slow `1800ms` pulse breath. Tab transitions are 300ms. Mood pill state changes are 150ms.
- **No bounces** except on the haptic-feedback record button (scale 1.0 → 1.03 → 1.0).
- **No springs** on layout-affecting transitions.
- **Fade-only** for screen transitions.

### Interactive states
- **Hover (web equivalent / pointer):** ink-2 → ink for links; coral → coral-deep `#B84420` on the primary action. Underline appears on hover for editorial links.
- **Press:** scale `0.98`, transition 150ms. The primary button additionally darkens to coral-deep.
- **Disabled:** opacity `0.5`, no color change.
- **Focus:** 2px coral outline, 2px offset. Never a glow.

### Borders, dividers, edges
- **Hairlines only.** `1px solid #E8E4E0`. The hairline is the design system's most-used border.
- **Coral border on selected/active:** `1.5px solid #D4592A` (e.g. the active mood radio, the active week-strip cell ring).
- **Editorial blockquote left-bar:** **2px** coral-at-50%-opacity stripe, 12px text inset — this is the canonical "from your coach" treatment. **This is the one place a colored left-border appears in the system.** Do not generalize.

### Shadow system
- **`shadow-card`** — `0 2px 8px rgba(0,0,0,0.06)`. The default. Tiles, sheets.
- **`shadow-coral`** — `0 4px 12px rgba(212,89,42,0.30)`. *Only* the primary record button.
- **`shadow-press`** — `0 1px 2px rgba(0,0,0,0.04)`. Pressed/recessed surfaces.
- No inset shadows. No multi-layer shadows. No colored shadows except the coral on the record button.

### Transparency / blur
- **Used almost nowhere.** The mood-pill background is `coral-wash` (12% coral) — that is the only transparency in the system.
- **No `backdrop-filter`** anywhere.

### Imagery (when needed)
- The product is text-first; product imagery is rare.
- When imagery appears (e.g. an athlete photo in onboarding), it is **black-and-white or desaturated warm tone**, never the iPhone-color-bright look. Think *The Atlantic* photo essay.
- No stock photography. No illustration.

### Corner radii
- **Pills:** 999px (mood badges, capsule pills).
- **Cards:** 12px.
- **Buttons:** 10px.
- **Inputs:** 8px.
- **Inset/sharp:** 4px (small marker rectangles like the "stop recording" inner square).
- Nothing is square (`0px`). Nothing is more rounded than `12px` except pills.

### Cards
- White fill `#FFFFFF` (or elevated `#FAFAF8` for hover/active).
- 12px radius.
- 16px internal padding (24px on hero cards).
- `shadow-card` only — no border on cards.
- Cards stand alone on the paper — no card-in-card.

### Fixed elements
- **Tab bar at bottom**, 5 tabs (`LOG · TRAIN · TRENDS · COACH · RUNS`), monospaced uppercase labels with the active label in coral and a filled coral 6px dot above. Hairline divider above.
- **Plate strip at top** of editorial surfaces (`RUNNING LOG — TRENDS · v1 ANALYTICS SURFACE` left, figure number + date right). Monospaced, tracked, on `paper` background.

---

## Iconography

See [`ICONOGRAPHY.md`](#iconography) section below — the codebase uses **Apple SF Symbols** native on iOS. For web/design recreations:

- **Source:** [Lucide](https://lucide.dev) via CDN (`https://unpkg.com/lucide@latest`). Closest stroke-weight + style match to SF Symbols (24px grid, 1.5px stroke, rounded line joins). **Flagged substitution** — these are not the assets the iOS app actually ships with.
- **Style:** Stroked, **not filled**. The only filled glyph in the system is the active-tab dot.
- **Color:** `ink-2` by default. `coral` on the *one* active or in-progress element per cluster.
- **Sizing:** 14px in pills/buttons, 16px inline with text, 20px in tab bars, 24px stand-alone.
- **No emoji.** Mood is communicated by the tracked uppercase pill plus dot color, never a face.
- **No unicode glyphs as icons** except: `·` (middle dot — separator), `↗` (action arrow on links like "Mark complete ↗", "View All ↗"), `→` (rare, in directional copy).
- **No icon backgrounds.** Icons sit on the surface; they are never inside colored chip backgrounds.

### Logo
- **`assets/PRD-Logo-On-Black.png`** — the primary mark. "post run drip" set in a bold geometric sans (weighty, slightly condensed — not Crimson Pro), arranged on three lines with a literal **drip drop hanging from the lowercase "p"** of "drip". Always on a deep ink or black field. This is the *only* place a different typeface appears in the system.
- **`assets/PRD-White.png`** — same logo in white-on-transparent for placement on dark or image backgrounds.
- The wordmark is never rendered in coral and never as a single line.

---

## Index

- [`colors_and_type.css`](./colors_and_type.css) — paste into any artifact; gives you every color, type ramp, spacing token
- [`fonts/`](./fonts/) — TTF files (Crimson Pro variable, PT Serif Regular/Italic/Bold)
- [`assets/`](./assets/) — Logos, brand marks
- [`preview/`](./preview/) — Design-system cards (colors, type, components, brand) — these populate the Design System tab
- [`ui_kits/ios_app/`](./ui_kits/ios_app/) — Interactive iOS app recreation; see its own README
- [`SKILL.md`](./SKILL.md) — Agent skill manifest

---

## How to use this system

1. **Always start with the editorial voice.** If your copy is "wellness app" generic, the visuals can't save it.
2. **Coral is a punctuation mark, not a paint.** When you find yourself adding a second coral element, change one to ink-2 instead.
3. **Type carries the brand.** Use Crimson Pro display for headlines, PT Serif for body, monospaced for every uppercase label.
4. **Editorial rules, not horizontal lines.** Use the `line · dot · line` divider for section breaks.
5. **The plate header strip + footer caption** is the single most identifiable visual gesture. Use it on any standalone artifact (slides, exports, web pages).
