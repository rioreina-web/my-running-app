# Post Run Drip — design system

A running app that reads like an editorial page. White stock, one red, numbers set
in tabular figures, and the athlete's own words treated as the only prose in the
interface.

Status: Direction I is the product system. Direction II ("Broadsheet") is a
parallel newsprint direction kept for comparison, scoped so the two can never mix.
Last updated Aug 2026.

---

## 1. Type — five roles, one face each

| Role | Face | Token | Used for |
|---|---|---|---|
| Display | Instrument Sans 700 | `--font-display` | Every headline. Sentence case, tracking −0.035em, one line where possible. |
| Label | Schibsted Grotesk 600 | `--font-label` | Every tracked uppercase label. 9–11px, tracking 0.15–0.20em. |
| Prose | Crimson Pro 400 | `--font-prose` | Anything read as sentences — the written summary, the memo. 20px/1.48. |
| Data | Inter 500/600 | `--font-data` | Every numeral, tabular. Doubles as body/UI copy. |
| Mono | JetBrains Mono 400 | `--font-mono` | Transcripts and machine answers, nothing else. |
| Accent | Times italic | `--font-serif` | Exactly one role: the single-line italic dek. |

**Never introduce a sixth family.**

### The one distinction that matters

> **Italic mono is the athlete. Roman mono is the machine.**

Same family, different posture — no avatar, no badge, no colour needed. The machine
has **no colour of its own**: the values it computed are marked by weight (500), and
its label sits in `--ink-2`. AI output is never set in Crimson (that would read as a
person's own conclusion) and never in italic (that would borrow the athlete's voice).

### Licensing — settled, do not relitigate

Neue Haas Grotesk Display and Akzidenz-Grotesk were both trialled and removed. They
are licensed Monotype / Berthold faces; the only freely downloadable files are rips
(the Akzidenz folder shipped a Berthold notice forbidding redistribution).

Instrument Sans was chosen **on measurement**, not taste. Rendered width of
"Recovery." at 46px/700:

| Face | Width | vs Haas |
|---|---|---|
| Neue Haas Display | 190 px | baseline |
| **Instrument Sans** | **196 px** | **+3.1%** |
| Helvetica Neue | 199 px | +4.6% |
| Archivo | 202 px | +5.9% |
| Inter | 210 px | +10.3% |
| Schibsted Grotesk | 210 px | +10.5% |

Instrument Sans holds the line break; that is why it took the headline. Schibsted is
the widest face measured, which is why it took the labels, where width costs nothing.
Inter is barred from display — keeping Inter on numerals against a tighter grotesk on
headlines is the contrast the system is built on. Archivo is ruled out on era, not
measure: it is the face this system wore while it looked like every other 2026 product.

Self-hosted in `fonts/`: Crimson Pro, JetBrains Mono. From Google: Instrument Sans,
Schibsted Grotesk, Inter.

---

## 2. Colour

### Surfaces and ink

| Token | Hex | Job |
|---|---|---|
| `--paper` | `#FFFFFF` | The page. Pure white. |
| `--paper-deep` | `#F2F2F2` | Inset wells only. |
| `--rule` | `#EBEBEB` | The hairline — the most-used border in the system. |
| `--rule-strong` | `#111111` | 2px editorial rule under a header. |
| `--ink` | `#111111` | Display and body. |
| `--ink-2` | `#6B6B6B` | Meta and labels. 5.3:1 — safe at 10px. |
| `--ink-3` | `#9A9A9A` | **Hairlines and disabled only. 2.8:1 — never text.** |

### Accents

| Token | Hex | Job |
|---|---|---|
| `--red` | `#EE2B24` | Fills: record button, active tab rule, dots. |
| `--red-text` | `#D31F19` | The same red as type, ≤13px. 5.0:1. |
| `--red-wash` | `rgba(238,43,36,.10)` | A tinted band or a highlight behind quoted words. |
| `--session` | `#1F4FA8` | Names a keyed session, and references. 7.3:1. |

One red. It points; it never fills a large surface. Blue names the keyed session and
real references (a linked run, a source). If blue starts appearing as chips and bars
everywhere, it has stopped meaning anything — that mistake has been made once already.

### Mood — one ramp

Green good → grey nothing → orange tired → two reds for trouble. All clear 4.5:1,
because a mood is always type or a dot, never a large fill.

| Token | Hex | Contrast |
|---|---|---|
| `--mood-energized` | `#12703A` | 5.9:1 |
| `--mood-positive` | `#1F7A41` | 5.2:1 |
| `--mood-neutral` | `#6B6B6B` | 5.3:1 |
| `--mood-tired` | `#A8560A` | 4.8:1 |
| `--mood-struggling` | `#C62828` | 4.9:1 |
| `--mood-injured` | `#8E1219` | 8.2:1 |

`--mood-speed` (`#5A3C78`) sits off the ramp — it is a session type, not a feeling.

**Known collision:** struggling `#C62828` sits close to brand red `#EE2B24`.
Distinguishable side by side, but if it ever reads as one colour, push struggling to
`#B3261E` or drop the step entirely.

### Retired

Olive (`#8CA02E` / `#5F6F00`) is gone. `--ai` and `--ai-text` still exist and resolve
to ink so older files don't break, but the machine gets no hue.

