/**
 * Collapse Junction/Vital HRV readings into one value per night.
 *
 * Junction's `hrv` resource is an interval timeseries, not a summary: a night
 * arrives as a run of per-reading rmssd samples (Garmin records roughly every
 * five minutes while asleep), never as a single nightly number. Everything that
 * consumes `daily_biometrics.hrv_rmssd` wants one value per date, so the
 * aggregation has to happen on ingest.
 *
 * Kept out of `vital-webhook/index.ts` for the same reason `voiceOrphanMatch`
 * is: the function body calls `Deno.serve` at import time, so pure logic that
 * lives there cannot be unit-tested.
 */

/** One ClientFacingHRVTimeseries sample, narrowed to the fields we use. */
export interface HrvSample {
  timestamp?: unknown;
  value?: unknown;
  /** Seconds east of UTC at the moment of the reading; null when unavailable. */
  timezone_offset?: unknown;
}

/**
 * Bucket an HRV reading to the calendar date of the morning its night ENDED —
 * the same convention Junction uses for `sleep.calendar_date` ("generally
 * matches the sleep end date"), so HRV and sleep for one night land on the same
 * (user_id, date, source) primary key and merge instead of splitting into two
 * rows a day apart.
 *
 * Shifting local time by +12h maps [12:00 D, 12:00 D+1) -> D+1: a 23:40 reading
 * belongs to the next morning, a 03:10 reading to the same morning. A night
 * straddles UTC midnight for most of the world, so the sample's own
 * `timezone_offset` is what makes this correct — bucketing on the raw UTC
 * timestamp files half of every night on the wrong day (the same class of bug
 * as the week-surface day/label fix).
 *
 * A missing offset degrades to UTC rather than dropping the reading: a night
 * on the wrong side of one date boundary is recoverable, a discarded night is not.
 */
export function hrvNightDate(timestamp: unknown, tzOffsetSec: unknown): string | null {
  if (typeof timestamp !== "string") return null;
  const t = Date.parse(timestamp);
  if (!Number.isFinite(t)) return null;
  const offset = typeof tzOffsetSec === "number" && Number.isFinite(tzOffsetSec) ? tzOffsetSec : 0;
  return new Date(t + offset * 1000 + 12 * 3600 * 1000).toISOString().slice(0, 10);
}

/**
 * Mean rmssd per night, keyed YYYY-MM-DD. Non-numeric and unparseable samples
 * are skipped rather than poisoning the mean. Rounded to 0.1 ms — the column is
 * numeric and sub-decimal precision on a beat-interval statistic is noise.
 */
export function nightlyHrv(samples: unknown): Map<string, number> {
  const acc = new Map<string, { sum: number; n: number }>();
  if (!Array.isArray(samples)) return new Map();
  for (const s of samples as HrvSample[]) {
    const v = s?.value;
    if (typeof v !== "number" || !Number.isFinite(v)) continue;
    const d = hrvNightDate(s?.timestamp, s?.timezone_offset);
    if (!d) continue;
    const cur = acc.get(d) ?? { sum: 0, n: 0 };
    cur.sum += v;
    cur.n += 1;
    acc.set(d, cur);
  }
  const out = new Map<string, number>();
  for (const [d, { sum, n }] of acc) out.set(d, Math.round((sum / n) * 10) / 10);
  return out;
}
