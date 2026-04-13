export default function GoalsLoading() {
  return (
    <div className="mx-auto max-w-5xl space-y-8 animate-pulse">
      {/* Header */}
      <div className="h-8 w-24 rounded bg-bg-elevated" />

      {/* Active section */}
      <div>
        <div className="h-3 w-24 rounded bg-bg-elevated" />
        <div className="mt-4 grid gap-4 sm:grid-cols-2">
          {[1, 2].map((i) => (
            <div
              key={i}
              className="rounded-xl bg-bg-card shadow-[0_2px_8px_rgba(0,0,0,0.06)] border-l-2 border-coral p-5"
            >
              <div className="flex items-start justify-between">
                <div>
                  <div className="h-5 w-36 rounded bg-bg-elevated" />
                  <div className="mt-2 h-4 w-16 rounded bg-bg-elevated" />
                </div>
                <div className="text-right">
                  <div className="h-7 w-10 rounded bg-bg-elevated" />
                  <div className="mt-1 h-3 w-14 rounded bg-bg-elevated" />
                </div>
              </div>
              <div className="mt-3 h-3 w-32 rounded bg-bg-elevated" />
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
