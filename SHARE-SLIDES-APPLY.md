# The story composer — a voice memo becomes the type

**Date:** 2026-08-21 · **Surface:** Workout detail → new two-step modal
**Scope:** one new folder (`RunningLog/Share/`), one new field on an existing edge function, one toolbar item, no schema migration
**Prototype:** `share-slides-prototype.html` — open it first; fonts and logo are embedded, it works offline
**Supersedes:** `SHARE-CARD-APPLY.md` (warm-paper era). Kept for the pace-ramp and coral-budget reasoning; everything else here replaces it.

---

## Context

Two things changed the shape of this feature.

**One:** the system moved. Direction I — white stock, `#EE2B24`, Instrument Sans display, Schibsted labels, Inter numerals, JetBrains Mono transcripts, hairlines instead of cards, no shadows, near-zero radii. The earlier warm-paper share cards are retired.

**Two, and this is the real one:** Direction I's copy rules say the interface may not write a feeling. *"A headline names the session. It never editorialises it."* *"The interface supplies the facts; the athlete supplies the feeling, in their own transcribed words."*

That reads like a constraint. It's actually the feature. It means the emotional content of a share slide **cannot** be generated — it has to come out of the athlete's mouth. And the athlete is already talking: `upload-voice-memo` → `process-training-memo` runs on most logged runs today.

So: the memo becomes the type. Forty seconds of rambling contains four or five phrases that are better than anything a template could produce, because nobody writes *legs were absolute bricks* on purpose. The composer's whole job is to find them, show them, and let the athlete put one on each slide.

**Outcome wanted:** talk for forty seconds after a run, tap three phrases, flip through the result, post it — and the post is unmistakably yours, because the words in it are.

---

## Decisions taken

| Question | Decision |
|---|---|
| System | **Direction I.** White, red, Instrument Sans / Schibsted / Inter / Crimson / JetBrains Mono. No dark theme — the photo slide is the dark one. |
| Shape | **Two steps.** 1 · the memo (pull phrases) → 2 · the story (flip, arrange, share). |
| Slides | **Cover · On the photo · On the route** on by default; **The splits · The workout** available |
| Canvas | **4:5 (1080 × 1350)** portrait and **9:16 (1080 × 1920)** story, one control, both always available |
| Phrase source | **Verbatim spans of the transcript only.** Never paraphrase, never a numeral. |
| Phrase placement | **The athlete taps.** Nothing auto-inserts. One phrase lives on one slide. |
| Phrase face | **JetBrains Mono 400 italic** — italic mono is the athlete. Display-italic alternative is in the prototype's rail; pick by eye. |
| Headlines | Factual only. `15 miles, long run.` |
| Logo | **Stacked wordmark on the cover**, `logo-drip.png` on every slide after it |
| Pace colour | The **zone ramp**, anchored to the athlete's marathon pace, interpolated between zone centres |
| Export | `ImageRenderer` at `scale = 3` from the same views drawn on screen |
| Persistence | The pulled phrases persist on the run. The composed story does not. |

---

## 1 · The memo step

```
┌─────────────────────────────────────────┐
│ Back          Your memo         Next ↗  │
├─────────────────────────────────────────┤
│ ══════════════════════════════════════  │  2px ink rule
│ SAT 11 JUL              15 MILES · LONG │  mono 9.5 · .20em
│                                         │
│ ▁▃▅▇▅▃▁▂▅█▆▄▂▁▃▅▇▅▃▂▄▆█▅▃▂▁▃▅▆▄▂▁▂▄  │  waveform · bars under a
│ 0:00        TRANSCRIBED           0:47  │  pulled phrase go red
│                                         │
│ "okay so that was fifteen miles out and │  JetBrains Mono ITALIC 12.5
│  back on the lake loop. legs were       │  pulled spans get --red-wash
│  absolute bricks getting to the dam…"   │
│ ─────────────────────────────────────── │
│ PULL A PHRASE               2 OF 6 PULLED
│ ☑ legs were absolute bricks    → ROUTE  │
│ ☐ thinking about turning around   0:15  │
│ ☐ something just let go           0:24  │
│ ☑ felt like falling downhill   → PHOTO  │
│ ☐ hot as hell though              0:39  │
│ ☐ i was cooked by the end         0:42  │
├─────────────────────────────────────────┤
│ Landing on: THE ROUTE   [ SET THE TYPE ]│
└─────────────────────────────────────────┘
```

