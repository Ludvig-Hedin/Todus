import { Copy, Check } from 'lucide-react';
import { useEffect, useRef, useState } from 'react';

interface CopyableTextCardProps {
  props: {
    label: string;
    content: string;
  };
  emit?: (event: string, params?: Record<string, unknown>) => void;
}

export function CopyableTextCard({ props, emit }: CopyableTextCardProps) {
  const [copied, setCopied] = useState(false);
  const copyTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    return () => {
      if (copyTimeoutRef.current != null) clearTimeout(copyTimeoutRef.current);
    };
  }, []);

  const handleCopy = () => {
    if (emit) {
      // Registry's copy_text action already writes to navigator.clipboard, so we let it
      // handle the actual write to keep one code path. Falls back to writing locally if
      // emit is not wired up (component used standalone).
      emit('press', { action: 'copy_text', content: props.content });
    } else if (typeof navigator !== 'undefined' && navigator.clipboard) {
      void navigator.clipboard.writeText(props.content);
    }
    setCopied(true);
    if (copyTimeoutRef.current != null) clearTimeout(copyTimeoutRef.current);
    copyTimeoutRef.current = setTimeout(() => {
      copyTimeoutRef.current = null;
      setCopied(false);
    }, 1500);
  };

  return (
    <div className="overflow-hidden rounded-xl border border-[#E7E7E7] dark:border-[#252525]">
      <div className="flex items-center justify-between bg-[#F6F6F7] px-3 py-2 dark:bg-[#1C1C1E]">
        <span className="text-xs text-[#8C8C8C]">{props.label}</span>
        <button
          onClick={handleCopy}
          className="inline-flex items-center gap-1.5 text-xs font-medium text-black hover:opacity-70 dark:text-white"
        >
          {copied ? <Check className="h-3 w-3" /> : <Copy className="h-3 w-3" />}
          {copied ? 'Copied' : 'Copy'}
        </button>
      </div>
      <div className="max-h-[280px] overflow-auto px-3 py-3">
        <p className="text-sm whitespace-pre-wrap break-words text-black dark:text-white">{props.content}</p>
      </div>
    </div>
  );
}
