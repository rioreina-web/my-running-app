# Palette — Post Run Drip

**Status:** white + scarlet trial, applied to iOS only.
**Last changed:** 2026-08-21
**Source of truth:** `RunningLog/RunningLog/App/DesignSystem.swift`

> ⚠️ **The three surfaces disagree right now.** iOS carries the values below.
> `web/src/app/globals.css` and `design-system/colors_and_type.css` are still on
> the old cream + coral palette. See [Divergence](#divergence) before committing.

---

## The three-palette rule

The system carries three colour families that **never share a hue**:

| Family | Owns | Where it lives |
|---|---|---|
| **Blue** | pace / intensity | `PaceSpectrum.swift` |
| **Warm** | mood | `DripColors` |
| **Accent** | alert, action, "look here" | `DripColors.coral` |

Pace reads as *depth*, never as a rainbow. Mood reads as *temperature*. The accent
is punctuation — roughly one accent element per visual cluster.

**This rule is currently violated.** See [Known issues](#known-issues).

---

## Surfaces

Measured against page paper `#FAFAF9`. L\* is CIE lightness. Hue angles are omitted here — at chroma ~1 they are noise.

| Token | Hex | Role | L* | vs paper |
|---|---|---|---|---|
| `background` | `#FAFAF9` | Page paper | 98.2 | 1.00:1 |
| `cardBackground` | `#FFFFFF` | Card | 100.0 | 1.04:1 |
| `cardBackgroundElevated` | `#FFFFFF` | Collapsed into card | 100.0 | 1.04:1 |
| `calendarBackground` | `#F0F0EE` | Calendar / inset well | 94.7 | 1.09:1 |
| `paperDeep` | `#F0F0EE` | Inset well, histogram track | 94.7 | 1.09:1 |
| `divider` | `#E6E7EA` | Hairline rule | 91.6 | 1.18:1 |

Cards separate from the page by 1.75 L\* — subtle but present, so cards still read
as cards without needing borders. Going to pure white would collapse that and force
a border on every card.

## Accent

| Token | Hex | Role | L* | LCh H | vs paper |
|---|---|---|---|---|---|
| `coral` | `#E63946` | Accent / alert | 52.1 | 27° | 3.99:1 |
| `coralLight` | `#F2616C` | Hover lift on dark | 60.4 | 22° | 3.00:1 |
| `coralDeep` | `#C42A36` | Press / hover | 43.7 | 28° | 5.39:1 |

`coralWash` — `rgba(230, 57, 70, 0.12)`. Capsule fill behind an active chip or a
niggle pill. Per the design system README this is *the only transparency in the system*.

> **The token is named `coral` but holds a scarlet.** Renaming it touches ~5,900
> callsites, so the rename is a separate mechanical pass. Don't be misled by the name.

## Ink

One ink at three dilutions — not three greys. The chroma carried down the ramp is
what makes type read as printing rather than as UI chrome.

| Token | Hex | Role | L* | LCh H | vs paper |
|---|---|---|---|---|---|
| `textPrimary` | `#0D1016` | Display + body | 4.6 | 274° | 18.23:1 |
| `textSecondary` | `#585D68` | Meta, labels | 39.4 | 275° | 6.32:1 |
| `textTertiary` | `#8F95A1` | Captions, disabled | 61.6 | 273° | 2.88:1 |

The ramp leans blue for two reasons: it opposes the scarlet accent, so scarlet reads
more scarlet; and it rhymes with `#0E1D4E`, the Mile end of the pace ramp already in
the palette. Warm ink belonged to the cream paper — on neutral paper it has nothing
to sit with.

`textTertiary` at 2.9:1 is below AA for body text. It is scoped to captions and
disabled states only. Do not use it for anything a person has to read.

## Moods

**Unchanged** — deliberately held while the accent moved. Last column is angular
distance from the accent; **bold** marks a collision.

| Token | Hex | Note | L* | LCh H | Δ from accent |
|---|---|---|---|---|---|
| `energized` | `#2D8A4E` | Deep green | 51.0 | 149° | 122° |
| `positive` | `#4A9E6B` | Sage | 58.9 | 153° | 126° |
| `neutral` | `#9B9590` | Warm gray | 62.1 | 70° | 42° |
| `tired` | `#C4873A` | Amber | 61.1 | 72° | 44° |
| `struggling` | `#C45A3A` | Terracotta | 51.1 | 44° | **16°** |
| `injured` | `#B83A4A` | Deep rose | 43.8 | 21° | **7°** |

`success` is an alias of `energized` (`#2D8A4E`).

## Pace ramp

**Unchanged.** Ten canonical zones, slow → fast, in `PaceSpectrum.swift`. A single-hue
blue depth ramp: dark = fast. Never recolour this to match a rebrand — the ordering
*is* the information.

| Zone | Hex | L* | LCh H | vs paper |
|---|---|---|---|---|
| Easy | `#93B9D6` | 73.4 | 252° | 1.98:1 |
| Moderate | `#74A8CC` | 66.6 | 252° | 2.45:1 |
| Steady | `#578FC0` | 57.5 | 262° | 3.30:1 |
| MP | `#3F7CB5` | 50.5 | 268° | 4.22:1 |
| HMP | `#2F66A8` | 42.7 | 277° | 5.61:1 |
| LT | `#27549B` | 36.2 | 283° | 7.11:1 |
| 10K | `#20448B` | 30.2 | 288° | 8.89:1 |
| 5K | `#1A3679` | 24.4 | 290° | 10.88:1 |
| 3K | `#142964` | 18.6 | 292° | 13.13:1 |
| Mile | `#0E1D4E` | 12.7 | 294° | 15.41:1 |

Two helpers:

- `easyText` `#5E93BE` — legibility-darkened Easy, for small text where the pale
  Easy blue would disappear.
- `paceFast` `#0E1D4E` — mirrors the Mile stop, for use outside the ramp.

The slow end is intentionally low-contrast: Easy at 2.07:1 is a *fill* colour, not a
text colour. It got slightly clearer moving from cream to off-white.

---

## Known issues

### 1. Scarlet collides with `struggling` — unresolved

```
scarlet     #E63946   LCh 27°   L* 52.1
struggling  #C45A3A   LCh 44°   L* 51.1     Δ 16° hue, Δ 1.0 L*
```

Sixteen degrees apart at effectively identical lightness. At pill size these are the
same colour, so on an entry carrying both a mood pill and a niggle chip the alert
stops reading as an alert. `injured` `#B83A4A` is 6° away but 8 L\* darker, so
lightness alone distinguishes it — hue contributes nothing.

There is no red that clears both: the moods were drawn to cover the emotional-warm
range, which is exactly where red lives. Every hue still reading as *red* sits in the
15°–50° corridor and both walls are occupied. Three ways out:

1. Nudge `struggling` cooler or darker — one value, smallest possible edit.
2. Separate by **form** instead of hue — alerts always solid, moods always wash.
3. Move the accent into the free 294°→21° arc, giving up red for rose/magenta.

### 2. Primary buttons fail contrast

`DripButton .primary` puts white 15pt Crimson Pro on the accent fill: **4.17:1**,
under the 4.5:1 minimum. Fix: point the primary fill at `coralDeep` `#C42A36` (5.63:1)
and leave scarlet everywhere else.

The **record button is fine** — its inner mark is a white *shape*, not text, and
shapes only need 3:1.

### 3. Accent-as-text is thin

Scarlet on paper is **3.99:1**, just under 4.5:1 for coloured links and labels.
`#E01C2B` — four points darker, same hue — reaches 4.60:1 and still reads scarlet.

---

## Divergence

| Token | iOS (live) | web `globals.css` | `colors_and_type.css` |
|---|---|---|---|
| paper | `#FAFAF9` | `#F5F3F0` | `#F5F3F0` |
| elevated | `#FFFFFF` | `#FAFAF8` | `#FAFAF8` |
| well | `#F0F0EE` | `#E8E4DF` | `#E8E4DF` |
| rule | `#E6E7EA` | `#E8E4E0` | `#E8E4E0` |
| accent | `#E63946` | `#D4592A` | `#D4592A` |
| accent light | `#F2616C` | `#E8764A` | `#E8764A` |
| accent deep | `#C42A36` | `#B84420` | `#B84420` |
| ink | `#0D1016` | `#1A1815` | `#1A1815` |
| ink-2 | `#585D68` | `#6B6560` | `#6B6560` |
| ink-3 | `#8F95A1` | `#9B9590` | `#9B9590` |

Moods and the pace ramp match across all three — only surfaces, accent, and ink drifted.
Thirteen values in two files closes it.

---

## Where things live

| What | File |
|---|---|
| iOS tokens | `RunningLog/RunningLog/App/DesignSystem.swift` |
| iOS pace ramp | `RunningLog/RunningLog/Workouts/PaceSpectrum.swift` |
| Web tokens | `web/src/app/globals.css` (`@theme` block) |
| Design-folder tokens | `design-system/colors_and_type.css` |
| Live comparison tool | `white-red-rebrand-prototype.html` |

### Token bypasses

Colours hardcoded past the tokens, which will not follow a palette change:

- **iOS** — ~62 across 14 files, mostly charts (`WorkoutReceiptCharts`,
  `TrendsSignalLanes`, `EffortChartView`).
- **Web** — ~250 across 21 files, mostly the coach dashboard.

Four were repointed at the tokens during this change: the nav bar background and
title colours in `RunningLogApp.swift`, and an ink literal in `ContentLibrarySidebar.swift`.
The rest still hold old values.

---

## Reverting

Backups of every file touched: `_to_delete/rebrand-backup-2026-08-21/`

| File | State |
|---|---|
| `DesignSystem.swift.bak` | original cream + coral |
| `DesignSystem.swift.brick.bak` | off-white + brick |
| `DesignSystem.swift.scarlet.bak` | scarlet, warm-neutral ink |
