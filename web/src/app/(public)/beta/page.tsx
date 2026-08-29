import type { Metadata } from "next";

import { Eyebrow, PlateStrip, EditorialRule } from "@/components/site/editorial";
import { BetaForm } from "./beta-form";

export const metadata: Metadata = {
  title: "Request an invite",
  description:
    "Post Run Drip is in closed beta on iOS, by TestFlight invite. Built for runners with a race on the calendar and a base under them.",
};

const EXPECTATIONS: [string, string][] = [
  [
    "What you get",
    "The iOS app on TestFlight, with the four surfaces working end to end. Two years of HealthKit history back-fills on first launch, so the log is not empty when you open it.",
  ],
  [
    "What is not built yet",
    "Recovery is partly there — sleep and how you said you felt — but it is not its own surface yet. Mobility and strength are not started. Android is not on the map.",
  ],
  [
    "What we want back",
    "The places the read gets it wrong. A sentence that sounded like a robot, a number that did not match how the run felt, a screen that made you close the app.",
  ],
  [
    "What it costs",
    "Nothing during the beta. When there is a price, you will hear it from us before you see it in an app store.",
  ],
];

export default function BetaPage() {
  return (
    <>
      <PlateStrip
        surface="Beta · closed"
        fig="Fig. 07"
        right="TestFlight · 2026"
      />

      <section className="border-b border-divider">
        <div className="mx-auto grid max-w-[1180px] items-start gap-14 px-6 py-16 md:px-10 lg:grid-cols-[1fr_0.9fr] lg:py-20">
          <div>
            <Eyebrow coral>iOS · by invite</Eyebrow>
            <h1 className="mt-5 max-w-[14ch] font-display text-[clamp(40px,7vw,64px)] font-bold leading-[1] tracking-[-0.02em] text-text-primary">
              Run a week with it.
            </h1>
            <p className="mt-7 max-w-[52ch] font-body text-[17px] leading-[1.6] text-text-secondary">
              Invites go out in small batches, because the point of a beta is
              reading every reply. Tell us what you are training for and we
              will fit you into one.
            </p>

            <EditorialRule className="my-10" />

            <dl className="space-y-8">
              {EXPECTATIONS.map(([term, detail]) => (
                <div key={term}>
                  <dt>
                    <Eyebrow>{term}</Eyebrow>
                  </dt>
                  <dd className="mt-2 max-w-[54ch] font-body text-[15px] leading-[1.65] text-text-secondary">
                    {detail}
                  </dd>
                </div>
              ))}
            </dl>
          </div>

          <BetaForm />
        </div>
      </section>
    </>
  );
}
