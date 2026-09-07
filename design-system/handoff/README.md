# Fitness Predictor — Rebrand Handoff

This bundle contains everything needed to port the rebranded design onto the
current iOS implementation.

## Contents

- `design/Fitness Predictor Rebrand.html` — the rebrand artboard (open in a browser)
- `design/fitness-predictor-rebrand.jsx` — the source-of-truth markup + styles
- `design/ui_kits/` — shared tokens (`ios_app/tokens.css`) + primitives the JSX uses
- `swift/FitnessPredictorView.swift` — current production view (847 lines, what we replace)
- `swift/FitnessPredictorModels.swift` — data models (no changes needed)
- `swift/FitnessPredictorService.swift` — fetch/predict logic (no changes needed)

The port is **view-only**. Service + models stay untouched.

## Token mapping (CSS var → SwiftUI)

| Rebrand CSS var | SwiftUI |
|---|---|
| `--coral`            | `Color.drip.coral` |
| `--paper`            | `Color.drip.background` |
| `--ink`              | `Color.drip.textPrimary` |
| `--ink-2`            | `Color.drip.textSecondary` |
| `--ink-3`            | `Color.drip.textTertiary` |
| `--rule`             | `Color.drip.divider` |
| `--font-mono`        | `.dripCaption(n)` + `.monospacedDigit()` |
| `--font-display`     | `.dripDisplay(n)` |
| `--font-body` italic | `.dripBody(n).italic()` |

Any CSS use without a Swift token: add it to `App/DesignSystem.swift` once,
don't inline a hex.

## Porting pass order

1. **Strip the chrome.** Remove the `.toolbar` "FITNESS PREDICTOR" + refresh
   button and the `DripBackground`. Replace with an inline plate-strip header
   (eyebrow + refresh icon over a 1pt `Color.drip.divider` rule).
2. **Delete card-in-card.** Each `*Card` becomes a hairline-bordered section —
   no `cardBackground`, no rounded rects. Horizontal padding goes 20 → 24.
3. **Port section-by-section** (keep the Swift type names, rewrite the bodies):
   - `PredictionErrorBanner` → quiet italic between two hairlines, coral label only
   - `RacePredictionsCard` → hairline-row table; goal row gets coral name + time
   - `TrainingCard` → two stacked hairline sections (paces / stimulus)
   - `FitnessTrendCard` → keep canvas, drop card shell
   - `FitnessSummaryCard` → italic paragraph between hairlines, no fill
   - `DataSourcesRow` → mono row, no chip backgrounds
4. **Numerals + eyebrows.** Every numeric value gets `.monospacedDigit()`.
   Every uppercase mono label is `.dripCaption(10).tracking(1.4)`
   (≈12% letter-spacing at 10pt).

## Suggested commit order

header → error banner → race predictions → training paces →
fitness trend → summary → data sources

One commit per section keeps the screen compiling and makes review easy.
