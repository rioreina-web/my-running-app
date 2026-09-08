"use client";

/* Athlete-site mockup · app shell.

   Desktop (≥ 900px): a left rail carrying the wordmark, the four tabs
   (Log · Trends · Train · Coach — the target IA from CLAUDE.md) and the
   editorial index of secondary destinations. Content sits in a single
   phone-width column so the site reads like the app.

   Mobile: bottom tab bar + the hamburger that opens the same index as a
   slide-in menu (AppSidebar in the iOS kit). */

import Link from "next/link";
import { usePathname, useSearchParams } from "next/navigation";
import { useState, type ReactNode } from "react";
import { ATHLETE } from "./data";

const TABS = [
  { id: "log", label: "Log", href: "/mockup/log" },
  { id: "trends", label: "Trends", href: "/mockup/trends" },
  { id: "train", label: "Train", href: "/mockup/train" },
  { id: "coach", label: "Coach", href: "/mockup/coach" },
];

const INDEX = [
  { n: "01", href: "/mockup/niggles", label: "Niggles", hint: "Body-part mentions, in your words." },
  { n: "02", href: "/mockup/goals", label: "Goals", hint: "Race and training targets." },
  { n: "03", href: "/mockup/races", label: "Races", hint: "History, the anchor, the next one." },
  { n: "04", href: "/mockup/pace-chart", label: "Pace chart", hint: "Ten zones, anchored on a race." },
  { n: "05", href: "/mockup/profile", label: "Profile", hint: "The athlete, derived nightly." },
  { n: "06", href: "/mockup/settings", label: "Settings", hint: "Account, data, preferences." },
];

const BARE_ROUTES = ["/mockup/sign-in", "/mockup/onboarding"];

function activeTab(pathname: string) {
  if (pathname.startsWith("/mockup/log") || pathname.startsWith("/mockup/workouts")) return "log";
  if (pathname.startsWith("/mockup/trends")) return "trends";
  if (pathname.startsWith("/mockup/train")) return "train";
  if (pathname.startsWith("/mockup/coach")) return "coach";
  return "";
}

