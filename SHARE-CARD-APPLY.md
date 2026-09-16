# The Drip Issue — a one-run magazine, posted

**Date:** 2026-08-21 · **Surface:** Workout detail (`HistoryDetailSheet`) → new modal
**Scope:** one new folder (`RunningLog/Share/`), one toolbar item, no schema change
**Prototype:** `share-card-composer-prototype.html` — open it first; every measurement below is taken from it

---

## Context

The app already draws every piece of this feature. `RouteMapView` renders the
GPS trace as a pace-coloured ink line with no basemap under it. `PaceSpectrum`
owns the colour-is-pace language. `PlateStrip`, `EditorialRule`, `CoachQuote`
and `StatCard` are the editorial furniture. What's missing is a surface that
arranges them at 1080 px and hands the result to the share sheet.

The reason to build it is not "runners like sharing runs." It's that **the
export is the only part of the product a non-user ever sees.** Every running app
posts a map with numbers on it, and they are indistinguishable from each other
because they all inherit the same basemap and the same system font.

**So this doesn't post cards. It posts a magazine.**

Each swipe is a *page*: a masthead and an issue number on the cover, a running
head and a folio on every page inside, a department name, a drop cap, two
justified columns, a figure caption under the chart, a pull quote over a byline.
That furniture is the point. It is what tells a stranger scrolling past that they
are looking at a different kind of object, and it is the part a competitor cannot
ship in a sprint, because copying it means owning a type system first.

**Outcome wanted:** in under thirty seconds after a run, the athlete produces a
three-to-five page issue that looks like it was printed, with their own sentence
on the cover, and posts it.

---

## Decisions taken

| Question | Decision |
|---|---|
| Where it lives | A **modal off the workout detail toolbar** — "Make an issue ↗". Not a tab. |
| Pages | **Cover · The numbers · Dispatch** on by default; **The ledger · The last word** available |
| Running order | **Fixed.** Pages can be added and dropped, never reordered. |
| Canvas | **4:5 (1080 × 1350)** and **9:16 (1080 × 1920)**, one segmented control |
| Theme | **Paper** (shipped tokens) and **Ink** (inverted), paper default |
| Accent budget | **One coral element per page**, plus the drip mark in the folio. Audited below. |
| The athlete's words | A prompt under the deck, **pre-filled from the run's memo**; lands on the cover *and* Dispatch |
| Body copy | Computed first, narrated second — the Ask pattern. Never free-generated. |
| Export | `ImageRenderer` at `scale = 3`, from the same SwiftUI views drawn on screen |
| Delivery | `ShareSheet` (already in `Shared/ExportView.swift`) with `[UIImage]` + caption string |
| Photos | `PhotosPicker` (already used in `SettingsView` / `ImportTrainingPlanSheet`) |
| Photo treatment | **Grayscale + slight warm sepia, always.** Not an option. |
| Persistence | **None in v1.** The issue is composed and thrown away. |

**Why the running order is fixed.** A magazine's running order is an editorial
decision, not a reader preference. The sequence — cover, the numbers, dispatch —
is the argument the issue makes: *here is the run, here is what it did, here is
what it felt like.* Every reordering produces a worse magazine, and a drag handle
would invite the athlete to find that out for themselves.

---

## The prompt — "what do you want to say about this run?"

The centre of the feature, not a nicety attached to it. A route trace and a
splits chart are facts; anyone's app has facts. The issue only becomes worth
posting when there is a sentence on the cover that a machine could not have
written.

**The block sits directly under the card deck, above the page tray** — visible
without scrolling, so it reads as part of composing rather than a step at the end.

```
YOUR WORDS                                    PULL FROM MEMO ↗
What do you want to say about this run?
Legs were bricks to the dam and then something let go. Last
three felt like falling downhill.
93 CHAR              ON THE COVER · THE DISPATCH · THE CAPTION
```

- **Eyebrow:** `YOUR WORDS` — mono 9 pt, tracked `.14em`, `textTertiary`.
- **Prompt:** Crimson Pro bold 15 pt, ink. Same register as the daily check-in.
- **Field:** PT Serif *italic* 12.5 pt — the athlete's words are always set in the
  diary voice, so what they type already looks like what will be printed.
  Placeholder: *"Say it the way you'd say it out loud."*
