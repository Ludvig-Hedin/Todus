/**
 * Docs landing page — two-column layout.
 * Left: DocTree (workspace + page navigation).
 * Right: Welcome/empty state with a prominent "New page" action.
 */
import { ResizablePanelGroup, ResizablePanel, ResizableHandle } from '@/components/ui/resizable';
import { DocTree } from '@/components/docs/doc-tree';
import { FileText, Plus, ArrowRight } from 'lucide-react';
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

  const { data: workspacesData, isLoading } = useQuery(
    trpc.docs.workspaces.list.queryOptions(),
  );
  const firstWorkspaceId = workspacesData?.workspaces?.[0]?.id;

  const createDoc = useMutation({
    ...trpc.docs.create.mutationOptions(),
    onSuccess: (result) => {
      void queryClient.invalidateQueries(trpc.docs.list.queryFilter());
      void navigate(`/mail/docs/${result.doc.id}`);
    },
  });

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

          {/* Primary action */}
          {!isLoading && (
            <Button
              onClick={() => {
                if (firstWorkspaceId) {
                  createDoc.mutate({ workspaceId: firstWorkspaceId, title: 'Untitled' });
                }
              }}
              disabled={createDoc.isPending || !firstWorkspaceId}
              className="gap-2"
            >
              <Plus className="h-4 w-4" />
              New page
            </Button>
          )}

          {/* Hint */}
          <p className="text-muted-foreground/60 flex items-center gap-1.5 text-xs">
            <ArrowRight className="h-3 w-3 -rotate-180" />
            Or select a page from the sidebar
          </p>
        </div>
      </ResizablePanel>
    </ResizablePanelGroup>
  );
}
