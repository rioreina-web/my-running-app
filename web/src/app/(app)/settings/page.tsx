import { createClient } from "@/lib/supabase/server";

interface UserProfile {
  display_name: string | null;
  email: string | null;
  unit_preference: string | null;
  created_at: string | null;
}

export default async function SettingsPage() {
  const supabase = await createClient();

  const { data: profile } = await supabase
    .from("user_profiles")
    .select("display_name, email, unit_preference, created_at")
    .limit(1)
    .single();

  return (
    <div className="mx-auto max-w-3xl space-y-6">
      <h1 className="font-display text-3xl tracking-wider text-text-primary">
        SETTINGS
      </h1>

      {/* Profile */}
      <div>
        <h2 className="mb-3 font-mono text-xs tracking-widest text-text-tertiary">
          PROFILE
        </h2>
        <div className="rounded-xl border border-bg-elevated bg-bg-card p-4 space-y-3">
          <SettingRow
            label="Name"
            value={profile?.display_name || "Not set"}
          />
          <SettingRow label="Email" value={profile?.email || "Not set"} />
          <SettingRow
            label="Units"
            value={profile?.unit_preference || "miles"}
          />
          {profile?.created_at && (
            <SettingRow
              label="Member since"
              value={new Date(profile.created_at).toLocaleDateString("en-US", {
                month: "long",
                year: "numeric",
              })}
            />
          )}
        </div>
      </div>

      {/* App info */}
      <div>
        <h2 className="mb-3 font-mono text-xs tracking-widest text-text-tertiary">
          APP INFO
        </h2>
        <div className="rounded-xl border border-bg-elevated bg-bg-card p-4 space-y-3">
          <SettingRow label="Version" value="Web 1.0.0" />
          <SettingRow label="Platform" value="Next.js + Supabase" />
        </div>
      </div>

      <div className="rounded-xl border border-bg-elevated bg-bg-card p-4 text-center text-xs text-text-tertiary">
        Profile editing is managed through the iOS app. Changes sync
        automatically.
      </div>
    </div>
  );
}

function SettingRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-center justify-between border-b border-bg-elevated pb-3 last:border-0 last:pb-0">
      <span className="text-sm text-text-secondary">{label}</span>
      <span className="font-mono text-sm text-text-primary">{value}</span>
    </div>
  );
}
