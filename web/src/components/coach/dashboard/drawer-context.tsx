"use client";

import { createContext, useContext, useState, type ReactNode } from "react";
import type { DashboardDay } from "@/lib/coach-dashboard/types";
import { WorkoutDrawer } from "./workout-drawer";

// Shares the drill-down drawer's open/close across the dashboard so the overlay
// bars, the key-session rail, the log rows, and the niggle links can all open
// the same panel without prop-drilling.
const OpenWorkoutContext = createContext<(id: string) => void>(() => {});

export function useOpenWorkout() {
  return useContext(OpenWorkoutContext);
}

export function DrawerProvider({
  days,
  children,
  athleteId,
}: {
  days: DashboardDay[];
  children: ReactNode;
  /** Live athlete id — enables the drawer's on-demand "generate the read".
   *  Absent in static previews. */
  athleteId?: string;
}) {
  const [openId, setOpenId] = useState<string | null>(null);
  const day = openId ? days.find((d) => d.id === openId) ?? null : null;

  return (
    <OpenWorkoutContext.Provider value={setOpenId}>
      {children}
      <WorkoutDrawer day={day} onClose={() => setOpenId(null)} athleteId={athleteId} />
    </OpenWorkoutContext.Provider>
  );
}
