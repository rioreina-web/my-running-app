# Empty-state copy rules

Every empty cell in the UI uses the empty-state component — never an em-dash
or a blank field. The component renders an optional eyebrow, a plain-prose
nudge, and an optional CTA.

Components:
- iOS: `RunningLog/Shared/EmptyStateView.swift` (init with a `Variant`).
- Web: `web/src/components/ui/empty-state.tsx`.

## Variants

| Variant         | When to use                                                              |
|-----------------|--------------------------------------------------------------------------|
| `setup-needed`  | The user must do something for this surface to populate.                 |
| `data-pending`  | The surface needs more activity (runs / voice logs) to populate.         |
| `optional-empty`| Legitimately empty. Not a problem. Quiet.                                |
| `error`         | A fetch or computation failed.                                           |

## Copy rules

1. **No em-dashes as placeholders.** Every empty cell uses this component.
   This is CLAUDE.md hard rule #8.

2. **Eyebrow is a short category label, UPPERCASE.** One to three words —
   what this surface is. e.g., *VOLUME*, *NEXT RACE*, *PACE TARGETS*.
   Skip the eyebrow when the surrounding header already names the section.

3. **The nudge is plain prose.** Sentence case, one short line. No italic
   serif, no pull-quote, no editorial register — those are gated to
   `data_depth >= 2`. e.g., *"You haven't logged a run yet."*

4. **CTA labels are imperative and specific.** *"Set a goal race"*, not
   *"Set up"*. *"Record your first voice log"*, not *"Get started"*. Use
   the words the user will see on the resulting screen.

5. **Empty-state, not editorial-state.** At `data_depth` 0–1 every section
   either renders its data or renders this component. No prose fill, no
   pull-quotes, no trend prose with no data behind it. (Pairs with CLAUDE.md
   hard rule #8 and the pull-quote-citation rule.)

6. **Error copy states what failed, in plain English.** No fake-cheery copy
   like *"Oops!"*. Include a retry action when the failure is recoverable.
   e.g., *"Couldn't load this week's volume."* with a *Retry* button.
