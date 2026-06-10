/**
 * Race-intel prompt — v1.
 *
 * Consumed by `supabase/functions/race-intel/index.ts`. Sent to Gemini
 * with Google-search grounding enabled to research course + logistics.
 *
 * Substitution placeholders:
 *   raceName        — e.g. "Berlin Marathon"
 *   dateHint        — " scheduled for 2026-09-27" or ""
 *   locationHint    — " in Berlin" or ""
 */

export const TEMPLATE = `Research the race "{{raceName}}"{{dateHint}}{{locationHint}}. I need detailed course and logistics data for race preparation.

Find the following information. Search the race's official website, running forums, past participant reviews, and course guides.

IMPORTANT RULES:
- Only include information you are confident about from actual sources.
- For EACH piece of data, mentally note where you found it.
- If you cannot find specific data (like exact elevation or aid stations), set that field to null — do NOT estimate or guess.
- If the race has changed its course recently, note that.
- If you're unsure about ANY detail, add a note in verification_notes explaining what's uncertain and suggest specific websites or resources the runner should check to verify (e.g., "Check the official course map at [race website] for the latest route" or "Elevation data varies by source — verify on the race's Strava segment").

Return ONLY a JSON object with this exact structure (no markdown, no code fences):

{
  "course": {
    "elevation_gain_ft": <number or null>,
    "elevation_loss_ft": <number or null>,
    "net_elevation_ft": <number or null — negative means net downhill>,
    "key_hills": [{"mile": <number>, "description": "<what happens>", "elevation_change_ft": <number>}],
    "surface": "<road/trail/mixed>",
    "aid_station_count": <number or null>,
    "aid_station_details": "<brief description of aid station spacing/offerings or null>",
    "course_description": "<2-3 paragraph description of the course — what to expect mile by mile, the vibe, tricky sections, where to push, where to hold back>",
    "course_map_url": "<official course map URL or null>",
    "start_time": "<typical start time or null>",
    "start_location": "<where the start line is>",
    "notable_features": ["<any notable course features — loops, bridges, spectator hotspots, etc.>"],
    "out_and_backs": <number of out-and-back sections or null>,
    "qualifying_race": <true if it's a Boston/other qualifier>,
    "field_size": "<approximate field size or null>"
  },
  "confidence": "<high if you found the official race website and recent course data, medium if you found some data but not everything, low if mostly uncertain>",
  "sources": ["<list of websites/sources you found information from>"],
  "verification_notes": "<what you're unsure about, what might have changed, and WHERE the runner should go to verify — be specific about URLs or resources>"
}`;
