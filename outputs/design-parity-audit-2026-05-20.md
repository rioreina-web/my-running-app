# Design parity audit — Post Run Drip iOS

*2026-05-20. Six surfaces audited against `Post Run Drip Design System/ui_kits/ios_app/`
and the system foundations (`README.md`, `colors_and_type.css`).*

The user surfaced the gap: "the iOS app doesn't feel very different from the
old model." This audit unpacks why. Findings are scoped to **what ships in
the iOS app today**, not what `IMPLEMENTATIONS.md` claims ships.

---

## TL;DR — why it feels like the old model

Three structural reasons. Token + chrome reasons stack on top.

1. **The Today tab is gone.** `MainTabView` ships `Log (voice) / Training /
   Coach / Plan`. `TodayHomeView` and `TodayPlate18` are orphaned on disk.
   The most editorial surface in the design system isn't reachable by users.
2. **The plate strip — the spec's "single most identifiable visual gesture"
   — is missing everywhere except `CoachReadView`.** Today, Training,
   Workout Detail, Injuries, Sign-in all skip it.
3. **Every uppercase label in the app is set in PT Serif, not monospace.**
   `Font.dripCaption(_:)` uses `PTSerif-Regular`. The design system spec is
   explicit: *"Monospaced … every uppercase label, eyebrow, stat caption,
   plate strip."* This single token drift is doing the most damage — it
   removes the typewriter cadence that makes the brand legible.

The Today, Workout Detail, and Injuries surfaces are structurally close to
their plates; the rest of the gap is chrome and tokens. The Training tab is
its own thing, intentionally — not a parity issue but a spec drift to
acknowledge.

---

## P0 — Information architecture

### Today tab removed from the user-facing app

`RunningLog/App/RunningLogApp.swift:81-137` ships four tabs:
`Log (mic.fill) / Training / Coach / Plan`. The Today tab was deleted with
this comment:

> Today tab removed — Log is the new front door, since "AI-assisted
> training log" is the core job. TodayHomeView is still on disk if we want
> to reintroduce a daily-summary surface (e.g. as a sheet from the Log
> header, or a separate destination in the sidebar).

**Consequence.** `TodayHomeView.swift` and `TodayPlate18.swift` — the most
faithfully-redesigned surfaces in the entire app — are unreachable. The
canonical "May 5th." / coach quote / mood prompt / yesterday / tomorrow /
fitness / zone-shifts / race-predictions flow exists but no user can see
it.

This also means three docs are now out of sync:

- `CLAUDE.md` says `Today / Voice / Train / Coach` — Today no longer
  exists in code.
- `Post Run Drip Design System/ui_kits/ios_app/README.md` references a
  five-tab nav `LOG · TRAIN · TRENDS · COACH · RUNS` — Trends and Runs
  don't exist in iOS.
- `IMPLEMENTATIONS.md` maps `TodayScreen.jsx → App/TodayHomeView.swift +
  App/TodayPlate18.swift` with parity unverified — it doesn't note that
  the view is orphaned.

**Decision needed** before any pixel-level reshape:

