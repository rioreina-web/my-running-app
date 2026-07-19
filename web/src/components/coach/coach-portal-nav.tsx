"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

const TABS = [
  { href: "/coach-portal/athletes", label: "Athletes" },
  { href: "/coach-portal/plans", label: "Training Plans" },
  { href: "/coach-portal/workouts", label: "Workout Library" },
];

export function CoachPortalNav() {
  const pathname = usePathname();

  return (
    <nav className="flex items-center gap-1 border-b border-[var(--color-divider)] -mt-2 mb-4">
      {TABS.map((tab) => {
        const isActive = pathname.startsWith(tab.href);
        return (
          <Link
            key={tab.href}
            href={tab.href}
            className={`-mb-px border-b-2 px-4 py-2.5 font-mono text-[11px] uppercase tracking-[0.12em] transition-colors ${
              isActive
                ? "border-coral text-coral"
                : "border-transparent text-text-secondary hover:text-text-primary"
            }`}
          >
            {tab.label}
          </Link>
        );
      })}
    </nav>
  );
}
