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
        'bg-transparent w-full border-none px-0 shadow-none',
        className,
      )}
    >
      <CardHeader className="flex flex-row items-start justify-between px-0 pt-0">
        <div className="space-y-1">
          <CardTitle className="text-base">{title}</CardTitle>
          {description && <CardDescription className="text-[13px]">{description}</CardDescription>}
        </div>
        {action && <div>{action}</div>}
      </CardHeader>
      <CardContent className="space-y-5 px-0">{children}</CardContent>
      {footer && <div className="border-t border-border/60 py-3.5">{footer}</div>}
      <PricingDialog />
    </Card>
  );
}
