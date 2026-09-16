# Coach · The Read — Execution Prompts

**Companion to:** `Coach iOS.html` (Direction A · The Read).
**Purpose:** Copy-pasteable prompts for Claude Code to ship the Coach tab redesign into iOS + Supabase, phase by phase.
**How to use:** Execute in order. Each prompt is self-contained — the agent does not need to read the design unless explicitly referenced. Dependencies are called out in each prompt header. After each prompt, build the project and review the diff before running the next.

---

## Decisions baked in

These have already been made — do **not** re-litigate them inside the prompts:

- **Cadence** — one **daily** Read posted at 6 AM athlete-local. Re-renders on-demand only if the athlete logs a workout that changes the picture (post-long-run, post-tempo).
- **Reply state in scope** — when the athlete asks a question in the Ask bar, the response renders as another editorial Read post (headline + paragraph with citations + confidence), not a chat bubble.
- **Surface position** — The Read replaces the body of the existing self-coached path inside `CoachTabView` (the `.aiAgent` section). The "coached" mode (athlete invited a human coach) is unchanged.
- **The existing `CoachView.swift` chat list is deprecated** — once The Read ships, it can be deleted along with `WelcomeCard`, `SuggestionChip`, and the AI-introducing copy ("Hey, I'm Coach", "Your AI running coach").
- **The brand-voice doc is the source of truth for tone** — `brand-voice.md`. Especially attribute 3.4 ("Honest when uncertain") which the **What I can't see** block exists to land.
- **Three citation styles** — `◆` workout (coral wash), `§` knowledge doc (outlined), `♪` voice memo (visible in Sources only, never inline).

---

## Phase 1 — Backend: structured Read endpoint (~2-3 days)

Goal: the agent returns a structured JSON Read object instead of plain markdown. Stored daily; re-fetchable on demand.

---

### Prompt 1.1 — Create `daily_coaching_reads` table

**Dependencies:** none (start here).
**Files to create:** new migration in `supabase/migrations/`.

> Create a new Supabase migration named `<timestamp>_daily_coaching_reads.sql`. Mirror the structure of `weekly_coaching_reports` (see `20260306_create_weekly_coaching_reports.sql`). Columns: `id uuid primary key default gen_random_uuid()`, `user_id uuid not null references auth.users(id) on delete cascade`, `read_date date not null` (the date the Read was generated for, athlete-local), `status text not null default 'pending'` (check in 'pending','completed','failed'), `headline text`, `paragraph jsonb not null default '[]'::jsonb` (array of segments — see schema below), `cant_see jsonb` (`{eyebrow, body}` or null), `sources jsonb not null default '{}'::jsonb` (`{workouts: [id], docs: [id], memos: [{label, excerpt, log_id}]}`), `confidence jsonb not null default '{}'::jsonb` (`{level, sub}`), `ai_model text`, `generated_at timestamptz`, `triggered_by text not null default 'cron'` (check in 'cron','manual','workout_trigger'), `created_at timestamptz not null default now()`, `updated_at timestamptz not null default now()`. Add `unique (user_id, read_date)`. RLS: users select/insert/update their own row; service role full access. Add an updated_at trigger. Index on `(user_id, read_date desc)`.
>
> The `paragraph` JSONB schema (document in a SQL comment on the column):
> ```jsonc
> // Each element is one of:
> //   "plain text"                              — a string
> //   { "workout_id": "<uuid>" }                — workout citation
> //   { "doc_id":     "<uuid>" }                — knowledge-base citation
> // The frontend renders strings inline and citations as kerned chips.
> ```

---

### Prompt 1.2 — Daily Read prompt + JSON schema

**Dependencies:** 1.1.
**Files to create:** `supabase/functions/_shared/prompts/daily-read.v1.ts`.

