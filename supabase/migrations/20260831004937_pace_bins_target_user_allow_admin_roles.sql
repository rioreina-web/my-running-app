-- Trusted callers are service_role by JWT (edge functions) or by database role
-- (cron, migrations, admin tooling). Everyone else gets their own data, whatever
-- they pass for p_user_id.
CREATE OR REPLACE FUNCTION public.pace_bins_target_user(p_user_id text)
RETURNS text
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
    SELECT CASE
             WHEN p_user_id IS NOT NULL
                  AND (auth.role() = 'service_role'
                       OR current_user IN ('service_role', 'postgres', 'supabase_admin'))
             THEN p_user_id
             ELSE (auth.uid())::text
           END;
$$;;
