# Race Course Database — v1

**Last updated:** 2026-05-28
**Status:** Working document. v1 curated course records for the race
report READY state's "course" section.
**Companion to:** `outputs/race-report-feature-spec-2026-05-28.md`
(TBD) and `outputs/maya-product-roadmap-2026-05-28.md` (decisions log).

This doc holds the v1 curated course preview records for major
marathons. Each race is a structured record. Once the data model is
locked, these get migrated into a Postgres table. Until then, this
file is the source of truth.

---

## Why this exists

Strava is out (licensing). HealthKit GPS only becomes available after
Maya runs a race. For the READY state of the race report (T-7 days
before the race), we need course preview data available *before* she
runs. Three-tier hybrid:

1. **Curated database** (this file). Top ~50 marathons hand-built. v1
   ships with 5-10.
2. **Athlete GPX upload.** For races not in the curated database. Self-
   serve. Engineering work in Phase 2 of the race report feature.
3. **HealthKit retro-extract.** Post-race, becomes the canonical
   recording for future athletes. v1.1+.

This file is the Tier 1 deliverable.

---

## Record schema

Every course record has these fields. Required fields marked `*`.

| Field | Type | Description |
|---|---|---|
| `slug*` | string | URL-safe identifier (`austin-marathon`) |
| `name*` | string | Display name (`Austin Marathon`) |
| `distance*` | enum | `marathon` / `half-marathon` / `10k` / `5k` / `other` |
| `location*` | string | City, region (`Austin, TX`) |
| `typical_date` | string | Cadence (`Third Sunday of February`) |
| `next_race_date` | date | Next scheduled instance, if known |
| `start_time_local` | string | Typical race-day gun time (`7:00 AM CT`) |
| `start_coords` | `[lat, lon]` | Start line GPS |
| `finish_coords` | `[lat, lon]` | Finish line GPS |
| `total_elevation_gain_ft*` | int | Total gain across the course |
| `total_elevation_loss_ft` | int | Total loss (often differs from gain on point-to-points) |
| `elevation_profile_url` | URL | Link to official elevation chart image |
| `course_map_url` | URL | Link to official course map |
| `official_gpx_url` | URL | Link to official GPX if downloadable |
| `surface*` | enum | `road` / `trail` / `mixed` / `track` |
| `notable_sections*` | array | `[{ mile, label, description }, ...]` |
| `typical_weather` | object | `{ low_f, high_f, conditions, notes }` |
| `coach_notes*` | string | AI-formatted readiness note (race strategy, pacing implications, what locals know) |
| `aid_stations` | array | `[{ mile, water, sports_drink, fuel }, ...]` (optional v1) |
| `pacing_strategy_default` | string | Generic recommendation (`bank time on the rolling first half`) |
| `official_url` | URL | Race organizer website |
| `source` | string | Where we sourced the data (`austinmarathon.com 2026`) |
| `last_verified` | date | When we last confirmed the data is current |
| `notes_open` | array | TODOs / open questions for this record |

### Coach notes format

The `coach_notes` field is the primary human-readable text the AI uses
when generating the READY state's course section. Conventions:

- Plain prose, 2-4 sentences
- Lead with the course's defining feature
- Name where the race is won or lost
- Mention surface conditions if non-obvious
- Reference notable sections by mile
- *Don't* prescribe pace; that comes from the athlete's pacing plan

Example: *"Rolling course with two main climbs — South Congress around
mile 7-8, then a sustained set of climbs from miles 19-22 leading to
the Capitol approach. Race is won or lost in those late hills; bank
time on the flat-to-rolling first half rather than the early downhill
miles, which sound easy but eat your legs. Last 1.5 miles drop into
downtown for a fast downhill finish."*

---

## Austin Marathon — complete record

