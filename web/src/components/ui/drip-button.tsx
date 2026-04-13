import { ReactNode, ButtonHTMLAttributes } from "react";

interface DripButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: "primary" | "secondary" | "ghost";
  icon?: ReactNode;
  isLoading?: boolean;
  children: ReactNode;
}

export function DripButton({
  variant = "primary",
  icon,
  isLoading,
  children,
  className = "",
  ...props
}: DripButtonProps) {
  const base = "inline-flex items-center justify-center gap-2 px-4 py-3 rounded-lg font-semibold text-[15px] transition-colors disabled:opacity-50";

  const variants = {
    primary: "bg-coral text-white hover:bg-coral-dark",
    secondary: "border-[1.5px] border-coral text-coral hover:bg-coral/5",
    ghost: "bg-bg-card text-text-primary hover:bg-bg-elevated",
  };

  return (
    <button className={`${base} ${variants[variant]} ${className}`} disabled={isLoading} {...props}>
      {isLoading ? (
        <div className="w-4 h-4 border-2 border-current border-t-transparent rounded-full animate-spin" />
      ) : icon ? (
        icon
      ) : null}
      {children}
    </button>
  );
}
