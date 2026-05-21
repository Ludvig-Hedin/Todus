import { motion } from 'motion/react';
import {
  Inbox,
  Star,
  FileEdit,
  Send,
  Archive,
  ShieldAlert,
  Trash2,
  CalendarDays,
  CheckSquare,
  Sparkles,
  Settings,
  HelpCircle,
  Pencil,
  StickyNote,
} from 'lucide-react';
import { cn } from '@/lib/utils';
import type { SceneId } from './mockData';
import { ACCENT_BLUE, SIDEBAR_FOLDERS, SIDEBAR_MANAGEMENT } from './mockData';

interface NavItem {
  id: string;
  label: string;
  icon: React.ComponentType<{ className?: string }>;
  count?: number;
}

const FOLDER_ICONS: Record<string, React.ComponentType<{ className?: string }>> = {
  inbox: Inbox,
  favorites: Star,
  drafts: FileEdit,
  sent: Send,
  archive: Archive,
  spam: ShieldAlert,
  bin: Trash2,
};

const APP_ITEMS: { id: SceneId; label: string; icon: React.ComponentType<{ className?: string }> }[] = [
  { id: 'calendar', label: 'Calendar', icon: CalendarDays },
  { id: 'tasks', label: 'Tasks', icon: CheckSquare },
  { id: 'assistant', label: 'Assistant', icon: Sparkles },
];

export function DemoSidebar({
  active,
  onSelect,
}: {
  active: SceneId;
  onSelect: (id: SceneId) => void;
}) {
  const folders: NavItem[] = SIDEBAR_FOLDERS.map((f) => ({
    id: f.id,
    label: f.label,
    icon: FOLDER_ICONS[f.id] ?? Inbox,
    count: 'count' in f ? f.count : undefined,
  }));
  const management: NavItem[] = SIDEBAR_MANAGEMENT.map((f) => ({
    id: f.id,
    label: f.label,
    icon: FOLDER_ICONS[f.id] ?? Archive,
    count: 'count' in f ? f.count : undefined,
  }));

  return (
    <aside className="flex w-[180px] shrink-0 flex-col gap-3 border-r border-white/[0.06] px-2.5 py-3 text-[12px]">
      <header className="flex items-center justify-between px-1.5">
        <div className="flex items-center gap-2">
          <div className="flex h-6 w-6 items-center justify-center rounded-md bg-white/[0.08] text-[10px] font-semibold text-white">
            B
          </div>
          <div className="leading-tight">
            <div className="text-[11px] font-semibold text-white">Baked Design</div>
            <div className="text-[9px] text-white/45">work@baked.design</div>
          </div>
        </div>
      </header>

      <button
        type="button"
        onClick={() => onSelect('mail')}
        className="flex h-8 w-full items-center justify-center gap-1.5 rounded-lg text-[11px] font-semibold text-white shadow-sm transition-opacity hover:opacity-90"
        style={{ backgroundColor: ACCENT_BLUE }}
      >
        <Pencil className="h-3 w-3" />
        <span>New email</span>
      </button>

      <nav aria-label="Mail folders" className="flex flex-col">
        <SectionLabel label="Core" />
        {folders.map((item) => (
          <SidebarRow
            key={item.id}
            label={item.label}
            icon={item.icon}
            count={item.count}
            active={active === 'mail' && item.id === 'inbox'}
            onClick={() => onSelect('mail')}
          />
        ))}
        <SectionLabel label="Management" className="mt-2" />
        {management.map((item) => (
          <SidebarRow
            key={item.id}
            label={item.label}
            icon={item.icon}
            count={item.count}
            onClick={() => onSelect('mail')}
          />
        ))}
        <SectionLabel label="Apps" className="mt-2" />
        {APP_ITEMS.map((item) => (
          <SidebarRow
            key={item.id}
            label={item.label}
            icon={item.icon}
            active={active === item.id}
            onClick={() => onSelect(item.id)}
          />
        ))}
        <SidebarRow label="Notes" icon={StickyNote} onClick={() => onSelect('mail')} />
      </nav>

      <div className="mt-auto flex flex-col">
        <SidebarRow label="Settings" icon={Settings} muted onClick={() => undefined} />
        <SidebarRow label="Support" icon={HelpCircle} muted onClick={() => undefined} />
      </div>
    </aside>
  );
}

function SectionLabel({ label, className }: { label: string; className?: string }) {
  return (
    <div
      className={cn(
        'px-1.5 pb-1 pt-2 text-[9px] font-semibold uppercase tracking-wider text-white/35',
        className,
      )}
    >
      {label}
    </div>
  );
}

function SidebarRow({
  label,
  icon: Icon,
  count,
  active,
  muted,
  onClick,
}: {
  label: string;
  icon: React.ComponentType<{ className?: string }>;
  count?: number;
  active?: boolean;
  muted?: boolean;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-pressed={active}
      className={cn(
        'relative flex h-7 w-full items-center gap-2 rounded-md px-1.5 text-left text-[11px] transition-colors',
        active ? 'text-white' : muted ? 'text-white/40 hover:text-white/70' : 'text-white/70 hover:text-white',
      )}
    >
      {active && (
        <motion.span
          layoutId="demo-sidebar-active"
          className="absolute inset-0 rounded-md bg-white/[0.08]"
          transition={{ type: 'spring', stiffness: 380, damping: 32 }}
        />
      )}
      <Icon className="relative h-3.5 w-3.5 shrink-0" />
      <span className="relative flex-1 truncate font-medium">{label}</span>
      {typeof count === 'number' && (
        <span className="relative text-[10px] tabular-nums text-white/40">{count}</span>
      )}
    </button>
  );
}