- **Underline** is a hairline that turns coral on focus.

**Voice note — one word changed.** The request was *"tell us what you want to say
about the workout."* The design system is explicit that the app never says "we"
or "us" — *"The app doesn't talk about itself."* So the prompt is **"What do you
want to say about this run?"** — same ask, second person, matching *"How are you
feeling?"* If you want the original wording it's a one-line change, but it will be
the only sentence in the product where the app refers to itself.

**Pre-fill, don't blank-page.** If the run has a voice memo or cleaned notes, the
field opens containing them and the athlete edits down. A blank field after a hard
long run is how this feature gets skipped. `PULL FROM MEMO ↗` re-fills it; hide the
button when there is no memo.

**Three destinations, one input:** the cover deck, the Dispatch pull quote, and
the caption string handed to the share sheet. Never ask twice.

---

## Magazine furniture

Build these once in `ShareCardCanvas.swift`; every page composes from them. **All
values are at 360 pt design width — the export is 1080 px, so multiply by 3.**

| Element | Spec | Where |
|---|---|---|
| **Masthead** | Crimson Pro 700, 31 pt (38 on story), uppercase, tracking `-.018em`, 1.5 pt ink rule under | cover only |
| **Issue line** | mono 7 pt, `.16em` — `NO. 143 · SATURDAY, JULY 11, 2026 · AUSTIN, TEXAS` | cover only |
| **Running head** | mono 7 pt, `.20em`, `textTertiary` — `POST RUN DRIP` left, `JULY 2026` right, hairline under | every inside page |
| **Folio** | mono 7 pt, `.18em` — department left, page number + drip mark right | every inside page |
| **Department head** | mono 8 pt `.16em` ink-2 left, sub-label `textTertiary` right | every inside page |
| **Drop cap** | Crimson Pro 700, 30 pt, `line-height .76`, floated, **coral** | The numbers |
| **Columns** | `column-count 2`, gutter 11 pt, hairline column rule, PT Serif 8.4 pt, justified, hyphens on | The numbers |
| **Figure caption** | PT Serif *italic* 8 pt, `textTertiary`; the `Fig. n` prefix in mono caps 7 pt ink-2 | under every chart |
| **Pull quote** | opening `"` in Crimson Pro 700 at 40 pt coral, hung left; text PT Serif italic 13.5 pt | Dispatch, The last word |
| **Byline** | mono 7.5 pt `.16em` — `BY MAYA REINA · AUSTIN, TEXAS` | Dispatch |
| **Ruled table** | 1 pt ink rule above and below the block, hairlines between rows, mono tabular | The ledger |
| **Colophon** | PT Serif 8 pt `textTertiary`, single column | The last word |
| **Drip mark** | 4 pt coral square, three rounded corners, rotated 45° — the drop off the logo's "p" | folio, cover foot |

**Two furniture rules that are easy to get wrong.**

*The cover carries no running head and no folio.* The masthead is the running
head, and magazines do not number their covers. Page numbering starts at 2 on the
first inside page.

*The masthead is a masthead, not the wordmark.* The real logo is a bold geometric
sans on three lines with the drip hanging off the "p", and it is the only place a
different typeface appears in the system. Setting it in Crimson Pro here is a
deliberate call — a magazine masthead, drawn in the magazine's own face. **Open
question for Rio:** if you'd rather the cover carry the actual lockup, place
`assets/PRD-Logo-On-Black.png` in an ink field at the head of the cover instead,
and the rest of the page is unchanged.

---

## The pages

### 1 · The cover

```
POST RUN DRIP                          masthead · 31 pt
════════════════════════════           1.5 pt ink rule
NO. 143 · SATURDAY, JULY 11, 2026 · AUSTIN, TEXAS

        ╭─────────╮
       ╱    ╭───╮  ╲                   the art — RouteMapView's INLINE treatment
      │    ╱     ╲  │                  no basemap, stroke 2.6, mile ticks as hairlines
       ╲  ╰───╯   ╱                    start = hollow ink ring · finish = coral dot
        ◉─────────╯
EASY ▬▬▬▬▬▬▬▬▬▬▬▬▬ MILE

THE LONG RUN · 14.99 MI · 78°F         kicker · mono 8 · ink-2
The last 3 miles were the fastest.     cover line · Crimson Pro 700 · 22 pt (28 story)
"Legs were bricks to the dam and…"     the deck — the athlete's own words, italic
INSIDE: THE NUMBERS · DISPATCH         story canvas only
───────────── · ─────────────
14.99 mi · 6:50 / mi · 1:42:32                                              ◗
```