The transcript is set in **italic mono** because that is what the system says the athlete's voice looks like. It is the same face the phrase will be printed in on the slide, so what the athlete reads here is what they will see published — no surprise at the end.

`Landing on:` names the slide currently showing in step 2. That is the whole interaction model: **the memo is cut across the story, not repeated on it.**

---

## 2 · Phrase extraction

### Where it runs

Inside **`process-training-memo`**, in the same call that already produces `{ transcription, cleaned_notes, mood, coach_insight, workout_notes, extracted_data, memory_candidates }`. Add one field:

```ts
pull_quotes: Array<{
  text: string;        // verbatim span of `transcription`
  start_ms: number;    // for the waveform marker and the provenance stamp
  end_ms: number;
}>
```

No new function, no new latency, no second model call, and it lands with the existing two-stage reveal — the composer simply has phrases the moment the memo finishes processing.

### The rules, enforced in code

Follow the `bodyVocabulary.ts` precedent exactly: *"That contract is enforced in code, not trusted to the LLM."* The model proposes; a pure function in `_shared/pullQuotes.ts` disposes. Every candidate must survive all seven checks or it is dropped:

1. **Verbatim.** `transcription.includes(text)` after whitespace normalisation. A paraphrase is not a near-miss, it is a fabricated quotation attributed to the athlete on a public post.
2. **3–9 words.** Shorter is a fragment; longer will not set at 26 pt.
3. **No numerals, no number words.** `/\b(\d|one|two|…|hundred)\b/i` → reject. The app owns numbers. A mis-transcribed "fifteen" sitting next to a measured `14.99` on a public post is the one failure that cannot be walked back.
4. **No body-part + severity pair.** Run it through `normalizeBodyMention`; if it maps, drop it. *"my knee was killing me"* is a niggle for the injury tracker, not a caption — and hard rule #2 is detection, not broadcast.
5. **Filler trimmed at the edges only.** Strip a leading/trailing `um · uh · like · so · okay · honestly · you know · i mean · that's it`. Never from the middle — the middle is the voice.
6. **Substance.** Must contain a sensation, effort, or motion word, or a first-person verb. A closed list, sibling to `SEVERITY_HINTS`. *"shoes felt good"* passes; *"out and back on the lake loop"* does not — it is a fact, and facts come from the app.
7. **Dedupe and cap.** Overlapping spans: longest wins. Rank by substance-word count, then by length. **Keep 6.**

If fewer than two survive, the composer opens with the phrase slots empty and a line saying so. That is a fine outcome — see Degradation.

### What it must never do

No rewriting, no tidying, no capitalisation, no punctuation added. `cleaned_notes` already exists for the tidy version; a pull quote is raw tape. The lowercase `i` in *i was cooked by the end* is the point.

---

## 3 · The slides

All geometry at **360 pt design width**; export is 1080 px, so ×3.

### Cover — the only slide with the wordmark

```
[logo-stacked, 50pt tall]              ← assets/logo-stacked.png, ink on transparent

══════════════════════════════════════ 2px ink
POST RUN DRIP        NO. 143 · SAT 11 JUL   mono 8 · .20em

15 miles,                              Instrument Sans 700 · 42pt (54 story)
long run.                              line-height .9 · tracking −.035em
▬▬▬▬                                   34 × 2 red ornament
Saturday morning. Austin, Texas.       Times italic 13.5 — the one italic dek

        ╭───────╮                      the route, pace-coloured
       ╱  ╭──╮   ╲                     start = hollow ink ring
      ◉───╯  ╰────╯                    finish = --red dot
──────────────────────────────────────
14.99        6:50         1:42:32      Inter 600 tabular 23pt
MILES        PER MILE     MOVING       Schibsted 600 · 8pt · .18em
```

