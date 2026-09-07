# HINGE — the page turn, as a hinge

**Applied:** 2026-08-21 · directly to the working tree on `design/wild-v2`
**Scope:** one new file, two existing files rewired.
**NOT COMPILED HERE** — this container has no Xcode and no Swift toolchain.
Nothing below has been type-checked. Build before trusting it. Verify steps in §5.
**Prototype:** `page-turn-lab-prototype.html` — the "Hinge" option.

---

## 1 · What changed

| File | Change |
|---|---|
| `App/HingePager.swift` | **New.** 299 lines. The turn, as a reusable container. |
| `App/JournalPager.swift` | Paging `ScrollView` → `HingePager(order: .sequence)`. Dead `step()` removed; its accessibility actions moved into the container. |
| `Workouts/HistoryDetailPager.swift` | Paging `ScrollView` → `HingePager(order: .book)`. Same removals. Stale header note corrected. |

Everything else at both call sites is untouched: `JournalProgress`, `JournalSpine`,
`PageTurnRail`, the soft haptic on `.onChange`, the entry-deleted recovery logic,
and the `pageTurnLocked` environment contract.

**No Xcode step needed.** The project uses `PBXFileSystemSynchronizedRootGroup`
(objectVersion 77), so `App/HingePager.swift` is compiled automatically by
virtue of sitting in the folder. Individual files are not listed in the
`.pbxproj` and you do not need to add it by hand.

---

## 2 · Why a container and not an effect

The lab costed "paper slide" at ~40 lines because it is a `.scrollTransition`
decorating the paging `ScrollView` you already had. **A hinge cannot be built
that way**, and this is the whole reason it was the expensive option:

A paging `ScrollView` lays its children out *side by side in a row*. There is no
page underneath. But a sheet rotating past 90° has to be composited **above** the
page it is revealing — that "beneath" is the entire effect.

So the pages stack in a `ZStack`, and everything `.scrollTargetBehavior(.paging)`
was giving you for free is now hand-rolled: velocity, snapping, rubber-banding at
the ends, and the directional guard that stops a horizontal drag stealing a
vertical scroll.

---

## 3 · The mechanic

For each page, `q` is how far past it we have turned — `0` is lying flat and face
up, `1` is fully turned away.

```
rotation  = -180° × q          about the leading edge
shade     = 0.34 × q           the sheet falling into shadow as it goes edge-on
gutter    = 0.26 × sin(π × q)  the shadow the sheet above casts into the binding
opacity   = q < 0.5 ? 1 : 0    the backface cut
```

Three of those need a word:

**The backface cut.** SwiftUI has no `backface-visibility`. Past 90° the sheet
would start showing its own back, which SwiftUI renders as a mirrored copy of the
front — it reads as a rendering bug, not as paper. The page is cut at exactly the
half-turn, where it is edge-on and one pixel wide, so the cut is invisible.

**The gutter uses `sin`, not `q`.** The shadow a folding page throws is strongest
at the half-turn and gone at both ends. Ramping it linearly makes it blink on and
off at the start and finish of every turn.

**`position` is not derived from `selection`.** This is the subtle one. If the
page index were computed from `selection`, committing a turn would change
`selection` instantly while the drag offset animated separately to zero — and the
page would jump a full width at the start of every single commit. `position` is
the animated source of truth; `selection` is written alongside it.

---

## 4 · The dials

All in `App/HingePager.swift`.

| Dial | Now | What it does |
|---|---|---|
| `perspective` | `0.55` | **The main one.** 0 shears the page flat with no depth; 1 is a wide-angle lens. 0.55 is a book at reading distance. |
| shade opacity | `0.34` | How dark the turning sheet goes. Lower reads as thin paper, higher as card. |
| gutter opacity | `0.26` | Depth at the binding. |
| commit threshold | `0.26` | How far you must drag before it turns rather than springs back. |
| flick threshold | `0.55` | Predicted travel that commits a turn your finger never finished. |
| turn duration | `0.34s` | `.snappy(extraBounce: 0)` — deliberately no bounce. Paper does not bounce. |
| directional guard | `1.2×` | How much more horizontal than vertical a drag must be before the turn takes it. **Raise this first if vertical scrolling feels stolen.** |

