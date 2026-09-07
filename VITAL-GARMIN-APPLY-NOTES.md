# Garmin via Vital / Junction — apply notes

*Placed 2026-07-23. Mirrors the repo's existing `APPLY-NOTES.md` + `*.patch` convention.*

## What was placed automatically (new, untracked — safe/additive)

- `supabase/migrations/20260723180000_vital_credentials.sql`
- `supabase/functions/vital-connect/index.ts`
- `supabase/functions/vital-webhook/index.ts`

These are purely new files. They do **not** modify any tracked file. They show as `??` (untracked) in `git status`.

## What you apply by hand (two tracked files)

I did **not** edit these automatically. `SettingsView.swift` currently has your uncommitted work on branch `fix/voice-memo-run-linking`, and `VitalManager.swift`, while clean, shouldn't be silently mixed into that branch. Apply these when you move the Garmin work onto its own branch.

### 1. `RunningLog/RunningLog/Health/VitalManager.swift`

**a) Base URL → current Junction US host:**
```swift
// BEFORE
private let baseURL = "https://api.sandbox.tryvital.io/v2"
// AFTER
private let baseURL = "https://api.sandbox.us.junction.com/v2"
```

**b) Un-stub the network call.** Delete the stub that returns `nil` (and its "trial ended" comment block), then rename the parked real one:
```swift
// DELETE:  private func vitalRequest(url _:, timeout _:) async -> Data? { return nil }
// RENAME:  vitalRequest_DISABLED  ->  vitalRequest
```

**c) Make the user id settable (needed for multi-user):**
```swift
// BEFORE
private let userId: String = Bundle.main.infoDictionary?["VITAL_USER_ID"] as? String ?? ""
// AFTER
var userId: String = Bundle.main.infoDictionary?["VITAL_USER_ID"] as? String ?? ""
```

### 2. `RunningLog/RunningLog/Shared/SettingsView.swift` — add next to "Sync from Strava"

```swift
@State private var isConnectingGarmin = false
@State private var garminConnectMessage: String?

private func connectGarmin() async {
    isConnectingGarmin = true
    garminConnectMessage = nil
    defer { isConnectingGarmin = false }

    struct ConnectBody: Encodable { let provider: String }
    struct ConnectResponse: Decodable {
        let vital_user_id: String?
        let link_web_url: String?
        let error: String?
    }

    do {
        let response: ConnectResponse = try await supabase.functions.invoke(
            "vital-connect",
            options: FunctionInvokeOptions(body: ConnectBody(provider: "garmin"))
        )
        if let err = response.error { garminConnectMessage = "Error: \(err)"; return }
        if let vid = response.vital_user_id { VitalManager.shared.userId = vid }
        if let s = response.link_web_url, let url = URL(string: s) {
            await UIApplication.shared.open(url)
            garminConnectMessage = "Opening Garmin sign-in…"
        } else {
            garminConnectMessage = "Couldn't get a connection link."
        }
    } catch {
        Log.app.error("Garmin connect failed: \(error.localizedDescription)")
        garminConnectMessage = "Failed: \(error.localizedDescription)"
    }
}
```

```swift
Button { Task { await connectGarmin() } } label: {
    HStack {
        Text("Connect Garmin")
        Spacer()
        if isConnectingGarmin { ProgressView() }
    }
}
.disabled(isConnectingGarmin)
if let msg = garminConnectMessage {
    Text(msg).font(.footnote).foregroundStyle(.secondary)
}
```

## Deploy (from a committed SHA — hard rule #9; do NOT apply via MCP)

**Secrets** (Supabase Vault, never committed):
```bash
supabase secrets set VITAL_API_KEY=sk_us_...your_sandbox_key...
supabase secrets set VITAL_BASE_URL=https://api.sandbox.us.junction.com/v2
supabase secrets set VITAL_WEBHOOK_SECRET=whsec_...   # Junction dashboard → Webhooks → Signing Secret
```

**Functions:**
```bash
supabase functions deploy vital-connect
supabase functions deploy vital-webhook --no-verify-jwt   # ← REQUIRED: Junction sends no JWT; the Svix signature is the auth
```

**Migration:**
```bash
supabase db push
```

**Junction dashboard:**
1. Enable **Garmin** for your team.
2. Webhooks → add endpoint: `https://<your-project-ref>.supabase.co/functions/v1/vital-webhook`
3. Copy the endpoint's **Signing Secret** into `VITAL_WEBHOOK_SECRET` (above), redeploy the function.

## Test order

1. Prove the key with curl (create-user → demo connect → summary) — see the setup runbook.
2. Deploy the functions + migration.
3. Tail logs: `supabase functions logs vital-webhook`.
4. Tap "Connect Garmin" in the app, log into a real Garmin. Expect first a `provider.connection.created` event, then `daily.data.workouts.created` events → new rows in `training_logs` with `source='garmin'`.

## Known gaps / next steps

- **Voice-orphan reconcile + stream backfill** aren't in the webhook yet (there's a `NOTE` comment marking where). Best fix: lift `reconcileVoiceOrphan` out of `strava-sync/index.ts` into `_shared/` so both sync paths share one copy; add a `/timeseries/workouts/{id}/stream` backfill into `external_streams`.
- **Two API details to confirm on a live sandbox call** (they'll surface instantly in the curl test): the `/user/resolve/{client_user_id}` fallback path, and whether the link response field is `link_web_url` (the code already accepts `link_url` as a fallback).
- **Production hardening:** move all Junction reads server-side and remove the `sk_` key from the app bundle (the security note from the setup runbook).

## Branch hygiene

These files are untracked on `fix/voice-memo-run-linking`. Untracked files follow you across branches — create a dedicated branch (e.g. `garmin-vital`) and commit them there; don't fold them into the voice-memo branch's commit.

## Heads-up: git lock in the connected folder

While placing these files, `git` reported a `.git/index.lock` permission warning — git writes from the Cowork bridge can be flaky. The files wrote fine (they're in the working tree, not `.git`). Run your own `git` from Terminal; if it complains about a lock, remove a stale `.git/index.lock` yourself.
