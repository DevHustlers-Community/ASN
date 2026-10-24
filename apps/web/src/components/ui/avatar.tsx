import * as React from 'react';
import * as AvatarPrimitive from '@radix-ui/react-avatar';
import { cn } from '@/lib/utils';

export interface AvatarProps extends React.ComponentPropsWithoutRef<typeof AvatarPrimitive.Root> {
  presence?: 'online' | 'offline' | 'away';
  presenceSize?: 'sm' | 'md' | 'lg';
}

export const Avatar = React.forwardRef<React.ElementRef<typeof AvatarPrimitive.Root>, AvatarProps>(
  ({ className, presence, presenceSize = 'md', children, ...props }, ref) => {
    const presenceDotSizes = {
      sm: 'w-2 h-2 border',
      md: 'w-2.5 h-2.5 border-2',
      lg: 'w-3.5 h-3.5 border-2',
    };

    return (
      <div className="relative inline-block">
        <AvatarPrimitive.Root
          ref={ref}
          className={cn('relative flex h-10 w-10 shrink-0 overflow-hidden rounded-pill border border-border bg-elevated', className)}
          {...props}
        >
          {children}
        </AvatarPrimitive.Root>
        {presence && (
          <span
            aria-label={`الحالة: ${presence}`}
            className={cn(
              'absolute bottom-0 start-0 rounded-full border-base',
              presenceDotSizes[presenceSize],
              presence === 'online' && 'bg-status-success',
              presence === 'offline' && 'bg-zinc-500',
              presence === 'away' && 'bg-status-warning'
            )}
          />
        )}
      </div>
    );
  }
);
Avatar.displayName = AvatarPrimitive.Root.displayName;

export const AvatarImage = React.forwardRef<
  React.ElementRef<typeof AvatarPrimitive.Image>,
  React.ComponentPropsWithoutRef<typeof AvatarPrimitive.Image>
>(({ className, ...props }, ref) => (
  <AvatarPrimitive.Image ref={ref} className={cn('aspect-square h-full w-full object-cover', className)} {...props} />
));
AvatarImage.displayName = AvatarPrimitive.Image.displayName;

export const AvatarFallback = React.forwardRef<
  React.ElementRef<typeof AvatarPrimitive.Fallback>,
  React.ComponentPropsWithoutRef<typeof AvatarPrimitive.Fallback>
>(({ className, ...props }, ref) => (
  <AvatarPrimitive.Fallback
    ref={ref}
    className={cn('flex h-full w-full items-center justify-center rounded-pill font-bold text-xs text-text-main bg-elevated', className)}
    {...props}
  />
));
AvatarFallback.displayName = AvatarPrimitive.Fallback.displayName;