Story canvas adds a second stat row: `AVG HR · ELEV FT · HEAT-ADJ · TEMP`.

The headline is assembled, not written: `{miles} miles, {session type}.` — `6 × 800m.` for an interval day, `Cut short at 3 miles.` when the run was abandoned. It is a lookup, not a sentence generator.

### On the photo

Two treatments, both honest print moves. Direction I has no gradients and no shadows, so a scrim was never on the table.

**Over the image** — `grayscale(1) contrast(1.06) brightness(.58)`, type in white over the whole frame:

```
┌──────────────────────────────┐
│  [duotone photograph]        │
│                              │
│  felt like falling           │  JetBrains Mono italic, white, 26pt (32 story)
│  downhill                    │
│  ▬▬▬▬                        │
│  FROM YOUR MEMO · 0:35 · 14.99 MI      ◗ │  mono 8 · .16em · 72% white
└──────────────────────────────┘
```

**In the band** — photograph left bright at `grayscale(1) contrast(1.04)`, type in a solid `--ink` block at the foot. Protects the photograph; less of a poster.

The grayscale is not optional. Full-colour imagery is the one thing that would make these slides look like every other running app's export.

### On the route

```
┌──────────────────────────────┐
│ ═════════════════════════════│
│ THE ROUTE     14.99 MI · 6:50│
│      ╱────────────╲          │  the trace, drawn at 30% opacity,
│     ╱   ╭──────╮   ╲         │  oversized and bled off two edges
│    │   ╱        ╲   │        │  — a field, not a map
│  legs were absolute          │  the phrase, ink, over the trace
│  bricks                      │
│  ▬▬▬▬                        │
│  FROM YOUR MEMO · 0:08       │
│  ◗                AUSTIN, TEXAS│
└──────────────────────────────┘
```

The trace is rendered with **negative padding** so it scales past the frame and crosses the type. Nobody reads a route at that scale — they read four words on a surface no other app can generate. The pace colour stays honest anyway; it costs nothing to keep it correct.

### The splits · The workout — off by default

Direction I retypings of the two figures. The splits slide accepts a phrase too; the workout slide does not. `Fig. 1` / `Fig. 2` captions set in Crimson Pro. Cap the workout table at 10 rows.

---

## 4 · Pace colour

Use the six-zone ramp from `pv-data.jsx`, but **anchor it to the athlete, not to fixture absolutes.** The shipped `ZONES` table has Easy at 477–540 s/mi (7:57–9:00 /mi); for an athlete with a 1:08 half that is not easy, it is a walk. Anchor the centres as ratios of marathon pace:

```swift
let mp = paceZones.marathonSecPerMile          // 332 for the fixture athlete
let centres: [(Double, Color)] = [
    (1.45,  Color(hex:"A8C6B2")),   // recovery
    (1.28,  Color(hex:"4A9E6B")),   // easy
    (1.17,  Color(hex:"9A9588")),   // steady
    (1.045, Color(hex:"D98A4E")),   // marathon
    (0.935, Color(hex:"D4592A")),   // threshold
    (0.87,  Color(hex:"A8371A")),   // 5K
]
// interpolate in RGB between adjacent centres — pv-spectrum.jsx already
// does exactly this with gradientStops(), so a narrow pace band still reads
// as a ramp rather than two flat blocks.
```

The fixture long run then draws green-through-warm-grey, which is what an easy 15 at 6:50 actually is. **Do not stretch the ramp to this run's own min and max** — the whole value of anchoring is that 6:50 is the same colour on the cover, in Trends, and on the workout sheet.

