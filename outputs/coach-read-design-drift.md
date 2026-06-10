# Coach Read — design system drift

**Why this exists:** I built `CoachReadView` and its components from the
textual descriptions in `coach-the-read-prompts.md` without ever
consulting `Post Run Drip Design System/`. This is the drift audit
against the actual reference set — `ui_kits/ios_app/Primitives.jsx`,
`tokens.css`, `colors_and_type.css`, and the patterns visible in
`TrainingScreen.jsx`.

**What this audit doesn't have access to:** the `Coach iOS.html` mock
that the prompts doc references as "Direction A · The Read." It's not
in the design system folder. Everything below is drift against the
*existing* primitive set; layout decisions that are unique to the
Coach Read page (the C-avatar byline, the WK 9/16 dateline) are
implemented per the prompts spec and can't be verified against a
pixel reference.

---

## High-visibility drift (worth fixing)

### 1. PlateStrip is one row; should be two stacked rows.

**Spec** (`Primitives.jsx` + `tokens.css`):
```
RUNNING LOG               FIG. 14
— COACH · THE READ        THE READ · 05.2026
```
- Two lines on each side, 2px gap between them
- "RUNNING LOG" and "FIG. 14" are `var(--ink)` (primary)
- The descriptor lines below are `var(--ink-2)` (secondary)
- 10px mono, **0.14em letter-spacing**, uppercase
- Horizontal padding: 24px from screen edge

**What I built** (`CoachReadView.swift:plateStrip`):
- One row, single line each side
- Both lines in `Color.drip.textSecondary`
- 10px mono with `.tracking(0.8)` — that's 0.08em at 10pt, half what the spec calls for
- 20px horizontal page padding (drift below)

**Fix:** rebuild as two stacked rows with the correct color split and
0.14em tracking (= 1.4pt at 10pt font).

### 2. Page padding is 20pt; should be 24pt.

**Spec** (`tokens.css:.page__body`): `padding: 16px 24px 24px 24px;`

**What I built:** `.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 32)`

**Fix:** 24pt horizontal, 16pt top, 24pt bottom.

### 3. Chip-card corner radius is 4pt; should be 12pt.

**Spec** (`tokens.css:.card` and `.stat-tile`): `border-radius: 12px;`

**What I built** (`EvidenceChip.expanded`, `DocChip.expanded`):
`.cornerRadius(4)` — that's the value for inline chip pills, not for
cards. The design system uses 4pt only for tight pills/capsules
(`.r-tight`); cards use 12pt (`.r-card`).

**Fix:** expanded chip cards → 12pt. Inline chip pills stay at 4pt.

### 4. Headline line-height is too loose.

**Spec** (`colors_and_type.css:.drip-display`): `line-height: 1.05`

**What I built:** `.lineSpacing(0)` — gives SwiftUI's default ~1.0
line-height-ish but it's font-rendering-dependent.

**Fix:** make the headline render at line-height 1.05 explicitly via a
`.lineSpacing(<computed>)` or convert to a `Text` with `AttributedString`
that carries an explicit line-height. Less urgent than the plate strip.

---

## Medium drift (tracking + weight values across many files)

### 5. Mono label letter-spacing is too tight everywhere.

**Spec** (`tokens.css`):
- Plate strip: `0.14em`
- Section eyebrows ("FROM YOUR COACH", "WEEK 09 OF 16"): `0.12em`
- Captions / pills: `0.10em`

**What I built:** `.tracking(0.8)` (and sometimes `.tracking(0.5)`)
across every mono label.

In SwiftUI `.tracking()` is in absolute points, not em. The
conversions:
- 0.14em × 10pt = **1.4pt**
- 0.12em × 10pt = **1.2pt**, × 11pt = **1.32pt**
- 0.10em × 10pt = **1.0pt**

**Affected files:** `EvidenceChip`, `DocChip`, `CantSeeBlock`,
`ConfidenceBar`, `SourcesPanel`, `CoachReadView`, `DocDetailSheet`,
and the existing `DesignSystem.swift`'s `dripStat` callers if you
want consistency.

**Fix:** sweep across all Coach Read files; use 1.0pt for captions,
1.2pt for section eyebrows, 1.4pt for plate strip.

### 6. Eyebrows are semibold; should be medium.

**Spec** (`colors_and_type.css:.drip-eyebrow`): `font-weight: 500;`

**What I built:** `Font.dripStat(N)` is defined in `DesignSystem.swift`
as `.system(... weight: .semibold ...)` (600).

**Fix:** either add a `dripStatMedium(_:)` font helper in
`DesignSystem.swift` for the eyebrow case, or accept this drift —
it's subtle and the existing app uses semibold throughout. Cheaper to
leave alone unless we're doing a sweep.

