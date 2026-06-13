/**
 * Tasks page — full parity with iOS TasksTabView.
 * View modes: List (default) | Board (kanban drag-drop) | Table (compact rows)
 * Folder filter: horizontal pill-chip strip at top (replaces sidebar)
 * Task detail: Sheet from right, full info + edit form
 */
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
  DropdownMenuRadioGroup,
  DropdownMenuRadioItem,
  DropdownMenuLabel,
  DropdownMenuSub,
  DropdownMenuSubTrigger,
  DropdownMenuSubContent,
} from '@/components/ui/dropdown-menu';
import {
  Plus,
  MoreHorizontal,
  Trash2,
  Pencil,
  CalendarIcon,
  Circle,
  CheckCircle2,
  ArrowUpDown,
  FolderIcon,
  FolderPlus,
  X,
  List,
  LayoutGrid,
  Table2,
  GripVertical,
  Zap,
  Eye,
  Loader2,
} from 'lucide-react';
import {
  DndContext,
  DragOverlay,
  PointerSensor,
  useSensor,
  useSensors,
  closestCenter,
  type DragStartEvent,
  type DragEndEvent,
} from '@dnd-kit/core';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from '@/components/ui/dialog';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import { SortableContext, useSortable, verticalListSortingStrategy } from '@dnd-kit/sortable';
import { Sheet, SheetContent, SheetHeader, SheetTitle } from '@/components/ui/sheet';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { ScrollArea } from '@/components/ui/scroll-area';
import { useTRPC } from '@/providers/query-provider';
import { BackgroundRefreshIndicator } from '@/components/ui/background-refresh-indicator';
import { removeTaskFromTaskCaches, upsertTaskInTaskCaches } from '@/lib/task-cache';
import { Textarea } from '@/components/ui/textarea';
import { Calendar } from '@/components/ui/calendar';
import { format, isPast, isToday } from 'date-fns';
import { useState, useMemo, useRef, useCallback, useEffect } from 'react';
import { toast } from 'sonner';
import type { Outputs } from '@zero/server/trpc';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Badge } from '@/components/ui/badge';
import { authProxy } from '@/lib/auth-proxy';
import { useDroppable } from '@dnd-kit/core';
import type { Route } from './+types/page';
import { CSS } from '@dnd-kit/utilities';
import { cn } from '@/lib/utils';
import { parseNaturalLanguage } from '@/lib/nlp/parse-natural-language';
import { CalendarGrid } from '@/components/calendar/calendar-grid';

type Task = Outputs['tasks']['list']['tasks'][number];
type Folder = Outputs['folders']['list']['folders'][number];
type TaskStatus = 'todo' | 'doing' | 'done';
type TaskPriority = 'none' | 'low' | 'medium' | 'high';
type SortBy = 'newest' | 'oldest' | 'priority' | 'smart';
type ViewMode = 'list' | 'board' | 'table' | 'dates';

// localStorage keys for per-session UI preferences. macOS persists view +
// sort + status filter across launches; web used to drop them on every
// route remount which made the user reselect Board every time they bounced
// from Inbox → Tasks.
const PREF_VIEW_MODE_KEY = 'tasks.viewMode';
const PREF_SORT_BY_KEY = 'tasks.sortBy';
const PREF_STATUS_FILTER_KEY = 'tasks.statusFilter';
const readPref = <T extends string>(key: string, allowed: readonly T[], fallback: T): T => {
  if (typeof window === 'undefined') return fallback;
  try {
    const raw = localStorage.getItem(key);
    if (raw && (allowed as readonly string[]).includes(raw)) return raw as T;
  } catch {
    // private mode etc — fall through
  }
  return fallback;
};
const writePref = (key: string, value: string) => {
  if (typeof window === 'undefined') return;
  try {
    localStorage.setItem(key, value);
  } catch {
    // ignore
  }
};

// Auth guard
export async function clientLoader({ request }: Route.ClientLoaderArgs) {
  const { redirect } = await import('react-router');
  const session = await authProxy.api.getSession({ headers: request.headers });
  if (!session) throw redirect('/login');
  return {};
}

const PRIORITY_CONFIG: Record<TaskPriority, { label: string; className: string }> = {
  none: { label: 'No priority', className: 'text-muted-foreground bg-muted/50' },
  low: {
    label: 'Low',
    className: 'text-blue-600 bg-blue-50 dark:bg-blue-950/30 dark:text-blue-400',
  },
  medium: {
    label: 'Medium',
    className: 'text-yellow-600 bg-yellow-50 dark:bg-yellow-950/30 dark:text-yellow-400',
  },
  high: { label: 'High', className: 'text-red-600 bg-red-50 dark:bg-red-950/30 dark:text-red-400' },
};

const STATUS_CONFIG: Record<TaskStatus, { label: string; color: string }> = {
  todo: { label: 'To Do', color: 'text-muted-foreground' },
  doing: { label: 'Doing', color: 'text-blue-600 dark:text-blue-400' },
  done: { label: 'Done', color: 'text-green-600 dark:text-green-400' },
};

const BOARD_COLUMNS: { status: TaskStatus; label: string }[] = [
  { status: 'todo', label: 'To Do' },
  { status: 'doing', label: 'Doing' },
  { status: 'done', label: 'Done' },
];

interface TaskFormData {
  title: string;
  description: string;
  status: TaskStatus;
  priority: TaskPriority;
  dueDate: Date | undefined;
  folderId: string | null;
}

const defaultForm: TaskFormData = {
  title: '',
  description: '',
  status: 'todo',
  priority: 'none',
  dueDate: undefined,
  folderId: null,
};

// ─── Main Page ────────────────────────────────────────────────────────────────

