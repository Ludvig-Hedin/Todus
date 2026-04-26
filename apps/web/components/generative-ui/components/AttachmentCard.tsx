import { File, FileText, Image as ImageIcon, FileArchive, FileVideo, FileAudio, Download } from 'lucide-react';

interface AttachmentCardProps {
  props: {
    name: string;
    size: number;
    mimeType: string;
    previewUrl: string | null;
    downloadAction: string | null;
    downloadParams: Record<string, string> | null;
  };
  emit?: (event: string, params?: Record<string, unknown>) => void;
}

function formatBytes(bytes: number): string {
  if (!Number.isFinite(bytes) || bytes <= 0) return '';
  const units = ['B', 'KB', 'MB', 'GB'];
  let i = 0;
  let n = bytes;
  while (n >= 1024 && i < units.length - 1) {
    n /= 1024;
    i++;
  }
  return `${n.toFixed(n < 10 && i > 0 ? 1 : 0)} ${units[i]}`;
}

function iconFor(mime: string) {
  if (mime.startsWith('image/')) return ImageIcon;
  if (mime.startsWith('video/')) return FileVideo;
  if (mime.startsWith('audio/')) return FileAudio;
  if (mime === 'application/pdf' || mime.startsWith('text/')) return FileText;
  if (mime.includes('zip') || mime.includes('compressed')) return FileArchive;
  return File;
}

export function AttachmentCard({ props, emit }: AttachmentCardProps) {
  const Icon = iconFor(props.mimeType);
  const handleClick = () => {
    const action = props.downloadAction ?? 'open_attachment';
    emit?.('press', {
      action,
      name: props.name,
      mimeType: props.mimeType,
      ...(props.previewUrl ? { previewUrl: props.previewUrl } : {}),
      downloadParams: props.downloadParams ?? undefined,
    });
  };

  const isImage = props.mimeType.startsWith('image/') && props.previewUrl;

  return (
    <button
      type="button"
      onClick={handleClick}
      className="flex w-full items-center gap-3 rounded-xl border border-[#E7E7E7] bg-white p-2.5 text-left transition-colors hover:bg-[#F6F6F7] dark:border-[#252525] dark:bg-[#1C1C1E] dark:hover:bg-[#252525]"
    >
      {isImage ? (
        <img
          src={props.previewUrl ?? ''}
          alt={props.name}
          className="h-10 w-10 shrink-0 rounded-md object-cover"
        />
      ) : (
        <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-md bg-[#F6F6F7] text-[#8C8C8C] dark:bg-[#252525]">
          <Icon className="h-4 w-4" />
        </div>
      )}
      <div className="min-w-0 flex-1">
        <p className="truncate text-sm font-medium text-black dark:text-white">{props.name}</p>
        <p className="text-xs text-[#8C8C8C]">
          {formatBytes(props.size)}
          {props.mimeType ? ` · ${props.mimeType.split('/')[1] ?? props.mimeType}` : ''}
        </p>
      </div>
      <Download className="h-4 w-4 shrink-0 text-[#8C8C8C]" />
    </button>
  );
}
