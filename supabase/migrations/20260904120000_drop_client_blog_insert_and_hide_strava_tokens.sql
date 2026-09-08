-- 2026-09-03 security audit — two client-surface holes with no client behind them.
--
-- Both were verified against the live project (aqdijapxmjqaetursrde) and
-- against every client in this repo before writing. Both are idempotent and
-- guard on existence, so they are safe on a fresh local stack too.
--
-- ── 1. blog_posts: any signed-in user can publish to the public site ────────
--
-- Live policy set on blog_posts is three rows: two SELECT policies scoped to
-- status = 'published', and "Authenticated users can insert posts" with
-- WITH CHECK (author_id = auth.uid()::text). That check stops you forging
-- somebody else's byline; it does NOT stop you setting status = 'published'.
-- So any account created through the open signup form can POST to
-- /rest/v1/blog_posts and put content on the public marketing site. The blog
-- pages render post.content through DOMPurify, so this is not stored XSS —
-- it is phishing links and SEO spam served from the product's own domain.
--
-- Nothing in the product needs this policy. The only client references to
-- blog_posts anywhere in the repo are two SELECTs:
--   web/src/app/(public)/blog/page.tsx        (list, status = 'published')
--   web/src/app/(public)/blog/[slug]/page.tsx (one post, status = 'published')
-- There is no authoring UI, and no iOS or edge-function writer. Posts are
-- authored out-of-band (dashboard / service role), which bypasses RLS
-- entirely and is therefore unaffected by this change.
--
-- History: 20260313100000 (lock_down_rls) already dropped this policy; it was
-- reintroduced by 20260609233553 while tightening the author_id check. This
-- drops it without a replacement — if an admin authoring surface is ever
-- built, give it its own policy gated on an explicit author allowlist rather
-- than on "is authenticated".

DO $$
BEGIN
    IF to_regclass('public.blog_posts') IS NOT NULL THEN
        DROP POLICY IF EXISTS "Authenticated users can insert posts" ON public.blog_posts;
    END IF;
END $$;

-- ── 2. strava_credentials: OAuth tokens readable by the token's owner ───────
--
-- RLS is correct here (owner-only), so this is not a cross-user leak: it lets
-- an athlete read their own Strava access_token and refresh_token over
-- PostgREST. No client ever does. The only readers are two edge functions,
-- strava-sync and strava-test-pull, both of which use the service-role key
-- and bypass grants and RLS alike — so this change cannot affect them.
--
-- The reason to close it anyway: refresh_token is long-lived, and Strava
-- rotates it on every refresh, so a copy pulled out through the API keeps
-- working against the athlete's Strava account independently of this app.
-- A token the product never hands to the client should not be fetchable by
-- the client.
--
-- Postgres will not let a column-level REVOKE subtract from a table-level
-- grant, so the table grant is dropped and re-issued per column. The
-- non-secret columns stay readable, so a future "Strava connected?" indicator
-- needs no migration — only access_token and refresh_token are withheld.

DO $$
BEGIN
    IF to_regclass('public.strava_credentials') IS NOT NULL THEN
        REVOKE SELECT ON public.strava_credentials FROM anon, authenticated;

        GRANT SELECT (
            user_id,
            strava_athlete_id,
            expires_at,
            scope,
            last_refreshed_at,
            created_at
        ) ON public.strava_credentials TO authenticated;
    END IF;
END $$;