```json
{
  "slug": "austin-marathon",
  "name": "Austin Marathon",
  "distance": "marathon",
  "location": "Austin, TX",
  "typical_date": "Third Sunday of February (Presidents' Day weekend)",
  "next_race_date": "2027-02-21",
  "start_time_local": "7:00 AM CT",
  "start_coords": [30.2697, -97.7434],
  "finish_coords": [30.2747, -97.7404],
  "total_elevation_gain_ft": 850,
  "total_elevation_loss_ft": 850,
  "elevation_profile_url": "https://youraustinmarathon.com/course-map/",
  "course_map_url": "https://youraustinmarathon.com/course-map/",
  "official_gpx_url": "https://youraustinmarathon.com/course-map/",
  "surface": "road",
  "notable_sections": [
    {
      "mile": 1,
      "label": "Downtown start",
      "description": "Flat-to-downhill opening through downtown Austin. Easy to bank time here, but the early downhill is deceptively quad-fatiguing."
    },
    {
      "mile": 7,
      "label": "South Congress climb",
      "description": "First sustained climb of the race — ~150 ft over a mile up South Congress Avenue. Rolling terrain continues through mile 13."
    },
    {
      "mile": 13,
      "label": "Halfway through neighborhoods",
      "description": "Course winds through residential South Austin and Bouldin Creek. Rolling, shaded in places, generally well-supported by spectators."
    },
    {
      "mile": 18,
      "label": "Mopac return",
      "description": "Course turns north back toward central Austin. Rolling terrain starts to bite — legs feel the cumulative climbs."
    },
    {
      "mile": 19,
      "label": "Late hills begin",
      "description": "Sustained climbing through miles 19-22. This is where the race is decided. Cumulative ~250 ft of gain over 3 miles. Sun exposure increases."
    },
    {
      "mile": 22,
      "label": "Capitol approach climb",
      "description": "Final significant climb up to the Capitol complex. After this, mostly downhill or flat to finish."
    },
    {
      "mile": 24.5,
      "label": "Downhill finish begins",
      "description": "Course drops back into downtown. Last 1.5 miles are net-downhill, fast if you've got something left."
    }
  ],
  "typical_weather": {
    "low_f": 45,
    "high_f": 62,
    "conditions": "Cool morning warming to mild. Sun exposure increases in the second half.",
    "notes": "Texas February can swing wildly — 35°F race-day starts happen, as do 70°F finishes. Check forecast 5-7 days out. Wind can pick up from the south through downtown."
  },
  "coach_notes": "Rolling course with two main climb sections — South Congress around mile 7-8, then a sustained set of climbs from miles 19-22 leading to the Capitol approach. Race is won or lost in those late hills; bank time on the rolling first half rather than the early downhill miles, which sound easy but eat your legs. Last 1.5 miles drop into downtown for a fast downhill finish. Late February weather is usually cool at the start, warmer by the finish — dress for the start temperature plus 20 degrees in your effort math.",
  "pacing_strategy_default": "Even-effort, not even-pace. Plan to run the early downhill miles ~10 sec/mi slower than goal pace to spare the quads. Goal pace on the rolling middle section (miles 8-18). Accept that miles 19-22 will be slower than goal pace and budget accordingly. Push the last 4 miles on the downhill finish.",
  "official_url": "https://youraustinmarathon.com",
  "source": "youraustinmarathon.com 2026 course information; community knowledge",
  "last_verified": "2026-05-28",
  "notes_open": [
    "Aid station spacing and contents need verification from current year materials",
    "Confirm official GPX URL once event site is updated for 2027 race",
    "Course altered in 2024; need to verify current route hasn't changed for 2027",
    "Add finish-line orientation (looking south toward Capitol or north toward 11th St?)"
  ]
}
```

---

## Stub records — next 6 races to flesh out

The records below are stubs. They have enough for the readiness state
to show *something*, but TODOs flag what's missing. Order is rough
priority by athlete demand.

### Boston Marathon

```json
{
  "slug": "boston-marathon",
  "name": "Boston Marathon",
  "distance": "marathon",
  "location": "Hopkinton → Boston, MA",
  "typical_date": "Third Monday of April (Patriots' Day)",
  "next_race_date": "2027-04-19",
  "start_time_local": "9:00 AM ET (waves)",
  "total_elevation_gain_ft": 815,
  "total_elevation_loss_ft": 1295,
  "surface": "road",
  "notable_sections": [
    { "mile": 16, "label": "Newton Hills begin", "description": "Four hills between miles 16-21, ending with Heartbreak Hill." },
    { "mile": 21, "label": "Heartbreak Hill", "description": "Last and steepest of the Newton hills — ~88 ft gain over half a mile." },
    { "mile": 25.5, "label": "Right on Hereford, left on Boylston", "description": "Iconic finish stretch into Copley Square." }
  ],
  "typical_weather": { "low_f": 42, "high_f": 60, "conditions": "Variable — can be 30s cold rain or 75°F sunny. Tailwind likely (point-to-point east)." },
  "coach_notes": "Point-to-point with net downhill but deceptive — the early downhills (miles 1-6 drop ~300 ft) shred your quads if you go out at goal pace. The Newton Hills (miles 16-21) are the famous section; Heartbreak Hill at mile 21 is steepest. After Heartbreak, mostly downhill to the finish on Boylston Street. Tailwind is common; weather is the wildcard.",
  "pacing_strategy_default": "Hold back the first 6 miles (~10-15 sec/mi slower than goal). Goal pace through Newton until the hills. Survive the hills. Push the last 5 miles on the downhill into Boston.",
  "official_url": "https://www.baa.org",
  "last_verified": "2026-05-28",
  "notes_open": [
    "Add coords for start (Hopkinton) and finish (Boylston)",
    "Add elevation profile URL",
    "Wave start details — corral assignments matter for pacing",
    "Aid station list"
  ]
}
```

