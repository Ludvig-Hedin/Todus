/**
 * Convention-driven manifest of shadcn/ui primitives shown in the Design
 * System viewer. When a new primitive lands under
 * `apps/web/components/ui/`, add an entry here so the viewer renders it
 * alongside the others (the page maps over this list, grouped by category).
 *
 * Rationale (see DESIGN_SYSTEM_INCONSISTENCIES.md "🟡 Web component gallery"):
 * a build-time scan of `components/ui/` would couple the viewer to the build
 * pipeline. The manifest keeps the surface explicit, the build fast, and only
 * costs one PR-sized diff per primitive.
 *
 * Cross-platform sisters:
 *   - iOS: `Features/DesignSystem/DesignSystemView.swift`
 *   - macOS: `Views/Settings/MacDesignSystemView.swift`
 *
 * Render functions execute inside the viewer's `TooltipProvider`. State-heavy
 * demos (Switch, Tabs, custom motion playgrounds, etc.) wrap themselves in
 * tiny inline components so each render is self-contained.
 */

import { useState, type ReactNode } from 'react';
import {
  ChevronDown,
  Mail,
  MoreHorizontal,
  Plus,
  Settings as SettingsIcon,
} from 'lucide-react';

import { Accordion, AccordionContent, AccordionItem, AccordionTrigger } from '@/components/ui/accordion';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from '@/components/ui/dialog';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { Input } from '@/components/ui/input';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
  SheetTrigger,
} from '@/components/ui/sheet';
import { Switch } from '@/components/ui/switch';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Tooltip, TooltipContent, TooltipTrigger } from '@/components/ui/tooltip';

/* -------------------------------------------------------------------------- */
/* Types                                                                       */
/* -------------------------------------------------------------------------- */

export type ComponentCategory =
  | 'buttons'
  | 'forms'
  | 'layout'
  | 'feedback'
  | 'overlays'
  | 'navigation';

export interface ComponentEntry {
  /** Display name in the gallery row header. */
  name: string;
  /** Logical grouping. Determines the section order on the page. */
  category: ComponentCategory;
  /** Repo-relative source path. Surfaced as a small label so reviewers can jump to the primitive fast. */
  file: string;
  /** Free-form caption rendered under the row, e.g. cross-platform note. */
  notes?: string;
  /** Either a single render (for monolithic samples) or a list of named variant renders. */
  render?: () => ReactNode;
  variants?: Array<{ name: string; render: () => ReactNode }>;
}

/* -------------------------------------------------------------------------- */
/* Stateful demo components                                                    */
/* -------------------------------------------------------------------------- */

function SwitchDemo() {
  const [on, setOn] = useState(true);
  return (
    <div className="flex flex-wrap items-center gap-4">
      <div className="flex items-center gap-3">
        <Switch checked={on} onCheckedChange={setOn} aria-label="Toggle preview" />
        <span className="text-sm">{on ? 'On' : 'Off'}</span>
      </div>
      <Switch disabled aria-label="Disabled toggle" />
    </div>
  );
}

/**
 * Glass buttons need a non-flat backdrop so the backdrop-blur is visible.
 * We render the variant over a soft gradient so the glass effect reads.
 */
function GlassButtonStage() {
  return (
    <div className="relative overflow-hidden rounded-xl border border-border/60 bg-gradient-to-br from-indigo-400/40 via-fuchsia-300/30 to-amber-200/40 p-6 dark:from-indigo-900/40 dark:via-fuchsia-900/30 dark:to-amber-800/30">
      {/* Subtle decorative orbs so the blur is obvious even on a small swatch. */}
      <div
        aria-hidden
        className="pointer-events-none absolute -left-6 -top-6 h-24 w-24 rounded-full bg-white/40 blur-2xl"
      />
      <div
        aria-hidden
        className="pointer-events-none absolute -bottom-8 -right-6 h-28 w-28 rounded-full bg-indigo-500/40 blur-2xl"
      />
      <div className="relative flex flex-wrap items-center gap-3">
        <Button variant="glass">Glass</Button>
        <Button variant="glass" size="sm">
          Glass small
        </Button>
        <Button variant="glass" size="icon" aria-label="Glass icon">
          <SettingsIcon />
        </Button>
      </div>
    </div>
  );
}

/* -------------------------------------------------------------------------- */
/* Manifest                                                                    */
/* -------------------------------------------------------------------------- */