export default function TasksPage() {
  const trpc = useTRPC();
  const queryClient = useQueryClient();

  const [viewMode, setViewModeState] = useState<ViewMode>(() =>
    readPref<ViewMode>(PREF_VIEW_MODE_KEY, ['list', 'board', 'table', 'dates'] as const, 'list'),
  );
  const [statusFilter, setStatusFilterState] = useState<TaskStatus | 'all'>(() =>
    readPref<TaskStatus | 'all'>(
      PREF_STATUS_FILTER_KEY,
      ['all', 'todo', 'doing', 'done'] as const,
      'all',
    ),
  );
  const [sortBy, setSortByState] = useState<SortBy>(() =>
    readPref<SortBy>(
      PREF_SORT_BY_KEY,
      ['newest', 'oldest', 'priority', 'smart'] as const,
      'smart',
    ),
  );
  // Wrap the setters to persist on every change without scattering localStorage
  // writes through the JSX. Memoized so dependent useCallbacks stay stable.
  const setViewMode = useCallback((v: ViewMode) => {
    setViewModeState(v);
    writePref(PREF_VIEW_MODE_KEY, v);
  }, []);
  const setStatusFilter = useCallback((v: TaskStatus | 'all') => {
    setStatusFilterState(v);
    writePref(PREF_STATUS_FILTER_KEY, v);
  }, []);
  const setSortBy = useCallback((v: SortBy) => {
    setSortByState(v);
    writePref(PREF_SORT_BY_KEY, v);
  }, []);
  const [activeFolderId, setActiveFolderId] = useState<string | null>(null);
  const [searchText, setSearchText] = useState('');
  // Selected date for the "Dates" calendar grid view. Independent from list
  // state — keeps month-cell focus stable while the user pans the grid.
  const [datesSelected, setDatesSelected] = useState<Date>(() => new Date());

  // Dialog state
  const [dialogOpen, setDialogOpen] = useState(false);
  const [editingTask, setEditingTask] = useState<Task | null>(null);
  const [form, setForm] = useState<TaskFormData>(defaultForm);
  const [calendarOpen, setCalendarOpen] = useState(false);

  // Task detail sheet
  const [detailTask, setDetailTask] = useState<Task | null>(null);

  // Folder dialog
  const [folderDialogOpen, setFolderDialogOpen] = useState(false);
  const [folderName, setFolderName] = useState('');
  const [editingFolder, setEditingFolder] = useState<Folder | null>(null);

  // NLP quick-add mode preference (stored in localStorage inside NlpQuickAdd)

  // Board drag state
  const [activeTaskId, setActiveTaskId] = useState<string | null>(null);

  const { data: foldersData, isFetching: isFetchingFolders } = useQuery(
    trpc.folders.list.queryOptions(void 0, {
      staleTime: 1000 * 60 * 30,
      refetchOnMount: false,
    }),
  );
  const folders = foldersData?.folders ?? [];

  // For board mode we need all statuses; otherwise filter
  const boardMode = viewMode === 'board';
  // Server enum currently knows `newest|oldest|priority`. 'smart' is computed
  // client-side from the data; pass `newest` upstream so the server gives
  // us the chronological set, then bucket it locally.
  const serverSortBy: 'newest' | 'oldest' | 'priority' =
    sortBy === 'smart' ? 'newest' : sortBy;
  const queryInput = {
    ...(statusFilter !== 'all' && !boardMode && { status: statusFilter }),
    ...(activeFolderId && { folderId: activeFolderId }),
    sortBy: serverSortBy,
    limit: 500, // higher for board + table
    ...(searchText && { search: searchText }),
  };

  const { data, isLoading, isFetching } = useQuery(
    trpc.tasks.list.queryOptions(queryInput, {
      staleTime: 1000 * 60 * 5,
      refetchOnMount: false,
    }),
  );
  const tasks = useMemo(() => data?.tasks ?? [], [data]);

  const createMutation = useMutation({
    ...trpc.tasks.create.mutationOptions(),
    onSuccess: ({ task }) => {
      upsertTaskInTaskCaches(queryClient, task);
    },
  });

  const handleCreateTask = useCallback(
    (params: { title: string; dueDate: Date | null; status: string; folderId: string | null }) => {
      createMutation.mutate(
        {
          title: params.title,
          status: params.status as 'todo' | 'doing' | 'done',
          priority: 'none',
          dueDate: params.dueDate ? params.dueDate.toISOString() : null,
          folderId: params.folderId,
        },
        {
          onSuccess: ({ task }) => {
            toast.success(`"${task.title}" created`, {
              description: params.dueDate
                ? `Due ${format(params.dueDate, "EEE d MMM 'at' HH:mm")}`
                : undefined,
              duration: 3000,
            });
          },
        },
      );
    },
    [createMutation],
  );
  const updateMutation = useMutation({
    ...trpc.tasks.update.mutationOptions(),
    onSuccess: ({ task }) => {
      upsertTaskInTaskCaches(queryClient, task);
    },
  });
  const rawDeleteMutation = useMutation({
    ...trpc.tasks.delete.mutationOptions(),
    onSuccess: (_result, variables) => {
      removeTaskFromTaskCaches(queryClient, variables.id);
    },
    onError: (err) => {
      console.error('Failed to delete task:', err);
      toast.error('Could not delete task. Please try again.');
    },
  });
  // Wrap raw delete so every call site (row menu, board card, table action,
  // detail dialog) gets the same confirm step. The previous "instant delete"
  // affordance was easy to fire accidentally from a hover menu with no undo.
  const deleteMutation = useMemo(
    () => ({
      ...rawDeleteMutation,
      mutate: (vars: { id: string }) => {
        if (typeof window !== 'undefined' && !window.confirm('Delete this task?')) return;
        rawDeleteMutation.mutate(vars);
      },
    }),
    [rawDeleteMutation],
  );
  const createFolderMutation = useMutation({
    ...trpc.folders.create.mutationOptions(),
    onSuccess: () => void queryClient.invalidateQueries(trpc.folders.list.queryFilter()),
  });
  const updateFolderMutation = useMutation({
    ...trpc.folders.update.mutationOptions(),
    onSuccess: () => void queryClient.invalidateQueries(trpc.folders.list.queryFilter()),
  });
  const deleteFolderMutation = useMutation(trpc.folders.delete.mutationOptions());

  const openCreate = (prefillStatus?: TaskStatus, prefillDate?: Date) => {
    setEditingTask(null);
    setForm({
      ...defaultForm,
      folderId: activeFolderId,
      status: prefillStatus ?? 'todo',
      dueDate: prefillDate,
    });
    setDialogOpen(true);
  };

  const openEdit = (task: Task) => {
    setEditingTask(task);
    setForm({
      title: task.title,
      description: task.description ?? '',
      status: task.status as TaskStatus,
      priority: task.priority as TaskPriority,
      dueDate: task.dueDate ? new Date(task.dueDate) : undefined,
      folderId: task.folderId ?? null,
    });
    setDialogOpen(true);
  };

  const handleToggle = (task: Task) =>
    updateMutation.mutate({
      id: task.id,
      data: { status: task.status === 'done' ? 'todo' : 'done' },
    });

  const handleSubmit = () => {
    if (!form.title.trim()) return;
    const payload = {
      title: form.title.trim(),
      description: form.description,
      status: form.status,
      priority: form.priority,
      dueDate: form.dueDate ? form.dueDate.toISOString() : null,
      folderId: form.folderId,
    };
    if (editingTask) {
      updateMutation.mutate(
        { id: editingTask.id, data: payload },
        { onSuccess: () => setDialogOpen(false) },
      );
    } else {
      createMutation.mutate(payload, { onSuccess: () => setDialogOpen(false) });
    }
  };


  const handleMoveToFolder = (taskId: string, folderId: string | null) =>
    updateMutation.mutate({ id: taskId, data: { folderId } });

  const handleFolderSubmit = () => {
    if (!folderName.trim()) return;
    if (editingFolder) {
      updateFolderMutation.mutate(
        { id: editingFolder.id, name: folderName.trim() },
        {
          onSuccess: () => {
            setFolderDialogOpen(false);
            setFolderName('');
            setEditingFolder(null);
          },
        },
      );
    } else {
      createFolderMutation.mutate(
        { name: folderName.trim() },
        {
          onSuccess: () => {
            setFolderDialogOpen(false);
            setFolderName('');
          },
        },
      );
    }
  };

  // Accepts both string (ISO) and Date object since tRPC may return either
  const isDueDateWarning = (dueDate: string | Date | null | undefined) => {
    if (!dueDate) return false;
    const d = new Date(dueDate);
    return isPast(d) && !isToday(d);
  };

  // DnD sensors — require 5px of movement before activating
  const sensors = useSensors(useSensor(PointerSensor, { activationConstraint: { distance: 5 } }));

  const handleDragStart = (event: DragStartEvent) => {
    setActiveTaskId(event.active.id as string);
  };

  const handleDragEnd = (event: DragEndEvent) => {
    setActiveTaskId(null);
    const { active, over } = event;
    if (!over) return;
    // `over.id` is the column's `status` string when dropped on a column,
    // OR the sibling task's id when dropped on another card inside the same
    // column. Resolve to a column status either way so dropping onto a
    // sibling card moves the dragged task to that sibling's column instead
    // of silently no-op'ing (which was the previous behavior).
    const overId = String(over.id);
    const isColumnDrop = BOARD_COLUMNS.some((c) => c.status === overId);
    let newStatus: TaskStatus | null = null;
    if (isColumnDrop) {
      newStatus = overId as TaskStatus;
    } else {
      const overTask = tasks.find((t) => t.id === overId);
      if (overTask?.status) newStatus = overTask.status as TaskStatus;
    }
    const task = tasks.find((t) => t.id === active.id);
    if (newStatus && task && task.status !== newStatus) {
      updateMutation.mutate({ id: task.id, data: { status: newStatus } });
    }
  };

  const activeTask = activeTaskId ? tasks.find((t) => t.id === activeTaskId) : null;
  const isBackgroundRefreshing =
    (!!data && !isLoading && isFetching) || (!!foldersData && isFetchingFolders);

  // Board column groups (client-side split)
  const boardGroups = useMemo(() => {
    const result: Record<TaskStatus, Task[]> = { todo: [], doing: [], done: [] };
    for (const task of tasks) {
      const s = task.status as TaskStatus;
      if (result[s]) result[s].push(task);
    }
    return result;
  }, [tasks]);

  const activeFolder = folders.find((f) => f.id === activeFolderId);

  return (
    <div className="bg-background flex h-screen flex-col overflow-hidden">
      {/* ── Header ── */}
      <div className="flex shrink-0 items-center justify-between border-b px-5 py-3">
        <div className="flex items-center gap-2">
          <h1 className="text-xl font-semibold tracking-tight">
            {activeFolder ? activeFolder.name : 'Tasks'}
          </h1>
          {isBackgroundRefreshing ? <BackgroundRefreshIndicator label="Updating tasks" /> : null}
        </div>
        <div className="flex items-center gap-2">
          {/* View mode switcher — matches iOS segmented control */}
          <div className="bg-muted/50 flex items-center gap-0.5 rounded-lg border p-0.5">
            {(
              [
                ['list', List],
                ['board', LayoutGrid],
                ['table', Table2],
                ['dates', CalendarIcon],
              ] as [ViewMode, typeof List][]
            ).map(([mode, Icon]) => (
              <button
                key={mode}
                type="button"
                onClick={() => setViewMode(mode)}
                className={cn(
                  'flex h-7 w-7 items-center justify-center rounded-md transition-colors',
                  'focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring',
                  viewMode === mode
                    ? 'bg-background text-foreground shadow-sm'
                    : 'text-muted-foreground hover:text-foreground',
                )}
                aria-label={`${mode.charAt(0).toUpperCase()}${mode.slice(1)} view`}
                aria-pressed={viewMode === mode}
              >
                <Icon className="h-3.5 w-3.5" />
              </button>
            ))}
          </div>

          {/* Sort — only for list/table (board manages by column; dates uses month grid) */}
          {viewMode !== 'board' && viewMode !== 'dates' && (
            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <Button variant="outline" size="sm" className="h-8 gap-1.5 text-xs">
                  <ArrowUpDown className="h-3.5 w-3.5" />
                  {sortBy === 'newest'
                    ? 'Newest'
                    : sortBy === 'oldest'
                      ? 'Oldest'
                      : sortBy === 'priority'
                        ? 'Priority'
                        : 'Smart'}
                </Button>
              </DropdownMenuTrigger>
              <DropdownMenuContent align="end">
                <DropdownMenuLabel>Sort by</DropdownMenuLabel>
                <DropdownMenuRadioGroup
                  value={sortBy}
                  onValueChange={(v) => setSortBy(v as SortBy)}
                >
                  <DropdownMenuRadioItem value="smart">Smart (Overdue → Today → Later)</DropdownMenuRadioItem>
                  <DropdownMenuRadioItem value="newest">Newest</DropdownMenuRadioItem>
                  <DropdownMenuRadioItem value="oldest">Oldest</DropdownMenuRadioItem>
                  <DropdownMenuRadioItem value="priority">Priority</DropdownMenuRadioItem>
                </DropdownMenuRadioGroup>
              </DropdownMenuContent>
            </DropdownMenu>
          )}

          <Button onClick={() => openCreate()} size="sm" className="h-8 gap-1.5 text-xs">
            <Plus className="h-3.5 w-3.5" />
            New task
          </Button>
        </div>
      </div>

      {/* ── Folder Pill Strip ── */}
      <div className="shrink-0 border-b">
        <div className="scrollbar-none flex items-center gap-1.5 overflow-x-auto px-5 py-2">
          {folders.length > 0 && (
            <>
            {/* All */}
            <button
              type="button"
              onClick={() => setActiveFolderId(null)}
              className={cn(
                'flex shrink-0 items-center gap-1.5 rounded-full border px-3.5 py-1 text-[13px] font-medium transition-colors',
                activeFolderId === null
                  ? 'border-foreground/20 bg-accent text-accent-foreground'
                  : 'border-border text-muted-foreground hover:bg-accent/50 hover:text-foreground bg-transparent',
              )}
            >
              All
            </button>
            {folders.map((folder) => (
              <div key={folder.id} className="group relative flex shrink-0 items-center">
                <button
                  type="button"
                  onClick={() => setActiveFolderId(folder.id)}
                  className={cn(
                    'flex items-center gap-1.5 rounded-full border px-3.5 py-1 text-[13px] font-medium transition-colors',
                    activeFolderId === folder.id
                      ? 'border-foreground/20 bg-accent text-accent-foreground'
                      : 'border-border text-muted-foreground hover:bg-accent/50 hover:text-foreground bg-transparent',
                  )}
                >
                  <FolderIcon className="h-3 w-3" />
                  {folder.name}
                </button>
                {/* Hover manage icon */}
                <DropdownMenu>
                  <DropdownMenuTrigger asChild>
                    <button
                      type="button"
                      className="bg-muted text-muted-foreground absolute -right-1 -top-1 hidden h-4 w-4 items-center justify-center rounded-full shadow group-hover:flex focus-visible:flex focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
                      aria-label={`Manage folder ${folder.name}`}
                    >
                      <X className="h-2.5 w-2.5" />
                    </button>
                  </DropdownMenuTrigger>
                  <DropdownMenuContent>
                    <DropdownMenuItem
                      onClick={() => {
                        setEditingFolder(folder);
                        setFolderName(folder.name);
                        setFolderDialogOpen(true);
                      }}
                    >
                      <Pencil className="mr-2 h-3.5 w-3.5" /> Rename
                    </DropdownMenuItem>
                    <DropdownMenuSeparator />
                    <DropdownMenuItem
                      className="text-destructive focus:text-destructive"
                      onClick={() => {
                        // Confirm before destroying a folder — there is no undo path
                        // and tasks belonging to it lose their folder reference.
                        if (
                          typeof window !== 'undefined' &&
                          !window.confirm(`Delete folder "${folder.name}"? Tasks inside will be unfiled.`)
                        ) {
                          return;
                        }
                        deleteFolderMutation.mutate(
                          { id: folder.id },
                          {
                            onSuccess: () => {
                              void queryClient.invalidateQueries(trpc.folders.list.queryFilter());
                              if (activeFolderId === folder.id) setActiveFolderId(null);
                              if (editingFolder?.id === folder.id) setEditingFolder(null);
                            },
                            onError: (err) => {
                              console.error('Failed to delete folder:', err);
                              toast.error('Could not delete folder. Please try again.');
                            },
                          },
                        );
                      }}
                    >
                      <Trash2 className="mr-2 h-3.5 w-3.5" /> Delete
                    </DropdownMenuItem>
                  </DropdownMenuContent>
                </DropdownMenu>
              </div>
            ))}
            </>
          )}
            {/* New folder */}
            <button
              type="button"
              onClick={() => {
                setEditingFolder(null);
                setFolderName('');
                setFolderDialogOpen(true);
              }}
              className="border-border text-muted-foreground hover:border-foreground/30 hover:text-foreground flex shrink-0 items-center gap-1 rounded-full border border-dashed px-3 py-1 text-[13px] transition-colors"
            >
              <FolderPlus className="h-3 w-3" />
              Add folder
            </button>
        </div>
      </div>

      {/* ── Search + Filter Bar (List / Table only) ── */}
      {viewMode !== 'board' && viewMode !== 'dates' && (
        <div className="flex shrink-0 items-center gap-2 border-b px-5 py-2">
          <div className="relative flex-1">
            <input
              value={searchText}
              onChange={(e) => setSearchText(e.target.value)}
              placeholder="Search tasks…"
              aria-label="Search tasks"
              className="bg-muted/50 placeholder:text-muted-foreground focus-visible:ring-ring h-8 w-full rounded-full border px-3 text-[13px] focus:outline-none focus-visible:ring-1"
            />
          </div>
          {/* Status filter tabs */}
          <div className="bg-muted/50 flex items-center gap-0.5 rounded-lg border p-0.5" role="group" aria-label="Filter tasks by status">
            {(['all', 'todo', 'doing', 'done'] as const).map((s) => (
              <button
                key={s}
                type="button"
                onClick={() => setStatusFilter(s)}
                aria-pressed={statusFilter === s}
                className={cn(
                  'rounded-md px-2.5 py-1 text-[12px] font-medium transition-colors',
                  'focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring',
                  statusFilter === s
                    ? 'bg-background text-foreground shadow-sm'
                    : 'text-muted-foreground hover:text-foreground',
                )}
              >
                {s === 'all' ? 'All' : STATUS_CONFIG[s].label}
              </button>
            ))}
          </div>
        </div>
      )}

      {/* ── Content Area ── */}
      <div className="flex-1 overflow-hidden">
        {viewMode === 'list' && (
          <ListContent
            tasks={tasks}
            folders={folders}
            isLoading={isLoading}
            defaultStatus={statusFilter}
            activeFolderId={activeFolderId}
            onCreateTask={handleCreateTask}
            isCreating={createMutation.isPending}
            onToggle={handleToggle}
            onEdit={openEdit}
            onDelete={(id) => deleteMutation.mutate({ id })}
            onMoveToFolder={handleMoveToFolder}
            onOpenDetail={setDetailTask}
            onOpenCreate={openCreate}
            isDueDateWarning={isDueDateWarning}
            useSmartBuckets={sortBy === 'smart'}
          />
        )}

        {viewMode === 'board' && (
          <DndContext
            sensors={sensors}
            collisionDetection={closestCenter}
            onDragStart={handleDragStart}
            onDragEnd={handleDragEnd}
          >
            <div className="flex h-full gap-3 overflow-x-auto p-4">
              {BOARD_COLUMNS.map(({ status, label }) => (
                <BoardColumn
                  key={status}
                  status={status}
                  label={label}
                  tasks={boardGroups[status]}
                  folders={folders}
                  onEdit={openEdit}
                  onDelete={(id) => deleteMutation.mutate({ id })}
                  onOpenDetail={setDetailTask}
                  onQuickCreate={(s) => openCreate(s)}
                />
              ))}
            </div>
            <DragOverlay>
              {activeTask ? (
                <BoardCard
                  task={activeTask}
                  isDragging
                  folders={folders}
                  onEdit={() => {}}
                  onDelete={() => {}}
                  onOpenDetail={() => {}}
                />
              ) : null}
            </DragOverlay>
          </DndContext>
        )}

        {viewMode === 'table' && (
          <TableContent
            tasks={tasks}
            folders={folders}
            isLoading={isLoading}
            onToggle={handleToggle}
            onEdit={openEdit}
            onDelete={(id) => deleteMutation.mutate({ id })}
            onMoveToFolder={handleMoveToFolder}
            onOpenCreate={openCreate}
          />
        )}

        {viewMode === 'dates' && (
          // Dates view: month grid keyed off task `dueDate`. Clicking a task
          // chip opens the existing detail panel; clicking an empty day cell
          // (double-click) prefills the create dialog with that date.
          <div className="flex h-full flex-col">
            {/* Quick-add row — mirrors the NLP quick-add input on list view so
                users can capture from this view without clicking a cell.
                Respect the current `statusFilter` so quick-add captures land
                where the user expects (consistent with list view). */}
            <div className="border-b px-5 py-2">
              <NlpQuickAdd
                defaultStatus={statusFilter}
                folderId={activeFolderId}
                onSubmit={handleCreateTask}
                isSubmitting={createMutation.isPending}
              />
            </div>
            <div className="min-h-0 flex-1">
              <CalendarGrid
                mode="month"
                events={[]}
                tasks={tasks.map((t) => ({
                  id: t.id,
                  title: t.title,
                  dueDate: t.dueDate,
                  status: t.status,
                }))}
                selectedDate={datesSelected}
                onSelectDate={setDatesSelected}
                onTaskClick={(taskId) => {
                  const t = tasks.find((task) => task.id === taskId);
                  if (t) setDetailTask(t);
                }}
                onCreateAt={(start) => openCreate('todo', start)}
              />
            </div>
          </div>
        )}
      </div>

      {/* ── Task Detail Side Panel ── */}
      <Sheet
        modal={false}
        open={!!detailTask}
        onOpenChange={(open) => !open && setDetailTask(null)}
      >
        <SheetContent
          side="right"
          hideOverlay
          // Side panel: stays interactive with the rest of the page, no outside-click close,
          // no scroll lock, no Escape close — closes only via the explicit Close button.
          onPointerDownOutside={(e) => e.preventDefault()}
          onInteractOutside={(e) => e.preventDefault()}
          onEscapeKeyDown={(e) => e.preventDefault()}
          className="w-[400px] overflow-y-auto sm:max-w-[400px]"
        >
          {detailTask && (
            <TaskDetailPanel
              task={detailTask}
              folders={folders}
              onEdit={openEdit}
              onToggle={handleToggle}
              onDelete={(id) => {
                deleteMutation.mutate({ id });
                setDetailTask(null);
              }}
            />
          )}
        </SheetContent>
      </Sheet>

      {/* ── Create / Edit Task Dialog ── */}
      <TaskDialog
        open={dialogOpen}
        onOpenChange={setDialogOpen}
        editingTask={editingTask}
        form={form}
        setForm={setForm}
        calendarOpen={calendarOpen}
        setCalendarOpen={setCalendarOpen}
        folders={folders}
        onSubmit={handleSubmit}
        isPending={createMutation.isPending || updateMutation.isPending}
      />

      {/* ── Folder Dialog ── */}
      <Dialog
        open={folderDialogOpen}
        onOpenChange={(open) => {
          setFolderDialogOpen(open);
          if (!open) {
            setFolderName('');
            setEditingFolder(null);
          }
        }}
      >
        <DialogContent className="sm:max-w-sm">
          <DialogHeader>
            <DialogTitle>{editingFolder ? 'Rename folder' : 'New folder'}</DialogTitle>
          </DialogHeader>
          <div className="py-2">
            <Input
              placeholder="Folder name"
              value={folderName}
              onChange={(e) => setFolderName(e.target.value)}
              onKeyDown={(e) => e.key === 'Enter' && handleFolderSubmit()}
              autoFocus
            />
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setFolderDialogOpen(false)}>
              Cancel
            </Button>
            <Button
              onClick={handleFolderSubmit}
              disabled={
                !folderName.trim() ||
                createFolderMutation.isPending ||
                updateFolderMutation.isPending
              }
            >
              {editingFolder ? 'Rename' : 'Create folder'}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}

