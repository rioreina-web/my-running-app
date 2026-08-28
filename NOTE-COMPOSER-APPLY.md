# NOTE-COMPOSER-APPLY

**Date:** 2026-08-24
**Screen:** Log tab, Direction I (`LogWildView.swift`)
**Prototype:** `note-composer-prototype.html`
**Reverses:** `LOG-WILD-APPLY.md` §6d (partially — see §2)

---

## 1 · The report

Tapping **Type a note instead** put the composer on screen and the keyboard
over the top of it. What was left was a ~44pt strip holding the `NOTE · TODAY`
label and the `SAVE ↗` link, and nothing at all for the text. The tab bar
stayed visible below it, and the keyboard toolbar's **Done** button rendered on
top of the tab bar. The headline above was clipped mid-glyph, and `Uploading…`
from the previous voice memo was still sitting in the lede.

You could type. You could not see what you typed.

---

## 2 · Why the slot could not be patched

§6d moved the composer *into the record button's slot* for a good reason:
it had been rendering below `frontDoor`, which is a full screenful, so the
button looked like it did nothing. That diagnosis was right.

But the slot is at the foot of a page sized `minHeight: max(height, 480)`
inside a `ScrollView`. When the keyboard raises, the safe area shrinks while
the page keeps its full-viewport height — so the composer, pinned to the
bottom of that page, goes under the keyboard. The tab bar takes another ~50pt
before that. There is no padding value that fixes this; the geometry is the
bug.

**§6d's actual requirement — "Type a note instead" must not look dead — is
preserved.** The sheet opens on the same tap, immediately. Only the surface
changed.

---

## 3 · What shipped

A presented sheet, `WildNoteComposerSheet`, at the foot of `LogWildView.swift`.
Five fixed rows with the writing surface taking whatever is left:

| Row | Content |
|---|---|
| Bar | `Cancel` · `Save ↗` |
| Lede | `Note.` over *Write a note about your run.* |
| Linked run | `10.01 mi` · `Today morning · 1:11:35 · 7:09/mi` · `Change ↗` |
| **Writing surface** | Crimson Pro 20pt, placeholder *How did the run feel?* |
| Footer | `Record instead ↗` · `Mon · Aug 24` |

On a 393×852 device with the keyboard up that leaves ~319pt to write in,
against ~44pt before.

### Decisions

1. **Linked run compressed to one line.** You still need to know where the
   note lands and `Change ↗` still opens `WildWorkoutPickerSheet`. It does not
   need the 32pt figure and the chip rail a second time — the front door
   underneath is already carrying that block.

2. **It reads `recentRuns`, not `recentWorkouts`.** Same reason as the linked
   block: a Strava-only run has to be linkable. See the merge in
   `HealthKitManager.refreshRecentRuns`.

3. **`Save ↗` is a state, not a button.** `ink3` until the field holds
   non-whitespace, then `redText`. Same verb-plus-arrow as `Mark complete ↗`,
   so there is no new affordance.

4. **A failed save does not dismiss.** The sheet stays up with the text
   intact and the view model surfaces the error. Dismissing would throw away
   words the athlete cannot get back.

5. **`Record instead ↗` moved to the footer.** In the inline composer it sat
   directly beneath the field, competing with what was being typed.

6. **Crimson Pro for the body.** Prose is what the athlete wrote. Italic
   JetBrains Mono is a transcript — the machine quoting them back. This is the
   writing case.

7. **No `Uploading…`.** That status belongs to the voice path and stays in the
   lede on the screen behind, which is where the upload actually is.

8. **`padding(.horizontal, 17)` on the writing surface, not 22.** `TextEditor`
   carries ~5pt of its own leading inset. 17 is what lines the first character
   up with the rules above it.

### Writing by default

**Settings → App → Write notes by default.** Off means the Log tab opens on
the record button, as it always has. On means it opens on `writeBlock` — a
type slab bound by the 2pt editorial rules, `Tap to write` beneath it, and
`Record instead ↗` as the quiet link. An exact mirror of `recordBlock`.

The primary is a type slab and not a second circular button on purpose: a
filled circle reads as "record" everywhere, and the one red belongs to the
record button alone.

`Record instead ↗` starts the take immediately rather than swapping the view
first. That flips `recorder.isRecording`, which sends `writingFirst` false and
hands the screen back to `recordBlock` — which is where the stop control
lives. A take in progress therefore always shows the record block regardless
of the preference.

Stored under `LogDefaultMode.key` (`defaultLogMode`, `"voice"` | `"text"`).
Both files go through those constants so a typo cannot split one preference
into two keys.

### Also changed

- `dayPhrase(for:)`, `metaLine(for:)` and `shortDate(_:)` moved from members of
  `LogWildView` to file scope, so the sheet shares one copy of the phrasing
  rather than growing a second.
- The keyboard toolbar's `Done` now clears `journalSearchFocused`. The journal
  search field is the only thing on this screen that takes the keyboard now —
  the composer brings its own.
- `frontDoor` no longer swaps its slot; `recordBlock` always holds it.

---

## 4 · Open

**The date stamp is display-only.** The footer reads `Mon · Aug 24` and is not
tappable. If a note should be attachable to a past day *without* going through
the run picker, that stamp is where it belongs — and this change does not
handle it. Decide before someone builds a second date affordance somewhere else.

**`WildLabel` at 10pt for `Cancel`.** Tracked uppercase is the skin's only
label role, so `Cancel` is set the same way as everything else. It reads
slightly quieter than a standard iOS sheet's Cancel. Watch whether beta
testers find it.

---

## 5 · Verify

1. Log tab → **Type a note instead** → the sheet opens with the keyboard up and
   the caret already in the field.
2. The text you type is visible. Four lines fit without scrolling.
3. `Save ↗` is grey on an empty field and on whitespace only; red once there
   are words.
4. `Change ↗` opens the run picker; picking a run updates the line behind it.
5. Save → sheet dismisses, journal scrolls to the new entry at the top.
6. With Health denied and Strava connected, the linked line still shows a run.
7. Turn airplane mode on and save → error surfaces, sheet stays up, text intact.
8. Settings → App → **Write notes by default** on → Log tab opens on the type
   slab, and the lede reads *Tap the button to write a note.*
9. With it on, tap `Record instead ↗` → recording starts and the screen shows
   the record button with `Tap to stop`. Stopping returns you to the type slab.
10. Toggle it back off → Log tab opens on the record button again.
