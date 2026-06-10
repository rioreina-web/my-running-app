# Why iOS ↔ design parity is so hard — and what's missing

*2026-05-20. Read after `design-parity-audit-2026-05-20.md` (what's drifted)
and `design-system-audit-2026-05-20.md` (the system-level gaps). This one
answers a different question: not what's wrong, but why translation keeps
producing drift in the first place.*

I now have the full design system folder (`/Users/rioreina/Downloads/Post Run Drip Design System/`)
and have compared every JSX screen to its Swift counterpart. The problem
isn't that the iOS engineers don't care about the spec. The problem is
that the spec, as delivered, is structurally hostile to faithful
translation into SwiftUI. Here's why.

---

## The size mismatch tells the story

| Surface | JSX (design) | Swift (code) | Ratio |
|---------|--------------|--------------|-------|
| Today           | 129 lines (TodayScreen.jsx)        | 1,414 lines (TodayPlate18 + TodayHomeView) | 11× |
| Training        | 126 lines (TrainingScreen.jsx)     | 991 lines (TrainingTabView) | 8× |
| Workout detail  | 146 lines (WorkoutDetailScreen.jsx)| 267 lines (WorkoutDetailPlate23) | 2× |
| Injuries        | 84 lines (InjuriesScreen.jsx)      | 254 lines (InjuryPlate28) | 3× |
| Sign-in         | 63 lines (SignInScreen.jsx)        | 249 lines (SignInView) | 4× |

The JSX files are **pure layout** — what goes on the page, in what order,
with what tokens. Today is 129 lines and you can read what the screen
is in under a minute. The Swift Today is **1,414 lines** because it
also contains Supabase queries, Decodable structs, async data fetchers,
date formatters, fallback logic, and error handling — all interleaved
with the view code. Lines 23–200 of `TodayPlate18.swift` are pure
data-layer before any view code appears.

**Consequence:** the engineer can't read the design intent off the
Swift file, and the designer can't see the data layer in the JSX file.
Every translation has to walk the JSX, identify the design intent,
re-implement it inside a Swift file that also runs the database. Drift
compounds at every step.

---

## What's actually missing from the design system

The system has good foundations (`colors_and_type.css` is tight,
the README's voice is clear). But the iOS UI kit is missing five
specific things that, if added, would make parity tractable.

### 1. Half the JSX vocabulary doesn't exist as a Swift primitive

| JSX primitive | Swift equivalent? | What happens today |
|---------------|-------------------|--------------------|
| `<Eyebrow>` / `<Eyebrow coral>` | **Missing** | Every section header reinvents `Text("X").font(...).tracking(N)`. Tracking values drift across copies (`0.5`, `0.6`, `0.8`, `1.0`, `1.3`, `1.4`, `1.5`). |
| `<Section eyebrow="X">` (eyebrow + body wrapper) | **Missing** | Each section is hand-built as a VStack with the eyebrow code inlined. No shared inter-section spacing. |
| `<MoodRadio>` (today check-in cluster) | **Missing** | TodayHomeView invented its own — 18×18 outlined circles with labels underneath. JSX uses 14px circles with coral-fill active state. Different affordance. |
| `<MoodPill>` | `MoodBadge` (drifts) | Swift `MoodBadge` ships SF Symbol icons (`bolt.fill`, `bandage.fill`). The spec explicitly bans emoji-equivalent glyphs in mood. |
| `<StatTile>` (label / value / unit / delta) | `StatCard` (different shape) | Different API, different padding, no `delta` slot. |
| `<TabBar>` (coral dot active, mono tracked labels) | Native `TabView` | iOS uses native chrome — coral tint only. No coral dot, no mono labels. |
| `<CoachQuote>` | `CoachQuote` ✓ | Parity. Good. |
| `<PlateStrip>` | `PlateStrip` ✓ | Defined, but **only one of six surfaces calls it** (`CoachReadView`). |
| `<EditorialRule>` | `EditorialRule` ✓ | Recently consolidated from four private duplicates. Good. |
| `<LineChart>` (inline mini-chart for fitness trend) | **Missing** | Today fitness chart uses an unstyled chart card; no axis labels, no card chrome. |
| `<ZoneBar>` (HR-zone segmented bar) | **Missing** | Workout Detail uses the pre-redesign `VitalWorkoutCharts` zone display. |
| `<RaceStrip>` (5-cell predictions row) | **Missing** | Today reinvents it inline. |
| `<WeekStrip>` (Mon–Sun day capsules, today in coral) | **Missing** | Training has a different weekly section. The COACH'S PLAN day strip from the spec is just absent. |

About 60% of the JSX primitive vocabulary has no Swift equivalent. The
other 40% either drifts (`MoodBadge`) or is defined but underused
(`PlateStrip`).

### 2. The JSX hides "components" inside inline styles

Half the patterns in the JSX aren't components — they're inline-style
soup that *looks* like a component. Example from TodayScreen.jsx line 26:

```jsx
<span style={{
  fontFamily: "var(--font-mono)", fontSize: 10,
  color: "var(--ink-3)", letterSpacing: "0.10em",
  textTransform: "uppercase"
}}>2 days ago</span>
```

That's clearly an Eyebrow — but it isn't called `<Eyebrow>`. So the
Swift engineer translating this surface sees raw style props and types
`.font(.system(size: 10, ...)).tracking(1.0)` inline. Next section
they see slightly different style props (`fontSize: 9`,
`letterSpacing: "0.08em"`) and type it again, slightly differently.
After six sections you have six near-identical "eyebrows" with
different tracking. That's **exactly** the pattern we see in iOS
today.

**Fix:** factor every inline style block in the JSX into a named
primitive (`<Eyebrow>`, `<MetaTimestamp>`, `<StatLabel>`, etc.).
If it appears twice, it's a component. If the JSX doesn't name it,
Swift will invent its own.

### 3. tokens.css has layout primitives the Swift side never received

`tokens.css` defines: `.race-strip`, `.wkstrip` (week strip), `.injury`,
`.injury-stats`, `.dot-line`, `.step` (workout step rows), `.splits`
(splits table), `.signin-shell`. These aren't components in the JSX —
they're pure layout patterns (grid column counts, gap values, padding,
dividers) baked into CSS class names.

Swift has none of these as primitives. So `WorkoutDetailPlate23` has
to re-derive what a "splits row" is by reading the CSS class
(which Swift implementers may or may not have looked at) or by
guessing from the JSX render. That's where the off-grid spacing
comes from — `.race-strip` uses `padding-top: 12px`, the Swift
implementer chose 14, and there's no token to point at saying which
is right.

**Fix:** every CSS layout class in `tokens.css` needs a Swift
counterpart in `DesignSystem.swift` — either as a primitive view, or
as a documented "this is a `HStack(spacing: 12) { ... }.padding(.top, 12)`"
pattern in a comment.

### 4. The JSX shows only the happy path — no empty / loading / error / overflow

Every screen in `ui_kits/ios_app/` is a single mock snapshot with
hardcoded mock data. There's no:

- Empty state (what does Today look like if there are zero runs logged?)
- Loading state (what does the fitness chart show while the trend query runs?)
- Error state (what does the race-predictions strip show if the
  predictor fails?)
- Overflow state (what does the coach quote look like if it's 300 words?)
- First-week state (what does week 1 of a marathon block look like
  before any workouts exist?)

The spec acknowledges this in one sentence — *"Empty states state the
absence then say what fills it"* — and points at
`docs/conventions/empty-states.md`. That doc exists, has 6 copy rules,
and is excellent. But it's **copy guidance only** — no visual mock,
no per-surface placement, no JSX example. So Swift implementers
either:

- Skip the empty state and ship `Text("—")` (4 places in iOS, see
  CLAUDE.md hard rule #8), or
- Invent their own treatment that drifts from web's `EmptyState`
  component.

**Fix:** every screen in `ui_kits/ios_app/` ships in 3 variants —
`default.jsx`, `empty.jsx`, `error.jsx`. Even if `error.jsx` is just
the screen with one section in the error state. Mock the absence.

### 5. The IA in the design system disagrees with the IA in the code

The ios_app README says the tab bar is `LOG · TRAIN · TRENDS · COACH · RUNS`
(5 tabs). The Swift app ships `Log / Training / Coach / Plan` (4 tabs).
Trends and Runs **don't exist** on iOS. Today tab was removed and
folded into Log. So the design system itself is referencing screens
that don't exist in code.

This puts the iOS engineer in an impossible position: "Follow the
design system" = "build two tabs that don't exist and remove one
that does."

**Fix:** before any pixel-level reshape work, reconcile the IA. Either:
- Update the design system README + TabBar to match the 4-tab reality (`LOG · TRAINING · COACH · PLAN`), or
- Build Trends and Runs as their own JSX screens with explicit IA, and add them to `ui_kits/ios_app/`.

The May 20 parity audit flagged this as P0 ("Resolve the Today tab IA
question"). It's still unresolved.

---

## Other structural cracks

### IMPLEMENTATIONS.md isn't a parity tracker — it's a TODO list

Every row in the "Parity verified?" column is `—`. The doc is honest
about it: *"none of the ui_kit ↔ iOS pairs above have been visually
verified."* Without verification, there is no feedback loop from
"design exists" → "code matches" → "system is healthy." Everything
is in the "in flight" state forever.

**Fix:** for each row, set a single human reviewer to do a side-by-side
in two hours (open `index.html` next to the iOS sim). Mark it yes/no
with a one-line note. That's it.

### The design system isn't in the repo

`Post Run Drip Design System/` is in `~/Downloads`, not in the codebase.
Yesterday's parity audit referenced it by path; today's audit confirmed
it's a separate folder. CLAUDE.md doesn't mention it. So new engineers,
new contributors, AI assistants — none of them see it unless someone
hands it over.

**Fix:** check it into `/Users/rioreina/my-running-app/design-system/`
(or wherever). Add CLAUDE.md entries pointing at the JSX screens for
each Swift surface. Stop the "design system as a moving target outside
the repo" pattern.

### The JSX targets web, the implementation targets SwiftUI

The JSX uses CSS variables, flexbox grids, inline-style objects — patterns
that don't translate 1:1 to SwiftUI. `display: grid; grid-template-columns: repeat(5, 1fr)`
becomes `HStack { ForEach(...) }` with `.frame(maxWidth: .infinity)` on
each child. `box-shadow: 0 2px 8px rgba(0,0,0,0.06)` becomes
`.shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)`.
Every translation requires a creative judgment call.

**Fix (if appetite):** for the canonical primitives, ship a `Primitives.swift`
file alongside `Primitives.jsx` in `ui_kits/ios_app/`. One file, the SwiftUI
implementation of each `<Eyebrow>` / `<Section>` / `<MoodPill>` / etc.
Then the engineer copy-pastes instead of translating. (This is a real
ask of design work — but it pays back the first time it's used.)

### Coach surfaces have three implementations and no canonical JSX

CLAUDE.md flags it; IMPLEMENTATIONS.md flags it ("`Coach iOS.html`
(Direction A · The Read) — **missing from this folder**"). The Coach
surfaces have shipped on iOS (`Coaching/Read/CoachReadView.swift` + 9
other files) without ever having a JSX reference. Built from prompts
docs only. That's how `outputs/coach-read-design-drift.md` gets to
exist as a separate doc.

---

## The minimal fix path

If this audit had to pick three things to do this week, they would be:

1. **Move `Post Run Drip Design System/` into the repo.** Half a day.
   Stops the "moving target outside the codebase" problem dead.

2. **Extract every inline-style block in the JSX into a named primitive,
   then write a matching `Primitives.swift`.** One day per platform.
   Specifically: `Eyebrow`, `EyebrowCoral`, `Section`, `MoodRadio`,
   `MoodPill` (replaces `MoodBadge`), `RaceStrip`, `WeekStrip`,
   `StatTile` (replaces `StatCard`), `LineChartMini`, `ZoneBar`.
   After this, Today drops from ~1,400 lines to maybe ~600.

3. **Reconcile the IA.** One meeting. Decide: 4 tabs or 5 tabs, does
   Today exist as a tab, where do Trends and Runs go. Update both the
   design system README and CLAUDE.md to match. Without this, every
   surface-level fix is built on disputed ground.

Everything else in the parity audit is downstream of these three.

---

## Files referenced

- `Post Run Drip Design System/README.md` — voice + foundations spec
- `Post Run Drip Design System/colors_and_type.css` — token source of truth
- `Post Run Drip Design System/IMPLEMENTATIONS.md` — design ↔ code map (parity column empty)
- `Post Run Drip Design System/ui_kits/ios_app/README.md` — UI kit map (5-tab IA, contradicts code)
- `Post Run Drip Design System/ui_kits/ios_app/Primitives.jsx` — 12 named primitives, 145 lines
- `Post Run Drip Design System/ui_kits/ios_app/tokens.css` — layout patterns as CSS classes
- `Post Run Drip Design System/ui_kits/ios_app/{TodayScreen,TrainingScreen,WorkoutDetailScreen,InjuriesScreen,SignInScreen}.jsx`
- `RunningLog/RunningLog/App/{DesignSystem,TodayPlate18,TodayHomeView,RunningLogApp}.swift`
- `outputs/design-parity-audit-2026-05-20.md` — per-surface iOS drift (the *what*)
- `outputs/design-system-audit-2026-05-20.md` — system-level token + primitive gaps (the *where*)
- This doc — translation friction (the *why*)
