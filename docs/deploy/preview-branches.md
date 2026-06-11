# Preview branches (Phase 4.2) — setup notes

Decision (locked 2026-06-10): Supabase branching for per-PR isolation.

**Mechanism: use the official Supabase GitHub integration**, not a
hand-rolled workflow. Dashboard → Project Settings → Integrations →
GitHub → connect `rioreina-web/my-running-app`, enable "Supabase branching"
on PRs. It then automatically: creates a preview branch per PR, applies
`supabase/migrations/` to it, reports status as a PR check, and tears the
branch down on merge/close. Hand-rolling the same in Actions duplicates
this fragilely.

**Cost (verified via API 2026-06-11):** $0.01344/hour per active branch
(~$0.32/day). A PR open for two days costs well under a dollar. Teardown
on close is what keeps this bounded — verify it's enabled.

**Plan requirement:** the org is on the FREE plan; branching requires a
paid plan. Factor ~$25/mo (Pro) + branch-hours into the Phase 4 decision.
This is also the plan tier that takes "Supabase prod config in dev mode"
(roadmap Phase 5.2) seriously — likely worth it regardless.

**What stays in our Actions:** the smoke tests. Point
`.github/scripts/post_deploy_smoke.sh` at the preview branch URL (the
integration exposes branch credentials per PR) so a PR is green only if a
real isolated copy of prod accepted the change — then flip deploy.yml's
trigger to `push: branches [main]` (Phase 4.1) for true CD.

**Migration caveat:** preview branches apply the repo's migration files
from scratch. Files recovered from prod (e.g. `20260128_fix_vector_search.sql`)
and re-stamped ones must therefore be runnable standalone in order — if a
branch fails to provision, the failing migration is the bug; fix the file,
never the prod ledger.
