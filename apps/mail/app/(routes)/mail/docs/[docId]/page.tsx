/**
 * Doc editor page — two-column layout matching the docs list page.
 * Left panel: DocTree navigation (with the current doc highlighted).
 * Right panel: Title input + Tiptap Editor with auto-save (1 s debounce).
 *
 * Content is stored as Tiptap JSONContent in the DB (jsonb column).
 * We capture the live editor instance via `onEditorReady` so we can call
 * `.getJSON()` and `.getText()` in the debounced save instead of relying on
 * the HTML string that `onChange` emits.
 */
import { useParams, useNavigate, Link } from 'react-router';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useTRPC } from '@/providers/query-provider';
import {
  ResizablePanelGroup,
  ResizablePanel,
  ResizableHandle,
} from '@/components/ui/resizable';
import { DocTree } from '@/components/docs/doc-tree';
import { Editor } from '@/components/create/editor';
import { Editor as TiptapEditor } from '@tiptap/react';
import type { JSONContent } from 'novel';
import { useRef, useCallback, useState, useEffect } from 'react';

// ─── Simple inline debounce with .cancel() support (lodash-es is not in deps) ─
// The .cancel() method is used in a cleanup effect to flush any pending save
// when the component unmounts or docId changes, preventing stale mutations.
function debounce<T extends (...args: Parameters<T>) => void>(fn: T, delay: number) {
  let timer: ReturnType<typeof setTimeout>;
  const debounced = (...args: Parameters<T>) => {
    clearTimeout(timer);
    timer = setTimeout(() => fn(...args), delay);
  };
  debounced.cancel = () => clearTimeout(timer);
  return debounced;
}

