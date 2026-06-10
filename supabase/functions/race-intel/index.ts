import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { GoogleGenerativeAI } from "https://esm.sh/@google/generative-ai@0.21.0";
import { validateLength } from "../_shared/validation.ts";
import { getAthleteState } from "../_shared/athlete-state.ts";
import { loadPrompt } from "../_shared/prompt-library.ts";

import { corsHeaders } from "../_shared/cors.ts";
import { requireAuthOrServiceRole } from "../_shared/auth.ts";
import { enforceFeatureRateLimit } from "../_shared/rateLimit.ts";
// ============================================================================
// TYPES
// ============================================================================

interface RaceIntelRequest {
  race_name: string;
  race_date?: string;      // ISO date or "November 2026"
  location?: string;       // Optional hint: "San Antonio, TX"
  user_id?: string;
  goal_id?: string;
  force_refresh?: boolean;
}

interface CourseData {
  elevation_gain_ft: number | null;
  elevation_loss_ft: number | null;
  net_elevation_ft: number | null;
  key_hills: Array<{ mile: number; description: string; elevation_change_ft: number }>;
  surface: string;
  aid_station_count: number | null;
  aid_station_details: string | null;
  course_description: string;
  course_map_url: string | null;
  start_time: string | null;
  start_location: string | null;
  notable_features: string[];
  out_and_backs: number | null;
  qualifying_race: boolean;
  field_size: string | null;
}

interface WeatherData {
  avg_temp_f: number | null;
  avg_low_f: number | null;
  avg_high_f: number | null;
  avg_humidity_pct: number | null;
  avg_wind_mph: number | null;
  precipitation_chance_pct: number | null;
  sunrise: string | null;
  conditions_summary: string;
}

// ============================================================================
// GEMINI: Research race with search grounding
// ============================================================================

async function researchRace(
  raceName: string,
  raceDate: string | undefined,
  location: string | undefined,
  geminiKey: string,
): Promise<{ course: CourseData; confidence: string; sources: string[]; verification_notes: string; raw: string }> {
  const genAI = new GoogleGenerativeAI(geminiKey);

  const model = genAI.getGenerativeModel({
    model: "gemini-2.0-flash",
    generationConfig: {
      temperature: 0.2,
      maxOutputTokens: 4096,
    },
    // Enable Google Search grounding for real-time data
    tools: [{ googleSearch: {} } as any],
  });

  const dateHint = raceDate ? ` scheduled for ${raceDate}` : "";
  const locationHint = location ? ` in ${location}` : "";

  const prompt = loadPrompt("race-intel.v1", { raceName, dateHint, locationHint });

  const result = await model.generateContent(prompt);
  const raw = result.response.text();

  // Extract JSON from response (may have markdown fences, duplicated blocks, or trailing content)
  let jsonStr = raw;

  // Try all ```json blocks and pick the last complete one (Gemini sometimes duplicates)
  const allJsonBlocks = [...raw.matchAll(/```(?:json)?\s*([\s\S]*?)```/g)];
  if (allJsonBlocks.length > 0) {
    // Try each block from last to first, pick the first one that parses
    for (let i = allJsonBlocks.length - 1; i >= 0; i--) {
      const candidate = allJsonBlocks[i][1].trim();
      try { JSON.parse(candidate); jsonStr = candidate; break; } catch { continue; }
    }
    // If none parsed, use the last block raw
    if (jsonStr === raw) jsonStr = allJsonBlocks[allJsonBlocks.length - 1][1].trim();
  } else {
    // No markdown fences — try to find a JSON object
    const braceStart = raw.indexOf("{");
    if (braceStart !== -1) {
      // Find the matching closing brace by counting depth
      let depth = 0;
      let end = braceStart;
      for (let i = braceStart; i < raw.length; i++) {
        if (raw[i] === "{") depth++;
        else if (raw[i] === "}") { depth--; if (depth === 0) { end = i; break; } }
      }
      jsonStr = raw.slice(braceStart, end + 1);
    }
  }

  // Clean up [cite: N] references that Gemini's grounding adds
  jsonStr = jsonStr.replace(/\s*\[cite:\s*[\d,\s]+\]/g, "");

  try {
    const parsed = JSON.parse(jsonStr);
    return {
      course: parsed.course || {},
      confidence: parsed.confidence || "low",
      sources: parsed.sources || [],
      verification_notes: parsed.verification_notes || "",
      raw,
    };
  } catch {
    console.error("Failed to parse Gemini response as JSON:", raw.slice(0, 500));
    return {
      course: { course_description: raw.slice(0, 2000) } as any,
      confidence: "low",
      sources: [],
      verification_notes: "Response could not be parsed. Raw LLM output saved for review.",
      raw,
    };
  }
}

