-- Drop the unsecured ghost table `public._csv_export_tmp`.
--
-- Why: the security advisor flagged this table as RLS-disabled in the public
-- schema (lint 0013_rls_disabled_in_public, level ERROR/critical) — it is fully
-- exposed to the anon and authenticated roles, so anyone with the anon key can
-- read or modify every row. It is NOT defined in any prior migration; it was
-- created ad-hoc against prod (a CSV-export scratch table) and never cleaned
-- up. A codebase-wide search (edge functions, web, iOS) found zero readers, so
-- dropping it is safe and closes the exposure rather than locking it behind an
-- empty RLS policy.
--
-- Append-only per hard rule #5. Reaches prod via `supabase db push` per rule #9.

DROP TABLE IF EXISTS public._csv_export_tmp;
