import Link from "next/link";
import { Eyebrow } from "./editorial";

const COLUMNS: { heading: string; links: { href: string; label: string }[] }[] =
  [
    {
      heading: "Product",
      links: [
        { href: "/how-it-works", label: "How it works" },
        { href: "/principles", label: "Principles" },
        { href: "/blog", label: "Blog" },
      ],
    },
    {
      heading: "Account",
      links: [
        { href: "/login", label: "Sign in" },
        { href: "/beta", label: "Request an invite" },
      ],
    },
  ];

export function SiteFooter() {
  return (
    <footer className="border-t border-divider bg-bg-base">
      <div className="mx-auto max-w-[1180px] px-6 py-14 md:px-10">
        <div className="grid gap-10 md:grid-cols-[1.4fr_1fr_1fr]">
          <div>
            <div className="font-display text-[20px] font-bold tracking-[-0.01em] text-text-primary">
              Post Run Drip
            </div>
            <p className="mt-3 max-w-[34ch] font-body text-[14px] leading-[1.6] text-text-secondary">
              A training log for runners coaching themselves. Voice in, honest
              observation out.
            </p>
          </div>

          {COLUMNS.map((col) => (
            <div key={col.heading}>
              <Eyebrow>{col.heading}</Eyebrow>
              <ul className="mt-4 space-y-2.5">
                {col.links.map((link) => (
                  <li key={link.href}>
                    <Link
                      href={link.href}
                      className="font-body text-[14px] text-text-secondary transition-colors hover:text-text-primary"
                    >
                      {link.label}
                    </Link>
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </div>

        <div className="mt-12 flex flex-wrap items-baseline justify-between gap-3 border-t border-divider pt-6">
          <Eyebrow>© {new Date().getFullYear()} · Austin, TX</Eyebrow>
          <span className="font-body text-[13px] italic text-text-tertiary">
            — restraint as foundation, intensity as accent
          </span>
        </div>
      </div>
    </footer>
  );
}
