interface SectionHeaderProps {
  title: string;
  subtitle?: string;
  action?: () => void;
  actionLabel?: string;
  actionHref?: string;
  /** Mark the section as the active/live one — turns the label coral. */
  coral?: boolean;
}

export function SectionHeader({ title, subtitle, action, actionLabel, actionHref, coral }: SectionHeaderProps) {
  return (
    <div className="space-y-2">
      <div className="flex items-baseline justify-between px-1">
        <span
          className={`font-mono text-[11px] font-medium tracking-[0.12em] uppercase ${
            coral ? "text-coral" : "text-text-secondary"
          }`}
        >
          {title}
          {subtitle ? (
            <span className="ml-2 tracking-normal normal-case text-text-secondary/70">{subtitle}</span>
          ) : null}
        </span>
        {actionHref && actionLabel ? (
          <a href={actionHref} className="text-[11px] text-coral italic hover:text-coral-dark transition-colors">
            {actionLabel}
          </a>
        ) : action && actionLabel ? (
          <button onClick={action} className="text-[11px] text-coral italic hover:text-coral-dark transition-colors">
            {actionLabel}
          </button>
        ) : null}
      </div>
      <div className="h-px bg-divider" />
    </div>
  );
}