### 7. Coach Quote primitive exists; CantSee block is adjacent but not identical.

**Spec** (`Primitives.jsx:CoachQuote` + `tokens.css:.coach-quote`):
- 14px italic body
- 2px coral 50% alpha left bar (`rgba(212,89,42,0.5)`)
- "the *one* place coloured left-borders appear in the system"

**What I built** (`CantSeeBlock`):
- 13.5px italic body
- 2px ink-tertiary (gray) left bar
- Mono eyebrow on top

**Tension:** the design system says coral is the only colored left bar,
and my `CantSeeBlock` uses gray — that follows the rule. But the body
size is 13.5 instead of 14, and the mono eyebrow on top isn't part of
the `CoachQuote` primitive. The `CantSeeBlock` is a *distinct* pattern
(uncertainty, not coach voice), so it doesn't strictly need to be a
`CoachQuote`. But it should at least bump to 14px body.

**Fix:** body 13.5 → 14pt. Keep gray bar (correct per the rule).

---

## Low drift (notes for the IMPLEMENTATIONS map)

### 8. Headlines should end in a period.

**Voice note** (`ui_kits/ios_app/README.md`): "All headlines end in
a period: `May 5th.`, `Marathon block.`, `Active aches.`"

**What I did:** the v2 prompt's example headlines end in periods ("The
base is taking.", "Quiet week — that's by design.") and the
`#Preview` mocks follow the rule.

**Status:** ✓ already correct — prompt and previews comply. No code
change needed.

### 9. Separators are `·` (middle dot), never `|` or `/`.

**Voice note** (`README.md`).

**What I did:** consistent use of `·` throughout the Read components.

**Status:** ✓ already correct.

### 10. Plate strip surface name.

**Pattern observed** (`TrainingScreen.jsx`): `surface="TRAINING · RE-TUNING"`
— a two-segment hierarchy where the first segment is the section name
and the second is the artifact / sub-title.

**What I built:** `"COACH · THE READ"` — already a two-segment value.
Fits the pattern when laid out on the second stacked row.

**Status:** ✓ value is correct, layout (one-row vs two-row) is the
drift to fix.

---

## Layout patterns I implemented per the prompts doc that aren't
verifiable against the design system

These were specified in `coach-the-read-prompts.md` Phase 4.1 but
have no precedent in `ui_kits/ios_app/`. Implemented from the textual
spec only. Worth review when the `Coach iOS.html` mock arrives.

- **Dateline row** with WK 9/16 + ↗ HISTORY — not a standard pattern
  in the iOS UI kit. TrainingScreen instead uses a section eyebrow row
  ("TRAINING · WEEK 09 OF 16" coral + "MON · APR 27" ink-2) above the
  headline.
- **Coach byline** with 28pt black-circle C-avatar — no equivalent
  primitive exists; this is a Coach Read invention per the doc.
- **Signature line** ("— posted Thursday morning · 4 min read") in
  italic body 12pt — fits the system's italic caption treatment but
  isn't a documented primitive.
- **Ask bar** pinned at bottom — not in the UI kit. The doc's
  `.safeAreaInset(edge: .bottom)` placement is a reasonable SwiftUI
  pattern.

---

## Proposed fix order

If we want to ship the Read with verified design fidelity:

**Phase A — high-visibility drift (1-2 hours):**
1. Rebuild `plateStrip` in `CoachReadView` as two stacked rows with
   correct ink/ink-2 colors and 1.4pt tracking.
2. Update page padding: 24pt horizontal, 16pt top, 24pt bottom.
3. Update `EvidenceChip` and `DocChip` expanded cards: corner
   radius 4 → 12.
4. Update `CantSeeBlock` body: 13.5 → 14pt.

**Phase B — tracking sweep (~30 min):**
1. Update `tracking()` values across all Coach Read components per
   the conversion table above.

**Phase C — only if we want to be exhaustive:**
1. Add `dripStatMedium(_:)` to `DesignSystem.swift` for 500-weight
   eyebrow case and sweep callers.
2. Fix headline line-height to 1.05 explicitly.

**Phase D — gated on the missing mock:**
1. Once `Coach iOS.html` is in the design system folder, do a real
   pixel-faithful review of the dateline, byline, signature, and
   ask-bar treatments — and update `IMPLEMENTATIONS.md` row for
   "Coach iOS" with parity-verified yes.

---

## What this audit doesn't change

The behavioral work — the morning Read generating correctly with the
right citations, the mode-aware prompt branching by user state, the
chip caches hydrating, the trigger firing on quality workouts — is
unaffected by visual drift. Phases A-C are all cosmetic. If we ship
as-is and look at output for a week, the test results are still
valid; the styling just won't match the design system 1:1.

If you want the design verified before launch, do Phases A and B
before flipping the cron on for users.
