-- A trigger function has no business being reachable at /rest/v1/rpc/.
-- The trigger itself still fires; only the RPC surface goes away.
REVOKE ALL ON FUNCTION public.fn_recompute_pace_bins() FROM PUBLIC, anon, authenticated;;
