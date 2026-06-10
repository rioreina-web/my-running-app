import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { GoogleGenerativeAI } from "https://esm.sh/@google/generative-ai@0.24.0";
import { getAuthenticatedUser, unauthorizedResponse } from "../_shared/auth.ts";
import { checkFeatureRateLimit, isRateLimitEnabled } from "../_shared/rateLimit.ts";
import {
  validateLength,
  validationErrorResponse,
  internalErrorResponse,
} from "../_shared/validation.ts";
import { generatePlanSkeleton } from "./deterministic-builder.ts";
import type { SkeletonRunnerProfile, WeeklySkeleton, AIWorkoutSelection, AIFinalOutput } from "./deterministic-builder.ts";
import { corsHeaders } from "../_shared/cors.ts";

// ── Workout Library (source of truth — TrainingPRD) ─────────────

interface WorkoutDef {
  workoutType: string;
  name: string;
  description: string;
  pacePercentage: number;
  focusArea: string;
  recoveryType: string;
}

const WORKOUT_LIBRARY: Record<string, WorkoutDef> = {
  // ─── MARATHON: 0.80 Basic Endurance ────────────────────────────

  BE_1:  { workoutType: "long_run", name: "10mi Easy",         description: "10mi easy at 80%",                        pacePercentage: 80, focusArea: "Endurance", recoveryType: "Steady State" },
  BE_2:  { workoutType: "long_run", name: "12mi Easy",         description: "12mi easy at 80%",                        pacePercentage: 80, focusArea: "Endurance", recoveryType: "Steady State" },
  BE_3:  { workoutType: "long_run", name: "15mi Easy",         description: "15mi easy at 80%",                        pacePercentage: 80, focusArea: "Endurance", recoveryType: "Steady State" },
  BE_4:  { workoutType: "long_run", name: "18mi Easy",         description: "18mi easy at 80%",                        pacePercentage: 80, focusArea: "Endurance", recoveryType: "Steady State" },
  BE_5:  { workoutType: "long_run", name: "20mi Easy",         description: "20mi easy at 80%",                        pacePercentage: 80, focusArea: "Endurance", recoveryType: "Steady State" },
  BE_6:  { workoutType: "long_run", name: "22mi Easy",         description: "22mi easy at 80%",                        pacePercentage: 80, focusArea: "Endurance", recoveryType: "Steady State" },
  BE_7:  { workoutType: "long_run", name: "24mi Easy",         description: "24mi easy at 80%",                        pacePercentage: 80, focusArea: "Endurance", recoveryType: "Steady State" },
  BE_8:  { workoutType: "long_run", name: "2hr Rolling Hills", description: "2 hrs easy over rolling hills at 80%",    pacePercentage: 80, focusArea: "Endurance", recoveryType: "Steady State" },

  // ─── MARATHON: 0.85 General Endurance ──────────────────────────

  GE_1:  { workoutType: "long_run", name: "10mi Moderate",         description: "10mi moderate at 85%",                    pacePercentage: 85, focusArea: "Endurance", recoveryType: "Steady State" },
  GE_2:  { workoutType: "long_run", name: "12mi Moderate",         description: "12mi moderate at 85%",                    pacePercentage: 85, focusArea: "Endurance", recoveryType: "Steady State" },
  GE_3:  { workoutType: "long_run", name: "15mi Moderate",         description: "15mi moderate at 85%",                    pacePercentage: 85, focusArea: "Endurance", recoveryType: "Steady State" },
  GE_4:  { workoutType: "long_run", name: "18mi Moderate",         description: "18mi moderate at 85%",                    pacePercentage: 85, focusArea: "Endurance", recoveryType: "Steady State" },
  GE_5:  { workoutType: "long_run", name: "20mi Moderate",         description: "20mi moderate at 85%",                    pacePercentage: 85, focusArea: "Endurance", recoveryType: "Steady State" },
  GE_6:  { workoutType: "long_run", name: "22mi Moderate",         description: "22mi moderate at 85%",                    pacePercentage: 85, focusArea: "Endurance", recoveryType: "Steady State" },
  GE_7:  { workoutType: "long_run", name: "1hr Progression",       description: "1hr progression (80% > 90%)",             pacePercentage: 85, focusArea: "Endurance", recoveryType: "Steady State" },
  GE_8:  { workoutType: "long_run", name: "90min Progression",     description: "90 min progression (80% > 90%)",          pacePercentage: 85, focusArea: "Endurance", recoveryType: "Steady State" },
  GE_9:  { workoutType: "long_run", name: "2hr Progression",       description: "2hr progression (80% > 90%)",             pacePercentage: 85, focusArea: "Endurance", recoveryType: "Steady State" },
  GE_10: { workoutType: "long_run", name: "20mi Progression 80>90%", description: "20mi progression (80% > 90%)",          pacePercentage: 85, focusArea: "Endurance", recoveryType: "Steady State" },

  // ─── MARATHON: 0.90 Race-Supportive Endurance ──────────────────

  RSE_1: { workoutType: "long_run", name: "8mi Steady State",      description: "8mi steady state at 90%",                 pacePercentage: 90, focusArea: "Endurance", recoveryType: "Steady State" },
  RSE_2: { workoutType: "long_run", name: "10mi Steady State",     description: "10mi steady state at 90%",                pacePercentage: 90, focusArea: "Endurance", recoveryType: "Steady State" },
  RSE_3: { workoutType: "long_run", name: "12mi Steady State",     description: "12mi steady state at 90%",                pacePercentage: 90, focusArea: "Endurance", recoveryType: "Steady State" },
  RSE_4: { workoutType: "long_run", name: "15mi Steady State",     description: "15mi steady state at 90%",                pacePercentage: 90, focusArea: "Endurance", recoveryType: "Steady State" },
  RSE_5: { workoutType: "long_run", name: "18mi Steady State",     description: "18mi steady state at 90%",                pacePercentage: 90, focusArea: "Endurance", recoveryType: "Steady State" },
  RSE_6: { workoutType: "long_run", name: "20mi Progression",      description: "20mi progression (85% > 92%)",            pacePercentage: 90, focusArea: "Endurance", recoveryType: "Steady State" },
  RSE_7: { workoutType: "workout",  name: "10x1km Alternations",   description: "10x1km at 95% w/ 1km at 85% (20km total)", pacePercentage: 90, focusArea: "Alternations", recoveryType: "Continuous" },
  RSE_8: { workoutType: "workout",  name: "8x1mi Alternations",    description: "8x1mi at 95% w/ 1mi at 85% (16mi total)", pacePercentage: 90, focusArea: "Alternations", recoveryType: "Continuous" },
  RSE_9: { workoutType: "long_run", name: "20mi Progression 85>95%", description: "20mi progression (85% > 95%)",          pacePercentage: 90, focusArea: "Progression", recoveryType: "Continuous" },
  RSE_10:{ workoutType: "long_run", name: "15mi at 90-95%",         description: "15mi steady at 90% > 95%",               pacePercentage: 92, focusArea: "Race Simulation", recoveryType: "Continuous" },

  // ─── MARATHON: 0.95 Race-Specific Endurance ────────────────────

  RCE_1: { workoutType: "long_run", name: "10mi at 95%",           description: "10mi continuous at 95%",                  pacePercentage: 95, focusArea: "Race Simulation", recoveryType: "Continuous" },
  RCE_2: { workoutType: "long_run", name: "12mi at 95%",           description: "12mi continuous at 95%",                  pacePercentage: 95, focusArea: "Race Simulation", recoveryType: "Continuous" },
  RCE_3: { workoutType: "long_run", name: "15mi at 95%",           description: "15mi continuous at 95%",                  pacePercentage: 95, focusArea: "Race Simulation", recoveryType: "Continuous" },
  RCE_4: { workoutType: "long_run", name: "18mi 90>95%",           description: "18mi continuous at (90% > 95%)",          pacePercentage: 95, focusArea: "Race Simulation", recoveryType: "Continuous" },
  RCE_5: { workoutType: "workout",  name: "4x3mi at 95%",         description: "4x3mi at 95% w/ 1mi at 85%",             pacePercentage: 95, focusArea: "Race Simulation", recoveryType: "Float" },
  RCE_6: { workoutType: "workout",  name: "4x4mi at 95%",         description: "4x4mi at 95% w/ 1mi at 85%",             pacePercentage: 95, focusArea: "Race Simulation", recoveryType: "Float" },
  RCE_7: { workoutType: "workout",  name: "5x3mi at 95%",         description: "5x3mi at 95% w/ 1mi at 85%",             pacePercentage: 95, focusArea: "Race Simulation", recoveryType: "Float" },
  RCE_8: { workoutType: "long_run", name: "15k/10k/5k Progression", description: "15km at 90% + 10km at 95% + 5km at 100%", pacePercentage: 95, focusArea: "Progression", recoveryType: "Continuous" },

  // ─── MARATHON: 1.00 Race Pace ──────────────────────────────────

  RP_1:  { workoutType: "long_run", name: "10mi at MP",            description: "10mi continuous at MP",                   pacePercentage: 100, focusArea: "Race Simulation", recoveryType: "Continuous" },
  RP_2:  { workoutType: "long_run", name: "12mi at MP",            description: "12mi continuous at MP",                   pacePercentage: 100, focusArea: "Race Simulation", recoveryType: "Continuous" },
  RP_3:  { workoutType: "workout",  name: "10x1mi at MP",         description: "10x1mi at MP w/ .5mi float at 90%",      pacePercentage: 100, focusArea: "Specific Alternations", recoveryType: "Float" },
  RP_4:  { workoutType: "workout",  name: "5x2mi at MP",          description: "5x2mi at MP w/ .5mi at 85% float",       pacePercentage: 100, focusArea: "Specific Alternations", recoveryType: "Float" },
  RP_5:  { workoutType: "workout",  name: "6x2mi at MP",          description: "6x2mi at MP w/ 1mi at 90% float",        pacePercentage: 100, focusArea: "Specific Alternations", recoveryType: "Float" },
  RP_6:  { workoutType: "workout",  name: "4x3mi at MP",          description: "4x3mi at MP w/ 1mi at 85% float",        pacePercentage: 100, focusArea: "Specific Alternations", recoveryType: "Float" },
  RP_7:  { workoutType: "workout",  name: "5x3mi at MP",          description: "5x3mi at MP w/ .5mi at 85% float",       pacePercentage: 100, focusArea: "Specific Alternations", recoveryType: "Float" },
  RP_8:  { workoutType: "workout",  name: "2x5mi at MP",          description: "2x5mi at MP w/ 1mi at 85% float",        pacePercentage: 100, focusArea: "Specific Alternations", recoveryType: "Float" },
  RP_9:  { workoutType: "workout",  name: "3x5mi at MP",          description: "3x5mi at MP w/ 1mi at 90% float",        pacePercentage: 100, focusArea: "Specific Alternations", recoveryType: "Float" },
  RP_10: { workoutType: "workout",  name: "2x6mi at MP",          description: "2x6mi at MP w/ 1mi at 85% float",        pacePercentage: 100, focusArea: "Specific Alternations", recoveryType: "Float" },
  RP_11: { workoutType: "workout",  name: "10x1km at 102%",       description: "10x1km at 102% w/ 1km at 95% float",     pacePercentage: 102, focusArea: "Specific Alternations", recoveryType: "Float" },
  RP_12: { workoutType: "workout",  name: "8x2km at MP",          description: "8x2km at MP w/ 1km at 90% float",        pacePercentage: 100, focusArea: "Specific Alternations", recoveryType: "Float" },
  RP_13: { workoutType: "workout",  name: "10x2km at MP",         description: "10x2km at MP w/ 1km at 85% float",       pacePercentage: 100, focusArea: "Specific Alternations", recoveryType: "Float" },
  RP_14: { workoutType: "workout",  name: "6x3km at MP",          description: "6x3km at MP w/ 1km at 90% float",        pacePercentage: 100, focusArea: "Specific Alternations", recoveryType: "Float" },
  RP_15: { workoutType: "workout",  name: "4x4km at MP",          description: "4x4km at MP w/ 1km at 85% float",        pacePercentage: 100, focusArea: "Specific Alternations", recoveryType: "Float" },
  RP_16: { workoutType: "workout",  name: "5x4km at MP",          description: "5x4km at MP w/ 1km at 90% float",        pacePercentage: 100, focusArea: "Specific Alternations", recoveryType: "Float" },
  RP_17: { workoutType: "workout",  name: "4x5km at MP",          description: "4x5km at MP w/ 1km at 85% float",        pacePercentage: 100, focusArea: "Specific Alternations", recoveryType: "Float" },
  RP_18: { workoutType: "workout",  name: "5x5km at MP",          description: "5x5km at MP w/ 1km at 90% float",        pacePercentage: 100, focusArea: "Specific Alternations", recoveryType: "Float" },
  RP_19: { workoutType: "workout",  name: "MP Descending Ladder", description: "7km-6km-5km-4km-3km-2km at MP w/ 1km at 85%", pacePercentage: 100, focusArea: "Progression Alternations", recoveryType: "Float" },

  // ─── MARATHON: 1.05 Race-Specific Speed ────────────────────────

  RSS_1:  { workoutType: "workout", name: "8 x 3' Steady",          description: "8x3' steady w/ 2' moderate at 105%",     pacePercentage: 105, focusArea: "Fartlek", recoveryType: "Continuous" },
  RSS_2:  { workoutType: "workout", name: "6x6' Fartlek",          description: "6x6' steady w/ 3' easy at 105%",         pacePercentage: 105, focusArea: "Fartlek", recoveryType: "Continuous" },
  RSS_3:  { workoutType: "workout", name: "12x2' Fartlek",         description: "12x2' fast w/ 2' easy at 105%",          pacePercentage: 105, focusArea: "Fartlek", recoveryType: "Continuous" },
  RSS_4:  { workoutType: "workout", name: "10x3' Fartlek",         description: "10x3' steady w/ 2' moderate at 105%",    pacePercentage: 105, focusArea: "Fartlek", recoveryType: "Continuous" },
  RSS_4b: { workoutType: "workout", name: "10x3'/3' Alternation", description: "10x3' fast w/ 3' moderate at 105%",      pacePercentage: 105, focusArea: "Fartlek", recoveryType: "Continuous" },
  RSS_5:  { workoutType: "workout", name: "10x800m at 107%",       description: "10x800m at 107% w/ 1' rest",             pacePercentage: 107, focusArea: "Specific Speed", recoveryType: "Jog" },
  RSS_6:  { workoutType: "workout", name: "10x1km at 107%",        description: "10x1km at 107% w/ 1' rest",              pacePercentage: 107, focusArea: "Specific Speed", recoveryType: "Jog" },
  RSS_7:  { workoutType: "workout", name: "6xMile at 107%",        description: "6x mile at 107% w/ 1' rest",             pacePercentage: 107, focusArea: "Specific Speed", recoveryType: "Jog" },
  RSS_8:  { workoutType: "workout", name: "3x2mi at 106%",         description: "3x2mi at 106% w/ .5mi float at 80%",     pacePercentage: 106, focusArea: "Specific Speed", recoveryType: "Float" },
  RSS_9:  { workoutType: "workout", name: "12x1km at 106%",        description: "12x1km at 106% w/ 1' rest",              pacePercentage: 106, focusArea: "Specific Speed", recoveryType: "Jog" },
  RSS_10: { workoutType: "workout", name: "8xMile at 105%",        description: "8x mile at 105% w/ 1' rest",             pacePercentage: 105, focusArea: "Specific Speed", recoveryType: "Jog" },
  RSS_11: { workoutType: "workout", name: "3mi/2mi/1mi Cutdown",   description: "3mi/2mi/1mi at 105%/107%/110% w/ .5mi float 80%", pacePercentage: 105, focusArea: "Specific Speed", recoveryType: "Continuous" },
  RSS_12: { workoutType: "workout", name: "2x3mi at 104%",         description: "2x3mi at 104% w/ .5mi float",            pacePercentage: 104, focusArea: "Specific Speed", recoveryType: "Float" },
  RSS_13: { workoutType: "workout", name: "7mi Progression",       description: "7mi progression at 97% > 105%",          pacePercentage: 105, focusArea: "Progression", recoveryType: "Float" },
  RSS_14: { workoutType: "workout", name: "3x2mi at 105%",        description: "3x2mi at 105% w/ .5mi float at 85%",     pacePercentage: 105, focusArea: "Specific Speed", recoveryType: "Float" },
  RSS_15: { workoutType: "workout", name: "2x4mi at 105%",        description: "2x4mi at 105% w/ .5mi float at 85%",     pacePercentage: 105, focusArea: "Specific Speed", recoveryType: "Float" },
  RSS_16: { workoutType: "workout", name: "6xMile at 105%",       description: "6x mile at 105% w/ 1' float",            pacePercentage: 105, focusArea: "Specific Speed", recoveryType: "Float" },
  RSS_17: { workoutType: "workout", name: "4xMile at 105%",       description: "4x mile at 105% w/ 2' rest",             pacePercentage: 105, focusArea: "Specific Speed", recoveryType: "Jog" },
  RSS_18: { workoutType: "workout", name: "2x3mi at 105%",        description: "2x3mi at 105% w/ .5mi float at 85%",     pacePercentage: 105, focusArea: "Specific Speed", recoveryType: "Float" },
  RSS_19: { workoutType: "workout", name: "7mi Progression 97>103%", description: "7mi progression at 97% > 103%",        pacePercentage: 101, focusArea: "Progression", recoveryType: "Continuous" },

  // ─── MARATHON: 1.10 Race-Supportive Speed ──────────────────────

  RSPS_1: { workoutType: "workout", name: "12x400m at 110%",       description: "12x400m at 110% w/ 1' rest",             pacePercentage: 110, focusArea: "Speed", recoveryType: "Jog" },
  RSPS_2: { workoutType: "workout", name: "8x800m at 110%",        description: "8x800m at 110% w/ 90s rest",            pacePercentage: 110, focusArea: "Speed", recoveryType: "Jog" },
  RSPS_3: { workoutType: "workout", name: "3x4x800m at 110%",      description: "3 sets of 4x800m at 110% w/ 1' rest & 4' rest b/t sets", pacePercentage: 110, focusArea: "Speed", recoveryType: "Jog" },
  RSPS_4: { workoutType: "workout", name: "12x600m at 110%",       description: "12x600m at 110% w/ 200m float",          pacePercentage: 110, focusArea: "Speed", recoveryType: "Float" },
  RSPS_5: { workoutType: "workout", name: "8x1000m at 110%",       description: "8x1000m at 110% w/ 2 min jog",           pacePercentage: 110, focusArea: "Speed", recoveryType: "Jog" },
  RSPS_6: { workoutType: "workout", name: "5xMile at 110%",        description: "5x1mi at 110% w/ 2.5 min jog",           pacePercentage: 110, focusArea: "Speed", recoveryType: "Jog" },
  RSPS_7: { workoutType: "workout", name: "6x1200m at 110%",       description: "6x1200m at 110% w/ 2' jog",              pacePercentage: 110, focusArea: "Speed", recoveryType: "Jog" },
  RSPS_8: { workoutType: "workout", name: "3x4x800m at 108%",     description: "3 sets of 4x800m at 108% w/ 1' rest & 400m jog b/t sets", pacePercentage: 108, focusArea: "Speed", recoveryType: "Jog" },

  // ─── MARATHON: 1.15 Mechanical Speed ───────────────────────────

  GS_1: { workoutType: "workout", name: "12x200m at 115%",         description: "12x200m at 115% w/ 200m jog",            pacePercentage: 115, focusArea: "Neuromuscular", recoveryType: "Jog" },
  GS_2: { workoutType: "workout", name: "12x300m at 115%",         description: "12x300m at 115% w/ 200m float at 80%",   pacePercentage: 115, focusArea: "Neuromuscular", recoveryType: "Jog" },
  GS_3: { workoutType: "workout", name: "10x400m at 115%",         description: "10x400m at 115% w/ 200m jog",            pacePercentage: 115, focusArea: "Neuromuscular", recoveryType: "Jog" },
  GS_4: { workoutType: "workout", name: "12x400m at 115%",         description: "12x400m at 115% w/ 400m jog",            pacePercentage: 115, focusArea: "Neuromuscular", recoveryType: "Jog" },
  GS_5: { workoutType: "workout", name: "Hill Sprints 10sec",      description: "8x10 sec steep hill sprints w/ full recovery", pacePercentage: 115, focusArea: "Neuromuscular", recoveryType: "Walk" },
  GS_6: { workoutType: "workout", name: "Fast Strides 100m",       description: "8x100m fast strides",                    pacePercentage: 115, focusArea: "Neuromuscular", recoveryType: "Walk" },
  GS_7: { workoutType: "workout", name: "Hill Sprints 15sec",      description: "10x15 sec steep hill sprints w/ full recovery", pacePercentage: 115, focusArea: "Neuromuscular", recoveryType: "Walk" },
  GS_8: { workoutType: "workout", name: "Hill Sprints 8x15s",     description: "8x15 sec hill sprints w/ full recovery",   pacePercentage: 115, focusArea: "Neuromuscular", recoveryType: "Walk" },

  // ─── SPECIAL ───────────────────────────────────────────────────

  FARTLEK: { workoutType: "workout", name: "8x3' Steady + 2' Easy", description: "8x3' steady / 2' easy", pacePercentage: 85, focusArea: "Fartlek", recoveryType: "Continuous" },
  EASY:    { workoutType: "easy",    name: "Easy Run", description: "Easy conversational pace at 70-75%", pacePercentage: 70, focusArea: "Recovery", recoveryType: "Steady State" },
  REST:    { workoutType: "rest",    name: "Rest Day", description: "Rest day", pacePercentage: 0, focusArea: "Recovery", recoveryType: "Steady State" },
  STRIDES: { workoutType: "strides", name: "Easy Run + Strides", description: "Easy run + 4-6x100m strides at 115%", pacePercentage: 70, focusArea: "Neuromuscular", recoveryType: "Walk" },
  RACE:    { workoutType: "race",    name: "Race Day", description: "Race day", pacePercentage: 100, focusArea: "Race Simulation", recoveryType: "Continuous" },
};

