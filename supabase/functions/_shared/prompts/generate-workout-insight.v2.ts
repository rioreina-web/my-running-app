/**
 * Generate-workout-insight prompt — v2 (pace-anchored).
 *
 * v1 → v2 changes:
 *   - Inject the athlete's canonical pace zones (recovery / easy /
 *     moderate / steady, MP / HMP / 10K / 5K / 3K / mile) so the LLM
 *     references real numbers, not made-up ones.
 *   - Inject a deterministic zone classification line so the LLM
 *     doesn't have to do pace arithmetic itself (Flash slips on it).
 *   - Inject a prescription-vs-execution block when a scheduled
 *     workout is linked. Empty otherwise — no "no prescribed
 *     workout" filler, just nothing.
 *
 * Backwards compat: v1 stays on disk. The eval harness (when it lands)
 * will compare v1 vs. v2 outputs against the same fixtures.
 *
 * Substitution placeholders (caller fills, "" if absent):
 *   pacesBlock          — multi-line "## Athlete's training paces" block
 *   classificationLine  — one-line deterministic zone read
 *   prescribedBlock     — multi-line "## Prescribed vs. executed" block
 *                          (omitted entirely when no scheduled workout)
 *   workoutType / distance / pace / duration / mood / athleteNotes
 *   recentSummary
 */

export const TEMPLATE = `You're an experienced run coach reading an athlete's training log.

{{pacesBlock}}

## Today's run
- Type: {{workoutType}}
- Distance: {{distance}} mi
- Pace: {{pace}}/mi
- Duration: {{duration}} min
- Mood: {{mood}}
- Athlete notes: {{athleteNotes}}

{{classificationLine}}

{{prescribedBlock}}

Last 7 days: {{recentSummary}}

Write ONE sentence (max 25 words) reading this workout. Match a smart
coach's voice — observational, specific, no exclamation points, no
emojis. Reference the athlete's actual zones (don't invent numbers like
"7:30 pace"; use their real bands and anchors from above). When the
classification shows a zone violation (e.g. easy run sitting in
moderate, or a tempo workout off-pace), call it directly. When a
prescribed workout is linked and the execution deviates, acknowledge
that. Don't be a cheerleader. When there's nothing actionable to add,
make an observation about pattern or context rather than inventing
advice.`;
