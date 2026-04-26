interface QuoteCardProps {
  props: {
    quote: string;
    sourceLabel: string | null;
    sourceAction: string | null;
    sourceParams: Record<string, string> | null;
  };
  emit?: (event: string, params?: Record<string, unknown>) => void;
}

export function QuoteCard({ props, emit }: QuoteCardProps) {
  const handleSourceClick = () => {
    if (!props.sourceAction) return;
    emit?.('press', { action: props.sourceAction, ...(props.sourceParams ?? {}) });
  };

  return (
    <div className="flex gap-3 rounded-xl border border-[#E7E7E7] bg-white px-3 py-2.5 dark:border-[#252525] dark:bg-[#1C1C1E]">
      <div className="w-0.5 shrink-0 rounded-full bg-[#437DFB]" />
      <div className="flex flex-1 flex-col gap-1">
        <p className="text-sm italic text-black dark:text-white">{props.quote}</p>
        {props.sourceLabel && (
          <button
            onClick={handleSourceClick}
            disabled={!props.sourceAction}
            className="text-left text-xs text-[#8C8C8C] enabled:hover:text-black enabled:hover:underline dark:enabled:hover:text-white"
          >
            — {props.sourceLabel}
          </button>
        )}
      </div>
    </div>
  );
}