const VALID_CODES = new Set(Object.keys(WORKOUT_LIBRARY));

// ── Authoritative Workout Distances ─────────────────────────────
// Total session miles for every workout code. Includes warmup, intervals,
// recovery, and cooldown. NEVER trust the LLM's totalDistanceMiles —
// always use this table for quality workouts.

const WORKOUT_DISTANCES: Record<string, number> = {
  // 0.80 Basic Endurance
  BE_1: 10, BE_2: 12, BE_3: 15, BE_4: 18, BE_5: 20, BE_6: 22, BE_7: 24, BE_8: 16,
  // 0.85 General Endurance
  GE_1: 10, GE_2: 12, GE_3: 15, GE_4: 18, GE_5: 20, GE_6: 22,
  GE_7: 8, GE_8: 11, GE_9: 16, GE_10: 20,
  // 0.90 Race-Supportive Endurance
  RSE_1: 8, RSE_2: 10, RSE_3: 12, RSE_4: 15, RSE_5: 18,
  RSE_6: 20, RSE_7: 16, RSE_8: 16, RSE_9: 20, RSE_10: 15,
  // 0.95 Race-Specific Endurance
  RCE_1: 10, RCE_2: 12, RCE_3: 15, RCE_4: 18,
  RCE_5: 16, RCE_6: 20, RCE_7: 19, RCE_8: 19,
  // 1.00 Race Pace
  RP_1: 10, RP_2: 12, RP_3: 14, RP_4: 14, RP_5: 17, RP_6: 16, RP_7: 17,
  RP_8: 12, RP_9: 18, RP_10: 14, RP_11: 16, RP_12: 18, RP_13: 21,
  RP_14: 16, RP_15: 13, RP_16: 17, RP_17: 16, RP_18: 20, RP_19: 21,
  // 1.05 Race-Specific Speed
  RSS_1: 12, RSS_2: 10, RSS_3: 10, RSS_4: 10, RSS_4b: 10,
  RSS_5: 10, RSS_6: 12, RSS_7: 12, RSS_8: 10, RSS_9: 13, RSS_10: 14,
  RSS_11: 10, RSS_12: 9, RSS_13: 11,
  RSS_14: 9, RSS_15: 12, RSS_16: 12, RSS_17: 10, RSS_18: 9, RSS_19: 11,
  // 1.10 Race-Supportive Speed
  RSPS_1: 7, RSPS_2: 9, RSPS_3: 10, RSPS_4: 9,
  RSPS_5: 10, RSPS_6: 11, RSPS_7: 14, RSPS_8: 10,
  // 1.15 Mechanical Speed
  GS_1: 7, GS_2: 7, GS_3: 6, GS_4: 8, GS_5: 6, GS_6: 5, GS_7: 6, GS_8: 6,
  // Special
  FARTLEK: 8,
};

// ── Runner Profile (derived from fitness assessment) ────────────

interface RunnerProfile {
  fitnessLevel: "beginner" | "novice" | "intermediate" | "advanced" | "elite";
  yearsRunning: string;
  consistencyLevel: string;
  currentWeeklyMileage: number;
  recommendedStartingMileage: number;
  recommendedPeakMileage: number;
  runsPerWeek: number;
  canRunDoubles: boolean;
  maxSessionMinutes: number;
  goalTimeSeconds: number;
  fitnessIndex: number | null;
  goalIsRealistic: boolean;
  suggestedGoalTimeSeconds: number | null;
  hasAccessToTrack: boolean;
  preferredWorkoutTypes: string[];
  excludedWorkoutCodes: string[];
  preferredLongRunDay: number;
  workout1Day: number;
  workout2Day: number;
  restDayCount: number;
  hasInjury: boolean;
  injuryDetails: string | null;
  riskLevel: "low" | "moderate" | "high";
  maxMileageJumpPercent: number;
  requiresExtraRecovery: boolean;
  crossTrainingActivities: string[];
}

// ── Fitness Index Tables (abridged, covers FI 30-85) ──

const FI_MARATHON: [number, number][] = [
  [30, 17820], [33, 16200], [35, 15300], [37, 14400], [40, 13500],
  [42, 12900], [45, 12000], [48, 11100], [50, 10800], [52, 10200],
  [55, 9600],  [58, 9000],  [60, 8700],  [63, 8100],  [65, 7800],
  [68, 7200],  [70, 6900],  [73, 6600],  [75, 6300],  [80, 5700],
  [85, 5100],
];

const FI_HM: [number, number][] = [
  [30, 8280], [33, 7500], [35, 7080], [37, 6660], [40, 6240],
  [42, 5940], [45, 5520], [48, 5100], [50, 4980], [52, 4680],
  [55, 4380], [58, 4080], [60, 3960], [63, 3660], [65, 3540],
  [68, 3300], [70, 3180], [75, 2880], [80, 2580], [85, 2340],
];

const FI_10K: [number, number][] = [
  [30, 3720], [33, 3360], [35, 3180], [37, 3000], [40, 2820],
  [42, 2700], [45, 2520], [48, 2340], [50, 2280], [52, 2160],
  [55, 2040], [58, 1920], [60, 1860], [63, 1740], [65, 1680],
  [68, 1560], [70, 1500], [75, 1380], [80, 1260], [85, 1140],
];

const FI_5K: [number, number][] = [
  [30, 1800], [33, 1620], [35, 1530], [37, 1440], [40, 1350],
  [42, 1290], [45, 1200], [48, 1110], [50, 1080], [52, 1020],
  [55, 960],  [58, 900],  [60, 870],  [63, 810],  [65, 780],
  [68, 720],  [70, 690],  [75, 630],  [80, 570],  [85, 510],
];

function interpolateFI(table: [number, number][], timeSec: number): number {
  for (let i = 0; i < table.length - 1; i++) {
    const [v1, t1] = table[i];
    const [v2, t2] = table[i + 1];
    if (timeSec <= t1 && timeSec >= t2) {
      return v1 + ((t1 - timeSec) / (t1 - t2)) * (v2 - v1);
    }
  }
  if (timeSec >= table[0][1]) return table[0][0];
  return table[table.length - 1][0];
}

function computeFIFromPRs(a: Record<string, unknown>): number | null {
  const estimates: number[] = [];
  if (a.marathonPR) estimates.push(interpolateFI(FI_MARATHON, a.marathonPR as number));
  if (a.halfMarathonPR) estimates.push(interpolateFI(FI_HM, a.halfMarathonPR as number));
  if (a.recent10kTime) estimates.push(interpolateFI(FI_10K, a.recent10kTime as number));
  if (a.recent5kTime) estimates.push(interpolateFI(FI_5K, a.recent5kTime as number));
  if (estimates.length === 0) return null;
  estimates.sort((a, b) => a - b);
  return Math.round(estimates[Math.floor(estimates.length / 2)] * 10) / 10;
}

function fiTable(dist: string): [number, number][] {
  if (dist === "5k") return FI_5K;
  if (dist === "10k") return FI_10K;
  if (dist === "half_marathon") return FI_HM;
  return FI_MARATHON;
}

function filterWorkoutCodes(
  level: string, hasTrack: boolean, maxMinutes: number, mileage: number,
): string[] {
  const excluded: string[] = [];

  // No track → remove short track repeats
  if (!hasTrack) {
    excluded.push("GS_1", "GS_2", "GS_3", "GS_4", "RSPS_1", "RSPS_3", "RSPS_4");
  }

  // Beginner: no high-volume or high-intensity codes
  if (level === "beginner") {
    excluded.push("BE_5", "BE_6", "BE_7", "GE_5", "GE_6", "RSE_5", "RSE_6", "RSE_9");
    excluded.push("RSS_9", "RSS_10", "RSPS_6", "RSPS_7");
    excluded.push("RCE_3", "RCE_4", "RCE_5", "RCE_6", "RCE_7", "RCE_8");
    excluded.push("RP_5", "RP_6", "RP_7");
  }

  if (level === "novice") {
    excluded.push("BE_6", "BE_7", "GE_6", "RSE_9");
    excluded.push("RCE_6", "RCE_7", "RCE_8");
    excluded.push("RP_7");
  }

  // Time-limited → remove long sessions (rough: 9 min/mi avg including rest)
  if (maxMinutes <= 45) {
    const maxMi = maxMinutes / 9;
    for (const [code, def] of Object.entries(WORKOUT_LIBRARY)) {
      const descDist = def.description.match(/(\d+)\s*mi/);
      if (descDist && parseInt(descDist[1]) > maxMi) excluded.push(code);
    }
  }

  // Low mileage → no high-rep sessions
  if (mileage < 20) {
    excluded.push("RSS_9", "RSS_10", "RSPS_7", "RSPS_8");
  }

  return [...new Set(excluded)];
}

