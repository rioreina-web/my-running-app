import type { Metadata } from "next";
import { CoachAthleteDashboard } from "@/components/coach/dashboard/coach-dashboard";
import { getAthleteDashboard } from "@/lib/coach-dashboard/get-dashboard";

export const metadata: Metadata = {
  title: "Coach athlete dashboard · preview",
  description: "Phase 1 coach athlete deep-dive, rendered from fixtures.",
  robots: { index: false, follow: false },
};

/**
 * Design preview for the Phase 1 coach athlete dashboard.
 *
 * A server component that fetches the dashboard payload and hands it to the
 * client view. Today `getAthleteDashboard` returns Maya fixtures; when it starts
 * returning real Supabase rows this page (and the components) are unchanged —
 * only the data source moves. This route touches no real data.
 */
export default async function CoachDashboardPreview() {
  const data = await getAthleteDashboard("maya");
  return (
    // data-skin="wild" mirrors (app)/coach-portal/layout.tsx. Without it the
    // preview renders the editorial skin and every .drip-* role goes inert —
    // i.e. it previews a page that does not exist.
    <div data-skin="wild" className="min-h-screen bg-bg-base text-text-primary">
      <CoachAthleteDashboard data={data} />
    </div>
  );
}