// ─── List Content ─────────────────────────────────────────────────────────────

// Smart sort buckets — mirror the macOS `TaskSmartSort` semantics so users
// see the same "what to do next" surface across platforms.
type SmartBucket = 'overdue' | 'today' | 'thisWeek' | 'later' | 'noDate' | 'done';
const SMART_BUCKET_LABEL: Record<SmartBucket, string> = {
  overdue: 'Overdue',
  today: 'Today',
  thisWeek: 'This week',
  later: 'Later',
  noDate: 'No due date',
  done: 'Done',
};
const SMART_BUCKET_ORDER: SmartBucket[] = [
  'overdue',
  'today',
  'thisWeek',
  'later',
  'noDate',
  'done',
];
function bucketForTask(task: Task, now: Date): SmartBucket {
  if (task.status === 'done') return 'done';
  if (!task.dueDate) return 'noDate';
  const due = new Date(task.dueDate);
  if (Number.isNaN(due.getTime())) return 'noDate';
  const startOfToday = new Date(now);
  startOfToday.setHours(0, 0, 0, 0);
  const startOfTomorrow = new Date(startOfToday);
  startOfTomorrow.setDate(startOfTomorrow.getDate() + 1);
  const endOfWeek = new Date(startOfToday);
  endOfWeek.setDate(endOfWeek.getDate() + 7);
  if (due < startOfToday) return 'overdue';
  if (due < startOfTomorrow) return 'today';
  if (due < endOfWeek) return 'thisWeek';
  return 'later';
}