function buildRunnerProfile(
  assessment: Record<string, unknown>,
  goalTimeSec: number,
  raceDistance: string,
  currentMileage: number,
): RunnerProfile {
  const wa = (assessment.workoutAnalysis as Record<string, unknown>) || {};
  const ai = (assessment.aiAssessment as Record<string, unknown>) || {};

  // Fitness level
  const fitnessLevel = (ai.fitnessLevel as string) ||
    (currentMileage < 15 ? "beginner" : currentMileage < 25 ? "novice" :
     currentMileage < 45 ? "intermediate" : currentMileage < 65 ? "advanced" : "elite");

  // Fitness Index
  const fiFromAnalysis = (wa.fitnessIndex as number) || null;
  const fiFromPRs = computeFIFromPRs(assessment);
  const fitnessIndex = fiFromAnalysis || fiFromPRs;

  // Goal validation
  let goalIsRealistic = true;
  if (ai.goalIsRealistic !== undefined) {
    goalIsRealistic = ai.goalIsRealistic as boolean;
  } else if (fitnessIndex && goalTimeSec) {
    const requiredFI = interpolateFI(fiTable(raceDistance), goalTimeSec);
    goalIsRealistic = requiredFI <= fitnessIndex + 3;
  }
  const suggestedGoalTimeSeconds = (ai.suggestedGoalTime as number) || null;

  // Time availability → session cap
  const timeMap: Record<string, number> = { limited: 45, moderate: 75, flexible: 90, abundant: 120 };
  const maxSessionMinutes = timeMap[(assessment.timeAvailablePerDay as string) || "moderate"] || 75;

  // Volume
  const recommendedStarting = (ai.recommendedStartingMileage as number) || currentMileage;
  const recommendedPeak = (ai.recommendedPeakMileage as number) || Math.round(currentMileage * 1.5);

  // Safety
  const hasInjury = (assessment.recentInjury as boolean) || false;
  const consistencyLevel = (assessment.consistencyLevel as string) || "mostly_consistent";
  const riskFactors = (ai.riskFactors as Array<Record<string, unknown>>) || [];
  const highRiskCount = riskFactors.filter(r => r.severity === "high").length;
  const riskLevel = highRiskCount > 0 ? "high" : (hasInjury || consistencyLevel === "returning") ? "moderate" : "low";

  let maxMileageJumpPercent = 10;
  if (riskLevel === "high") maxMileageJumpPercent = 5;
  else if (riskLevel === "moderate") maxMileageJumpPercent = 7;
  else if (fitnessLevel === "beginner" || fitnessLevel === "novice") maxMileageJumpPercent = 8;

  const requiresExtraRecovery = hasInjury || consistencyLevel === "returning" || consistencyLevel === "inconsistent";

  // Workout filtering
  const hasTrack = (assessment.hasAccessToTrack as boolean) ?? true;
  const excluded = filterWorkoutCodes(fitnessLevel, hasTrack, maxSessionMinutes, currentMileage);

  // Scheduling
  const runsPerWeek = (assessment.runsPerWeek as number) || 6;
  const dayMap: Record<string, number> = {
    monday: 1, tuesday: 2, wednesday: 3, thursday: 4, friday: 5, saturday: 6, sunday: 7,
  };

  return {
    fitnessLevel: fitnessLevel as RunnerProfile["fitnessLevel"],
    yearsRunning: (assessment.yearsRunning as string) || "2_to_5",
    consistencyLevel,
    currentWeeklyMileage: currentMileage,
    recommendedStartingMileage: recommendedStarting,
    recommendedPeakMileage: recommendedPeak,
    runsPerWeek,
    canRunDoubles: (assessment.canRunDoubles as boolean) || false,
    maxSessionMinutes,
    goalTimeSeconds: goalTimeSec,
    fitnessIndex,
    goalIsRealistic,
    suggestedGoalTimeSeconds,
    hasAccessToTrack: hasTrack,
    preferredWorkoutTypes: (assessment.preferredWorkoutTypes as string[]) || [],
    excludedWorkoutCodes: excluded,
    preferredLongRunDay: dayMap[(assessment.preferredLongRunDay as string)?.toLowerCase() || "sunday"] || 7,
    workout1Day: dayMap[(assessment.preferredWorkout1Day as string)?.toLowerCase() || "tuesday"] || 2,
    workout2Day: dayMap[(assessment.preferredWorkout2Day as string)?.toLowerCase() || "thursday"] || 4,
    restDayCount: Math.max(0, 7 - runsPerWeek),
    hasInjury,
    injuryDetails: (assessment.injuryDetails as string) || null,
    riskLevel: riskLevel as RunnerProfile["riskLevel"],
    maxMileageJumpPercent,
    requiresExtraRecovery,
    crossTrainingActivities: (assessment.crossTrainingActivities as string[]) || [],
  };
}

function buildCoachingDirectives(p: RunnerProfile): string {
  const lines: string[] = ["\n=== RUNNER PROFILE (use these constraints) ==="];

  lines.push(`Fitness Level: ${p.fitnessLevel} | Years running: ${p.yearsRunning} | Consistency: ${p.consistencyLevel}`);
  lines.push(`Starting mileage: ${p.recommendedStartingMileage} mpw | Peak cap: ${p.recommendedPeakMileage} mpw`);
  lines.push(`Runs per week: ${p.runsPerWeek} | Max weekly increase: ${p.maxMileageJumpPercent}%`);

  if (p.canRunDoubles) {
    lines.push(`Can run doubles: YES (add when weekly mileage > ${Math.round(p.recommendedPeakMileage * 0.85)} mpw)`);
  } else {
    lines.push("Can run doubles: NO — single runs only, distribute mileage across available days");
  }

  lines.push(`Max session duration: ${p.maxSessionMinutes} min`);
  if (p.maxSessionMinutes <= 45) {
    lines.push("TIME CONSTRAINT: Keep ALL sessions under 45 min. No long runs over 7mi. Shorter intervals.");
  } else if (p.maxSessionMinutes <= 75) {
    lines.push("TIME CONSTRAINT: Cap sessions at ~75 min. Long runs max ~13-14mi for most runners.");
  }

  if (p.fitnessIndex) {
    lines.push(`Fitness Index: ${p.fitnessIndex}`);
    if (!p.goalIsRealistic) {
      const suggestion = p.suggestedGoalTimeSeconds
        ? ` Suggested realistic goal: ${Math.floor(p.suggestedGoalTimeSeconds / 3600)}:${String(Math.floor((p.suggestedGoalTimeSeconds % 3600) / 60)).padStart(2, "0")}.`
        : "";
      lines.push(`WARNING: Goal is aggressive for this Fitness Index.${suggestion} Build conservatively — use moderate paces early, shift to goal pace in final 40%.`);
    }
  }

  if (!p.hasAccessToTrack) {
    lines.push("NO TRACK ACCESS — use fartleks, road intervals (mile/km reps), hill sprints, progressions. Avoid 200m-400m track repeats.");
  }

  if (p.preferredWorkoutTypes.length > 0) {
    lines.push(`Preferred workout styles: ${p.preferredWorkoutTypes.join(", ")} — bias Tuesday sessions toward these`);
  }

  if (p.hasInjury) {
    lines.push(`INJURY: ${p.injuryDetails || "Recent injury reported"}. Conservative build (${p.maxMileageJumpPercent}%/week max). Avoid hill sprints for first 4 weeks. Recovery week every 3 weeks.`);
  } else if (p.requiresExtraRecovery) {
    lines.push("EXTRA RECOVERY NEEDED — recovery week every 3 weeks instead of 4.");
  }

  if (p.restDayCount >= 2) {
    lines.push(`Schedule ${p.restDayCount} rest days per week (runner only runs ${p.runsPerWeek} days).`);
  }

  if (p.crossTrainingActivities.length > 0 && !p.crossTrainingActivities.includes("none")) {
    lines.push(`Cross-training: ${p.crossTrainingActivities.join(", ")} — can suggest on easy/rest days`);
  }

  if (p.excludedWorkoutCodes.length > 0) {
    lines.push(`DO NOT USE these workout codes: ${p.excludedWorkoutCodes.join(", ")}`);
  }

  lines.push("=== END RUNNER PROFILE ===\n");
  return lines.join("\n");
}

// ── Interval Parsing & Pace Helpers ─────────────────────────────

const RACE_DISTANCE_MILES: Record<string, number> = {
  "800m": 0.497, "1500m": 0.932, "mile": 1.0, "3000m": 1.864,
  "5k": 3.107, "10k": 6.214, "half_marathon": 13.109, "marathon": 26.219,
};

const DIST_TO_MILES: Record<string, number> = {
  m: 1 / 1609.34, k: 0.621371, km: 0.621371, mi: 1, mile: 1,
};

interface IntervalInfo {
  reps: number;                    // reps per set (NOT multiplied by sets)
  repDistanceMiles: number;        // 0 for time-based reps
  repLabel: string;
  repUnit: string;                 // original unit: "m", "k", "km", "mi", "mile", "min"
  repRawValue: number;             // original value before conversion
  isTimeBased: boolean;            // true for time-based reps (e.g., 3')
  repDurationSeconds: number;      // seconds per rep (only used when isTimeBased)
  sets: number;                    // number of sets (1 if no grouping)
  setRecoveryDistanceMiles: number | null;
  setRecoveryUnit: string | null;
  setRecoveryRawValue: number | null;
  setRecoverySeconds: number | null;
  recoveryMinutes: number;
  recoveryDistanceMiles: number | null;
  recoveryUnit: string | null;
  recoveryRawValue: number | null;
  recoveryPacePercentage: number;  // 65 default, 80-85 for float
}