// ============================================================================
// OPEN-METEO: Historical weather for race date + location
// ============================================================================

async function fetchHistoricalWeather(
  location: string,
  raceDate: string | undefined,
): Promise<WeatherData> {
  const fallback: WeatherData = {
    avg_temp_f: null, avg_low_f: null, avg_high_f: null,
    avg_humidity_pct: null, avg_wind_mph: null,
    precipitation_chance_pct: null, sunrise: null,
    conditions_summary: "Weather data unavailable — check historical averages closer to race day.",
  };

  if (!location || !raceDate) return fallback;

  try {
    // Step 1: Geocode the location (strip state abbreviations and commas for cleaner geocoding)
    const cleanLocation = location.split(",")[0].trim();
    const geoUrl = `https://geocoding-api.open-meteo.com/v1/search?name=${encodeURIComponent(cleanLocation)}&count=1&language=en&format=json`;
    console.log(`Geocoding: "${cleanLocation}" -> ${geoUrl}`);
    const geoRes = await fetch(geoUrl);
    if (!geoRes.ok) { console.error(`Geocoding failed: ${geoRes.status}`); return fallback; }
    const geoData = await geoRes.json();
    if (!geoData.results?.[0]) { console.error("Geocoding: no results"); return fallback; }

    const { latitude, longitude, timezone } = geoData.results[0];

    // Step 2: Determine the date range — look at the same week in prior years
    // Parse the race date to get month/day
    let month: number;
    let day: number;

    const isoMatch = raceDate.match(/^(\d{4})-(\d{2})-(\d{2})/);
    if (isoMatch) {
      month = parseInt(isoMatch[2]) - 1; // 0-indexed
      day = parseInt(isoMatch[3]);
    } else {
      // Try to extract month/year from strings like "November 2026"
      const monthMatch = raceDate.match(/(january|february|march|april|may|june|july|august|september|october|november|december)\s*(\d{4})?/i);
      if (!monthMatch) return fallback;
      const monthNames = ["january","february","march","april","may","june","july","august","september","october","november","december"];
      month = monthNames.indexOf(monthMatch[1].toLowerCase());
      if (month === -1) return fallback;
      day = 15; // mid-month estimate
    }

    console.log(`Weather lookup: location="${location}", lat=${latitude}, lng=${longitude}, tz=${timezone}, month=${month + 1}, day=${day}`);

    // Get historical data from the past 5 years for the same week
    const years = [2024, 2023, 2022, 2021, 2020];
    const temps: number[] = [];
    const lows: number[] = [];
    const highs: number[] = [];
    const humidities: number[] = [];
    const winds: number[] = [];
    const precips: number[] = [];

    for (const year of years) {
      const startDate = new Date(year, month, Math.max(1, day - 3));
      const endDate = new Date(year, month, Math.min(28, day + 3));
      const startStr = startDate.toISOString().split("T")[0];
      const endStr = endDate.toISOString().split("T")[0];

      const weatherUrl = `https://archive-api.open-meteo.com/v1/archive?latitude=${latitude}&longitude=${longitude}&start_date=${startStr}&end_date=${endStr}&daily=temperature_2m_max,temperature_2m_min,temperature_2m_mean,relative_humidity_2m_mean,wind_speed_10m_max,precipitation_sum&temperature_unit=fahrenheit&wind_speed_unit=mph&timezone=${encodeURIComponent(timezone || "auto")}`;

      try {
        const wRes = await fetch(weatherUrl);
        if (!wRes.ok) { console.error(`Weather API ${year}: ${wRes.status}`); continue; }
        const wData = await wRes.json();
        const daily = wData.daily;
        if (!daily) { console.error(`Weather API ${year}: no daily data`); continue; }
        console.log(`Weather ${year}: ${daily.temperature_2m_mean?.length || 0} days fetched`);

        for (let i = 0; i < (daily.temperature_2m_mean?.length || 0); i++) {
          if (daily.temperature_2m_mean?.[i] != null) temps.push(daily.temperature_2m_mean[i]);
          if (daily.temperature_2m_min?.[i] != null) lows.push(daily.temperature_2m_min[i]);
          if (daily.temperature_2m_max?.[i] != null) highs.push(daily.temperature_2m_max[i]);
          if (daily.relative_humidity_2m_mean?.[i] != null) humidities.push(daily.relative_humidity_2m_mean[i]);
          if (daily.wind_speed_10m_max?.[i] != null) winds.push(daily.wind_speed_10m_max[i]);
          if (daily.precipitation_sum?.[i] != null) precips.push(daily.precipitation_sum[i] > 0.1 ? 1 : 0);
        }
      } catch (yearErr) {
        console.error(`Weather ${year} error:`, yearErr);
        continue;
      }
    }

    const avg = (arr: number[]) => arr.length > 0 ? Math.round(arr.reduce((a, b) => a + b, 0) / arr.length) : null;

    const avgTemp = avg(temps);
    const avgLow = avg(lows);
    const avgHigh = avg(highs);
    const avgHumidity = avg(humidities);
    const avgWind = avg(winds);
    const precipChance = precips.length > 0 ? Math.round((precips.reduce((a, b) => a + b, 0) / precips.length) * 100) : null;

    // Build summary
    let summary = "";
    if (avgTemp != null && avgLow != null && avgHigh != null) {
      summary = `Based on 5-year historical data: expect ${avgLow}-${avgHigh}°F (avg ${avgTemp}°F)`;
      if (avgHumidity != null) summary += `, ${avgHumidity}% humidity`;
      if (avgWind != null) summary += `, winds up to ${avgWind} mph`;
      if (precipChance != null) summary += `. ${precipChance}% chance of rain.`;
    }

    return {
      avg_temp_f: avgTemp,
      avg_low_f: avgLow,
      avg_high_f: avgHigh,
      avg_humidity_pct: avgHumidity,
      avg_wind_mph: avgWind,
      precipitation_chance_pct: precipChance,
      sunrise: null, // Could add sunrise API call
      conditions_summary: summary || fallback.conditions_summary,
    };
  } catch (error) {
    console.error("Weather fetch error:", error);
    return fallback;
  }
}

