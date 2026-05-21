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
    <ResizablePanel defaultSize={22} minSize={16} maxSize={35} className="border-r">
      <DocTree
        selectedDocId={docId}
        onSelectDoc={(id) => navigate(`/mail/docs/${id}`)}
      />
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

  const saveTitle = useCallback(
    (newTitle: string) => {
      if (!docId) return;
      const serverTitle = (doc as { title?: string } | undefined)?.title ?? '';
      if (newTitle !== serverTitle) {
        updateDoc.mutate({ id: docId, title: newTitle });
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
          {/* Title — Affine-style large h1 */}
          <div className="px-12 pb-0 pt-10">
            <input
              type="text"
              value={title}
              placeholder="Untitled"
              aria-label="Document title"
              className="text-foreground w-full rounded-md bg-transparent text-4xl font-bold tracking-tight outline-none placeholder:text-gray-300 focus-visible:ring-1 focus-visible:ring-ring dark:placeholder:text-gray-600"
              onChange={(e) => setTitle(e.target.value)}
              onBlur={() => saveTitle(title)}
              onKeyDown={(e) => {
                if (e.key === 'Enter') {
                  e.currentTarget.blur();
                }
              }}
            />
          </div>

          {/* Divider between title and body */}
          <div className="mx-12 mb-2 mt-4 h-px bg-border/50" />

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
    </ResizablePanelGroup>
  );
}