- (a) Reintroduce a Today/Log tab that uses TodayHomeView, or
- (b) Fold the Today components (mood prompt, fitness trend, zone shifts,
  race predictions, journal entry, tomorrow's prescription) into a header
  of `VoiceLogView`, or
- (c) Move Today into a sidebar destination per the inline comment, and
  rewrite CLAUDE.md + the design system IA to match.

This is the call that drives every other reshape. **Do this first.**

### Decision (2026-05-21): sheet from Log header

A fourth option emerged once we read the structure of `VoiceLogView`:
the hero is intentionally sized to fill the viewport with the record
button, which makes (b) — fold into VoiceLogView — a non-starter. (a)
adds nav clutter and contradicts the recent "voice is the front door"
call. (c) hides editorial chrome behind a hamburger.

Chosen: **Today opens as a sheet via a `TODAY ↗` toolbar button** on
`VoiceLogView`'s nav bar. Today is reachable in one tap, doesn't take a
tab slot, doesn't displace the record button. The `MainTabView`
comment explicitly contemplated this. Implementation: `VoiceLogView`
adds `@State showToday` + a `topBarTrailing` toolbar item + a `.sheet`
modifier that presents `TodayHomeView()` inside a `NavigationStack`
with a Done button.

CLAUDE.md still says "Four-tab bottom nav: Today / Voice / Train /
Coach" — that documentation drift is a separate follow-up.

---

## P1 — Foundation drift (every surface is downstream of these)

### `Font.dripCaption(_:)` uses PT Serif instead of monospace

`RunningLog/App/DesignSystem.swift:107-109`:

```swift
static func dripCaption(_ size: CGFloat) -> Font {
    .custom("PTSerif-Regular", size: size)
}
```

The design system spec (`README.md`, *"Typography — three families, sharply
assigned"*):

> Monospaced (SF Mono on iOS / ui-monospace on web) — *every* uppercase
> label, eyebrow, stat caption, plate strip. Tracked +0.10em to +0.14em.

Effect: every section header in iOS rendered via `dripCaption` reads as
PT Serif uppercase — closer to a magazine subheading than the editorial
typewriter eyebrow the spec calls for. This is the single biggest reason
the app reads as "the old version."

Used in: `SectionHeader` (DesignSystem.swift:364), `TrainingTabView`
header (TrainingTabView.swift:85), `SignInView` toggle text and error
message (SignInView.swift:119, 130), every other inline call.

**Fix:** change `dripCaption` to `.system(size: size, weight: .medium,
design: .monospaced)` and audit every callsite for tracking values.

### No shared primitives — every surface rolls its own eyebrow

`Text(...).font(.system(size: 10, weight: .medium, design: .monospaced))
.tracking(N)` is repeated dozens of times across `TodayPlate18`,
`TrainingTabView`, `WorkoutDetailPlate23`, `InjuryPlate28`. Tracking
values drift across copies: `0.5`, `0.6`, `0.8`, `1.0`, `1.4`, `1.5`. The
spec says `0.10em` (caption) or `0.12em` (label). At 10px that's `1.0` or
`1.2` — half the call sites are wrong.

**Fix:** extract `Eyebrow`, `EyebrowCoral`, `PlateStrip`, `CoachQuote`,
and `EditorialRule` into `DesignSystem.swift` as canonical primitives.
`EditorialRule` is currently duplicated as four private structs (TodayHomeView,
TrainingTabView, WorkoutDetailPlate23 as `WD23EditorialRule`, InjuryPlate28
as `InjuryRule28`) — same line·dot·line shape, no shared source.

### MoodBadge violates "no emoji" rule

`DesignSystem.swift:182-208` renders moods with SF Symbol glyphs:
`face.smiling.fill`, `bolt.fill`, `bandage.fill`, `moon.fill`,
`exclamationmark.triangle.fill`. The spec:

> No emoji. (Mood is communicated through tracked uppercase pills + dot
> color, not faces.)

The badge text is also in PT Serif (`dripCaption(10)`) without tracking —
should be SF Mono with `+0.10em` tracking per spec.

**Fix:** replace icon with a 6px filled dot in the mood color; switch
label to monospace with proper tracking. Match `MoodPill` from
`ui_kits/ios_app/Primitives.jsx`.

### `Color.drip.electric` is the wrong name

`DesignSystem.swift:24`:

```swift
let electric = Color(hex: "B84420")          // Darker hover state
```

Value is right; the design system calls this `--coral-deep`. Rename to
match — "electric" sounds like a Stripe color, not the editorial system's
press-state coral.

### Spacing tokens don't exist

`DesignSystem.swift` has no spacing scale. Padding values are hardcoded
(`16`, `8`, `4`, `24`, `20`, `22`). The spec defines an 8pt grid:
`4 / 8 / 12 / 16 / 20 / 24 / 32 / 40 / 56`. iOS uses `20` and `22` in
places where the spec says `24`.

**Fix:** add `DripSpacing` enum or constants to `DesignSystem.swift`.

### `coralWash` is undefined as a token (used inline at `.opacity(0.12)`)

The spec has `--coral-wash: rgba(212, 89, 42, 0.12)`. `MoodBadge` uses
`moodColor.opacity(0.12)` inline. Fine in practice; not a problem to fix
yet — but if a future pass diverges this value, there's nothing to point
at.

---

## P2 — Per-surface findings

### Today — `TodayHomeView.swift` + `TodayPlate18.swift`

**Status: structurally close to spec, orphaned from app.** Section order
matches `TodayScreen.jsx` (header → coach → mood → editorial rule →
yesterday → tomorrow → editorial rule → fitness → zones → predictions).
Editorial rule is line·dot·line. Coral mood-bar in journal entry. Race
predictions strip.

Drift:

- **No PlateStrip** (`LOG · v1 DIARY + CHARTS` / `FIG. 18`).
- **Header has no italic-serif aside** (`— eleven weeks to the marathon. —`).
  TodayHomeView's date header is bare.
- **TUESDAY eyebrow is not coral.** Per `TodayScreen.jsx:12`,
  `<Eyebrow coral>TUESDAY</Eyebrow>` — Swift renders all eyebrows in
  `textSecondary`/`textTertiary`. Lose the coral and you lose the active-day
  signal.
- **Mood prompt is small dots in a row, not capsule radio pills.** JSX
  uses `<MoodRadio>` — uppercase tracked pills with dot. Swift uses
  18×18 outlined circles with tiny mono labels underneath. Different
  affordance.
- **Fitness trend chart not card-wrapped.** JSX wraps the chart in a
  white card with header strip and "12W AGO / NOW" axis labels. Swift
  renders bare on the paper background, no axis labels.
- **Hand-tracked values:** journal entry uses `.tracking(1.0)` on a 10px
  mono label (= 0.10em — fine for `caption`, but the day-date label should
  be at `0.12em` = 1.2 for `label` per spec).
- **Coach note rendering not verified** — `coachNoteSection` was not read in
  this audit pass. Confirm it uses `CoachQuote` (italic-serif + 2px
  coral-50% left bar) per spec, not a generic styled view.

### Training — `TrainingTabView.swift` (the one that ships)

**Status: not a parity drift — a deliberate spec drift.**
`TrainingDashboardView.swift` is dead code despite `IMPLEMENTATIONS.md`
pointing at it. The shipping view is `TrainingTabView`, which is its own
six-section design (header → pace zones × 10 → training load × ACWR →
daily intensity calendar → weekly load → pace analysis → load split). The
plate-6 design (`TrainingScreen.jsx`) is a five-section design (header
→ weekly mileage → coach's plan day strip → pace × volume × 5 buckets →
recent training log).

So the question for Training isn't *"does it match TrainingScreen.jsx?"* —
it's *"is the design system out of date, or is the iOS code out of date?"*

Drift if measured against `TrainingScreen.jsx`:

- **No PlateStrip** (`TRAINING · RE-TUNING` / `FIG. 6`).
- **No `Marathon block.` title.** iOS uses `TRAINING` (tertiary mono)
  → `Where you actually run.` (Crimson Pro 26) → `From your most recent
  fitness snapshot…`. The spec calls for week-of-block coral eyebrow →
  `Marathon block.` Crimson Pro display → goal/days-out line with `Edit ↗`.
  `Where you actually run.` is positioning-y copy, not editorial copy.
- **No COACH'S PLAN week strip.** The Mon→Sun day capsules with miles,
  type, and today highlighted in coral are absent.
- **No weekly mileage big numeral + 4-week mini-bars.** iOS has a
  `weeklyLoadSection` but the layout differs.
- **No pace × volume × 5 buckets visualization** (EASY/STEADY/THRESHOLD/
  VO2/RACE bars). iOS has a 10-zone expandable pace table — much more
  elaborate.
- **No recent training log feed with quote + mood pill.**
- **22px horizontal padding** instead of 24px (TrainingTabView.swift:71).
- **Header eyebrow uses `dripCaption(11).tracking(1.5)`** — PT Serif at
  1.5 tracking. Per token fix: should be mono with `~1.32` (= 0.12em at
  11px).

**Recommendation:** treat this as a strategy call, not a reshape task.
Either:

- Designate `TrainingTabView` as the new canonical design and supersede
  `TrainingScreen.jsx`/Plate 6 in the design system, or
- Reshape `TrainingTabView` toward Plate 6 (much heavier lift — would
  delete the ACWR section, the 28-day calendar, the 10-zone pace table,
  the load split).

The first option is cheaper. The second option is what the design system
currently implies should happen. Pick one and update the system docs.

### Workout Detail — `WorkoutDetailPlate23.swift` (chrome only)

**Status: editorial chrome ships, charts are unchanged.** The file's own
docstring is candid:

> the existing chart components — PaceChartCard, RouteMapCard,
> HeartRateGraphCard, mile splits — stay where they are; we just dress
> the framing around them down to match the rest of the trend-mockup
> voice.

So the header, stat strips, editorial rule, and weekly-context block are
all editorial. The middle of the screen (pace chart, HR chart, splits
table) is still pre-redesign.

Drift:

- **No PlateStrip** (`WORKOUT DETAIL · SHARPENED` / `FIG. 23`).
- **Two-stat top strip vs four-stat top strip.** JSX surfaces
  DISTANCE / DURATION / GAP / LOAD across the top. iOS surfaces only
  DISTANCE / DURATION, pushing pace into a secondary row. JSX also has a
  separate 5-cell secondary row (CADENCE / DRIFT / EF / HR AVG / WEEK)
  that iOS doesn't surface at all.
- **No combined PACE × HR overlay chart.** JSX shows pace and HR as two
  polylines on the same SVG with shared distance axis. iOS keeps two
  separate cards (PaceChartCard + HeartRateGraphCard) — not editorialized.
- **Splits table — fastest mile coral highlight not verified** (JSX uses
  `.fastest` CSS class with coral background; iOS implementation lives
  outside this file, in the legacy splits component).
- **HR ZONES bar treatment not verified** — JSX uses `<ZoneBar>` (a
  segmented bar with Z1/Z2/Z3/Z4 + minute counts). iOS has HR zone display
  somewhere in `VitalWorkoutCharts` — needs separate audit.

### Injuries — `InjuryPlate28.swift`

**Status: closest to spec of any surface.** Editorial header, severity
score in coral, 4-stat strip (MENTIONS / AVG VOL / AVG LOAD / TREND),
14-day mention dots, italic-serif quote, mono action links with middots.
Disclaimer rendered as quiet italic, not red banner.

Drift:

- **No PlateStrip** (`INJURY · LIVING LOG` / `FIG. 28`).
- **Severity score is `injury.severity / 10`, not `mentions / 10`.** JSX
  shows `4 / 10` derived from mention count. Swift shows self-reported
  severity. Product call — but if user-reported severity isn't authored
  for every injury, the score will be blank, while mention-count is
  always derivable. Spec implies mentions.
- **Stat label font sizes are 8px** (`size: 8, weight: .medium,
  design: .monospaced`). Smallest defined size in the system is
  `--t-meta-sm: 10px`. 8px is below spec floor.
- **Dot styling for mention dots not verified against the CSS.** Swift
  renders mentioned days as 6px coral and unmentioned as 2px tertiary.
  JSX uses `.d` and `.d.on` classes (defined in `_card.css`, not read in
  this pass). Plausible but unverified.
- **TrendLabel `easing` maps to coral.** Per the system's coral rule
  (*"one coral element per visual cluster, maximum"*), having both the
  severity score and the EASING trend in coral inside the same card
  violates the cluster rule. Pick one.

### Sign-in — `SignInView.swift`

**Status: drifts in voice and chrome.** Coral primary button, Apple sign-in,
warm-paper background — bones are right.

Drift:

- **No "Welcome back." display headline** (Crimson Pro, sentence-case).
  iOS goes straight from logo to email field.
- **No italic-serif tagline** (`— a quieter log for serious runners. —`).
- **Toggle copy `"no account? sign up"` is lowercase.** Spec says
  sentence-case headlines and body, with eyebrows uppercase. JSX uses
  `Create account` for the equivalent link. The lowercase / informal
  voice doesn't match anywhere else in the system.
- **Email/password input fields use 10px corner radius.** Spec says
  `--r-input: 8px`.
- **Apple sign-in button uses 12px corner radius.** Spec says
  `--r-button: 10px`. Inconsistent with the email button on the same screen.
- **Sign-in button uses `dripBody(15)` for label.** Spec says button labels
  are Crimson Pro semibold (`dripLabel`), not PT Serif body.

---

## Recommended reshape order

Sequenced by impact-per-effort. Each gate is a real decision point.

1. **Resolve the Today tab IA question.** Cheap if (b) or (c); costly if
   (a) — but everything else is downstream of where Today lives.
2. **Fix `Font.dripCaption(_:)` to monospace.** Single-token fix that
   propagates editorial cadence to every section header in the app.
   Re-walk every callsite after this to confirm nothing breaks visually.
3. **Extract canonical primitives in `DesignSystem.swift`:** `Eyebrow`,
   `EyebrowCoral`, `EditorialRule`, `PlateStrip`, `CoachQuote`,
   `DripSpacing`. Delete the duplicates in `TodayHomeView`,
   `TrainingTabView`, `WorkoutDetailPlate23`, `InjuryPlate28`.
4. **Fix `MoodBadge` to no-emoji + monospace + tracking.** High-visibility,
   low-effort win — mood pills appear across Today, Training log feed,
   journal entry. Today they read like fitness-tracker UI.
5. **Add PlateStrip to Today / Training / Workout Detail / Injuries.**
   The single most identifiable visual gesture per the spec. Should be
   one primitive accepting `surface` and `fig`, applied at the top of
   each editorial scroll.
6. **Resolve the Training spec drift (strategy call, not pixel work).**
   Either deprecate `TrainingScreen.jsx`/Plate 6 in favor of the
   richer `TrainingTabView` (cheaper), or reshape the iOS Training tab
   toward Plate 6 (more work).
7. **Per-surface chrome reshapes** (Today header italic aside, coral
   TUESDAY, mood radio capsules; Sign-in welcome + tagline + voice fix;
   Workout Detail combined pace×HR chart + 4-stat top strip; Injuries
   stat font sizes + mentions-as-score).
8. **`IMPLEMENTATIONS.md` refresh.** It points at `TrainingDashboardView`
   and doesn't note Today is orphaned. Update the map.

---

## Files referenced

- `Post Run Drip Design System/README.md` — voice + foundations spec
- `Post Run Drip Design System/colors_and_type.css` — token source of truth
- `Post Run Drip Design System/ui_kits/ios_app/{TodayScreen,TrainingScreen,WorkoutDetailScreen,InjuriesScreen,SignInScreen}.jsx`
- `Post Run Drip Design System/IMPLEMENTATIONS.md`
- `RunningLog/RunningLog/App/{DesignSystem,RunningLogApp,TodayHomeView,TodayPlate18}.swift`
- `RunningLog/RunningLog/Training/{TrainingTabView,TrainingDashboardView}.swift`
- `RunningLog/RunningLog/Workouts/WorkoutDetailPlate23.swift`
- `RunningLog/RunningLog/Analysis/InjuryPlate28.swift`
- `RunningLog/RunningLog/Auth/SignInView.swift`
