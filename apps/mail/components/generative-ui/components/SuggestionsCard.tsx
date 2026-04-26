interface Suggestion {
  label: string;
  action: string;
  params: Record<string, string> | null;
}

interface SuggestionsCardProps {
  props: {
    suggestions: Suggestion[];
  };
  emit?: (event: string, params?: Record<string, unknown>) => void;
}

export function SuggestionsCard({ props, emit }: SuggestionsCardProps) {
  const handleClick = (suggestion: Suggestion) => {
    emit?.('press', { action: suggestion.action, ...(suggestion.params ?? {}) });
  };

  return (
    <div className="flex flex-wrap gap-1.5">
      {props.suggestions.map((suggestion, index) => (
        <button
          key={`${suggestion.action}-${suggestion.label}-${index}`}
          onClick={() => handleClick(suggestion)}
          className="inline-flex items-center rounded-full border border-[#E7E7E7] bg-white px-3 py-1.5 text-xs font-medium text-black transition-colors hover:bg-[#F6F6F7] dark:border-[#252525] dark:bg-[#1C1C1E] dark:text-white dark:hover:bg-[#252525]"
        >
          {suggestion.label}
        </button>
      ))}
    </div>
  );
}