function ListContent({
  tasks,
  folders,
  isLoading,
  defaultStatus,
  activeFolderId,
  onCreateTask,
  isCreating,
  onToggle,
  onEdit,
  onDelete,
  onMoveToFolder,
  onOpenDetail,
  onOpenCreate,
  isDueDateWarning,
  useSmartBuckets,
}: {
  tasks: Task[];
  folders: Folder[];
  isLoading: boolean;
  defaultStatus: TaskStatus | 'all';
  activeFolderId: string | null;
  onCreateTask: (p: { title: string; dueDate: Date | null; status: string; folderId: string | null }) => void;
  isCreating: boolean;
  onToggle: (t: Task) => void;
  onEdit: (t: Task) => void;
  onDelete: (id: string) => void;
  onMoveToFolder: (taskId: string, folderId: string | null) => void;
  onOpenDetail: (t: Task) => void;
  onOpenCreate: () => void;
  isDueDateWarning: (d: string | Date | null | undefined) => boolean;
  useSmartBuckets?: boolean;
}) {
  const buckets = useMemo(() => {
    if (!useSmartBuckets) return null;
    const now = new Date();
    const grouped = new Map<SmartBucket, Task[]>();
    for (const task of tasks) {
      const b = bucketForTask(task, now);
      const arr = grouped.get(b) ?? [];
      arr.push(task);
      grouped.set(b, arr);
    }
    // Sort each bucket: overdue+today by date asc, others by date asc then title.
    for (const [b, list] of grouped) {
      list.sort((a, b2) => {
        const aDate = a.dueDate ? new Date(a.dueDate).getTime() : Number.POSITIVE_INFINITY;
        const bDate = b2.dueDate ? new Date(b2.dueDate).getTime() : Number.POSITIVE_INFINITY;
        if (aDate !== bDate) return aDate - bDate;
        return (a.title ?? '').localeCompare(b2.title ?? '');
      });
      grouped.set(b, list);
    }
    return grouped;
  }, [tasks, useSmartBuckets]);
  return (
    <ScrollArea className="h-full">
      <div className="space-y-1 px-5 py-3">
        <NlpQuickAdd
          defaultStatus={defaultStatus}
          folderId={activeFolderId}
          onSubmit={onCreateTask}
          isSubmitting={isCreating}
        />

        {isLoading ? (
          ['list-skeleton-1', 'list-skeleton-2', 'list-skeleton-3', 'list-skeleton-4', 'list-skeleton-5'].map((key) => (
            <div key={key} className="bg-muted/50 h-16 animate-pulse rounded-xl" />
          ))
        ) : tasks.length === 0 ? (
          <div className="flex flex-col items-center justify-center gap-3 py-16 text-center">
            <div className="bg-muted flex h-12 w-12 items-center justify-center rounded-full">
              <CheckCircle2 className="text-muted-foreground h-6 w-6" />
            </div>
            <div>
              <p className="font-medium">No tasks yet</p>
              <p className="text-muted-foreground text-sm">Create your first task to get started</p>
            </div>
            <Button onClick={onOpenCreate} size="sm" variant="outline">
              <Plus className="mr-1.5 h-4 w-4" />
              New task
            </Button>
          </div>
        ) : useSmartBuckets && buckets ? (
          SMART_BUCKET_ORDER.flatMap((bucket) => {
            const list = buckets.get(bucket) ?? [];
            if (list.length === 0) return [];
            return [
              <div
                key={`bucket-${bucket}`}
                className="text-muted-foreground sticky top-0 z-10 bg-background/95 pb-1 pt-3 text-[11px] font-semibold uppercase tracking-wider backdrop-blur"
              >
                {SMART_BUCKET_LABEL[bucket]}
                <span className="ml-1.5 opacity-60">({list.length})</span>
              </div>,
              ...list.map((task) => (
                <TaskRow
                  key={task.id}
                  task={task}
                  folders={folders}
                  onToggle={onToggle}
                  onEdit={onEdit}
                  onDelete={onDelete}
                  onMoveToFolder={onMoveToFolder}
                  onOpenDetail={onOpenDetail}
                  isDueDateWarning={isDueDateWarning(task.dueDate)}
                />
              )),
            ];
          })
        ) : (
          tasks.map((task) => (
            <TaskRow
              key={task.id}
              task={task}
              folders={folders}
              onToggle={onToggle}
              onEdit={onEdit}
              onDelete={onDelete}
              onMoveToFolder={onMoveToFolder}
              onOpenDetail={onOpenDetail}
              isDueDateWarning={isDueDateWarning(task.dueDate)}
            />
          ))
        )}
      </div>
    </ScrollArea>
  );
}

