-- athlete_signature_observations — the Athlete Signature store (addendum §5)
--
-- The second learning layer on top of the AI Coaching Profile. Where the
-- profile learns HOW to talk to an athlete, the signature stores WHAT the AI
-- has discovered to be true about their training — patterns mined
-- algorithmically from the athlete's own history (addendum §0).
--
-- Design principle: OPEN DISCOVERY, STRUCTURED EVIDENCE. The hypothesis space
-- is combinatorial and unlisted (the grammar generates it — addendum §4.1),
-- but every finding is a first-class, auditable record: it carries its own
-- statistics (instance count, base vs conditional rate, effect size, example
-- workout ids), a confidence grade, and a status that DECAYS when the data
-- stops supporting it (addendum §6).
--
-- Two tables:
--   athlete_signature_observations — one row per (athlete, pattern_key),
--     the current state of a discovered pattern (re-detections UPDATE in
--     place, never duplicate).
--   athlete_signature_events — append-only audit of every status/evidence
--     transition (same shape idea as athlete_ai_profile_events in the base
--     spec: field / old / new / source / evidence / actor).
--
-- Hard rules honored:
--   #1  RLS ships in this same migration.
--   #2  No medical claim lives here; the detection-not-diagnosis contract is
--       enforced in the code that reads/phrases these rows (niggle gate, §7).
--   #4/#5 Miner writes are service-role only; migrations are append-only.
--   #9  Reaches prod only via `supabase db push` from a committed SHA.
--
-- RLS mirrors body_mentions / athlete_state: service-role full access (the
-- weekly miner runs under service role on the cron path), athlete reads own
-- rows, athlete UPDATE limited to the dismiss transition, coach reads/vets
-- via current_coach_id(). No client INSERT policy — the miner is the only
-- writer of new observations.

-- ── Observations ─────────────────────────────────────────────────────────────

create table if not exists public.athlete_signature_observations (
  id uuid primary key default gen_random_uuid(),
  user_id text not null,

  -- Canonical machine form of the pattern, e.g. `rest_day->quality_exec@+2d`.
  -- One row per (user, pattern_key): re-detections upsert in place.
  pattern_key text not null,

  -- Closed display/gating vocabulary (addendum §5). Drives Model of You
  -- grouping and the niggle gate (§7). Enforced by CHECK so a bad category
  -- can never reach the athlete-facing surface.
  category text not null,

  -- Athlete-facing sentence (LLM output in S2; NULL while the miner runs
  -- dark in S1). Regenerated when the evidence materially updates.
  statement text,

  -- The full statistical case for the pattern. Shape:
  --   { n, base_rate, conditional_rate, effect, effect_unit,
  --     window_start, window_end, example_log_ids[], last_instance_at,
  --     split_half:{ first:{effect,n}, second:{effect,n} } }
  -- Everything a coach (or the athlete tapping "see the runs") needs to
  -- audit the claim. Never a bare assertion.
  evidence jsonb not null default '{}'::jsonb,

  confidence text not null default 'low',
  status text not null default 'candidate',

  -- Set only on coach vet actions (confirm / dismiss / annotate). coach_id is
  -- a UUID referencing coach_profiles.id, matching the codebase convention.
  coach_id uuid,
  coach_note text,

  first_detected_at timestamptz not null default now(),
  last_confirmed_at timestamptz,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  -- Closed vocabularies. Kept in the DB (not just code) because these gate a
  -- surface the athlete sees — a bad value must be rejected at write time.
  constraint athlete_signature_category_check check (category in (
    'performance', 'recovery', 'load_response',
    'mood', 'niggle_assoc', 'schedule', 'environment'
  )),
  constraint athlete_signature_confidence_check check (confidence in (
    'low', 'medium', 'high'
  )),
  constraint athlete_signature_status_check check (status in (
    'candidate', 'active', 'fading', 'refuted',
    'athlete_dismissed', 'coach_confirmed', 'coach_dismissed'
  ))
);

