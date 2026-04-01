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
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
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

  // Fetch workspaces so we can guard the "New page" button — a doc requires a workspace.
  const { data: workspacesData } = useQuery(trpc.docs.workspaces.list.queryOptions());
  const firstWorkspaceId = workspacesData?.[0]?.id;

  // Quick-create a doc from the empty state's "New page" button.
  // Must pass a workspaceId — enforced by checking firstWorkspaceId before rendering the button.
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
          {firstWorkspaceId ? (
            // Workspace exists — allow quick-creating a new doc from here
            <Button
              variant="ghost"
              size="sm"
              className="gap-1.5"
              onClick={() => createDoc.mutate({ workspaceId: firstWorkspaceId, title: 'Untitled' })}
              disabled={createDoc.isPending}
            >
              <Plus className="h-4 w-4" />
              New page
            </Button>
          ) : (
            // No workspaces yet — guide the user to create one first via the left panel
            <p className="text-muted-foreground text-sm">
              Create a workspace first using the + button on the left.
            </p>
          )}
        </div>
      </ResizablePanel>
    </ResizablePanelGroup>
  );
}
