# Design system audit — how is the app looking

*2026-05-20. Picks up where `design-parity-audit-2026-05-20.md` left off,
but scoped to the **system** (tokens, primitives, cross-platform parity)
rather than per-surface drift.*

## TL;DR

The brand reads as two products, not one. Same color palette across iOS
and web, completely different type system. iOS has more sophisticated
editorial primitives (`PlateStrip`, `CoachQuote`, `EditorialRule`) — but
they're underused. Web has cleaner token discipline on color but is
swimming in arbitrary `text-[10.5px]` and `tracking-[1.5px]` one-offs.

**Score: 58/100.** Foundations exist, primitives exist, conventions are
written down. The gap is enforcement — drift accumulates faster than it's
cleaned up.

The yesterday parity audit (`design-parity-audit-2026-05-20.md`) named
the iOS-specific reasons it "feels like the old model." Nothing in that
audit has been fixed yet. This one zooms out one layer: even if every iOS
fix shipped tomorrow, the system itself has structural gaps that will
keep generating drift.

---

## Three calls before any pixel work

These rank above the surface-by-surface fixes in the parity audit because
they're root causes — fixing surfaces without fixing these guarantees
re-drift in six weeks.

1. **Pick one type system or commit to two on purpose.** iOS ships
   Crimson Pro / PT Serif / SF Mono. Web ships Playfair Display / DM Sans
   / JetBrains Mono. Colors match exactly; fonts don't share a single
   family. The design system source-of-truth file
   (`Post Run Drip Design System/colors_and_type.css`) isn't checked
   into the repo — it lives outside the codebase. Without a checked-in
   token contract, no one can tell which platform is "right."

2. **Tokenize spacing and tracking, in both platforms.** iOS has zero
   spacing tokens — every `.padding(20)` is hand-typed. The most-used
   values in the codebase are 20 (352×), 16 (257×), 12 (139×), 14 (123×),
   10 (96×), 6 (55×). The 14/10/6/22 cluster is off the 8pt grid the
   spec calls for. Web has the same problem on tracking — 101 distinct
   `tracking-[Npx]` callsites, no token, values drift between 1.3, 1.4,
   1.5, 1.6 for the same eyebrow.

3. **Pick a canonical empty-state pattern and delete the em-dashes.**
   CLAUDE.md hard rule #8 says every empty cell uses the empty-state
   component. Both platforms have one (`EmptyStateView.swift`,
   `empty-state.tsx`). Both platforms also still ship `Text("—")` in
   production paths — 4 iOS sites (including `TodayPlate18.swift:831`
   and `:836` — the canonical Today surface) and 5 web sites. Rule
   written, rule not enforced.

---

## Token coverage

| Category | iOS | Web | Notes |
|----------|-----|-----|-------|
| Color — semantic | Defined (DripColors struct) | Defined (CSS vars + Tailwind theme) | Same hex values across both — only thing that's parity. |
| Color — hardcoded usage | Minimal (single `electric` rename pending) | 16 .tsx files with `#XXXXXX` literals | Chart components are the worst offenders (`mood-heatmap`, `pace-trend-chart`, `injury-timeline`, `compliance-chart`, `workout-type-donut`). |
| Typography — families | 4 helpers (display/body/label/stat/eyebrow/caption) | 3 CSS vars (display/mono/body) | Different families per platform. See call #1. |
| Typography — sizes | No scale defined; sizes passed as arguments | 16 distinct `text-[Npx]` arbitrary values (130× `text-[10px]`, 53× `text-[11px]`, 16× `text-[10.5px]`, etc.) | No `text-xs`/`text-sm` ladder is in use — every callsite picks pixels. |
| Tracking | Hand-typed at callsites (`0.5`, `0.6`, `0.8`, `1.0`, `1.3`, `1.4`, `1.5`) | 101 distinct `tracking-[Npx]` literals | Spec says 0.10em/0.12em/0.14em depending on label class. No token enforces this anywhere. |
| Spacing | **None defined.** Raw pixel values. | Tailwind scale present but heavily supplemented with arbitrary `[Npx]` | iOS off-grid: 14, 10, 6, 22. Web stays mostly on Tailwind's scale for layout, but inline padding/sizes drift. |
| Border radius | Hardcoded per component (10, 12, 8) | Mostly Tailwind (`rounded-lg`, `rounded-xl`, `rounded-full`) | Sign-in form alone uses 8/10/12 in three places — see parity audit. |
| Shadows | One inline value (`black.opacity(0.06), radius: 8, x: 0, y: 2`) | One inline value, same numbers | Not tokenized but at least consistent. Promotable to a named elevation. |
| Motion | None defined | None defined | One spinner duration is a magic number; not yet a problem. |