**The art is the route, always — never the photograph.** The system's hardest rule
is *"no images as background, ever"*, so a cover cannot be type over a sunrise. The
art sits framed in a field of paper the way an essay cover works. The route earns
the slot because it is the one mark unique to this run; the photograph gets its own
page in Dispatch, where a caption can do it justice.

**Colour the route by the run's own pace range**, not the athlete's zone anchors —
`PaceSpectrum.color(forPaceSec:slowSec:fastSec:)`, not `anchoredColor`. On a single
cover the job is to show *this run's* shape, and a long run anchored to global zones
is fifteen miles of the same pale blue. This is the opposite of the call
`LONG-RUN-PACE-STRIP-APPLY.md` made, for the opposite reason: that surface compares
runs to each other, this one doesn't.

**The cover line is generated, and it is the one line that must never be wrong.**
Derive it from the split shape — negative split → *"The last 3 miles were the
fastest."*; even → *"Fifteen miles that never moved."*; fade → *"It got hard at
eleven."* Pick from a **closed set of templates filled with computed numbers.** Do
not hand this to a model. See "Body copy" below.

### 2 · The numbers

```
THE NUMBERS                        15 MILES · 6:50 AVERAGE
Slow open, fast close.             20 pt (26 story)

              ▁▃▅▆▆▇▆▇▆▅▄▆█▉      bars · faster = taller
AVG ┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈
   1 2 3 4 5 6 7 8 9 ...  14 15

Fig. 1 — Mile splits, seconds per mile; taller is faster. The dashed
line is the run's own average of 6:50. The final mile, 6:29, is the
day's fastest.
───────────── · ─────────────
┌T┐he first mile went out at │ than eight seconds either
│ │7:18, the slowest of the  │ side of it. The last three
└─┘day. From four to twelve  │ are the story: 6:47, then
the run sat on 6:50 and      │ 6:38, then 6:29 at the line.
never moved more             │
```

- Bar height is **inverted pace** normalised to `[fastest − 8s, slowest + 8s]`,
  floored at 16 % so no bar vanishes. Faster = taller is the only mapping a
  non-runner reads correctly at thumbnail size.
- **No bar is coral.** The ramp already encodes pace; colouring the fastest split
  coral says it twice, and this page's coral is the drop cap.
- A partial final mile still draws a full-width bar — its *pace* is the honest
  number, and shrinking it reads as "slow" to anyone who doesn't know the rule.
- **Story canvas adds** a second paragraph (heat-adjusted pace, dew point, the
  read) and the OPEN / STEADY / CLOSE callout row under a rule.

### 3 · Dispatch

```
DISPATCH                                  MILE 11 · THE DAM
┌──────────────────────────────────────┐
│                                      │  grayscale(1) contrast(1.06) sepia(.16)
└──────────────────────────────────────┘
Mile 11, the dam. The turn where the run changed.
───────────── · ─────────────
❝ Cooked by mile nine and got it back.
BY MAYA REINA · AUSTIN, TEXAS
▏A slow open and a fast close is the right shape…    ← story canvas only
14.99 MI · 6:50 /MI · 1:42:32                        ← feed canvas only
```

The grayscale is not a filter option, it's the brand: *"When imagery appears it is
black-and-white or desaturated warm tone, never the iPhone-colour-bright look."* A
full-colour sunrise here destroys the paper illusion instantly — the page stops
being a page and becomes a screenshot with a photo in it. Hold this line even when
it gets requested.

The coach note, on the story canvas, uses the **2 pt coral-at-50 % left bar** — the
one place the system allows a coloured left border, and the canonical `CoachQuote`
treatment. It is its own visual cluster, so its coral does not spend the page's.

With no photo picked, the page renders the empty frame on screen and is **excluded
from the export** rather than shipped empty.

