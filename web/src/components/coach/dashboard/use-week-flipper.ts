"use client";

import { useEffect, useMemo, useState } from "react";
import type { DashboardDay } from "@/lib/coach-dashboard/types";

// Train's week flipper (spec §2.2) — ported from the mockup's weekRows() /
// weekTotals() / render() almost unchanged, as pure functions over
// DashboardDay[] instead of the mockup's WK_DAYS fixture. `?week=YYYY-MM-DD`
// opens on that week (so a link can point at one); the URL stays in sync via
// history.replaceState without triggering navigation.

export interface WeekRow {
  iso: string;
  dow: string;
  label: string;
  day: DashboardDay | null;
  future: boolean;
  today: boolean;
}

export interface WeekTotals {
  mi: number;
  load: number;
  n: number;
  quality: number;
  longest: number;
  longestDay: string;
  days: number;
}

const DOW = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

function parseISO(s: string): Date {
  const [y, m, d] = s.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, d));
}
function isoOfUTC(d: Date): string {
  return d.toISOString().slice(0, 10);
}
function mondayOfISO(s: string): string {
  const d = parseISO(s);
  const w = (d.getUTCDay() + 6) % 7;
  d.setUTCDate(d.getUTCDate() - w);
  return isoOfUTC(d);
}
export function fmtWeekOf(monIso: string): string {
  const d = parseISO(monIso);
  return `Week of ${MONTHS[d.getUTCMonth()]} ${d.getUTCDate()}`;
}

export function useWeekFlipper(days: DashboardDay[], todayISO: string) {
  const byDate = useMemo(() => {
    const m = new Map<string, DashboardDay>();
    for (const d of days) m.set(d.date, d);
    return m;
  }, [days]);

  // Every Monday from the first day the dashboard covers to the week
  // containing today. `days` is the caller's fetched window, not full
  // history — `‹` disables at the start of what's actually loaded, a real
  // boundary rather than a fake one.
  const weeks = useMemo(() => {
    if (!days.length) return [] as string[];
    const start = mondayOfISO(days[0].date);
    const end = mondayOfISO(todayISO);
    const out: string[] = [];
    const c = parseISO(start);
    const endDt = parseISO(end);
    while (c <= endDt) {
      out.push(isoOfUTC(c));
      c.setUTCDate(c.getUTCDate() + 7);
    }
    return out;
  }, [days, todayISO]);

  const [cur, setCur] = useState(() => Math.max(0, weeks.length - 1));

  // Deep link, read client-side after mount (matches the mockup's own
  // location.search parse) — avoids requiring a Suspense boundary for
  // useSearchParams on an otherwise fully client-rendered section.
  useEffect(() => {
    if (typeof window === "undefined" || !weeks.length) return;
    const q = /[?&]week=(\d{4}-\d{2}-\d{2})/.exec(window.location.search);
    if (!q) {
      setCur(weeks.length - 1);
      return;
    }
    const i = weeks.indexOf(q[1]);
    setCur(i >= 0 ? i : weeks.length - 1);
    // Only re-derive when the available weeks change (e.g. data arrives) —
    // not on every `cur` change, which would fight manual navigation.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [weeks.length]);

  const syncUrl = (index: number) => {
    if (typeof window === "undefined" || !window.history.replaceState) return;
    const u = new URL(window.location.href);
    if (index === weeks.length - 1) u.searchParams.delete("week");
    else u.searchParams.set("week", weeks[index]);
    window.history.replaceState(null, "", u);
  };

  const goTo = (index: number) => {
    if (!weeks.length) return;
    const clamped = Math.max(0, Math.min(weeks.length - 1, index));
    setCur(clamped);
    syncUrl(clamped);
  };

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const tag = (e.target as HTMLElement | null)?.tagName;
      if (tag === "INPUT" || tag === "TEXTAREA") return;
      if (e.key === "ArrowLeft") goTo(cur - 1);
      if (e.key === "ArrowRight") goTo(cur + 1);
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [cur, weeks.length]);

  function weekRows(monIso: string): WeekRow[] {
    const m = parseISO(monIso);
    const rows: WeekRow[] = [];
    for (let i = 0; i < 7; i++) {
      const d = new Date(m);
      d.setUTCDate(d.getUTCDate() + i);
      const iso = isoOfUTC(d);
      rows.push({
        iso,
        dow: DOW[i],
        label: `${DOW[i]} ${d.getUTCDate()}`,
        day: byDate.get(iso) ?? null,
        future: iso > todayISO,
        today: iso === todayISO,
      });
    }
    return rows;
  }

  // A day with no row (or `logged === false`) is not a zero — before today
  // it's rest, after it, it simply hasn't happened. Callers must keep that
  // distinction; this function only aggregates days that DID happen.
  function weekTotals(rows: WeekRow[]): WeekTotals {
    let mi = 0;
    let load = 0;
    let n = 0;
    let quality = 0;
    let longest = 0;
    let longestDay = "";
    let daysCount = 0;
    for (const r of rows) {
      if (!r.day || r.day.logged === false || r.day.miles <= 0) continue;
      mi += r.day.miles;
      load += r.day.load ?? 0;
      n += r.day.sessions ?? 1;
      daysCount += 1;
      if (r.day.key) quality += 1;
      if (r.day.miles > longest) {
        longest = r.day.miles;
        longestDay = r.dow;
      }
    }
    return { mi, load, n, quality, longest, longestDay, days: daysCount };
  }

  const weekStripMiles = useMemo(
    () => weeks.map((w) => weekTotals(weekRows(w)).mi),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [weeks, byDate, todayISO],
  );

  return {
    weeks,
    cur,
    goTo,
    weekRows,
    weekTotals,
    weekStripMiles,
    isCurrentWeek: weeks.length > 0 && cur === weeks.length - 1,
  };
}