One consequence to watch: on a warm-zone run the trace lands near `#D4592A`, which is close to brand `#EE2B24`. The finish dot is the only pure red on the slide, so they sit side by side. If it ever reads as one colour, the finish dot becomes ink and the red is spent on the ornament instead.

---

## 5 · Data model

```swift
struct StoryData {
    // masthead
    let issueNo: Int
    let dateShort: String         // "Sat 11 Jul"
    let headline: [String]        // ["15 miles,", "long run."] — assembled, not written
    let dek: String               // "Saturday morning. Austin, Texas."
    let place: String

    // facts
    let distanceMi: Double
    let movingSeconds: Int
    let avgPaceSecPerMi: Double
    let heatAdjPaceSecPerMi: Double?
    let avgHr: Int?, maxHr: Int?, elevationFt: Int?
    let tempF: Double?, dewF: Double?
    let marathonPaceSec: Double   // anchors the ramp

    // material
    let route: [CLLocation]
    let splits: [MileSplit]
    let blocks: [LedgerRow]
    var photo: UIImage?

    // the voice
    let memoDuration: TimeInterval
    let transcript: String
    let pullQuotes: [PullQuote]
}

struct PullQuote: Identifiable, Codable {
    let id: UUID
    let text: String
    let startMs: Int
    var stamp: String { /* 0:35 */ }
}

/// One phrase lives on one slide. Assigning it elsewhere moves it.
@Observable final class StoryComposition {
    var enabled: Set<Slide> = [.cover, .photo, .route]
    var assignment: [Slide: PullQuote.ID] = [:]
    var canvas: Canvas = .portrait
    var index: Int = 0
    func assign(_ q: PullQuote.ID, to s: Slide) {
        assignment = assignment.filter { $0.value != q }
        assignment[s] = assignment[s] == q ? nil : q
    }
}
```

`pull_quotes` persists on `training_logs` as JSONB alongside `cleaned_notes`. The composition does not persist — compose, share, discard.

---

## 6 · Files

**New — `RunningLog/RunningLog/Share/`**

| File | Contains |
|---|---|
| `StoryData.swift` | the struct above + `from(viewModel:)` |
| `StoryHeadline.swift` | the factual headline lookup (session type → `["15 miles,", "long run."]`) |
| `StoryFurniture.swift` | kicker rule, ornament, stat cell, hairline, figure caption, drip mark, wordmark |
| `StorySlides.swift` | the five slides |
| `MemoStepView.swift` | waveform, transcript, candidate list, `Landing on:` |
| `StoryStepView.swift` | the deck, dots, tray, canvas control |
| `StoryRenderer.swift` | `ImageRenderer` → `[UIImage]` + the caption string |

**Touched**

| File | Change |
|---|---|
| `Workouts/HistoryDetailSheet.swift` | one `ToolbarItem`: "Make a story ↗" — hidden when the run has no memo *and* no photo |
| `Workouts/PaceSpectrum.swift` | `anchoredStops(marathonPaceSec:)` per §4 |
| `supabase/functions/process-training-memo/index.ts` | `pull_quotes` on `AnalysisResult`, filtered through the new guard |
| `supabase/functions/_shared/pullQuotes.ts` | **new** — the seven rules, pure, unit-tested |

**Assets:** `logo-stacked.png` (ink on transparent — tint white with a `.colorMultiply` or ship a white variant) and `logo-drip.png`, both already in `assets/`.

---

## 7 · Export

```swift
@MainActor
func render(_ slide: Slide, data: StoryData, comp: StoryComposition) -> UIImage? {
    let r = ImageRenderer(content:
        SlideView(slide: slide, data: data, comp: comp)
            .frame(width: 360, height: comp.canvas.height))   // 450 or 640
    r.scale = 3                                               // 1080 × 1350 / 1080 × 1920
    r.isOpaque = true
    return r.uiImage
}
```

