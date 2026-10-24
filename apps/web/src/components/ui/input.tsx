import * as React from 'react';
import { cn } from '@/lib/utils';

export interface InputProps extends React.InputHTMLAttributes<HTMLInputElement> {
  error?: string;
  startIcon?: React.ReactNode;
  endIcon?: React.ReactNode;
}

export const Input = React.forwardRef<HTMLInputElement, InputProps>(
  ({ className, type, error, startIcon, endIcon, ...props }, ref) => {
    return (
      <div className="w-full space-y-1">
        <div className="relative flex items-center">
          {startIcon && (
            <span className="absolute start-3 text-text-dim pointer-events-none flex items-center">
              {startIcon}
            </span>
          )}
          <input
            type={type}
            className={cn(
              'flex h-10 w-full rounded-btn border border-border bg-surface px-3 py-2 text-xs text-text-main ring-offset-base file:border-0 file:bg-transparent file:text-xs file:font-medium placeholder:text-text-dim focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-primary disabled:cursor-not-allowed disabled:opacity-50 text-start',
              startIcon && 'ps-9',
              endIcon && 'pe-9',
              error && 'border-status-destructive focus-visible:ring-status-destructive',
              className
            )}
            ref={ref}
            {...props}
          />
          {endIcon && (
            <span className="absolute end-3 text-text-dim flex items-center">
              {endIcon}
            </span>
          )}
        </div>
        {error && (
          <p className="text-[11px] font-medium text-status-destructive flex items-center gap-1">
            <span>⚠️</span>
            <span>{error}</span>
          </p>
        )}
      </div>
    );
  }
);
Input.displayName = 'Input';
