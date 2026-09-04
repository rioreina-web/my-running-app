import Link from "next/link";
import { notFound } from "next/navigation";
import { EditorialRule, EmptyState, Eyebrow, MoodPill, PlateStrip, Quoted, Section, SheetChrome, Spacer } from "@/components/mockup/primitives";
import { JOURNAL, WORKOUTS } from "@/components/mockup/data";

/* Journal entry · the full memo, the mood, the niggles quoted verbatim,
   the life context, and the linked workout. Still pure record. */

export default async function JournalEntryPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const entry = JOURNAL.find((e) => e.id === id);
  if (!entry) notFound();
  const workout = entry.workoutId ? WORKOUTS[entry.workoutId] : undefined;

  return (
    <>
      <PlateStrip surface="JOURNAL · ENTRY DETAIL" fig="FIG. 19" />
      <div className="m-body">
        <SheetChrome back="/mockup/log" backLabel="Journal" surface="ENTRY" action={{ label: "Edit", href: "#" }} />

        <div className="m-section m-mt-14">
          <Eyebrow coral>
            {entry.dow.toUpperCase()} · {entry.dateUpper}
          </Eyebrow>
          <h1 className="m-display m-display--l">
            {entry.zone}
            {entry.miles ? ` ${entry.miles}` : ""}.
          </h1>
          <div className="m-caption m-caption--faint">
            {[entry.duration, entry.pace, entry.source].filter(Boolean).join("  ·  ").toUpperCase()}
          </div>
        </div>

        <Spacer h={16} />
        <EditorialRule />

        <Section eyebrow={entry.kind === "voice" ? `VOICE MEMO · ${entry.voiceLength}` : entry.kind === "text" ? "TYPED NOTE" : "MEMO"}>
          {entry.body ? (
            <p className="m-quote m-mt-6">
              <Quoted>{entry.body}</Quoted>
            </p>
          ) : (
            <EmptyState nudge="No memo on this session." cta={{ label: "Add a note", href: "/mockup/log" }} quiet />
          )}
          {entry.kind === "voice" ? (
            <div className="m-row m-mt-10">
              <span className="m-caption m-caption--faint">TRANSCRIBED · CLEANED</span>
              <span className="m-link m-link--mono">PLAY ORIGINAL ↗</span>
            </div>
          ) : null}
        </Section>

        {entry.mood ? (
          <Section eyebrow="MOOD">
            <div className="m-mt-4">
              <MoodPill mood={entry.mood} />
            </div>
          </Section>
        ) : null}

        {entry.niggles?.length ? (
          <Section eyebrow="NIGGLES · IN YOUR WORDS" eyebrowRight="DETECTED, NOT DIAGNOSED">
            {entry.niggles.map((n) => (
              <div key={n.part} className="m-listrow m-listrow--2">
                <div>
                  <span className="m-listrow__label">
                    {n.side === "R" ? "Right " : n.side === "L" ? "Left " : ""}
                    {n.part.toLowerCase()}
                  </span>
                  <span className="m-listrow__hint">
                    <Quoted>{n.quote}</Quoted>
                  </span>
                </div>
                <Link href="/mockup/niggles" className="m-listrow__value is-coral">
                  TIMELINE ↗
                </Link>
              </div>
            ))}
          </Section>
        ) : null}

        {entry.life?.length ? (
          <Section eyebrow="LIFE CONTEXT">
            <div className="m-chips m-mt-4">
              {entry.life.map((l) => (
                <span key={l} className="m-chip m-chip--life">
                  {l}
                </span>
              ))}
              <span className="m-chip">+ ADD</span>
            </div>
            <p className="m-quote m-quote--faint m-mt-8">Sleep, weather, work, travel. Whatever shaped the run.</p>
          </Section>
        ) : (
          <Section eyebrow="LIFE CONTEXT">
            <EmptyState nudge="Nothing captured for this day." cta={{ label: "Add sleep or weather", href: "#" }} quiet />
          </Section>
        )}

        <Spacer h={20} />
        <EditorialRule />

        <Section eyebrow="LINKED WORKOUT" eyebrowRight={workout ? workout.zone.toUpperCase() : undefined}>
          {workout ? (
            <Link href={`/mockup/workouts/${workout.id}`} className="m-card m-block m-mt-6">
              <div className="m-row">
                <span className="m-display m-display--s">{workout.title}</span>
                <span className="m-caption m-caption--coral">OPEN ↗</span>
              </div>
              <div className="m-caption m-caption--faint m-mt-6">
                {workout.miles} MI · {workout.duration} · {workout.avgPace} / MI · {workout.hrAvg} BPM
              </div>
            </Link>
          ) : (
            <EmptyState nudge="No workout attached. Link one from your recent runs." cta={{ label: "Link a run", href: "/mockup/log" }} quiet />
          )}
        </Section>

        <Spacer h={24} />
        <div className="m-row">
          <span className="m-link m-link--quiet m-link--sm">Edit entry</span>
          <span className="m-link m-link--quiet m-link--sm">Delete</span>
        </div>
      </div>
    </>
  );
}