### 4 · The ledger — *off by default*

```
THE LEDGER                                 THE RUN, PARSED
Three blocks.
BLOCK      DISTANCE          PACE     AVG HR
──────────────────────────────────────────────
OPEN       3 MI              7:05        152
STEADY     9 MI              6:50        161
CLOSE      3 MI              6:38        170
──────────────────────────────────────────────
Fig. 2 — Blocks are derived from the run's own splits, thirds by
distance. An interval session lists its reps here instead.
───────────── · ─────────────
6:50 /mi        6:30 /mi        HELD
AVERAGE         HEAT-ADJ        THE READ
```

Off by default on purpose. It is the most impressive page in the app and the least
legible in a feed — nine rep rows of monospace at 1080 px is a photograph of a
spreadsheet. On an interval day it earns its place and the athlete will turn it on.
**Cap it at 10 rows**; beyond that, merge to blocks.

### 5 · The last word — *off by default*

The coach note set as an essay pull quote, centred in the page, with the colophon
under a rule at the foot:

> *Set in Crimson Pro and PT Serif. Route drawn from the run's own trace, coloured
> by pace. Numbers computed before they were narrated. Printed after the run.*

The colophon is the closing joke and it is also true, which is why it can be
printed. It gives the coach voice a home for athletes who want it, and stays out of
the way for the ones who don't.

---

## Body copy

The drop-cap paragraph, the cover line and the figure caption are the only
generated prose in the feature, and they are the highest-risk thing in it: a wrong
number on a page the athlete posts publicly is worse than a wrong number anywhere
else in the product.

**Use the Ask architecture exactly as it stands.** Compute first, narrate second,
and run the output through `_shared/narration-guard.ts`: *if a number is not in
`facts`, it does not exist.* For v1, go further — **the paragraph is a template
filled from computed values, with no model call at all**:

```
The first mile went out at {split[0]}, the slowest of the day.
From {a} to {b} the run sat on {avg} and never moved more than
{spread} seconds either side of it. The last three are the story:
{split[-3]}, then {split[-2]}, then {split[-1]} at the line.
```

Three or four templates keyed on the split shape covers every run in the log. When
this later moves to a model, it is a golden family under hard rule #3 — athlete-
facing and safety-baitable — and needs recorded cassettes before it ships.

---

## Data model

One value type, assembled when the sheet opens. No new network calls: every field
already exists on the workout detail view model.

```swift
struct IssueData {
    // masthead
    let issueNo: Int              // the run's index in the athlete's log
    let dateLong: String          // "Saturday, July 11, 2026"
    let place: String             // "Austin, Texas"
    let month: String             // "July 2026"        — the running head
    let byline: String            // athlete display name

    // headline stats
    let distanceMi: Double
    let movingSeconds: Int
    let avgPaceSecPerMi: Double
    let heatAdjPaceSecPerMi: Double?
    let avgHr: Int?
    let maxHr: Int?
    let elevationFt: Int?
    let tempF: Double?
    let dewF: Double?
    let readLabel: String?        // "HELD" / "NEGATIVE SPLIT" / "FADED"

    // pages
    let route: [CLLocation]       // cleaned trace — same input RouteMapView takes
    let splits: [MileSplit]       // existing type, Health/HealthKitManager.swift
    let blocks: [LedgerRow]       // reps for interval runs, thirds for continuous
    var photo: UIImage?
    var photoCaption: String?
    var words: String             // the prompt's output
    let coachNote: String?

    // generated, from templates — never free text
    let coverLine: String
    let numbersHeadline: String
    let narration: String
}

struct LedgerRow {
    let label: String             // "OPEN" / "REP 3" / "6 × 1 MI"
    let distanceLabel: String     // "3 mi"
    let paceSecPerMi: Double
    let avgHr: Int?
}
```

`blocks` is the one field needing a branch. For an interval session it's the reps
`WorkoutRepChart` already computes off `WorkoutLapRow` (after `mergeWorkBouts`).
For a continuous run there are no reps, so **split the mile splits into thirds and
average each** — open / steady / close. A long run that went 7:05 / 6:50 / 6:38 is
a story; fifteen undifferentiated rows are not.

---

## Files

**New — `RunningLog/RunningLog/Share/`**

