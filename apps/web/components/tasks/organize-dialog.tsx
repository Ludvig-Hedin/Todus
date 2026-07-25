/**
 * Organize dialog — parity with iOS `TaskOrganizeService` + `OrganizeReviewSheet`.
 *
 * Two-layer proposal pass over every unfiled, non-done task:
 *   1. Rule layer (instant, offline): a folder wins when its full name
 *      (multi-word) or its name as a whole word (single-word) appears in the
 *      task text. Same matcher as iOS `ruleMatch`.
 *   2. `tasks.organize` for whatever the rules didn't claim — the server may
 *      also propose up to 2 new folder names.
 *
 * Nothing is applied until the user hits Apply, and every row can be
 * unchecked individually.
 */
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { FolderIcon, FolderPlus, Loader2, Sparkles } from 'lucide-react';
import { useMutation, useQuery } from '@tanstack/react-query';
import { ScrollArea } from '@/components/ui/scroll-area';
import { useTRPC } from '@/providers/query-provider';
import { Button } from '@/components/ui/button';
import { useEffect, useState } from 'react';
import { cn } from '@/lib/utils';
import { toast } from 'sonner';

interface OrganizeTaskInput {
  id: string;
  title: string;
  description: string;
  folderId: string | null;
  status: string;
}

export interface OrganizeFolderInput {
  id: string;
  name: string;
}

/** A destination is either an existing folder id or a not-yet-created name. */
type Destination =
  | { kind: 'existing'; folderId: string; name: string }
  | { kind: 'new'; name: string };

interface Proposal {
  taskId: string;
  taskTitle: string;
  destination: Destination;
  source: 'rule' | 'ai';
  accepted: boolean;
}

/**
 * Deterministic folder match, mirroring iOS `ruleMatch`: multi-word folder
 * names must appear as a full substring; single-word names must appear as a
 * whole word so "Work" doesn't match "Workshop".
 */
function ruleMatch(
  task: OrganizeTaskInput,
  folders: OrganizeFolderInput[],
): OrganizeFolderInput | null {
  const haystack = `${task.title} ${task.description}`.toLowerCase();
  const words = new Set(haystack.split(/[^\p{L}\p{N}]+/u).filter(Boolean));

  for (const folder of folders) {
    const name = folder.name.trim().toLowerCase();
    if (!name) continue;
    const isMultiWord = /\s/.test(name);
    if (isMultiWord ? haystack.includes(name) : words.has(name)) return folder;
  }
  return null;
}

interface OrganizeDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  folders: OrganizeFolderInput[];
  /** Creates a folder and resolves to its new id. */
  onCreateFolder: (name: string) => Promise<string>;
  /** Moves one task into a folder. */
  onMoveTask: (taskId: string, folderId: string) => Promise<void>;
  /** Called once after a successful apply so the caller can refetch. */
  onApplied: (movedCount: number) => void;
}

