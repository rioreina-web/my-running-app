/**
 * Pace / time formatters shared across the athlete-state module.
 * Extracted verbatim from `athlete-state.ts` (kept re-exported there for
 * backwards compatibility with existing importers).
 */

/**
 * Seconds-per-mile → "M:SS". Rounds to whole seconds FIRST, then splits, so a
 * fractional input like 479.6 produces "8:00", not "7:60" (rounding the
 * seconds part in isolation would let it carry incorrectly).
 */
export function formatPace(secondsPerMile: number): string {
  const total = Math.round(secondsPerMile);
  const mins = Math.floor(total / 60);
  const secs = total % 60;
  return `${mins}:${secs.toString().padStart(2, "0")}`;
}

/** Seconds → "M:SS" or "H:MM:SS". Returns "?" for non-positive / falsy input. */
export function formatTime(seconds: number): string {
  if (!seconds || seconds <= 0) return "?";
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = seconds % 60;
  if (h > 0) return `${h}:${m.toString().padStart(2, "0")}:${s.toString().padStart(2, "0")}`;
  return `${m}:${s.toString().padStart(2, "0")}`;
}

/**
 * Format a time delta. Signed. Under 60s → "45s faster". Over 60s → "1:39
 * slower". Runners read time in M:SS, not raw seconds — "99 seconds slower" is
 * jarring.
 */
export function formatTimeDelta(seconds: number): string {
  if (!seconds || seconds === 0) return "same";
  const abs = Math.abs(seconds);
  const direction = seconds > 0 ? "slower" : "faster";
  if (abs < 60) return `${abs}s ${direction}`;
  const m = Math.floor(abs / 60);
  const s = abs % 60;
  return `${m}:${s.toString().padStart(2, "0")} ${direction}`;
}
