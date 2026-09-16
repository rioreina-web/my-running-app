import type { Metadata } from "next";
import localFont from "next/font/local";
import "./globals.css";

// Post Run Drip's canonical type, SELF-HOSTED — the exact TTFs the iOS app
// ships (RunningLog/Fonts, mirrored in design-system/fonts, copied to
// src/fonts). Crimson Pro is the display serif; PT Serif carries body +
// italic quotes. Previously these loaded via next/font/google, which
// fetches from Google at compile time and silently falls back to a
// metrics-adjusted system serif when the fetch fails — the brand quietly
// disappears. Local files can't fail. The mono stack (eyebrows, stats,
// tabular numerals) is the design system's own: ui-monospace first — see
// --font-mono in globals.css and design-system/colors_and_type.css.
const crimsonPro = localFont({
  src: "../fonts/CrimsonPro-Variable.ttf",
  weight: "200 900",
  style: "normal",
  display: "swap",
  variable: "--font-crimson-pro",
});

const ptSerif = localFont({
  src: [
    { path: "../fonts/PTSerif-Regular.ttf", weight: "400", style: "normal" },
    { path: "../fonts/PTSerif-Italic.ttf", weight: "400", style: "italic" },
    { path: "../fonts/PTSerif-Bold.ttf", weight: "700", style: "normal" },
  ],
  display: "swap",
  variable: "--font-pt-serif",
});

// Direction I — the locked four-role system from design-system/CLAUDE.md,
// mirroring `WildFace` in RunningLog/App/DripTheme.swift face for face and
// weight for weight. Same TTFs the app bundles, copied from
// RunningLog/Fonts. Self-hosted for the same reason as the two above.
//
// Scoped, not global: only [data-skin="wild"] subtrees resolve these (see
// globals.css). That mirrors DripTheme's own note — the skin switch is
// "DELIBERATELY NOT GLOBAL (yet)" — so repainting the coach portal cannot
// repaint the log, trends, or plan surfaces by accident.
const instrumentSans = localFont({
  src: [
    { path: "../fonts/InstrumentSans-Medium.ttf", weight: "500", style: "normal" },
    { path: "../fonts/InstrumentSans-SemiBold.ttf", weight: "600", style: "normal" },
    { path: "../fonts/InstrumentSans-Bold.ttf", weight: "700", style: "normal" },
  ],
  display: "swap",
  variable: "--font-instrument-sans",
});

const schibstedGrotesk = localFont({
  src: [
    { path: "../fonts/SchibstedGrotesk-Medium.ttf", weight: "500", style: "normal" },
    { path: "../fonts/SchibstedGrotesk-SemiBold.ttf", weight: "600", style: "normal" },
    { path: "../fonts/SchibstedGrotesk-Bold.ttf", weight: "700", style: "normal" },
  ],
  display: "swap",
  variable: "--font-schibsted",
});

const inter = localFont({
  src: [
    { path: "../fonts/Inter-Regular.ttf", weight: "400", style: "normal" },
    { path: "../fonts/Inter-Medium.ttf", weight: "500", style: "normal" },
    { path: "../fonts/Inter-SemiBold.ttf", weight: "600", style: "normal" },
  ],
  display: "swap",
  variable: "--font-inter",
});

const jetBrainsMono = localFont({
  src: [
    { path: "../fonts/JetBrainsMono-Regular.ttf", weight: "400", style: "normal" },
    { path: "../fonts/JetBrainsMono-Medium.ttf", weight: "500", style: "normal" },
    { path: "../fonts/JetBrainsMono-Italic.ttf", weight: "400", style: "italic" },
  ],
  display: "swap",
  variable: "--font-jetbrains",
});

export const metadata: Metadata = {
  title: "Post Run Drip",
  description:
    "A running log for runners with a goal time and a base.",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body
        className={`${crimsonPro.variable} ${ptSerif.variable} ${instrumentSans.variable} ${schibstedGrotesk.variable} ${inter.variable} ${jetBrainsMono.variable} antialiased`}
      >
        {children}
      </body>
    </html>
  );
}
