"use client";

import Image from "next/image";
import Link from "next/link";
import { usePathname } from "next/navigation";

const NAV_ITEMS = [
  { href: "/dashboard", label: "Dashboard", icon: "◉" },
  { href: "/log", label: "Training Log", icon: "◈" },
  { href: "/coach", label: "Coach", icon: "◇" },
  { href: "/plan", label: "Plan", icon: "▦" },
];

const FEATURE_ITEMS = [
  { href: "/goals", label: "Goals", icon: "◎" },
  { href: "/analysis", label: "Analysis", icon: "▥" },
  { href: "/injuries", label: "Injuries", icon: "✚" },
  { href: "/predictor", label: "Fitness Predictor", icon: "▲" },
  { href: "/pace-chart", label: "Pace Chart", icon: "⏱" },
  { href: "/library", label: "Content Library", icon: "▤" },
];

const BOTTOM_ITEMS = [
  { href: "/blog", label: "Blog", icon: "✎" },
  { href: "/export", label: "Export", icon: "↓" },
  { href: "/settings", label: "Settings", icon: "⚙" },
];

function NavLink({
  href,
  label,
  icon,
  isActive,
}: {
  href: string;
  label: string;
  icon: string;
  isActive: boolean;
}) {
  return (
    <Link
      href={href}
      className={`flex items-center gap-3 rounded-lg px-3 py-2 text-sm transition-colors ${
        isActive
          ? "bg-coral/10 text-coral"
          : "text-text-secondary hover:bg-bg-elevated hover:text-text-primary"
      }`}
    >
      <span className="w-5 text-center text-xs">{icon}</span>
      {label}
    </Link>
  );
}

export default function Sidebar() {
  const pathname = usePathname();

  return (
    <aside className="flex h-screen w-56 flex-col border-r border-bg-elevated bg-bg-base">
      {/* Logo */}
      <div className="flex h-14 items-center px-5">
        <Link href="/dashboard">
          <Image
            src="/logo.png"
            alt="Post Run Drip"
            width={120}
            height={186}
            className="h-10 w-auto"
            priority
          />
        </Link>
      </div>

      {/* Main nav */}
      <nav className="flex flex-1 flex-col gap-1 overflow-y-auto px-3 py-2">
        {NAV_ITEMS.map((item) => (
          <NavLink
            key={item.href}
            {...item}
            isActive={pathname === item.href}
          />
        ))}

        <div className="my-3 border-t border-bg-elevated" />

        {FEATURE_ITEMS.map((item) => (
          <NavLink
            key={item.href}
            {...item}
            isActive={pathname === item.href}
          />
        ))}

        <div className="flex-1" />

        <div className="my-3 border-t border-bg-elevated" />

        {BOTTOM_ITEMS.map((item) => (
          <NavLink
            key={item.href}
            {...item}
            isActive={pathname === item.href}
          />
        ))}
      </nav>
    </aside>
  );
}
