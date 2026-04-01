/**
 * DocTree — sidebar tree showing workspaces and their nested pages.
 * Used in both the docs list page and the doc editor page.
 * Fetches workspaces + root-level docs per workspace via tRPC,
 * renders them as collapsible sections with inline "new page" and
 * "new workspace" actions.
 */
import { ChevronRight, ChevronDown, FileText, FolderOpen, Plus } from 'lucide-react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useTRPC } from '@/providers/query-provider';
import { Skeleton } from '@/components/ui/skeleton';
import { Button } from '@/components/ui/button';
import { useState } from 'react';
import { cn } from '@/lib/utils';

interface DocTreeProps {
  selectedDocId?: string;
  onSelectDoc: (docId: string) => void;
}

/** Per-workspace section: fetches root docs and renders them as a collapsible list. */
function WorkspaceSection({
  workspace,
  selectedDocId,
  onSelectDoc,
}: {
  workspace: { id: string; name: string; emoji: string | null };
  selectedDocId?: string;
  onSelectDoc: (docId: string) => void;
}) {
  const [expanded, setExpanded] = useState(true);
  const trpc = useTRPC();
  const queryClient = useQueryClient();

  // Fetch root-level docs (parentId undefined = no parent) for this workspace
  const { data, isLoading } = useQuery(
    trpc.docs.list.queryOptions({ workspaceId: workspace.id }),
  );

  const createDoc = useMutation({
    ...trpc.docs.create.mutationOptions(),
    onSuccess: (result) => {
      // Invalidate only this workspace's docs list so the new page appears in the tree
      void queryClient.invalidateQueries(trpc.docs.list.queryFilter({ workspaceId: workspace.id }));
      // Navigate immediately to the newly created doc
      onSelectDoc(result.doc.id);
    },
  });

  const docs = data?.docs ?? [];

  return (
    <div className="mb-1">
      {/* Workspace header row with expand/collapse + new page button */}
      <div className="group flex items-center gap-0.5 rounded-md px-1 py-0.5 hover:bg-accent/50">
        <button
          onClick={() => setExpanded((v) => !v)}
          className="flex flex-1 items-center gap-1 text-left"
        >
          {expanded ? (
            <ChevronDown className="text-muted-foreground h-3.5 w-3.5 shrink-0" />
          ) : (
            <ChevronRight className="text-muted-foreground h-3.5 w-3.5 shrink-0" />
          )}
          <FolderOpen className="text-muted-foreground h-3.5 w-3.5 shrink-0" />
          <span className="text-foreground truncate text-sm font-medium">
            {workspace.emoji ? `${workspace.emoji} ` : ''}
            {workspace.name}
          </span>
        </button>

        {/* "New page" button — only visible on hover to keep the tree clean */}
        <Button
          variant="ghost"
          size="sm"
          className="text-muted-foreground h-5 w-5 shrink-0 p-0 opacity-0 transition-opacity group-hover:opacity-100"
          onClick={(e) => {
            e.stopPropagation();
            createDoc.mutate({ workspaceId: workspace.id, title: 'Untitled' });
          }}
          disabled={createDoc.isPending}
          title="New page"
        >
          <Plus className="h-3.5 w-3.5" />
        </Button>
      </div>

      {/* Docs list — only rendered when expanded */}
      {expanded && (
        <div className="ml-3 mt-0.5 border-l pl-2">
          {isLoading ? (
            // Skeleton placeholders while docs are loading
            <div className="space-y-1 py-1">
              <Skeleton className="h-4 w-3/4 rounded" />
              <Skeleton className="h-4 w-1/2 rounded" />
            </div>
          ) : docs.length === 0 ? (
            <p className="text-muted-foreground px-1 py-1 text-xs">No pages yet</p>
          ) : (
            <div className="space-y-0.5 py-0.5">
              {docs.map((d) => (
                <button
                  key={d.id}
                  onClick={() => onSelectDoc(d.id)}
                  className={cn(
                    'flex w-full items-center gap-1.5 rounded-md px-2 py-1 text-left text-sm transition-colors',
                    selectedDocId === d.id
                      ? 'bg-accent text-accent-foreground font-medium'
                      : 'text-muted-foreground hover:bg-accent/50 hover:text-foreground',
                  )}
                >
                  <FileText className="h-3.5 w-3.5 shrink-0" />
                  <span className="truncate">
                    {d.emoji ? `${d.emoji} ` : ''}
                    {d.title || 'Untitled'}
                  </span>
                </button>
              ))}
            </div>
          )}
        </div>
      )}
    </div>
  );
}

/** DocTree — root component. Fetches workspaces and renders a WorkspaceSection per workspace. */
export function DocTree({ selectedDocId, onSelectDoc }: DocTreeProps) {
  const trpc = useTRPC();
  const queryClient = useQueryClient();

  const { data, isLoading } = useQuery(trpc.docs.workspaces.list.queryOptions());

  const createWorkspace = useMutation({
    ...trpc.docs.workspaces.create.mutationOptions(),
    onSuccess: () => {
      // Re-fetch the workspace list so the new entry appears immediately
      void queryClient.invalidateQueries(trpc.docs.workspaces.list.queryFilter());
    },
  });

  const workspaces = data?.workspaces ?? [];

  return (
    <div className="flex h-full flex-col gap-1 p-2">
      <div className="flex-1 overflow-y-auto">
        {isLoading ? (
          // Skeleton while workspaces are loading
          <div className="space-y-2 p-1">
            <Skeleton className="h-5 w-full rounded" />
            <Skeleton className="ml-3 h-4 w-3/4 rounded" />
            <Skeleton className="ml-3 h-4 w-1/2 rounded" />
          </div>
        ) : workspaces.length === 0 ? (
          // Empty state — prompt the user to create a workspace
          <div className="flex flex-col items-center gap-2 px-2 py-8 text-center">
            <FolderOpen className="text-muted-foreground h-8 w-8" />
            <p className="text-muted-foreground text-sm">No docs yet</p>
            <p className="text-muted-foreground text-xs">Create a workspace to get started</p>
          </div>
        ) : (
          workspaces.map((ws) => (
            <WorkspaceSection
              key={ws.id}
              workspace={ws}
              selectedDocId={selectedDocId}
              onSelectDoc={onSelectDoc}
            />
          ))
        )}
      </div>

      {/* "New workspace" button anchored at the bottom of the tree */}
      <Button
        variant="ghost"
        size="sm"
        className="text-muted-foreground mt-auto w-full justify-start gap-1.5 text-xs"
        onClick={() => createWorkspace.mutate({ name: 'New Workspace' })}
        disabled={createWorkspace.isPending}
      >
        <Plus className="h-3.5 w-3.5" />
        New workspace
      </Button>
    </div>
  );
}