> Create a new prompt module at `supabase/functions/_shared/prompts/daily-read.v1.ts`. Follow the file structure used in `_shared/prompts/coaching-agent-moderate.v1.ts` — a header comment block + exported `SYSTEM_PROMPT` string + exported `RESPONSE_SCHEMA` (Gemini structured output schema).
>
> The system prompt opens with the brand voice section from `brand-voice.md` ("Coach first, software second"; "Grounded, not generic"; "Honest when uncertain"; "Numbers over adjectives"; the banned-word list). Then it instructs the model: "Write a 4-6 sentence morning paragraph for the athlete. Open with a one-line headline that names what's happening (e.g., 'The base is taking.'). In the paragraph, cite specific workouts by their `workout_id` and specific knowledge-base docs by their `doc_id`. Never invent citations. Always include a `cant_see` block when there is a meaningful blind spot (missing sleep data, unsynced workouts, single-data-point niggles, low-confidence prediction). The `confidence.level` is HIGH, MEDIUM, or LOW based on workout count + doc count + recency."
>
> `RESPONSE_SCHEMA` is a Gemini structured-output JSON schema for:
> ```ts
> {
>   headline: string,
>   paragraph: Array<string | {workout_id: string} | {doc_id: string}>,
>   cant_see: { eyebrow: string, body: string } | null,
>   sources: {
>     workouts: string[],   // ids referenced
>     docs: string[],       // ids referenced
>     memos: { label: string, excerpt: string, log_id: string }[]
>   },
>   confidence: { level: 'HIGH'|'MEDIUM'|'LOW', sub: string }
> }
> ```
> Cite the brand voice doc at the top of the file. Mark this prompt as `v1` — if you change the schema later, bump to `v2` and keep v1 importable for evals.

---

### Prompt 1.3 — `coaching-daily-read` edge function

**Dependencies:** 1.1, 1.2.
**Files to create:** `supabase/functions/coaching-daily-read/index.ts`.

> Create a new edge function at `supabase/functions/coaching-daily-read/index.ts`. Reuse the context-fetch pattern from `coaching-agent/index.ts` lines 700-820 (the `Promise.allSettled` batch fetching training logs, athlete state, weekly report, RAG docs, etc.) — extract that into a shared helper at `supabase/functions/_shared/coach-context.ts` if it isn't one already, and import from both functions.
>
> Input: `{ user_id }` from POST body, service-role-only (cron-callable). Logic:
> 1. Resolve athlete-local date.
> 2. If `daily_coaching_reads` already has a `completed` row for `(user_id, today)`, return it.
> 3. Insert a `pending` row.
> 4. Build the full context bundle (training logs, athlete state, RAG top-5 generic docs + targeted RAG retrieval based on recent workout types + active goal, weekly report, race intel, recent voice memos).
> 5. Build the prompt with `DAILY_READ_SYSTEM_PROMPT + context + "Generate today's Read for this athlete."`
> 6. Call Gemini 2.5 Flash via the existing `router.ts` (force `complexity: 'complex'` because this is a creative-writing task that benefits from the extended context window). Use `responseSchema: RESPONSE_SCHEMA` for structured output.
> 7. Validate the response — every `workout_id` must exist in the athlete's `training_logs`; every `doc_id` must exist in `coaching_documents`. Strip invalid citations and log a warning.
> 8. Update the row to `completed` with the JSON fields populated. Set `ai_model` to the model id from the response.
> 9. On failure, set `status='failed'` and store the error. Don't throw.
>
> Return the row. Enforce `verify_jwt = false` (service-role only) and add an explicit service-role check at the top: reject if `x-supabase-role` is not `service_role`. Add this function to `supabase/config.toml`.

---

### Prompt 1.4 — Cron trigger

**Dependencies:** 1.3.
**Files to create:** new migration.

> Create a migration `<timestamp>_daily_coaching_reads_cron.sql`. Use `cron.schedule` (pg_cron) to run a SQL function `enqueue_daily_reads()` every hour, similar to `drain-coach-insight-jobs` pattern. The function: select all `user_profiles` rows where the user's local time is between 06:00 and 06:59 (use the `timezone` column, default 'UTC'), and for each one, fire-and-forget call `coaching-daily-read` via `pg_net.http_post` with `{user_id}` and the service role bearer. Idempotent — the edge function already short-circuits if a completed row exists for today. Log the request count to a `daily_read_dispatch_log` table (also create it).

