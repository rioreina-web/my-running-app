import { ReactNode } from "react";

interface CardProps {
  children: ReactNode;
  className?: string;
  accent?: boolean;
  padding?: "sm" | "md" | "lg";
}

export function Card({ children, className = "", accent, padding = "md" }: CardProps) {
  const paddings = { sm: "p-3", md: "p-4", lg: "p-5" };
  return (
    <div
      className={`bg-bg-card rounded-xl shadow-[0_2px_8px_rgba(0,0,0,0.06)] ${paddings[padding]} ${
        accent ? "border-l-2 border-l-coral" : ""
      } ${className}`}
    >
      {children}
    </div>
  );
}
