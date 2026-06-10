# Periodization Phase Model — Archived Reference

**Status:** Archived May 2026. Not in active use. Preserved as v2 reference.

## Context

The phase model and volume math that powered `deterministic-builder.ts`
in the now-cut `generate-training-plan` edge function. This describes
the periodization shape any algorithmic plan generator would need to
re-implement.

## The four phases

Marathon training was broken into four phases, sized proportionally to
plan length so an 18-week plan and a 12-week plan get the same shape,
just compressed.

| Phase | % of plan | Purpose |
|---|---|---|
| 0 — Introductory | top ~11% (≈2 of 18 weeks) | Ramp from current mileage, no structured track work |
| 1 — Fundamental | next ~33% (≈6 of 18 weeks) | Build aerobic base, add general endurance + tempo |
| 2 — Specific | next ~45% (≈8 of 18 weeks) | MP work, race-specific intensities, peak volume |
| 3 — Peak/Taper/Race | final ~11% (≈2 of 18 weeks) | Sharpen, taper, race |

The boundary computation lived as percentage thresholds:

```
pct = weeksOut / totalWeeks

pct > 0.89  →  Phase 0
pct > 0.56  →  Phase 1
pct > 0.11  →  Phase 2
else         →  Phase 3
```

(`weeksOut` is the count of weeks remaining before race day, including
the current week.)

## Volume ramping

The deterministic builder computed weekly mileage as a smooth ramp from
the athlete's starting mileage to their peak, with a taper at the end.

### Peak mileage by race distance

```
Marathon       — current × 1.7, clamped 75–100 mpw
Half Marathon  — current × 1.5, clamped 55–85 mpw
10K            — current × 1.3, capped at 70 mpw
Other          — current × 1.2, capped at 60 mpw
```

These are conservative ramps. The clamping prevents both under-prescribing
to highly experienced runners and over-prescribing to athletes with
unrealistic peak targets.

### Weekly ramp

```
Phase 0 + early Phase 1 (pct > 0.56):
  Ramp from current_mileage → 85% of peak

Phase 2 (0.11 < pct ≤ 0.56):
  Ramp from 85% of peak → 100% of peak

Phase 3 (pct ≤ 0.11):
  Week 2 (taper week)        — 60% of peak
  Week 1 (race week)         — 35% of peak (includes race distance)
```

The ramp uses linear interpolation within each phase based on `pct`.

## Quality day allocation

Each week, three days were quality days. Day mileage as a percentage of
total weekly volume:

```
Long run     — 27% of weekly, capped at 24mi
Workout 1    — 17% of weekly  (e.g., Tuesday)
Workout 2    — 17% of weekly  (e.g., Thursday, the medium-long run)
Easy days    — absorb the remainder (39%)
```

So a 60-mpw week would allocate roughly:
- Long run: 16mi
- Tuesday workout: 10mi
- Thursday workout: 10mi
- Easy days: 24mi spread across remaining days

## Type rotation (variety within phase)

To avoid prescribing the same workout type week after week, the builder
rotated through workout categories per phase.

### Tuesday categories

```
Phase 0: progression → fartlek (alternating)
Phase 1: trackShort → fartlek → trackLong → progression (cycling)
Phase 2: fartlek → trackLong → tempo → fartlek (cycling)
Phase 3: tempo / trackLong (alternating peak), then trackShort (taper),
         then RSS_17 (4xMile @ 105%, race week sharpener)
```

### Saturday (long run) categories

```
Phase 0: easyLong / progressionLong (alternating)
Phase 1: easyLong → moderateLong → rseWork → progressionLong (cycling)
Phase 2: moderateLong → mpWork → progressionLong → mpContinuous (cycling)
Phase 3: mpWork (4 weeks out, peak MP) → mpWork (3 weeks out, lighter)
         → moderateLong (taper) → RACE
```

## The "hangover rule"

After a big MP Saturday (long run with substantial MP volume — > 14mi),
the following Tuesday workout was downgraded to a lighter fartlek session.

```
if prevSatMPVolume > 14:
  tuesday = pick from fartlek pool, capped at 10mi
```

This protected against accumulated fatigue when two big sessions stacked
in adjacent days (Saturday → Tuesday is a 3-day recovery).

## Easy day distribution

Within a week, the easy days were patterned around the long run:

- **Day after long run** — recovery, lighter than other easy days
  (≈4–6mi vs 7–8mi for normal easy days)
- **Day before strides slot** — easy + strides (one day per week)
- **Other easy days** — standard easy, 7–10mi in non-intro phases
- **Doubles** — optional, weekday-only, never in intro phase, only when
  weekly mileage demands it (4–5mi second sessions)

Easy day mileage was tuned by surplus/deficit passes — after the
deterministic builder placed quality days, any remaining mileage budget
got allocated across easy days with caps (recovery ≤ 8mi, normal ≤ 10mi).

## Race-distance modulations

The phase model applied to all distances but with adjusted Saturday
work:

| Distance | Saturday MP work shifts to |
|---|---|
| Marathon | RP_* (race pace alternations) |
| Half marathon | Mostly RSE_* (steady-state at HM pace ≈ 90% of MP) |
| 10K | Less long-run emphasis, more workout volume |
| 5K | Track-heavy, lower volume |

In practice the workout library was marathon-coded (the BE_* / GE_* /
RP_* codes are all referenced in marathon distances), so half/10K/5K
plans got marathon workouts adapted by mileage targets — not ideal,
flagged in the codebase audit as uneven race-distance support.

## Why this was archived

The phase model is sound coaching but baked into algorithmic plan
generation that v1 doesn't ship. Coaches build their own periodization
in the coach portal; the system doesn't need to know the difference
between Phase 1 and Phase 2.

If v2 revisits algorithmic generation, this is the periodization shape
to start from. See `outputs/workout-system-rebuild.md` for context.
