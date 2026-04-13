export function DropCap({ text, className = "" }: { text: string; className?: string }) {
  if (!text) return null;
  const first = text.charAt(0);
  const rest = text.slice(1);

  return (
    <div className={`flex gap-2 ${className}`}>
      <span className="font-display text-[44px] leading-none text-coral pt-1 w-9 flex-shrink-0">
        {first}
      </span>
      <p className="font-body text-[15px] text-text-primary/85 leading-7">
        {rest}
      </p>
    </div>
  );
}
