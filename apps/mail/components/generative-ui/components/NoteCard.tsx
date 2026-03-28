import { Pin } from 'lucide-react';
import { cn } from '@/lib/utils';

interface NoteCardProps {
  props: {
    noteId: string;
    content: string;
    color: string | null;
    isPinned: boolean | null;
    threadId: string | null;
  };
  emit?: (event: string, params?: Record<string, unknown>) => void;
}

const noteColors: Record<string, string> = {
  default: 'bg-[#f0f0f0] dark:bg-[#252525]',
  yellow: 'bg-yellow-50 dark:bg-yellow-900/20',
  blue: 'bg-blue-50 dark:bg-blue-900/20',
  green: 'bg-green-50 dark:bg-green-900/20',
  red: 'bg-red-50 dark:bg-red-900/20',
  purple: 'bg-purple-50 dark:bg-purple-900/20',
};

export function NoteCard({ props }: NoteCardProps) {
  const colorClass = noteColors[props.color ?? 'default'] ?? noteColors.default;

  return (
    <div className={cn('rounded-lg p-3', colorClass)}>
      <div className="flex items-start justify-between gap-2">
        <p className="text-sm text-black dark:text-white">{props.content}</p>
        {props.isPinned && <Pin className="h-3 w-3 shrink-0 text-[#8C8C8C]" />}
      </div>
    </div>
  );
}