### Chicago Marathon

```json
{
  "slug": "chicago-marathon",
  "name": "Bank of America Chicago Marathon",
  "distance": "marathon",
  "location": "Chicago, IL",
  "typical_date": "Second Sunday of October",
  "total_elevation_gain_ft": 130,
  "total_elevation_loss_ft": 130,
  "surface": "road",
  "notable_sections": [
    { "mile": 0, "label": "Grant Park start", "description": "Loop course starting and finishing at Grant Park." },
    { "mile": 13, "label": "Halfway in Pilsen", "description": "Course goes through diverse neighborhoods." },
    { "mile": 25, "label": "Mt. Roosevelt", "description": "Final small climb back to Grant Park finish." }
  ],
  "typical_weather": { "low_f": 45, "high_f": 60, "conditions": "Cool fall morning, can warm by finish. Wind off the lake is the variable." },
  "coach_notes": "One of the world's flattest, fastest marathon courses — total elevation gain is under 150 ft. Loop course through Chicago's neighborhoods, starting and finishing in Grant Park. The only real climb is the short rise to Roosevelt Road in the final mile. Wind off Lake Michigan is the wildcard; otherwise, the course gives you exactly what your fitness can do.",
  "pacing_strategy_default": "Even-pace race. Goal pace from the start, no need to bank time. Tangents matter — the course has many turns; running the inside line saves real distance over 26 miles.",
  "official_url": "https://www.chicagomarathon.com",
  "last_verified": "2026-05-28",
  "notes_open": ["Full elevation profile", "Coords", "Aid stations", "Course tangent guidance"]
}
```

### NYC Marathon

```json
{
  "slug": "nyc-marathon",
  "name": "TCS New York City Marathon",
  "distance": "marathon",
  "location": "New York, NY",
  "typical_date": "First Sunday of November",
  "total_elevation_gain_ft": 825,
  "surface": "road",
  "notable_sections": [
    { "mile": 0, "label": "Verrazzano Bridge", "description": "Climb up the bridge — strong wind possible." },
    { "mile": 16, "label": "Queensboro Bridge", "description": "Sustained climb up to Manhattan, ~half mile of uphill in silence." },
    { "mile": 17, "label": "First Avenue", "description": "Down the bridge and onto First Ave — emotional surge from the crowds, easy to over-extend." },
    { "mile": 23, "label": "Fifth Avenue climb", "description": "Sustained climb up Fifth Ave — the final test before Central Park." },
    { "mile": 24, "label": "Central Park", "description": "Rolling hills inside the park; finish line at Tavern on the Green." }
  ],
  "typical_weather": { "low_f": 42, "high_f": 55, "conditions": "Cool fall, can be windy especially on bridges." },
  "coach_notes": "Five-borough tour with deceptive elevation — the bridges are the climbs, and the Fifth Avenue climb (mile 23) is the real race-decider. Crowds on First Avenue (mile 17) are euphoric but can pull you off pace. Save energy for the Central Park finish — rolling hills inside the park can feel brutal at mile 24+.",
  "pacing_strategy_default": "Hold back on the Verrazzano climb and First Avenue crowd surge. Settle into goal pace through Brooklyn. Manage the bridges as efforts, not paces. Save your fight for Fifth Avenue and the park.",
  "official_url": "https://www.nyrr.org/tcsnycmarathon",
  "last_verified": "2026-05-28",
  "notes_open": ["Coords", "Aid stations", "Wave start timing", "Cell service blackouts on Verrazzano"]
}
```

