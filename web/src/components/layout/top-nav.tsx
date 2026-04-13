"use client";

import { Menu } from "lucide-react";
import { useSidebar } from "./sidebar-context";

export default function TopNav() {
  const { toggle } = useSidebar();

  return (
    <header className="flex h-14 items-center justify-between border-b border-divider bg-bg-base px-4 md:px-6">
      <button
        onClick={toggle}
        className="rounded p-1.5 text-text-secondary hover:text-text-primary md:hidden"
        aria-label="Toggle menu"
      >
        <Menu size={20} />
      </button>
      <div className="hidden md:block" />
      <div className="flex items-center gap-4">
        <span className="font-mono text-xs text-text-tertiary">dev-user</span>
      </div>
    </header>
  );
}