| File | Contains |
|---|---|
| `IssueData.swift` | the struct above + the `from(viewModel:)` assembler |
| `IssueCopy.swift` | the cover-line / headline / narration templates and their selectors |
| `IssueTheme.swift` | `enum IssueTheme { case paper, ink }` → colour set + pace ramp |
| `IssueFurniture.swift` | masthead, running head, folio, department head, drop cap, columns, figure caption, pull quote, byline, ruled table, drip mark |
| `IssuePages.swift` | the five pages |
| `IssueComposerView.swift` | the modal: deck, dots, words block, page tray, action bar |
| `IssueRenderer.swift` | `ImageRenderer` → `[UIImage]`, plus the caption string |

**Touched**

| File | Change |
|---|---|
| `Workouts/HistoryDetailSheet.swift` | one `ToolbarItem(.topBarTrailing)`: "Make an issue ↗" |
| `Workouts/PaceSpectrum.swift` | add `static func stops(for theme: IssueTheme) -> [Color]` |

Nothing else. If the diff reaches into the view models, something has gone wrong:
the composer reads, it does not compute.

---

## Themes

`IssueTheme.swift` returns a full colour set. Nothing else in the composer reads
`Color.drip.*` directly, so a rebrand — the white/red study in
`white-red-rebrand-prototype.html`, for instance — swaps one file.

| Token | Paper | Ink |
|---|---|---|
| surface | `#F5F3F0` | `#12100E` |
| card / well | `#FFFFFF` / `#E8E4DF` | `#1B1815` / `#0B0A09` |
| rule | `#E8E4E0` | `#2C2723` |
| ink / ink-2 / ink-3 | `#1A1815` / `#6B6560` / `#9B9590` | `#F4F1EC` / `#A29A91` / `#6F6862` |
| accent | `#D4592A` | `#E8764A` (the existing `coralLight`) |

**The pace ramp has to flip, and this is the one non-obvious decision in the
build.** The shipped ramp runs pale sky → navy: on warm paper, *deeper is faster*,
and `PaceSpectrum`'s own header explains why lightness carries the scale. On a
near-black page navy is invisible — the fastest miles would disappear, inverting
the meaning of the chart. So the ink ramp inverts the luminance: **dim slate for
easy, near-white sky for mile.** Same semantic — intensity — on the only axis a
black field has.

```swift
// PaceSpectrum.swift
static let inkStops: [Color] = [
    Color(hex: "3B5570"), Color(hex: "476781"), Color(hex: "547A93"),
    Color(hex: "628DA6"), Color(hex: "71A0B9"), Color(hex: "82B4CC"),
    Color(hex: "95C7DD"), Color(hex: "AAD8EB"), Color(hex: "C2E6F5"),
    Color(hex: "DCF1FC"),
]
static func stops(for theme: IssueTheme) -> [Color] {
    theme == .ink ? inkStops : stops
}
```

Check the ink ramp's Easy stop against the ink surface before shipping — the same
1.87:1 problem the header documents for paper applies here in reverse.

---

## The coral audit

The system allows *"one coral element per visual cluster, maximum."* On a page the
athlete posts, that budget is worth spending deliberately. Building this, three
elements per page wanted coral and two had to be given up each time:

| Page | Coral | Given up |
|---|---|---|
| Cover | the route's **finish marker** | the kicker, the masthead |
| The numbers | the **drop cap** | the department label, the fastest split's bar |
| Dispatch | the **pull-quote mark** (+ the coach bar, its own cluster) | the department label |
| The ledger | *none* | the department label, the fastest row |
| The last word | the **pull-quote mark** | the colophon |

Department labels fall to **ink-2 everywhere**. The fastest split's bar goes back
to the deep end of the ramp: the ramp already says "fastest", so coral there says
it twice. The drop cap keeps its coral because the design system names a coloured
capital as the reason coral exists — *"used the way italics or a coloured capital
is in a magazine: to point."*

The **drip mark in the folio does not count against the budget.** It is the
attribution, it is 4 pt, and it appears once per page.

---

## Export and delivery

