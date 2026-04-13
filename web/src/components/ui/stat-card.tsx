import { ReactNode } from "react";

interface StatCardProps {
  value: string;
  label: string;
  icon?: ReactNode;
  accentColor?: string;
  sparkline?: ReactNode;
  trend?: "up" | "down" | "flat";
}

export function StatCard({ value, label, icon, accentColor, sparkline, trend }: StatCardProps) {
  return (
    <div className="bg-bg-card rounded-xl shadow-[0_2px_8px_rgba(0,0,0,0.06)] p-4">
      <div className="flex items-start justify-between">
        <div className="space-y-2">
          {icon && (
            <div className={accentColor ? `text-[${accentColor}]` : "text-coral"}>
              {icon}
            </div>
          )}
          <div className="font-mono text-2xl font-semibold text-text-primary">{value}</div>
          <div className="text-[10px] font-medium tracking-[1.2px] uppercase text-text-secondary">
            {label}
          </div>
        </div>
        <div className="flex flex-col items-end gap-1">
          {trend && (
            <span className={`text-xs font-medium ${
              trend === "up" ? "text-mood-energized" : trend === "down" ? "text-mood-tired" : "text-text-tertiary"
            }`}>
              {trend === "up" ? "↑" : trend === "down" ? "↓" : "→"}
            </span>
          )}
          {sparkline}
        </div>
      </div>
    </div>
  );
}
