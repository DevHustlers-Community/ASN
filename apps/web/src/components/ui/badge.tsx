import * as React from 'react';
import { cva, type VariantProps } from 'class-variance-authority';
import { cn } from '@/lib/utils';

export const badgeVariants = cva(
  'inline-flex items-center gap-1.5 rounded-pill border px-2.5 py-0.5 text-xs font-medium transition-colors font-mono',
  {
    variants: {
      variant: {
        default: 'border-primary/30 bg-primary/10 text-primary',
        secondary: 'border-border bg-surface text-text-muted',
        outline: 'border-border text-text-main',
        destructive: 'border-status-destructive/40 bg-status-destructive/15 text-rose-400',
        success: 'border-status-success/40 bg-status-success/15 text-emerald-400',
        warning: 'border-status-warning/40 bg-status-warning/15 text-amber-400',
        info: 'border-status-info/40 bg-status-info/15 text-sky-400',
      },
    },
    defaultVariants: {
      variant: 'default',
    },
  }
);

export interface BadgeProps
  extends React.HTMLAttributes<HTMLDivElement>,
    VariantProps<typeof badgeVariants> {}

export function Badge({ className, variant, ...props }: BadgeProps) {
  return <div className={cn(badgeVariants({ variant }), className)} {...props} />;
}