Same view on screen and in the PNG. `isOpaque = true` — a transparent PNG posts as a black rectangle on some clients and white on others. Render on Share, not per keystroke.

**Caption** — the first pulled phrase, then facts:

```
"felt like falling downhill"

15 miles, long run.
14.99 mi · 6:50 / mi · 1:42:32
Austin, TX · 78°F · dew 72
```

Hand `ShareSheet` (already in `Shared/ExportView.swift`) `images + [caption]`.

---

## 8 · Degradation

| Missing | Behaviour |
|---|---|
| No memo | Composer still opens. Phrase slots read `TAP A PHRASE FROM YOUR MEMO` on screen and are **omitted from the export** — the photo slide becomes a photograph with a stat line, which is still a good slide. Offer `Record one ↗` inline. |
| Memo still processing | Step 1 shows the waveform with `TRANSCRIBING…`; step 2 is reachable and works without phrases. Poll the existing two-stage status. |
| Fewer than 2 candidates survive | Show what survived plus a line: *"Not much to print from this one."* Never pad with rejected candidates. |
| No photo | Photo slide hidden from the tray. Its phrase, if assigned, moves to the route slide. |
| No GPS | Route slide hidden; the cover's trace area collapses and the headline block rises into it. |
| No splits | Splits slide hidden from the tray. |
| Neither memo nor photo | **Toolbar item hidden.** A manual 3-miler with no words and no picture has no story to tell. |

The tray never reaches zero slides — the last enabled chip ignores taps.

---

## 9 · Acceptance

1. A run with a processed memo shows **Make a story ↗**.
2. Step 1 lists ≤ 6 candidates, each a verbatim substring of `transcription`. Assert it in a test against 20 real memos.
3. No candidate contains a numeral or number-word. No candidate maps through `normalizeBodyMention`.
4. Tapping a candidate assigns it to the slide showing in step 2; tapping a second slide **moves** it rather than duplicating it.
5. The transcript highlights exactly the pulled spans, and the waveform reddens at their `start_ms`.
6. Toggle 4:5 ↔ 9:16 → slides re-compose with the extra rows, not letterboxed.
7. The cover carries `logo-stacked`; every other slide carries `logo-drip` and never the wordmark.
8. Pace colour for a 6:50 mile is identical on the cover, the splits slide, and the Trends surface for the same athlete.
9. Share → N PNGs at exactly 1080 × 1350 / 1080 × 1920, sRGB, opaque, plus the caption.
10. Open a run with no memo → composer opens, exports slides with no phrase blocks, nothing empty ships.
11. Every headline on every slide is assembled from a lookup. Grep the Share folder for adjectives; there should be none.

---

## 10 · Open questions

1. **Phrase face.** JetBrains Mono italic is the literal reading of the type roles and it looks like raw tape, which is true. Instrument Sans italic is more conventionally handsome. The prototype's rail switches between them — decide by eye, then delete the loser.
2. **The masthead vs the wordmark.** The cover uses `logo-stacked.png` directly. The earlier warm-paper study set a masthead in the display face instead. Direction I has a real grotesk now, so the logo and the headline finally belong to the same family — which is an argument for using the actual mark, and this build does.
3. **Should a phrase ever reach the cover?** Right now the cover is pure fact and the dek is the Times italic line. Putting a pulled phrase there instead would be the single most postable slide in the set, and would make the cover impossible without a memo. Worth trying once.
4. **Story mode as a sequence.** The 9:16 slides currently export as separate frames. Instagram will stitch them if uploaded together, but a purpose-built story sequence could time them to the memo audio. That is the v2 that matters — and it needs the still slides right first.
5. **Broadsheet.** Direction II would make a genuinely different-looking set of slides — newsprint, drop caps, standfirsts. If Broadsheet ever becomes the marketing skin, these slides are the first place it should appear, because they are the only surface a non-user sees.
