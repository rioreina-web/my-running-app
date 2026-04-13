import { createClient } from "@/lib/supabase/server";
import { Card } from "@/components/ui/card";
import { SectionHeader } from "@/components/ui/section-header";
import { EditorialDivider } from "@/components/ui/editorial-divider";

interface UserProfile {
  easy_pace_min: number | null;
  easy_pace_max: number | null;
  tempo_pace: number | null;
  interval_pace: number | null;
  race_5k_pace: number | null;
  race_10k_pace: number | null;
  race_half_pace: number | null;
  race_marathon_pace: number | null;
}

const RACE_DISTANCES = [
  { label: "5K", miles: 3.1 },
  { label: "10K", miles: 6.2 },
  { label: "Half Marathon", miles: 13.1 },
  { label: "Marathon", miles: 26.2 },
];

export default async function PaceChartPage() {
  const supabase = await createClient();

  const { data: profile } = await supabase
    .from("user_profiles")
    .select(
      "easy_pace_min, easy_pace_max, tempo_pace, interval_pace, race_5k_pace, race_10k_pace, race_half_pace, race_marathon_pace"
    )
    .limit(1)
    .single();

  return (
    <div className="mx-auto max-w-3xl space-y-8">
      <h1 className="font-display text-3xl text-text-primary">Pace Chart</h1>

      {/* Training zones */}
      <div>
        <SectionHeader title="Training Zones" />
        <Card className="mt-4" padding="sm">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-divider">
                <th className="px-4 py-3 text-left font-body text-[11px] font-medium tracking-[1.5px] uppercase text-text-secondary">
                  Zone
                </th>
                <th className="px-4 py-3 text-right font-body text-[11px] font-medium tracking-[1.5px] uppercase text-text-secondary">
                  Pace /mi
                </th>
              </tr>
            </thead>
            <tbody className="divide-y divide-divider">
              <PaceRow
                zone="Easy"
                pace={
                  profile?.easy_pace_min && profile?.easy_pace_max
                    ? `${formatPace(profile.easy_pace_min)} – ${formatPace(
                        profile.easy_pace_max
                      )}`
                    : null
                }
                color="text-mood-positive"
              />
              <PaceRow
                zone="Tempo"
                pace={
                  profile?.tempo_pace
                    ? formatPace(profile.tempo_pace)
                    : null
                }
                color="text-mood-tired"
              />
              <PaceRow
                zone="Interval"
                pace={
                  profile?.interval_pace
                    ? formatPace(profile.interval_pace)
                    : null
                }
                color="text-mood-struggling"
              />
            </tbody>
          </table>
        </Card>
      </div>

      <EditorialDivider />

      {/* Race equivalents */}
      <div>
        <SectionHeader title="Race Pace Equivalents" />
        <Card className="mt-4" padding="sm">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-divider">
                <th className="px-4 py-3 text-left font-body text-[11px] font-medium tracking-[1.5px] uppercase text-text-secondary">
                  Distance
                </th>
                <th className="px-4 py-3 text-right font-body text-[11px] font-medium tracking-[1.5px] uppercase text-text-secondary">
                  Pace /mi
                </th>
                <th className="px-4 py-3 text-right font-body text-[11px] font-medium tracking-[1.5px] uppercase text-text-secondary">
                  Est. Time
                </th>
              </tr>
            </thead>
            <tbody className="divide-y divide-divider">
              {RACE_DISTANCES.map((race) => {
                const paceKey = `race_${race.label
                  .toLowerCase()
                  .replace(/ /g, "_")
                  .replace("half_marathon", "half")
                  .replace("5k", "5k")
                  .replace("10k", "10k")}_pace` as keyof UserProfile;
                const paceVal = profile?.[paceKey] as number | null;

                return (
                  <tr key={race.label}>
                    <td className="px-4 py-3 font-medium text-text-primary">
                      {race.label}
                    </td>
                    <td className="px-4 py-3 text-right font-mono text-coral">
                      {paceVal ? formatPace(paceVal) : "--"}
                    </td>
                    <td className="px-4 py-3 text-right font-mono text-text-secondary">
                      {paceVal ? formatFinishTime(paceVal, race.miles) : "--"}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </Card>
      </div>

      <EditorialDivider />

      <Card>
        <p className="text-center text-sm italic text-text-tertiary">
          Pace data is pulled from your user profile. Update paces in the iOS
          app or Settings.
        </p>
      </Card>
    </div>
  );
}

function PaceRow({
  zone,
  pace,
  color,
}: {
  zone: string;
  pace: string | null;
  color: string;
}) {
  return (
    <tr>
      <td className="px-4 py-3">
        <span className={`font-medium ${color}`}>{zone}</span>
      </td>
      <td className="px-4 py-3 text-right font-mono text-text-primary">
        {pace || "--"}
      </td>
    </tr>
  );
}

function formatPace(minutesPerMile: number): string {
  const mins = Math.floor(minutesPerMile);
  const secs = Math.round((minutesPerMile - mins) * 60);
  return `${mins}:${secs.toString().padStart(2, "0")}`;
}

function formatFinishTime(pacePerMile: number, miles: number): string {
  const totalMinutes = pacePerMile * miles;
  const hours = Math.floor(totalMinutes / 60);
  const mins = Math.floor(totalMinutes % 60);
  const secs = Math.round((totalMinutes % 1) * 60);
  if (hours > 0) {
    return `${hours}:${mins.toString().padStart(2, "0")}:${secs
      .toString()
      .padStart(2, "0")}`;
  }
  return `${mins}:${secs.toString().padStart(2, "0")}`;
}
