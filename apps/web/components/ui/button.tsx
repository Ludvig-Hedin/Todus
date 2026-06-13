import { cva, type VariantProps } from 'class-variance-authority';
import { Loader2 } from 'lucide-react';
import { Slot } from 'radix-ui';
import * as React from 'react';

import { cn } from '@/lib/utils';

const buttonVariants = cva(
  'inline-flex items-center justify-center cursor-pointer gap-2 whitespace-nowrap rounded-full text-[13px] font-medium ring-offset-background transition-colors duration-(--motion-duration-fast) ease-(--motion-easing-standard) focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:pointer-events-none disabled:opacity-50 aria-disabled:opacity-50 [&_svg]:pointer-events-none [&_svg]:size-4 [&_svg]:shrink-0 aria-busy:cursor-progress',
  {
    variants: {
      variant: {
        default: 'bg-primary text-primary-foreground hover:bg-primary/90',
        destructive: 'bg-logout text-destructive-foreground hover:bg-logout/90',
        // Outline mirrors the iOS / macOS outline aesthetic: transparent fill,
        // visible border, fill-on-hover only. Previous `bg-background` made the
        // button read as a filled chip on top of card surfaces, which drifted
        // from the native platforms (audit DESIGN_SYSTEM_INCONSISTENCIES.md).
        outline:
          'border border-input bg-transparent hover:bg-accent hover:text-accent-foreground',
        secondary: 'bg-secondary text-secondary-foreground hover:bg-secondary/80',
        ghost: 'hover:bg-accent hover:text-accent-foreground',
        link: 'text-primary underline-offset-4 hover:underline',
        main: 'bg-muted text-primary',
        // Liquid Glass — sister of iOS `LiquidGlassButtonStyle`. Backdrop blur,
        // hairline white highlight, soft layered shadow, press = scale 0.97 +
        // brief brightness lift. Default radius uses `--radius-md` (14px) so
        // the corner matches iOS `Radius.control`.
        glass:
          'rounded-(--radius-md) border border-white/20 bg-white/10 text-foreground shadow-[0_1px_2px_rgba(0,0,0,0.04),_0_8px_24px_-12px_rgba(0,0,0,0.12)] backdrop-blur-xl backdrop-saturate-150 transition-[background-color,transform,filter] duration-(--motion-duration-fast) ease-(--motion-easing-standard) hover:bg-white/15 active:scale-[0.97] active:brightness-110 dark:border-white/10 dark:bg-white/5 dark:hover:bg-white/[0.08]',
        // A button that resembles a dropdownItem
        dropdownItem:
          'select-none gap-2 rounded-sm text-sm outline-none transition-colors focus:bg-accent focus:text-accent-foreground hover:bg-accent',
      },
      size: {
        dropdownItem: 'px-2 py-1.5',
        default: 'h-10 px-4 py-2',
        sm: 'h-9 px-3',
        xs: 'h-8 px-2',
        lg: 'h-11 px-8',
        icon: 'h-10 w-10',
      },
    },
    defaultVariants: {
      variant: 'default',
      size: 'default',
    },
  },
);

export interface ButtonProps
  extends React.ButtonHTMLAttributes<HTMLButtonElement>,
    VariantProps<typeof buttonVariants> {
  asChild?: boolean;
  isLoading?: boolean;
  loadingText?: string;
}

