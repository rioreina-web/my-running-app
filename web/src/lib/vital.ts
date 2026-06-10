/**
 * Vital API client — fetches Garmin workout data server-side.
 * Computes mile splits, HR zones, pace/HR overlay, effort distribution.
 */

const VITAL_BASE_URL = process.env.VITAL_BASE_URL || "https://api.sandbox.tryvital.io/v2";
const VITAL_API_KEY = process.env.VITAL_API_KEY || "";
const VITAL_USER_ID = process.env.VITAL_USER_ID || "";

// ─── Types ───────────────────────────────────────────────────

interface VitalStream {
  time: number[];
  heartrate: number[];
  lat: number[];
  lng: number[];
  altitude: number[];
  distance: number[];
  velocity_smooth: number[];
  cadence: number[];
  power: number[];
}

export interface WorkoutStreamData {
  summary: {
    averageHr: number | null;
    maxHr: number | null;
    elevationGainFt: number | null;
    elevationLossFt: number | null;
    movingTimeSec: number | null;
    calories: number | null;
    cadenceAvg: number | null;
  };
  mileSplits: MileSplit[];
  timeline: TimelinePoint[];       // Per-minute pace + HR for overlay chart
  hrZones: HRZoneBreakdown;        // Time in each HR zone
  effortDistribution: EffortBlock[];  // Visual workout structure
  elevationProfile: ElevPoint[];
  insights: string[];              // Auto-generated coaching observations
}

export interface MileSplit {
  mile: number;
  pace: string;
  paceSeconds: number;
  heartRate: number | null;
  elevation: number | null;       // net elevation change for this mile
  isPartial: boolean;
  partialDistance?: number;
}

export interface TimelinePoint {
  minute: number;
  pace: number;       // seconds per mile
  hr: number;
  distance: number;   // cumulative miles
  altitude: number;   // feet
}

export interface HRZoneBreakdown {
  zones: { name: string; min: number; max: number; seconds: number; pct: number; color: string }[];
  maxHr: number;
}

export interface EffortBlock {
  type: "easy" | "moderate" | "hard" | "recovery" | "stopped";
  startMin: number;
  endMin: number;
  avgPace: number;
  avgHr: number;
  distanceMiles: number;
}

export interface ElevPoint {
  distance: number;
  altitude: number;
}

// ─── Main Fetch ──────────────────────────────────────────────

export async function fetchVitalStream(workoutId: string): Promise<WorkoutStreamData | null> {
  const [summaryRes, streamRes] = await Promise.all([
    vitalFetch(`${VITAL_BASE_URL}/summary/workouts/${VITAL_USER_ID}?start_date=2025-01-01&end_date=2027-01-01`),
    vitalFetch(`${VITAL_BASE_URL}/timeseries/workouts/${workoutId}/stream`),
  ]);

  // Parse summary
  let summary: WorkoutStreamData["summary"] = {
    averageHr: null, maxHr: null, elevationGainFt: null, elevationLossFt: null,
    movingTimeSec: null, calories: null, cadenceAvg: null,
  };

  if (summaryRes) {
    const data = await summaryRes.json();
    const match = (data.workouts || []).find((w: { id: string }) => w.id === workoutId);
    if (match) {
      summary = {
        averageHr: match.average_hr,
        maxHr: match.max_hr,
        elevationGainFt: match.total_elevation_gain ? Math.round(match.total_elevation_gain * 3.28084) : null,
        elevationLossFt: match.elev_low && match.elev_high
          ? Math.round((match.elev_high - match.elev_low) * 3.28084) : null,
        movingTimeSec: match.moving_time || null,
        calories: match.calories ? Math.round(match.calories) : null,
        cadenceAvg: match.steps && match.moving_time
          ? Math.round((match.steps / (match.moving_time / 60)) / 2) : null,
      };
    }
  }

  if (!streamRes) {
    return { summary, mileSplits: [], timeline: [], hrZones: { zones: [], maxHr: 0 }, effortDistribution: [], elevationProfile: [], insights: [] };
  }

  const stream: VitalStream = await streamRes.json();
  if (!stream.time?.length || !stream.distance?.length) {
    return { summary, mileSplits: [], timeline: [], hrZones: { zones: [], maxHr: 0 }, effortDistribution: [], elevationProfile: [], insights: [] };
  }

  const mileSplits = computeMileSplits(stream);
  const timeline = computeTimeline(stream);
  const hrZones = computeHRZones(stream, summary.maxHr || 185);
  const effortDistribution = computeEffortBlocks(stream);
  const elevationProfile = computeElevation(stream);
  const insights = generateInsights(mileSplits, timeline, hrZones, summary, effortDistribution);

  return { summary, mileSplits, timeline, hrZones, effortDistribution, elevationProfile, insights };
}

