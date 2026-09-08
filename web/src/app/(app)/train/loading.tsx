export default function PlanLoading() {
  return (
    <div className="mx-auto max-w-5xl space-y-8 animate-pulse">
      {/* Header */}
      <div className="h-8 w-40 rounded bg-bg-elevated" />

      {/* Plan card */}
      <div className="rounded-xl bg-bg-card shadow-[0_2px_8px_rgba(0,0,0,0.06)] p-5">
        <div className="h-5 w-48 rounded bg-bg-elevated" />
        <div className="mt-2 h-3 w-32 rounded bg-bg-elevated" />
      </div>

      <div className="h-px bg-divider" />

      {/* Compliance chart */}
      <div>
        <div className="h-3 w-32 rounded bg-bg-elevated" />
        <div className="mt-4 h-44 rounded-xl bg-bg-card shadow-[0_2px_8px_rgba(0,0,0,0.06)]" />
      </div>

      <div className="h-px bg-divider" />

      {/* Weekly grid */}
      <div className="space-y-6">
        {[1, 2].map((w) => (
          <div key={w}>
            <div className="h-3 w-28 rounded bg-bg-elevated" />
            <div className="mt-3 grid grid-cols-7 gap-2">
              {Array.from({ length: 7 }).map((_, i) => (
                <div
                  key={i}
                  className="h-20 rounded-lg bg-bg-elevated/50"
                />
              ))}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
