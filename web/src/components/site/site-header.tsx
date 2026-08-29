"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useState } from "react";

const NAV = [
  { href: "/how-it-works", label: "How it works" },
  { href: "/principles", label: "Principles" },
  { href: "/blog", label: "Blog" },
];

/**
 * Public-site header. Shared by the landing page, the long-form pages and
 * the blog so the whole site carries one chrome.
 *
 * No blur, no glass — hard rule from the design system. The header sits on
 * opaque paper with a hairline under it.
 */
export function SiteHeader() {
  const pathname = usePathname();
  const [open, setOpen] = useState(false);

  return (
    <header className="sticky top-0 z-30 border-b border-divider bg-bg-base">
      <div className="mx-auto flex max-w-[1180px] items-center justify-between gap-6 px-6 py-4 md:px-10 md:py-5">
        <Link
          href="/"
          className="shrink-0 font-display text-[22px] font-bold tracking-[-0.01em] text-text-primary"
        >
          Post Run Drip
        </Link>

        <nav className="hidden items-center gap-8 md:flex">
          {NAV.map((item) => {
            const active =
              pathname === item.href || pathname.startsWith(`${item.href}/`);
            return (
              <Link
                key={item.href}
                href={item.href}
                className={`font-mono text-[10px] font-medium tracking-[0.14em] uppercase transition-colors ${
                  active
                    ? "text-coral"
                    : "text-text-secondary hover:text-text-primary"
                }`}
              >
                {item.label}
              </Link>
            );
          })}
          <span className="h-4 w-px bg-divider" aria-hidden />
          <Link
            href="/login"
            className="font-body text-[14px] text-text-secondary transition-colors hover:text-text-primary"
          >
            Sign in
          </Link>
          <Link
            href="/beta"
            className="rounded-[10px] bg-coral px-4 py-2 font-display text-[14px] font-semibold text-white transition-colors hover:bg-coral-dark"
          >
            Request an invite
          </Link>
        </nav>

        <button
          type="button"
          onClick={() => setOpen((v) => !v)}
          aria-expanded={open}
          aria-label="Menu"
          className="font-mono text-[10px] font-medium tracking-[0.14em] uppercase text-text-secondary md:hidden"
        >
          {open ? "Close" : "Menu"}
        </button>
      </div>

      {open && (
        <div className="border-t border-divider px-6 py-4 md:hidden">
          <div className="flex flex-col gap-4">
            {NAV.map((item) => (
              <Link
                key={item.href}
                href={item.href}
                onClick={() => setOpen(false)}
                className="font-mono text-[10px] font-medium tracking-[0.14em] uppercase text-text-secondary"
              >
                {item.label}
              </Link>
            ))}
            <Link
              href="/login"
              onClick={() => setOpen(false)}
              className="font-mono text-[10px] font-medium tracking-[0.14em] uppercase text-text-secondary"
            >
              Sign in
            </Link>
            <Link
              href="/beta"
              onClick={() => setOpen(false)}
              className="rounded-[10px] bg-coral px-4 py-2.5 text-center font-display text-[14px] font-semibold text-white"
            >
              Request an invite
            </Link>
          </div>
        </div>
      )}
    </header>
  );
}
