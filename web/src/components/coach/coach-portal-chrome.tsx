"use client";

import { usePathname } from "next/navigation";
import { CoachPortalNav } from "@/components/coach/coach-portal-nav";

// Some coach surfaces are full-bleed editing environments rather than pages in
// the portal: the plan builder frames itself with its own PlateStrip, cancels
// the app's <main> padding with -m-4/-m-6, and sizes itself to the viewport.
// Wrapping one of those in the portal's own strip + padding stacks two plate
// strips and double-cancels the margin, which is what made the builder's header
// overlap the nav.
//
// So the chrome is conditional and the skin is not: everything under
// /coach-portal renders Direction I, but only browsable pages get the frame.
const FULL_BLEED = ["/builder"];

export function CoachPortalChrome({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  const isFullBleed = FULL_BLEED.some((seg) => pathname.includes(seg));

  // Full-bleed surfaces cancel the app <main> padding themselves. Doing it
  // here as well would pull them out twice.
  if (isFullBleed) return <>{children}</>;

  return (
    <div className="-m-4 px-7 pb-16 md:-m-6">
      <CoachPortalNav />
      {children}
    </div>
  );
}