export function OrganizeDialog({
  open,
  onOpenChange,
  folders,
  onCreateFolder,
  onMoveTask,
  onApplied,
}: OrganizeDialogProps) {
  const trpc = useTRPC();
  const [proposals, setProposals] = useState<Proposal[] | null>(null);
  const [isApplying, setIsApplying] = useState(false);
  const organize = useMutation(trpc.tasks.organize.mutationOptions());

  // Own query rather than reusing the page's list: that one is scoped by the
  // active folder / status filter / search box, and organizing must see every
  // unfiled task regardless of what the page is currently showing.
  const { data: allTasksData, isLoading: isLoadingTasks } = useQuery(
    trpc.tasks.list.queryOptions(
      { sortBy: 'newest', limit: 500 },
      { enabled: open, staleTime: 0 },
    ),
  );

  // The unfiled, still-open set is what we propose over — matching iOS, which
  // ignores tasks that already live in a folder and anything already done.
  const unfiled: OrganizeTaskInput[] = (allTasksData?.tasks ?? [])
    .filter((t) => !t.folderId && t.status !== 'done')
    .map((t) => ({
      id: t.id,
      title: t.title,
      description: t.description ?? '',
      folderId: t.folderId ?? null,
      status: t.status,
    }));

  useEffect(() => {
    if (!open || isLoadingTasks || !allTasksData) {
      if (!open) setProposals(null);
      return;
    }

    let cancelled = false;

    void (async () => {
      if (unfiled.length === 0) {
        if (!cancelled) setProposals([]);
        return;
      }

      const ruleProposals: Proposal[] = [];
      const needsAI: OrganizeTaskInput[] = [];

      for (const task of unfiled) {
        const folder = ruleMatch(task, folders);
        if (folder) {
          ruleProposals.push({
            taskId: task.id,
            taskTitle: task.title,
            destination: { kind: 'existing', folderId: folder.id, name: folder.name },
            source: 'rule',
            accepted: true,
          });
        } else {
          needsAI.push(task);
        }
      }

      const aiProposals: Proposal[] = [];
      if (needsAI.length > 0) {
        try {
          // The server caps input at 100 tasks / 50 folders.
          const result = await organize.mutateAsync({
            tasks: needsAI.slice(0, 100).map((t) => ({
              id: t.id,
              title: t.title.slice(0, 500),
              description: t.description.slice(0, 2000),
            })),
            folders: folders.slice(0, 50).map((f) => ({ id: f.id, name: f.name.slice(0, 200) })),
          });

          const byId = new Map(needsAI.map((t) => [t.id, t]));
          for (const assignment of result.assignments) {
            const task = byId.get(assignment.taskId);
            if (!task) continue;
            if (assignment.folderId) {
              const folder = folders.find((f) => f.id === assignment.folderId);
              if (!folder) continue;
              aiProposals.push({
                taskId: task.id,
                taskTitle: task.title,
                destination: { kind: 'existing', folderId: folder.id, name: folder.name },
                source: 'ai',
                accepted: true,
              });
            } else if (assignment.newFolderName) {
              aiProposals.push({
                taskId: task.id,
                taskTitle: task.title,
                destination: { kind: 'new', name: assignment.newFolderName },
                source: 'ai',
                accepted: true,
              });
            }
            // folderId === null && newFolderName === null → stays unfiled.
          }
        } catch (error) {
          console.error('tasks.organize failed:', error);
          // Rules-only fallback, same as iOS when offline. Only warn when the
          // rule layer produced nothing, otherwise the partial result stands.
          if (ruleProposals.length === 0) {
            toast.error('Could not reach the organizer. Try again in a moment.');
          }
        }
      }

      if (!cancelled) setProposals([...ruleProposals, ...aiProposals]);
    })();

    return () => {
      cancelled = true;
    };
    // Deliberately keyed on open + the loaded task payload only. Re-running on
    // every `folders`/`unfiled` identity change would restart the AI pass
    // mid-review; the snapshot taken when the data first lands is what we review.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, allTasksData, isLoadingTasks]);

  const acceptedCount = proposals?.filter((p) => p.accepted).length ?? 0;

  const toggle = (taskId: string) =>
    setProposals(
      (prev) =>
        prev?.map((p) => (p.taskId === taskId ? { ...p, accepted: !p.accepted } : p)) ?? prev,
    );

  const setAll = (accepted: boolean) =>
    setProposals((prev) => prev?.map((p) => ({ ...p, accepted })) ?? prev);

  const apply = async () => {
    if (!proposals) return;
    const accepted = proposals.filter((p) => p.accepted);
    if (accepted.length === 0) return;

    setIsApplying(true);
    try {
      // Get-or-create by lowercased name so two proposals sharing a name land
      // in one folder (iOS `createdByName`).
      const createdByName = new Map<string, string>();
      let moved = 0;

      for (const proposal of accepted) {
        let folderId: string;
        if (proposal.destination.kind === 'existing') {
          folderId = proposal.destination.folderId;
        } else {
          const key = proposal.destination.name.toLowerCase();
          const cached = createdByName.get(key);
          if (cached) {
            folderId = cached;
          } else {
            folderId = await onCreateFolder(proposal.destination.name);
            createdByName.set(key, folderId);
          }
        }
        await onMoveTask(proposal.taskId, folderId);
        moved += 1;
      }

      onApplied(moved);
      onOpenChange(false);
      toast.success(moved === 1 ? '1 task filed' : `${moved} tasks filed`);
    } catch (error) {
      console.error('Failed to apply organize proposals:', error);
      toast.error('Could not file every task. Please try again.');
    } finally {
      setIsApplying(false);
    }
  };

  const isLoading = proposals === null;

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent showOverlay className="sm:max-w-lg">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Sparkles className="h-4 w-4" />
            Organize tasks
          </DialogTitle>
          <DialogDescription>
            Review where each unfiled task should go. Nothing moves until you apply.
          </DialogDescription>
        </DialogHeader>

        {isLoading ? (
          <div className="text-muted-foreground flex items-center justify-center gap-2 py-10 text-sm">
            <Loader2 className="h-4 w-4 animate-spin" />
            {unfiled.length > 0
              ? `Sorting ${unfiled.length} unfiled ${unfiled.length === 1 ? 'task' : 'tasks'}…`
              : 'Looking at your tasks…'}
          </div>
        ) : proposals.length === 0 ? (
          <div className="text-muted-foreground py-10 text-center text-sm">
            {unfiled.length === 0
              ? 'Every task is already filed.'
              : 'No confident suggestions — these tasks stay in the inbox.'}
          </div>
        ) : (
          <>
            <div className="flex items-center justify-between text-xs">
              <span className="text-muted-foreground">
                {acceptedCount} of {proposals.length} selected
              </span>
              <div className="flex items-center gap-1">
                <Button variant="ghost" size="sm" className="h-7 text-xs" onClick={() => setAll(true)}>
                  Select all
                </Button>
                <Button variant="ghost" size="sm" className="h-7 text-xs" onClick={() => setAll(false)}>
                  Clear
                </Button>
              </div>
            </div>

            <ScrollArea className="max-h-[45vh] pr-2">
              <ul className="space-y-1">
                {proposals.map((proposal) => (
                  <li key={proposal.taskId}>
                    <button
                      type="button"
                      onClick={() => toggle(proposal.taskId)}
                      aria-pressed={proposal.accepted}
                      className={cn(
                        'flex w-full items-start gap-3 rounded-lg border p-2.5 text-left transition-colors',
                        'focus-visible:ring-ring focus-visible:outline-none focus-visible:ring-1',
                        proposal.accepted
                          ? 'border-foreground/20 bg-accent/40'
                          : 'border-border hover:bg-accent/20 opacity-60',
                      )}
                    >
                      <span
                        className={cn(
                          'mt-0.5 flex h-4 w-4 shrink-0 items-center justify-center rounded border text-[10px]',
                          proposal.accepted
                            ? 'bg-foreground text-background border-transparent'
                            : 'border-border',
                        )}
                        aria-hidden
                      >
                        {proposal.accepted ? '✓' : ''}
                      </span>
                      <span className="min-w-0 flex-1">
                        <span className="block truncate text-sm">{proposal.taskTitle}</span>
                        <span className="text-muted-foreground mt-0.5 flex items-center gap-1.5 text-xs">
                          {proposal.destination.kind === 'new' ? (
                            <FolderPlus className="h-3 w-3" />
                          ) : (
                            <FolderIcon className="h-3 w-3" />
                          )}
                          {proposal.destination.name}
                          {proposal.destination.kind === 'new' && (
                            <span className="bg-muted rounded px-1 py-px text-[10px] uppercase tracking-wide">
                              New
                            </span>
                          )}
                          {proposal.source === 'ai' && (
                            <Sparkles className="h-2.5 w-2.5 opacity-60" aria-label="AI suggestion" />
                          )}
                        </span>
                      </span>
                    </button>
                  </li>
                ))}
              </ul>
            </ScrollArea>
          </>
        )}

        <DialogFooter>
          <Button variant="ghost" onClick={() => onOpenChange(false)} disabled={isApplying}>
            Cancel
          </Button>
          <Button onClick={() => void apply()} disabled={isLoading || acceptedCount === 0 || isApplying}>
            {isApplying && <Loader2 className="mr-1.5 h-3.5 w-3.5 animate-spin" />}
            Apply {acceptedCount > 0 ? acceptedCount : ''}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