export default function DocEditorPage() {
  const { docId } = useParams<{ docId: string }>();
  const navigate = useNavigate();
  const trpc = useTRPC();
  const queryClient = useQueryClient();

  // ── Title local state — kept in sync with loaded doc, editable inline ──────
  const [title, setTitle] = useState('');
  // Track whether we've seeded the title from the server response yet
  const titleInitialized = useRef(false);

  // ── Capture the Tiptap editor instance so we can call .getJSON()/.getText() ─
  const editorRef = useRef<TiptapEditor | null>(null);

  // Clear the editor ref on unmount to avoid holding a reference to a destroyed
  // Tiptap instance, which could cause runtime errors if a pending async callback
  // fires after the component is gone.
  useEffect(() => {
    return () => {
      editorRef.current = null;
    };
  }, []);

  // ── Server state ─────────────────────────────────────────────────────────────
  const { data, isLoading, isError } = useQuery({
    ...trpc.docs.get.queryOptions({ id: docId! }),
    enabled: !!docId,
  });

  const doc = (data as { doc: Record<string, unknown> } | undefined)?.doc;

  // Reset title state when navigating to a different doc so the previous doc's
  // title doesn't flash before the new doc loads.
  useEffect(() => {
    titleInitialized.current = false;
    setTitle('');
  }, [docId]);

  // Seed local title once the doc loads for the first time.
  // TanStack Query v5 removed onSuccess from useQuery — use useEffect instead.
  useEffect(() => {
    if (doc && !titleInitialized.current) {
      setTitle((doc as { title?: string }).title ?? '');
      titleInitialized.current = true;
    }
  }, [doc]);

  // ── Mutations ─────────────────────────────────────────────────────────────────
  const updateDoc = useMutation({
    ...trpc.docs.update.mutationOptions(),
    onSuccess: () => {
      // Invalidate doc + list queries so the tree reflects any title changes
      void queryClient.invalidateQueries(trpc.docs.get.queryFilter({ id: docId! }));
      void queryClient.invalidateQueries(trpc.docs.list.queryFilter());
    },
  });

  // ── Title save (on blur or Enter key) ────────────────────────────────────────
  const saveTitle = useCallback(
    (newTitle: string) => {
      if (!docId) return;
      // Only persist if the value actually changed from what the server has
      const currentServerTitle = (doc as { title?: string } | undefined)?.title ?? '';
      if (newTitle !== currentServerTitle) {
        updateDoc.mutate({ id: docId, title: newTitle });
      }
    },
    [docId, doc, updateDoc],
  );

  // ── Content auto-save (debounced 1 s) ────────────────────────────────────────
  // eslint-disable-next-line react-hooks/exhaustive-deps
  const debouncedSave = useCallback(
    debounce(() => {
      if (!editorRef.current || !docId) return;
      const content: JSONContent = editorRef.current.getJSON();
      const contentText: string = editorRef.current.getText();
      updateDoc.mutate({ id: docId, content, contentText });
    }, 1000),
    [docId],
  );

  // Cancel any pending debounced save on unmount to prevent stale mutations
  // after the component has been removed from the tree.
  useEffect(() => {
    return () => debouncedSave.cancel();
  }, [debouncedSave]);

  // ─────────────────────────────────────────────────────────────────────────────

  if (isLoading) {
    return (
      <ResizablePanelGroup direction="horizontal" className="h-full">
        <ResizablePanel defaultSize={20} minSize={15} className="border-r">
          <DocTree selectedDocId={docId} onSelectDoc={(id) => void navigate(`/mail/docs/${id}`)} />
        </ResizablePanel>
        <ResizableHandle />
        <ResizablePanel className="flex flex-col gap-4 p-8">
          {/* Loading shimmer bars while the doc loads */}
          <div className="bg-muted h-9 w-1/2 animate-pulse rounded" />
          <div className="bg-muted h-4 w-full animate-pulse rounded" />
          <div className="bg-muted h-4 w-3/4 animate-pulse rounded" />
          <div className="bg-muted h-4 w-5/6 animate-pulse rounded" />
        </ResizablePanel>
      </ResizablePanelGroup>
    );
  }

  if (isError || !doc) {
    return (
      <ResizablePanelGroup direction="horizontal" className="h-full">
        <ResizablePanel defaultSize={20} minSize={15} className="border-r">
          <DocTree selectedDocId={docId} onSelectDoc={(id) => void navigate(`/mail/docs/${id}`)} />
        </ResizablePanel>
        <ResizableHandle />
        <ResizablePanel className="flex flex-col items-center justify-center gap-3">
          <p className="text-foreground font-medium">Doc not found</p>
          <Link to="/mail/docs" className="text-muted-foreground text-sm underline">
            Back to Docs
          </Link>
        </ResizablePanel>
      </ResizablePanelGroup>
    );
  }

  return (
    <ResizablePanelGroup direction="horizontal" className="h-full">
      {/* Left panel — DocTree navigation with current doc highlighted */}
      <ResizablePanel defaultSize={20} minSize={15} className="border-r">
        <DocTree
          selectedDocId={docId}
          onSelectDoc={(id) => void navigate(`/mail/docs/${id}`)}
        />
      </ResizablePanel>

      <ResizableHandle />

      {/* Right panel — editor area */}
      <ResizablePanel className="flex min-h-0 flex-col">
        {/* Header row: title input */}
        <div className="flex items-center gap-2 border-b px-8 py-3">
          <input
            type="text"
            value={title}
            placeholder="Untitled"
            className="text-foreground flex-1 bg-transparent text-2xl font-semibold outline-none placeholder:text-gray-400"
            onChange={(e) => setTitle(e.target.value)}
            onBlur={() => saveTitle(title)}
            onKeyDown={(e) => {
              if (e.key === 'Enter') {
                e.currentTarget.blur();
              }
            }}
          />
        </div>

        {/* Editor — fills remaining height, scrolls internally */}
        <div className="min-h-0 flex-1 overflow-y-auto px-8 py-4">
          <Editor
            // Pass stored JSONContent as initial value; falls back to empty doc
            initialValue={(doc as { content?: JSONContent }).content ?? undefined}
            // onChange gives us HTML — we ignore the HTML and use the editor ref
            // for getJSON()/getText() in debouncedSave to store JSONContent
            onChange={() => {
              debouncedSave();
            }}
            onEditorReady={(editor) => {
              editorRef.current = editor;
            }}
            placeholder="Write something..."
            hideToolbar={false}
          />
        </div>
      </ResizablePanel>
    </ResizablePanelGroup>
  );
}
