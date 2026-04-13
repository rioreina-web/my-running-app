export default function LogLoading() {
  return (
    <div className="mx-auto max-w-5xl space-y-6 animate-pulse">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div className="h-8 w-36 rounded bg-bg-elevated" />
        <div className="h-3 w-20 rounded bg-bg-elevated" />
      </div>

      {/* Log entries */}
      <div className="rounded-xl bg-bg-card shadow-[0_2px_8px_rgba(0,0,0,0.06)]">
        {Array.from({ length: 8 }).map((_, i) => (
          <div
            key={i}
            className="flex items-center gap-4 px-4 py-3 border-b border-divider last:border-0"
          >
            <div className="h-3 w-20 rounded bg-bg-elevated" />
            <div className="h-5 w-14 rounded bg-bg-elevated" />
            <div className="h-3 w-16 rounded bg-bg-elevated" />
            <div className="h-3 w-12 rounded bg-bg-elevated" />
            <div className="h-5 w-5 rounded-full bg-bg-elevated" />
            <div className="ml-auto h-3 w-12 rounded bg-bg-elevated" />
          </div>
        ))}
      </div>
    </div>
  );
}