// ─── TaskRow (List View) ──────────────────────────────────────────────────────

function TaskRow({
  task,
  folders,
  onToggle,
  onEdit,
  onDelete,
  onMoveToFolder,
  onOpenDetail,
  isDueDateWarning,
}: {
  task: Task;
  folders: Folder[];
  onToggle: (t: Task) => void;
  onEdit: (t: Task) => void;
  onDelete: (id: string) => void;
  onMoveToFolder: (taskId: string, folderId: string | null) => void;
  onOpenDetail: (t: Task) => void;
  isDueDateWarning: boolean;
}) {
  const isDone = task.status === 'done';
  const priority = task.priority as TaskPriority;

  return (
    <div
      className={cn(
        'border-border bg-card hover:border-border/80 hover:bg-accent/20 group flex items-start gap-3 rounded-xl border px-3.5 py-3 transition-colors',
        isDone && 'opacity-60',
      )}
    >
      <button
        type="button"
        onClick={() => onToggle(task)}
        className="text-muted-foreground hover:text-primary mt-0.5 shrink-0 transition-colors"
      >
        {isDone ? (
          <CheckCircle2 className="h-4.5 w-4.5 text-primary" />
        ) : (
          <Circle className="h-4.5 w-4.5" />
        )}
      </button>

      <button type="button" className="min-w-0 flex-1 text-left" onClick={() => onOpenDetail(task)}>
        <p
          className={cn(
            'text-sm font-medium leading-snug',
            isDone && 'text-muted-foreground line-through',
          )}
        >
          {task.title}
        </p>
        {task.description && (
          <p className="text-muted-foreground mt-0.5 line-clamp-1 text-xs">{task.description}</p>
        )}
        <div className="mt-1.5 flex flex-wrap items-center gap-1.5">
          {priority !== 'none' && (
            <Badge
              variant="secondary"
              className={cn(
                'h-4 rounded-md border-0 px-1.5 text-[10px] font-medium',
                PRIORITY_CONFIG[priority].className,
              )}
            >
              {PRIORITY_CONFIG[priority].label}
            </Badge>
          )}
          {task.status !== 'todo' && (
            <Badge
              variant="outline"
              className={cn(
                'h-4 rounded-md px-1.5 text-[10px] font-medium',
                STATUS_CONFIG[task.status as TaskStatus]?.color,
              )}
            >
              {STATUS_CONFIG[task.status as TaskStatus]?.label}
            </Badge>
          )}
          {task.dueDate && (
            <span
              className={cn(
                'flex items-center gap-0.5 text-[10px] font-medium',
                isDueDateWarning ? 'text-red-500' : 'text-muted-foreground',
              )}
            >
              <CalendarIcon className="h-3 w-3" />
              {isToday(new Date(task.dueDate)) ? 'Today' : format(new Date(task.dueDate), 'MMM d')}
            </span>
          )}
          {task.folderId && folders.length > 0 && (
            <span className="text-muted-foreground flex items-center gap-0.5 text-[10px]">
              <FolderIcon className="h-3 w-3" />
              {folders.find((f) => f.id === task.folderId)?.name}
            </span>
          )}
        </div>
      </button>

      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <Button
            variant="ghost"
            size="icon"
            className="h-7 w-7 shrink-0 opacity-0 group-hover:opacity-100"
          >
            <MoreHorizontal className="h-4 w-4" />
          </Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end" className="w-44">
          <DropdownMenuItem onClick={() => onEdit(task)}>
            <Pencil className="mr-2 h-3.5 w-3.5" />
            Edit
          </DropdownMenuItem>
          {folders.length > 0 && (
            <DropdownMenuSub>
              <DropdownMenuSubTrigger>
                <FolderIcon className="mr-2 h-3.5 w-3.5" />
                Move to folder
              </DropdownMenuSubTrigger>
              <DropdownMenuSubContent>
                <DropdownMenuItem onClick={() => onMoveToFolder(task.id, null)}>
                  <CheckCircle2 className="mr-2 h-3.5 w-3.5" />
                  No folder
                </DropdownMenuItem>
                <DropdownMenuSeparator />
                {folders.map((folder) => (
                  <DropdownMenuItem
                    key={folder.id}
                    onClick={() => onMoveToFolder(task.id, folder.id)}
                  >
                    <FolderIcon className="mr-2 h-3.5 w-3.5" />
                    {folder.name}
                  </DropdownMenuItem>
                ))}
              </DropdownMenuSubContent>
            </DropdownMenuSub>
          )}
          <DropdownMenuSeparator />
          <DropdownMenuItem
            className="text-destructive focus:text-destructive"
            onClick={() => onDelete(task.id)}
          >
            <Trash2 className="mr-2 h-3.5 w-3.5" />
            Delete
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>
    </div>
  );
}

// ─── Board View ───────────────────────────────────────────────────────────────

function BoardColumn({
  status,
  label,
  tasks,
  folders,
  onEdit,
  onDelete,
  onOpenDetail,
  onQuickCreate,
}: {
  status: TaskStatus;
  label: string;
  tasks: Task[];
  folders: Folder[];
  onEdit: (t: Task) => void;
  onDelete: (id: string) => void;
  onOpenDetail: (t: Task) => void;
  onQuickCreate: (s: TaskStatus) => void;
}) {
  const { setNodeRef, isOver } = useDroppable({ id: status });

  return (
    <div
      ref={setNodeRef}
      className={cn(
        'bg-muted/30 flex h-full w-72 shrink-0 flex-col rounded-xl border transition-colors',
        isOver && 'border-primary/50 bg-accent/30',
      )}
    >
      {/* Column header */}
      <div className="flex items-center justify-between px-3 py-2.5">
        <div className="flex items-center gap-2">
          <span className="text-[13px] font-semibold">{label}</span>
          <span className="bg-muted text-muted-foreground flex h-4 min-w-[1rem] items-center justify-center rounded-full px-1 text-[10px] font-bold">
            {tasks.length}
          </span>
        </div>
        <Button
          variant="ghost"
          size="icon"
          className="h-6 w-6"
          onClick={() => onQuickCreate(status)}
          aria-label={`Add task to ${label}`}
        >
          <Plus className="h-3.5 w-3.5" />
        </Button>
      </div>

      {/* Cards */}
      <SortableContext items={tasks.map((t) => t.id)} strategy={verticalListSortingStrategy}>
        <ScrollArea className="flex-1">
          <div className="space-y-1.5 px-2 pb-2">
            {tasks.map((task) => (
              <BoardCard
                key={task.id}
                task={task}
                folders={folders}
                onEdit={onEdit}
                onDelete={onDelete}
                onOpenDetail={onOpenDetail}
              />
            ))}
            {tasks.length === 0 && (
              <div className="border-border text-muted-foreground flex h-16 items-center justify-center rounded-lg border border-dashed text-xs">
                Drop tasks here
              </div>
            )}
          </div>
        </ScrollArea>
      </SortableContext>
    </div>
  );
}