---

## 5 · Verify on device

In rough order of how likely each is to be the thing that is wrong.

1. **Vertical scrolling inside a page.** The biggest risk in this change. Open a
   workout sheet with a long body and scroll up and down hard. If the page starts
   turning when you meant to scroll, raise the `1.2×` guard toward `1.6×`, and
   raise `minimumDistance` from `14` toward `20`.
2. **The telemetry scrubber.** `UnifiedTelemetryCard` raises `pageTurnLocked`
   during a scrub. Press-and-drag on the chart and confirm the page does not turn
   under you. This is the contract `gestureMask` is honouring.
3. **`NavigationStack` inside a rotated sheet.** Each `HistoryDetailSheet` carries
   its own `NavigationStack` and toolbar. Rotating a navigation container in 3D
   is unusual — watch the toolbar mid-turn for flicker or mis-placed buttons. If
   it misbehaves, this is the one thing that might push the workout sheets back
   to paper-slide while the journal keeps the hinge.
4. **Charts under a 3D transform.** Turn onto the workout page of a session with
   a full GPS stream and watch for dropped frames. The lever is `.drawingGroup()`
   on the page content — but it flattens the layer, so check materials and blend
   modes afterwards.
5. **Reduce Motion.** Settings → Accessibility → Motion → Reduce Motion. The turn
   should become a crossfade with no rotation and no shading. A 3D page flip is a
   textbook vestibular trigger; this must work.
6. **VoiceOver.** The journal should offer "Next page" / "Previous page"; a
   workout sheet should offer "Older entry" / "Newer entry". Exactly one of each —
   if you hear duplicates, a call site kept its own actions.
7. **The ends.** First and last page should rubber-band and spring back, not stop
   dead.
8. **Delete the entry you are standing on.** The recovery logic in
   `.onChange(of: entries.map(\.id))` is unchanged, but it now has to co-operate
   with `position`. You should land on the neighbour, not at the top of the journal.

---

## 6 · Behaviour that genuinely changed

Not bugs — consequences of leaving the scroll view behind.

- **A fast flick turns exactly one page.** The old paging scroll had momentum and
  could carry you several pages on one throw. A hinge cannot: you cannot turn
  three sheets at once. Multi-page jumps are the rail's and the spine's job now,
  and both still work.
- **A downward drag on a journal page still dismisses the Today sheet.** Unchanged
  from `PAGED-HOME-APPLY.md` §7, and worth re-confirming since the gesture
  landscape moved.

---

## 7 · Open questions

**7.1 · The two pagers still run opposite ways in time.** `HistoryDetailPager` is
book order — oldest sheet first, today last. `HomeDayPager` is newspaper order —
today is the front page. `PAGED-HOME-APPLY.md` §8.1 flagged this while the turn
was a flat slide, when it was a detail. **A hinge makes direction physical**: the
same wrist movement now means "forward in time" in one surface and "backward" in
the other, and it is a much louder contradiction when the paper is visibly
turning.

`HingeOrder` exists so this is a one-line decision per call site when you settle
it, rather than a rewrite. It changes only VoiceOver wording today.

**7.2 · `HomeDayPager` was deliberately not converted.** It is a day old and still
untracked as of this morning. Converting a third surface in the same change would
mean two new mechanics landing on top of each other. Do it once the two here have
survived a week on device — it is the same six-line swap.

**7.3 · The Sheet is still one scroll.** You chose one month per spread. That is
page-break work in `SheetTabView`, not turn work, and it has to come first —
there is nothing to turn until the ledger has pages.

---

## 8 · Rollback

The whole change is three files on a branch that nothing else depends on.

```bash
cd ~/my-running-app
git checkout design/wild-v2 -- .          # discard local edits on the branch
git revert <this commit>                  # or undo it entirely
```

To leave the branch and go back to the shipping app:

```bash
git checkout beta-v1-editorial
```
