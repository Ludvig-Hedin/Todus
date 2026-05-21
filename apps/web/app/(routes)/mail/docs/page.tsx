/**
 * Docs landing page — two-column layout.
 * Left: DocTree (workspace + page navigation).
 * Right: Welcome/empty state with a prominent "New page" action.
 */
import { ResizablePanelGroup, ResizablePanel, ResizableHandle } from '@/components/ui/resizable';
import { DocTree } from '@/components/docs/doc-tree';
import { FileText, Plus, ArrowRight } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { useNavigate, redirect } from 'react-router';
import { useTRPC } from '@/providers/query-provider';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { TRPCClientError } from '@trpc/client';
import { authProxy } from '@/lib/auth-proxy';
import type { Route } from './+types/page';
import { toast } from 'sonner';

function mapWorkspaceListError(error: unknown): string {
  if (error instanceof TRPCClientError) {
    const code = error.data && typeof error.data === 'object' && 'code' in error.data
      ? String((error.data as { code?: string }).code)
      : undefined;
    if (code === 'UNAUTHORIZED' || code === 'FORBIDDEN') {
      return 'You need to be signed in to load workspaces.';
    }
    if (code === 'PRECONDITION_FAILED' || code === 'NOT_FOUND') {
      return 'Workspaces are not available yet. Try again in a moment.';
    }
  }
  return 'Unable to load workspaces';
}

// Auth guard — redirect to login if no session
export async function clientLoader({ request }: Route.ClientLoaderArgs) {
  const session = await authProxy.api.getSession({ headers: request.headers });
  if (!session) throw redirect('/login');
  return {};
}

export default function DocsPage() {
  const navigate = useNavigate();
  const trpc = useTRPC();
  const queryClient = useQueryClient();

  const { data: workspacesData, isLoading, isError, error } = useQuery(
    trpc.docs.workspaces.list.queryOptions(),
  );
  const listErrorMessage = isError ? mapWorkspaceListError(error) : null;
  const firstWorkspaceId = workspacesData?.workspaces?.[0]?.id;

  const createDoc = useMutation({
    ...trpc.docs.create.mutationOptions(),
    onSuccess: (result) => {
      void queryClient.invalidateQueries(trpc.docs.list.queryFilter());
      void navigate(`/mail/docs/${result.doc.id}`);
    },
    onError: (err) => {
      console.error('Failed to create doc:', err);
      const message = err instanceof Error ? err.message : 'Could not create page.';
      toast.error(message);
    },
  });

  const createWorkspace = useMutation({
    ...trpc.docs.workspaces.create.mutationOptions(),
    onError: (err) => {
      console.error('Failed to create workspace:', err);
      toast.error(err instanceof Error ? err.message : 'Could not create workspace.');
    },
  });

  // If the user has no workspaces yet (new account / first visit), creating
  // a default one + a starter page in one click is far better UX than the
  // permanently-disabled "New page" button this had before.
  const handleNewPage = async () => {
    let workspaceId = firstWorkspaceId;
    if (!workspaceId) {
      const created = await createWorkspace.mutateAsync({ name: 'My workspace' }).catch(() => null);
      workspaceId = created?.workspace?.id;
      if (workspaceId) {
        await queryClient.invalidateQueries(trpc.docs.workspaces.list.queryFilter());
      }
    }
    if (!workspaceId) return;
    createDoc.mutate({ workspaceId, title: 'Untitled' });
  };

  return (
    <ResizablePanelGroup direction="horizontal" className="h-full">
      {/* Left — page tree */}
      <ResizablePanel defaultSize={22} minSize={16} maxSize={35} className="border-r">
        <DocTree onSelectDoc={(id) => void navigate(`/mail/docs/${id}`)} />
      </ResizablePanel>

      <ResizableHandle withHandle />

      {/* Right — welcome state */}
      <ResizablePanel className="flex h-full flex-col">
        <div className="flex h-full flex-col items-center justify-center gap-6 px-8">
          {/* Icon */}
          <div className="bg-accent/50 flex h-16 w-16 items-center justify-center rounded-2xl">
            <FileText className="text-muted-foreground h-8 w-8" />
          </div>

          {/* Heading */}
          <div className="space-y-2 text-center">
            <h2 className="text-foreground text-xl font-semibold">
              Your docs, all in one place
            </h2>
            <p className="text-muted-foreground max-w-xs text-sm leading-relaxed">
              Write notes, capture ideas, draft documents — pick a page on the left or start a new
              one.
            </p>
          </div>

          {/* Primary action — works even when the user has zero workspaces
              by auto-creating a default workspace first. */}
          {!isLoading && !isError && (
            <Button
              onClick={() => void handleNewPage()}
              disabled={createDoc.isPending || createWorkspace.isPending}
              className="gap-2"
            >
              <Plus className="h-4 w-4" />
              {firstWorkspaceId ? 'New page' : 'Get started'}
            </Button>
          )}

          {!isLoading && isError && (
            <div className="flex max-w-md flex-col items-center gap-3 text-center">
              <p className="text-muted-foreground text-sm leading-relaxed">{listErrorMessage}</p>
              <Button
                variant="outline"
                onClick={() =>
                  void queryClient.invalidateQueries(trpc.docs.workspaces.list.queryFilter())
                }
              >
                Retry
              </Button>
            </div>
          )}

          {/* Hint */}
          {!isError && (
            <p className="text-muted-foreground/60 flex items-center gap-1.5 text-xs">
              <ArrowRight className="h-3 w-3 -rotate-180" />
              Or select a page from the sidebar
            </p>
          )}
        </div>
      </ResizablePanel>
    </ResizablePanelGroup>
  );
}
