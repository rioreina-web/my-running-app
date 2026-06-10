// Single source of truth for race distances and mile/km conversion factors.
// Mirrors Swift's `RaceDistanceConstants` in
// /RunningLog/RunningLog/Workouts/PaceCalculator.swift — keep the two in sync.
//
// Values are derived from the international mile (1609.344 m exactly) and the
// IAAF-standard 42.195 km marathon.

export const RACE_DISTANCE_CONSTANTS = {
  marathonMiles: 26.21875,        // 42.195 km / 1.609344
  halfMarathonMiles: 13.109375,   // marathonMiles / 2
  tenKMiles: 6.2137119,           // 10 km / 1.609344
  fiveKMiles: 3.1068560,          // 5 km  / 1.609344
  meterPerMile: 1609.344,         // exact definition
  kmPerMile: 1.609344,            // exact definition
} as const;
