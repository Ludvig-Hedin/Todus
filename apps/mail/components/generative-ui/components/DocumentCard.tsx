import { FileText } from 'lucide-react';
import { format, parseISO } from 'date-fns';

interface DocumentCardProps {
  props: {
    documentId: string;
    title: string;
    snippet: string | null;
    updatedAt: string | null;
    workspaceName: string | null;
  };
  emit?: (event: string, params?: Record<string, unknown>) => void;
}

export function DocumentCard({ props, emit }: DocumentCardProps) {
  const handleClick = () => {
    emit?.('press', { action: 'navigate_document', documentId: props.documentId });
  };

  const updated = (() => {
    if (!props.updatedAt) return null;
    try {
      return format(parseISO(props.updatedAt), 'MMM d');
    } catch {
      return props.updatedAt;
    }
  })();

  return (
    <button
      type="button"
      onClick={handleClick}
      className="flex w-full items-start gap-2.5 rounded-xl border border-[#E7E7E7] bg-white p-2.5 text-left transition-colors hover:bg-[#F6F6F7] dark:border-[#252525] dark:bg-[#1C1C1E] dark:hover:bg-[#252525]"
    >
      <div className="mt-0.5 flex h-7 w-7 shrink-0 items-center justify-center rounded-md bg-[#F6F6F7] text-[#8C8C8C] dark:bg-[#252525]">
        <FileText className="h-3.5 w-3.5" />
      </div>
      <div className="min-w-0 flex-1">
        <div className="flex items-center justify-between gap-2">
          <p className="truncate text-sm font-medium text-black dark:text-white">{props.title}</p>
          {updated && <span className="shrink-0 text-xs text-[#8C8C8C]">{updated}</span>}
        </div>
        {props.snippet && (
          <p className="line-clamp-2 text-xs text-[#8C8C8C]">{props.snippet}</p>
        )}
        {props.workspaceName && (
          <p className="mt-1 text-[10px] text-[#8C8C8C]">{props.workspaceName}</p>
        )}
      </div>
    </button>
  );
}