---

## Component completeness

### iOS — `DesignSystem.swift` (526 lines)

| Component | States covered | Variants | Notes |
|-----------|---------------|----------|-------|
| `StatCard` | default | accentColor optional | Solid. Uses dripStat/dripEyebrow correctly. |
| `MoodBadge` | default | by mood string | **Drifts.** Uses SF Symbol icons (emoji-equivalent per spec — should be a dot). Caption text is in PT Serif (`dripCaption(10)`), not mono. Flagged in parity audit. |
| `PulsingRecordButton` | recording / not / disabled | — | Bespoke to Voice surface. Fine as a one-off. |
| `DripButton` | primary / secondary / ghost / loading / disabled | 3 | Good. Label uses `dripLabel(15)` correctly. |
| `SectionHeader` | default | action button optional | Good. Uses mono eyebrow at 0.12em tracking. |
| `PlateStrip` | default | surface + fig | **Underused.** Only `CoachReadView` calls it. Every other editorial surface is supposed to. |
| `PlateFooter` | with/without caption | — | Underused — same scope as PlateStrip. |
| `CoachQuote` | default | — | Good. Wraps text in curly quotes itself. Spec-correct. |
| `Hairline` / `EditorialRule` | default | — | Good. EditorialRule replaced four private duplicates. Worth checking they're actually gone. |
| `EmptyStateView` | 4 variants + legacy init | 4 | Works, but eyebrow uses `dripLabel(11)` (Crimson Pro semibold) instead of mono — drifts from its own spec. |
| `SkeletonPulse` / `SkeletonBar` | default | — | Fine. |
| `GlowingOrb` | — | — | **No-op placeholder.** Should probably be deleted; ZIP of 0x0 Color.clear is a maintenance smell. |