---

### Prompt 1.5 — Workout-trigger re-render

**Dependencies:** 1.3.
**Files to modify:** add a Postgres trigger on `training_logs`.

> When a `training_logs` row is inserted/updated where the workout type is `long`, `tempo`, or `interval` (a "quality" session), enqueue a re-render of today's Read. Implement as a Postgres trigger on `training_logs` AFTER INSERT/UPDATE that calls `coaching-daily-read` via `pg_net.http_post` with `{user_id, triggered_by: 'workout_trigger'}`. Use `pg_advisory_lock` keyed on `(user_id, current_date)` to debounce — at most one trigger per athlete per day after the morning cron.

---

## Phase 2 — Swift models (~half day)

Goal: typed Swift structs matching the JSONB response, plus a service that fetches and caches the latest Read.

---

### Prompt 2.1 — `CoachRead` model

**Dependencies:** Phase 1 shipped to staging.
**Files to create:** `RunningLog/RunningLog/Models/CoachRead.swift`.

> Create `RunningLog/RunningLog/Models/CoachRead.swift`. Define:
>
> ```swift
> struct CoachRead: Codable, Identifiable, Equatable {
>     let id: UUID
>     let readDate: Date
>     let headline: String
>     let paragraph: [Segment]
>     let cantSee: CantSee?
>     let sources: Sources
>     let confidence: Confidence
>     let aiModel: String?
>     let generatedAt: Date
>
>     enum Segment: Codable, Equatable {
>         case text(String)
>         case workout(workoutId: UUID)
>         case doc(docId: UUID)
>         // Custom init(from:) — if container has key "workout_id" → .workout,
>         // "doc_id" → .doc, else try decoding as String → .text.
>     }
>
>     struct CantSee: Codable, Equatable { let eyebrow: String; let body: String }
>     struct Sources: Codable, Equatable {
>         let workouts: [UUID]
>         let docs: [UUID]
>         let memos: [Memo]
>         struct Memo: Codable, Equatable { let label: String; let excerpt: String; let logId: UUID }
>     }
>     struct Confidence: Codable, Equatable {
>         let level: Level; let sub: String
>         enum Level: String, Codable { case high = "HIGH", medium = "MEDIUM", low = "LOW" }
>     }
> }
> ```
>
> Use `CodingKeys` to map snake_case (`read_date`, `cant_see`, `ai_model`, `generated_at`, `workout_id`, `doc_id`, `log_id`). Write a unit test in `RunningLogTests` decoding a sample JSON fixture — include one workout chip, one doc chip, and one plain string in the paragraph.

---

### Prompt 2.2 — `CoachReadService`

**Dependencies:** 2.1.
**Files to create:** `RunningLog/RunningLog/Services/CoachReadService.swift`.

