"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

const TABS = [
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
            className={`px-4 py-2.5 text-sm font-medium transition-colors border-b-2 -mb-px ${
              isActive
                ? "text-[var(--color-coral)] border-[var(--color-coral)]"
                : "text-[var(--color-text-secondary)] border-transparent hover:text-[var(--color-text-primary)]"
            }`}
          >
            {tab.label}
          </Link>
        );
      })}
    </nav>
  );
}
