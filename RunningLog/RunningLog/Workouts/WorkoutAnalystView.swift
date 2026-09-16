//
//  WorkoutAnalystView.swift
//  RunningLog
//
//  REMOVED 2026-06-16 during the workout-detail consolidation.
//
//  This was "Direction B · Analyst" — a 12-chart stream-analysis screen that
//  rendered off the `external_streams` JSONB. It was the view a Strava tap
//  opened, and it showed "0 SPLITS" with empty pace + cadence because the
//  stream parser (`ExternalStreamAdapter.buildVitalStream`) silently dropped
//  mixed Int/Double arrays (distance / velocity_smooth / cadence). That parser
//  bug is now fixed, but the screen itself is retired.
//
//  The single canonical workout detail is `WorkoutRepChart`, presented via
//  `WorkoutRepDetailSheet`. It reads the clean rep-level `running_workout_laps`
//  table instead of the stream blob. Full implementation history is in git.
//
