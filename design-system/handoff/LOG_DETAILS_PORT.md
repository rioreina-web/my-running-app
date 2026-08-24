# Log Details — Editorial Port (Direction A)

This is the Swift port of the **A · Editorial** direction from
`Log Details Rebrand.html`. Two new files:

- `DripEditorialPrimitives.swift` — reusable views: `DripPlateStrip`,
  `DripHairline`, `DripEyebrow`, `DripStatStrip`/`DripStat`, `DripTextLink`.
  No new tokens; everything resolves to existing `Color.drip.*` +
  `.dripCaption(n)`.
- `HistoryDetailSheet+Editorial.swift` — an extension on `HistoryDetailSheet`
  exposing `editorialBody`. Drop this in alongside the existing file, then
  swap one block in `HistoryDetailSheet.body`.

## What to replace

In `HistoryDetailSheet.swift`, the current `body` is:

```swift
NavigationStack {
  ZStack {
    Color.drip.background.ignoresSafeArea()
    ScrollView { VStack(spacing: 24) { … 250 lines of cards … } }
  }
  .navigationBarTitleDisplayMode(.inline)
  .toolbar { … }
  …
}
```

Replace the **`ScrollView { VStack { … } }` block only** with:

```swift
editorialBody
```

Everything else — toolbar, sheets, alert, `.task`, `.onAppear` —
stays exactly as it is. You can also drop the `.toolbar { ToolbarItem(placement: .principal) … }`
"LOG DETAILS" centerpiece, since the plate strip now carries the title.

## Helper methods you may need on `vm` / `TrainingLog`

The editorial body reads a few fields the current view doesn't surface
directly. If they aren't already on `TrainingLog`, add thin accessors:

- `workoutAverageHeartRate` → Double? (already in linked-workout data)
- `workoutElevationGainMeters` → Double?
- `displayDate.shortDateString` → "MAY 21" (mono uppercase)
- `displayDate.shortTimeString` → "09:06"
- `createdAt.shortDateString` → "May 21"

If these names don't match what's on the model, just rename inside
`editorialStats` and the plate strip.

## Coach insight wiring

The "Ask the coach →" link is a `DripTextLink`. The original
`CoachInsightSection` owned the generator call internally — when you
port this, lift that call (`vm.generateCoachInsight(entry:)` or
whatever name it has) into the link's action closure. I left a
`// call existing CoachInsightSection generator path` TODO inline.

## What else this changes

- "AI SUMMARY" card with coral border → eyebrow + `FormattedSummaryText`
- Mint LINKED WORKOUT tile → folded into the stat strip + a hairline
  "LINKED · HEALTHKIT" row with one coral "VIEW DETAIL ↗" link
- Pink "Get Coach Feedback" pill → `DripTextLink`
- Gray "Save Notes" pill → tiny mono "SAVE" link, coral when notes are dirty
- Red "Delete Log" pill → quiet mono "DELETE LOG" at the foot
- "Original Notes" serif paragraph (`Distance: 6.9 mi / Duration: …`)
  → gone. The data lives in the stat strip now. If users were typing
  free-form into that field, surface it through "WORKOUT NOTES" instead.

## Once this lands

`DripPlateStrip`, `DripHairline`, `DripEyebrow`, `DripStatStrip`,
`DripTextLink` are now project-wide vocabulary — reuse them when porting
the Fitness Predictor rebrand and any other surface that's still
card-in-card today.
