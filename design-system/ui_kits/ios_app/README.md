# Post Run Drip · iOS UI kit

A pixel-faithful recreation of the Post Run Drip iOS app — the "Plate 18" diary+cockpit direction documented in `my-running-app/design/`.

**This is a UI kit, not a production app.** Buttons fire, tabs switch, sheets open and close, but data is static. The job is to faithfully reproduce the visual language so designs that bolt onto it look correct.

## Run it

Open [`index.html`](./index.html) — a single-file static prototype that mounts the whole app inside an iOS device frame.

## Screens (in nav order)

| Tab / sheet | Source plate | Component | Notes |
|---|---|---|---|
| **Log** (Today)         | Plate 18, 17 | [`TodayScreen.jsx`](./TodayScreen.jsx) | Diary spine top half, cockpit bottom half. Coach blockquote, mood check-in, yesterday/tomorrow, fitness line, zone shifts, race predictions. |
| **Train**               | Plate 6, 7   | [`TrainingScreen.jsx`](./TrainingScreen.jsx) | Marathon block summary, week strip with today highlighted in coral, pace × volume bars, recent training log. |
| **Trends**              | Plate 1      | (inline in App.jsx · `TrendsPlaceholder`) | The "5-second view" — four stat tiles, 12-week fitness line, weekly volume × ACWR bars. Has links into the Workout-detail and Injuries sheets. |
| **Coach**               | (extrapolated from coach voice docs) | (inline in App.jsx · `CoachPlaceholder`) | A two-turn coach conversation. Coach copy is the canonical blockquote treatment. |
| **Runs** (History)      | (extrapolated) | (inline in App.jsx · `RunsPlaceholder`) | All-runs index. Tapping May 7 opens Workout detail. |
| **Workout detail**      | Plate 23     | [`WorkoutDetailScreen.jsx`](./WorkoutDetailScreen.jsx) | "Pace, narrated." Stat strip, pace × HR overlay, splits table with fastest mile in coral, HR-zone bar, weekly context. |
| **Injuries**            | Plate 28     | [`InjuriesScreen.jsx`](./InjuriesScreen.jsx) | "Active aches" — knee + Achilles cards with 14-day mention dots. |
| **Sign-in** (gated)     | iOS `SignInView.swift` | [`SignInScreen.jsx`](./SignInScreen.jsx) | Email + Apple sign-in. App starts past sign-in; click "Sign in" to enter. |

## Components

The shared primitives are factored out into [`Primitives.jsx`](./Primitives.jsx). Each is exposed on `window` for cross-file use:

- `PlateStrip` — top mono header (`RUNNING LOG · …` / `FIG. N · NEGATIVE SPLITS · 04.2026`)
- `Eyebrow`, `eyebrow--coral` — tracked uppercase section labels
- `EditorialRule` — `line · dot · line` divider
- `Hairline` — 1px rule
- `MoodPill`, `MoodRadio` — tracked capsules, with the 7-mood palette
- `StatTile` — white card numeral tile (the cockpit fundamental)
- `Section` — eyebrow + optional right-aligned eyebrow + children
- `TabBar` — 5-tab footer, coral dot on active
- `CoachQuote` — italic blockquote with the 2px coral left-bar (the *one* place coloured left-borders appear in the system)
- `LineChart`, `ZoneBar` — tiny inline SVG primitives for the cockpit charts
- `Toggle` — coral pill toggle

## Voice notes

- All headlines end in a period: `May 5th.`, `Marathon block.`, `Active aches.`
- All separators are middle-dot `·`. Never `|` or `/` between fields.
- All UPPERCASE labels are monospaced and tracked at +0.10em to +0.14em.
- Coach copy is in 2nd person, in italics, inside the coral-bar blockquote.
- Empty states state the absence then say what fills it.

## Caveats

- Icons substituted from Lucide (the iOS app uses Apple SF Symbols natively).
- `Trends`, `Coach`, `Runs` tabs are reasonable extrapolations — the codebase has equivalents (`TrendsView`, `CoachTabView`, `HistoryView`) but the canonical Plate is only documented for the Today / Training / Workout / Injuries surfaces. They use only system-validated primitives.
- The status bar / device chrome comes from the shared `ios-frame.jsx` starter; it's iOS 26-style.