### CIM (California International Marathon)

```json
{
  "slug": "cim",
  "name": "California International Marathon (CIM)",
  "distance": "marathon",
  "location": "Folsom → Sacramento, CA",
  "typical_date": "First Sunday of December",
  "total_elevation_gain_ft": 340,
  "total_elevation_loss_ft": 700,
  "surface": "road",
  "notable_sections": [
    { "mile": 0, "label": "Folsom start", "description": "Point-to-point starting in Folsom, finishing at the State Capitol." },
    { "mile": 10, "label": "Rolling miles", "description": "Course is net downhill with small rolling sections — not as flat as Chicago but fast." },
    { "mile": 20, "label": "Sacramento city", "description": "Flatter approach into Sacramento for the final 6 miles." },
    { "mile": 26, "label": "Capitol finish", "description": "Iconic finish at the State Capitol building." }
  ],
  "typical_weather": { "low_f": 42, "high_f": 58, "conditions": "Cool, often foggy at start, clear by finish. December rain possible." },
  "coach_notes": "Net-downhill point-to-point known as a BQ machine — fast course used by many to qualify for Boston. Rolling first half feels harder than the elevation profile suggests; the final 6 miles into Sacramento are genuinely flat. Weather is reliably cool and crisp; rain is the variable.",
  "pacing_strategy_default": "Even effort, slightly back-loaded. The rolling first half can chew you up if you chase the downhills. Hold back, then push the flatter final 6 miles into the Capitol.",
  "official_url": "https://www.runcim.org",
  "last_verified": "2026-05-28",
  "notes_open": ["Coords", "Elevation profile URL", "Aid stations", "Pacer info"]
}
```

### Houston Marathon

```json
{
  "slug": "houston-marathon",
  "name": "Chevron Houston Marathon",
  "distance": "marathon",
  "location": "Houston, TX",
  "typical_date": "Third Sunday of January (MLK weekend)",
  "next_race_date": "2027-01-17",
  "start_time_local": "7:00 AM CT",
  "start_coords": [29.7589, -95.3677],
  "finish_coords": [29.7560, -95.3631],
  "total_elevation_gain_ft": 200,
  "total_elevation_loss_ft": 200,
  "elevation_profile_url": "TBD — chevronhoustonmarathon.com",
  "course_map_url": "TBD — chevronhoustonmarathon.com",
  "official_gpx_url": "TBD — typically posted in the runner toolkit",
  "surface": "road",
  "notable_sections": [
    {
      "mile": 0,
      "label": "Downtown / GRB Convention Center start",
      "description": "Mass start outside the convention center. Wide streets, easy to get into rhythm. The opening miles head west out of downtown."
    },
    {
      "mile": 3,
      "label": "Washington Avenue stretch",
      "description": "Flat through Washington Avenue corridor. Minimal elevation change throughout this section."
    },
    {
      "mile": 8,
      "label": "Memorial / Tanglewood",
      "description": "Course turns south through River Oaks and Tanglewood. Tree-lined neighborhoods, slight shade, generally well-supported by spectators."
    },
    {
      "mile": 13,
      "label": "Halfway near Galleria",
      "description": "Course reaches westernmost point near the Galleria. Half-marathon course peels off here. From here it's the return loop."
    },
    {
      "mile": 18,
      "label": "Hermann Park / Rice University area",
      "description": "Course turns north through the museum district. Some of the most scenic miles, but exposed if the sun is up."
    },
    {
      "mile": 22,
      "label": "Allen Parkway approach",
      "description": "Final stretch along Allen Parkway heading back to downtown. Long, slightly downhill, mostly straight — feels endless on tired legs."
    },
    {
      "mile": 26,
      "label": "Downtown finish",
      "description": "Final turn into downtown and the finish line outside the convention center. Crowd-supported, fast finish."
    }
  ],
  "typical_weather": {
    "low_f": 48,
    "high_f": 60,
    "conditions": "Cool morning warming through the run. Houston in January is mild but humid; dew point is the variable, not temperature.",
    "notes": "60°F at 60% humidity feels harder than 60°F dry. Check dew point 3-5 days out — a 65°F dew point makes Houston a hard day even at moderate temperatures. Occasional fog at start. Rain happens. Wind generally light, can pick up from the south."
  },
  "coach_notes": "Flat, fast loop course often used as a BQ qualifier — one of the flattest marathons in the US with under 250 ft of total elevation gain. Humidity is the wildcard, not heat or hills. The course gives you exactly what your fitness can deliver on a dry-air day; on a high-dew-point day, expect 10-30 sec/mi slower than goal pace for the same effort. The final 4 miles down Allen Parkway feel longer than they are — save something for them.",
  "pacing_strategy_default": "Even pace from the start, slightly back-loaded. The course is so flat that pacing is purely about effort management — no terrain to play. If conditions are humid, plan to add 5-15 sec/mi to goal pace and accept a slower finish. Tangents matter: the course has gradual curves that add real distance if you run wide.",
  "official_url": "https://www.chevronhoustonmarathon.com",
  "source": "Course knowledge from prior race materials; community knowledge",
  "last_verified": "2026-05-28",
  "notes_open": [
    "Verify exact start/finish coords against current GRB Convention Center setup",
    "Add elevation profile URL once 2027 race materials post",
    "Aid station spacing and contents (Houston is known for good support)",
    "Houston Half courses overlap miles 1-13 — clarify in implementation",
    "Confirm course hasn't changed for 2027 (course adjustments are common as Houston construction continues)"
  ],
  "note_for_maya": "This is Maya's last race (3:28, January 2026). Her fitness anchor lives here. When the AI references 'last cycle' or 'compared to Houston,' this is the record. Houston was a humid year (dew point ~62°F) — that context matters for honest cycle comparison; she was not on a dry-air day."
}
```

