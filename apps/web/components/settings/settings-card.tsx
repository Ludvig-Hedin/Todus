import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import type { ReactNode, HTMLAttributes } from 'react';
import { PricingDialog } from '../ui/pricing-dialog';
import { cn } from '@/lib/utils';

interface SettingsCardProps extends HTMLAttributes<HTMLDivElement> {
  title: string;
  description?: string;
  children: ReactNode;
  footer?: ReactNode;
  action?: ReactNode;
}

export function SettingsCard({
  title,
  description,
  children,
  footer,
  action,
  className,
}: SettingsCardProps) {
  return (
    <Card
      className={cn(
        'w-full border-none bg-transparent px-0 pb-0 shadow-none',
        className,
      )}
    >
      <CardHeader className="flex flex-row items-start justify-between gap-3 px-0 pb-2 pt-0">
        <div className="space-y-0.5">
          <CardTitle className="text-sm font-semibold">{title}</CardTitle>
          {description && (
            <CardDescription className="text-muted-foreground text-xs">{description}</CardDescription>
          )}
        </div>
        {action && <div>{action}</div>}
      </CardHeader>
      <CardContent className="space-y-3 px-0">{children}</CardContent>
      {footer && <div className="border-border/60 mt-3 border-t pt-3">{footer}</div>}
      <PricingDialog />
    </Card>
  );
}
