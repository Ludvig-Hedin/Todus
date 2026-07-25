/**
 * Folder contents strip — parity with iOS `FolderDetailView` / macOS
 * `MacFolderDetailView`, where a folder holds more than tasks: saved emails,
 * calendar events, docs, and AI chats filed into it.
 *
 * The tasks list below already renders the folder's tasks, so this panel shows
 * only the non-task members (`folders.listContents` minus `task`) and lets the
 * user open or unfile each one.
 */
import { Calendar, FileText, Loader2, Mail, MessageSquare, X } from 'lucide-react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useTRPC } from '@/providers/query-provider';
import { Link } from 'react-router';
import { toast } from 'sonner';

/** Types that live in `folder_item` and can therefore be removed by id. */
const REMOVABLE_TYPES = ['email', 'event', 'doc'] as const;
type RemovableType = (typeof REMOVABLE_TYPES)[number];

const ICONS = {
  chat: MessageSquare,
  email: Mail,
  event: Calendar,
  doc: FileText,
} as const;

const isRemovable = (type: string): type is RemovableType =>
  (REMOVABLE_TYPES as readonly string[]).includes(type);

/** Where each member type opens. Emails deep-link into the inbox thread view. */
function hrefFor(type: string, id: string): string | null {
  switch (type) {
    case 'email':
      return `/mail/inbox?threadId=${encodeURIComponent(id)}`;
    case 'event':
      return '/mail/calendar';
    case 'doc':
      return `/mail/docs/${encodeURIComponent(id)}`;
    case 'chat':
      return '/mail/chat';
    default:
      return null;
  }
}

export function FolderContents({ folderId }: { folderId: string }) {
  const trpc = useTRPC();
  const queryClient = useQueryClient();

  const { data, isLoading } = useQuery(
    trpc.folders.listContents.queryOptions(
      { folderId, types: ['chat', 'email', 'event', 'doc'], limit: 50 },
      { staleTime: 1000 * 60 },
    ),
  );

  const removeItem = useMutation({
    ...trpc.folders.removeItem.mutationOptions(),
    onSuccess: () => {
      void queryClient.invalidateQueries(trpc.folders.listContents.queryFilter({ folderId }));
      // The folder pill count comes from `folders.summary`, which counts this
      // item too — without this it keeps showing the pre-removal number.
      void queryClient.invalidateQueries(trpc.folders.summary.queryFilter());
    },
    onError: (error) => {
      console.error('Failed to remove folder item:', error);
      toast.error('Could not remove that item');
    },
  });

  const items = data?.items ?? [];

  // Nothing saved yet is the common case — stay out of the way entirely rather
  // than showing an empty shell above the task list.
  if (!isLoading && items.length === 0) return null;

  return (
    <div className="shrink-0 border-b px-5 py-2">
      <div className="text-muted-foreground mb-1.5 text-[11px] font-medium uppercase tracking-wide">
        Saved to this folder
      </div>
      {isLoading ? (
        <div className="text-muted-foreground flex items-center gap-2 py-1 text-xs">
          <Loader2 className="h-3 w-3 animate-spin" /> Loading…
        </div>
      ) : (
        <div className="scrollbar-none flex items-center gap-1.5 overflow-x-auto pb-0.5">
          {items.map((item) => {
            const Icon = ICONS[item.type as keyof typeof ICONS] ?? FileText;
            const href = hrefFor(item.type, item.id);
            const chip = (
              <span className="flex min-w-0 items-center gap-1.5">
                <Icon className="h-3 w-3 shrink-0 opacity-60" />
                <span className="max-w-[220px] truncate">{item.title}</span>
              </span>
            );

            return (
              <div
                key={`${item.type}-${item.id}`}
                className="border-border text-muted-foreground hover:text-foreground flex shrink-0 items-center gap-1 rounded-full border py-1 pl-3 pr-1.5 text-[13px]"
              >
                {href ? (
                  <Link to={href} className="min-w-0">
                    {chip}
                  </Link>
                ) : (
                  chip
                )}
                {isRemovable(item.type) && (
                  <button
                    type="button"
                    aria-label={`Remove ${item.title} from folder`}
                    disabled={removeItem.isPending}
                    onClick={() =>
                      removeItem.mutate({
                        folderId,
                        itemType: item.type as RemovableType,
                        itemId: item.id,
                      })
                    }
                    className="hover:bg-accent focus-visible:ring-ring rounded-full p-0.5 focus-visible:outline-none focus-visible:ring-1"
                  >
                    <X className="h-3 w-3" />
                  </button>
                )}
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