const Button = React.forwardRef<HTMLButtonElement, ButtonProps>(
  (
    {
      className,
      variant,
      size,
      asChild = false,
      isLoading = false,
      loadingText,
      children,
      disabled,
      ...props
    },
    ref,
  ) => {
    const Comp = asChild ? Slot.Slot : 'button';
    const effectiveDisabled = isLoading || disabled;
    // Radix `Slot` runs `React.Children.only` on its child. When `asChild` is
    // true we cannot wrap the spinner + children in a Fragment, so the loading
    // affordance is suppressed for slotted children. Callers needing a loading
    // state should pass a single child (e.g. `<Button asChild><Link>…</Link></Button>`)
    // and skip `isLoading`, or use a non-`asChild` button.
    // Use Vite's `import.meta.env.DEV` (statically replaced at build time
    // and tree-shaken from prod) instead of `process.env.NODE_ENV` —
    // `process` isn't always polyfilled in the Cloudflare Workers SSR
    // runtime and would crash with `ReferenceError: process is not defined`.
    if (import.meta.env.DEV && isLoading && asChild) {
      // eslint-disable-next-line no-console
      console.warn(
        'Button: `isLoading` is suppressed when `asChild` is true (Radix Slot requires a single child). ' +
          'Render a non-asChild Button or remove `isLoading`.',
      );
    }
    const showSpinner = isLoading && !asChild;
    // `disabled` is not a valid HTML attribute on `<a>` / `<Link>`. When
    // `asChild` is true the Slot forwards `disabled` to whatever element the
    // child renders, which would leave a loading or disabled link clickable
    // while emitting an invalid DOM attribute warning in React 19+. Skip
    // disabled forwarding in slot mode and rely on `pointer-events-none`
    // + `aria-disabled` to gate interaction — otherwise a screen reader
    // announces the link as disabled while it stays clickable.
    const slotDisabledClass = asChild && effectiveDisabled ? 'pointer-events-none' : '';
    // Per-attribute merge — preserves caller intent for unrelated attrs
    // (e.g. `tabIndex={0}` on a non-disabled `asChild`) while keeping
    // internal invariants (loading lock, busy announcement) override-proof.
    //
    // - `disabled`: always reflect internal state on native `<button>`.
    //   `disabled` was already destructured out of `props` above, so we
    //   don't need to filter it from the spread.
    // - `aria-busy`: only when loading; caller's value is preserved otherwise.
    // - `aria-disabled`: only in `asChild` mode (native `<button>`'s
    //   `disabled` attribute already conveys the state to assistive tech;
    //   adding `aria-disabled` on top confuses some screen readers).
    // - `tabIndex`: respect caller's value if provided; fall back to `-1`
    //   in `asChild` + disabled (a slotted `<a>` has no native disabled
    //   semantics so removing it from the tab order is the only honest
    //   default).
    // - keyboard intercept: a focused slotted `<a>` would still activate
    //   on Enter despite `pointer-events-none`. Capture-phase handlers
    //   block click + Enter / Space activation when slot mode is disabled.
    const extras: Record<string, unknown> = {};
    if (!asChild) extras.disabled = effectiveDisabled || undefined;
    if (isLoading) extras['aria-busy'] = true;
    // When `loadingText` is an empty string the caller wants a spinner-only
    // button. `Loader2` is `aria-hidden`, so screen readers would announce
    // nothing — fall back to `aria-label="Loading"` (unless the caller
    // already supplied one) so the busy state has a name.
    if (showSpinner && loadingText === '' && props['aria-label'] === undefined) {
      extras['aria-label'] = 'Loading';
    }
    if (asChild && effectiveDisabled) {
      extras['aria-disabled'] = true;
      if (props.tabIndex === undefined) {
        extras.tabIndex = -1;
      }
      const blockActivation = (event: React.SyntheticEvent) => {
        event.preventDefault();
        event.stopPropagation();
      };
      extras.onClickCapture = blockActivation;
      extras.onKeyDownCapture = (event: React.KeyboardEvent) => {
        if (event.key === 'Enter' || event.key === ' ') {
          event.preventDefault();
          event.stopPropagation();
        }
      };
    }
    return (
      <Comp
        className={cn(buttonVariants({ variant, size }), slotDisabledClass, className)}
        ref={ref}
        {...props}
        {...extras}
      >
        {showSpinner ? (
          <>
            {/* No `mr-2` — base `gap-2` on the button already spaces icon + text. */}
            <Loader2 className="h-4 w-4 animate-spin" aria-hidden />
            {/* `??` (not `||`) so a caller can intentionally pass `""` to hide
                text during loading and show only the spinner. */}
            {loadingText ?? children}
          </>
        ) : (
          children
        )}
      </Comp>
    );
  },
);
Button.displayName = 'Button';

export { Button, buttonVariants };