### Marine Corps Marathon

```json
{
  "slug": "marine-corps-marathon",
  "name": "Marine Corps Marathon",
  "distance": "marathon",
  "location": "Arlington, VA / Washington, DC",
  "typical_date": "Last Sunday of October",
  "total_elevation_gain_ft": 610,
  "surface": "road",
  "notable_sections": [
    { "mile": 0, "label": "Arlington start", "description": "Climb up to Lee Highway — first hill of the day right out of the gate." },
    { "mile": 12, "label": "Hains Point", "description": "Flat, exposed loop with no crowds — mental challenge." },
    { "mile": 20, "label": "Beat the bridge", "description": "Must cross the 14th Street Bridge by mile 20 cutoff — a course-specific psychological landmark." },
    { "mile": 26, "label": "Iwo Jima finish", "description": "Final uphill to the Marine Corps War Memorial." }
  ],
  "typical_weather": { "low_f": 45, "high_f": 62, "conditions": "Fall in DC — can be warm, can be cold, occasionally rain." },
  "coach_notes": "Tour of DC monuments with a notable course structure — opening climb, exposed flat middle (Hains Point), then a final uphill finish at the Marine Corps War Memorial. 'Beating the bridge' (mile 20 cutoff) is part of the lore. Volunteer support from active-duty Marines is the cultural signature.",
  "pacing_strategy_default": "Manage the opening climb (don't chase pace up the first hill). Hold goal pace through DC. Save energy for the final uphill — it's short but punishing.",
  "official_url": "https://www.marinemarathon.com",
  "last_verified": "2026-05-28",
  "notes_open": ["Coords", "Elevation profile URL", "Aid stations"]
}
```

---

## Build sequence

Order to fill out the remaining stubs, by athlete demand (rough
estimate of how many serious marathoners target each in a given year):

