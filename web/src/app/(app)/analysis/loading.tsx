export default function AnalysisLoading() {
  return (
    <div className="mx-auto max-w-5xl space-y-8 animate-pulse">
      {/* Header */}
      <div>
        <div className="h-8 w-52 rounded bg-bg-elevated" />
        <div className="mt-2 h-4 w-24 rounded bg-bg-elevated" />
      </div>

      {/* Lede */}
      <div className="h-12 w-3/4 rounded bg-bg-elevated" />

      <div className="h-px bg-divider" />

      {/* Chart */}
      <div>
        <div className="h-3 w-32 rounded bg-bg-elevated" />
        <div className="mt-4 h-52 rounded-xl bg-bg-card shadow-[0_2px_8px_rgba(0,0,0,0.06)]" />
      </div>

      <div className="h-px bg-divider" />

      {/* Two charts side by side */}
      <div className="grid gap-6 md:grid-cols-2">
        <div>
          <div className="h-3 w-24 rounded bg-bg-elevated" />
          <div className="mt-4 h-52 rounded-xl bg-bg-card shadow-[0_2px_8px_rgba(0,0,0,0.06)]" />
        </div>
        <div>
          <div className="h-3 w-28 rounded bg-bg-elevated" />
          <div className="mt-4 h-52 rounded-xl bg-bg-card shadow-[0_2px_8px_rgba(0,0,0,0.06)]" />
        </div>
      </div>

      <div className="h-px bg-divider" />

      {/* Two more charts */}
      <div className="grid gap-6 md:grid-cols-2">
        <div>
          <div className="h-3 w-28 rounded bg-bg-elevated" />
          <div className="mt-4 h-52 rounded-xl bg-bg-card shadow-[0_2px_8px_rgba(0,0,0,0.06)]" />
        </div>
        <div>
          <div className="h-3 w-24 rounded bg-bg-elevated" />
          <div className="mt-4 h-52 rounded-xl bg-bg-card shadow-[0_2px_8px_rgba(0,0,0,0.06)]" />
        </div>
      </div>
    </div>
  );
}
