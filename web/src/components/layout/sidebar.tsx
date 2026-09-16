"use client";

import Image from "next/image";
import Link from "next/link";
import { usePathname } from "next/navigation";
import {
  BookOpen,
  Calendar,
  HeartPulse,
  TrendingUp,
  Timer,
  Settings,
  X,
  UserCheck,
} from "lucide-react";
import { ComponentType, useEffect } from "react";
import { useSidebar } from "./sidebar-context";
import { Eyebrow } from "@/components/ui/eyebrow";

interface NavItem {
  href: string;
  label: string;
  icon: ComponentType<{ size?: number }>;
}

// Main nav mirrors the iOS 4-tab IA (Log · Trends · Train · Coach) —
// input → overview → detail. The Coach read stays iOS-only for now, so
// the web nav ships the first three; Plan lives inside Train.
const NAV_ITEMS: NavItem[] = [
  { href: "/log", label: "Log", icon: BookOpen },
  { href: "/trends", label: "Trends", icon: TrendingUp },
  { href: "/train", label: "Train", icon: Calendar },
];

// Tools — only routes that actually exist. (Goals, Analysis, Predictor,
// Library, and Export were dead links; restore them as their pages ship.)
const FEATURE_ITEMS: NavItem[] = [
  { href: "/injuries", label: "Niggles", icon: HeartPulse },
  { href: "/pace-chart", label: "Pace Chart", icon: Timer },
  { href: "/coach-portal", label: "Coach Portal", icon: UserCheck },
];

const BOTTOM_ITEMS: NavItem[] = [
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
      className={`relative flex items-center gap-3 rounded-lg px-3 py-2 font-mono text-[11px] uppercase tracking-[0.1em] transition-colors ${
        isActive
          ? "text-coral"
          : "text-text-secondary hover:bg-bg-elevated hover:text-text-primary"
      }`}
    >
      {isActive && (
        <span className="absolute left-0 top-1/2 h-4 w-[2px] -translate-y-1/2 rounded-full bg-coral" />
      )}
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
          <Link href="/trends">
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

          <div className="mt-5 mb-2 px-3">
            <Eyebrow>Tools</Eyebrow>
          </div>

          {FEATURE_ITEMS.map((item) => (
            <NavLink
              key={item.href}
              {...item}
              isActive={pathname === item.href}
              onClick={close}
            />
          ))}

          <div className="flex-1" />

          <div className="mt-5 mb-2 px-3">
            <Eyebrow>Account</Eyebrow>
          </div>

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
