import { ArrowDown, ArrowUp, Minus } from 'lucide-react';

interface MetricCardProps {
  props: {
    label: string;
    value: string;
    delta: string | null;
    deltaDirection: 'up' | 'down' | 'neutral' | null;
    helpText: string | null;
  };
}

const directionStyle: Record<NonNullable<MetricCardProps['props']['deltaDirection']>, string> = {
  up: 'text-green-600 dark:text-green-400',
  down: 'text-red-600 dark:text-red-400',
  neutral: 'text-[#8C8C8C]',
};

export function MetricCard({ props }: MetricCardProps) {
  const dir = props.deltaDirection ?? 'neutral';
  const Icon = dir === 'up' ? ArrowUp : dir === 'down' ? ArrowDown : Minus;
  return (
    <div className="rounded-xl border border-[#E7E7E7] bg-white p-3 dark:border-[#252525] dark:bg-[#1C1C1E]">
      <p className="text-xs text-[#8C8C8C]">{props.label}</p>
      <div className="mt-1 flex items-baseline gap-2">
        <span className="text-2xl font-semibold tabular-nums text-black dark:text-white">{props.value}</span>
        {props.delta && (
          <span className={`inline-flex items-center gap-0.5 text-xs font-medium ${directionStyle[dir]}`}>
            <Icon className="h-3 w-3" />
            {props.delta}
          </span>
        )}
      </div>
      {props.helpText && <p className="mt-1 text-xs text-[#8C8C8C]">{props.helpText}</p>}
    </div>
  );
}
