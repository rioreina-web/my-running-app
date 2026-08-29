import type { Metadata } from "next";
import { Crimson_Pro, JetBrains_Mono, PT_Serif } from "next/font/google";
import "./globals.css";

// Post Run Drip ships Crimson Pro (display) + PT Serif (body) in the iOS
// bundle — see design-system/fonts/. The web served Playfair + DM Sans, which
// read as a different brand next to the app; these are the same two families.
const crimsonPro = Crimson_Pro({
  subsets: ["latin"],
  variable: "--font-crimson-pro",
});

const jetbrainsMono = JetBrains_Mono({
  subsets: ["latin"],
  variable: "--font-jetbrains-mono",
});

const ptSerif = PT_Serif({
  subsets: ["latin"],
  weight: ["400", "700"],
  style: ["normal", "italic"],
  variable: "--font-pt-serif",
});

export const metadata: Metadata = {
  title: {
    default: "Post Run Drip — a training log for self-coached runners",
    template: "%s · Post Run Drip",
  },
  description:
    "Voice-log the run, sync the watch, and get your training read back honestly — anchored to races you have actually run. No prescriptions, no diagnoses.",
};

/**
 * Every route renders per request.
 *
 * middleware.ts serves a nonce-based CSP, and a nonce only exists per
 * request — a prerendered page ships script tags without one, so the policy
 * blocks its own framework chunks and the page never hydrates. Nothing here
 * is served from a static cache in practice anyway: the middleware calls
 * supabase.auth.getUser() on every route it matches.
 */
export const dynamic = "force-dynamic";

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body
        className={`${crimsonPro.variable} ${jetbrainsMono.variable} ${ptSerif.variable} antialiased`}
      >
        {children}
      </body>
    </html>
  );
}