```swift
@MainActor
func render(_ page: IssuePage, data: IssueData,
            theme: IssueTheme, canvas: IssueCanvas) -> UIImage? {
    let renderer = ImageRenderer(content:
        IssuePageView(page: page, data: data, theme: theme, canvas: canvas)
            .frame(width: canvas.width, height: canvas.height)   // 360 × 450 or 360 × 640
    )
    renderer.scale = 3                                            // → 1080 × 1350 / 1080 × 1920
    renderer.isOpaque = true
    return renderer.uiImage
}
```

- **The same view renders on screen and to PNG.** No second layout, no "export
  mode". This is the whole reason the page is built at 360 pt.
- `isOpaque = true` — a transparent PNG posts as a black rectangle on some clients
  and white on others.
- Render on tap of Share, not on every keystroke; five pages is roughly 150 ms.
- Hand the share sheet `images + [caption]`. iOS routes the string to the caption
  field on destinations that have one and drops it on the ones that don't.

**Caption format** — the athlete's words first, because that's the part a reader
stops for:

```
"Legs were bricks to the dam and then something let go."

14.99 mi · 6:50 / mi · 1:42:32
Austin, TX · 78°F · dew 72
```

Middle dots, lowercase units, numerals — the same rules as everywhere else. No
hashtags, no app URL. The masthead and the drip mark are the attribution.

---

## Degradation

The composer must compose for every run in the log, including the ugly ones.

| Missing | Behaviour |
|---|---|
| No GPS (treadmill, manual) | Cover keeps the masthead and stats; **the art slot collapses**, cover line and deck rise into it |
| No splits | The numbers page **hidden from the tray entirely** — not shown empty |
| No photo | Dispatch renders the empty frame on screen, **excluded from export** |
| No words | Cover deck omitted; Dispatch shows `YOUR WORDS GO HERE` on screen, **excluded from export** |
| No memo | `PULL FROM MEMO ↗` hidden, field opens empty with the placeholder |
| No coach note | The last word hidden from the tray; Dispatch's sidebar omitted |
| No HR / weather / elevation | The stat and the kicker segment drop; the row re-flows, **no `—` placeholders** (hard rule #8) |
| Fewer than 3 splits | Ledger falls back to a single `WHOLE RUN` row rather than fake thirds |

The tray never lets the athlete reach zero pages: the last enabled chip does not
respond to a tap. The cover is always available, because a masthead, a date and
three numbers are a magazine.

---

## Acceptance

1. Open a long run with GPS → toolbar shows **Make an issue ↗**.
2. Modal opens on the cover, three chips lit, words field pre-filled from the memo,
   paper + 4:5 selected.
3. Swipe; dots track; the tray adds and drops pages; **folio numbers renumber** and
   the cover's INSIDE line updates with them.
4. Type in the words field → the cover deck, the Dispatch pull quote and the
   caption preview all update live.
5. Toggle ink → every surface, rule, type tone **and the pace ramp** invert.
6. Toggle 9:16 → pages re-compose with the extra paragraph, callouts, INSIDE line
   and coach sidebar. **Not letterboxed.**
7. Share → N PNGs at exactly 1080 × 1350 (or 1080 × 1920), sRGB, opaque, plus the
   caption string.
8. Every number in the drop-cap paragraph appears in the splits array. Change the
   fixture's splits; the paragraph changes with them.
9. Open a treadmill run with no GPS and no splits → the issue opens with a cover
   and a dispatch, and it works.
10. Open a 200s session with 8 reps → The ledger, enabled, draws 8 rows and does
    not overflow the page.
11. Count the coral on every rendered page against the audit table. One each.
12. VoiceOver reads the composer's controls. The exported PNG is an image; that is
    a known and accepted floor.

---

## Not in v1, deliberately

- **No in-app feed.** This posts to Instagram, not to Post Run Drip. Building the
  network is a different product; building the export is a week.
- **No page reordering, templates, filters, stickers, or font choices.** The
  constraint is the product. Every option added is a way to make the issue look
  like everyone else's.
- **No model-written prose.** Templates filled from computed numbers. The whole
  point of the prompt is that the one human sentence is the athlete's; a generated
  one is the first thing a reader could smell.
- **No video or animated route draw.** The obvious v2, and it should wait until the
  still pages are right.
- **No saved issues.** Compose, share, discard. Add persistence when somebody asks
  for it twice.