> Create an `@Observable class CoachReadService` singleton (`static let shared`). State:
> - `var todayRead: CoachRead?` — the current Read.
> - `var isLoading: Bool` — true during refresh.
> - `var lastError: Error?`
> - `var workoutsById: [UUID: TrainingLog]` — hydrated cache so chips can render without a second fetch.
> - `var docsById: [UUID: CoachingDocument]` — same for docs (create the `CoachingDocument` Codable model if it doesn't exist, matching the `coaching_documents` table).
>
> Methods:
> - `func refresh() async throws` — fetch `daily_coaching_reads` row for today via the standard Supabase client; if missing, POST to `coaching-daily-read` with the user JWT. Then hydrate referenced workouts (one `in` query over `sources.workouts`) and docs (one `in` query over `sources.docs`). Cache.
> - `func ask(_ question: String) async throws -> CoachRead` — POSTs to `coaching-agent` with a new `format: "editorial"` flag (Phase 4 adds this); returns a CoachRead-shaped response. Does NOT mutate `todayRead`. The reply lives in `CoachReplyService` (see Prompt 4.1).
>
> Call `refresh()` from `RunningLogApp` once on launch and re-call on app foreground. Log errors to `Log` category `coachRead`.

---

## Phase 3 — SwiftUI components (~1 day)

Goal: pixel-faithful SwiftUI versions of the four primitives from the jsx mock. Each is its own file so they're individually testable + previewable.

---

### Prompt 3.1 — `EvidenceChip` (workout, ◆ coral wash)

**Dependencies:** 2.1.
**Files to create:** `RunningLog/RunningLog/Coaching/Read/EvidenceChip.swift`.

> Create `RunningLog/RunningLog/Coaching/Read/EvidenceChip.swift`. Define `struct EvidenceChip: View` with two init forms: `inline(workout: TrainingLog)` and `expanded(workout: TrainingLog)`. The inline form is `Text("◆ \(workout.typeLabel.uppercased()) \(workout.shortDay)")` with `.font(.dripCaption(11))`, `.foregroundStyle(Color.drip.coral)`, `.tracking(0.5)`, `.padding(.horizontal, 6)`, `.background(Color.drip.coral.opacity(0.12))`, `.cornerRadius(4)`. Use `.fixedSize(horizontal: true, vertical: false)` so it never wraps mid-chip. The expanded form is the full workout card (mono day+type eyebrow, display title, mono meta line, ↗ trailing). Tap action sets a binding `selectedWorkoutId: UUID?` on the parent — actual sheet routing lives in `CoachReadView`. Add a `#Preview` block with both forms and a mock workout.

---

### Prompt 3.2 — `DocChip` (knowledge, § outlined)

**Dependencies:** 2.1.
**Files to create:** `RunningLog/RunningLog/Coaching/Read/DocChip.swift`.

> Create `RunningLog/RunningLog/Coaching/Read/DocChip.swift`. Same shape as `EvidenceChip` but: inline is `Text("§ \(doc.title)")` with `.foregroundStyle(Color.drip.textPrimary)`, no background fill, 1px border in `Color.drip.divider`, `.cornerRadius(4)`. Expanded is title + category eyebrow + italic excerpt + ↗ trailing. Tap routes to a `DocDetailSheet` (create as a stub for now — just a sheet that displays the full doc content from `coaching_documents.content`). Add a `#Preview`.

---

### Prompt 3.3 — `ReadProse` (paragraph renderer)

**Dependencies:** 3.1, 3.2.
**Files to create:** `RunningLog/RunningLog/Coaching/Read/ReadProse.swift`.

> Create `struct ReadProse: View` that takes `segments: [CoachRead.Segment]`, `workouts: [UUID: TrainingLog]`, `docs: [UUID: CoachingDocument]`. It composes the paragraph using SwiftUI's `Text` concatenation operator (`+`) for plain text + interpolated chips. Where SwiftUI's `Text` interpolation can't fit a custom View, fall back to a `FlowLayout` (use `Layout` protocol for a left-to-right wrapping flow) and render each segment as either `Text` or a chip View. Set `.font(.dripBody(16))`, `.lineSpacing(4)`, `.foregroundStyle(Color.drip.textPrimary)`. Inline chips should sit on the text baseline. Add a `#Preview` with a mixed paragraph using the same sample text from the design mock: "Three good weeks in a row…"

---

### Prompt 3.4 — `CantSeeBlock`, `SourcesPanel`, `ConfidenceBar`

**Dependencies:** 2.1.
**Files to create:** all in `RunningLog/RunningLog/Coaching/Read/`.

> Create three small View files:
>
> **`CantSeeBlock.swift`** — left bar (`Color.drip.textTertiary`, 2pt wide), mono eyebrow on top (the `cantSee.eyebrow`), italic body below (`cantSee.body`) in `.dripBody(13.5)`, ink color. Background `Color.drip.cardBackgroundElevated`. Padding 12pt. Used only when `cantSee != nil`.
>
> **`SourcesPanel.swift`** — `DisclosureGroup` that opens to a `VStack` of expanded `EvidenceChip` (one per workout), expanded `DocChip` (one per doc), and a custom `MemoChip` (mono "♪ \(label)" eyebrow + italic excerpt). Header is "SOURCES · \(count) · WORKOUTS, KNOWLEDGE, VOICE MEMOS" mono. Top/bottom hairline borders matching the design mock.
>
> **`ConfidenceBar.swift`** — left side: mono "CONFIDENCE" eyebrow + sub-line in `dripCaption(10)`. Right side: three small 14×4 rounded rectangles, filled coral (1, 2, or 3 based on level), then mono level label. No interactivity.
>
> Each file has a `#Preview` block with realistic data.

---

## Phase 4 — `CoachReadView` and the reply state (~2 days)

Goal: replace `CoachView`'s body for the self-coached path. The Read is the page; chat is one tool below.

---

### Prompt 4.1 — `CoachReadView` skeleton

**Dependencies:** 2.2, 3.1-3.4.
**Files to create:** `RunningLog/RunningLog/Coaching/Read/CoachReadView.swift`.

> Create `struct CoachReadView: View`. Pull `CoachReadService.shared` into an `@Environment` or use `@State` to observe it directly. Layout (top to bottom in a `ScrollView`):
>
> 1. Plate strip — mono "RUNNING LOG — COACH · THE READ" + "FIG. 14" right-aligned.
> 2. Dateline row — "THU · MAY 14 · WK 9 / 16" + "↗ HISTORY" right-aligned.
> 3. Coach byline — 28pt black circle with coral 1.5pt border and "C" inside, then mono coral "FROM YOUR COACH · THU 7:41 AM".
> 4. Headline (`Color.drip.textPrimary`, 32pt display, line-height 1.02).
> 5. `ReadProse(segments:, workouts:, docs:)`.
> 6. Signature line — italic body 12pt, ink-3, "— posted Thursday morning · 4 min read".
> 7. `CantSeeBlock` if present.
> 8. `SourcesPanel`.
> 9. `ConfidenceBar`.
> 10. Editorial rule (line · dot · line — use the same primitive that exists in TodayHomeView; create one if it doesn't).
> 11. "OPEN THREADS · \(count) OPEN" eyebrow + rows (title + coach-quote excerpt + last-touched timestamp).
> 12. Ask bar pinned at bottom via `.safeAreaInset(edge: .bottom)`.
>
> If `service.todayRead == nil && service.isLoading`, show a skeleton state (gray bars at byline/headline/paragraph positions). If `todayRead == nil && !isLoading && lastError != nil`, show a single-line "Couldn't load today's read. Pull to refresh." with retry. Pull-to-refresh calls `service.refresh()`. No "Hey, I'm Coach"-style intro card — if the user has zero workouts (data_depth = 1), the Read paragraph itself handles the empty case via the prompt (the prompt instructs the model to write "I need a workout to read" in that case).

---

### Prompt 4.2 — Reply state

**Dependencies:** 4.1.
**Files to modify:** `supabase/functions/coaching-agent/index.ts`, `RunningLog/RunningLog/Coaching/Read/CoachReplyView.swift`.

> **Backend:** Add a `format: "editorial" | "chat"` field to the `coaching-agent` request body (default "chat" for backward compat). When `format === "editorial"`, swap the system prompt to a variant of `daily-read.v1.ts` adapted for answering a specific question: open with a one-line answer-as-headline, then 3-5 sentences citing workouts + docs. Response shape matches `CoachRead` but adds a `you: { eyebrow: string, text: string }` field (the original question, echoed back) and a `related_ask: string[]` field (3 follow-up questions grounded in the athlete's data). Add both to the response schema.
>
> **iOS:** Create `CoachReplyView.swift` that takes a `CoachRead` + the original question. Layout:
> 1. Dateline (same as Read).
> 2. "YOU ASKED · THU 8:12 AM" eyebrow.
> 3. The question itself as a 22pt italic display blockquote in `Color.drip.textSecondary`, wrapped in curly quotes.
> 4. Editorial rule.
> 5. Coach byline.
> 6. Answer headline + `ReadProse` paragraph + signature ("— answered in 14s · 2 docs + 1 workout cited" — `signature` is a computed string).
> 7. `ConfidenceBar`.
> 8. "RELATED · ASK NEXT" eyebrow + 3 tappable suggestion rows from `related_ask`.
> 9. Ask bar pinned at bottom with placeholder "Keep going…".
>
> Wire up from `CoachReadView`'s ask bar: submit → push a `CoachReplyView` onto a `NavigationStack`. Persist the reply in memory only (no schema for chat history right now — Phase 5+ if needed).

---

### Prompt 4.3 — Swap `CoachReadView` into `CoachTabView`

**Dependencies:** 4.1.
**Files to modify:** `RunningLog/RunningLog/Coaching/CoachTabView.swift`, `RunningLog/RunningLog/App/RunningLogApp.swift`.

> In `CoachTabView.swift`, find the section that renders `CoachView()` in the self-coached path (around line 114). Replace it with `CoachReadView()`. Leave the coached-mode (athlete invited a human coach) branch alone. Remove the `@State private var viewModel = CoachViewModel()` from `CoachTabView` if no other path needs it; otherwise keep it. Run the app, navigate to the Coach tab, verify the Read renders.
>
> Do **not** delete `CoachView.swift`, `CoachChatViewModel.swift`, `WelcomeCard`, `SuggestionChip` yet — those come out in Phase 5 after one release in production.

---

## Phase 5 — Cleanup (~half day, after staged rollout)

**Run only after Phase 4 has been in production for 2 weeks with no rollback signal.**

---

### Prompt 5.1 — Delete the old chat UI

**Dependencies:** Phase 4 shipped + bake time.
**Files to delete or trim:** several.

> Delete or trim the following — only run after confirming no remaining references via grep:
>
> 1. Delete `RunningLog/RunningLog/Coaching/CoachView.swift` (the chat list view). Keep `CoachChatViewModel.swift` if `CoachReplyService` reuses any of its rate-limit logic — extract that to a shared `CoachRateLimit.swift` first.
> 2. Delete `WelcomeCard`, `SuggestionChip`, `TypingIndicator`, `ChatBubble`, `ChatInputBar` from wherever they live.
> 3. Remove the legacy `coachInsight` and chat-thread columns from the response shape of `coaching-agent` if no callers remain.
> 4. Run `git grep "AI running coach"` and `git grep "Hey, I'm Coach"` and remove every match — these phrases violate the brand voice doc (section 2 + 3.3).
> 5. Update `outputs/IMPLEMENTATIONS.md` (or wherever the design-system → app map is tracked) — mark "Coach iOS" as shipped.

---

## How to test each phase

- **Phase 1** — Hit `coaching-daily-read` with a test user via `curl --service-role`. Inspect the row. Validate paragraph segments parse back into the model. Confirm Gemini returns valid `workout_id`s by checking against `training_logs`.
- **Phase 2** — Unit tests on `CoachRead` decode. Mock the service with a fixture; verify `workoutsById` populates after `refresh()`.
- **Phase 3** — Run each `#Preview` in Xcode Canvas. Snapshot test if `swift-snapshot-testing` is installed.
- **Phase 4** — End-to-end on a TestFlight build. Confirm: morning Read renders, asking a question opens the reply view with citations, pull-to-refresh works, offline shows the cached Read.
- **Phase 5** — Just `grep`. Build clean.

---

## Don'ts

- **Don't use "AI" in any user-facing copy** inside Coach. The model is the engine; the coach is the face. (brand-voice.md §2)
- **Don't show a generic loading spinner** during Read fetch. Show the skeleton lined up where the headline + paragraph will go.
- **Don't allow `Text` markdown rendering for the paragraph.** The model returns structured segments; the citation chips are real Views, not inline markdown.
- **Don't fall back to a "lite" prompt or short context** if Gemini is slow — the Read is a once-a-day creative task and is worth waiting for. Cron has 60s; queue-and-retry if it times out.
- **Don't generate fake citations.** If the model invents a `workout_id` or `doc_id`, the validator in Prompt 1.3 strips it. Better to ship a thinner Read than a Read with a citation that opens to nothing.