1. ✓ Austin Marathon — complete
2. Boston Marathon — stub built, needs detail
3. Chicago Marathon — stub built, needs detail
4. NYC Marathon — stub built, needs detail
5. CIM — stub built, needs detail
6. Houston Marathon — stub built, needs detail (Maya's anchor)
7. Marine Corps Marathon — stub built, needs detail

Then (v1.1+):
8. LA Marathon
9. Berlin Marathon (international, but huge US athlete contingent)
10. London Marathon (similar)
11. Twin Cities Marathon
12. Philadelphia Marathon
13. Grandma's Marathon
14. Big Sur Marathon
15. Rock 'n' Roll San Diego / Las Vegas / Nashville (series)
16. Disney Marathon
17. Indianapolis Monumental
18. Detroit Free Press Marathon
19. Pittsburgh Marathon
20. Mountain races (Pike's Peak, Mt. Marathon — different category)

Plus the half-marathon equivalents (NYC Half, Boston Half via BAA half
series, Houston Half, Hot Chocolate series, Rock 'n' Roll halves).

---

## Mapping tool — the actual long-term solution (2026-05-28)

Manual curation past 5-10 races doesn't scale. Updates don't scale.
Verification doesn't scale. The honest long-term path is a course
mapping tool that:

1. **Accepts a route as input.** GPX upload (most common — race
   organizers publish), visual route drawing on a map, or URL import
   if machine-readable.
2. **Auto-extracts topography.** Pulls elevation point-by-point from
   Mapbox terrain or USGS DEM. Computes total gain/loss, mile markers,
   default elevation profile chart. No human work for the basics.
3. **Detects notable sections algorithmically.** Sustained climbs
   above threshold (~50 ft gain over <1 mile), sustained descents,
   flat exposed stretches, turnarounds, bridges, OSM-tagged
   landmarks. Outputs candidate notable sections; curator refines.
4. **AI-assists the coach notes.** Given route, elevation, weather
   seasonality, and detected sections, AI drafts a candidate
   `coach_notes` paragraph in editorial voice. Human polishes.
   ~60% of the hard work auto-drafted; 40% human refinement.
5. **Exports to schema.** Writes directly to the `race_courses`
   table, or outputs a markdown record for code review.

**Versioning + community contributions** (v1.5+):
year-over-year course updates, athlete-contributed corrections,
moderation workflow.

**Engineering scope:**

| Tier | Capability | Scope |
|---|---|---|
| Minimum | GPX upload + auto elevation + auto section detection + form to fill coach notes | ~2 weeks |
| Real tool | Above + visual route drawing on map + AI-assisted coach notes | ~6-8 weeks |
| Community tool | Above + auth, moderation, version control | ~12+ weeks |

**Strategic options:**

- **Option A — Ship v1 with manual curation, build the tool for v1.5.**
  Hand-curate 5-10 majors now. Ship the race report feature in Phase
  4 of Maya's roadmap. Build the mapping tool in Phase 6-7 as an
  enabling infrastructure layer. Course preview becomes higher-quality
  and broader once the tool ships.
- **Option B — Pause race report shipping. Build the mapping tool
  first.** Acknowledges that race report quality is gated on course
  data quality, and curated data has a quality ceiling. Adds ~2 weeks
  minimum to the path; ~6-8 weeks for the real tool.
- **Option C — Hybrid: ship minimum tool + minimum curation in v1.**
  Build the 2-week minimum tool (GPX + auto extract + form). Use it
  to add the top 5-10 races faster than pure manual curation. Ship
  race report with this. Defer visual editor and community features.

Strategic call is in section "Open questions for v1" below.

---

## Open questions for v1

1. **Where does this data live in code?** Postgres table
   `race_courses` with one row per record? JSON files in
   `supabase/seed/race-courses/`? Hardcoded TypeScript constants? Each
   has tradeoffs (DB = mutable, file = source-controlled, constants =
   no I/O).
2. **How does Maya specify which race she's training for?** A
   dropdown / typeahead populated from this database, plus "other"
   that triggers GPX upload? Or always free-text + AI matches to a
   record if confident?
3. **Year-over-year course changes.** Some races alter their course
   between years (construction, permitting). Do we version records
   per year, or just update with a `last_verified` and a change log?
4. **Non-marathon distances.** Some halves are part of marathon
   weekends (NYC Half, Houston Half) with overlapping courses. Same
   record with distance variants, or distinct records?
5. **Cycling / tri / ultra distances.** Out of scope for v1 (running
   focus), but the schema should be extensible.
6. **How does the AI use this data in the READY state Coach Read?**
   The `coach_notes` field is the raw material. The AI synthesizes it
   into Maya's voice for her readiness paragraph. Prompt design TBD.
7. **Updates and accuracy.** Race courses change. Aid station counts
   change. Who maintains the records? Initially Rio + Claude; later, a
   community-maintained system or paid race-organizer partnerships.

---

## How to use this doc

- **Before building any race report UI**, check this doc for the
  record format. Schema is here.
- **When adding a new race**, copy an existing record as a template.
  Fill required fields. Add stubs/TODOs for the rest.
- **When Maya schedules a race for the calendar**, the system looks
  up the slug here. If found → READY state populates from this record.
  If not → prompt her to upload GPX or fill basics manually.
- **When a record's `last_verified` is more than a year old**, flag
  for re-verification before relying on it for a current race.
- **The `coach_notes` field is the AI's primary text source.** Write
  it for the AI to read aloud, not for engineering metadata.
