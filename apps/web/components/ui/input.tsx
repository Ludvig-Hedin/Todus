import * as React from 'react';

import { cn } from '@/lib/utils';

const Input = React.forwardRef<HTMLInputElement, React.ComponentProps<'input'>>(
  ({ className, type, ...props }, ref) => {
    return (
      <input
        type={type}
        className={cn(
          // text-[13px] is intentional — matches the app's design system (button.tsx uses the same size).
          // Professional mail UIs typically use compact font sizes; this is above the 12px WCAG minimum.
          'border-input bg-background file:text-foreground placeholder:text-muted-foreground flex h-9 w-full rounded-lg border px-3 py-2 text-[13px] file:border-0 file:bg-transparent file:text-sm file:font-medium focus-visible:outline-none focus-visible:border-foreground/30 disabled:cursor-not-allowed disabled:opacity-50 transition-colors duration-(--motion-duration-fast) ease-(--motion-easing-standard)',
          className,
        )}
        ref={ref}
        {...props}
      />
    );
  },
);
Input.displayName = 'Input';

export { Input };
