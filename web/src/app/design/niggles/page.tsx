import type { Metadata } from "next";

import NigglesDashboard from "./niggles-client";

/* ════════════════════════════════════════════════════════════════════
   NIGGLES · v2 PROTOTYPE
   A niggles-primary dashboard: body-part mentions auto-extracted from
   voice logs, plotted over time, with training as a switchable
   overlay. Recurrence and resolution are derived by fixed rule.

   This is a DESIGN PREVIEW with mock data. No Supabase wiring.
   Spec: outputs/niggles-v2-dashboard-2026-08-23.md
   ════════════════════════════════════════════════════════════════════ */

export const metadata: Metadata = {
  title: "Niggles · v2 prototype",
  description:
    "Body-part mentions from voice logs, over time, with a training overlay. Design preview with mock data.",
  robots: { index: false, follow: false },
};

export default function NigglesPreviewPage() {
  return <NigglesDashboard />;
}
