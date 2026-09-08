# Redesigning Post Run Drip without losing the app you have

Written 2026-08-21, before the wild redesign starts.

---

## 1. The safety net is already in place

Three things happened before this file was written:

| What | Why it matters |
|---|---|
| Every uncommitted file was committed (78 files, ~10,300 lines) | Uncommitted work is the **only** thing git cannot get back for you. It's now safe. |
| The current app was tagged `beta-v1-editorial` | A tag is a permanent bookmark. Branches move; tags never do. |
| A branch `design/wild-v2` was created | The redesign happens there. `design/log-detail-editorial` stays exactly as it is today. |

**One thing is still owed:** none of this is on GitHub yet. The push has to run from your own terminal (this session can't reach the network). Two commands:

```bash
cd ~/my-running-app
git push origin design/log-detail-editorial
git push origin --tags
git push -u origin design/wild-v2
```

Until you run those, the backup exists only on your laptop.

---

## 2. How to get back to today's app, forever

If the redesign goes wrong at any point, in any way:

```bash
cd ~/my-running-app
git checkout beta-v1-editorial
```

That is the whole recovery procedure. Your app comes back exactly as it is right now — every screen, every color, every feature. Nothing you do on `design/wild-v2` can touch it.

To go back to the redesign afterwards:

```bash
git checkout design/wild-v2
```

You can bounce between them as many times as you like. This is the single most important thing to understand: **in git, "losing progress" is almost always about uncommitted files, not about experiments.** Experiments are free.

---

## 3. Your app is unusually ready for this

This isn't flattery — these are counts from the codebase:

- **5,959** places reference a color through the design system (`.drip.textPrimary`, `.drip.coral`, …). Only **62** hardcode one — a 99% hit rate.
- **2,815** places reference a font through the design system (`.dripDisplay(28)`, `.dripBody(15)`, …).
- Both live in **one file**: `RunningLog/RunningLog/App/DesignSystem.swift`.

Meaning: a completely new palette and a completely new typeface can be applied to the entire app by editing roughly 60 lines in one file. Not 324 files. One.

Most apps at 145,000 lines are not in this position. Yours is.

---

## 4. The three layers, and what each one actually costs

A "wild redesign" is really three separate jobs with very different price tags. Don't treat them as one.

### Layer 1 — Color · **cheap, global, reversible in a minute**
Change the hex values in `DripColors`. Every screen changes at once. If you hate it, change them back.

### Layer 2 — Type · **cheap, global, one extra step**
Change the font-face names in the `Font` extension. The one extra step: a new typeface has to be dropped into `RunningLog/RunningLog/` and listed in `Info.plist` under `UIAppFonts` — the app currently ships Crimson Pro and PT Serif that way.

### Layer 3 — Layout · **the expensive one, and the only one that needs the parallel approach**
Layout is not centralized and can't be. It lives across 324 Swift files. A new home screen is a new home screen — there's no token to flip.

This is why you chose the parallel approach, and it's the right call. Layer 3 is where a redesign eats an app alive, because half-rebuilt screens don't compile and the app stops running while you're mid-thought.

---

## 5. The architecture: one switch, two skins

The goal is that **both designs exist in the app at the same time** and a single setting picks which one renders. That means the old app never breaks, you can flip between them live on your phone, and beta testers can be shown either.

### The switch

A new file, `App/DripTheme.swift`:

```swift
enum DripThemeID: String { case editorial, wild }

enum DripTheme {
    @AppStorage("dripTheme") static var id: DripThemeID = .editorial

    static var colors: DripColors { id == .wild ? .wild : .editorial }
    static var fonts:  DripFonts  { id == .wild ? .wild : .editorial }
}
```

### Colors — from one palette to two

`DripColors` currently hardcodes its values inline. It becomes a struct with two named instances:

```swift
struct DripColors {
    let background: Color
    let coral: Color
    let textPrimary: Color
    // …the same ~25 tokens, now supplied rather than baked in

    static let editorial = DripColors(   // today's app, untouched
        background:  Color(hex: "FAFAF9"),
        coral:       Color(hex: "E63946"),
        textPrimary: Color(hex: "0D1016")
    )

    static let wild = DripColors(        // the new one
        background:  Color(hex: "…"),
        coral:       Color(hex: "…"),
        textPrimary: Color(hex: "…")
    )
}

extension Color {
    static var drip: DripColors { DripTheme.colors }   // was: static let drip = DripColors()
}
```

That last line is the whole trick. All 5,959 callsites keep reading `.drip.coral` and never know anything changed.

> ⚠️ One real gotcha: the token is *named* `coral` but currently holds scarlet `#E63946`. Token names in this app describe **role**, not hue. Don't rename them during the redesign — a rename touches 5,959 lines and turns a safe change into a risky one. Let `coral` mean "the accent" and move on.

### Type — same pattern

```swift
struct DripFonts {
    let display: String, body: String, bodyItalic: String, label: String

    static let editorial = DripFonts(display: "CrimsonPro-Regular", body: "PTSerif-Regular", …)
    static let wild      = DripFonts(display: "…",                  body: "…",              …)
}

static func dripDisplay(_ size: CGFloat) -> Font {
    .custom(DripTheme.fonts.display, size: size).weight(.bold)
}
```

Note `dripStat` and `dripEyebrow` use the *system* monospace font rather than a bundled one. Between them that's **1,144** callsites — every number and every uppercase label in the app. They need an actual decision (keep SF Mono, or bundle a new mono), not a find-and-replace.

### Layout — new files, but far fewer than you'd think

Yes: a structural layout change means a second file. There is no token that turns one arrangement of boxes into a different arrangement.

But the number of duplicated files is **not** "every screen." It's bounded by how many screens' *bones* actually change. Three tiers, and only the third one duplicates:

**Tier 1 — same bones, new skin → zero new files.**
If a screen keeps its structure and just wears new colors and type, the token swap already did it. This will cover most of the app.

**Tier 2 — shared components → one file, two bodies.**
Don't duplicate these. Put the branch *inside* the component:

```swift
struct EditorialRule: View {
    var body: some View {
        if DripTheme.id == .wild { /* new mark */ } else { /* today's rule */ }
    }
}
```

One edit, and every callsite follows. Current usage counts — `EditorialRule` **57**, `EmptyStateView` **48**, `Hairline` **28**, `SectionHeader` **21**, `DripButton` **20**, `MoodBadge` **11**, `PlateStrip` **10**. Changing `EditorialRule` once restyles 57 places. Duplicating it 57 times would be the mistake.

**Tier 3 — genuinely different screens → two files.** This is where your instinct is right.

There are only six root screens:

| Screen | File | Lines |
|---|---|---|
| Log | `Workouts/VoiceLogView.swift` | 1,748 |
| Train | `Training/Analytics/TrainingTabView.swift` | 1,565 |
| Sheet | `App/SheetTabView.swift` | 776 |
| Week | `Week/WeekTabView.swift` | 756 |
| Trends | `Trends/TrendsTabView.swift` | 109 |
| Ask | `Analysis/AskTabView.swift` | 42 |

So the worst case is six duplicated files, not 324. And you almost certainly won't want all six rebuilt.

### Go finer than a whole tab

Trends and Ask are 109 and 42 lines because they're **thin shells that compose sections**. The real content lives in the section files below them. That means you rarely have to duplicate a 1,700-line screen — you duplicate the one *section* whose layout changed and leave the shell alone.

### You have already built this exact pattern

`TrendsTabView.swift` right now:

```swift
switch surface {
case .v1:    TrendsLegacyTabView(...)
case .block: TrendsBlockView(...)
}
```

Two completely different layouts of the same screen, both live in the app, chosen by a stored setting, with a door in the UI to flip between them. That *is* the redesign architecture. You invented it already to compare two Trends designs on device. The redesign just applies it at the app level with `DripTheme.id` instead of `surfaceRaw`.

### Where the app-level switch physically goes

`App/RunningLogApp.swift`, in the `ZStack` that mounts the tabs. Today:

```swift
NavigationStack { TrendsTabView() }
    .opacity(selectedTab == 4 ? 1 : 0)
```

Becomes:

```swift
NavigationStack {
    if DripTheme.id == .wild { TrendsTabViewWild() } else { TrendsTabView() }
}
.opacity(selectedTab == 4 ? 1 : 0)
```

One line per screen you rebuild. Screens you haven't reached yet keep rendering the old way, so the app never stops working.

### The payoff

Add a picker in `SettingsView` (Editorial / Wild). Now you can flip your whole app's identity on your phone, mid-run, and see the real thing with real data — not a mockup.

---

## 6. Order of operations

1. **Prototype in HTML first.** You already do this — `white-red-rebrand-prototype.html` is exactly the right instinct, and your `*-APPLY.md` → Swift workflow is the right pipeline. Iterating on color and type in a browser costs seconds; iterating in Xcode costs minutes. Settle the look *before* touching Swift.
2. **Build the switch** (`DripTheme.swift` + the two-instance refactor). Ship it with `wild` set to identical values to `editorial`. The app should look *completely unchanged*. That proves the plumbing works before any design decisions are riding on it.
3. **Fill in `DripColors.wild`.** Flip the setting. The entire app is recolored. This is the moment that feels like magic.
4. **Fill in `DripFonts.wild`** + bundle the typeface + add it to `Info.plist`.
5. **Rebuild layouts one screen at a time**, in priority order — Home first, since it's what beta users judge you on.
6. **Merge to main only when you're happy.** `design/wild-v2` can live for months.

---

## 7. Four rules that keep you safe

1. **Commit at the end of every session.** Even messy. `git commit -am "wip"` is always better than nothing. Uncommitted work is the only work git can't rescue.
2. **Tag anything you might want back.** `git tag -a name -m "why"`. Tags are free and permanent.
3. **Never edit an old screen file during the redesign — add a new one.** Files you don't touch can't break.
4. **Push to GitHub regularly.** A laptop is not a backup.

---

## 8. Building for the future

You said you want the beta to be able to grow into a real product. The theme switch is not just a redesign tool — it's permanent infrastructure you'll keep using:

- Dark mode is the same mechanism with a third `DripColors` instance.
- Seasonal or race-day skins, same thing.
- A/B testing two identities on real beta users, same thing.
- And the discipline it enforces — *never hardcode a color, always use a token* — is the single habit that keeps a design system from rotting as the app grows.

You already have that discipline. Across 324 Swift files there are **5,959** tokenized color references and only **62** hardcoded ones — a 99% hit rate. That is the reason this redesign is a one-file job instead of a three-month rewrite. Keep it.