export const COMPONENT_MANIFEST: ReadonlyArray<ComponentEntry> = [
  {
    name: 'Button',
    category: 'buttons',
    file: 'components/ui/button.tsx',
    variants: [
      { name: 'default', render: () => <Button>Default</Button> },
      { name: 'secondary', render: () => <Button variant="secondary">Secondary</Button> },
      { name: 'outline', render: () => <Button variant="outline">Outline</Button> },
      { name: 'ghost', render: () => <Button variant="ghost">Ghost</Button> },
      { name: 'destructive', render: () => <Button variant="destructive">Destructive</Button> },
      { name: 'link', render: () => <Button variant="link">Link</Button> },
      { name: 'main', render: () => <Button variant="main">Main</Button> },
      { name: 'sm', render: () => <Button size="sm">Small</Button> },
      { name: 'xs', render: () => <Button size="xs">Extra small</Button> },
      { name: 'lg', render: () => <Button size="lg">Large</Button> },
      {
        name: 'icon',
        render: () => (
          <Button size="icon" aria-label="Settings">
            <SettingsIcon />
          </Button>
        ),
      },
      { name: 'disabled', render: () => <Button disabled>Disabled</Button> },
      { name: 'loading', render: () => <Button isLoading>Loading</Button> },
    ],
  },
  {
    name: 'Button — Liquid Glass',
    category: 'buttons',
    file: 'components/ui/button.tsx',
    notes:
      'Sister of iOS `LiquidGlassButtonStyle` (AppTheme.swift). Renders over a colored backdrop so the blur is visible. Press: scale 0.97 + brightness lift.',
    render: () => <GlassButtonStage />,
  },
  {
    name: 'Badge',
    category: 'feedback',
    file: 'components/ui/badge.tsx',
    variants: [
      { name: 'default', render: () => <Badge>Default</Badge> },
      { name: 'secondary', render: () => <Badge variant="secondary">Secondary</Badge> },
      { name: 'outline', render: () => <Badge variant="outline">Outline</Badge> },
      { name: 'destructive', render: () => <Badge variant="destructive">Destructive</Badge> },
      { name: 'important', render: () => <Badge variant="important">Important</Badge> },
      { name: 'promotions', render: () => <Badge variant="promotions">Promotions</Badge> },
      { name: 'personal', render: () => <Badge variant="personal">Personal</Badge> },
      { name: 'updates', render: () => <Badge variant="updates">Updates</Badge> },
      { name: 'forums', render: () => <Badge variant="forums">Forums</Badge> },
    ],
  },
  {
    name: 'Card',
    category: 'layout',
    file: 'components/ui/card.tsx',
    render: () => (
      <Card className="w-full max-w-sm">
        <CardHeader>
          <CardTitle>Inbox today</CardTitle>
        </CardHeader>
        <CardContent>
          <p className="text-muted-foreground text-sm">
            12 unread messages across 4 conversations. Two waiting on a reply from you.
          </p>
        </CardContent>
      </Card>
    ),
  },
  {
    name: 'Input',
    category: 'forms',
    file: 'components/ui/input.tsx',
    render: () => (
      <div className="w-full max-w-sm space-y-2">
        <Input placeholder="Standard input" />
        <Input placeholder="Disabled" disabled />
        <Input type="email" placeholder="you@example.com" />
      </div>
    ),
  },
  {
    name: 'Switch',
    category: 'forms',
    file: 'components/ui/switch.tsx',
    render: () => <SwitchDemo />,
  },
  {
    name: 'Dropdown menu',
    category: 'overlays',
    file: 'components/ui/dropdown-menu.tsx',
    render: () => (
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <Button variant="outline">
            Actions <ChevronDown className="ml-1 h-3.5 w-3.5" />
          </Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="start">
          <DropdownMenuLabel>Quick actions</DropdownMenuLabel>
          <DropdownMenuSeparator />
          <DropdownMenuItem>
            <Mail className="mr-2 h-4 w-4" /> New message
          </DropdownMenuItem>
          <DropdownMenuItem>
            <Plus className="mr-2 h-4 w-4" /> New folder
          </DropdownMenuItem>
          <DropdownMenuSeparator />
          <DropdownMenuItem>
            <MoreHorizontal className="mr-2 h-4 w-4" /> More
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>
    ),
  },
  {
    name: 'Dialog',
    category: 'overlays',
    file: 'components/ui/dialog.tsx',
    render: () => (
      <Dialog>
        <DialogTrigger asChild>
          <Button variant="outline">Open dialog</Button>
        </DialogTrigger>
        <DialogContent showOverlay className="max-w-md">
          <DialogHeader>
            <DialogTitle>Confirm reschedule</DialogTitle>
            <DialogDescription>
              This will move the meeting to tomorrow at 09:00 and notify all attendees.
            </DialogDescription>
          </DialogHeader>
          <div className="flex justify-end gap-2 pt-2">
            <Button variant="ghost">Cancel</Button>
            <Button>Reschedule</Button>
          </div>
        </DialogContent>
      </Dialog>
    ),
  },
  {
    name: 'Sheet',
    category: 'overlays',
    file: 'components/ui/sheet.tsx',
    render: () => (
      <Sheet>
        <SheetTrigger asChild>
          <Button variant="outline">Open sheet</Button>
        </SheetTrigger>
        <SheetContent side="right" className="w-[320px] sm:w-[420px]">
          <SheetHeader>
            <SheetTitle>Conversation details</SheetTitle>
            <SheetDescription>
              Side panel renders with the slow + emphasized motion token.
            </SheetDescription>
          </SheetHeader>
        </SheetContent>
      </Sheet>
    ),
  },
  {
    name: 'Tabs',
    category: 'navigation',
    file: 'components/ui/tabs.tsx',
    render: () => (
      <Tabs defaultValue="inbox" className="w-full max-w-sm">
        <TabsList>
          <TabsTrigger value="inbox">Inbox</TabsTrigger>
          <TabsTrigger value="drafts">Drafts</TabsTrigger>
          <TabsTrigger value="sent">Sent</TabsTrigger>
        </TabsList>
        <TabsContent value="inbox">
          <p className="text-muted-foreground text-sm">12 unread</p>
        </TabsContent>
        <TabsContent value="drafts">
          <p className="text-muted-foreground text-sm">3 drafts</p>
        </TabsContent>
        <TabsContent value="sent">
          <p className="text-muted-foreground text-sm">128 sent</p>
        </TabsContent>
      </Tabs>
    ),
  },
  {
    name: 'Popover',
    category: 'overlays',
    file: 'components/ui/popover.tsx',
    render: () => (
      <Popover>
        <PopoverTrigger asChild>
          <Button variant="outline">Open popover</Button>
        </PopoverTrigger>
        <PopoverContent>
          <p className="text-sm">
            Popovers use the standard motion token for enter / exit. Avoid for content over ~80
            characters — use a Sheet instead.
          </p>
        </PopoverContent>
      </Popover>
    ),
  },
  {
    name: 'Tooltip',
    category: 'overlays',
    file: 'components/ui/tooltip.tsx',
    notes: 'Hover any button below to render a tooltip variant.',
    variants: [
      {
        name: 'default',
        render: () => (
          <Tooltip>
            <TooltipTrigger asChild>
              <Button variant="outline" size="sm">
                Default
              </Button>
            </TooltipTrigger>
            <TooltipContent>Default tooltip</TooltipContent>
          </Tooltip>
        ),
      },
      {
        name: 'destructive',
        render: () => (
          <Tooltip>
            <TooltipTrigger asChild>
              <Button variant="outline" size="sm">
                Destructive
              </Button>
            </TooltipTrigger>
            <TooltipContent variant="destructive">Destructive tooltip</TooltipContent>
          </Tooltip>
        ),
      },
      {
        name: 'important',
        render: () => (
          <Tooltip>
            <TooltipTrigger asChild>
              <Button variant="outline" size="sm">
                Important
              </Button>
            </TooltipTrigger>
            <TooltipContent variant="important">Important tooltip</TooltipContent>
          </Tooltip>
        ),
      },
    ],
  },
  {
    name: 'Accordion',
    category: 'layout',
    file: 'components/ui/accordion.tsx',
    render: () => (
      <Accordion type="single" collapsible className="w-full max-w-md">
        <AccordionItem value="item-1">
          <AccordionTrigger>What is the design system viewer?</AccordionTrigger>
          <AccordionContent>
            A dogfood-only surface for spotting cross-platform drift early.
          </AccordionContent>
        </AccordionItem>
        <AccordionItem value="item-2">
          <AccordionTrigger>How do I add a new token?</AccordionTrigger>
          <AccordionContent>
            Add it to globals.css :root, expose it inside @theme inline, then surface it here.
          </AccordionContent>
        </AccordionItem>
      </Accordion>
    ),
  },
];

/* -------------------------------------------------------------------------- */
/* Category metadata                                                           */
/* -------------------------------------------------------------------------- */

export const CATEGORY_ORDER: ReadonlyArray<ComponentCategory> = [
  'buttons',
  'forms',
  'layout',
  'feedback',
  'overlays',
  'navigation',
];

export const CATEGORY_LABELS: Readonly<Record<ComponentCategory, string>> = {
  buttons: 'Buttons',
  forms: 'Forms',
  layout: 'Layout',
  feedback: 'Feedback',
  overlays: 'Overlays',
  navigation: 'Navigation',
};

/**
 * Repo-relative path to this manifest. Surfaced in the viewer as the "Add new
 * component" callout so the next contributor knows exactly which file to edit.
 */
export const MANIFEST_FILE_PATH =
  'apps/web/app/(routes)/settings/design-system/_components-manifest.tsx';
