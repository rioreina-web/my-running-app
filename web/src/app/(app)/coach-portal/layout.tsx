import { CoachPortalChrome } from "@/components/coach/coach-portal-chrome";

// Direction I is switched on here, and only here. `data-skin="wild"` is the
// scope selector the token block in globals.css hangs off, so the coach portal
// repaints without touching Log, Trends, Plan, or the app chrome. Same call
// DripTheme.swift makes on iOS, for the same reason.
//
// The skin wraps everything; the frame does not — see CoachPortalChrome, which
// also owns the negative margin that cancels the app <main> padding. That has
// to be conditional too: the plan builder already cancels it itself, so
// applying it here as well would pull the surface out twice.
export default function CoachPortalLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <div data-skin="wild" className="min-h-full">
      <CoachPortalChrome>{children}</CoachPortalChrome>
    </div>
  );
}
