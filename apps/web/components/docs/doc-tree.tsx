/**
 * DocTree — Affine-inspired sidebar for workspaces and pages.
 *
 * UX principles:
 * - Zero friction: auto-creates a "Personal" workspace on first load
 * - "New page" is one click away from the sidebar header
 * - Workspace sections are collapsible with an inline "+" on hover
 * - No mandatory workspace setup step
 */
import { ChevronRight, ChevronDown, FileText, Plus, PenLine } from 'lucide-react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useTRPC } from '@/providers/query-provider';
import { Skeleton } from '@/components/ui/skeleton';
import { useEffect, useRef, useState } from 'react';
import { cn } from '@/lib/utils';

export interface DocTreeProps {
  selectedDocId?: string;
  onSelectDoc: (docId: string) => void;
}

// ─── WorkspaceSection ──────────────────────────────────────────────────────────

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

  const { data, isLoading } = useQuery(
    trpc.docs.list.queryOptions({ workspaceId: workspace.id }),
  );

  const createDoc = useMutation({
    ...trpc.docs.create.mutationOptions(),
    onSuccess: (result) => {
      void queryClient.invalidateQueries(
        trpc.docs.list.queryFilter({ workspaceId: workspace.id }),
      );
      onSelectDoc(result.doc.id);
    },
  });

  const docs = data?.docs ?? [];

  return (
    <div>
      {/* Workspace header */}
      <div className="group/ws flex items-center gap-0.5 rounded-md px-2 py-1.5 hover:bg-accent/50">
        <button
          onClick={() => setExpanded((v) => !v)}
          className="flex flex-1 items-center gap-1 text-left"
        >
          {expanded ? (
            <ChevronDown className="text-muted-foreground h-3 w-3 shrink-0" />
          ) : (
            <ChevronRight className="text-muted-foreground h-3 w-3 shrink-0" />
          )}
          <span className="text-muted-foreground truncate text-[11px] font-semibold uppercase tracking-wider">
            {workspace.emoji ? `${workspace.emoji} ` : ''}
            {workspace.name}
          </span>
        </button>

        {/* New page in this workspace — appears on row hover */}
        <button
          className="text-muted-foreground ml-auto opacity-0 transition-opacity hover:text-foreground group-hover/ws:opacity-100"
          onClick={(e) => {
            e.stopPropagation();
            createDoc.mutate({ workspaceId: workspace.id, title: 'Untitled' });
          }}
          disabled={createDoc.isPending}
          title="New page"
        >
          <Plus className="h-3.5 w-3.5" />
        </button>
      </div>

      {/* Pages list */}
      {expanded && (
        <div className="mb-1 ml-2 space-y-0.5">
          {isLoading ? (
            <div className="space-y-1 py-1 pl-4">
              <Skeleton className="h-4 w-4/5 rounded" />
              <Skeleton className="h-4 w-3/5 rounded" />
            </div>
          ) : docs.length === 0 ? (
            // Empty workspace — show a subtle "new page" prompt
            <button
              className="text-muted-foreground hover:text-foreground flex w-full items-center gap-2 rounded-md py-1.5 pl-5 pr-2 text-[13px] transition-colors hover:bg-accent/40"
              onClick={() =>
                createDoc.mutate({ workspaceId: workspace.id, title: 'Untitled' })
              }
            >
              <Plus className="h-3.5 w-3.5 shrink-0" />
              New page
            </button>
          ) : (
            docs.map((d) => (
              <button
                key={d.id}
                onClick={() => onSelectDoc(d.id)}
                className={cn(
                  'group/doc flex w-full items-center gap-2 rounded-md py-1.5 pl-5 pr-2 text-left text-[13px] transition-colors',
                  selectedDocId === d.id
                    ? 'bg-accent text-accent-foreground font-medium'
                    : 'text-foreground/80 hover:bg-accent/40 hover:text-foreground',
                )}
              >
                <FileText className="text-muted-foreground h-3.5 w-3.5 shrink-0" />
                <span className="flex-1 truncate">
                  {d.emoji ? `${d.emoji} ` : ''}
                  {d.title || 'Untitled'}
                </span>
              </button>
            ))
          )}
        </div>
      )}
    </div>
  );
}

// ─── DocTree root ──────────────────────────────────────────────────────────────

export function DocTree({ selectedDocId, onSelectDoc }: DocTreeProps) {
  const trpc = useTRPC();
  const queryClient = useQueryClient();
  const autoCreatedRef = useRef(false);

  const { data, isLoading } = useQuery(trpc.docs.workspaces.list.queryOptions());

  const createWorkspace = useMutation({
    ...trpc.docs.workspaces.create.mutationOptions(),
    onSuccess: () => {
      void queryClient.invalidateQueries(trpc.docs.workspaces.list.queryFilter());
    },
  });

  // Quick-create a doc in the first workspace
  const quickCreateDoc = useMutation({
    ...trpc.docs.create.mutationOptions(),
    onSuccess: (result) => {
      void queryClient.invalidateQueries(trpc.docs.list.queryFilter());
      onSelectDoc(result.doc.id);
    },
  });

  // Auto-create "Personal" workspace on first load.
  // Guarded by a ref so it only fires once even in React StrictMode.
  useEffect(() => {
    if (!isLoading && data?.workspaces.length === 0 && !autoCreatedRef.current) {
      autoCreatedRef.current = true;
      createWorkspace.mutate({ name: 'Personal' });
    }
  }, [isLoading, data, createWorkspace]);

  const workspaces = data?.workspaces ?? [];
  const firstWorkspaceId = workspaces[0]?.id;
  const isSettingUp = isLoading || (workspaces.length === 0 && createWorkspace.isPending);

  return (
    <div className="flex h-full flex-col">
      {/* Header with "New page" quick action */}
      <div className="flex items-center justify-between border-b px-3 py-2.5">
        <span className="text-foreground text-[13px] font-semibold">Docs</span>
        {firstWorkspaceId && (
          <button
            className="text-muted-foreground hover:bg-accent hover:text-foreground rounded-md p-1.5 transition-colors"
            onClick={() =>
              quickCreateDoc.mutate({
                workspaceId: firstWorkspaceId,
                title: 'Untitled',
              })
            }
            disabled={quickCreateDoc.isPending}
            title="New page"
          >
            <PenLine className="h-3.5 w-3.5" />
          </button>
        )}
      </div>

      {/* Workspace tree */}
      <div className="flex-1 overflow-y-auto py-1.5 pr-1">
        {isSettingUp ? (
          <div className="space-y-2 px-3 py-2">
            <Skeleton className="h-4 w-2/5 rounded" />
            <Skeleton className="ml-3 h-4 w-3/4 rounded" />
            <Skeleton className="ml-3 h-4 w-1/2 rounded" />
          </div>
        ) : (
          <>
            {workspaces.map((ws) => (
              <WorkspaceSection
                key={ws.id}
                workspace={ws}
                selectedDocId={selectedDocId}
                onSelectDoc={onSelectDoc}
              />
            ))}

            {/* Add workspace — tertiary, stays out of the way */}
            <button
              className="text-muted-foreground/50 hover:text-muted-foreground mt-1 flex w-full items-center gap-1.5 rounded-md px-2.5 py-1 text-[11px] transition-colors hover:bg-accent/30"
              onClick={() => createWorkspace.mutate({ name: 'New Workspace' })}
              disabled={createWorkspace.isPending}
            >
              <Plus className="h-3 w-3" />
              Add workspace
            </button>
          </>
        )}
      </div>
    </div>
  );
}
