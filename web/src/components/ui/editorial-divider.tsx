export function EditorialDivider({ className = "" }: { className?: string }) {
  return (
    <div className={`flex items-center gap-2 ${className}`}>
      <div className="flex-1 h-px bg-divider" />
      <div className="w-[3px] h-[3px] rounded-full bg-divider" />
      <div className="flex-1 h-px bg-divider" />
    </div>
  );
}
