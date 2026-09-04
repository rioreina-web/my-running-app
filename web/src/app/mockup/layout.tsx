import type { Metadata } from "next";
import localFont from "next/font/local";
import { MockupShell } from "@/components/mockup/shell";
import "./mockup.css";

/* /mockup/* — the athlete-facing site, mocked end to end.

   Post Run Drip's own typefaces (Crimson Pro display, PT Serif body) are
   loaded here from the TTFs the iOS app ships, so the web reads exactly
   like the app. JetBrains Mono comes from the root layout and stands in
   for SF Mono. Everything under this layout is mock data; see
   web/src/components/mockup/data.ts. */

const crimson = localFont({
  src: "./fonts/CrimsonPro-Variable.ttf",
  weight: "200 900",
  variable: "--m-font-display",
  display: "swap",
});

const ptSerif = localFont({
  src: [
    { path: "./fonts/PTSerif-Regular.ttf", weight: "400", style: "normal" },
    { path: "./fonts/PTSerif-Italic.ttf", weight: "400", style: "italic" },
    { path: "./fonts/PTSerif-Bold.ttf", weight: "700", style: "normal" },
  ],
  variable: "--m-font-body",
  display: "swap",
});

/* The middleware sets a per-request nonce CSP. Statically prerendered
   pages carry no nonce, so their scripts get blocked; rendering this
   route group dynamically keeps the interactive parts working. */
export const dynamic = "force-dynamic";

export const metadata: Metadata = {
  title: "Post Run Drip · athlete site mockup",
  description: "The athlete-facing site, mocked with Maya's data. Not connected to real accounts.",
  robots: { index: false, follow: false },
};

export default function MockupLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className={`${crimson.variable} ${ptSerif.variable}`}>
      <MockupShell>{children}</MockupShell>
    </div>
  );
}
