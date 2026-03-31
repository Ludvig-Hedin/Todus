/**
 * Tasks page — full parity with iOS TasksTabView.
 * View modes: List (default) | Board (kanban drag-drop) | Table (compact rows)
 * Folder filter: horizontal pill-chip strip at top (replaces sidebar)
 * Task detail: Sheet from right, full info + edit form
 */
import { useState, useMemo, useRef } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { format, isPast, isToday } from 'date-fns';
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
  SortableContext,
  useSortable,
  verticalListSortingStrategy,
} from '@dnd-kit/sortable';
import { useDroppable } from '@dnd-kit/core';
import { CSS } from '@dnd-kit/utilities';
import { useTRPC } from '@/providers/query-provider';
import { authProxy } from '@/lib/auth-proxy';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { Badge } from '@/components/ui/badge';
import { Calendar } from '@/components/ui/calendar';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from '@/components/ui/dialog';
import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
} from '@/components/ui/sheet';
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
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { ScrollArea } from '@/components/ui/scroll-area';
import { cn } from '@/lib/utils';
import type { Route } from './+types/page';
import type { Outputs } from '@zero/server/trpc';

type Task = Outputs['tasks']['list']['tasks'][number];
type Folder = Outputs['folders']['list']['folders'][number];
type TaskStatus = 'todo' | 'doing' | 'done';
type TaskPriority = 'none' | 'low' | 'medium' | 'high';
type SortBy = 'newest' | 'oldest' | 'priority';
type ViewMode = 'list' | 'board' | 'table';

// Auth guard
export async function clientLoader({ request }: Route.ClientLoaderArgs) {
  const session = await authProxy.api.getSession({ headers: request.headers });
  if (!session) return Response.redirect(`${import.meta.env.VITE_PUBLIC_APP_URL}/login`);
  return {};
}

const PRIORITY_CONFIG: Record<TaskPriority, { label: string; className: string }> = {
  none: { label: 'No priority', className: 'text-muted-foreground bg-muted/50' },
  low: { label: 'Low', className: 'text-blue-600 bg-blue-50 dark:bg-blue-950/30 dark:text-blue-400' },
  medium: { label: 'Medium', className: 'text-yellow-600 bg-yellow-50 dark:bg-yellow-950/30 dark:text-yellow-400' },
  high: { label: 'High', className: 'text-red-600 bg-red-50 dark:bg-red-950/30 dark:text-red-400' },
};

const STATUS_CONFIG: Record<TaskStatus, { label: string; color: string }> = {
  todo:  { label: 'To Do',  color: 'text-muted-foreground' },
  doing: { label: 'Doing',  color: 'text-blue-600 dark:text-blue-400' },
  done:  { label: 'Done',   color: 'text-green-600 dark:text-green-400' },
};

const BOARD_COLUMNS: { status: TaskStatus; label: string }[] = [
  { status: 'todo',  label: 'To Do' },
  { status: 'doing', label: 'Doing' },
  { status: 'done',  label: 'Done'  },
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
  title: '', description: '', status: 'todo', priority: 'none',
  dueDate: undefined, folderId: null,
};

// ─── Main Page ────────────────────────────────────────────────────────────────

