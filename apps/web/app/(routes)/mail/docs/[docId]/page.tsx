/**
 * Doc editor page — Affine-inspired two-column layout.
 * Left: DocTree for navigation.
 * Right: Full-page title + rich text editor with auto-save.
 *
 * prosemirror.css must be imported here so the Tiptap/Novel editor renders
 * with proper rich-text styling (headings, lists, code blocks, etc.).
 */
// Editor CSS — must be imported at page level since the Editor component
// doesn't self-import it (it's shared with the compose flow).
import '@/components/create/prosemirror.css';

import { useParams, useNavigate, Link, redirect } from 'react-router';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useTRPC } from '@/providers/query-provider';
import { authProxy } from '@/lib/auth-proxy';
import type { Route } from './+types/page';
import {
  ResizablePanelGroup,
  ResizablePanel,
  ResizableHandle,
} from '@/components/ui/resizable';
import { DocTree } from '@/components/docs/doc-tree';
import Editor from '@/components/create/editor';
import { Editor as TiptapEditor } from '@tiptap/react';
import type { JSONContent } from 'novel';
import { useRef, useCallback, useState, useEffect } from 'react';
import { Button } from '@/components/ui/button';
import { Trash2 } from 'lucide-react';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { toast } from 'sonner';

// Auth guard — redirect to login if no session
export async function clientLoader({ request }: Route.ClientLoaderArgs) {
  const session = await authProxy.api.getSession({ headers: request.headers });
  if (!session) throw redirect('/login');
  return {};
}

// ─── Debounce helper with .cancel() ────────────────────────────────────────────
function debounce<T extends (...args: Parameters<T>) => void>(fn: T, delay: number) {
  let timer: ReturnType<typeof setTimeout>;
  const debounced = (...args: Parameters<T>) => {
    clearTimeout(timer);
    timer = setTimeout(() => fn(...args), delay);
  };
  debounced.cancel = () => clearTimeout(timer);
  return debounced;
}

// ─── Shared sidebar panel ──────────────────────────────────────────────────────
function SidebarPanel({
  docId,
  navigate,
}: {
  docId: string | undefined;
  navigate: (path: string) => void;
}) {
  return (
    <ResizablePanel
      defaultSize={22}
      minSize={16}
      maxSize={35}
      className="border-r"
    >
      {/* data-doc-sidebar lets native iOS / macOS shells inject CSS to hide
          this panel when they render their own sidebar above the WebView. */}
      <div data-doc-sidebar className="h-full">
        <DocTree
          selectedDocId={docId}
          onSelectDoc={(id) => navigate(`/mail/docs/${id}`)}
        />
      </div>
    </ResizablePanel>
  );
}

