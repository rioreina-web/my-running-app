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
        className={`${crimsonPro.variable} ${ptSerif.variable} antialiased`}
      >
        {children}
      </body>
    </html>
  );
}
