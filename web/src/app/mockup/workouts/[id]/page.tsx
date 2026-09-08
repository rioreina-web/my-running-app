import Link from "next/link";
import { notFound } from "next/navigation";
import { EditorialRule, Eyebrow, MoodPill, PlateStrip, Quoted, Section, SheetChrome, Spacer, StripCell } from "@/components/mockup/primitives";
import { Telemetry } from "@/components/mockup/charts";
import { ACWR, JOURNAL, WORKOUTS } from "@/components/mockup/data";

/* Workout detail · Plate 23, "Pace, narrated". The narration is the
   athlete's own memo, not an AI caption. The data does the rest. */

export default async function WorkoutPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const w = WORKOUTS[id];
  if (!w) notFound();
  const entry = JOURNAL.find((e) => e.id === w.entryId);
  const secs = w.splits.map((s) => s.sec);
  const max = Math.max(...secs);
  const min = Math.min(...secs);

  return (
    <>
      <PlateStrip surface="WORKOUT DETAIL · SHARPENED" fig="FIG. 23" />
      <div className="m-body">
        <SheetChrome back="/mockup/log" backLabel="Back" surface="WORKOUT" action={{ label: "Share", href: "#" }} />

        <div className="m-section m-mt-14">
          <Eyebrow coral>
            {w.dow} · {w.zone.toUpperCase()}
          </Eyebrow>
          <h1 className="m-display m-display--l">{w.date}</h1>
          <p className="m-quote m-quote--sub">
            {w.miles} mi · {w.duration} · Apple Watch
          </p>
        </div>

        <Spacer h={12} />
        <div className="m-strip m-strip--4">
          <StripCell l="DISTANCE" v={w.miles} u="mi" s={w.elev} />
          <StripCell l="DURATION" v={w.duration} s={`${w.avgPace} avg`} />
          <StripCell l="GAP" v={w.gap} u="/mi" s="grade-adjusted" />
          <StripCell l="LOAD" v={w.load} s={w.loadDelta} />
        </div>
        <div className="m-strip m-strip--5 m-strip--noborder-top">
          <StripCell l="CADENCE" v={w.cadence} s="spm" center small />
          <StripCell l="DRIFT" v={w.drift} s="Pa:Hr" center small />
          <StripCell l="HR AVG" v={w.hrAvg} s={w.hrZone} center small />
          <StripCell l="WEEK" v={w.weekIndex} s={`${w.weekMiles} mi`} center small />
          <StripCell l="SOURCE" v="WATCH" s="synced" center small />
        </div>

        <Section eyebrow="TELEMETRY · PACE × HR × ELEVATION" eyebrowRight="WHOLE RUN">
          <div className="m-card m-card--tight m-mt-6">
            <Telemetry pace={w.paceSeries} hr={w.hrSeries} elev={w.elevSeries} />
            <div className="m-legend">
              <span className="m-legend__item"><span className="m-legend__sw" />PACE</span>
              <span className="m-legend__item"><span className="m-legend__sw is-coral" />HEART RATE</span>
              <span className="m-legend__item"><span className="m-legend__sw is-faint" />ELEVATION</span>
            </div>
          </div>
        </Section>

        <Section eyebrow="SPLITS" eyebrowRight={`FASTEST IN CORAL`}>
          <table className="m-splits m-mt-6">
            <thead>
              <tr>
                <th>MI</th>
                <th>PACE</th>
                <th className="r">HR</th>
                <th className="r">VS AVG</th>
              </tr>
            </thead>
            <tbody>
              {w.splits.map((s) => {
                const isFastest = s.sec === min;
                const avg = secs.reduce((a, b) => a + b, 0) / secs.length;
                const d = Math.round(s.sec - avg);
                void max;
                return (
                  <tr key={s.mi} className={isFastest ? "is-key" : ""}>
                    <td>{s.mi}</td>
                    <td>{s.pace}</td>
                    <td className="r">{s.hr}</td>
                    <td className="r">{d > 0 ? `+${d}s` : `${d}s`}</td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </Section>

        <Spacer h={20} />
        <EditorialRule />

        <Section eyebrow="THE MEMO" eyebrowRight={entry?.kind === "voice" ? `VOICE · ${entry.voiceLength}` : entry ? "TYPED" : undefined}>
          {entry?.body ? (
            <>
              <p className="m-quote m-mt-6">
                <Quoted>{entry.body}</Quoted>
              </p>
              <div className="m-flex m-gap-8 m-items-center m-wrap m-mt-12">
                {entry.mood ? <MoodPill mood={entry.mood} /> : null}
                {entry.niggles?.map((n) => (
                  <Link key={n.part} href="/mockup/niggles" className="m-chip m-chip--niggle">
                    {n.side ? `${n.side} ` : ""}
                    {n.part}
                  </Link>
                ))}
                {entry.life?.map((l) => (
                  <span key={l} className="m-chip m-chip--life">
                    {l}
                  </span>
                ))}
              </div>
              <div className="m-mt-12">
                <Link href={`/mockup/log/${entry.id}`} className="m-link m-link--quiet m-link--sm">
                  Open the entry ↗
                </Link>
              </div>
            </>
          ) : (
            <p className="m-quote m-quote--faint m-mt-6">No memo on this run. Add one from the log.</p>
          )}
        </Section>

        <Spacer h={16} />
        <EditorialRule />

        <Section eyebrow="WEEKLY CONTEXT">
          <p className="m-quote m-mt-4">
            Run {w.weekIndex} this week. {w.weekMiles} mi banked.
          </p>
          <p className="m-quote m-quote--faint m-mt-4">
            Acute-to-chronic load now {ACWR.value}, still in the productive band.
          </p>
        </Section>

        <Spacer h={24} />
      </div>
    </>
  );
}