function BoardCard({
  task,
  folders,
  onEdit,
  onDelete,
  onOpenDetail,
  isDragging,
}: {
  task: Task;
  folders: Folder[];
  onEdit: (t: Task) => void;
  onDelete: (id: string) => void;
  onOpenDetail: (t: Task) => void;
  isDragging?: boolean;
}) {
  const {
    attributes,
    listeners,
    setNodeRef,
    transform,
    transition,
    isDragging: isSortableDragging,
  } = useSortable({ id: task.id });

  const style = {
    transform: CSS.Transform.toString(transform),
    transition,
    opacity: isSortableDragging ? 0.4 : 1,
  };

  const priority = task.priority as TaskPriority;

  return (
    <div
      ref={setNodeRef}
      style={style}
      className={cn(
        'border-border bg-card group relative rounded-lg border px-3 py-2.5 shadow-sm transition-shadow',
        isDragging && 'rotate-1 shadow-md',
      )}
    >
      {/* Drag handle */}
      <div
        {...attributes}
        {...listeners}
        className="absolute left-1 top-1/2 -translate-y-1/2 cursor-grab touch-none opacity-0 group-hover:opacity-100"
      >
        <GripVertical className="text-muted-foreground h-3.5 w-3.5" />
      </div>

      <button type="button" className="w-full text-left" onClick={() => onOpenDetail(task)}>
        <p className="text-[13px] font-medium leading-snug">{task.title}</p>
        {task.description && (
          <p className="text-muted-foreground mt-0.5 line-clamp-2 text-[11px]">
            {task.description}
          </p>
        )}
      </button>

      <div className="mt-2 flex flex-wrap items-center gap-1.5">
        {priority !== 'none' && (
          <Badge
            variant="secondary"
            className={cn(
              'h-4 rounded border-0 px-1.5 text-[10px] font-medium',
              PRIORITY_CONFIG[priority].className,
            )}
          >
            {PRIORITY_CONFIG[priority].label}
          </Badge>
        )}
        {task.dueDate && (
          <span className="text-muted-foreground flex items-center gap-0.5 text-[10px]">
            <CalendarIcon className="h-3 w-3" />
            {isToday(new Date(task.dueDate)) ? 'Today' : format(new Date(task.dueDate), 'MMM d')}
          </span>
        )}
        {task.folderId && folders.length > 0 && (
          <span className="text-muted-foreground flex items-center gap-0.5 text-[10px]">
            <FolderIcon className="h-3 w-3" />
            {folders.find((f) => f.id === task.folderId)?.name}
          </span>
        )}
      </div>

      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <Button
            variant="ghost"
            size="icon"
            className="absolute right-1 top-1 h-6 w-6 opacity-0 group-hover:opacity-100"
          >
            <MoreHorizontal className="h-3.5 w-3.5" />
          </Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end" className="w-36">
          <DropdownMenuItem onClick={() => onEdit(task)}>
            <Pencil className="mr-2 h-3.5 w-3.5" />
            Edit
          </DropdownMenuItem>
          <DropdownMenuSeparator />
          <DropdownMenuItem
            className="text-destructive focus:text-destructive"
            onClick={() => onDelete(task.id)}
          >
            <Trash2 className="mr-2 h-3.5 w-3.5" />
            Delete
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>
    </div>
  );
}

// ─── Table View ───────────────────────────────────────────────────────────────

function TableContent({
  tasks,
  folders,
  isLoading,
  onToggle,
  onEdit,
  onDelete,
  onMoveToFolder,
  onOpenCreate,
}: {
  tasks: Task[];
  folders: Folder[];
  isLoading: boolean;
  onToggle: (t: Task) => void;
  onEdit: (t: Task) => void;
  onDelete: (id: string) => void;
  onMoveToFolder: (taskId: string, folderId: string | null) => void;
  onOpenCreate: () => void;
}) {
  return (
    <ScrollArea className="h-full">
      <table className="w-full text-sm">
        <thead>
          <tr className="bg-muted/30 text-muted-foreground border-b text-left text-[11px] font-semibold uppercase tracking-wide">
            <th className="w-8 px-4 py-2" />
            <th className="px-2 py-2">Title</th>
            <th className="w-24 px-2 py-2">Priority</th>
            <th className="w-24 px-2 py-2">Status</th>
            <th className="w-24 px-2 py-2">Due</th>
            <th className="w-28 px-2 py-2">Folder</th>
            <th className="w-8 px-4 py-2" />
          </tr>
        </thead>
        <tbody className="divide-y">
          {isLoading ? (
            ['table-skeleton-1', 'table-skeleton-2', 'table-skeleton-3', 'table-skeleton-4', 'table-skeleton-5', 'table-skeleton-6'].map((key) => (
              <tr key={key}>
                <td colSpan={7}>
                  <div className="bg-muted/50 mx-4 my-1 h-8 animate-pulse rounded" />
                </td>
              </tr>
            ))
          ) : tasks.length === 0 ? (
            <tr>
              <td colSpan={7}>
                <div className="flex flex-col items-center justify-center gap-3 py-16 text-center">
                  <p className="text-sm font-medium">No tasks</p>
                  <Button onClick={onOpenCreate} size="sm" variant="outline">
                    <Plus className="mr-1.5 h-4 w-4" />
                    New task
                  </Button>
                </div>
              </td>
            </tr>
          ) : (
            tasks.map((task) => {
              const isDone = task.status === 'done';
              const priority = task.priority as TaskPriority;
              const folder = folders.find((f) => f.id === task.folderId);
              return (
                <tr
                  key={task.id}
                  className={cn(
                    'hover:bg-accent/20 group transition-colors',
                    isDone && 'opacity-50',
                  )}
                >
                  <td className="px-4 py-2">
                    <button
                      type="button"
                      onClick={() => onToggle(task)}
                      className="text-muted-foreground hover:text-primary"
                    >
                      {isDone ? (
                        <CheckCircle2 className="text-primary h-4 w-4" />
                      ) : (
                        <Circle className="h-4 w-4" />
                      )}
                    </button>
                  </td>
                  <td className="max-w-0 px-2 py-2">
                    <p
                      className={cn(
                        'truncate text-[13px] font-medium',
                        isDone && 'text-muted-foreground line-through',
                      )}
                    >
                      {task.title}
                    </p>
                  </td>
                  <td className="px-2 py-2">
                    {priority !== 'none' && (
                      <Badge
                        variant="secondary"
                        className={cn(
                          'h-4 rounded border-0 px-1.5 text-[10px]',
                          PRIORITY_CONFIG[priority].className,
                        )}
                      >
                        {PRIORITY_CONFIG[priority].label}
                      </Badge>
                    )}
                  </td>
                  <td
                    className={cn(
                      'px-2 py-2 text-[12px]',
                      STATUS_CONFIG[task.status as TaskStatus]?.color,
                    )}
                  >
                    {STATUS_CONFIG[task.status as TaskStatus]?.label}
                  </td>
                  <td className="text-muted-foreground px-2 py-2 text-[12px]">
                    {task.dueDate && format(new Date(task.dueDate), 'MMM d')}
                  </td>
                  <td className="text-muted-foreground px-2 py-2 text-[12px]">{folder?.name}</td>
                  <td className="px-4 py-2">
                    <DropdownMenu>
                      <DropdownMenuTrigger asChild>
                        <Button
                          variant="ghost"
                          size="icon"
                          className="h-6 w-6 opacity-0 group-hover:opacity-100"
                        >
                          <MoreHorizontal className="h-3.5 w-3.5" />
                        </Button>
                      </DropdownMenuTrigger>
                      <DropdownMenuContent align="end" className="w-44">
                        <DropdownMenuItem onClick={() => onEdit(task)}>
                          <Pencil className="mr-2 h-3.5 w-3.5" />
                          Edit
                        </DropdownMenuItem>
                        {folders.length > 0 && (
                          <DropdownMenuSub>
                            <DropdownMenuSubTrigger>
                              <FolderIcon className="mr-2 h-3.5 w-3.5" />
                              Move to folder
                            </DropdownMenuSubTrigger>
                            <DropdownMenuSubContent>
                              <DropdownMenuItem onClick={() => onMoveToFolder(task.id, null)}>
                                <CheckCircle2 className="mr-2 h-3.5 w-3.5" />
                                No folder
                              </DropdownMenuItem>
                              <DropdownMenuSeparator />
                              {folders.map((folder) => (
                                <DropdownMenuItem
                                  key={folder.id}
                                  onClick={() => onMoveToFolder(task.id, folder.id)}
                                >
                                  <FolderIcon className="mr-2 h-3.5 w-3.5" />
                                  {folder.name}
                                </DropdownMenuItem>
                              ))}
                            </DropdownMenuSubContent>
                          </DropdownMenuSub>
                        )}
                        <DropdownMenuSeparator />
                        <DropdownMenuItem
                          className="text-destructive focus:text-destructive"
                          onClick={() => onDelete(task.id)}
                        >
                          <Trash2 className="mr-2 h-3.5 w-3.5" />
                          Delete
                        </DropdownMenuItem>
                      </DropdownMenuContent>
                    </DropdownMenu>
                  </td>
                </tr>
              );
            })
          )}
        </tbody>
      </table>
    </ScrollArea>
  );
}

