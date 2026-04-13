export default function DashboardLoading() {
  return (
    <div className="mx-auto max-w-5xl space-y-8 animate-pulse">
      {/* Header skeleton */}
      <div>
        <div className="h-8 w-40 rounded bg-bg-elevated" />
        <div className="mt-2 h-4 w-56 rounded bg-bg-elevated" />
      </div>

      {/* Narrative lede skeleton */}
      <div className="h-12 w-3/4 rounded bg-bg-elevated" />

      {/* Stats grid */}
      <div className="grid grid-cols-2 gap-4 md:grid-cols-4">
        {[1, 2, 3, 4].map((i) => (
          <div
            key={i}
            className="rounded-xl bg-bg-card shadow-[0_2px_8px_rgba(0,0,0,0.06)] p-4"
          >
            <div className="h-7 w-16 rounded bg-bg-elevated" />
            <div className="mt-2 h-3 w-12 rounded bg-bg-elevated" />
          </div>
        ))}
      </div>

      {/* Divider */}
      <div className="h-px bg-divider" />

      {/* Chart skeleton */}
      <div>
        <div className="h-3 w-32 rounded bg-bg-elevated" />
        <div className="mt-4 h-40 rounded-xl bg-bg-elevated" />
      </div>

      {/* Divider */}
      <div className="h-px bg-divider" />

      {/* Recent runs skeleton */}
      <div>
        <div className="h-3 w-28 rounded bg-bg-elevated" />
        <div className="mt-4 rounded-xl bg-bg-card shadow-[0_2px_8px_rgba(0,0,0,0.06)]">
          {[1, 2, 3].map((i) => (
            <div
              key={i}
              className="flex items-center gap-4 px-4 py-3 border-b border-divider last:border-0"
            >
              <div className="h-3 w-20 rounded bg-bg-elevated" />
              <div className="h-5 w-12 rounded bg-bg-elevated" />
              <div className="h-3 w-16 rounded bg-bg-elevated" />
              <div className="ml-auto h-3 w-12 rounded bg-bg-elevated" />
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
