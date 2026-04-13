import { createClient } from "@/lib/supabase/server";
import { Card } from "@/components/ui/card";
import { SectionHeader } from "@/components/ui/section-header";
import { EditorialDivider } from "@/components/ui/editorial-divider";

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
    <div className="mx-auto max-w-3xl space-y-8">
      <h1 className="font-display text-3xl text-text-primary">Settings</h1>

      {/* Profile */}
      <div>
        <SectionHeader title="Profile" />
        <Card className="mt-4 space-y-0">
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
              last
            />
          )}
        </Card>
      </div>

      <EditorialDivider />

      {/* App info */}
      <div>
        <SectionHeader title="App Info" />
        <Card className="mt-4 space-y-0">
          <SettingRow label="Version" value="Web 1.0.0" />
          <SettingRow label="Platform" value="Next.js + Supabase" last />
        </Card>
      </div>

      <EditorialDivider />

      <Card>
        <p className="text-center text-sm italic text-text-tertiary">
          Profile editing is managed through the iOS app. Changes sync
          automatically.
        </p>
      </Card>
    </div>
  );
}

function SettingRow({
  label,
  value,
  last = false,
}: {
  label: string;
  value: string;
  last?: boolean;
}) {
  return (
    <div
      className={`flex items-center justify-between py-3 px-1 ${
        last ? "" : "border-b border-divider"
      }`}
    >
      <span className="text-sm text-text-secondary">{label}</span>
      <span className="font-mono text-sm text-text-primary">{value}</span>
    </div>
  );
}