// ─── Task Detail Panel ────────────────────────────────────────────────────────

function TaskDetailPanel({
  task,
  folders,
  onEdit,
  onToggle,
  onDelete,
}: {
  task: Task;
  folders: Folder[];
  onEdit: (t: Task) => void;
  onToggle: (t: Task) => void;
  onDelete: (id: string) => void;
}) {
  const priority = task.priority as TaskPriority;
  const folder = folders.find((f) => f.id === task.folderId);

  return (
    <>
      <SheetHeader className="mb-4">
        <SheetTitle className="text-left">Task Details</SheetTitle>
      </SheetHeader>

      <div className="flex flex-col gap-4">
        {/* Title + toggle */}
        <div className="flex items-start gap-3">
          <button
            type="button"
            onClick={() => onToggle(task)}
            className="text-muted-foreground hover:text-primary mt-1 shrink-0"
          >
            {task.status === 'done' ? (
              <CheckCircle2 className="text-primary h-5 w-5" />
            ) : (
              <Circle className="h-5 w-5" />
            )}
          </button>
          <h2
            className={cn(
              'text-base font-semibold leading-snug',
              task.status === 'done' && 'text-muted-foreground line-through',
            )}
          >
            {task.title}
          </h2>
        </div>

        {/* Description */}
        {task.description && (
          <p className="text-muted-foreground text-sm leading-relaxed">{task.description}</p>
        )}

        {/* Metadata */}
        <div className="bg-muted/30 flex flex-col gap-2 rounded-xl border p-3 text-sm">
          <div className="flex items-center justify-between">
            <span className="text-muted-foreground text-xs">Status</span>
            <span
              className={cn('text-xs font-medium', STATUS_CONFIG[task.status as TaskStatus]?.color)}
            >
              {STATUS_CONFIG[task.status as TaskStatus]?.label}
            </span>
          </div>
          {priority !== 'none' && (
            <div className="flex items-center justify-between">
              <span className="text-muted-foreground text-xs">Priority</span>
              <Badge
                variant="secondary"
                className={cn(
                  'h-4 rounded border-0 px-1.5 text-[10px]',
                  PRIORITY_CONFIG[priority].className,
                )}
              >
                {PRIORITY_CONFIG[priority].label}
              </Badge>
            </div>
          )}
          {task.dueDate && (
            <div className="flex items-center justify-between">
              <span className="text-muted-foreground text-xs">Due date</span>
              <span className="text-xs font-medium">{format(new Date(task.dueDate), 'PPP')}</span>
            </div>
          )}
          {folder && (
            <div className="flex items-center justify-between">
              <span className="text-muted-foreground text-xs">Folder</span>
              <span className="flex items-center gap-1 text-xs font-medium">
                <FolderIcon className="h-3 w-3" />
                {folder.name}
              </span>
            </div>
          )}
          {(() => {
            const createdAt = task.createdAt ? new Date(task.createdAt) : null;

            return createdAt && !Number.isNaN(createdAt.getTime()) ? (
              <div className="flex items-center justify-between">
                <span className="text-muted-foreground text-xs">Created</span>
                <span className="text-muted-foreground text-xs">{format(createdAt, 'PPP')}</span>
              </div>
            ) : null;
          })()}
        </div>

        {/* Actions */}
        <div className="flex gap-2">
          <Button variant="outline" className="flex-1" onClick={() => onEdit(task)}>
            <Pencil className="mr-1.5 h-4 w-4" />
            Edit
          </Button>
          <Button variant="destructive" size="icon" onClick={() => onDelete(task.id)}>
            <Trash2 className="h-4 w-4" />
          </Button>
        </div>
      </div>
    </>
  );
}

// ─── Task Dialog ──────────────────────────────────────────────────────────────

