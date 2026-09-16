"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

// Roster first. The portal used to land on the plan library — you opened your
// coaching tool and got a filing cabinet. The first thing a coach needs is
// who needs them today.
const TABS = [
  { href: "/coach-portal/athletes", label: "Roster" },
  { href: "/coach-portal/plans", label: "Plans" },
  { href: "/coach-portal/workouts", label: "Library" },
];

export function CoachPortalNav() {
  const pathname = usePathname();

  return (
    <>
      {/* Plate strip — the surface names itself, the way every iOS screen opens. */}
      <div
        className="flex items-center gap-[10px] py-[14px]"
        style={{ borderBottom: "1px solid var(--color-divider)" }}
      >
        <span
          className="block h-[6px] w-[6px] rounded-full"
          style={{ background: "var(--red)" }}
        />
        <span className="drip-eyebrow">Coach · The Desk</span>
      </div>

      <nav
        className="flex items-stretch gap-[26px]"
        style={{ borderBottom: "2px solid var(--rule-strong)" }}
      >
        {TABS.map((tab) => {
          const isActive = pathname.startsWith(tab.href);
          return (
            <Link
              key={tab.href}
              href={tab.href}
              aria-current={isActive ? "page" : undefined}
              className="drip-eyebrow -mb-[2px] border-b-[3px] px-0 pb-[11px] pt-[13px] text-[11px] transition-colors"
              style={{
                color: isActive
                  ? "var(--color-text-primary)"
                  : "var(--color-text-tertiary)",
                borderBottomColor: isActive ? "var(--red)" : "transparent",
              }}
            >
              {tab.label}
            </Link>
          );
        })}
      </nav>
    </>
  );
}
