interface SectionHeaderProps {
  title: string;
  subtitle?: string;
  action?: () => void;
  actionLabel?: string;
  actionHref?: string;
}

export function SectionHeader({ title, subtitle, action, actionLabel, actionHref }: SectionHeaderProps) {
  return (
    <div className="space-y-2">
      <div className="flex items-baseline justify-between px-1">
        <span className="font-body text-[11px] font-medium tracking-[1.5px] uppercase text-text-secondary">
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
