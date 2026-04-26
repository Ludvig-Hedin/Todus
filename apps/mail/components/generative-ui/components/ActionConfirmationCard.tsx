import { Check, Archive, Trash2, Mail, Undo2 } from 'lucide-react';

const iconMap: Record<string, React.ComponentType<{ className?: string }>> = {
  check: Check,
  archive: Archive,
  trash: Trash2,
  mail: Mail,
};

interface ActionConfirmationCardProps {
  props: {
    icon: string | null;
    message: string;
    undoAction: string | null;
    /** JSON string of params for the undo action (catalog / runtime use string, not a nested object). */
    undoParams: string | null;
  };
  emit?: (event: string, params?: Record<string, unknown>) => void;
}

export function ActionConfirmationCard({ props, emit }: ActionConfirmationCardProps) {
  const Icon = iconMap[props.icon ?? 'check'] ?? Check;

  const handleUndo = () => {
    if (!props.undoAction) return;
    const raw = props.undoParams?.trim();
    emit?.('press', {
      action: 'undo',
      undoAction: props.undoAction,
      undoParams: raw && raw.length > 0 ? raw : '{}',
    });
  };

  return (
    <div className="flex items-center justify-between rounded-xl border border-[#E7E7E7] bg-white px-3 py-2.5 dark:border-[#252525] dark:bg-[#1C1C1E]">
      <div className="flex items-center gap-2.5">
        <div className="flex h-7 w-7 items-center justify-center rounded-full bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400">
          <Icon className="h-3.5 w-3.5" />
        </div>
        <p className="text-sm text-black dark:text-white">{props.message}</p>
      </div>
      {props.undoAction && (
        <button
          type="button"
          onClick={handleUndo}
          className="inline-flex items-center gap-1 rounded-md text-xs font-medium text-[#437DFB] hover:opacity-70 focus:outline-none focus:ring-2 focus:ring-[#437DFB]/40 focus:ring-offset-1 focus:ring-offset-white dark:focus:ring-offset-[#1C1C1E]"
        >
          <Undo2 className="h-3 w-3" />
          Undo
        </button>
      )}
    </div>
  );
}
