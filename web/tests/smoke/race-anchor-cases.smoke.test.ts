// Race-anchor calculator: runs canonical pace-zone derivation against
// real athlete inputs and prints the full table.
//
// Run: cd web && npm run test:smoke
//
// To add an athlete, drop a new entry into ATHLETES below.
//
// This is both a calculator (the printed output is the deliverable for
// design conversations) AND a regression test (the pin assertions catch
// silent drift in RACE_RATIOS_TO_10K or TRAINING_MP_SPEED_RATIO).

import { test } from "node:test";
import { strict as assert } from "node:assert";

import {
  derivePaceTableFromGoal,
  trainingZoneRange,
  type PaceZone,
} from "@/components/coach/workout-helpers";

// ── Formatters ──────────────────────────────────────────

function fmtTime(totalSeconds: number): string {
  const s = Math.round(totalSeconds);
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const sec = s % 60;
  if (h > 0) return `${h}:${String(m).padStart(2, "0")}:${String(sec).padStart(2, "0")}`;
  return `${m}:${String(sec).padStart(2, "0")}`;
}

function fmtPace(secPerMile: number): string {
  const s = Math.round(secPerMile);
  const m = Math.floor(s / 60);
  const sec = s % 60;
  return `${m}:${String(sec).padStart(2, "0")}/mi`;
}

// Distances in miles for race-equivalent zones (matches RACE_DISTANCE_MI).
const DISTANCE_MI: Record<string, number> = {
  mile:      1.0,
  fiveK:     3.1069,
  tenK:      6.2137,
  threshold: 0,    // LT is a pace not a race distance; printed separately
  hm:        13.1094,
  mp:        26.2188,
};

// ── Athlete cases ───────────────────────────────────────

type Athlete = {
  name: string;
  raceDistance: "mile" | "5k" | "10k" | "half_marathon" | "marathon";
  raceTimeSeconds: number;
  context: string;
};

const ATHLETES: Athlete[] = [
  {
    name: "Athlete A — 4:34 road mile, 40–45 MPW",
    raceDistance: "mile",
    raceTimeSeconds: 274,                 // 4:34
    context: "Strong VO2max signal. Volume validates mile through 10K; "
           + "HM and marathon predictions are speed-derived only.",
  },
  // Reference calibration from paces.ts line 28:
  //   2:20:00 marathon → 5K 14:34 / Mile 4:14
  {
    name: "Reference calibration — 2:20 marathon",
    raceDistance: "marathon",
    raceTimeSeconds: 8400,                // 2:20:00
    context: "Sanity check. Mile should be ~4:14, 5K should be ~14:34.",
  },
];

// ── Pretty printer ──────────────────────────────────────

function printPaceTable(athlete: Athlete) {
  const raceMi = ({ mile: 1.0, "5k": 3.1069, "10k": 6.2137, half_marathon: 13.1094, marathon: 26.2188 })[athlete.raceDistance];
  const raceSecPerMile = athlete.raceTimeSeconds / raceMi;
  const table = derivePaceTableFromGoal(raceSecPerMile, athlete.raceDistance);

  // Header
  console.log("");
  console.log("─".repeat(72));
  console.log(athlete.name);
  console.log(`  Input: ${athlete.raceDistance} in ${fmtTime(athlete.raceTimeSeconds)} (${fmtPace(raceSecPerMile)})`);
  console.log(`  Context: ${athlete.context}`);
  console.log("─".repeat(72));

  // Race-equivalent zones (single targets)
  console.log("Race-equivalent times:");
  const raceZones: Array<[PaceZone, string]> = [
    ["mile", "1 mile     "],
    ["fiveK", "5K         "],
    ["tenK", "10K        "],
    ["threshold", "LT (1hr)   "],
    ["hm", "Half       "],
    ["mp", "Marathon   "],
  ];
  for (const [zone, label] of raceZones) {
    const pace = table[zone];
    const distance = DISTANCE_MI[zone];
    const totalTime = distance > 0 ? pace * distance : 0;
    if (zone === "threshold") {
      // LT is a pace, not a race time — derive the distance it implies
      const distanceInHour = 3600 / pace;
      console.log(`  ${label} ${fmtPace(pace).padStart(10)}   (~${distanceInHour.toFixed(2)} mi in 1hr)`);
    } else {
      console.log(`  ${label} ${fmtPace(pace).padStart(10)}   total: ${fmtTime(totalTime)}`);
    }
  }

  // Training zones (ranges)
  console.log("Training zones (% of MP speed):");
  const mpPace = table.mp;
  const trainingZones: Array<[PaceZone, string]> = [
    ["steady",   "Steady     "],
    ["moderate", "Moderate   "],
    ["easy",     "Easy       "],
    ["recovery", "Recovery   "],
  ];
  for (const [zone, label] of trainingZones) {
    const band = trainingZoneRange(zone, mpPace);
    if (band) {
      console.log(`  ${label} ${fmtPace(band.fastSec)} – ${fmtPace(band.slowSec)}   (${band.bandLabel})`);
    }
  }
  console.log("");
}

// ── Tests ───────────────────────────────────────────────

test("race anchor calculator — print and pin each athlete", () => {
  for (const a of ATHLETES) {
    printPaceTable(a);
  }
});

// Pin the reference calibration so silent drift in the ratio table is caught.
test("reference calibration: 2:20 marathon → mile ≈ 4:14 / 5K ≈ 14:34", () => {
  const raceSecPerMile = 8400 / 26.2188;
  const table = derivePaceTableFromGoal(raceSecPerMile, "marathon");

  const mileSeconds = table.mile * 1.0;
  const fiveKSeconds = table.fiveK * 3.1069;

  // Mile target: 4:14 ± 5s
  assert.ok(
    Math.abs(mileSeconds - 254) < 5,
    `2:20 marathoner mile should be ~4:14 (254s), got ${fmtTime(mileSeconds)} (${Math.round(mileSeconds)}s)`,
  );
  // 5K target: 14:34 ± 10s (docs round to 14:34, exact ratio gives 14:36ish)
  assert.ok(
    Math.abs(fiveKSeconds - 874) < 10,
    `2:20 marathoner 5K should be ~14:34 (874s), got ${fmtTime(fiveKSeconds)} (${Math.round(fiveKSeconds)}s)`,
  );
});

// Pin Athlete A's marathon prediction so we know if the ratios change.
test("Athlete A (4:34 mile) → marathon prediction is stable", () => {
  const raceSecPerMile = 274 / 1.0;
  const table = derivePaceTableFromGoal(raceSecPerMile, "mile");
  const marathonSeconds = table.mp * 26.2188;

  // Expected from current ratios: ~2:31:02 (9061.5s)
  assert.ok(
    Math.abs(marathonSeconds - 9062) < 30,
    `4:34 miler marathon prediction should be ~2:31:02 (9062s), got ${fmtTime(marathonSeconds)} (${Math.round(marathonSeconds)}s)`,
  );
});

// Pin LT ordering: for Athlete A, LT should be faster than HM (sub-1hr 10mi territory).
test("Athlete A: LT pace is faster than HM pace", () => {
  const raceSecPerMile = 274 / 1.0;
  const table = derivePaceTableFromGoal(raceSecPerMile, "mile");
  assert.ok(
    table.threshold < table.hm,
    `LT (${fmtPace(table.threshold)}) should be faster than HM (${fmtPace(table.hm)})`,
  );
});
