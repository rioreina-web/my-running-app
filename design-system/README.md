# Post Run Drip — Design System

> *Restraint as foundation, intensity as accent.*

Post Run Drip (PRD) is a running app for serious athletes — half **diary**, half **cockpit**. The voice is editorial: think *The New York Times Magazine* sports section, not a tech-bro fitness tracker. The product is built around the idea that a runner's data should read like a story, with a coach's voice running through it.

The aesthetic is a *sports desk*. White page. Near-black ink. One red — used as restraint allows, never as decoration.

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
| `styles.css` | Global stylesheet entry — imports `colors_and_type.css` |
| `components/` | Built React components (see **Components** below) |
| `fonts/` | Self-hosted faces: Crimson Pro, JetBrains Mono. PT Serif remains but is legacy. |
| `assets/` | PRD logo, brand marks, generic imagery |
| `preview/` | Design system tab cards — colors, type, components |
| `templates/app-screen/` | **Start here for a new screen** — phone shell, masthead, week ledger, entries, tab bar |
| `broadsheet/` | Direction II, "Broadsheet" — a parallel newsprint/editorial system, scoped `--bs-*` |
| `ui_kits/ios_app/` | iOS app recreation — TodayHome, Training, WorkoutDetail, Injuries, Sign-in |
| `slides/` | (none — no slide template was provided) |
| `SKILL.md` | Skill manifest for Claude Code compatibility |

---

## Components

Eight primitives are built and exported. Everything else in the app composes from these.

| Component | What it is |
|---|---|
| `Eyebrow` | Tracked monospace section label — `TUESDAY`, `FROM YOUR COACH`. `coral` for the one active section per screen. |
| `EditorialRule` | The canonical section break: thin rule · 3px dot · thin rule. A typesetting mark, not a divider. |
| `PlateStrip` | Plate header at the top of every editorial surface — surface name, figure number, date. |
| `MoodPill` | Tracked uppercase mood at 12% wash. Six moods, low chroma, no faces. |
| `StatTile` | Tracked label over a tabular monospaced numeral, with optional unit and delta. |
| `CoachQuote` | The "from your coach" blockquote — 2px coral-at-50% left stripe, italic body. The one coloured left border in the system. |
| `TypeChip` | Session type. Solid blue for the keyed session, hairline outline for everything easy. One keyed chip per screenful. |
| `LogEntry` | One run in the feed: mood dot, date, type chip, factual headline, the athlete's words, up to three stats, provenance byline. |

Each lives in `components/<Name>/` with its `.jsx`, a `.d.ts` describing its props, and a preview card.

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
PRD is a **white, near-monochrome system with a single red hit**. Red is *never* a fill across large surfaces — it's used the way a second ink is in a magazine: to point.

- **Surfaces** are pure white `#FFFFFF`. There is no tinted paper. Separation comes from **hairlines**, not from fills or shadows: `#EBEBEB` for the standard rule, `#F2F2F2` for the rare inset well, `2px #111111` when a header needs real weight.
- **Ink** is near-black `#111111`, with `#6B6B6B` for meta and labels. `#9A9A9A` exists for **hairlines and disabled states only** — at 2.8:1 it must never be used for text. Two text tones, not three.
- **Red** `#EE2B24` is the *only* accent, and it lives on fills: the record button, the active tab rule, the active tab-bar dot. For text at 13px or smaller use `#D31F19` (5.0:1) — the brand red fails contrast at label sizes. **One red element per visual cluster, maximum.**
- **Moods** are the only place additional hues appear, and all six were darkened to clear 4.5:1 — deep green, sage, amber, red, rose, plum. Tracked uppercase, and the entry's left rule carries the mood colour.

### Typography — five locked roles (Aug 2026)

| Role | Face | Token |
|---|---|---|
| Display | Instrument Sans 700 | `--font-display` |
| Label | Schibsted Grotesk 600, tracked caps | `--font-label` |
| Prose | Crimson Pro 400 — anything read as sentences | `--font-prose` |
| Data | Inter 500/600, tabular — every numeral | `--font-data` |
| Mono | JetBrains Mono — transcripts and machine answers only | `--font-mono` |

Every face is free to ship. Neue Haas Grotesk and Akzidenz-Grotesk were trialled and removed — licensed Monotype/Berthold faces with no legitimate webfont available. Instrument Sans replaced Haas on measurement: +3.1% width at 46px/700, the closest free grotesk, so no line break moved. Crimson Pro and JetBrains Mono are self-hosted in `fonts/`; the three grotesks load from Google. Times survives in exactly one role: the single-line italic dek (`--font-serif`). Archivo and PT Serif are retired. **Italic mono is the athlete; roman mono is the machine** — and the machine has no colour of its own, so weight (not hue) marks the values it computed.

**Copy rule:** a headline names the session, it never editorialises it. `6 × 800m.` — not "Six by eight hundred, held."

### Legacy note — one sans, two specialists
- **Helvetica Neue** — the whole interface. **Black (900)** for display, uppercase and tight (`-0.04em`), one line wherever possible. **Black** sentence-case for entry titles. **Bold (700)** for every tracked caps label at `+0.03em` to `+0.06em`. Archivo is the webfont fallback off Apple platforms.
- **Times** — the serif accent, italic. Deks, optional notes, credits. One or two lines at a time; never body copy. This is the contrast against the industrial sans, and the only serif in the system.
- **DM Mono** — every numeral, and the athlete's transcribed voice memos in *italic*. Data looks computed even mid-sentence; a voice memo looks transcribed.