function parseIntervals(description: string): IntervalInfo | null {
  // Skip continuous/progression workouts
  if (/progression|progressive/i.test(description) && !/\dx/i.test(description)) return null;
  // Skip alternating patterns with parenthetical structure
  if (/sets of \(/i.test(description)) return null;
  // Skip ladder workouts (e.g., "2k/1600/1200/800/400")
  if (/\d+[mk]?\/\d+[mk]?\/\d+/i.test(description)) return null;
  // Skip alternating (e.g., "1km at 105% / 1km at 90%")
  const withoutWSlash = description.replace(/w\//g, "");
  if (/\d+\s*(km|k|m|mi)\s+at\s+\d+%\s*\/\s*\d+/i.test(withoutWSlash)) return null;

  // Check for "N sets of MxDIST" pattern — keep sets separate (don't multiply)
  let sets = 1;
  const setsMatch = description.match(/(\d+)(?:-\d+)?\s+sets?\s+(?:of\s+)?/i);
  if (setsMatch) sets = parseInt(setsMatch[1]);

  let reps: number;
  let distMiles = 0;
  let label: string;
  let rawUnit: string;
  let rawValue: number;
  let isTimeBased = false;
  let repDurationSeconds = 0;

  // Match "NxDIST" (e.g., "6x800m", "5x2k", "3x1.5mi")
  const numMatch = description.match(/(\d+)(?:\s*-\s*\d+)?\s*[x×]\s*(\d+(?:\.\d+)?)\s*(m|k|km|mi|mile)\b/i);
  if (numMatch) {
    reps = parseInt(numMatch[1]);
    const dist = parseFloat(numMatch[2]);
    const unit = numMatch[3].toLowerCase();
    distMiles = dist * (DIST_TO_MILES[unit] || 1 / 1609.34);
    rawUnit = unit; rawValue = dist;
    if (unit === "mi" || unit === "mile") label = dist === 1 ? "mile" : `${dist}mi`;
    else if (unit === "k" || unit === "km") label = `${dist}k`;
    else label = `${Math.round(dist)}m`;
  } else {
    // Try "Nx mile" pattern (space before "mile")
    const mileMatch = description.match(/(\d+)(?:\s*-\s*\d+)?\s*[x×]\s*mile/i);
    if (mileMatch) {
      reps = parseInt(mileMatch[1]);
      distMiles = 1.0; label = "mile"; rawUnit = "mile"; rawValue = 1;
    } else {
      // Try time-based: "8x3'" or "10x3' fast" or "8x3 min"
      const timeRepMatch = description.match(/(\d+)(?:\s*-\s*\d+)?\s*[x×]\s*(\d+(?:\.\d+)?)\s*('|min)/i);
      if (timeRepMatch) {
        reps = parseInt(timeRepMatch[1]);
        const minutes = parseFloat(timeRepMatch[2]);
        isTimeBased = true;
        repDurationSeconds = Math.round(minutes * 60);
        rawUnit = "min"; rawValue = minutes;
        label = `${minutes}'`;
      } else {
        // Try unitless "Nx400", "Nx600" etc. (assume meters)
        const noUnitMatch = description.match(/(\d+)(?:\s*-\s*\d+)?\s*[x×]\s*(\d+(?:\.\d+)?)\s+at\b/i);
        if (noUnitMatch) {
          reps = parseInt(noUnitMatch[1]);
          const dist = parseFloat(noUnitMatch[2]);
          distMiles = dist / 1609.34;
          label = `${Math.round(dist)}m`;
          rawUnit = "m"; rawValue = dist;
        } else return null;
      }
    }
  }

  // Parse between-rep recovery
  let recoveryMinutes = 2.0;
  let recoveryDistanceMiles: number | null = null;
  let recUnit: string | null = null;
  let recRawValue: number | null = null;
  let recoveryPacePercentage = 65;

  // Time recovery: "w/ 90s jog", "w/ 2 min jog", "w/ 1' rest" (removed \b — fails after ')
  const timeRec = description.match(/w\/\s*(\d+(?:\.\d+)?)(?:\s*-\s*\d+(?:\.\d+)?)?\s*(s|sec|min|')/i);
  if (timeRec) {
    const val = parseFloat(timeRec[1]);
    const unit = timeRec[2].toLowerCase();
    recoveryMinutes = (unit === "s" || unit === "sec") ? val / 60 : val;
  } else {
    // Colon format: "w/ 2:30 jog"
    const colonRec = description.match(/w\/\s*(\d+):(\d+)/);
    if (colonRec) {
      recoveryMinutes = parseInt(colonRec[1]) + parseInt(colonRec[2]) / 60;
    } else {
      // Distance recovery: "w/ 400m jog", "w/ .5mi float"
      const distRec = description.match(/w\/\s*(\d*\.?\d+)\s*(m|k|km|mi|mile)\b/i);
      if (distRec) {
        const val = parseFloat(distRec[1]);
        const unit = distRec[2].toLowerCase();
        recoveryDistanceMiles = val * (DIST_TO_MILES[unit] || 1 / 1609.34);
        recUnit = unit; recRawValue = val;
      }
    }
  }

  // Fallback: "N min rest/jog/float/moderate" without "w/"
  if (!timeRec && !recoveryDistanceMiles) {
    const restMatch = description.match(/(\d+(?:\.\d+)?)(?:\s*-\s*\d+(?:\.\d+)?)?\s*(s|sec|min|')\s*(rest|jog|walk|float|moderate|easy)/i);
    if (restMatch) {
      const val = parseFloat(restMatch[1]);
      const unit = restMatch[2].toLowerCase();
      recoveryMinutes = (unit === "s" || unit === "sec") ? val / 60 : val;
    }
  }

  // Detect float recovery: "float at 85%", "float" → default 80%
  const floatMatch = description.match(/float(?:\s+at\s+(\d+)%)?/i);
  if (floatMatch) {
    recoveryPacePercentage = floatMatch[1] ? parseInt(floatMatch[1]) : 80;
  }

  // Parse between-set recovery: "& 400m jog b/t sets", "400m jog between sets"
  let setRecoveryDistanceMiles: number | null = null;
  let setRecoveryUnit: string | null = null;
  let setRecoveryRawValue: number | null = null;
  let setRecoverySeconds: number | null = null;

  if (sets > 1) {
    const setDistRec = description.match(/(\d*\.?\d+)\s*(m|k|km|mi|mile)\s*(?:jog\s*)?(?:b\/t|between)\s*sets/i);
    if (setDistRec) {
      const val = parseFloat(setDistRec[1]);
      const unit = setDistRec[2].toLowerCase();
      setRecoveryDistanceMiles = val * (DIST_TO_MILES[unit] || 1 / 1609.34);
      setRecoveryUnit = unit; setRecoveryRawValue = val;
    }
    const setTimeRec = description.match(/(\d+(?:\.\d+)?)\s*(s|sec|min|')\s*(?:rest\s*)?(?:b\/t|between)\s*sets/i);
    if (!setDistRec && setTimeRec) {
      const val = parseFloat(setTimeRec[1]);
      const unit = setTimeRec[2].toLowerCase();
      setRecoverySeconds = Math.round((unit === "s" || unit === "sec") ? val : val * 60);
    }
    // Default set recovery if sets but nothing parsed
    if (!setRecoveryDistanceMiles && !setRecoverySeconds) {
      setRecoverySeconds = 180; // 3 min default
    }
  }

  return {
    reps, repDistanceMiles: distMiles, repLabel: label, repUnit: rawUnit, repRawValue: rawValue,
    isTimeBased, repDurationSeconds, sets,
    setRecoveryDistanceMiles, setRecoveryUnit, setRecoveryRawValue, setRecoverySeconds,
    recoveryMinutes, recoveryDistanceMiles, recoveryUnit: recUnit, recoveryRawValue: recRawValue,
    recoveryPacePercentage,
  };
}

function formatPace(totalSeconds: number): string {
  const rounded = Math.round(totalSeconds);
  const m = Math.floor(rounded / 60);
  const s = rounded % 60;
  return `${m}:${String(s).padStart(2, "0")}`;
}

function repPaceString(pctOfRacePace: number, goalTimeSec: number, raceDistMi: number, repDistMi: number): string {
  const racePacePerMile = goalTimeSec / raceDistMi;
  const adjustedPacePerMile = racePacePerMile / (pctOfRacePace / 100);
  return formatPace(adjustedPacePerMile * repDistMi);
}

function pacePerMileStr(pct: number, goalTimeSec: number, raceDistMi: number): string {
  const racePacePerMile = goalTimeSec / raceDistMi;
  const adjustedPace = racePacePerMile / (pct / 100);
  return formatPace(adjustedPace);
}

function replacePaceRefs(text: string, goalTimeSec: number, raceDistMi: number): string {
  const p = (pct: number) => pacePerMileStr(pct, goalTimeSec, raceDistMi);
  // "N%/N%/N%" triple slash (e.g., "100%/102%/105%")
  text = text.replace(/(\d+)%\s*\/\s*(\d+)%\s*\/\s*(\d+)%/g,
    (_, a, b, c) => `${p(+a)}/${p(+b)}/${p(+c)} per mi`);
  // "N%-N% MP" or "N-N% MP" range with MP qualifier
  text = text.replace(/(\d+)%?\s*-\s*(\d+)%\s*MP/g,
    (_, a, b) => `${p(+a)}-${p(+b)}/mi`);
  // "N% MP" single with MP qualifier
  text = text.replace(/(\d+)%\s*MP/g, (_, a) => `${p(+a)}/mi`);
  // "N% > N%" progression (e.g., "90% > 100%")
  text = text.replace(/(\d+)%\s*>\s*(\d+)%/g,
    (_, a, b) => `${p(+a)} > ${p(+b)}/mi`);
  // "N%-N%" or "N-N%" range without MP
  text = text.replace(/(\d+)%?\s*-\s*(\d+)%/g,
    (_, a, b) => `${p(+a)}-${p(+b)}/mi`);
  // Standalone "MP" (100% race pace)
  text = text.replace(/\bMP\b/g, `${p(100)}/mi`);
  // Standalone "N%"
  text = text.replace(/(\d+)%/g, (_, a) => `${p(+a)}/mi`);
  return text;
}

// ── System Prompt ───────────────────────────────────────────────

const SYSTEM_PROMPT = `You are a running coach who builds training plans using periodized training methodology. You can build plans for any distance: 800m, 1500m/mile, 3000m/2-mile, 5k, 10k, half marathon, or marathon.

BEHAVIOR:
If the user provides race distance, race date, start date, goal time, and current weekly mileage — you have enough info. Generate the plan IMMEDIATELY. Do NOT ask follow-up questions when all key info is provided. Output the plan in the <<<PLAN>>> format right away.

Only ask questions if critical info is missing (no race distance, no dates, no mileage). Keep questions to 1-2 max. Never ask more than once.

CONVERSATION STYLE:
Talk like a real coach. Casual, direct, encouraging. No markdown formatting — no bold, no bullet lists, no headers. Plain sentences and short paragraphs.

WORKOUT LIBRARY — reference workouts by CODE only. You MUST use ONLY these codes. The server will reject any code not in this list.

=== MARATHON WORKOUTS ===

80% Basic Endurance (BE_1 to BE_8):
  BE_1: 10mi easy | BE_2: 12mi easy | BE_3: 15mi easy | BE_4: 18mi easy | BE_5: 20mi easy | BE_6: 22mi easy | BE_7: 24mi easy | BE_8: 2hr rolling hills

85% General Endurance (GE_1 to GE_9):
  GE_1: 10mi moderate | GE_2: 12mi moderate | GE_3: 15mi moderate | GE_4: 18mi moderate | GE_5: 20mi moderate | GE_6: 22mi moderate
  GE_7: 1hr progression (80>90%) | GE_8: 90min progression (80>90%) | GE_9: 2hr progression (80>90%)

90% Race-Supportive Endurance (RSE_1 to RSE_8):
  RSE_1: 8mi steady state | RSE_2: 10mi steady state | RSE_3: 12mi steady state | RSE_4: 15mi steady state | RSE_5: 18mi steady state
  RSE_6: 20mi progression (85>92%) | RSE_7: 10x1km at 95%/1km at 85% (alternations) | RSE_8: 8x1mi at 95%/1mi at 85% (alternations)

95% Race-Specific Endurance (RCE_1 to RCE_8):
  RCE_1: 10mi at 95% | RCE_2: 12mi at 95% | RCE_3: 15mi at 95% | RCE_4: 18mi (90>95%)
  RCE_5: 4x3mi at 95% w/1mi float | RCE_6: 4x4mi at 95% w/1mi float | RCE_7: 5x3mi at 95% w/1mi float | RCE_8: 15k/10k/5k progression (SATURDAY ONLY — too much volume for Tuesday)

100% Race Pace (RP_1 to RP_19):
  RP_1: 10mi at MP | RP_2: 12mi at MP | RP_3: 10x1mi at MP w/.5mi float | RP_4: 5x2mi at MP w/.5mi float
  RP_5: 6x2mi at MP w/1mi float | RP_6: 4x3mi at MP w/1mi float | RP_7: 5x3mi at MP w/.5mi float
  RP_8: 2x5mi at MP | RP_9: 3x5mi at MP | RP_10: 2x6mi at MP | RP_11: 10x1km at 102% w/1km float
  RP_12-19: additional MP alternations in km (8x2km, 10x2km, 6x3km, 4x4km, 5x4km, 4x5km, 5x5km, descending ladder)

105% Race-Specific Speed (RSS_1 to RSS_13):
  RSS_1: 8x3' fartlek | RSS_2: 6x6' fartlek | RSS_3: 12x2' fartlek | RSS_4: 10x3' fartlek
  RSS_5: 10x800m at 107% | RSS_6: 10x1km at 107% | RSS_7: 6xmile at 107% | RSS_8: 3x2mi at 106%
  RSS_9: 12x1km at 106% | RSS_10: 8xmile at 105% | RSS_11: 3mi/2mi/1mi cutdown | RSS_12: 2x3mi at 104% | RSS_13: 7mi progression

110% Race-Supportive Speed (RSPS_1 to RSPS_7):
  RSPS_1: 12x400m at 110% | RSPS_2: 8x800m at 110% | RSPS_3: 3x4x800m at 110% | RSPS_4: 12x600m at 110%
  RSPS_5: 8x1000m at 110% | RSPS_6: 5xmile at 110% | RSPS_7: 6x1200m at 110%

115% Mechanical Speed (GS_1 to GS_7):
  GS_1: 12x200m at 115% | GS_2: 12x300m at 115% | GS_3: 10x400m at 115% | GS_4: 12x400m at 115%
  GS_5: 8x10sec hill sprints | GS_6: 8x100m fast strides | GS_7: 10x15sec hill sprints

=== HALF MARATHON WORKOUTS ===

  HM_90: 10-18mi at 90% | HM_95: 10-15mi at 95%
  HM_100: 5-6 sets (3km at 100%, 1km at 90%) | HM_105: 5x2km at 105% w/3' jog
  HM_110: 8x800m at 110% w/2' jog | HM_115: 12x300m at 115% w/100m jog

=== 10K WORKOUTS ===

  K10_90: 7-10mi at 90% | K10_95: 4-7mi at 95%; or 5 sets (3km at 95%, 1km at 85%)
  K10_100: 5x2km at 100% | K10_105: 6x1000m at 105% w/3-5' jog
  K10_110: 8-10x500m at 110% w/1.5-2' jog | K10_115: 16x200m at 115% w/1.5-2' walk/jog

=== 5K WORKOUTS ===

  K5_90: 4-7mi at 90% | K5_95: 4x2km at 95% w/3' jog; or 4-6km at 95%
  K5_100: 5-6x1200m at 100% w/3' jog | K5_105: 2 sets (5-6x500m at 105%) w/45s & 4-5' walk/jog
  K5_110: 16x200m at 110% w/1-2' jog | K5_115: 10-12x200m at 115% w/2-3' walk/jog

=== 3000m / 2-MILE WORKOUTS ===

  K3_90: 4-6km at 90%; or 3-4x mile at 90% w/3' jog | K3_95: 8x800m at 95% w/2' jog
  K3_100: 8x600m at 100% w/2-3' jog | K3_105: 6-7x500m at 105% w/2-3' walk/jog
  K3_110: 16x200m at 110% w/2' jog | K3_115: 10-12x150m at 115% w/2' walk

=== 1500m / MILE WORKOUTS ===

  MI_80: 6-8x1km at 80% w/1-2' jog | MI_85: 5-7x1km at 85% w/1.5-3' walk/jog
  MI_90: 5-6x800m at 90% w/2-3' walk/jog | MI_95: 6-8x600m at 95% w/2-3' walk/jog
  MI_100: 5x600m at 100% w/3' walk/jog | MI_105: 8-10x300m at 105% w/2' walk
  MI_110: 12x200m at 110% w/2' walk | MI_115: 8-10x120m at 115% w/3-5' walk

=== 800m WORKOUTS ===

  R8_90_1: 10x400 at 88% w/90s rest | R8_90_2: 6x600 at 88% w/3' rest
  R8_90_3: 1k/600/400 at 90% w/5' rest | R8_90_4: 6-8x400m at 90% w/2-3' jog
  R8_90_5: 4-5x500m at 90% w/4-5' walk/jog
  R8_95_1: 4-5x400m at 95% w/3' rest | R8_95_2: 2 sets 4x300m at 95% w/90s rest, 5' b/t sets
  R8_95_3: 2-3 sets 600/400/200 at 93/95/100% w/2' rest, 5' b/t sets | R8_95_4: 3-4x600m at 95% w/4-5' walk/jog
  R8_100_1: 2 sets 5x300m at 100% w/2' rest, 5' b/t sets | R8_100_2: 3-4x400m at 100% w/3-4' rest
  R8_100_3: 3x500m at 100% w/6-8' walk/jog
  R8_105: 6x300m at 105% w/2-3' walk/jog
  R8_110: 10-12x200m at 110% w/2-3' walk/jog
  R8_115: 6-10x60m at 115% w/3-4' walk

=== OTHER ===

  FARTLEK: 8x3' steady / 2' easy (unstructured speed play)
  EASY: Easy Run (70-75%) | REST: Rest Day | STRIDES: Easy Run + Strides (easy + 4-6x100m strides) | RACE: Race Day

WEEKLY DAY STRUCTURE:
- Tuesday: SPEED SESSION — the main quality workout. This is where intervals, tempo, and race-specific speed live. KEEP TEMPO/SPEED VOLUME ≤10 MILES (not counting warmup/cooldown). Heavy volume sessions (15k/10k/5k progression, 20mi progression, long alternations) belong on SATURDAY, never Tuesday.
- Thursday: MODERATE RUN — steady 85% effort, 8-12 miles max. Use ONLY GE_1 (10mi) or GE_2 (12mi). NEVER assign GE_3+ (15mi+) on Thursday — those distances belong on Saturday only. Occasionally swap for a progression (GE_7) or hill sprints (GS_5, GS_7).
- Friday: NEUROMUSCULAR — easy run with strides (STRIDES) or hill sprints (GS_5, GS_7, GS_8). Keep legs sharp. Optional — only include if the runner needs it.
- Saturday: LONG RUN — the main endurance session. This is where distance and race-specific endurance build.
- Monday/Wednesday/Sunday: The server fills these as easy runs. You do NOT output these.

PHASE STRUCTURE — periodized progression:

Phase 1 — Base (~25% of weeks):
- Tuesday: Start with progressions (GE_7) → fartlek (RSS_1) → short track (RSPS_2 800m @ 110%) → medium track (RSS_6 1k @ 107%). Build rep length gradually.
- Saturday: Easy long runs building distance (BE_1 → BE_2 → BE_3). Alternate with progressions (GE_8, GE_9).

Phase 2 — Support (~25% of weeks):
- Tuesday: Grouped sets (RSPS_8 3x4x800), 1000m-mile reps at 110% (RSPS_5), race-specific floats (RSS_14 3x2mi @ 105%).
- Saturday: Moderate long runs building to 18-20mi (GE_3, GE_4, GE_5). First quality long run (RSE_1 at 90%).

Phase 3 — Specific (~30% of weeks):
- Tuesday: Longer race-specific reps at 105% (RSS_14, RSS_15, RSS_10, RSS_18). Alternate with 107% track (RSS_6, RSS_9) and progressions (RSS_19). NEVER the same workout two weeks in a row.
- Saturday: Race-pace work (RP_6 4x3mi @ MP, RP_7 5x3mi @ MP), big progressions (RSE_9 20mi 85>95%, GE_10 20mi 80>90%), steady-state (RSE_10 15mi @ 90-95%). ALTERNATE these three types every week — never the same type back to back.

Phase 4 — Taper + Race (~20% of weeks):
- Drop volume fast. Keep 1-2 shorter quality sessions.
- 2 weeks out: mile repeats (RSS_16 6xmile @ 105%) or cutdown (RSS_11 3/2/1mi) on Tuesday. NOT 12x400 or short track — the athlete needs race-specific rhythm, not pure speed.
- 1 week out (race week): GS_1 or short speed on Tue, EASY Thu, STRIDES Sat, RACE on race day.
- Saturday: 12mi moderate (2 weeks out), then 3mi + strides (race week).

TUESDAY SPEED PROGRESSION (example for 16-week marathon build):
Wk1: GE_7 (progression, no intervals) → Wk2: RSS_1 (8x3' fartlek) → Wk3: RSPS_2 (8x800m @ 110%) → Wk4: RSS_6 (10xK @ 107%) → Wk5: RSPS_8 (3x4x800 @ 108%) → Wk6: RSS_14 (3x2mi @ 105%) → Wk7: RSPS_5 (8x1000m @ 110%) → Wk8: RSS_14 (3x2mi @ 105%) → Wk9: RSS_6 (10xK @ 107%) → Wk10: RSS_19 (7mi progression) → Wk11: RSS_18 (2x3mi @ 105%) → Wk12: RSS_10 (8xmile @ 105%) → Wk13: RSS_4b (10x3'/3') → Wk14: RSS_15 (2x4mi @ 105%) → Wk15: RSS_16 (6xmile @ 105%) → Race: RSS_17 (4xmile @ 105%)
Notice: the speed workout changes EVERY week. It alternates between 110% track sessions and 105% race-specific sessions.

SATURDAY LONG RUN PROGRESSION (same example):
Wk1: BE_2 (12mi easy) → Wk2: BE_3 (15mi easy) → Wk3: RSE_1 (8mi @ 90%) → Wk4: GE_8 (90min progression) → Wk5: GE_3 (15mi moderate) → Wk6: GE_4 (18mi moderate) → Wk7: GE_5 (20mi moderate) → Wk8: RCE_5 (4x3mi @ 95%) → Wk9: RSE_9 (20mi progression 85>95%) → Wk10: RP_6 (4x3mi @ MP) → Wk11: GE_6 (22mi moderate) → Wk12: RSE_10 (15mi @ 90-95%) → Wk13: RP_7 (5x3mi @ MP) → Wk14: GE_10 (20mi progression 80>90%) → Wk15: GE_2 (12mi moderate, taper) → Race: RACE
Notice: long runs alternate between easy/moderate, progression, and race-specific. The distance builds gradually. NEVER the same code or type two weeks in a row.

VOLUME PROGRESSION:
- Week 1 = current weekly mileage. Never higher. Week 1 should feel easy.
- Weeks 1-4 (Phase 1): CONSERVATIVE. Build no more than 3-5% per week. Example: 40mpw → 42 → 43 → 45 → 40 (recovery). The body needs time to adapt to training structure before adding volume.
- Weeks 5+: Build no more than 8-10% per week. Long run grows 1-2mi per week.
- Recovery every 3-4 weeks: drop volume ~20%, shorten long run 3-4mi.
- NEVER jump more than 5 miles in a single week during the first half of the plan.
- The first half of the plan should feel moderate. Peak mileage belongs in weeks 60-80% of the plan, NOT before.

SCALING FOR LEVEL:
- Beginner (under 20mpw): peak ~30-35mi, peak long run ~18-20mi. Only 2 quality workouts/week (Tue + Sat). Skip Thu moderate.
- Intermediate (20-40mpw): peak ~45-55mi, peak long run ~20-22mi. 2-3 quality/week.
- Advanced (40-60mpw): peak 75-90mi, peak long run ~22mi. 3 quality/week. Marathon = target 75-90 mid-late.
- Elite (60+mpw): peak 85-100mi, peak long run ~22-24mi. 3-4 quality/week including Thu moderate. Marathon = target 85-100 mid-late.
- NEVER prescribe a workout the runner isn't ready for. 15mpw runners can't handle 8xmile repeats.
- weeklyMileage values MUST be realistic. Build from week 1 = current mileage.

HIGH MILEAGE (70+mpw):
- No rest days — the server fills easy recovery runs instead.
- The server adds doubles dynamically when single runs can't absorb the volume. Never on weekends or long run day.
- Marathon plans should build toward 75-100mpw in mid-late weeks (Phase 2-3 peak).

PLAN RULES:
- Output 3-4 quality workouts per week: Tuesday (speed), Thursday (moderate GE code), Saturday (long run). Optionally Friday (strides/hills GS_5/GS_7/GS_8).
- Do NOT output easy runs (Mon/Wed/Sun) — the server fills those automatically.
- Week 1: only 2 quality entries — a progression (GE_7) and a short long run (BE_1 or BE_2). No intervals.
- Week 2: introduce fartlek (RSS_1 or FARTLEK). Still only 2-3 quality entries.
- Recovery weeks: 2 quality entries, shorter long run, easier speed session.
- Include weeklyMileage for each week so the server can distribute easy miles correctly.
- Use the appropriate distance-specific codes for the target race.

VARIETY — every week should feel different:
- EVERY workout code must be DIFFERENT from the previous week's code for that day. No repeats.
- Alternate workout types: fartlek one week, track intervals next, tempo/progression next, MP work next.
- Vary the Saturday long run: alternate easy long runs (BE), moderate long runs (GE), progression long runs (GE_7/GE_8), and MP work (RP codes).
- Vary the Thursday moderate: rotate between different GE/BE distances and progressions.
- Don't fall into patterns. If week 3 Tue = track 800s, week 4 Tue should be tempo or fartlek, not track 1000s.

WHEN READY, output the plan in <<<PLAN>>> format. Use ONLY workoutCode — the server enriches with paces, warmup/cooldown, and steps.

<<<PLAN>>>
{
  "plan": {
    "name": "16-Week Marathon Plan",
    "startDate": "2026-03-09",
    "endDate": "2026-06-28",
    "targetRaceDistance": "marathon",
    "targetTimeSeconds": 8400
  },
  "weeks": [
    { "weekNumber": 1, "weeklyMileage": 65, "workouts": [
      { "dayOfWeek": 2, "workoutCode": "GE_7", "totalDistanceMiles": 8.0 },
      { "dayOfWeek": 4, "workoutCode": "GE_1", "totalDistanceMiles": 10.0 },
      { "dayOfWeek": 6, "workoutCode": "BE_2", "totalDistanceMiles": 12.0 }
    ]},
    { "weekNumber": 2, "weeklyMileage": 72, "workouts": [
      { "dayOfWeek": 2, "workoutCode": "RSS_1", "totalDistanceMiles": 10.0 },
      { "dayOfWeek": 4, "workoutCode": "GE_1", "totalDistanceMiles": 10.0 },
      { "dayOfWeek": 5, "workoutCode": "GS_7", "totalDistanceMiles": 7.0 },
      { "dayOfWeek": 6, "workoutCode": "BE_3", "totalDistanceMiles": 15.0 }
    ]},
    { "weekNumber": 3, "weeklyMileage": 78, "workouts": [
      { "dayOfWeek": 2, "workoutCode": "RSPS_2", "totalDistanceMiles": 9.0 },
      { "dayOfWeek": 4, "workoutCode": "GE_1", "totalDistanceMiles": 10.0 },
      { "dayOfWeek": 6, "workoutCode": "RSE_1", "totalDistanceMiles": 12.0 }
    ]},
    { "weekNumber": 4, "weeklyMileage": 82, "workouts": [
      { "dayOfWeek": 2, "workoutCode": "RSS_6", "totalDistanceMiles": 12.0 },
      { "dayOfWeek": 4, "workoutCode": "GE_2", "totalDistanceMiles": 12.0 },
      { "dayOfWeek": 6, "workoutCode": "GE_8", "totalDistanceMiles": 11.0 }
    ]}
  ]
}
<<<END_PLAN>>>

OUTPUT FORMAT:
- dayOfWeek: 1=Monday through 7=Sunday
- weeklyMileage: target total miles for the week (server distributes easy runs and doubles to fill this)
- targetTimeSeconds: null if no goal time
- targetRaceDistance: "800m", "1500m", "3000m", "5k", "10k", "half_marathon", or "marathon"
- Output quality workouts only (Tue/Thu/Sat + optional Fri). The server adds easy days, strides, and doubles.`;

// ── Skeleton System Prompt ───────────────────────────────────────

const SKELETON_SYSTEM_PROMPT = `You are an expert running coach selecting workouts for a periodized training plan.
You'll receive a training plan SKELETON with phases, mileage targets, and empty quality-day slots.
Your ONLY job: pick the best workout CODE for each quality day from the library below.

=== TUESDAY (Speed/Quality) ===
Fartlek 105%: RSS_1 8x3' | RSS_2 6x6' | RSS_3 12x2' | RSS_4 10x3' | RSS_4b 10x3'/3' | FARTLEK 8x3'/2'
Track 110%: RSPS_1 12x400m | RSPS_2 8x800m | RSPS_3 3x4x800m | RSPS_4 12x600m | RSPS_5 8x1km | RSPS_6 5xmi | RSPS_7 6x1200m | RSPS_8 3x4x800m@108%
Speed 105-107%: RSS_5 10x800m@107% | RSS_6 10x1km@107% | RSS_7 6xmi@107% | RSS_8 3x2mi@106% | RSS_9 12x1km@106% | RSS_10 8xmi@105% | RSS_14 3x2mi@105% | RSS_15 2x4mi@105% | RSS_16 6xmi@105% | RSS_17 4xmi@105% | RSS_18 2x3mi@105%
Tempo/Cutdown: RSS_11 3/2/1mi cutdown | RSS_12 2x3mi@104%
Progression: RSS_13 7mi 97>105% | RSS_19 7mi 97>103% | GE_7 1hr 80>90% | GE_8 90min 80>90%
Hill/Speed 115%: GS_1 12x200m | GS_2 12x300m | GS_3 10x400m | GS_4 12x400m | GS_5 hill sprints 10s | GS_7 hill sprints 15s

=== THURSDAY (Moderate — restricted set) ===
ONLY use: GE_1 10mi@85% | GE_2 12mi@85% | BE_1 10mi@80% | BE_2 12mi@80% | GE_7 1hr progression | GS_5 hill sprints | GS_7 hill sprints

=== SATURDAY (Long Run) ===
Easy 80%: BE_1 10mi | BE_2 12mi | BE_3 15mi | BE_4 18mi | BE_5 20mi | BE_6 22mi | BE_7 24mi | BE_8 2hr hills
Moderate 85%: GE_1 10mi | GE_2 12mi | GE_3 15mi | GE_4 18mi | GE_5 20mi | GE_6 22mi
Progression: GE_7 1hr | GE_8 90min | GE_9 2hr | GE_10 20mi 80>90%
Steady 90%: RSE_1 8mi | RSE_2 10mi | RSE_3 12mi | RSE_4 15mi | RSE_5 18mi | RSE_6 20mi prog 85>92%
Alternation 90%: RSE_7 10x1km | RSE_8 8x1mi | RSE_9 20mi 85>95% | RSE_10 15mi@90-95%
Race-Specific 95%: RCE_1 10mi | RCE_2 12mi | RCE_3 15mi | RCE_4 18mi 90>95% | RCE_5 4x3mi | RCE_6 4x4mi | RCE_7 5x3mi | RCE_8 15k/10k/5k
MP 100%: RP_1 10mi | RP_2 12mi | RP_3 10x1mi | RP_4 5x2mi | RP_5 6x2mi | RP_6 4x3mi | RP_7 5x3mi | RP_8 2x5mi | RP_9 3x5mi | RP_10 2x6mi
MP km: RP_11 10x1km@102% | RP_12 8x2km | RP_13 10x2km | RP_14 6x3km | RP_15 4x4km | RP_16 5x4km | RP_17 4x5km | RP_18 5x5km | RP_19 descending ladder

=== PHASE PROGRESSION ===

Phase 0 (Intro): Tue=progressions (GE_7) + easy fartleks (RSS_1, FARTLEK). No structured track.
  Sat=easy long (BE_1-BE_3) alternating with progressions (GE_7, GE_8). Build distance slowly.

Phase 1 (Fundamental): Tue=cycle: track short (RSPS_2)→fartlek (RSS_4)→track long (RSS_6)→progression (GE_8).
  Sat=build distance (BE_3→BE_5). First quality long runs (RSE_1, GE_8). Alternate easy and moderate.

Phase 2 (Specific): Tue=race-specific speed: RSS_14, RSS_15, RSS_10, RSS_18. Mix with track (RSS_6, RSS_9) and progressions (RSS_19).
  Sat=race-pace work (RP_6, RP_7), big progressions (RSE_9, GE_10), steady-state (RSE_10). ALTERNATE types every week.

Phase 3 (Taper/Race): Tue=tempo/sharpener (RSS_16, RSS_11)→short track. Race week=RSS_17.
  Sat=12mi moderate (2 weeks out)→RACE. Drop volume fast.

=== TUESDAY SPEED EXAMPLE (16-week marathon) ===
Wk1: GE_7 → Wk2: RSS_1 → Wk3: RSPS_2 → Wk4: RSS_6 → Wk5: RSPS_8 → Wk6: RSS_14 → Wk7: RSPS_5 → Wk8: RSS_14 → Wk9: RSS_6 → Wk10: RSS_19 → Wk11: RSS_18 → Wk12: RSS_10 → Wk13: RSS_4b → Wk14: RSS_15 → Wk15: RSS_16 → Wk16: RSS_17

=== SATURDAY LONG RUN EXAMPLE ===
Wk1: BE_2 → Wk2: BE_3 → Wk3: RSE_1 → Wk4: GE_8 → Wk5: GE_3 → Wk6: GE_4 → Wk7: GE_5 → Wk8: RCE_5 → Wk9: RSE_9 → Wk10: RP_6 → Wk11: GE_6 → Wk12: RSE_10 → Wk13: RP_7 → Wk14: GE_10 → Wk15: GE_2 → Wk16: RACE

=== RULES ===
1. NEVER repeat the same code on the same day two weeks in a row
2. Alternate workout TYPES each week (fartlek→track→tempo→progression, NOT track→track)
3. Saturday must alternate types (easy→moderate→progression→MP, NOT MP→MP)
4. Phase 0: ONLY progressions and fartleks on Tuesday. No structured track.
5. Week 1: Tuesday=GE_7 (progression), Saturday=BE_1 or BE_2. Start conservative.
6. Respect EXCLUDED CODES listed in the profile — never use them
7. After a heavy MP Saturday (any RP code), next Tuesday should be fartlek (lighter)
8. Race week: Tuesday=RSS_17, thursday_code=GE_1, saturday_code=RACE
9. Taper week (2 weeks out): shorter quality sessions, reduced intensity

Output ONLY valid JSON:
{
  "coaching_strategy": "1-2 paragraphs: your overall coaching approach and key decisions for this athlete",
  "selections": [
    {"weekNumber": 1, "tuesday_code": "GE_7", "thursday_code": "GE_1", "saturday_code": "BE_2"},
    ...one entry per week...
  ]
}`;

// ── Skeleton Helpers ────────────────────────────────────────────

function formatSkeletonForAI(
  skeleton: WeeklySkeleton[],
  profile: RunnerProfile | undefined,
  goalTimeSec: number | undefined,
): string {
  const lines: string[] = [];

  lines.push("=== RUNNER PROFILE ===");
  if (profile) {
    lines.push(`Level: ${profile.fitnessLevel} | Current mileage: ${profile.currentWeeklyMileage} mpw`);
    if (profile.fitnessIndex) lines.push(`Fitness Index: ${profile.fitnessIndex}`);
    if (!profile.goalIsRealistic) lines.push("WARNING: Goal is aggressive for current fitness. Be conservative with intensity.");
    if (profile.hasInjury) lines.push(`INJURY: ${profile.injuryDetails || "Recent injury"}. Extra conservative build.`);
    if (!profile.hasAccessToTrack) lines.push("NO TRACK ACCESS — avoid track-only workouts (GS_1-4, RSPS_1/3/4)");
    if (profile.excludedWorkoutCodes.length > 0) {
      lines.push(`EXCLUDED CODES (DO NOT USE): ${profile.excludedWorkoutCodes.join(", ")}`);
    }
  }
  if (goalTimeSec) {
    const h = Math.floor(goalTimeSec / 3600);
    const m = Math.floor((goalTimeSec % 3600) / 60);
    lines.push(`Goal time: ${h}:${String(m).padStart(2, "0")}`);
  }

  lines.push("");
  lines.push("=== WEEKLY SKELETON ===");

  const phaseNames = ["Intro", "Fundamental", "Specific", "Taper/Race"];
  const dayNames = ["", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

  for (const week of skeleton) {
    const pn = phaseNames[week.phase];
    const rw = week.weeksOutFromRace === 1 ? " RACE WEEK" : "";
    let line = `Wk${week.weekNumber} (Phase ${week.phase} ${pn}, ${week.targetWeeklyMileage}mpw${rw}):`;

    const parts: string[] = [];
    for (const d of week.days) {
      if (d.isQualityDay && d.ai_workout_code === null) {
        parts.push(`${dayNames[d.dayOfWeek]} ?~${d.assignedMileage}mi`);
      } else if (d.ai_workout_code) {
        parts.push(`${dayNames[d.dayOfWeek]} ${d.ai_workout_code} ${Math.round(d.assignedMileage)}mi`);
      }
    }
    line += " " + parts.join(" | ");
    lines.push(line);
  }

  return lines.join("\n");
}

function parseAISelections(text: string): AIFinalOutput | null {
  // Try parsing the whole response as JSON
  try {
    const parsed = JSON.parse(text.trim());
    if (parsed.selections && Array.isArray(parsed.selections)) return parsed as AIFinalOutput;
  } catch { /* continue */ }

  // Try extracting JSON from markdown code block
  const codeBlock = text.match(/```(?:json)?\s*([\s\S]*?)```/);
  if (codeBlock) {
    try {
      const parsed = JSON.parse(codeBlock[1].trim());
      if (parsed.selections) return parsed as AIFinalOutput;
    } catch { /* continue */ }
  }

  // Try finding first { to last }
  const first = text.indexOf("{");
  const last = text.lastIndexOf("}");
  if (first !== -1 && last > first) {
    try {
      const parsed = JSON.parse(text.substring(first, last + 1));
      if (parsed.selections) return parsed as AIFinalOutput;
    } catch { /* continue */ }
  }

  return null;
}

function mergeAISelections(skeleton: WeeklySkeleton[], selections: AIWorkoutSelection[]): void {
  const selMap = new Map(selections.map(s => [s.weekNumber, s]));

  for (const week of skeleton) {
    const sel = selMap.get(week.weekNumber);
    if (!sel) continue;

    // Identify the long run as the quality day with the largest assignedMileage;
    // the other quality days are the two workout slots, taken in day-of-week order.
    const qualityDays = week.days.filter(d => d.isQualityDay && d.ai_workout_code === null);
    if (qualityDays.length === 0) continue;
    const longRun = qualityDays.reduce((a, b) => b.assignedMileage > a.assignedMileage ? b : a);
    const workoutSlots = qualityDays
      .filter(d => d !== longRun)
      .sort((a, b) => a.dayOfWeek - b.dayOfWeek);

    if (workoutSlots[0] && sel.tuesday_code) workoutSlots[0].ai_workout_code = sel.tuesday_code;
    if (workoutSlots[1] && sel.thursday_code) workoutSlots[1].ai_workout_code = sel.thursday_code;
    if (longRun && sel.saturday_code) longRun.ai_workout_code = sel.saturday_code;
  }
}

function skeletonToWorkouts(
  skeleton: WeeklySkeleton[],
  startDate: string,
  raceDate: string,
): Record<string, unknown>[] {
  const start = new Date(startDate + "T00:00:00Z");
  const end = new Date(raceDate + "T00:00:00Z");
  const workouts: Record<string, unknown>[] = [];

  for (const week of skeleton) {
    const weekStart = new Date(start);
    weekStart.setDate(weekStart.getDate() + (week.weekNumber - 1) * 7);

    for (const day of week.days) {
      const dayDate = new Date(weekStart);
      dayDate.setDate(dayDate.getDate() + (day.dayOfWeek - 1));

      if (dayDate < start || dayDate > end) continue;

      const code = day.ai_workout_code || day.easyPaceCode || "REST";
      workouts.push({
        date: dayDate.toISOString().split("T")[0],
        dayOfWeek: day.dayOfWeek,
        weekNumber: week.weekNumber,
        workoutCode: code,
        totalDistanceMiles: day.assignedMileage,
        estimatedDurationMinutes: day.assignedMileage > 0 ? Math.round(day.assignedMileage * 10) : 0,
      });
    }
  }

  // Ensure race day has RACE
  const endStr = end.toISOString().split("T")[0];
  const raceIdx = workouts.findIndex(w => w.date === endStr);
  if (raceIdx >= 0 && workouts[raceIdx].workoutCode !== "RACE") {
    const raceDist = 26.219; // will be overridden by enrichment
    workouts[raceIdx].workoutCode = "RACE";
    workouts[raceIdx].totalDistanceMiles = raceDist;
  }

  return workouts;
}

// ── Workout Enrichment ──────────────────────────────────────────

interface Step {
  stepType: string;
  durationType: string;
  durationValue: number;
  pacePercentage: number;
  paceSecondsPerKm?: number;
  notes: string;
}

function buildSteps(code: string, def: WorkoutDef, totalMiles: number, goalTimeSec?: number, raceDistMi?: number): Step[] {
  if (code === "REST") {
    return [{ stepType: "rest", durationType: "time_seconds", durationValue: 0, pacePercentage: 0, notes: "Rest day" }];
  }

  if (code === "EASY") {
    let notes = "Easy conversational pace";
    if (goalTimeSec && raceDistMi) {
      const pacePerMile = (goalTimeSec / raceDistMi) / (70 / 100);
      notes += ` (${formatPace(pacePerMile)}/mi)`;
    }
    return [{ stepType: "active", durationType: "distance_miles", durationValue: totalMiles, pacePercentage: 70, notes }];
  }

  if (code === "STRIDES") {
    return [
      { stepType: "active", durationType: "distance_miles", durationValue: totalMiles, pacePercentage: 70, notes: `${totalMiles} mi easy + strides` },
    ];
  }

  if (code === "RACE") {
    return [{ stepType: "active", durationType: "distance_miles", durationValue: totalMiles, pacePercentage: 100, notes: "Race" }];
  }

  // GS_6 (strides): simple single step like STRIDES
  if (code === "GS_6") {
    return [
      { stepType: "active", durationType: "distance_miles", durationValue: totalMiles, pacePercentage: 70, notes: `${totalMiles} mi easy + strides` },
    ];
  }

  // Hill sprints: easy run + short sprint reps (like STRIDES but steeper)
  if (/^GS_[5-8]$/.test(code) || /hill sprint|steep hill/i.test(def.description)) {
    const easyMiles = Math.max(totalMiles - 1, 4);
    const sprintMatch = def.description.match(/(\d+)\s*x\s*(\d+)\s*sec/i);
    const sprintNotes = sprintMatch
      ? `${sprintMatch[1]}x${sprintMatch[2]}sec hill sprints w/ walk-back recovery`
      : def.description;
    return [
      { stepType: "active", durationType: "distance_miles", durationValue: easyMiles, pacePercentage: 70, notes: "Easy pace" },
      { stepType: "active", durationType: "distance_miles", durationValue: totalMiles - easyMiles, pacePercentage: 115, notes: sprintNotes },
    ];
  }

  if (code === "FARTLEK") {
    const warmup = 1.5;
    const cooldown = 1.5;
    const steps: Step[] = [];
    let steadyNotes = "3' steady";
    let easyNotes = "2' easy";
    if (goalTimeSec && raceDistMi) {
      steadyNotes = `3' steady (~${pacePerMileStr(85, goalTimeSec, raceDistMi)}/mi)`;
      easyNotes = `2' easy (~${pacePerMileStr(70, goalTimeSec, raceDistMi)}/mi)`;
    }
    steps.push({ stepType: "warmup", durationType: "distance_miles", durationValue: warmup, pacePercentage: 65, notes: "Warmup jog" });
    for (let i = 0; i < 8; i++) {
      steps.push({ stepType: "active", durationType: "time_seconds", durationValue: 180, pacePercentage: 85, notes: steadyNotes });
      if (i < 7) {
        steps.push({ stepType: "recovery", durationType: "time_seconds", durationValue: 120, pacePercentage: 70, notes: easyNotes });
      }
    }
    steps.push({ stepType: "cooldown", durationType: "distance_miles", durationValue: cooldown, pacePercentage: 65, notes: "Cooldown jog" });
    return steps;
  }

  // Cutdown workouts — descending distance segments at increasing pace with float recovery
  // e.g., "3mi/2mi/1mi at 105%/107%/110% w/ .5mi float 80%"
  const cutdownMatch = def.description.match(
    /(\d+)mi\s*\/\s*(\d+)mi\s*\/\s*(\d+)mi\s*(?:at\s*)?(\d+)%\s*\/\s*(\d+)%\s*\/\s*(\d+)%\s*(?:w\/?\s*)?\.?(\d+\.?\d*)\s*mi\s*float\s*(\d+)%/i
  );
  if (cutdownMatch && goalTimeSec && raceDistMi) {
    const dists = [parseFloat(cutdownMatch[1]), parseFloat(cutdownMatch[2]), parseFloat(cutdownMatch[3])];
    const pcts = [parseInt(cutdownMatch[4]), parseInt(cutdownMatch[5]), parseInt(cutdownMatch[6])];
    const floatDist = parseFloat(cutdownMatch[7]);
    const floatPct = parseInt(cutdownMatch[8]);
    const p = (pct: number) => pacePerMileStr(pct, goalTimeSec!, raceDistMi!);
    const steps: Step[] = [];
    steps.push({ stepType: "warmup", durationType: "distance_miles", durationValue: 2, pacePercentage: 65, notes: "Warmup jog" });
    for (let i = 0; i < dists.length; i++) {
      steps.push({ stepType: "active", durationType: "distance_miles", durationValue: dists[i], pacePercentage: pcts[i], notes: `${dists[i]}mi @ ${p(pcts[i])}/mi` });
      if (i < dists.length - 1) {
        steps.push({ stepType: "recovery", durationType: "distance_miles", durationValue: floatDist, pacePercentage: floatPct, notes: `${floatDist}mi float (${p(floatPct)}/mi)` });
      }
    }
    steps.push({ stepType: "cooldown", durationType: "distance_miles", durationValue: 2, pacePercentage: 65, notes: "Cooldown jog" });
    return steps;
  }

  // Multi-segment workouts — e.g., "15km at 90% + 10km at 95% + 5km at 100%"
  const multiSegMatch = def.description.match(/(\d+)\s*(km|mi)\s*(?:at\s*)?(\d+)%\s*\+\s*(\d+)\s*(km|mi)\s*(?:at\s*)?(\d+)%\s*\+\s*(\d+)\s*(km|mi)\s*(?:at\s*)?(\d+)%/i);
  if (multiSegMatch && goalTimeSec && raceDistMi) {
    const toMi = (val: number, unit: string) => unit === "km" ? val * 0.621371 : val;
    const segs = [
      { dist: toMi(parseInt(multiSegMatch[1]), multiSegMatch[2]), pct: parseInt(multiSegMatch[3]) },
      { dist: toMi(parseInt(multiSegMatch[4]), multiSegMatch[5]), pct: parseInt(multiSegMatch[6]) },
      { dist: toMi(parseInt(multiSegMatch[7]), multiSegMatch[8]), pct: parseInt(multiSegMatch[9]) },
    ];
    const p = (pct: number) => pacePerMileStr(pct, goalTimeSec!, raceDistMi!);
    return segs.map(s => ({
      stepType: "active" as const, durationType: "distance_miles",
      durationValue: Math.round(s.dist * 10) / 10, pacePercentage: s.pct,
      notes: `${Math.round(s.dist * 10) / 10}mi @ ${p(s.pct)}/mi`,
    }));
  }

  // Progression workouts — split into 3 segments with increasing pace
  if (/progression|progressive/i.test(def.description) && goalTimeSec && raceDistMi) {
    const progMatch = def.description.match(/(\d+)%\s*(?:to|>|-)\s*(\d+)%/) ||
                      def.description.match(/(\d+)%?\s*-\s*(\d+)%/);
    if (progMatch) {
      const startPct = parseInt(progMatch[1]);
      const endPct = parseInt(progMatch[2]);
      const midPct = Math.round((startPct + endPct) / 2);
      const p = (pct: number) => pacePerMileStr(pct, goalTimeSec!, raceDistMi!);

      // Check for easy warmup portion (e.g., "2mi easy + ...")
      const warmupMatch = def.description.match(/(\d+)\s*mi\s*easy\s*\+/);
      const warmupMiles = warmupMatch ? parseInt(warmupMatch[1]) : 0;

      // Time-based progression (e.g., "1hr")
      const timeMatch = def.description.match(/(\d+)\s*hr/i);
      if (timeMatch) {
        const totalMin = parseInt(timeMatch[1]) * 60;
        const segMin = Math.round(totalMin / 3);
        return [
          { stepType: "active", durationType: "time_seconds", durationValue: segMin * 60, pacePercentage: startPct, notes: `${startPct}% (${p(startPct)}/mi)` },
          { stepType: "active", durationType: "time_seconds", durationValue: segMin * 60, pacePercentage: midPct, notes: `${midPct}% (${p(midPct)}/mi)` },
          { stepType: "active", durationType: "time_seconds", durationValue: (totalMin - 2 * segMin) * 60, pacePercentage: endPct, notes: `${endPct}% (${p(endPct)}/mi)` },
        ];
      }

      // Distance-based progression
      const steps: Step[] = [];
      if (warmupMiles > 0) {
        steps.push({ stepType: "warmup", durationType: "distance_miles", durationValue: warmupMiles, pacePercentage: 75, notes: `Easy warmup (${p(75)}/mi)` });
      }
      const mainMiles = totalMiles - warmupMiles;
      const segMiles = Math.ceil(mainMiles / 3);
      const lastSeg = mainMiles - 2 * segMiles;
      steps.push({ stepType: "active", durationType: "distance_miles", durationValue: segMiles, pacePercentage: startPct, notes: `${startPct}% (${p(startPct)}/mi)` });
      steps.push({ stepType: "active", durationType: "distance_miles", durationValue: segMiles, pacePercentage: midPct, notes: `${midPct}% (${p(midPct)}/mi)` });
      steps.push({ stepType: "active", durationType: "distance_miles", durationValue: lastSeg, pacePercentage: endPct, notes: `${endPct}% (${p(endPct)}/mi)` });
      return steps;
    }
  }

  // Speed workouts: parse intervals for proper rep/recovery structure
  if (def.workoutType === "workout") {
    const warmup = 2.0;
    const cooldown = 2.0;
    const intervals = parseIntervals(def.description);

    // CRITICAL: structured steps must be emitted whenever the description
    // is a recognizable interval pattern. Earlier this path required BOTH
    // `goalTimeSec` AND `raceDistMi` to be present — when either was
    // missing (which happens on the WorkoutChatSheet/Replace path) the
    // entire workout collapsed into a single Active step with the
    // description in notes. The athlete saw "Active 5.0 mi" for a "2x3mi"
    // workout. Now: emit structure when parseIntervals succeeds, with
    // pace-formatted notes only when the goal context is available.
    if (intervals) {
      const havePaceContext = !!(goalTimeSec && raceDistMi);
      const steps: Step[] = [];
      steps.push({ stepType: "warmup", durationType: "distance_miles", durationValue: warmup, pacePercentage: 65, notes: "Warmup jog" });

      // Determine rep duration type and pace string
      let repDurationType: string;
      let repDurationValue: number;
      let paceStr: string;

      if (intervals.isTimeBased) {
        repDurationType = "time_seconds";
        repDurationValue = intervals.repDurationSeconds;
        paceStr = havePaceContext
          ? pacePerMileStr(def.pacePercentage, goalTimeSec!, raceDistMi!)
          : `${def.pacePercentage}%`;
      } else {
        repDurationType = (intervals.repUnit === "m") ? "distance_meters" :
          (intervals.repUnit === "k" || intervals.repUnit === "km") ? "distance_km" : "distance_miles";
        repDurationValue = (intervals.repUnit === "m") ? Math.round(intervals.repRawValue) :
          Math.round(intervals.repRawValue * 100) / 100;
        paceStr = havePaceContext
          ? repPaceString(def.pacePercentage, goalTimeSec!, raceDistMi!, intervals.repDistanceMiles)
          : `${def.pacePercentage}% MP`;
      }

      // Recovery step builders
      const isFloat = intervals.recoveryPacePercentage > 65;
      const recNotes = isFloat ? "Float" : "Recovery jog";

      const buildRepRecovery = (): Step => {
        if (intervals.recoveryDistanceMiles && intervals.recoveryUnit && intervals.recoveryRawValue != null) {
          const recDurationType = (intervals.recoveryUnit === "m") ? "distance_meters" :
            (intervals.recoveryUnit === "k" || intervals.recoveryUnit === "km") ? "distance_km" : "distance_miles";
          const recDurationValue = (intervals.recoveryUnit === "m") ? Math.round(intervals.recoveryRawValue) :
            Math.round(intervals.recoveryRawValue * 100) / 100;
          return {
            stepType: "recovery", durationType: recDurationType, durationValue: recDurationValue,
            pacePercentage: intervals.recoveryPacePercentage, notes: recNotes,
          };
        }
        return {
          stepType: "recovery", durationType: "time_seconds",
          durationValue: Math.round(intervals.recoveryMinutes * 60),
          pacePercentage: isFloat ? intervals.recoveryPacePercentage : 0,
          notes: recNotes,
        };
      };

      const buildSetRecovery = (): Step => {
        if (intervals.setRecoveryDistanceMiles && intervals.setRecoveryUnit && intervals.setRecoveryRawValue != null) {
          const dt = (intervals.setRecoveryUnit === "m") ? "distance_meters" :
            (intervals.setRecoveryUnit === "k" || intervals.setRecoveryUnit === "km") ? "distance_km" : "distance_miles";
          const dv = (intervals.setRecoveryUnit === "m") ? Math.round(intervals.setRecoveryRawValue) :
            Math.round(intervals.setRecoveryRawValue * 100) / 100;
          return { stepType: "recovery", durationType: dt, durationValue: dv, pacePercentage: 65, notes: "Recovery jog between sets" };
        }
        return {
          stepType: "recovery", durationType: "time_seconds",
          durationValue: intervals.setRecoverySeconds || 180,
          pacePercentage: 0, notes: "Recovery between sets",
        };
      };

      // Build reps within sets
      const repNotes = intervals.isTimeBased
        ? `${intervals.repLabel} @ ${paceStr}/mi`
        : `${intervals.repLabel} @ ${paceStr}`;

      for (let s = 0; s < intervals.sets; s++) {
        for (let i = 0; i < intervals.reps; i++) {
          steps.push({
            stepType: "active", durationType: repDurationType, durationValue: repDurationValue,
            pacePercentage: def.pacePercentage, notes: repNotes,
          });
          if (i < intervals.reps - 1) {
            steps.push(buildRepRecovery());
          }
        }
        if (s < intervals.sets - 1) {
          steps.push(buildSetRecovery());
        }
      }

      steps.push({ stepType: "cooldown", durationType: "distance_miles", durationValue: cooldown, pacePercentage: 65, notes: "Cooldown jog" });
      return steps;
    }

    // Fallback: single block. Only reached when parseIntervals returns null
    // (truly unrecognizable description, e.g. ladder workouts that we
    // explicitly skip). Even here, embed the description as notes so the
    // athlete sees what's expected even if the structure is opaque.
    const main = Math.max(totalMiles - warmup - cooldown, 1);
    let mainNotes = def.description;
    if (goalTimeSec && raceDistMi) {
      const enriched = replacePaceRefs(mainNotes, goalTimeSec, raceDistMi);
      if (enriched !== mainNotes) { mainNotes = enriched; }
      else { mainNotes += ` (${formatPace((goalTimeSec / raceDistMi) / (def.pacePercentage / 100))}/mi)`; }
    }
    return [
      { stepType: "warmup", durationType: "distance_miles", durationValue: warmup, pacePercentage: 65, notes: "Warmup jog" },
      { stepType: "active", durationType: "distance_miles", durationValue: main, pacePercentage: def.pacePercentage, notes: mainNotes },
      { stepType: "cooldown", durationType: "distance_miles", durationValue: cooldown, pacePercentage: 65, notes: "Cooldown jog" },
    ];
  }

  // Long runs at 80-85%: entire run at target pace
  if (def.pacePercentage <= 85) {
    let notes = def.description;
    if (goalTimeSec && raceDistMi) {
      const enriched = replacePaceRefs(notes, goalTimeSec, raceDistMi);
      if (enriched !== notes) { notes = enriched; }
      else { notes += ` (${formatPace((goalTimeSec / raceDistMi) / (def.pacePercentage / 100))}/mi)`; }
    }
    return [{ stepType: "active", durationType: "distance_miles", durationValue: totalMiles, pacePercentage: def.pacePercentage, notes }];
  }

  // Long runs at 90%+: parse warmup from description or use 25% default
  const descWarmupMatch = def.description.match(/(\d+)\s*mi\s*easy\s*\+\s*(\d+)\s*mi/);
  let warmupMiles: number;
  let mainMiles: number;
  if (descWarmupMatch) {
    warmupMiles = parseInt(descWarmupMatch[1]);
    mainMiles = parseInt(descWarmupMatch[2]);
  } else {
    warmupMiles = Math.min(Math.round(totalMiles * 0.25), 6);
    mainMiles = totalMiles - warmupMiles;
  }
  let mainNotes = def.description;
  if (goalTimeSec && raceDistMi) {
    const enriched = replacePaceRefs(mainNotes, goalTimeSec, raceDistMi);
    if (enriched !== mainNotes) { mainNotes = enriched; }
    else { mainNotes += ` (${formatPace((goalTimeSec / raceDistMi) / (def.pacePercentage / 100))}/mi)`; }
  }
  return [
    { stepType: "warmup", durationType: "distance_miles", durationValue: warmupMiles, pacePercentage: 80, notes: "Easy warmup" },
    { stepType: "active", durationType: "distance_miles", durationValue: mainMiles, pacePercentage: def.pacePercentage, notes: mainNotes },
  ];
}

function enrichWorkout(raw: Record<string, unknown>, goalTimeSec?: number, raceDistance?: string, profile?: RunnerProfile): Record<string, unknown> {
  const code = (raw.workoutCode as string) || "";
  const def = WORKOUT_LIBRARY[code];
  let totalMiles = (raw.totalDistanceMiles as number) || 5;
  const duration = (raw.estimatedDurationMinutes as number) || 50;
  const raceDistMi = raceDistance ? (RACE_DISTANCE_MILES[raceDistance] || 26.219) : undefined;

  // fitness-index-based pace adjustment: if goal is unrealistic and workout is high-intensity (105%+),
  // use FI-predicted pace for intervals to prevent injury from unsustainable paces.
  // MP workouts (100%) still use stated goal pace.
  let effectiveGoalTimeSec = goalTimeSec;
  if (profile?.fitnessIndex && !profile.goalIsRealistic && goalTimeSec && raceDistMi && def) {
    if (def.pacePercentage >= 105) {
      const table = fiTable(raceDistance || "marathon");
      // Find predicted race time from current fitness index
      for (let i = 0; i < table.length - 1; i++) {
        const [v1, t1] = table[i];
        const [v2, t2] = table[i + 1];
        if (profile.fitnessIndex >= v1 && profile.fitnessIndex <= v2) {
          effectiveGoalTimeSec = Math.round(t1 + ((profile.fitnessIndex - v1) / (v2 - v1)) * (t2 - t1));
          break;
        }
      }
    }
  }

  if (!def) {
    console.warn(`Invalid workout code "${code}" on ${raw.date} — replacing with Easy Run`);
    const fallback = WORKOUT_LIBRARY["EASY"];
    return {
      date: raw.date, dayOfWeek: raw.dayOfWeek, weekNumber: raw.weekNumber,
      workoutType: fallback.workoutType, name: fallback.name, description: fallback.description,
      totalDistanceMiles: totalMiles, estimatedDurationMinutes: duration,
      steps: buildSteps("EASY", fallback, totalMiles),
    };
  }

  // AUTHORITATIVE DISTANCE: use the lookup table, never trust LLM distances
  // Only EASY, REST, STRIDES are computed by expandPlan and should keep their values
  if (WORKOUT_DISTANCES[code] !== undefined) {
    totalMiles = WORKOUT_DISTANCES[code];
  }

  // Use effectiveGoalTimeSec for interval paces (FI-adjusted if unrealistic)
  // Use original goalTimeSec for MP/race-pace display (that's what the runner asked for)
  const paceGoal = effectiveGoalTimeSec || goalTimeSec;

  // STRIDES / GS_6: clean name
  if (code === "STRIDES" || code === "GS_6") {
    const enrichedSteps = buildSteps(code, def, totalMiles, paceGoal, raceDistMi);
    // Add paceSecondsPerKm to steps
    if (paceGoal && raceDistMi) {
      const racePacePerMile = paceGoal / raceDistMi;
      for (const step of enrichedSteps) {
        if (step.pacePercentage > 0) {
          step.paceSecondsPerKm = Math.round((racePacePerMile / (step.pacePercentage / 100) / 1.60934) * 10) / 10;
        }
      }
    }
    return {
      date: raw.date, dayOfWeek: raw.dayOfWeek, weekNumber: raw.weekNumber,
      workoutType: def.workoutType, name: `${Math.round(totalMiles)} mi + Strides`,
      description: `${Math.round(totalMiles)} mi easy + strides`,
      totalDistanceMiles: totalMiles, estimatedDurationMinutes: Math.round(totalMiles * 10),
      steps: enrichedSteps,
    };
  }

  // Update name and description with actual paces for ALL workout types
  let name = def.name;
  let description = def.description;
  const skipEnrich = ["EASY", "REST", "STRIDES", "RACE", "FARTLEK"].includes(code);
  const isProgression = /progression|progressive/i.test(def.description) && !/\dx/i.test(def.description);
  if (paceGoal && raceDistMi && !skipEnrich) {
    if (isProgression) {
      // Progression workouts: keep % in name, show % > % (pace) in description
      const progMatch = def.description.match(/(\d+)%\s*(?:to|>|-)\s*(\d+)%/);
      if (progMatch) {
        const startPct = parseInt(progMatch[1]);
        const endPct = parseInt(progMatch[2]);
        const p = (pct: number) => pacePerMileStr(pct, paceGoal, raceDistMi);
        // Name: "Progression 80% > 90%"
        const distMatch = def.description.match(/(\d+)\s*mi/);
        const timeMatch = def.description.match(/(\d+)\s*hr|(\d+)\s*min/i);
        const prefix = distMatch ? `${distMatch[1]}mi` : timeMatch ? (timeMatch[1] ? `${timeMatch[1]}hr` : `${timeMatch[2]}min`) : "";
        name = `${prefix} Progression ${startPct}% > ${endPct}%`.trim();
        // Description: show paces alongside percentages
        description = `${prefix} progression ${startPct}% > ${endPct}% (${p(startPct)} > ${p(endPct)}/mi)`.trim();
      }
    } else {
      // For any workout with parseable intervals, create clean interval name
      const intervals = parseIntervals(def.description);
      if (intervals) {
        const setsPrefix = intervals.sets > 1 ? `${intervals.sets}x` : "";
        if (intervals.isTimeBased && def.pacePercentage >= 95) {
          name = `${setsPrefix}${intervals.reps}x${intervals.repLabel} @ ${def.pacePercentage}%-${def.pacePercentage - 10}%`;
        } else if (intervals.isTimeBased) {
          // Lower intensity time-based — keep library name as-is
        } else {
          const paceStr = repPaceString(def.pacePercentage, paceGoal, raceDistMi, intervals.repDistanceMiles);
          name = `${setsPrefix}${intervals.reps}x${intervals.repLabel} @ ${paceStr}`;
        }
      }
      // Replace all pace references (MP, N%, ranges) in description
      // For MP workouts (100%), use original goal time so the runner sees their target
      const descPaceGoal = def.pacePercentage === 100 ? (goalTimeSec || paceGoal) : paceGoal;
      description = replacePaceRefs(def.description, descPaceGoal, raceDistMi);
      if (/\d+%|\bMP\b/.test(name)) {
        name = replacePaceRefs(name, descPaceGoal, raceDistMi);
      }
    }
  }

  const steps = buildSteps(code, def, totalMiles, paceGoal, raceDistMi);

  // Post-process steps: add actual paceSecondsPerKm for iOS display
  if (paceGoal && raceDistMi) {
    const racePacePerMile = paceGoal / raceDistMi;
    for (const step of steps) {
      if (step.pacePercentage > 0) {
        const pacePerMile = racePacePerMile / (step.pacePercentage / 100);
        step.paceSecondsPerKm = Math.round((pacePerMile / 1.60934) * 10) / 10;
      }
    }
  }

  // Compute accurate duration from steps instead of using LLM estimate
  const racePaceMinsPerMi = (paceGoal && raceDistMi) ? (paceGoal / raceDistMi / 60) : 10;
  let computedDuration = 0;
  for (const step of steps) {
    if (step.durationType === "time_seconds") {
      computedDuration += step.durationValue / 60;
    } else {
      let distMi = step.durationValue;
      if (step.durationType === "distance_km") distMi = step.durationValue * 0.621371;
      else if (step.durationType === "distance_meters") distMi = step.durationValue / 1609.34;
      const paceMinPerMi = step.pacePercentage > 0
        ? racePaceMinsPerMi / (step.pacePercentage / 100)
        : racePaceMinsPerMi / 0.7; // default to easy pace
      computedDuration += distMi * paceMinPerMi;
    }
  }

  return {
    date: raw.date, dayOfWeek: raw.dayOfWeek, weekNumber: raw.weekNumber,
    workoutType: def.workoutType, name, description,
    totalDistanceMiles: totalMiles,
    estimatedDurationMinutes: Math.round(computedDuration) || Math.round(totalMiles * 10),
    steps,
  };
}

// ── Helpers ─────────────────────────────────────────────────────

function extractPlanData(text: string): Record<string, unknown> | null {
  const s = text.indexOf("<<<PLAN>>>");
  const e = text.indexOf("<<<END_PLAN>>>");
  if (s === -1 || e === -1 || e <= s) return null;

  let json = text.substring(s + "<<<PLAN>>>".length, e).trim();
  const cb = json.match(/```(?:json)?\s*([\s\S]*?)```/);
  if (cb) json = cb[1].trim();

  try {
    return JSON.parse(json);
  } catch {
    const f = json.indexOf("{");
    const l = json.lastIndexOf("}");
    if (f !== -1 && l > f) {
      try { return JSON.parse(json.substring(f, l + 1)); } catch { /* */ }
    }
  }
  return null;
}

function getConversationalMessage(text: string): string {
  const s = text.indexOf("<<<PLAN>>>");
  const e = text.indexOf("<<<END_PLAN>>>");
  if (s !== -1 && e !== -1) {
    return (text.substring(0, s).trim() + " " + text.substring(e + "<<<END_PLAN>>>".length).trim()).trim();
  }
  return text;
}

function validatePlan(data: Record<string, unknown>): string | null {
  const plan = data.plan as Record<string, unknown> | undefined;
  if (!plan) return "Missing plan";
  if (!plan.startDate || !plan.endDate) return "Missing dates";
  // Support both old (workouts array) and new (weeks array) format
  const weeks = data.weeks;
  const workouts = data.workouts;
  if (Array.isArray(weeks) && weeks.length > 0) return null;
  if (Array.isArray(workouts) && workouts.length > 0) return null;
  return "No workouts or weeks";
}

// Expand compact week-based plan into full daily workouts.
// The deterministic builder now plans ALL 7 days per week, so this function
// simply assigns calendar dates and handles race day overlay.
function expandPlan(
  planData: Record<string, unknown>,
  preferredLongRunDay: number,
  _profile?: RunnerProfile,
): void {
  const weeks = planData.weeks as Array<Record<string, unknown>> | undefined;
  if (!weeks) return;

  const plan = planData.plan as Record<string, unknown>;
  const startDate = new Date(plan.startDate as string);
  const endDate = new Date(plan.endDate as string);

  const allWorkouts: Record<string, unknown>[] = [];

  for (const week of weeks) {
    const weekNum = week.weekNumber as number;
    const weekWorkouts = (week.workouts as Array<Record<string, unknown>>) || [];

    const weekStart = new Date(startDate);
    weekStart.setDate(weekStart.getDate() + (weekNum - 1) * 7);

    for (const w of weekWorkouts) {
      const dow = w.dayOfWeek as number;
      const dayDate = new Date(weekStart);
      dayDate.setDate(dayDate.getDate() + (dow - 1));

      if (dayDate < startDate || dayDate > endDate) continue;

      const dateStr = dayDate.toISOString().split("T")[0];
      const miles = (w.totalDistanceMiles as number) || 0;
      const session = (w.session as number) || 1;

      allWorkouts.push({
        date: dateStr,
        dayOfWeek: dow,
        weekNumber: weekNum,
        session,
        workoutCode: w.workoutCode,
        totalDistanceMiles: miles,
        estimatedDurationMinutes: miles > 0 ? Math.round(miles * 10) : 0,
      });
    }
  }

  // Ensure race day has a RACE workout
  const endDateStr = endDate.toISOString().split("T")[0];
  const hasRace = allWorkouts.some(w => w.date === endDateStr && w.workoutCode === "RACE");
  if (!hasRace) {
    const endDow = endDate.getDay() || 7;
    const lastWeekNum = weeks.length > 0 ? (weeks[weeks.length - 1].weekNumber as number) : 1;
    const raceDistStr = (plan.targetRaceDistance as string) || "marathon";
    const raceMiles = RACE_DISTANCE_MILES[raceDistStr] || 26.219;
    const raceIdx = allWorkouts.findIndex(w => w.date === endDateStr);
    if (raceIdx >= 0) {
      allWorkouts[raceIdx] = {
        date: endDateStr, dayOfWeek: endDow, weekNumber: lastWeekNum,
        session: 1, workoutCode: "RACE",
        totalDistanceMiles: raceMiles, estimatedDurationMinutes: 0,
      };
    } else {
      allWorkouts.push({
        date: endDateStr, dayOfWeek: endDow, weekNumber: lastWeekNum,
        session: 1, workoutCode: "RACE",
        totalDistanceMiles: raceMiles, estimatedDurationMinutes: 0,
      });
    }
  }

  // Fill empty days with EASY runs (Mon/Wed/Sun and any other unassigned day)
  // This ensures taper weeks and all weeks have daily runs instead of blank/rest days
  for (const week of weeks) {
    const weekNum = week.weekNumber as number;
    const weeklyMileage = (week.weeklyMileage as number) || 0;
    const weekStart = new Date(startDate);
    weekStart.setDate(weekStart.getDate() + (weekNum - 1) * 7);

    // Find which days already have workouts this week
    const assignedDays = new Set(
      allWorkouts.filter(w => w.weekNumber === weekNum).map(w => w.dayOfWeek as number)
    );

    // Sum quality workout miles
    const qualityMiles = allWorkouts
      .filter(w => w.weekNumber === weekNum)
      .reduce((sum, w) => sum + ((w.totalDistanceMiles as number) || 0), 0);

    // Remaining miles to distribute as easy runs
    const remainingMiles = Math.max(0, weeklyMileage - qualityMiles);
    const emptyDays = [1, 2, 3, 4, 5, 6, 7].filter(d => !assignedDays.has(d));

    if (emptyDays.length > 0 && remainingMiles > 0) {
      const easyMilesPerDay = Math.round((remainingMiles / emptyDays.length) * 10) / 10;
      // Cap easy runs at reasonable range (3-12mi)
      const cappedMiles = Math.max(3, Math.min(12, easyMilesPerDay));

      for (const dow of emptyDays) {
        const dayDate = new Date(weekStart);
        dayDate.setDate(dayDate.getDate() + (dow - 1));
        if (dayDate < startDate || dayDate > endDate) continue;

        const dateStr = dayDate.toISOString().split("T")[0];
        allWorkouts.push({
          date: dateStr,
          dayOfWeek: dow,
          weekNumber: weekNum,
          session: 1,
          workoutCode: "EASY",
          totalDistanceMiles: cappedMiles,
          estimatedDurationMinutes: Math.round(cappedMiles * 10),
        });
      }
    }
  }

  delete planData.weeks;
  planData.workouts = allWorkouts;
}

// ── Main ────────────────────────────────────────────────────────

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const userId = await getAuthenticatedUser(req);
    if (!userId) return unauthorizedResponse(corsHeaders);

    if (isRateLimitEnabled()) {
      const rl = await checkFeatureRateLimit(userId, "plan_builder");
      if (!rl.allowed) {
        return new Response(
          JSON.stringify({ error: "Rate limit exceeded", remaining: 0, resetAt: rl.resetAt.toISOString() }),
          { status: 429, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }
    }

    const body = await req.json();
    if (!body.message?.trim()) return validationErrorResponse("Message is required", corsHeaders);
    const lenErr = validateLength(body.message, "message", 5000);
    if (lenErr) return validationErrorResponse(lenErr, corsHeaders);

    const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

    // ── Hybrid skeleton path (DISABLED — needs tuning, using full AI path for now) ──
    // Infrastructure is in place; re-enable when skeleton prompt produces better selections.
    if (false && !body.conversationId && body.startDate && body.raceDate && body.currentWeeklyMileage) {
      const raceDistGuess = (body.message as string)?.toLowerCase().includes("half") ? "half_marathon" :
        (body.message as string)?.toLowerCase().includes("10k") ? "10k" :
        (body.message as string)?.toLowerCase().includes("5k") ? "5k" :
        (body.message as string)?.toLowerCase().includes("800") ? "800m" :
        (body.message as string)?.toLowerCase().includes("1500") ? "1500m" :
        (body.message as string)?.toLowerCase().includes("3000") ? "3000m" : "marathon";
      const goalTimeSec = (body.goalTimeSeconds as number) || undefined;
      const currentMileage = body.currentWeeklyMileage as number;

      // Build runner profile from assessment
      let profile: RunnerProfile | undefined;
      if (body.assessment) {
        profile = buildRunnerProfile(
          body.assessment as Record<string, unknown>,
          goalTimeSec || 0,
          raceDistGuess,
          currentMileage,
        );
        (body as Record<string, unknown>)._runnerProfile = profile;
      }

      // Parse preferred long run day from message
      const dayMap: Record<string, number> = {
        monday: 1, tuesday: 2, wednesday: 3, thursday: 4,
        friday: 5, saturday: 6, sunday: 7,
      };
      let preferredLongRunDay = profile?.preferredLongRunDay || 6;
      const lowerMsg = (body.message as string).toLowerCase();
      for (const [name, num] of Object.entries(dayMap)) {
        if (lowerMsg.includes(`long run day: ${name}`) || lowerMsg.includes(`preferred long run day: ${name}`)) {
          preferredLongRunDay = num;
          break;
        }
      }

      let workout1Day = profile?.workout1Day || 2;
      let workout2Day = profile?.workout2Day || 4;
      for (const [name, num] of Object.entries(dayMap)) {
        if (lowerMsg.includes(`preferred workout day 1: ${name}`)) workout1Day = num;
        if (lowerMsg.includes(`preferred workout day 2: ${name}`)) workout2Day = num;
      }
      // Guard: quality slots must be distinct from each other and from long run day
      if (workout1Day === preferredLongRunDay || workout1Day === workout2Day) workout1Day = 2;
      if (workout2Day === preferredLongRunDay || workout2Day === workout1Day) workout2Day = workout1Day === 4 ? 3 : 4;

      // Build skeleton profile from runner profile
      const skeletonProfile: SkeletonRunnerProfile = {
        fitnessLevel: (profile?.fitnessLevel || (currentMileage < 15 ? "beginner" : currentMileage < 25 ? "novice" : currentMileage < 45 ? "intermediate" : currentMileage < 65 ? "advanced" : "elite")) as SkeletonRunnerProfile["fitnessLevel"],
        fitnessIndex: profile?.fitnessIndex || null,
        currentWeeklyMileage: currentMileage,
        goalDistance: raceDistGuess,
        canRunDoubles: profile?.canRunDoubles || false,
        trackAccess: profile?.hasAccessToTrack ?? true,
        maxSessionMinutes: profile?.maxSessionMinutes || 75,
        preferredLongRunDay,
        workout1Day,
        workout2Day,
        runsPerWeek: profile?.runsPerWeek || 6,
        maxMileageJumpPercent: profile?.maxMileageJumpPercent || 10,
        maxWeeklyMileage: null,
      };

      // Generate deterministic skeleton
      const skeleton = generatePlanSkeleton(skeletonProfile, body.startDate as string, body.raceDate as string);
      console.log("Skeleton generated:", JSON.stringify({
        totalWeeks: skeleton.length,
        phases: skeleton.map(w => w.phase),
        mileage: skeleton.map(w => w.targetWeeklyMileage),
      }));

      // Format skeleton for AI and call Gemini
      const skeletonPrompt = formatSkeletonForAI(skeleton, profile, goalTimeSec);

      const genAI = new GoogleGenerativeAI(Deno.env.get("GEMINI_API_KEY")!);
      const skeletonModel = genAI.getGenerativeModel({
        model: "gemini-2.5-pro",
        generationConfig: { maxOutputTokens: 8192, temperature: 0.3 },
        systemInstruction: SKELETON_SYSTEM_PROMPT,
      });

      const aiResult = await skeletonModel.generateContent(skeletonPrompt);
      const aiText = aiResult.response.text();
      const aiOutput = parseAISelections(aiText);

      if (aiOutput && aiOutput.selections.length > 0) {
        // Merge AI code selections into skeleton
        mergeAISelections(skeleton, aiOutput.selections);

        // Convert skeleton to flat workout array
        const rawWorkouts = skeletonToWorkouts(skeleton, body.startDate as string, body.raceDate as string);

        // Enrich every workout (paces, steps, durations)
        const enrichedWorkouts: Record<string, unknown>[] = [];
        let invalidCount = 0;
        for (const raw of rawWorkouts) {
          const code = (raw.workoutCode as string) || "";
          if (code && !VALID_CODES.has(code)) invalidCount++;
          enrichedWorkouts.push(enrichWorkout(raw, goalTimeSec, raceDistGuess, profile));
        }

        if (invalidCount > 0) {
          console.warn(`Skeleton hybrid: ${invalidCount} invalid workout codes replaced with Easy Run`);
        }

        const planData: Record<string, unknown> = {
          plan: {
            name: `${raceDistGuess.replace("_", " ")} Training Plan`,
            startDate: body.startDate,
            endDate: body.raceDate,
            targetRaceDistance: raceDistGuess,
            targetTimeSeconds: goalTimeSec || null,
          },
          workouts: enrichedWorkouts,
        };

        // Save conversation for follow-ups
        const now = new Date().toISOString();
        const coachMsg = aiOutput.coaching_strategy || `Here's your ${raceDistGuess.replace("_", " ")} training plan! Let me know if you'd like to adjust anything.`;
        const { data: convData } = await supabase.from("conversations").insert({
          messages: [
            { role: "user", content: body.message, timestamp: now },
            { role: "assistant", content: coachMsg, timestamp: now },
          ],
        }).select("id").single();

        return new Response(JSON.stringify({
          type: "plan",
          message: coachMsg,
          planData,
          conversationId: convData?.id || null,
        }), {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      // If AI parsing failed, fall through to the full AI conversation path
      console.warn("Skeleton AI parsing failed, falling back to full AI conversation path");
    }

    // ── AI conversation path (follow-up messages + fallback) ──

    // Load conversation history
    let history: Array<{ role: string; content: string; timestamp: string }> = [];
    if (body.conversationId) {
      const { data } = await supabase.from("conversations").select("messages").eq("id", body.conversationId).single();
      if (data?.messages) history = data.messages;
    }

    // Build user message with context on first message
    let userMessage = body.message;
    if (!body.conversationId) {
      const parts: string[] = [];
      if (body.startDate) parts.push(`Training start date: ${body.startDate}`);
      if (body.raceDate) parts.push(`Race date: ${body.raceDate}`);
      if (body.goalTimeSeconds) {
        const h = Math.floor(body.goalTimeSeconds / 3600);
        const m = Math.floor((body.goalTimeSeconds % 3600) / 60);
        parts.push(`Goal time: ${h}:${String(m).padStart(2, "0")}`);
      }
      if (body.currentWeeklyMileage) parts.push(`Current weekly mileage: ${body.currentWeeklyMileage} miles/week`);
      if (parts.length > 0) userMessage = `[Runner context: ${parts.join(", ")}]\n\n${body.message}`;

      // Build runner profile from structured assessment data and inject coaching directives
      if (body.assessment) {
        const raceDistGuess = (body.message as string)?.toLowerCase().includes("half") ? "half_marathon" :
          (body.message as string)?.toLowerCase().includes("10k") ? "10k" :
          (body.message as string)?.toLowerCase().includes("5k") ? "5k" : "marathon";
        const profile = buildRunnerProfile(
          body.assessment as Record<string, unknown>,
          (body.goalTimeSeconds as number) || 0,
          raceDistGuess,
          (body.currentWeeklyMileage as number) || 30,
        );
        const directives = buildCoachingDirectives(profile);
        userMessage = directives + userMessage;
        // Store profile for expandPlan/enrichWorkout
        (body as Record<string, unknown>)._runnerProfile = profile;
      }
    }

    // Call Gemini
    const genAI = new GoogleGenerativeAI(Deno.env.get("GEMINI_API_KEY")!);
    const model = genAI.getGenerativeModel({
      model: "gemini-2.5-pro",
      generationConfig: { maxOutputTokens: 32768, temperature: 0.5 },
      systemInstruction: SYSTEM_PROMPT,
    });

    const chat = model.startChat({
      history: history.map((m) => ({
        role: m.role === "user" ? "user" : ("model" as const),
        parts: [{ text: m.content }],
      })),
    });

    const result = await chat.sendMessage([{ text: userMessage }]);
    const responseText = result.response.text();

    // Extract plan if present
    const planData = extractPlanData(responseText);
    const message = getConversationalMessage(responseText);

    // Save conversation
    const now = new Date().toISOString();
    const newMessages = [
      ...history,
      { role: "user", content: userMessage, timestamp: now },
      { role: "assistant", content: message, timestamp: now },
    ];

    let conversationId = body.conversationId;
    if (conversationId) {
      await supabase.from("conversations").update({ messages: newMessages, updated_at: now }).eq("id", conversationId);
    } else {
      const { data } = await supabase.from("conversations").insert({ messages: newMessages }).select("id").single();
      conversationId = data?.id;
    }

    // Build response
    const response: Record<string, unknown> = {
      type: "question",
      message,
      conversationId,
    };

    if (planData) {
      const err = validatePlan(planData);
      if (err) {
        console.warn("Plan validation failed:", err);
      } else {
        // Parse preferred long run day from user message
        const dayMap: Record<string, number> = {
          monday: 1, tuesday: 2, wednesday: 3, thursday: 4,
          friday: 5, saturday: 6, sunday: 7,
        };
        let preferredLongRunDay = 7; // Default Sunday
        const lowerMsg = userMessage.toLowerCase();
        for (const [name, num] of Object.entries(dayMap)) {
          if (lowerMsg.includes(`long run day: ${name}`) || lowerMsg.includes(`preferred long run day: ${name}`)) {
            preferredLongRunDay = num;
            break;
          }
        }
        // Skip expandPlan for single-workout modifications (1 week, 1 workout)
        const planWeeks = planData.weeks as Array<Record<string, unknown>> | undefined;
        const isSingleWorkoutMod = planWeeks && planWeeks.length === 1 &&
          ((planWeeks[0].workouts as Array<unknown>) || []).length === 1;

        if (isSingleWorkoutMod) {
          // For single-workout modifications, just flatten without filling REST/EASY/STRIDES
          const week = planWeeks![0];
          const weekNum = week.weekNumber as number;
          const qWorkouts = (week.workouts as Array<Record<string, unknown>>) || [];
          const flatWorkouts: Record<string, unknown>[] = qWorkouts.map(w => ({
            date: "",
            dayOfWeek: w.dayOfWeek,
            weekNumber: weekNum,
            workoutCode: w.workoutCode,
            totalDistanceMiles: w.totalDistanceMiles || 0,
            estimatedDurationMinutes: w.estimatedDurationMinutes || 0,
          }));
          delete planData.weeks;
          planData.workouts = flatWorkouts;
        } else {
          expandPlan(planData, preferredLongRunDay, (body as Record<string, unknown>)._runnerProfile as RunnerProfile | undefined);
        }

        // Enrich every workout with library data — this is the enforcement layer
        const rawWorkouts = planData.workouts as Array<Record<string, unknown>>;
        const enrichedWorkouts: Record<string, unknown>[] = [];
        let invalidCount = 0;
        const planMeta = planData.plan as Record<string, unknown>;
        const goalTimeSec = (planMeta.targetTimeSeconds as number) || (body.goalTimeSeconds as number) || undefined;
        const raceDist = (planMeta.targetRaceDistance as string) || undefined;

        for (const raw of rawWorkouts) {
          const code = (raw.workoutCode as string) || "";
          if (code && !VALID_CODES.has(code)) invalidCount++;
          enrichedWorkouts.push(enrichWorkout(raw, goalTimeSec, raceDist, (body as Record<string, unknown>)._runnerProfile as RunnerProfile | undefined));
        }

        if (invalidCount > 0) {
          console.warn(`${invalidCount} invalid workout codes were replaced with Easy Run`);
        }

        planData.workouts = enrichedWorkouts;
        response.type = "plan";
        response.planData = planData;
      }
    }

    return new Response(JSON.stringify(response), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("Error:", error);
    return internalErrorResponse(corsHeaders);
  }
});
