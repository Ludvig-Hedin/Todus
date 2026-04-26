import { Copy, Check } from 'lucide-react';
import { useEffect, useRef, useState } from 'react';

interface CodeBlockCardProps {
  props: {
    language: string;
    code: string;
    filename: string | null;
  };
  emit?: (event: string, params?: Record<string, unknown>) => void;
}

export function CodeBlockCard({ props, emit }: CodeBlockCardProps) {
  const [copied, setCopied] = useState(false);
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => () => { if (timerRef.current) clearTimeout(timerRef.current); }, []);

  const handleCopy = () => {
    if (typeof navigator !== 'undefined' && navigator.clipboard) {
      void navigator.clipboard.writeText(props.code);
    }
    emit?.('press', { action: 'copy_text', content: props.code });
    setCopied(true);
    if (timerRef.current) clearTimeout(timerRef.current);
    timerRef.current = setTimeout(() => setCopied(false), 1500);
  };

  return (
    <div className="overflow-hidden rounded-xl border border-[#E7E7E7] dark:border-[#252525]">
      <div className="flex items-center justify-between bg-[#F6F6F7] px-3 py-2 dark:bg-[#1C1C1E]">
        <div className="flex items-center gap-2">
          <span className="rounded-sm bg-white px-1.5 py-0.5 text-[10px] font-medium text-[#555] dark:bg-[#252525] dark:text-[#929292]">
            {props.language || 'text'}
          </span>
          {props.filename && (
            <span className="text-xs text-[#8C8C8C]">{props.filename}</span>
          )}
        </div>
        <button
          type="button"
          onClick={handleCopy}
          className="inline-flex items-center gap-1.5 text-xs font-medium text-black hover:opacity-70 dark:text-white"
        >
          {copied ? <Check className="h-3 w-3" /> : <Copy className="h-3 w-3" />}
          {copied ? 'Copied' : 'Copy'}
        </button>
      </div>
      <pre className="max-h-[320px] overflow-auto bg-white px-3 py-3 text-xs leading-relaxed text-black dark:bg-[#1C1C1E] dark:text-white">
        <code className="font-mono whitespace-pre">{props.code}</code>
      </pre>
    </div>
  );
}
