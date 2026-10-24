import * as React from 'react';
import { cva, type VariantProps } from 'class-variance-authority';
import { cn } from '@/lib/utils';

export const badgeVariants = cva(
  'inline-flex items-center gap-1 rounded-pill border px-3 py-1 text-xs font-medium transition-colors font-mono',
  {
    variants: {
      variant: {
        default: 'border-primary/30 bg-primary/10 text-primary-text',
        secondary: 'border-border bg-surface text-text-muted',
        outline: 'border-border text-text-main',
        destructive: 'border-status-destructive/40 bg-status-destructive/15 text-status-destructive-foreground',
        success: 'border-status-success/40 bg-status-success/15 text-status-success-foreground',
        warning: 'border-status-warning/40 bg-status-warning/15 text-status-warning-foreground',
        info: 'border-status-info/40 bg-status-info/15 text-status-info-foreground',
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
