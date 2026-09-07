"use client";

import { useState } from "react";
import { WorkoutDrawer } from "@/components/coach/dashboard/workout-drawer";
import { PREVIEW_JUL11_LONG_RUN } from "@/lib/coach-dashboard/preview-fixtures";

/**
 * Design preview for the redesigned coach WorkoutDrawer (FIG 24).
 *
 * Renders the production drawer with the canonical Jul 11 long-run fixture so
 * the ten-section redesign can be reviewed in the browser without live data.
 * Static preview only — no Supabase, no auth gate needed for the fixture.
 * Route: /coach-portal/workout-drawer-preview
 */
export default function WorkoutDrawerPreviewPage() {
  const [open, setOpen] = useState(true);

  return (
    <main className="mx-auto min-h-screen max-w-3xl px-6 py-16">
      <p className="font-mono text-[10px] font-medium uppercase tracking-[0.14em] text-text-secondary">
        Post Run Drip · Coach portal
      </p>
      <h1 className="mt-3 font-display text-[40px] font-bold leading-[1.05] text-text-primary">
        Workout drawer, re-cut.
      </h1>
      <p className="mt-4 max-w-xl font-body text-[15px] italic leading-relaxed text-text-secondary">
        The key-session drill-down, rebuilt to answer the coach&rsquo;s five
        questions in order across ten sections. This is the production component
        rendered with the canonical Jul 11 long-run fixture — the same run drawn
        in FIG 24.
      </p>

      <button
        type="button"
        onClick={() => setOpen(true)}
        className="mt-8 rounded-[10px] bg-coral px-5 py-3 font-display text-[15px] font-semibold text-white shadow-[0_4px_12px_rgba(212,89,42,0.3)] hover:bg-coral-light"
      >
        Open the drawer
      </button>

      <WorkoutDrawer day={open ? PREVIEW_JUL11_LONG_RUN : null} onClose={() => setOpen(false)} />
    </main>
  );
}