// ─── Timeline (per-minute pace + HR overlay) ─────────────────

function computeTimeline(stream: VitalStream): TimelinePoint[] {
  const points: TimelinePoint[] = [];
  if (!stream.time?.length) return points;

  const startTime = stream.time[0];
  const totalSec = stream.time[stream.time.length - 1] - startTime;
  const totalMin = Math.ceil(totalSec / 60);

  for (let min = 0; min <= totalMin; min++) {
    const targetTime = startTime + min * 60;
    // Find closest index
    let idx = 0;
    for (let i = 0; i < stream.time.length; i++) {
      if (stream.time[i] >= targetTime) { idx = i; break; }
      idx = i;
    }

    const vel = stream.velocity_smooth?.[idx] || 0;
    const paceSecPerMile = vel > 0.5 ? (1609.34 / vel) : 0;
    const hr = stream.heartrate?.[idx] || 0;
    const dist = (stream.distance?.[idx] || 0) / 1609.34;
    const alt = (stream.altitude?.[idx] || 0) * 3.28084;

    points.push({ minute: min, pace: Math.round(paceSecPerMile), hr, distance: Math.round(dist * 100) / 100, altitude: Math.round(alt) });
  }

  return points;
}

// ─── HR Zones ────────────────────────────────────────────────

function computeHRZones(stream: VitalStream, estimatedMaxHr: number): HRZoneBreakdown {
  const maxHr = estimatedMaxHr;
  const zones = [
    { name: "Z1 Recovery", min: 0, max: Math.round(maxHr * 0.6), seconds: 0, pct: 0, color: "#9B9590" },
    { name: "Z2 Easy", min: Math.round(maxHr * 0.6), max: Math.round(maxHr * 0.7), seconds: 0, pct: 0, color: "#4A9E6B" },
    { name: "Z3 Aerobic", min: Math.round(maxHr * 0.7), max: Math.round(maxHr * 0.8), seconds: 0, pct: 0, color: "#C4873A" },
    { name: "Z4 Threshold", min: Math.round(maxHr * 0.8), max: Math.round(maxHr * 0.9), seconds: 0, pct: 0, color: "#D4592A" },
    { name: "Z5 Max", min: Math.round(maxHr * 0.9), max: 999, seconds: 0, pct: 0, color: "#B83A4A" },
  ];

  if (!stream.heartrate?.length || !stream.time?.length) return { zones, maxHr };

  let totalSec = 0;
  for (let i = 1; i < stream.heartrate.length; i++) {
    const dt = stream.time[i] - stream.time[i - 1];
    if (dt > 10) continue; // skip gaps
    const hr = stream.heartrate[i];
    for (const zone of zones) {
      if (hr >= zone.min && hr < zone.max) {
        zone.seconds += dt;
        break;
      }
    }
    totalSec += dt;
  }

  if (totalSec > 0) {
    for (const zone of zones) {
      zone.pct = Math.round((zone.seconds / totalSec) * 100);
    }
  }

  return { zones, maxHr };
}

// ─── Effort Distribution (workout structure) ─────────────────

