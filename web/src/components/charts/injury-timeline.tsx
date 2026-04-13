"use client";

interface InjuryData {
  id: string;
  bodyArea: string;
  severity: number;
  startDate: string;
  endDate?: string;
  status: string;
}

interface InjuryTimelineProps {
  injuries: InjuryData[];
}

const SEVERITY_COLORS = [
  "#4A9E6B", // 1-2 mild (green)
  "#4A9E6B",
  "#C4873A", // 3-4 moderate (amber)
  "#C4873A",
  "#C45A3A", // 5-6 (terracotta)
  "#C45A3A",
  "#B83A4A", // 7-8 severe (rose)
  "#B83A4A",
  "#B83A4A", // 9-10 critical
  "#B83A4A",
];

export function InjuryTimeline({ injuries }: InjuryTimelineProps) {
  if (!injuries.length) return null;

  const now = new Date();
  const dates = injuries.flatMap((i) => [
    new Date(i.startDate).getTime(),
    i.endDate ? new Date(i.endDate).getTime() : now.getTime(),
  ]);
  const minDate = Math.min(...dates);
  const maxDate = Math.max(...dates);
  const range = maxDate - minDate || 1;

  return (
    <div className="space-y-2">
      {injuries.map((injury) => {
        const start = new Date(injury.startDate).getTime();
        const end = injury.endDate ? new Date(injury.endDate).getTime() : now.getTime();
        const left = ((start - minDate) / range) * 100;
        const width = Math.max(((end - start) / range) * 100, 2);
        const color = SEVERITY_COLORS[Math.min(injury.severity - 1, 9)] || "#9B9590";

        return (
          <div key={injury.id} className="flex items-center gap-3">
            <span className="text-xs text-text-secondary w-24 truncate font-body">
              {injury.bodyArea}
            </span>
            <div className="relative flex-1 h-4 bg-bg-elevated rounded">
              <div
                className="absolute h-full rounded"
                style={{
                  left: `${left}%`,
                  width: `${width}%`,
                  backgroundColor: color,
                  opacity: injury.status === "resolved" ? 0.4 : 0.7,
                }}
              />
            </div>
            <span className="font-mono text-[10px] text-text-tertiary w-8 text-right">
              {injury.severity}/10
            </span>
          </div>
        );
      })}
    </div>
  );
}