export default function TasksPage() {
  const trpc = useTRPC();
  const queryClient = useQueryClient();

  const [viewMode, setViewMode] = useState<ViewMode>('list');
  const [statusFilter, setStatusFilter] = useState<TaskStatus | 'all'>('all');
  const [sortBy, setSortBy] = useState<SortBy>('newest');
  const [activeFolderId, setActiveFolderId] = useState<string | null>(null);
  const [searchText, setSearchText] = useState('');

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

  // Quick-add input ref
  const quickAddRef = useRef<HTMLInputElement>(null);
  const [quickAddValue, setQuickAddValue] = useState('');

  // Board drag state
  const [activeTaskId, setActiveTaskId] = useState<string | null>(null);

  const { data: foldersData } = useQuery(trpc.folders.list.queryOptions());
  const folders = foldersData?.folders ?? [];

  // For board mode we need all statuses; otherwise filter
  const boardMode = viewMode === 'board';
  const queryInput = {
    ...(statusFilter !== 'all' && !boardMode && { status: statusFilter }),
    ...(activeFolderId && { folderId: activeFolderId }),
    sortBy,
    limit: 500, // higher for board + table
    ...(searchText && { search: searchText }),
  };

  const { data, isLoading } = useQuery(trpc.tasks.list.queryOptions(queryInput));
  const tasks = data?.tasks ?? [];

  const invalidateTasks = () => void queryClient.invalidateQueries(trpc.tasks.list.queryFilter());

  const createMutation = useMutation({ ...trpc.tasks.create.mutationOptions(), onSuccess: invalidateTasks });
  const updateMutation = useMutation({ ...trpc.tasks.update.mutationOptions(), onSuccess: () => { invalidateTasks(); if (detailTask) setDetailTask((prev) => prev ? { ...prev } : null); } });
  const deleteMutation = useMutation({ ...trpc.tasks.delete.mutationOptions(), onSuccess: invalidateTasks });
  const createFolderMutation = useMutation({ ...trpc.folders.create.mutationOptions(), onSuccess: () => void queryClient.invalidateQueries(trpc.folders.list.queryFilter()) });
  const updateFolderMutation = useMutation({ ...trpc.folders.update.mutationOptions(), onSuccess: () => void queryClient.invalidateQueries(trpc.folders.list.queryFilter()) });
  const deleteFolderMutation = useMutation({
    ...trpc.folders.delete.mutationOptions(),
    onSuccess: () => {
      void queryClient.invalidateQueries(trpc.folders.list.queryFilter());
      if (activeFolderId === editingFolder?.id) setActiveFolderId(null);
    },
  });

  const openCreate = (prefillStatus?: TaskStatus, prefillDate?: Date) => {
    setEditingTask(null);
    setForm({ ...defaultForm, folderId: activeFolderId, status: prefillStatus ?? 'todo', dueDate: prefillDate });
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
    updateMutation.mutate({ id: task.id, data: { status: task.status === 'done' ? 'todo' : 'done' } });

  const handleSubmit = () => {
    if (!form.title.trim()) return;
    const payload = {
      title: form.title.trim(), description: form.description,
      status: form.status, priority: form.priority,
      dueDate: form.dueDate ? form.dueDate.toISOString() : null,
      folderId: form.folderId,
    };
    if (editingTask) {
      updateMutation.mutate({ id: editingTask.id, data: payload }, { onSuccess: () => setDialogOpen(false) });
    } else {
      createMutation.mutate(payload, { onSuccess: () => setDialogOpen(false) });
    }
  };

  const handleQuickAdd = (e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'Enter' && quickAddValue.trim()) {
      createMutation.mutate({
        title: quickAddValue.trim(),
        status: statusFilter !== 'all' ? statusFilter : 'todo',
        priority: 'none',
        folderId: activeFolderId,
      });
      setQuickAddValue('');
    }
  };

  const handleMoveToFolder = (taskId: string, folderId: string | null) =>
    updateMutation.mutate({ id: taskId, data: { folderId } });

  const handleFolderSubmit = () => {
    if (!folderName.trim()) return;
    if (editingFolder) {
      updateFolderMutation.mutate(
        { id: editingFolder.id, name: folderName.trim() },
        { onSuccess: () => { setFolderDialogOpen(false); setFolderName(''); setEditingFolder(null); } },
      );
    } else {
      createFolderMutation.mutate(
        { name: folderName.trim() },
        { onSuccess: () => { setFolderDialogOpen(false); setFolderName(''); } },
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
    // over.id will be the column status string ('todo' | 'doing' | 'done')
    const newStatus = over.id as TaskStatus;
    const task = tasks.find((t) => t.id === active.id);
    if (task && task.status !== newStatus && BOARD_COLUMNS.some((c) => c.status === newStatus)) {
      updateMutation.mutate({ id: task.id, data: { status: newStatus } });
    }
  };

  const activeTask = activeTaskId ? tasks.find((t) => t.id === activeTaskId) : null;

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
    <div className="flex h-screen flex-col overflow-hidden bg-background">
      {/* ── Header ── */}
      <div className="flex shrink-0 items-center justify-between border-b px-5 py-3">
        <h1 className="text-xl font-semibold tracking-tight">
          {activeFolder ? activeFolder.name : 'Tasks'}
        </h1>
        <div className="flex items-center gap-2">
          {/* View mode switcher — matches iOS segmented control */}
          <div className="flex items-center gap-0.5 rounded-lg border bg-muted/50 p-0.5">
            {([['list', List], ['board', LayoutGrid], ['table', Table2]] as [ViewMode, typeof List][]).map(([mode, Icon]) => (
              <button
                key={mode}
                type="button"
                onClick={() => setViewMode(mode)}
                className={cn(
                  'flex h-7 w-7 items-center justify-center rounded-md transition-colors',
                  viewMode === mode ? 'bg-background shadow-sm text-foreground' : 'text-muted-foreground hover:text-foreground',
                )}
              >
                <Icon className="h-3.5 w-3.5" />
              </button>
            ))}
          </div>

          {/* Sort — only for list/table */}
          {viewMode !== 'board' && (
            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <Button variant="outline" size="sm" className="h-8 gap-1.5 text-xs">
                  <ArrowUpDown className="h-3.5 w-3.5" />
                  {sortBy === 'newest' ? 'Newest' : sortBy === 'oldest' ? 'Oldest' : 'Priority'}
                </Button>
              </DropdownMenuTrigger>
              <DropdownMenuContent align="end">
                <DropdownMenuLabel>Sort by</DropdownMenuLabel>
                <DropdownMenuRadioGroup value={sortBy} onValueChange={(v) => setSortBy(v as SortBy)}>
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
      {folders.length > 0 && (
        <div className="shrink-0 border-b">
          <div className="flex items-center gap-1.5 overflow-x-auto px-5 py-2 scrollbar-none">
            {/* All */}
            <button
              type="button"
              onClick={() => setActiveFolderId(null)}
              className={cn(
                'flex shrink-0 items-center gap-1.5 rounded-full border px-3.5 py-1 text-[13px] font-medium transition-colors',
                activeFolderId === null
                  ? 'border-foreground/20 bg-accent text-accent-foreground'
                  : 'border-border bg-transparent text-muted-foreground hover:bg-accent/50 hover:text-foreground',
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
                      : 'border-border bg-transparent text-muted-foreground hover:bg-accent/50 hover:text-foreground',
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
                      className="absolute -right-1 -top-1 hidden h-4 w-4 items-center justify-center rounded-full bg-muted text-muted-foreground shadow group-hover:flex"
                    >
                      <X className="h-2.5 w-2.5" />
                    </button>
                  </DropdownMenuTrigger>
                  <DropdownMenuContent>
                    <DropdownMenuItem onClick={() => { setEditingFolder(folder); setFolderName(folder.name); setFolderDialogOpen(true); }}>
                      <Pencil className="mr-2 h-3.5 w-3.5" /> Rename
                    </DropdownMenuItem>
                    <DropdownMenuSeparator />
                    <DropdownMenuItem className="text-destructive focus:text-destructive" onClick={() => { setEditingFolder(folder); deleteFolderMutation.mutate({ id: folder.id }); }}>
                      <Trash2 className="mr-2 h-3.5 w-3.5" /> Delete
                    </DropdownMenuItem>
                  </DropdownMenuContent>
                </DropdownMenu>
              </div>
            ))}
            {/* New folder */}
            <button
              type="button"
              onClick={() => { setEditingFolder(null); setFolderName(''); setFolderDialogOpen(true); }}
              className="flex shrink-0 items-center gap-1 rounded-full border border-dashed border-border px-3 py-1 text-[13px] text-muted-foreground transition-colors hover:border-foreground/30 hover:text-foreground"
            >
              <FolderPlus className="h-3 w-3" />
              Add folder
            </button>
          </div>
        </div>
      )}

      {/* ── Search + Filter Bar (List / Table only) ── */}
      {viewMode !== 'board' && (
        <div className="flex shrink-0 items-center gap-2 border-b px-5 py-2">
          <div className="relative flex-1">
            <input
              value={searchText}
              onChange={(e) => setSearchText(e.target.value)}
              placeholder="Search tasks…"
              className="h-8 w-full rounded-full border bg-muted/50 px-3 text-[13px] placeholder:text-muted-foreground focus:outline-none focus:ring-1 focus:ring-ring"
            />
          </div>
          {/* Status filter tabs */}
          <div className="flex items-center gap-0.5 rounded-lg border bg-muted/50 p-0.5">
            {(['all', 'todo', 'doing', 'done'] as const).map((s) => (
              <button
                key={s}
                type="button"
                onClick={() => setStatusFilter(s)}
                className={cn(
                  'rounded-md px-2.5 py-1 text-[12px] font-medium transition-colors',
                  statusFilter === s ? 'bg-background shadow-sm text-foreground' : 'text-muted-foreground hover:text-foreground',
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
            quickAddValue={quickAddValue}
            setQuickAddValue={setQuickAddValue}
            quickAddRef={quickAddRef}
            onQuickAdd={handleQuickAdd}
            onToggle={handleToggle}
            onEdit={openEdit}
            onDelete={(id) => deleteMutation.mutate({ id })}
            onMoveToFolder={handleMoveToFolder}
            onOpenDetail={setDetailTask}
            onOpenCreate={openCreate}
            isDueDateWarning={isDueDateWarning}
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
                <BoardCard task={activeTask} isDragging folders={folders} onEdit={() => {}} onDelete={() => {}} onOpenDetail={() => {}} />
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
      </div>

      {/* ── Task Detail Sheet ── */}
      <Sheet open={!!detailTask} onOpenChange={(open) => !open && setDetailTask(null)}>
        <SheetContent side="right" className="w-[400px] overflow-y-auto sm:max-w-[400px]">
          {detailTask && (
            <TaskDetailPanel
              task={detailTask}
              folders={folders}
              onEdit={openEdit}
              onToggle={handleToggle}
              onDelete={(id) => { deleteMutation.mutate({ id }); setDetailTask(null); }}
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
      <Dialog open={folderDialogOpen} onOpenChange={(open) => { setFolderDialogOpen(open); if (!open) { setFolderName(''); setEditingFolder(null); } }}>
        <DialogContent className="sm:max-w-sm">
          <DialogHeader>
            <DialogTitle>{editingFolder ? 'Rename folder' : 'New folder'}</DialogTitle>
          </DialogHeader>
          <div className="py-2">
            <Input placeholder="Folder name" value={folderName} onChange={(e) => setFolderName(e.target.value)} onKeyDown={(e) => e.key === 'Enter' && handleFolderSubmit()} autoFocus />
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setFolderDialogOpen(false)}>Cancel</Button>
            <Button onClick={handleFolderSubmit} disabled={!folderName.trim() || createFolderMutation.isPending || updateFolderMutation.isPending}>
              {editingFolder ? 'Rename' : 'Create folder'}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}

// ─── List Content ─────────────────────────────────────────────────────────────

function ListContent({
  tasks, folders, isLoading, quickAddValue, setQuickAddValue, quickAddRef,
  onQuickAdd, onToggle, onEdit, onDelete, onMoveToFolder, onOpenDetail, onOpenCreate, isDueDateWarning,
}: {
  tasks: Task[]; folders: Folder[]; isLoading: boolean;
  quickAddValue: string; setQuickAddValue: (v: string) => void;
  quickAddRef: React.RefObject<HTMLInputElement | null>;
  onQuickAdd: (e: React.KeyboardEvent<HTMLInputElement>) => void;
  onToggle: (t: Task) => void; onEdit: (t: Task) => void;
  onDelete: (id: string) => void; onMoveToFolder: (taskId: string, folderId: string | null) => void;
  onOpenDetail: (t: Task) => void; onOpenCreate: () => void;
  isDueDateWarning: (d: string | Date | null | undefined) => boolean;
}) {
  return (
    <ScrollArea className="h-full">
      <div className="space-y-1 px-5 py-3">
        {/* Inline quick-add row */}
        <div className="mb-3 flex items-center gap-2 rounded-xl border border-dashed border-border bg-muted/30 px-3 py-2">
          <Plus className="h-4 w-4 shrink-0 text-muted-foreground" />
          <input
            ref={quickAddRef}
            value={quickAddValue}
            onChange={(e) => setQuickAddValue(e.target.value)}
            onKeyDown={onQuickAdd}
            placeholder="Add a task… (press Enter)"
            className="flex-1 bg-transparent text-sm outline-none placeholder:text-muted-foreground"
          />
        </div>

        {isLoading ? (
          Array.from({ length: 5 }).map((_, i) => (
            <div key={i} className="h-16 animate-pulse rounded-xl bg-muted/50" />
          ))
        ) : tasks.length === 0 ? (
          <div className="flex flex-col items-center justify-center gap-3 py-16 text-center">
            <div className="flex h-12 w-12 items-center justify-center rounded-full bg-muted">
              <CheckCircle2 className="h-6 w-6 text-muted-foreground" />
            </div>
            <div>
              <p className="font-medium">No tasks yet</p>
              <p className="text-sm text-muted-foreground">Create your first task to get started</p>
            </div>
            <Button onClick={onOpenCreate} size="sm" variant="outline">
              <Plus className="mr-1.5 h-4 w-4" />
              New task
            </Button>
          </div>
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
  task, folders, onToggle, onEdit, onDelete, onMoveToFolder, onOpenDetail, isDueDateWarning,
}: {
  task: Task; folders: Folder[];
  onToggle: (t: Task) => void; onEdit: (t: Task) => void;
  onDelete: (id: string) => void; onMoveToFolder: (taskId: string, folderId: string | null) => void;
  onOpenDetail: (t: Task) => void; isDueDateWarning: boolean;
}) {
  const isDone = task.status === 'done';
  const priority = task.priority as TaskPriority;

  return (
    <div
      className={cn(
        'group flex items-start gap-3 rounded-xl border border-border bg-card px-3.5 py-3 transition-colors hover:border-border/80 hover:bg-accent/20',
        isDone && 'opacity-60',
      )}
    >
      <button
        type="button"
        onClick={() => onToggle(task)}
        className="mt-0.5 shrink-0 text-muted-foreground transition-colors hover:text-primary"
      >
        {isDone ? <CheckCircle2 className="h-4.5 w-4.5 text-primary" /> : <Circle className="h-4.5 w-4.5" />}
      </button>

      <button
        type="button"
        className="min-w-0 flex-1 text-left"
        onClick={() => onOpenDetail(task)}
      >
        <p className={cn('text-sm font-medium leading-snug', isDone && 'text-muted-foreground line-through')}>
          {task.title}
        </p>
        {task.description && (
          <p className="mt-0.5 line-clamp-1 text-xs text-muted-foreground">{task.description}</p>
        )}
        <div className="mt-1.5 flex flex-wrap items-center gap-1.5">
          {priority !== 'none' && (
            <Badge variant="secondary" className={cn('h-4 rounded-md px-1.5 text-[10px] font-medium border-0', PRIORITY_CONFIG[priority].className)}>
              {PRIORITY_CONFIG[priority].label}
            </Badge>
          )}
          {task.status !== 'todo' && (
            <Badge variant="outline" className={cn('h-4 rounded-md px-1.5 text-[10px] font-medium', STATUS_CONFIG[task.status as TaskStatus]?.color)}>
              {STATUS_CONFIG[task.status as TaskStatus]?.label}
            </Badge>
          )}
          {task.dueDate && (
            <span className={cn('flex items-center gap-0.5 text-[10px] font-medium', isDueDateWarning ? 'text-red-500' : 'text-muted-foreground')}>
              <CalendarIcon className="h-3 w-3" />
              {isToday(new Date(task.dueDate)) ? 'Today' : format(new Date(task.dueDate), 'MMM d')}
            </span>
          )}
          {task.folderId && folders.length > 0 && (
            <span className="flex items-center gap-0.5 text-[10px] text-muted-foreground">
              <FolderIcon className="h-3 w-3" />
              {folders.find((f) => f.id === task.folderId)?.name}
            </span>
          )}
        </div>
      </button>

      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <Button variant="ghost" size="icon" className="h-7 w-7 shrink-0 opacity-0 group-hover:opacity-100">
            <MoreHorizontal className="h-4 w-4" />
          </Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end" className="w-44">
          <DropdownMenuItem onClick={() => onEdit(task)}><Pencil className="mr-2 h-3.5 w-3.5" />Edit</DropdownMenuItem>
          {folders.length > 0 && (
            <DropdownMenuSub>
              <DropdownMenuSubTrigger><FolderIcon className="mr-2 h-3.5 w-3.5" />Move to folder</DropdownMenuSubTrigger>
              <DropdownMenuSubContent>
                <DropdownMenuItem onClick={() => onMoveToFolder(task.id, null)}><CheckCircle2 className="mr-2 h-3.5 w-3.5" />No folder</DropdownMenuItem>
                <DropdownMenuSeparator />
                {folders.map((folder) => (
                  <DropdownMenuItem key={folder.id} onClick={() => onMoveToFolder(task.id, folder.id)}>
                    <FolderIcon className="mr-2 h-3.5 w-3.5" />{folder.name}
                  </DropdownMenuItem>
                ))}
              </DropdownMenuSubContent>
            </DropdownMenuSub>
          )}
          <DropdownMenuSeparator />
          <DropdownMenuItem className="text-destructive focus:text-destructive" onClick={() => onDelete(task.id)}>
            <Trash2 className="mr-2 h-3.5 w-3.5" />Delete
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>
    </div>
  );
}

// ─── Board View ───────────────────────────────────────────────────────────────

function BoardColumn({
  status, label, tasks, folders, onEdit, onDelete, onOpenDetail, onQuickCreate,
}: {
  status: TaskStatus; label: string; tasks: Task[]; folders: Folder[];
  onEdit: (t: Task) => void; onDelete: (id: string) => void;
  onOpenDetail: (t: Task) => void; onQuickCreate: (s: TaskStatus) => void;
}) {
  const { setNodeRef, isOver } = useDroppable({ id: status });

  return (
    <div
      ref={setNodeRef}
      className={cn(
        'flex h-full w-72 shrink-0 flex-col rounded-xl border bg-muted/30 transition-colors',
        isOver && 'border-primary/50 bg-accent/30',
      )}
    >
      {/* Column header */}
      <div className="flex items-center justify-between px-3 py-2.5">
        <div className="flex items-center gap-2">
          <span className="text-[13px] font-semibold">{label}</span>
          <span className="flex h-4 min-w-[1rem] items-center justify-center rounded-full bg-muted px-1 text-[10px] font-bold text-muted-foreground">
            {tasks.length}
          </span>
        </div>
        <Button variant="ghost" size="icon" className="h-6 w-6" onClick={() => onQuickCreate(status)}>
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
              <div className="flex h-16 items-center justify-center rounded-lg border border-dashed border-border text-xs text-muted-foreground">
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
  task, folders, onEdit, onDelete, onOpenDetail, isDragging,
}: {
  task: Task; folders: Folder[];
  onEdit: (t: Task) => void; onDelete: (id: string) => void;
  onOpenDetail: (t: Task) => void; isDragging?: boolean;
}) {
  const { attributes, listeners, setNodeRef, transform, transition, isDragging: isSortableDragging } = useSortable({ id: task.id });

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
        'group relative rounded-lg border border-border bg-card px-3 py-2.5 shadow-sm transition-shadow',
        isDragging && 'shadow-md rotate-1',
      )}
    >
      {/* Drag handle */}
      <div
        {...attributes}
        {...listeners}
        className="absolute left-1 top-1/2 -translate-y-1/2 cursor-grab touch-none opacity-0 group-hover:opacity-100"
      >
        <GripVertical className="h-3.5 w-3.5 text-muted-foreground" />
      </div>

      <button type="button" className="w-full text-left" onClick={() => onOpenDetail(task)}>
        <p className="text-[13px] font-medium leading-snug">{task.title}</p>
        {task.description && (
          <p className="mt-0.5 line-clamp-2 text-[11px] text-muted-foreground">{task.description}</p>
        )}
      </button>

      <div className="mt-2 flex flex-wrap items-center gap-1.5">
        {priority !== 'none' && (
          <Badge variant="secondary" className={cn('h-4 rounded px-1.5 text-[10px] font-medium border-0', PRIORITY_CONFIG[priority].className)}>
            {PRIORITY_CONFIG[priority].label}
          </Badge>
        )}
        {task.dueDate && (
          <span className="flex items-center gap-0.5 text-[10px] text-muted-foreground">
            <CalendarIcon className="h-3 w-3" />
            {isToday(new Date(task.dueDate)) ? 'Today' : format(new Date(task.dueDate), 'MMM d')}
          </span>
        )}
        {task.folderId && folders.length > 0 && (
          <span className="flex items-center gap-0.5 text-[10px] text-muted-foreground">
            <FolderIcon className="h-3 w-3" />
            {folders.find((f) => f.id === task.folderId)?.name}
          </span>
        )}
      </div>

      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <Button variant="ghost" size="icon" className="absolute right-1 top-1 h-6 w-6 opacity-0 group-hover:opacity-100">
            <MoreHorizontal className="h-3.5 w-3.5" />
          </Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end" className="w-36">
          <DropdownMenuItem onClick={() => onEdit(task)}><Pencil className="mr-2 h-3.5 w-3.5" />Edit</DropdownMenuItem>
          <DropdownMenuSeparator />
          <DropdownMenuItem className="text-destructive focus:text-destructive" onClick={() => onDelete(task.id)}>
            <Trash2 className="mr-2 h-3.5 w-3.5" />Delete
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>
    </div>
  );
}

// ─── Table View ───────────────────────────────────────────────────────────────

function TableContent({
  tasks, folders, isLoading, onToggle, onEdit, onDelete, onMoveToFolder, onOpenCreate,
}: {
  tasks: Task[]; folders: Folder[]; isLoading: boolean;
  onToggle: (t: Task) => void; onEdit: (t: Task) => void;
  onDelete: (id: string) => void; onMoveToFolder: (taskId: string, folderId: string | null) => void;
  onOpenCreate: () => void;
}) {
  return (
    <ScrollArea className="h-full">
      <table className="w-full text-sm">
        <thead>
          <tr className="border-b bg-muted/30 text-left text-[11px] font-semibold uppercase tracking-wide text-muted-foreground">
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
          {isLoading
            ? Array.from({ length: 6 }).map((_, i) => (
                <tr key={i}><td colSpan={7}><div className="my-1 mx-4 h-8 animate-pulse rounded bg-muted/50" /></td></tr>
              ))
            : tasks.length === 0
            ? (
              <tr>
                <td colSpan={7}>
                  <div className="flex flex-col items-center justify-center gap-3 py-16 text-center">
                    <p className="font-medium text-sm">No tasks</p>
                    <Button onClick={onOpenCreate} size="sm" variant="outline"><Plus className="mr-1.5 h-4 w-4" />New task</Button>
                  </div>
                </td>
              </tr>
            )
            : tasks.map((task) => {
                const isDone = task.status === 'done';
                const priority = task.priority as TaskPriority;
                const folder = folders.find((f) => f.id === task.folderId);
                return (
                  <tr key={task.id} className={cn('group hover:bg-accent/20 transition-colors', isDone && 'opacity-50')}>
                    <td className="px-4 py-2">
                      <button type="button" onClick={() => onToggle(task)} className="text-muted-foreground hover:text-primary">
                        {isDone ? <CheckCircle2 className="h-4 w-4 text-primary" /> : <Circle className="h-4 w-4" />}
                      </button>
                    </td>
                    <td className="max-w-0 px-2 py-2">
                      <p className={cn('truncate text-[13px] font-medium', isDone && 'line-through text-muted-foreground')}>
                        {task.title}
                      </p>
                    </td>
                    <td className="px-2 py-2">
                      {priority !== 'none' && (
                        <Badge variant="secondary" className={cn('h-4 rounded px-1.5 text-[10px] border-0', PRIORITY_CONFIG[priority].className)}>
                          {PRIORITY_CONFIG[priority].label}
                        </Badge>
                      )}
                    </td>
                    <td className={cn('px-2 py-2 text-[12px]', STATUS_CONFIG[task.status as TaskStatus]?.color)}>
                      {STATUS_CONFIG[task.status as TaskStatus]?.label}
                    </td>
                    <td className="px-2 py-2 text-[12px] text-muted-foreground">
                      {task.dueDate && format(new Date(task.dueDate), 'MMM d')}
                    </td>
                    <td className="px-2 py-2 text-[12px] text-muted-foreground">
                      {folder?.name}
                    </td>
                    <td className="px-4 py-2">
                      <DropdownMenu>
                        <DropdownMenuTrigger asChild>
                          <Button variant="ghost" size="icon" className="h-6 w-6 opacity-0 group-hover:opacity-100">
                            <MoreHorizontal className="h-3.5 w-3.5" />
                          </Button>
                        </DropdownMenuTrigger>
                        <DropdownMenuContent align="end" className="w-44">
                          <DropdownMenuItem onClick={() => onEdit(task)}><Pencil className="mr-2 h-3.5 w-3.5" />Edit</DropdownMenuItem>
                          {folders.length > 0 && (
                            <DropdownMenuSub>
                              <DropdownMenuSubTrigger><FolderIcon className="mr-2 h-3.5 w-3.5" />Move to folder</DropdownMenuSubTrigger>
                              <DropdownMenuSubContent>
                                <DropdownMenuItem onClick={() => onMoveToFolder(task.id, null)}><CheckCircle2 className="mr-2 h-3.5 w-3.5" />No folder</DropdownMenuItem>
                                <DropdownMenuSeparator />
                                {folders.map((folder) => (
                                  <DropdownMenuItem key={folder.id} onClick={() => onMoveToFolder(task.id, folder.id)}>
                                    <FolderIcon className="mr-2 h-3.5 w-3.5" />{folder.name}
                                  </DropdownMenuItem>
                                ))}
                              </DropdownMenuSubContent>
                            </DropdownMenuSub>
                          )}
                          <DropdownMenuSeparator />
                          <DropdownMenuItem className="text-destructive focus:text-destructive" onClick={() => onDelete(task.id)}>
                            <Trash2 className="mr-2 h-3.5 w-3.5" />Delete
                          </DropdownMenuItem>
                        </DropdownMenuContent>
                      </DropdownMenu>
                    </td>
                  </tr>
                );
              })}
        </tbody>
      </table>
    </ScrollArea>
  );
}

// ─── Task Detail Panel ────────────────────────────────────────────────────────

function TaskDetailPanel({
  task, folders, onEdit, onToggle, onDelete,
}: {
  task: Task; folders: Folder[];
  onEdit: (t: Task) => void; onToggle: (t: Task) => void; onDelete: (id: string) => void;
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
          <button type="button" onClick={() => onToggle(task)} className="mt-1 shrink-0 text-muted-foreground hover:text-primary">
            {task.status === 'done' ? <CheckCircle2 className="h-5 w-5 text-primary" /> : <Circle className="h-5 w-5" />}
          </button>
          <h2 className={cn('text-base font-semibold leading-snug', task.status === 'done' && 'line-through text-muted-foreground')}>
            {task.title}
          </h2>
        </div>

        {/* Description */}
        {task.description && (
          <p className="text-sm text-muted-foreground leading-relaxed">{task.description}</p>
        )}

        {/* Metadata */}
        <div className="flex flex-col gap-2 rounded-xl border bg-muted/30 p-3 text-sm">
          <div className="flex items-center justify-between">
            <span className="text-xs text-muted-foreground">Status</span>
            <span className={cn('text-xs font-medium', STATUS_CONFIG[task.status as TaskStatus]?.color)}>
              {STATUS_CONFIG[task.status as TaskStatus]?.label}
            </span>
          </div>
          {priority !== 'none' && (
            <div className="flex items-center justify-between">
              <span className="text-xs text-muted-foreground">Priority</span>
              <Badge variant="secondary" className={cn('h-4 rounded px-1.5 text-[10px] border-0', PRIORITY_CONFIG[priority].className)}>
                {PRIORITY_CONFIG[priority].label}
              </Badge>
            </div>
          )}
          {task.dueDate && (
            <div className="flex items-center justify-between">
              <span className="text-xs text-muted-foreground">Due date</span>
              <span className="text-xs font-medium">{format(new Date(task.dueDate), 'PPP')}</span>
            </div>
          )}
          {folder && (
            <div className="flex items-center justify-between">
              <span className="text-xs text-muted-foreground">Folder</span>
              <span className="flex items-center gap-1 text-xs font-medium">
                <FolderIcon className="h-3 w-3" />{folder.name}
              </span>
            </div>
          )}
          {task.createdAt && (
            <div className="flex items-center justify-between">
              <span className="text-xs text-muted-foreground">Created</span>
              <span className="text-xs text-muted-foreground">{format(new Date(task.createdAt), 'PPP')}</span>
            </div>
          )}
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
  open, onOpenChange, editingTask, form, setForm, calendarOpen, setCalendarOpen,
  folders, onSubmit, isPending,
}: {
  open: boolean; onOpenChange: (v: boolean) => void;
  editingTask: Task | null; form: TaskFormData;
  setForm: React.Dispatch<React.SetStateAction<TaskFormData>>;
  calendarOpen: boolean; setCalendarOpen: (v: boolean) => void;
  folders: Folder[]; onSubmit: () => void; isPending: boolean;
}) {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>{editingTask ? 'Edit task' : 'New task'}</DialogTitle>
        </DialogHeader>

        <div className="flex flex-col gap-4 py-2">
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
              <label className="text-xs font-medium text-muted-foreground">Priority</label>
              <Select value={form.priority} onValueChange={(v) => setForm((f) => ({ ...f, priority: v as TaskPriority }))}>
                <SelectTrigger className="h-9 text-sm"><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="none">No priority</SelectItem>
                  <SelectItem value="low">Low</SelectItem>
                  <SelectItem value="medium">Medium</SelectItem>
                  <SelectItem value="high">High</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div className="flex flex-col gap-1.5">
              <label className="text-xs font-medium text-muted-foreground">Status</label>
              <Select value={form.status} onValueChange={(v) => setForm((f) => ({ ...f, status: v as TaskStatus }))}>
                <SelectTrigger className="h-9 text-sm"><SelectValue /></SelectTrigger>
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
              <label className="text-xs font-medium text-muted-foreground">Folder (optional)</label>
              <Select value={form.folderId ?? 'none'} onValueChange={(v) => setForm((f) => ({ ...f, folderId: v === 'none' ? null : v }))}>
                <SelectTrigger className="h-9 text-sm"><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="none">No folder</SelectItem>
                  {folders.map((folder) => (
                    <SelectItem key={folder.id} value={folder.id}>{folder.name}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          )}
          <div className="flex flex-col gap-1.5">
            <label className="text-xs font-medium text-muted-foreground">Due date (optional)</label>
            <Popover open={calendarOpen} onOpenChange={setCalendarOpen}>
              <PopoverTrigger asChild>
                <Button variant="outline" className={cn('h-9 justify-start text-left font-normal text-sm', !form.dueDate && 'text-muted-foreground')}>
                  <CalendarIcon className="mr-2 h-4 w-4" />
                  {form.dueDate ? format(form.dueDate, 'PPP') : 'Pick a date'}
                </Button>
              </PopoverTrigger>
              <PopoverContent className="w-auto p-0" align="start">
                <Calendar mode="single" selected={form.dueDate} onSelect={(d) => { setForm((f) => ({ ...f, dueDate: d })); setCalendarOpen(false); }} initialFocus />
                {form.dueDate && (
                  <div className="border-t p-2">
                    <Button variant="ghost" size="sm" className="w-full text-xs text-muted-foreground" onClick={() => { setForm((f) => ({ ...f, dueDate: undefined })); setCalendarOpen(false); }}>
                      Clear date
                    </Button>
                  </div>
                )}
              </PopoverContent>
            </Popover>
          </div>
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>Cancel</Button>
          <Button onClick={onSubmit} disabled={!form.title.trim() || isPending}>
            {editingTask ? 'Save changes' : 'Create task'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
