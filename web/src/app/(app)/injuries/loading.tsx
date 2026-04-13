export default function InjuriesLoading() {
  return (
    <div className="mx-auto max-w-5xl space-y-8 animate-pulse">
      {/* Header */}
      <div className="h-8 w-28 rounded bg-bg-elevated" />

      {/* Timeline card */}
      <div className="rounded-xl bg-bg-card shadow-[0_2px_8px_rgba(0,0,0,0.06)] p-5">
        <div className="h-3 w-20 rounded bg-bg-elevated" />
        <div className="mt-4 h-32 rounded bg-bg-elevated" />
      </div>

      <div className="h-px bg-divider" />

      {/* Active section */}
      <div>
        <div className="h-3 w-24 rounded bg-bg-elevated" />
        <div className="mt-4 space-y-4">
          {[1, 2].map((i) => (
            <div
              key={i}
              className="rounded-xl bg-bg-card shadow-[0_2px_8px_rgba(0,0,0,0.06)] border-l-2 border-coral p-5"
            >
              <div className="flex items-center gap-3">
                <div className="w-1 h-8 rounded-full bg-bg-elevated" />
                <div>
                  <div className="h-5 w-32 rounded bg-bg-elevated" />
                  <div className="mt-1 h-3 w-24 rounded bg-bg-elevated" />
                </div>
                <div className="ml-auto h-8 w-12 rounded bg-bg-elevated" />
              </div>
              <div className="mt-3 h-4 w-3/4 rounded bg-bg-elevated" />
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