function computeEffortBlocks(stream: VitalStream): EffortBlock[] {
  if (!stream.velocity_smooth?.length || !stream.time?.length) return [];

  const startTime = stream.time[0];
  const blocks: EffortBlock[] = [];

  // Classify each second as easy/moderate/hard/stopped based on velocity
  // Use rolling 30-second average
  const windowSize = 30;
  const smoothed: number[] = [];

  for (let i = 0; i < stream.velocity_smooth.length; i++) {
    const start = Math.max(0, i - windowSize);
    const end = Math.min(stream.velocity_smooth.length, i + windowSize);
    let sum = 0, count = 0;
    for (let j = start; j < end; j++) {
      sum += stream.velocity_smooth[j];
      count++;
    }
    smoothed.push(sum / count);
  }

  // Find median velocity (excluding stopped)
  const moving = smoothed.filter(v => v > 1.5);
  if (moving.length === 0) return [];
  const sorted = [...moving].sort((a, b) => a - b);
  const median = sorted[Math.floor(sorted.length / 2)];

  // Classify
  type Effort = "stopped" | "easy" | "moderate" | "hard" | "recovery";
  let currentType: Effort = "easy";
  let blockStart = 0;

  const classify = (vel: number): Effort => {
    if (vel < 1.5) return "stopped";
    if (vel > median * 1.08) return "hard";
    if (vel < median * 0.92) return "easy";
    return "moderate";
  };

  for (let i = 1; i < smoothed.length; i++) {
    const type = classify(smoothed[i]);
    if (type !== currentType || i === smoothed.length - 1) {
      const startMin = (stream.time[blockStart] - startTime) / 60;
      const endMin = (stream.time[i] - startTime) / 60;

      if (endMin - startMin > 0.3) { // skip tiny blocks < 20 sec
        // Compute avg pace and HR for this block
        let hrSum = 0, hrCount = 0;
        const distStart = stream.distance[blockStart], distEnd = stream.distance[i];
        for (let j = blockStart; j < i; j++) {
          if (stream.heartrate?.[j]) { hrSum += stream.heartrate[j]; hrCount++; }
        }
        const distMiles = (distEnd - distStart) / 1609.34;
        const durMin = endMin - startMin;
        const avgPace = distMiles > 0 ? (durMin / distMiles) * 60 : 0; // sec per mile

        blocks.push({
          type: currentType,
          startMin: Math.round(startMin * 10) / 10,
          endMin: Math.round(endMin * 10) / 10,
          avgPace: Math.round(avgPace),
          avgHr: hrCount > 0 ? Math.round(hrSum / hrCount) : 0,
          distanceMiles: Math.round(distMiles * 100) / 100,
        });
      }

      currentType = type;
      blockStart = i;
    }
  }

  return blocks;
}

// ─── Mile Splits ─────────────────────────────────────────────

