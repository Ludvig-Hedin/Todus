import { Tag } from 'lucide-react';

interface LabelCardProps {
  props: {
    labelId: string;
    name: string;
    color: string | null;
    count: number | null;
  };
}

export function LabelCard({ props }: LabelCardProps) {
  return (
    <div className="flex items-center gap-2 rounded-lg p-2">
      <div
        className="flex h-6 w-6 items-center justify-center rounded"
        style={{ backgroundColor: props.color ?? '#E7E7E7' }}
      >
        <Tag className="h-3.5 w-3.5" style={{ color: props.color ? '#fff' : '#555' }} />
      </div>
      <span className="text-sm text-black dark:text-white">{props.name}</span>
      {props.count != null && (
        <span className="ml-auto text-xs text-[#8C8C8C]">{props.count}</span>
      )}
    </div>
  );
}