Roughly half the primitives the design system spec calls for exist in
code; the other half (`Eyebrow`, `EyebrowCoral`, `DripSpacing`, `MoodPill`,
proper `ChartCard`, the COACH'S PLAN week strip) are either inlined or
missing entirely.

### Web — `components/ui/` (285 LOC across 9 files)

| Component | States covered | Variants | Notes |
|-----------|---------------|----------|-------|
| `Card` | default | accent (left coral border), padding sm/md/lg | Good — leans on tokens, has variants. |
| `DripButton` | primary / secondary / ghost / loading / disabled | 3 | Mirrors iOS API. Reasonable. |
| `MoodBadge` (19 LOC) | default | by mood | **Thinner than iOS.** Just colored text in a capsule. No dot. iOS at least tries (with the wrong icon). The spec wants `tracked uppercase pill + dot color`. Neither platform gets this right. |
| `SectionHeader` | default | — | Compact. Uses tokens. Fine. |
| `StatCard` | default | — | Fine. |
| `EditorialDivider` | default | — | Web's `line · dot · line`. Tiny, fine. |
| `DropCap` | default | — | Bespoke editorial moment, fine. |
| `NarrativeStat` | default | — | Spec lives in usage, not in docs. Worth a doc pass. |
| `EmptyState` | 4 variants | 4 | Best-documented component in the system — has a JSDoc and points at the conventions doc. Model for others. |

The web side has a tighter primitive set but skips real iOS-equivalents
(`PlateStrip`, `PlateFooter`, `CoachQuote`). These exist as inline
patterns in some pages — verifiable in the Today/Plan/Coach Read JSX
mockups — but aren't extracted to `components/ui/`.

---

## Cross-platform consistency check

This is the most informative table in the audit, because it's also where
parity is most embarrassing.

| Concept | iOS | Web | Same? |
|---------|-----|-----|-------|
| Color palette (coral, mood, paper) | `Color.drip.*` | `--color-*` CSS vars | ✅ Identical hex values |
| Display font | Crimson Pro | Playfair Display | ❌ Different family |
| Body font | PT Serif | DM Sans | ❌ Different family AND different category (serif vs sans) |
| Mono font | SF Mono | JetBrains Mono | ❌ Different family |
| Coral usage rule ("one per cluster") | Spec'd, not enforced | Spec'd, not enforced | ⚠️ Same problem |
| Empty-state component | `EmptyStateView` (4 variants) | `EmptyState` (4 variants) | ✅ API parity, but iOS eyebrow drifts to Crimson Pro |
| Em-dash placeholder ban | Hard rule #8 | Hard rule #8 | ❌ 4 iOS + 5 web files still ship `—` |
| Plate chrome (strip/footer) | `PlateStrip`, `PlateFooter` defined | Not extracted as components | ❌ Asymmetric |
| Coach quote (italic-serif + 2px coral bar) | `CoachQuote` primitive | `.coach-note` global class | ⚠️ Different implementation, same intent |
| `data_depth` editorial gating | Referenced in CLAUDE.md | Referenced in CLAUDE.md | ⚠️ Not codified as a hook/util on either platform |
| Tab structure | Log / Training / Coach / Plan (4) | Coach portal is a sidebar app | N/A — different audience |

---

## What changed since the May 20 parity audit

Nothing in code. The parity audit is dated `2026-05-20` and we're still
on `2026-05-20` — so this isn't a knock, it's a baseline. But the things
it called out (Today tab gone, dripCaption=PTSerif, MoodBadge emoji, no
PlateStrip on most surfaces) are all still present, verified just now in
the actual files.

The parity audit's **recommended reshape order** still stands as the
right work-plan for iOS. This audit's three "calls before any pixel
work" sit *above* that list — they're structural, the parity items are
surface.

---

## Priority actions (system-level)

Ranked impact-per-effort. Different from the parity audit's ranking —
this is "what unblocks the most other work."

1. **Check `Post Run Drip Design System/` into the repo.** Right now
   the source-of-truth `colors_and_type.css` and the JSX mockups for
   each plate live outside the codebase. The parity audit references them
   by path but they're not in the tree. Without that, "the spec" is a
   moving target. *Effort: half a day. Unblocks everything.*

2. **Fix `Font.dripCaption(_:)` to mono on iOS.** Single-token change,
   cascades to every uppercase eyebrow in the app. Parity audit P1 #1.
   *Effort: one hour + a visual sweep.*

3. **Add `DripSpacing` tokens (iOS) and a tracking token scale (web).**
   iOS: enum with `xs=4, sm=8, md=12, lg=16, xl=20, xxl=24, xxxl=32`.
   Web: `tracking-eyebrow-caption / -label / -plate-meta` semantic
   utilities mapped to 0.10em/0.12em/0.14em. Then run a
   migration sweep over the 101 web `tracking-[]` callsites and the
   1100+ iOS `.padding(N)` callsites. *Effort: one day per platform.*

4. **Sweep the em-dashes.** 4 iOS files, 5 web files. Direct replacement
   with `EmptyStateView(variant: .optionalEmpty, ...)` /
   `<EmptyState variant="optional-empty" ... />`. Mechanical work.
   *Effort: two hours.*

5. **Fix `MoodBadge` on both platforms simultaneously.** Replace SF
   Symbol with a 6px filled dot on iOS. Add a dot on web. Same API,
   same look. *Effort: half a day, both platforms.*

6. **Extract `PlateStrip` / `PlateFooter` / `CoachQuote` to
   `components/ui/` on web.** Cross-platform primitive parity. Web
   side has them as inline patterns already; just promote. *Effort:
   one day.*

7. **Resolve the type-system split.** This is the only one on the list
   that's a real strategy call, not engineering. Either (a) accept that
   iOS and web use different fonts on purpose and document why, or (b)
   pick one family per category and migrate the other platform. The
   honest answer here probably depends on font licensing and what's
   already in production hands. *Effort: depends entirely on choice.*

---

## What I'd *not* do yet

- **Don't deepen the Coach portal until the IA call is made.** Three
  surfaces (`iOS Coaching/`, web `(app)/coach`, web `(app)/coach-portal/*`).
  CLAUDE.md flags this as unresolved. Designing more pages into a
  three-way IA fork compounds drift.
- **Don't introduce new chart primitives** until the `#hex` literals
  inside the existing chart components (`mood-heatmap`, `pace-trend-chart`,
  `injury-timeline`, etc.) are pulled to tokens. New charts will
  copy the pattern.
- **Don't write more design specs.** The system already has
  `Post Run Drip Design System/README.md`, `colors_and_type.css`,
  the JSX mockups, `IMPLEMENTATIONS.md`, the parity audit, the empty-state
  doc, this audit, and CLAUDE.md. The bottleneck isn't documentation;
  it's enforcement.

---

## Files referenced

- `RunningLog/RunningLog/App/DesignSystem.swift` — iOS token + primitive source
- `RunningLog/RunningLog/Shared/EmptyStateView.swift` — iOS empty state
- `RunningLog/RunningLog/App/RunningLogApp.swift:75-140` — current iOS tab structure
- `web/src/app/globals.css` — web token source
- `web/src/components/ui/*.tsx` — web primitives (9 files, 285 LOC)
- `docs/conventions/empty-states.md` — copy rules
- `outputs/design-parity-audit-2026-05-20.md` — per-surface iOS drift (predecessor to this)
- `Post Run Drip Design System/` — referenced by parity audit; **not in tree** (see action #1)