-- One live row per pattern per athlete — the miner upserts on this key.
create unique index if not exists athlete_signature_observations_unique_key
  on public.athlete_signature_observations (user_id, pattern_key);

-- The athlete-facing read: "my active patterns, best first."
create index if not exists athlete_signature_observations_user_status
  on public.athlete_signature_observations (user_id, status, confidence desc);

alter table public.athlete_signature_observations enable row level security;

create policy "Service role full access to signature observations"
  on public.athlete_signature_observations
  for all
  using (auth.role() = 'service_role');

create policy "Users read own signature observations"
  on public.athlete_signature_observations
  for select
  using (user_id = (auth.uid())::text);

-- Athlete UPDATE is intentionally NOT granted here. The only athlete-driven
-- mutation is the dismiss transition, which goes through a service-role edge
-- function (so it can append an audit event atomically) — mirroring the
-- coachable_moments "no client INSERT" discipline. Adding a scoped athlete
-- UPDATE policy later would require a WITH CHECK that pins status to
-- 'athlete_dismissed' only; deferred to the edge-function path on purpose.

-- Coaches see their athletes' rows (including candidates — coaches look
-- further down the funnel than athletes, §7) and vet them. current_coach_id()
-- is the SECURITY DEFINER helper (hard rule #6) — never a raw subquery.
create policy "Coaches read their athletes signature observations"
  on public.athlete_signature_observations
  for select
  using (
    user_id in (
      select car.athlete_user_id
      from public.coach_athlete_relationships car
      where car.coach_id = current_coach_id()
        and car.status = 'active'
    )
  );

create policy "Coaches vet their athletes signature observations"
  on public.athlete_signature_observations
  for update
  using (
    user_id in (
      select car.athlete_user_id
      from public.coach_athlete_relationships car
      where car.coach_id = current_coach_id()
        and car.status = 'active'
    )
  );

-- ── Events (append-only audit) ───────────────────────────────────────────────

create table if not exists public.athlete_signature_events (
  id uuid primary key default gen_random_uuid(),
  observation_id uuid not null
    references public.athlete_signature_observations (id) on delete cascade,
  user_id text not null,

  -- What changed: 'status' | 'confidence' | 'evidence' | 'statement' |
  -- 'coach_note'. Kept as free TEXT (not a CHECK) so new tracked fields
  -- don't need a migration — the writer controls the vocabulary.
  field text not null,
  old_value text,
  new_value text,

  -- Who/what drove the transition: 'miner' | 'athlete' | 'coach' | 'decay'.
  source text not null,
  -- coach_profiles.id when source = 'coach'; NULL otherwise.
  actor_id uuid,

  -- Snapshot of the evidence at transition time — so the audit trail is
  -- self-contained even after the observation's evidence is overwritten.
  evidence jsonb,

  created_at timestamptz not null default now()
);

create index if not exists athlete_signature_events_observation
  on public.athlete_signature_events (observation_id, created_at desc);

create index if not exists athlete_signature_events_user
  on public.athlete_signature_events (user_id, created_at desc);

alter table public.athlete_signature_events enable row level security;

create policy "Service role full access to signature events"
  on public.athlete_signature_events
  for all
  using (auth.role() = 'service_role');

create policy "Users read own signature events"
  on public.athlete_signature_events
  for select
  using (user_id = (auth.uid())::text);

create policy "Coaches read their athletes signature events"
  on public.athlete_signature_events
  for select
  using (
    user_id in (
      select car.athlete_user_id
      from public.coach_athlete_relationships car
      where car.coach_id = current_coach_id()
        and car.status = 'active'
    )
  );

-- keep updated_at honest on the observations table
create or replace function public.touch_athlete_signature_observations()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_touch_athlete_signature_observations
  on public.athlete_signature_observations;

create trigger trg_touch_athlete_signature_observations
  before update on public.athlete_signature_observations
  for each row
  execute function public.touch_athlete_signature_observations();
