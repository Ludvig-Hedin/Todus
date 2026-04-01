/**
 * Docs list page — two-column layout with the DocTree on the left
 * and an empty-state prompt on the right.
 * Navigating to a doc from the tree takes you to /mail/docs/:id.
 */
import { ResizablePanelGroup, ResizablePanel, ResizableHandle } from 'react-resizable-panels';
import { DocTree } from '@/components/docs/doc-tree';
import { FileText, Plus } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { useNavigate } from 'react-router';
import { useTRPC } from '@/providers/query-provider';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { authProxy } from '@/lib/auth-proxy';
import type { Route } from './+types/page';

// Auth guard — redirect to login if no session
export async function clientLoader({ request }: Route.ClientLoaderArgs) {
  const session = await authProxy.api.getSession({ headers: request.headers });
  if (!session) return Response.redirect(`${import.meta.env.VITE_PUBLIC_APP_URL}/login`);
  return {};
}

export default function DocsPage() {
  const navigate = useNavigate();
  const trpc = useTRPC();
  const queryClient = useQueryClient();

  // Quick-create a doc from the empty state's "New page" button.
  // We don't tie it to a specific workspace here — the user can organize later.
  const createDoc = useMutation({
    ...trpc.docs.create.mutationOptions(),
    onSuccess: (result) => {
      void queryClient.invalidateQueries(trpc.docs.list.queryFilter());
      void navigate(`/mail/docs/${result.doc.id}`);
    },
  });

  return (
    <ResizablePanelGroup direction="horizontal" className="h-full">
      {/* Left panel — DocTree navigation */}
      <ResizablePanel defaultSize={20} minSize={15} className="border-r">
        <DocTree onSelectDoc={(id) => void navigate(`/mail/docs/${id}`)} />
      </ResizablePanel>

      <ResizableHandle />

      {/* Right panel — empty state when no doc is selected */}
      <ResizablePanel className="flex items-center justify-center">
        <div className="flex flex-col items-center gap-4 text-center">
          <FileText className="text-muted-foreground h-12 w-12" />
          <div className="space-y-1">
            <p className="text-foreground font-medium">Select a page to start reading</p>
            <p className="text-muted-foreground text-sm">
              Pick a page from the sidebar, or create a new one.
            </p>
          </div>
          <Button
            variant="ghost"
            size="sm"
            className="gap-1.5"
            onClick={() => createDoc.mutate({ title: 'Untitled' })}
            disabled={createDoc.isPending}
          >
            <Plus className="h-4 w-4" />
            New page
          </Button>
        </div>
      </ResizablePanel>
    </ResizablePanelGroup>
  );
}