function TaskDialog({
  open,
  onOpenChange,
  editingTask,
  form,
  setForm,
  calendarOpen,
  setCalendarOpen,
  folders,
  onSubmit,
  isPending,
}: {
  open: boolean;
  onOpenChange: (v: boolean) => void;
  editingTask: Task | null;
  form: TaskFormData;
  setForm: React.Dispatch<React.SetStateAction<TaskFormData>>;
  calendarOpen: boolean;
  setCalendarOpen: (v: boolean) => void;
  folders: Folder[];
  onSubmit: () => void;
  isPending: boolean;
}) {
  return (
    <Sheet modal={false} open={open} onOpenChange={onOpenChange}>
      <SheetContent
        side="right"
        hideOverlay
        // Non-modal: page stays interactive while creating/editing a task.
        onPointerDownOutside={(e) => e.preventDefault()}
        onInteractOutside={(e) => e.preventDefault()}
        onEscapeKeyDown={(e) => e.preventDefault()}
        className="flex w-[420px] flex-col gap-0 overflow-y-auto p-0 sm:max-w-[420px]"
      >
        <SheetHeader className="border-b px-6 py-4">
          <SheetTitle>{editingTask ? 'Edit task' : 'New task'}</SheetTitle>
        </SheetHeader>

        <div className="flex flex-1 flex-col gap-4 overflow-y-auto px-6 py-4">
          <Input
            placeholder="Task title"
            value={form.title}
            onChange={(e) => setForm((f) => ({ ...f, title: e.target.value }))}
            onKeyDown={(e) => e.key === 'Enter' && onSubmit()}
            autoFocus
          />
          <Textarea
            placeholder="Description (optional)"
            value={form.description}
            onChange={(e) => setForm((f) => ({ ...f, description: e.target.value }))}
            className="min-h-[80px] resize-none"
          />
          <div className="grid grid-cols-2 gap-3">
            <div className="flex flex-col gap-1.5">
              <label className="text-muted-foreground text-xs font-medium">Priority</label>
              <Select
                value={form.priority}
                onValueChange={(v) => setForm((f) => ({ ...f, priority: v as TaskPriority }))}
              >
                <SelectTrigger className="h-9 text-sm">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="none">No priority</SelectItem>
                  <SelectItem value="low">Low</SelectItem>
                  <SelectItem value="medium">Medium</SelectItem>
                  <SelectItem value="high">High</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div className="flex flex-col gap-1.5">
              <label className="text-muted-foreground text-xs font-medium">Status</label>
              <Select
                value={form.status}
                onValueChange={(v) => setForm((f) => ({ ...f, status: v as TaskStatus }))}
              >
                <SelectTrigger className="h-9 text-sm">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="todo">To Do</SelectItem>
                  <SelectItem value="doing">Doing</SelectItem>
                  <SelectItem value="done">Done</SelectItem>
                </SelectContent>
              </Select>
            </div>
          </div>
          {folders.length > 0 && (
            <div className="flex flex-col gap-1.5">
              <label className="text-muted-foreground text-xs font-medium">Folder (optional)</label>
              <Select
                value={form.folderId ?? 'none'}
                onValueChange={(v) => setForm((f) => ({ ...f, folderId: v === 'none' ? null : v }))}
              >
                <SelectTrigger className="h-9 text-sm">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="none">No folder</SelectItem>
                  {folders.map((folder) => (
                    <SelectItem key={folder.id} value={folder.id}>
                      {folder.name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          )}
          <div className="flex flex-col gap-1.5">
            <label className="text-muted-foreground text-xs font-medium">Due date (optional)</label>
            <Popover open={calendarOpen} onOpenChange={setCalendarOpen}>
              <PopoverTrigger asChild>
                <Button
                  variant="outline"
                  className={cn(
                    'h-9 justify-start text-left text-sm font-normal',
                    !form.dueDate && 'text-muted-foreground',
                  )}
                >
                  <CalendarIcon className="mr-2 h-4 w-4" />
                  {form.dueDate ? format(form.dueDate, 'PPP') : 'Pick a date'}
                </Button>
              </PopoverTrigger>
              <PopoverContent className="w-auto p-0" align="start">
                <Calendar
                  mode="single"
                  selected={form.dueDate}
                  onSelect={(d) => {
                    setForm((f) => ({ ...f, dueDate: d }));
                    setCalendarOpen(false);
                  }}
                  initialFocus
                />
                {form.dueDate && (
                  <div className="border-t p-2">
                    <Button
                      variant="ghost"
                      size="sm"
                      className="text-muted-foreground w-full text-xs"
                      onClick={() => {
                        setForm((f) => ({ ...f, dueDate: undefined }));
                        setCalendarOpen(false);
                      }}
                    >
                      Clear date
                    </Button>
                  </div>
                )}
              </PopoverContent>
            </Popover>
          </div>
        </div>

        <div className="flex justify-end gap-2 border-t px-6 py-4">
          <Button variant="outline" onClick={() => onOpenChange(false)}>
            Cancel
          </Button>
          <Button onClick={onSubmit} disabled={!form.title.trim() || isPending}>
            {isPending && <Loader2 className="mr-2 h-4 w-4 animate-spin" aria-hidden />}
            {editingTask ? 'Save changes' : 'Create task'}
          </Button>
        </div>
      </SheetContent>
    </Sheet>
  );
}

// ─── NLP Quick-Add ────────────────────────────────────────────────────────────

const NLP_MODE_KEY = 'tasks.nlpMode';

interface NlpQuickAddProps {
  defaultStatus: TaskStatus | 'all';
  folderId: string | null;
  onSubmit: (p: { title: string; dueDate: Date | null; status: string; folderId: string | null }) => void;
  isSubmitting: boolean;
}

function NlpQuickAdd({ defaultStatus, folderId, onSubmit, isSubmitting }: NlpQuickAddProps) {
  const [value, setValue] = useState('');
  const [mode, setMode] = useState<'auto' | 'confirm'>('auto');
  useEffect(() => {
    try {
      const stored = localStorage.getItem(NLP_MODE_KEY);
      if (stored === 'confirm') setMode('confirm');
    } catch {
      // ignore
    }
  }, []);
  const [awaitingConfirm, setAwaitingConfirm] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);

  // Compound-intent split: one input → many tasks. Mirrors macOS
  // `CompoundIntentParser`. Splits on " and " / "; " / newline boundaries
  // when the surrounding tokens look like distinct task titles (each side
  // either has a verb or a date). Conservative — falls back to single-task
  // when the heuristic doesn't apply, so "Email Sam and Sara" stays one task.
  const compoundParts = useMemo(() => {
    const raw = value.trim();
    if (!raw) return [];
    // Split on explicit separators only — semicolon / newline / " and then "
    // / " then ". `" and "` alone is too risky ("Email A and B"), so we
    // require either " and then " or a date keyword to trigger.
    const explicitSplit = raw.split(/\s*(?:;|\n|\sand then\s|\sthen\s)\s*/i);
    const candidates = explicitSplit.length > 1 ? explicitSplit : [raw];
    return candidates.map((s) => s.trim()).filter((s) => s.length > 0);
  }, [value]);

  const parsedParts = useMemo(
    () => compoundParts.map((part) => parseNaturalLanguage(part) ?? { title: part, dueDate: null }),
    [compoundParts],
  );

  const parsed = parsedParts[0] ?? null;
  const hasDate = parsed?.dueDate != null;
  const cleanTitle = parsed?.title ?? value.trim();
  const isCompound = parsedParts.length > 1;

  const buildParams = useCallback(
    () => ({
      title: cleanTitle || value.trim(),
      dueDate: parsed?.dueDate ?? null,
      status: defaultStatus === 'all' ? 'todo' : defaultStatus,
      folderId,
    }),
    [cleanTitle, value, parsed, defaultStatus, folderId],
  );

  const handleSubmit = useCallback(() => {
    if (!value.trim() || isSubmitting) return;
    if (mode === 'confirm' && !awaitingConfirm) {
      setAwaitingConfirm(true);
      return;
    }
    if (isCompound) {
      // Fire onSubmit once per parsed part so the user gets multiple captures
      // from a single input. defaultStatus + folderId apply to all.
      for (const part of parsedParts) {
        onSubmit({
          title: part.title || value.trim(),
          dueDate: part.dueDate ?? null,
          status: defaultStatus === 'all' ? 'todo' : defaultStatus,
          folderId,
        });
      }
    } else {
      onSubmit(buildParams());
    }
    setValue('');
    setAwaitingConfirm(false);
  }, [value, isSubmitting, mode, awaitingConfirm, onSubmit, buildParams, isCompound, parsedParts, defaultStatus, folderId]);

  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent<HTMLInputElement>) => {
      if (e.key === 'Enter') {
        e.preventDefault();
        handleSubmit();
      } else if (e.key === 'Escape') {
        if (awaitingConfirm) {
          setAwaitingConfirm(false);
        } else {
          setValue('');
        }
      }
    },
    [handleSubmit, awaitingConfirm],
  );

  const toggleMode = useCallback(() => {
    const next = mode === 'auto' ? 'confirm' : 'auto';
    setMode(next);
    setAwaitingConfirm(false);
    try {
      localStorage.setItem(NLP_MODE_KEY, next);
    } catch {
      // ignore
    }
  }, [mode]);

  const handleChange = useCallback((e: React.ChangeEvent<HTMLInputElement>) => {
    setValue(e.target.value);
    setAwaitingConfirm(false);
  }, []);

  const handleConfirmClick = useCallback(() => {
    onSubmit(buildParams());
    setValue('');
    setAwaitingConfirm(false);
    inputRef.current?.focus();
  }, [onSubmit, buildParams]);

  return (
    <div className="mb-2">
      {/* Input row */}
      <div className="flex items-center gap-2">
        <div className="relative flex-1">
          <Plus className="text-muted-foreground pointer-events-none absolute top-1/2 left-3 h-4 w-4 -translate-y-1/2" />
          <Input
            ref={inputRef}
            value={value}
            onChange={handleChange}
            onKeyDown={handleKeyDown}
            placeholder={'Add task… (e.g. "Ring Lisa fredag kl 9")'}
            className="h-9 pl-9 pr-3 text-sm"
            disabled={isSubmitting}
          />
        </div>

        {/* Mode toggle */}
        <button
          type="button"
          onClick={toggleMode}
          title={mode === 'auto' ? 'Auto-create (click to switch to confirm)' : 'Confirm before creating (click to switch to auto)'}
          aria-label={mode === 'auto' ? 'Auto-create (click to switch to confirm)' : 'Confirm before creating (click to switch to auto)'}
          className={cn(
            'flex h-9 w-9 shrink-0 items-center justify-center rounded-md border text-sm transition-colors',
            mode === 'auto'
              ? 'border-transparent bg-transparent text-muted-foreground hover:bg-accent hover:text-foreground'
              : 'border-border bg-accent text-foreground',
          )}
        >
          {mode === 'auto' ? <Zap className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
        </button>
      </div>

      {/* Live NLP preview / confirm card */}
      {value.trim() && (hasDate || awaitingConfirm) && (
        <div
          className={cn(
            'mt-1.5 flex items-center justify-between rounded-lg border px-3 py-2 text-xs transition-all',
            awaitingConfirm
              ? 'border-primary/30 bg-primary/5'
              : 'border-border/50 bg-muted/40',
          )}
        >
          <div className="flex min-w-0 flex-col gap-0.5">
            <span className="truncate font-medium text-foreground">{cleanTitle || value.trim()}</span>
            {hasDate && (
              <span className="text-muted-foreground">
                {format(parsed!.dueDate!, "EEE d MMM 'at' HH:mm")}
              </span>
            )}
          </div>

          {awaitingConfirm && (
            <button
              type="button"
              onClick={handleConfirmClick}
              disabled={isSubmitting}
              className="ml-3 shrink-0 rounded-md bg-primary px-2.5 py-1 text-xs font-medium text-primary-foreground transition-opacity hover:opacity-90 disabled:opacity-50"
            >
              Create ↵
            </button>
          )}
        </div>
      )}
    </div>
  );
}
