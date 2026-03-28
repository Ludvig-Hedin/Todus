/**
 * Layout and utility components for the generative UI system.
 * These are used by the AI to compose card layouts in chat.
 */

import { cn } from '@/lib/utils';

// ─── Stack ──────────────────────────────────────────────────────

interface StackProps {
  props: {
    direction: 'vertical' | 'horizontal';
    gap: 'none' | 'sm' | 'md' | 'lg' | null;
    align: 'start' | 'center' | 'end' | 'stretch' | null;
  };
  children?: React.ReactNode;
}

const gapClasses: Record<string, string> = {
  none: 'gap-0',
  sm: 'gap-1',
  md: 'gap-2',
  lg: 'gap-4',
};

const alignClasses: Record<string, string> = {
  start: 'items-start',
  center: 'items-center',
  end: 'items-end',
  stretch: 'items-stretch',
};

export function StackComponent({ props, children }: StackProps) {
  return (
    <div
      className={cn(
        'flex',
        props.direction === 'vertical' ? 'flex-col' : 'flex-row',
        gapClasses[props.gap ?? 'md'],
        alignClasses[props.align ?? 'stretch'],
      )}
    >
      {children}
    </div>
  );
}

// ─── Card ──────────────────────────────────────────────────────

interface CardComponentProps {
  props: {
    title: string | null;
    description: string | null;
    padding: 'none' | 'sm' | 'md' | 'lg' | null;
  };
  children?: React.ReactNode;
}

const paddingClasses: Record<string, string> = {
  none: 'p-0',
  sm: 'p-2',
  md: 'p-3',
  lg: 'p-4',
};

export function CardComponent({ props, children }: CardComponentProps) {
  return (
    <div
      className={cn(
        'rounded-lg border border-[#E7E7E7] dark:border-[#252525]',
        paddingClasses[props.padding ?? 'md'],
      )}
    >
      {props.title && (
        <p className="mb-1 text-sm font-medium text-black dark:text-white">{props.title}</p>
      )}
      {props.description && (
        <p className="mb-2 text-xs text-[#8C8C8C]">{props.description}</p>
      )}
      {children}
    </div>
  );
}

// ─── Text ──────────────────────────────────────────────────────

interface TextComponentProps {
  props: {
    content: string;
    variant: 'heading' | 'subheading' | 'body' | 'caption' | 'code' | null;
  };
}

const textVariantClasses: Record<string, string> = {
  heading: 'text-base font-semibold text-black dark:text-white',
  subheading: 'text-sm font-medium text-black dark:text-white',
  body: 'text-sm text-black dark:text-white',
  caption: 'text-xs text-[#8C8C8C]',
  code: 'text-xs font-mono bg-[#f0f0f0] dark:bg-[#252525] px-1.5 py-0.5 rounded',
};

export function TextComponent({ props }: TextComponentProps) {
  const variant = props.variant ?? 'body';
  return <span className={textVariantClasses[variant]}>{props.content}</span>;
}

// ─── Button ────────────────────────────────────────────────────

interface ButtonComponentProps {
  props: {
    label: string;
    action: string;
    actionParams: Record<string, string> | null;
    variant: 'default' | 'outline' | 'ghost' | 'destructive' | null;
  };
  emit?: (event: string, params?: Record<string, unknown>) => void;
}

const buttonVariantClasses: Record<string, string> = {
  default:
    'bg-[#262626] text-white hover:bg-[#333] dark:bg-white dark:text-black dark:hover:bg-[#e0e0e0]',
  outline:
    'border border-[#E7E7E7] dark:border-[#333] text-black dark:text-white hover:bg-[#f0f0f0] dark:hover:bg-[#252525]',
  ghost: 'text-black dark:text-white hover:bg-[#f0f0f0] dark:hover:bg-[#252525]',
  destructive: 'bg-red-500 text-white hover:bg-red-600',
};

export function ButtonComponent({ props, emit }: ButtonComponentProps) {
  const handleClick = () => {
    emit?.('press', { action: props.action, ...(props.actionParams ?? {}) });
  };

  return (
    <button
      onClick={handleClick}
      className={cn(
        'inline-flex items-center justify-center rounded-md px-3 py-1.5 text-xs font-medium transition-colors',
        buttonVariantClasses[props.variant ?? 'default'],
      )}
    >
      {props.label}
    </button>
  );
}

// ─── Badge ─────────────────────────────────────────────────────

interface BadgeComponentProps {
  props: {
    label: string;
    variant: 'default' | 'success' | 'warning' | 'destructive' | 'outline' | null;
  };
}

const badgeVariantClasses: Record<string, string> = {
  default: 'bg-[#f0f0f0] text-[#555] dark:bg-[#252525] dark:text-[#929292]',
  success: 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400',
  warning: 'bg-orange-100 text-orange-700 dark:bg-orange-900/30 dark:text-orange-400',
  destructive: 'bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-400',
  outline: 'border border-[#E7E7E7] dark:border-[#333] text-[#555] dark:text-[#929292]',
};

export function BadgeComponent({ props }: BadgeComponentProps) {
  return (
    <span
      className={cn(
        'inline-flex items-center rounded-full px-2 py-0.5 text-[10px] font-medium',
        badgeVariantClasses[props.variant ?? 'default'],
      )}
    >
      {props.label}
    </span>
  );
}

// ─── Divider ───────────────────────────────────────────────────

export function DividerComponent() {
  return <div className="my-1 h-px w-full bg-[#E7E7E7] dark:bg-[#252525]" />;
}