function computeMileSplits(stream: VitalStream): MileSplit[] {
  if (!stream.distance?.length || !stream.time?.length || stream.distance.length < 2) return [];

  const velocities = stream.velocity_smooth;
  const mileInMeters = 1609.34;
  const stoppedThreshold = 1.6;

  const movingTimeAt: number[] = [0];
  for (let i = 1; i < stream.time.length; i++) {
    const dt = stream.time[i] - stream.time[i - 1];
    const isMoving = velocities?.[i] ? velocities[i] >= stoppedThreshold : true;
    movingTimeAt.push(movingTimeAt[i - 1] + (isMoving ? dt : 0));
  }

  const splits: MileSplit[] = [];
  let mileStartMovingTime = 0;
  let mileStartIdx = 0;
  let currentMile = 1;

  for (let mile = 1; mile <= 100; mile++) {
    const targetDistance = mile * mileInMeters;
    if (targetDistance > stream.distance[stream.distance.length - 1]) break;

    for (let i = 1; i < stream.distance.length; i++) {
      if (stream.distance[i] >= targetDistance && stream.distance[i - 1] < targetDistance) {
        const distRange = stream.distance[i] - stream.distance[i - 1];
        const fraction = distRange > 0 ? (targetDistance - stream.distance[i - 1]) / distRange : 0;
        const mileEndMovingTime = movingTimeAt[i - 1] + fraction * (movingTimeAt[i] - movingTimeAt[i - 1]);
        const mileMovingTime = mileEndMovingTime - mileStartMovingTime;
        const paceSeconds = Math.round(mileMovingTime);

        // Average HR for this mile
        let hrSum = 0, hrCount = 0;
        for (let j = mileStartIdx; j <= i; j++) {
          if (stream.heartrate?.[j]) { hrSum += stream.heartrate[j]; hrCount++; }
        }

        // Net elevation change
        const altStart = stream.altitude?.[mileStartIdx] || 0;
        const altEnd = stream.altitude?.[i] || 0;
        const elevChange = Math.round((altEnd - altStart) * 3.28084);

        splits.push({
          mile: currentMile,
          pace: formatPace(mileMovingTime / 60),
          paceSeconds,
          heartRate: hrCount > 0 ? Math.round(hrSum / hrCount) : null,
          elevation: elevChange,
          isPartial: false,
        });

        mileStartMovingTime = mileEndMovingTime;
        mileStartIdx = i;
        currentMile++;
        break;
      }
    }
  }

  // Partial final mile
  const lastDist = stream.distance[stream.distance.length - 1];
  const completedDist = splits.length * mileInMeters;
  const remaining = lastDist - completedDist;
  if (remaining > 130) {
    const partialMiles = remaining / mileInMeters;
    const totalMovingTime = movingTimeAt[movingTimeAt.length - 1];
    const partialTime = totalMovingTime - mileStartMovingTime;
    const paceSeconds = partialMiles > 0 ? Math.round((partialTime / partialMiles)) : 0;

    let hrSum = 0, hrCount = 0;
    for (let j = mileStartIdx; j < stream.heartrate.length; j++) {
      if (stream.heartrate?.[j]) { hrSum += stream.heartrate[j]; hrCount++; }
    }

    splits.push({
      mile: currentMile,
      pace: formatPace(partialTime / 60 / partialMiles),
      paceSeconds,
      heartRate: hrCount > 0 ? Math.round(hrSum / hrCount) : null,
      elevation: null,
      isPartial: true,
      partialDistance: Math.round(partialMiles * 100) / 100,
    });
  }

  return splits;
}

// ─── Elevation ───────────────────────────────────────────────

function computeElevation(stream: VitalStream): ElevPoint[] {
  if (!stream.altitude?.length || !stream.distance?.length) return [];
  const points: ElevPoint[] = [];
  for (let i = 0; i < stream.altitude.length; i += 10) {
    points.push({
      distance: Math.round((stream.distance[i] / 1609.34) * 100) / 100,
      altitude: Math.round(stream.altitude[i] * 3.28084),
    });
  }
  return points;
}

// ─── Auto Insights ───────────────────────────────────────────