// ============================================================================
// MAIN HANDLER
// ============================================================================

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const body: RaceIntelRequest = await req.json();
    const { race_name, race_date, location, user_id: bodyUserId, goal_id, force_refresh } = body;

    const auth = await requireAuthOrServiceRole(req, bodyUserId, corsHeaders);
    if ("response" in auth) return auth.response;
    const { userId: user_id, isServiceRole } = auth;

    const rlBlocked = await enforceFeatureRateLimit(user_id, "race", corsHeaders, { isServiceRole });
    if (rlBlocked) return rlBlocked;

    if (!race_name) {
      return new Response(
        JSON.stringify({ error: "race_name is required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const nameErr = validateLength(race_name, "race_name", 200);
    if (nameErr) {
      return new Response(
        JSON.stringify({ error: nameErr }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Check for cached result (within 30 days) unless force refresh.
    // Cache is scoped per-user, plus a shared "system" pool for rows written
    // without a caller user_id. Never read another user's cached row.
    if (!force_refresh) {
      const thirtyDaysAgo = new Date();
      thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);

      const cacheOwners = user_id ? [user_id, "system"] : ["system"];
      const { data: cached } = await supabase
        .from("race_intel")
        .select("*")
        .ilike("race_name", `%${race_name}%`)
        .in("user_id", cacheOwners)
        .gte("fetched_at", thirtyDaysAgo.toISOString())
        .order("fetched_at", { ascending: false })
        .limit(1)
        .maybeSingle();

      if (cached) {
        console.log(`Cache hit for "${race_name}" (fetched ${cached.fetched_at})`);
        return new Response(
          JSON.stringify({ ...cached, cached: true }),
          { headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }
    }

    // Research the race
    const geminiKey = Deno.env.get("GEMINI_API_KEY");
    if (!geminiKey) {
      return new Response(
        JSON.stringify({ error: "GEMINI_API_KEY not configured" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    console.log(`Researching race: "${race_name}" ${race_date || ""} ${location || ""}`);

    const raceLocation = location || race_name.replace(/marathon|half|5k|10k|relay/gi, "").trim();

    // Run course research first, then weather (sequential to avoid Deno resource contention)
    const courseResult = await researchRace(race_name, race_date, location, geminiKey);
    console.log(`Course research done (confidence: ${courseResult.confidence}). Fetching weather...`);
    const weatherResult = await fetchHistoricalWeather(raceLocation, race_date);

    // ── Compute pace adjustments from course + weather + athlete ──
    const paceAdjustments: Record<string, unknown> = {};

    // Heat adjustment: every 10°F above 55°F adds ~1.5-3% to pace
    const avgTemp = weatherResult.avg_temp_f ?? weatherResult.avg_high_f;
    if (avgTemp && avgTemp > 55) {
      const heatDegrees = avgTemp - 55;
      const heatPctSlow = Math.round(heatDegrees * 0.2); // ~2% per 10°F
      const heatSecPerMile = Math.round(heatDegrees * 1.2); // ~12s per 10°F for a ~6:00 pace
      paceAdjustments.heat = {
        expected_temp_f: Math.round(avgTemp),
        adjustment_pct: heatPctSlow,
        adjustment_sec_per_mile: heatSecPerMile,
        note: `Expect ~${heatSecPerMile}s/mi slower than cool-weather pace (${Math.round(avgTemp)}°F avg). Hydrate early and often.`,
      };
    }

    // Humidity adjustment: above 60% adds ~1-2%
    const humidity = weatherResult.avg_humidity_pct;
    if (humidity && humidity > 60) {
      const humidityPct = Math.round((humidity - 60) * 0.05);
      paceAdjustments.humidity = {
        humidity_pct: humidity,
        adjustment_pct: humidityPct,
        note: `${humidity}% humidity — sweat won't evaporate as effectively. Start conservative.`,
      };
    }

    // Wind adjustment
    const wind = weatherResult.avg_wind_mph;
    if (wind && wind > 10) {
      paceAdjustments.wind = {
        wind_mph: wind,
        note: `Winds up to ${wind} mph expected. Tuck behind other runners into headwind, push on tailwind sections.`,
      };
    }

    // Hill adjustments from course data
    const hills = courseResult.course?.key_hills;
    if (hills && hills.length > 0) {
      paceAdjustments.hills = hills.map((hill: any) => ({
        mile: hill.mile,
        description: hill.description,
        elevation_change_ft: hill.elevation_change_ft,
        adjustment: hill.elevation_change_ft > 0
          ? `Slow ~${Math.round(hill.elevation_change_ft / 10)}s/mi on the uphill. Don't fight it — maintain effort, not pace.`
          : `Gain ~${Math.round(Math.abs(hill.elevation_change_ft) / 15)}s/mi on the downhill. Control your turnover, don't overstride.`,
      }));
    }

    // Elevation total adjustment
    const elevGain = courseResult.course?.elevation_gain_ft;
    if (elevGain && elevGain > 200) {
      const totalSlowSec = Math.round(elevGain / 30); // ~1s per 30ft of gain spread across the race
      paceAdjustments.elevation_total = {
        gain_ft: elevGain,
        total_adjustment_sec: totalSlowSec,
        note: `${elevGain}ft of climbing — expect overall pace ~${totalSlowSec}s/mi slower than a flat course.`,
      };
    }

    // Detect race distance from name
    const nameLower = race_name.toLowerCase();
    let raceDistance: "marathon" | "half" | "10k" | "5k" | "mile" = "marathon"; // default
    if (/\b5k\b|5\s*km\b/i.test(nameLower)) raceDistance = "5k";
    else if (/\b10k\b|10\s*km\b|cap\s*10/i.test(nameLower)) raceDistance = "10k";
    else if (/\bhalf\b|13\.1/i.test(nameLower)) raceDistance = "half";
    else if (/\bmile\b|1500|1\s*mi\b/i.test(nameLower)) raceDistance = "mile";
    else if (/\bmarathon\b|26\.2/i.test(nameLower)) raceDistance = "marathon";

    const distanceLabels: Record<string, string> = {
      marathon: "Marathon", half: "Half Marathon", "10k": "10K", "5k": "5K", mile: "Mile",
    };

    // Fetch athlete's paces for personalized recommendations (if user_id provided)
    let personalizedPaces: Record<string, unknown> | null = null;
    if (user_id && user_id !== "system") {
      const athleteState = await getAthleteState(supabase, user_id);
      if (athleteState?.pace_zones) {
        const zones = athleteState.pace_zones;
        // Pick the RIGHT pace zone for this race distance
        const racePaceMap: Record<string, number | undefined> = {
          marathon: zones.mp,
          half: zones.hm,
          "10k": zones.tenK,
          "5k": zones.fiveK,
          mile: zones.fiveK ? Math.round(zones.fiveK * 0.95) : undefined, // ~5% faster than 5K
        };
        const racePace = racePaceMap[raceDistance];
        const racePaceLabel = distanceLabels[raceDistance];

        if (racePace) {
          const formatPace = (s: number) => `${Math.floor(s / 60)}:${String(Math.round(s % 60)).padStart(2, "0")}`;
          let adjustedPace = racePace;
          if (paceAdjustments.heat) adjustedPace += (paceAdjustments.heat as any).adjustment_sec_per_mile;
          if (paceAdjustments.elevation_total) adjustedPace += (paceAdjustments.elevation_total as any).total_adjustment_sec;

          personalizedPaces = {
            race_distance: raceDistance,
            race_distance_label: racePaceLabel,
            flat_cool_race_pace: formatPace(racePace),
            adjusted_race_pace: formatPace(adjustedPace),
            first_half_suggestion: formatPace(adjustedPace + 3), // start slightly conservative
            second_half_suggestion: formatPace(adjustedPace - 2), // bring it home
            note: `This is a ${racePaceLabel}. Your flat-conditions ${racePaceLabel} pace is ${formatPace(racePace)}/mi. For this course + weather, target ${formatPace(adjustedPace)}/mi. Go out at ${formatPace(adjustedPace + 3)}/mi, then bring it home.`,
          };
        }
      }
    }

    // Store results
    const record = {
      user_id: user_id || "system",
      race_name,
      race_date: race_date && !isNaN(new Date(race_date).getTime()) ? race_date : null,
      location: raceLocation,
      course_data: {
        ...courseResult.course,
        pace_adjustments: paceAdjustments,
        personalized_paces: personalizedPaces,
      },
      weather_data: weatherResult,
      confidence: courseResult.confidence,
      sources: courseResult.sources,
      verification_notes: courseResult.verification_notes,
      raw_llm_response: courseResult.raw,
      goal_id: goal_id || null,
      fetched_at: new Date().toISOString(),
    };

    const { data: inserted, error: insertError } = await supabase
      .from("race_intel")
      .insert(record)
      .select("*")
      .single();

    if (insertError) {
      console.error("Failed to save race intel:", insertError);
      // Still return the data even if save fails
      return new Response(
        JSON.stringify({ ...record, save_error: insertError.message }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    console.log(`Race intel saved: ${inserted.id} (confidence: ${courseResult.confidence})`);

    return new Response(
      JSON.stringify({ ...inserted, cached: false }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (error) {
    console.error("Race intel error:", error);
    return new Response(
      JSON.stringify({ error: error.message || "Internal server error" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});