export function MockupShell({ children }: { children: ReactNode }) {
  const pathname = usePathname() ?? "";
  // `?day=1` swaps every tab to the state a brand-new account is in.
  // It rides along the tab links so the whole product can be walked in
  // either state without losing your place.
  const dayOne = useSearchParams().get("day") === "1";
  const q = dayOne ? "?day=1" : "";
  // The menu remembers the path it was opened on, so navigating closes it
  // without an effect.
  const [menuPath, setMenuPath] = useState<string | null>(null);
  const menuOpen = menuPath === pathname;
  const setMenuOpen = (open: boolean) => setMenuPath(open ? pathname : null);
  const tab = activeTab(pathname);

  if (BARE_ROUTES.some((r) => pathname.startsWith(r))) {
    return <div className="m-root">{children}</div>;
  }

  return (
    <div className="m-root">
      <div className="m-shell">
        <aside className="m-rail">
          <Link href="/mockup" className="m-rail__wordmark">
            post
            <br />
            run
            <br />
            <span>drip</span>
          </Link>
          <div className="m-rail__plate">Athlete · site mockup</div>

          <div className="m-seg m-mt-14" role="tablist" aria-label="Account state">
            <Link href={pathname} role="tab" aria-selected={!dayOne} className={`m-seg__tab${!dayOne ? " is-active" : ""}`}>
              Week 5
            </Link>
            <Link href={`${pathname}?day=1`} role="tab" aria-selected={dayOne} className={`m-seg__tab${dayOne ? " is-active" : ""}`}>
              Day one
            </Link>
          </div>

          <nav className="m-rail__tabs" aria-label="Tabs">
            {TABS.map((t) => (
              <Link key={t.id} href={`${t.href}${q}`} className={`m-rail__tab${tab === t.id ? " is-active" : ""}`}>
                <span className="m-tdot" />
                {t.label}
              </Link>
            ))}
          </nav>

          <div className="m-rail__group">
            <div className="m-rail__grouphead">
              <span>Index</span>
              <span className="ln" />
            </div>
            {INDEX.map((it) => (
              <Link key={it.href} href={it.href} className={`m-rail__item${pathname.startsWith(it.href) ? " is-active" : ""}`}>
                <span className="m-rail__num">{it.n}</span>
                <span className="m-rail__label">{it.label}</span>
                <span className="m-rail__arrow">↗</span>
              </Link>
            ))}
          </div>

          <div className="m-rail__foot">
            <Link href="/mockup/profile" className="m-rail__who">
              {ATHLETE.firstName}.
            </Link>
            <Link href="/mockup/sign-in" className="m-rail__build">
              Sign out
            </Link>
          </div>
        </aside>

        <main className="m-main">
          <div className="m-page">
            <button className="m-burger" onClick={() => setMenuOpen(true)} aria-label="Open menu">
              ☰
            </button>
            {children}
          </div>
        </main>
      </div>

      <nav className="m-tabbar" aria-label="Tabs">
        {TABS.map((t) => (
          <Link key={t.id} href={`${t.href}${q}`} className={`m-tabbar__tab${tab === t.id ? " is-active" : ""}`}>
            <span className="m-tdot" />
            {t.label}
          </Link>
        ))}
      </nav>

      {menuOpen ? (
        <>
          <div className="m-menu__scrim" onClick={() => setMenuOpen(false)} />
          <div className="m-menu" role="dialog" aria-label="Menu">
            <div className="m-menu__head">
              <div className="m-menu__toprow">
                <div className="m-rail__wordmark">
                  post
                  <br />
                  run
                  <br />
                  <span>drip</span>
                </div>
                <button className="m-menu__close" onClick={() => setMenuOpen(false)} aria-label="Close menu">
                  ✕
                </button>
              </div>
              <div className="m-menu__platerow">
                <span className="m-caption m-caption--faint">Menu · Index</span>
                <span className="m-caption m-caption--faint">06 destinations</span>
              </div>
              <div className="m-menu__identity">
                <div>
                  <div className="m-menu__name">{ATHLETE.firstName}.</div>
                  <div className="m-menu__email">{ATHLETE.email}</div>
                </div>
              </div>
            </div>
            <div className="m-menu__nav">
              <div className="m-seg" role="tablist" aria-label="Account state">
                <Link href={pathname} role="tab" aria-selected={!dayOne} className={`m-seg__tab${!dayOne ? " is-active" : ""}`}>
                  Week 5
                </Link>
                <Link href={`${pathname}?day=1`} role="tab" aria-selected={dayOne} className={`m-seg__tab${dayOne ? " is-active" : ""}`}>
                  Day one
                </Link>
              </div>
              <div className="m-sp-12" />
              {INDEX.map((it) => (
                <Link key={it.href} href={it.href} className="m-menu__item">
                  <span className="m-rail__num">{it.n}</span>
                  <span>
                    <span className="m-menu__label m-block">{it.label}</span>
                    <span className="m-menu__hint m-block">{it.hint}</span>
                  </span>
                  <span className="m-rail__arrow">↗</span>
                </Link>
              ))}
              <Link href="/mockup" className="m-menu__item">
                <span className="m-rail__num">··</span>
                <span>
                  <span className="m-menu__label m-block">Site map</span>
                  <span className="m-menu__hint m-block">Every surface in this mockup.</span>
                </span>
                <span className="m-rail__arrow">↗</span>
              </Link>
            </div>
            <div className="m-menu__foot">
              <Link href="/mockup/sign-in" className="m-menu__signout">
                Sign out
              </Link>
              <span className="m-rail__build">Mockup · Sep 2026</span>
            </div>
          </div>
        </>
      ) : null}
    </div>
  );
}
