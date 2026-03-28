import { Search } from 'lucide-react';

interface SearchResultCardProps {
  props: {
    query: string;
    resultCount: number;
    summary: string | null;
  };
}

export function SearchResultCard({ props }: SearchResultCardProps) {
  return (
    <div className="rounded-lg bg-[#f0f0f0] p-3 dark:bg-[#252525]">
      <div className="flex items-center gap-2">
        <Search className="h-4 w-4 text-[#8C8C8C]" />
        <p className="text-sm text-black dark:text-white">
          Found {props.resultCount} result{props.resultCount !== 1 ? 's' : ''} for &ldquo;
          {props.query}&rdquo;
        </p>
      </div>
      {props.summary && <p className="mt-1 text-xs text-[#8C8C8C]">{props.summary}</p>}
    </div>
  );
}
