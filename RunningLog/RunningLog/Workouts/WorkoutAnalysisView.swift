//
//  WorkoutAnalysisView.swift
//  RunningLog
//
//  REMOVED 2026-06-16 during the workout-detail consolidation.
//
//  This was a source-agnostic peer of WorkoutAnalystView (it rendered a
//  SplitsTable from `pace_segments` plus stream cards). It was never the
//  primary tap target — only a fallback — and it duplicated the same
//  external_streams-based plumbing.
//
//  The single canonical workout detail is `WorkoutRepChart`, presented via
//  `WorkoutRepDetailSheet`. The `PaceSegmentsLoader` / `ParsedStructureLoader`
//  helpers that used to live here were only consumed by this view; the
//  prescribed-workout context now loads via
//  `WorkoutLapsService.fetchPrescription`. Full history is in git.
//
