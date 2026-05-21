/**
 * Shared layout primitives for settings pages.
 *
 * Visual model:
 *   - Section: vertical-spaced group with title + optional description/action
 *   - Subheader: small uppercase divider inside a Section
 *   - RowList: single bordered container with internal hairline dividers
 *   - ToggleRow / SelectRow: list-row controls used inside RowList
 *   - Field: stacked label / control / helper text used outside RowList
 *
 * Each page composes these instead of nesting cards. Consistent spacing
 * (space-y-2 for label/control, space-y-3 inside Section, space-y-10 between
 * Sections) keeps every settings surface readable + tight.
 */
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Switch } from '@/components/ui/switch';
import { cn } from '@/lib/utils';
import type { ReactNode } from 'react';
import { Children } from 'react';

export function Section({
  title,
  description,
  action,
  children,
  className,
}: {
  title: string;
  description?: ReactNode;
  action?: ReactNode;
  children: ReactNode;
  className?: string;
}) {
  return (
    <section className={cn('space-y-3', className)}>
      <header className="flex items-start justify-between gap-3">
        <div className="space-y-0.5">
          <h2 className="text-base font-semibold tracking-tight">{title}</h2>
          {description && (
            <p className="text-muted-foreground text-xs">{description}</p>
          )}
        </div>
        {action}
      </header>
      <div className="space-y-3">{children}</div>
    </section>
  );
}

export function Subheader({ title }: { title: string }) {
  return (
    <h3 className="text-muted-foreground mt-4 text-[11px] font-medium uppercase tracking-wider first:mt-0">
      {title}
    </h3>
  );
}

export function RowList({
  children,
  className,
}: {
  children: ReactNode;
  className?: string;
}) {
  const items = Children.toArray(children).filter(Boolean);
  return (
    <div
      className={cn(
        'border-border/60 divide-border/60 divide-y overflow-hidden rounded-lg border',
        className,
      )}
    >
      {items.map((child, i) => (
        <div key={i} className="px-3">
          {child}
        </div>
      ))}
    </div>
  );
}

export function ToggleRow({
  label,
  description,
  checked,
  onChange,
  disabled,
}: {
  label: string;
  description?: ReactNode;
  checked: boolean;
  onChange: (next: boolean) => void;
  disabled?: boolean;
}) {
  return (
    <div className="flex items-center justify-between gap-4 py-2.5">
      <div className="min-w-0 flex-1">
        <p className="text-sm">{label}</p>
        {description && <p className="text-muted-foreground text-xs">{description}</p>}
      </div>
      <Switch checked={checked} onCheckedChange={onChange} disabled={disabled} />
    </div>
  );
}

export function SelectRow({
  label,
  description,
  value,
  options,
  onChange,
  width = 180,
}: {
  label: string;
  description?: ReactNode;
  value: string;
  options: { value: string; label: string }[];
  onChange: (next: string) => void;
  width?: number;
}) {
  return (
    <div className="flex items-center justify-between gap-4 py-2">
      <div className="min-w-0 flex-1">
        <p className="text-sm">{label}</p>
        {description && <p className="text-muted-foreground text-xs">{description}</p>}
      </div>
      <Select value={value} onValueChange={onChange}>
        <SelectTrigger className="h-8" style={{ width }}>
          <SelectValue />
        </SelectTrigger>
        <SelectContent>
          {options.map((o) => (
            <SelectItem key={o.value} value={o.value}>
              {o.label}
            </SelectItem>
          ))}
        </SelectContent>
      </Select>
    </div>
  );
}

export function Field({
  label,
  description,
  children,
  className,
}: {
  label: string;
  description?: ReactNode;
  children: ReactNode;
  className?: string;
}) {
  return (
    <div className={cn('space-y-2', className)}>
      <label className="text-sm font-medium">{label}</label>
      {children}
      {description && <p className="text-muted-foreground text-xs">{description}</p>}
    </div>
  );
}