// ─── Main page ─────────────────────────────────────────────────────────────────
export default function DocEditorPage() {
  const { docId } = useParams<{ docId: string }>();
  const navigate = useNavigate();
  const trpc = useTRPC();
  const queryClient = useQueryClient();

  const [title, setTitle] = useState('');
  const titleInitialized = useRef(false);
  const editorRef = useRef<TiptapEditor | null>(null);

  useEffect(() => {
    return () => {
      editorRef.current = null;
    };
  }, []);

  const { data, isLoading, isError } = useQuery({
    ...trpc.docs.get.queryOptions({ id: docId! }),
    enabled: !!docId,
  });

  const doc = (data as { doc: Record<string, unknown> } | undefined)?.doc;

  // Reset on doc navigation
  useEffect(() => {
    titleInitialized.current = false;
    setTitle('');
  }, [docId]);

  // Seed title from server
  useEffect(() => {
    if (doc && !titleInitialized.current) {
      setTitle((doc as { title?: string }).title ?? '');
      titleInitialized.current = true;
    }
  }, [doc]);

  const updateDoc = useMutation({
    ...trpc.docs.update.mutationOptions(),
    onSuccess: () => {
      void queryClient.invalidateQueries(trpc.docs.get.queryFilter({ id: docId! }));
      void queryClient.invalidateQueries(trpc.docs.list.queryFilter());
    },
  });

  const [confirmDeleteOpen, setConfirmDeleteOpen] = useState(false);
  const deleteDoc = useMutation({
    ...trpc.docs.delete.mutationOptions(),
    onSuccess: () => {
      void queryClient.invalidateQueries(trpc.docs.list.queryFilter());
      setConfirmDeleteOpen(false);
      toast.success('Page deleted');
      void navigate('/mail/docs');
    },
    onError: (err) => {
      toast.error(err instanceof Error ? err.message : 'Could not delete page');
    },
  });

  const saveTitle = useCallback(
    (newTitle: string) => {
      if (!docId) return;
      // Normalize empty/whitespace-only titles to "Untitled" so the title
      // never silently disappears on other platforms (iOS does the same in
      // its native shell). Matches the backend default for new docs.
      const trimmed = newTitle.trim();
      const finalTitle = trimmed.length === 0 ? 'Untitled' : newTitle;
      const serverTitle = (doc as { title?: string } | undefined)?.title ?? '';
      if (finalTitle !== serverTitle) {
        updateDoc.mutate({ id: docId, title: finalTitle });
      }
    },
    [docId, doc, updateDoc],
  );

  // Debounced save is owned by a ref so the cleanup runs against the SAME
  // instance the previous effect installed. The earlier useCallback pattern
  // returned a new debounced fn on every `docId` change while cleanup ran
  // AFTER the new instance was already in place — the lingering timer from
  // the prior doc would later fire, read editorRef.current (now pointing at
  // the next doc's editor) and overwrite the *previous* docId's content.
  const debouncedSaveRef = useRef<ReturnType<typeof debounce> | null>(null);
  useEffect(() => {
    const fn = debounce(() => {
      if (!editorRef.current || !docId) return;
      const content: JSONContent = editorRef.current.getJSON();
      const contentText: string = editorRef.current.getText();
      updateDoc.mutate({ id: docId, content, contentText });
    }, 1000);
    debouncedSaveRef.current = fn;
    return () => {
      fn.cancel();
      if (debouncedSaveRef.current === fn) debouncedSaveRef.current = null;
    };
    // updateDoc.mutate is stable per render of the page; we deliberately
    // re-create when docId changes so the timer is scoped to one doc.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [docId]);
  // Stable callable that forwards to the current ref-held debounce.
  const debouncedSave = useCallback(() => {
    debouncedSaveRef.current?.();
  }, []);

  if (isLoading) {
    return (
      <ResizablePanelGroup direction="horizontal" className="h-full">
        <SidebarPanel docId={docId} navigate={(p) => void navigate(p)} />
        <ResizableHandle withHandle />
        <ResizablePanel className="flex flex-col">
          <div className="border-b px-12 py-8">
            <div className="bg-muted h-10 w-2/5 animate-pulse rounded-lg" />
          </div>
          <div className="space-y-3 px-12 py-6">
            <div className="bg-muted h-4 w-full animate-pulse rounded" />
            <div className="bg-muted h-4 w-4/5 animate-pulse rounded" />
            <div className="bg-muted h-4 w-3/5 animate-pulse rounded" />
          </div>
        </ResizablePanel>
      </ResizablePanelGroup>
    );
  }

  if (isError || !doc) {
    return (
      <ResizablePanelGroup direction="horizontal" className="h-full">
        <SidebarPanel docId={docId} navigate={(p) => void navigate(p)} />
        <ResizableHandle withHandle />
        <ResizablePanel className="flex flex-col items-center justify-center gap-3">
          <p className="text-foreground font-medium">Page not found</p>
          <Link to="/mail/docs" className="text-muted-foreground text-sm underline">
            Back to Docs
          </Link>
        </ResizablePanel>
      </ResizablePanelGroup>
    );
  }

  return (
    <ResizablePanelGroup direction="horizontal" className="h-full">
      <SidebarPanel docId={docId} navigate={(p) => void navigate(p)} />

      <ResizableHandle withHandle />

      {/* Editor area */}
      <ResizablePanel className="flex min-h-0 flex-col overflow-hidden">
        {/* Scrollable content area: title + editor together */}
        <div className="min-h-0 flex-1 overflow-y-auto">
          {/* Title — Affine-style large h1.
              data-doc-page-title lets native iOS / macOS shells inject CSS to
              hide this row when they render their own title TextField. */}
          <div data-doc-page-title className="flex items-start gap-2 px-12 pb-0 pt-10">
            <input
              type="text"
              value={title}
              placeholder="Untitled"
              aria-label="Document title"
              className="text-foreground w-full flex-1 rounded-md bg-transparent text-4xl font-bold tracking-tight outline-none placeholder:text-gray-300 focus-visible:ring-1 focus-visible:ring-ring dark:placeholder:text-gray-600"
              onChange={(e) => setTitle(e.target.value)}
              onBlur={() => saveTitle(title)}
              onKeyDown={(e) => {
                if (e.key === 'Enter') {
                  e.currentTarget.blur();
                }
              }}
            />
            <Button
              variant="ghost"
              size="icon"
              className="text-muted-foreground hover:text-destructive mt-1 shrink-0"
              onClick={() => setConfirmDeleteOpen(true)}
              aria-label="Delete page"
            >
              <Trash2 className="h-4 w-4" />
            </Button>
          </div>

          {/* Divider between title and body. Tagged data-doc-page-title so
              native iOS / macOS shells hide it together with the title row
              — otherwise the orphan rule would float above the editor body. */}
          <div data-doc-page-title className="mx-12 mb-2 mt-4 h-px bg-border/50" />

          {/* Rich text editor */}
          <div className="px-12 pb-16">
            <Editor
              initialValue={(doc as { content?: JSONContent }).content ?? undefined}
              onChange={() => debouncedSave()}
              onEditorReady={(editor) => {
                editorRef.current = editor;
              }}
              placeholder="Start writing..."
              hideToolbar={false}
            />
          </div>
        </div>
      </ResizablePanel>

      <Dialog open={confirmDeleteOpen} onOpenChange={setConfirmDeleteOpen}>
        <DialogContent className="sm:max-w-[400px]">
          <DialogHeader>
            <DialogTitle className="text-[15px]">Delete page?</DialogTitle>
            <DialogDescription className="text-[12px]">
              This permanently deletes “{title || 'Untitled'}”. This can’t be undone.
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button variant="outline" size="sm" onClick={() => setConfirmDeleteOpen(false)}>
              Cancel
            </Button>
            <Button
              variant="destructive"
              size="sm"
              onClick={() => docId && deleteDoc.mutate({ id: docId })}
              disabled={deleteDoc.isPending}
            >
              Delete
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </ResizablePanelGroup>
  );
}
