import { ReactNode } from "react";

export function NarrativeStat({ children, className = "" }: { children: ReactNode; className?: string }) {
  return <p className={`leading-relaxed ${className}`}>{children}</p>;
}

export function StatValue({ children, size = "lg" }: { children: ReactNode; size?: "sm" | "md" | "lg" }) {
  const sizes = {
    sm: "font-display text-xl",
    md: "font-display text-2xl",
    lg: "font-display text-[40px]",
  };
  return <span className={`${sizes[size]} text-text-primary`}>{children}</span>;
}

export function StatAccent({ children, size = "md" }: { children: ReactNode; size?: "sm" | "md" | "lg" }) {
  const sizes = {
    sm: "font-display text-lg",
    md: "font-display text-2xl",
    lg: "font-display text-[28px]",
  };
  return <span className={`${sizes[size]} text-coral`}>{children}</span>;
}

export function StatLabel({ children }: { children: ReactNode }) {
  return <span className="font-body text-base text-text-secondary">{children}</span>;
}

export function StatMuted({ children }: { children: ReactNode }) {
  return <span className="font-body text-base text-text-tertiary">{children}</span>;
}