function generateInsights(
  splits: MileSplit[],
  timeline: TimelinePoint[],
  hrZones: HRZoneBreakdown,
  summary: WorkoutStreamData["summary"],
  effort: EffortBlock[]
): string[] {
  const insights: string[] = [];
  if (splits.length < 2) return insights;

  const fullSplits = splits.filter(s => !s.isPartial);
  if (fullSplits.length < 2) return insights;

  const paces = fullSplits.map(s => s.paceSeconds);
  const fastest = Math.min(...paces);
  const slowest = Math.max(...paces);
  const spread = slowest - fastest;

  // Even pacing check
  if (spread < 15) {
    insights.push("Very consistent pacing — less than 15 sec spread across all miles.");
  } else if (spread > 60) {
    insights.push(`Wide pace spread (${formatPace(fastest / 60)} to ${formatPace(slowest / 60)}). This could indicate interval structure or pacing issues.`);
  }

  // Negative split check
  const firstHalf = paces.slice(0, Math.floor(paces.length / 2));
  const secondHalf = paces.slice(Math.floor(paces.length / 2));
  const avgFirst = firstHalf.reduce((a, b) => a + b, 0) / firstHalf.length;
  const avgSecond = secondHalf.reduce((a, b) => a + b, 0) / secondHalf.length;
  if (avgSecond < avgFirst - 5) {
    insights.push(`Negative split — second half was ${Math.round(avgFirst - avgSecond)}s/mi faster. Strong finish.`);
  } else if (avgSecond > avgFirst + 10) {
    insights.push(`Positive split — slowed ${Math.round(avgSecond - avgFirst)}s/mi in the second half. Possible fatigue or deliberate cooldown.`);
  }

  // Cardiac drift check
  if (timeline.length > 10) {
    const firstQuarter = timeline.slice(0, Math.floor(timeline.length / 4));
    const lastQuarter = timeline.slice(Math.floor(timeline.length * 3 / 4));
    const hrFirst = firstQuarter.filter(t => t.hr > 0).reduce((s, t) => s + t.hr, 0) / firstQuarter.filter(t => t.hr > 0).length;
    const hrLast = lastQuarter.filter(t => t.hr > 0).reduce((s, t) => s + t.hr, 0) / lastQuarter.filter(t => t.hr > 0).length;
    const paceFirst = firstQuarter.filter(t => t.pace > 0 && t.pace < 1200).reduce((s, t) => s + t.pace, 0) / firstQuarter.filter(t => t.pace > 0 && t.pace < 1200).length;
    const paceLast = lastQuarter.filter(t => t.pace > 0 && t.pace < 1200).reduce((s, t) => s + t.pace, 0) / lastQuarter.filter(t => t.pace > 0 && t.pace < 1200).length;

    if (hrFirst > 0 && hrLast > 0) {
      const hrDrift = hrLast - hrFirst;
      const paceDrift = paceLast - paceFirst;
      if (hrDrift > 8 && Math.abs(paceDrift) < 15) {
        insights.push(`Cardiac drift detected: HR rose ${Math.round(hrDrift)} bpm while pace stayed similar. Could indicate dehydration or heat.`);
      }
    }
  }

  // HR zone distribution insight
  const hardZones = hrZones.zones.filter(z => z.name.includes("Z4") || z.name.includes("Z5"));
  const hardPct = hardZones.reduce((s, z) => s + z.pct, 0);
  const easyZones = hrZones.zones.filter(z => z.name.includes("Z1") || z.name.includes("Z2"));
  const easyPct = easyZones.reduce((s, z) => s + z.pct, 0);

  if (easyPct > 80) {
    insights.push(`${easyPct}% of time in easy zones — good recovery run.`);
  } else if (hardPct > 40) {
    insights.push(`${hardPct}% of time in threshold/max zones — high intensity session.`);
  }

  // Fastest mile callout
  const fastestSplit = fullSplits.reduce((a, b) => a.paceSeconds < b.paceSeconds ? a : b);
  insights.push(`Fastest mile: Mile ${fastestSplit.mile} at ${fastestSplit.pace}/mi${fastestSplit.heartRate ? ` (${fastestSplit.heartRate} bpm)` : ""}.`);

  return insights;
}

// ─── Helpers ─────────────────────────────────────────────────

async function vitalFetch(url: string): Promise<Response | null> {
  const maxRetries = 3;
  const backoffMs = [1000, 2000, 4000];

  for (let attempt = 0; attempt < maxRetries; attempt++) {
    try {
      const res = await fetch(url, {
        headers: { "x-vital-api-key": VITAL_API_KEY },
        next: { revalidate: 300 },
      });

      if (res.ok) return res;

      // 4xx — don't retry, caller's problem
      if (res.status >= 400 && res.status < 500) return null;

      // 5xx — retry after backoff
      if (attempt < maxRetries - 1) {
        await new Promise((r) => setTimeout(r, backoffMs[attempt]));
        continue;
      }
      return null;
    } catch {
      // Network failure — retry after backoff
      if (attempt < maxRetries - 1) {
        await new Promise((r) => setTimeout(r, backoffMs[attempt]));
        continue;
      }
      return null;
    }
  }
  return null;
}

function formatPace(minutes: number): string {
  const totalSec = Math.round(minutes * 60);
  const m = Math.floor(totalSec / 60);
  const s = totalSec % 60;
  return `${m}:${s.toString().padStart(2, "0")}`;
}
