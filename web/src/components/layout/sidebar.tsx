"use client";

import Image from "next/image";
import Link from "next/link";
import { usePathname } from "next/navigation";
import {
  LayoutDashboard,
  BookOpen,
  MessageCircle,
  Calendar,
  Target,
  BarChart3,
  HeartPulse,
  TrendingUp,
  Timer,
  PlaySquare,
  Download,
  Settings,
  X,
  UserCheck,
} from "lucide-react";
import { ComponentType, useEffect } from "react";
import { useSidebar } from "./sidebar-context";

interface NavItem {
  href: string;
  label: string;
  icon: ComponentType<{ size?: number }>;
}

const NAV_ITEMS: NavItem[] = [
  { href: "/dashboard", label: "Dashboard", icon: LayoutDashboard },
  { href: "/log", label: "Training Log", icon: BookOpen },
  { href: "/coach", label: "Coach", icon: MessageCircle },
  { href: "/plan", label: "Plan", icon: Calendar },
];

const FEATURE_ITEMS: NavItem[] = [
  { href: "/coach-portal/plans", label: "Coach Portal", icon: UserCheck },
  { href: "/goals", label: "Goals", icon: Target },
  { href: "/analysis", label: "Analysis", icon: BarChart3 },
  { href: "/injuries", label: "Injuries", icon: HeartPulse },
  { href: "/predictor", label: "Fitness Predictor", icon: TrendingUp },
  { href: "/pace-chart", label: "Pace Chart", icon: Timer },
  { href: "/library", label: "Content Library", icon: PlaySquare },
];

const BOTTOM_ITEMS: NavItem[] = [
  { href: "/export", label: "Export", icon: Download },
  { href: "/settings", label: "Settings", icon: Settings },
];

function NavLink({
  href,
  label,
  icon: Icon,
  isActive,
  onClick,
}: {
  href: string;
  label: string;
  icon: ComponentType<{ size?: number }>;
  isActive: boolean;
  onClick?: () => void;
}) {
  return (
    <Link
      href={href}
      onClick={onClick}
      className={`flex items-center gap-3 rounded-lg px-3 py-2 text-sm transition-colors ${
        isActive
          ? "bg-coral/10 text-coral"
          : "text-text-secondary hover:bg-bg-elevated hover:text-text-primary"
      }`}
    >
      <Icon size={16} />
      {label}
    </Link>
  );
}

export default function Sidebar() {
  const pathname = usePathname();
  const { open, close } = useSidebar();

  // Close sidebar on route change
  useEffect(() => {
    close();
  }, [pathname, close]);

  return (
    <>
      {/* Mobile overlay */}
      {open && (
        <div
          className="fixed inset-0 z-40 bg-black/30 md:hidden"
          onClick={close}
        />
      )}

      <aside
        className={`fixed inset-y-0 left-0 z-50 flex w-56 flex-col border-r border-divider bg-bg-base transition-transform duration-200 md:static md:translate-x-0 ${
          open ? "translate-x-0" : "-translate-x-full"
        }`}
      >
        {/* Logo + mobile close */}
        <div className="flex h-14 items-center justify-between px-5">
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
          <button
            onClick={close}
            className="rounded p-1 text-text-tertiary hover:text-text-primary md:hidden"
          >
            <X size={18} />
          </button>
        </div>

        {/* Main nav */}
        <nav className="flex flex-1 flex-col gap-1 overflow-y-auto px-3 py-2">
          {NAV_ITEMS.map((item) => (
            <NavLink
              key={item.href}
              {...item}
              isActive={pathname === item.href}
              onClick={close}
            />
          ))}

          <div className="my-3 border-t border-divider" />

          {FEATURE_ITEMS.map((item) => (
            <NavLink
              key={item.href}
              {...item}
              isActive={pathname === item.href}
              onClick={close}
            />
          ))}

          <div className="flex-1" />

          <div className="my-3 border-t border-divider" />

          {BOTTOM_ITEMS.map((item) => (
            <NavLink
              key={item.href}
              {...item}
              isActive={pathname === item.href}
              onClick={close}
            />
          ))}
        </nav>
      </aside>
    </>
  );
}