---

## 3. Copy rules

**A headline names the session. It never editorialises it.**

| Never | Write |
|---|---|
| Six by eight hundred, held. | 6 × 800m. |
| Eighteen miles, headwind. | 18 miles, long run. |
| Called it at three. | Cut short at 3 miles. |
| Sick, but out the door. | Easy 4.4 miles. |

Spelled-out numbers plus a mood-word flourish is the app writing poetry about someone
else's run. The interface supplies the facts; the athlete supplies the feeling, in
their own transcribed words — which keep their voice exactly as spoken.

Also: numerals stay numerals (`5 mi`, never "five miles"). No emoji. No cheerleading.
No exclamation points. No title-case headlines. Never "we" — the app doesn't talk
about itself.

---

## 4. Structure

- **8pt spacing scale**, 22px canonical screen gutter.
- **Hairlines replace cards, tints and shadows.** `--shadow-card` and `--shadow-press`
  are `none`. Depth is not part of this brand.
- **Radii:** pills 999px (record button, chips); everything else 0–4px. Print has no
  rounded corners.
- **Rules do the work:** 1px hairline for separation, 2px ink rule when a section needs
  weight, 2px red rule for the active state.
- **Minimum type size 9px**, and only for tracked caps in the label face.
- **44px minimum hit target.**

---

## 5. Components

Eight built primitives in `components/<Name>/` (`.jsx` + `.d.ts` + preview card):

| Component | What it is |
|---|---|
| `LogEntry` | One run in the feed: mood dot, date, type chip, factual headline, the athlete's words, up to three stats, provenance byline. Prose **or** voice, never both. |
| `TypeChip` | Session type. Solid blue for the keyed session, hairline outline for everything easy. One keyed chip per screenful. |
| `StatTile` | Tracked label over a tabular Inter numeral, optional unit and delta. |
| `MoodPill` | Tracked uppercase mood. Six moods, no faces, no emoji. |
| `Eyebrow` | Tracked section label. |
| `PlateStrip` | Surface name at the top of a screen. |
| `EditorialRule` | The canonical section break. |
| `CoachQuote` | The "from your coach" blockquote — the one coloured left border in the system. |

Note: `MoodPill`, `Eyebrow`, `PlateStrip`, `EditorialRule` and `CoachQuote` were built
in the earlier Helvetica/Archivo era and still carry `--font-mono` labels and coral
aliases. They render, but they have not been retyped onto the locked roles.

**Starting point:** `templates/app-screen/` — phone shell, masthead with the logo,
week ledger, entries, tab bar.

---

## 6. Screens

**Canonical** (link `styles.css`, zero hardcoded colour — change a token and they follow):

- `Workout Sheet - Redesign.html`
- `Voice Log - Neue Haas.html`
- `Log Feed - Migrated.html` — the 032c layout, unchanged, retyped on the locked system

**Earlier eras, kept for reference:** `Voice Log 032c.html`, `Log Feed 032c.html`,
`AI Insight.html`, `Training Screen v1–v3`, and the older Crimson + PT Serif set
(`Home Page v4`, `Plan Page`, `Training Log / Analysis / Summary`, `Fitness Predictor`,
`Workout Card`). These hardcode their own tokens and do not follow the system.

---

## 7. Direction II — Broadsheet

A parallel system, not a theme: `broadsheet/broadsheet.css`, scoped `--bs-*` / `.bs-*`.
Never mix its tokens with Direction I's.

Newsprint `#F7F5EF`, warm ink `#14120E`, one hot red `#D8341F` (`#B82612` as type),
desk blue `#1B3A6B`. Instrument Serif display, Newsreader text, Archivo Narrow labels,
IBM Plex Mono data. 26px gutter, 54px between articles, zero radii except the record
button. The athlete's words get a standfirst and a drop cap, because they are the
article. Copy is dated like filed copy: "filed against", "reassign", "nothing filed".

---

## 8. Open questions

1. **The five era-one components** need retyping onto the locked roles, or explicit
   retirement.
2. **Eight legacy screens** still run Crimson + PT Serif on `ui_kits/ios_app/tokens.css`.
   The stated intent is to rebuild them on the locked system; none have been done.
3. **Inter is not self-hosted.** Everything else either is or is retired — worth
   closing for offline/consistency.
4. **Struggling vs brand red** (see §2).
5. **Direction I vs Broadsheet:** no decision has been made about whether Broadsheet is
   an experiment, a marketing skin, or the future of the product.

---

## 9. Files

| Path | What |
|---|---|
| `styles.css` | Entry point; imports `colors_and_type.css`. |
| `colors_and_type.css` | Every Direction I token, plus the semantic `.drip-*` classes. |
| `broadsheet/broadsheet.css` | Direction II tokens and `.bs-*` classes. |
| `CLAUDE.md` | Standing rules: copy, type roles, no licensed faces. |
| `components/` | The eight built primitives. |
| `templates/app-screen/` | Starting point for a new screen. |
| `preview/` | Design-system cards — colour, type, components, brand voice. |
| `fonts/` | Crimson Pro, JetBrains Mono (PT Serif remains, legacy). |
| `assets/` | Logo and brand marks. |