Three registers, and you can tell who is speaking without a label: **Helvetica is the app**, **DM Mono italic is the athlete**, **Times italic is the aside**.

Type is the visual identity — not colour, not shape. If you only got the type right, the brand would still read.

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
- **Hairlines only.** `1px solid #EBEBEB`. The hairline is the design system's most-used border, and the *only* structural device — rules replace cards, tints, and shadows entirely.
- **A 2px ink rule** (`2px solid #111111`) when a header or block needs real weight.
- **A 2px accent rule** marks the active tab (`--red`) or an AI surface (`--ai`). Never both on one screen.
- **A 2px mood rule** runs down the left of a log entry, carrying that entry's mood colour. This is the one coloured left-border in the system. Do not generalize.
- **Editorial blockquote left-bar:** **2px** coral-at-50%-opacity stripe, 12px text inset — this is the canonical "from your coach" treatment. **This is the one place a colored left-border appears in the system.** Do not generalize.

### Shadow system
- **There is no shadow system.** `--shadow-card` and `--shadow-press` are `none`. Depth is not part of this brand; hairlines and type weight carry every hierarchy.
- The one exception is a sheet's top edge (`--shadow-sheet`, a 1px rule), because a sheet needs to read as a layer.
- No inset shadows. No coloured shadows. No blur, no glass, no `backdrop-filter`.

### Transparency / blur
- **Used nowhere.** Every surface is opaque white. Mood is a coloured word and a coloured rule, not a wash.
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
- **Tab bar at bottom**, 6 tabs (`LOG · TRAIN · TRENDS · WEEK · ASK · SHEET`), Helvetica Bold uppercase at 11px / `+0.03em`, a 6px dot above each. Active tab: filled red dot, ink label at 700. Inactive: hollow dot, `--ink-2` label. Hairline above, 44px minimum target.
- **Plate line at top** — the surface name alone (`RUNNING LOG`), Helvetica Bold caps 12px in `--ink-2`. The old two-line `— LOG · v1 VOICE LOG` strip and `FIG. 09` figure numbers are **retired**; they belonged to the serif era and read as costume here.
- **Header row** above it: hamburger left, `TODAY ↗` right in Bold caps. Both flat — no pills, no shadows.
- **Section tabs** under the plate: two Bold caps labels, 52px tall, active one in ink with a 2px accent rule beneath.

---

## Canonical screens

Two screens are canonical and consume the tokens directly (they link `styles.css` and hold no hardcoded colour):
**`Workout Sheet - Redesign.html`** and **`Voice Log - Neue Haas.html`**. The feed has not been migrated yet.

The three below are the earlier Helvetica/Archivo era, kept for reference. Read the canonical three first.

### `Voice Log 032c.html` — the reference
The screen every other screen is copied from. Plate line, two section tabs, a centred Helvetica Black uppercase hero (`LOG YOUR RUN.`) at 40px on one line, a Times italic dek, a `LINKED TO` row, then the red record button centred in the space that's left. Establishes the gutter (22px), the hairline rhythm, and the header treatment.

### `Log Feed 032c.html` — the diary
Filter chips (pill, black when active), `THIS WEEK · 25 MI` section labels, then entries. Each entry: a 2px mood rule down the left, a sentence-case Helvetica Black title at 23px, a Bold caps meta line with generous `word-spacing` around the middots, the voice memo in JetBrains Mono *italic*, and the mood in Bold caps in its own colour. Entries are separated by ~52px and a hairline — not by cards.

### `AI Insight.html` — generated content
Same chrome as Voice Log. The answer is JetBrains Mono **roman** in ink. Olive is retired: computed values are marked by weight, the label sits in `--ink-2`, and colour appears only where it names something real — blue on pace bands, a red wash behind the athlete's quoted words, orange on the heat penalty. The athlete's quoted words break out into Times italic. The active tab rule turns olive instead of red.

**The rule that ties them together:** *italic mono is the athlete, roman mono is the machine, Helvetica is the app, Times italic is an aside.* Four voices, and you never need a name label to tell who is speaking.

---

## What we are deliberately not

The warm-paper-and-coral system this replaced was well made, and it looked like every other AI product shipping in 2026: cream `#F5F3F0` surfaces, a burnt-orange accent, a literary serif, generous soft radii. That palette has become the house style of AI apps, and it made a running app for serious athletes read as a chatbot with a diary skin.

So, explicitly:

- **No cream, no beige, no warm paper.** The page is `#FFFFFF`. Warmth comes from photography and from the athlete's own words, never from the surface.
- **No literary serif for display.** Times appears only as a short italic aside. Headlines are Helvetica Black — a sports desk, not a novel.
- **No burnt orange or terracotta.** The accent is a hard red `#EE2B24`.
- **No soft cards.** `--r-card` is `0`. Radii exist only for pills and the record button.
- **No shadows, no tints, no washes.** If something needs separating, it gets a rule.
- **No emoji, no illustration, no gradient, no glass.**

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
2. **Red is a punctuation mark, not a paint.** When you find yourself adding a second red element, change one to ink-2 instead. Use `--red-text` for anything 13px or smaller.
3. **Type carries the brand.** Helvetica Neue Black for display, Bold caps for labels, DM Mono for numerals and voice, Times italic for asides.
4. **Hairlines, not boxes.** Structure comes from `1px #EBEBEB` rules and a `2px #111` rule under headers. No card shadows, no radii except pills.
5. **`--ink-3` is not a text colour.** Hairlines and disabled states only.
