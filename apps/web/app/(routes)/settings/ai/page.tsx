/**
 * AI Assistant settings page.
 *
 * Single scrollable surface owned by:
 * - Permissions (toggles — true on/off semantics)
 * - Personalization (stacked label/input fields)
 * - Mail Assistant (grouped list rows with subheaders, mixed controls)
 * - Model + Ollama
 *
 * Visual model: one flat page, sections separated by spacing + subheaders.
 * Inside a section, related rows live in a single bordered container with
 * internal hairline dividers — no nested cards.
 */

import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import {
  Bot,
  Trash2,
  Download,
  CircleCheck,
  CircleAlert,
  Info,
  RefreshCw,
  Loader2,
  MapPin,
} from 'lucide-react';
import {
  useOllamaModels,
  useOllamaStatus,
  useOllamaPull,
  useOllamaDelete,
} from '@/hooks/use-ollama';
import {
  assistantDefaultExcludedSendersPlaceholder,
  assistantAutoSendScenarioSchema,
  defaultAssistantAutomationPolicy,
} from '@zero/server/schemas';
import { formatModelSize, OLLAMA_CORS_HELP } from '@/lib/ollama-utils';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { ModelSelector } from '@/components/ui/model-selector';
import type { OllamaPullProgress } from '@/lib/ollama-utils';
import { useState, useCallback, useEffect, type ReactNode } from 'react';
import { useTRPC } from '@/providers/query-provider';
import { Progress } from '@/components/ui/progress';
import { useSettings } from '@/hooks/use-settings';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { Switch } from '@/components/ui/switch';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { m } from '@/paraglide/messages';
import { toast } from 'sonner';
import { cn } from '@/lib/utils';
import * as z from 'zod';

type AssistantAutoSendScenario = z.infer<typeof assistantAutoSendScenarioSchema>;

const assistantAutoSendScenarioOptions: ReadonlyArray<
  readonly [AssistantAutoSendScenario, string]
> = [
  ['acknowledgment', 'Acknowledgments'],
  ['simple_confirmation', 'Simple confirmations'],
  ['scheduling_confirmation', 'Scheduling confirmations'],
];

export default function AISettingsPage() {
  const { data: settings, refetch: refetchSettings } = useSettings();
  const trpc = useTRPC();
  const queryClient = useQueryClient();
  const ollamaBaseUrl = settings?.settings?.ollamaBaseUrl ?? 'http://localhost:11434';
  const { mutateAsync: saveUserSettings } = useMutation(trpc.settings.save.mutationOptions());

  const s = settings?.settings as any;
  const policy = s?.assistantAutomationPolicy ?? defaultAssistantAutomationPolicy;

  const patch = async (changes: Record<string, unknown>) => {
    if (!settings?.settings) return;
    const snapshot = settings.settings;
    queryClient.setQueryData(trpc.settings.get.queryKey(), (updater) => {
      if (!updater) return;
      return { settings: { ...updater.settings, ...changes } };
    });
    try {
      await saveUserSettings({ ...snapshot, ...changes } as any);
    } catch {
      toast.error(m['common.settings.failedToSave']());
      queryClient.setQueryData(trpc.settings.get.queryKey(), (updater) => {
        if (!updater) return;
        return { settings: snapshot };
      });
    }
  };

  const patchPolicy = (changes: Record<string, unknown>) =>
    patch({ assistantAutomationPolicy: { ...policy, ...changes } });

  const [showRecommendedConfirm, setShowRecommendedConfirm] = useState(false);
  const [excludedSendersDraft, setExcludedSendersDraft] = useState<string>(
    (policy.excludedSenderPatterns ?? []).join('\n'),
  );
  useEffect(() => {
    setExcludedSendersDraft((policy.excludedSenderPatterns ?? []).join('\n'));
  }, [policy.excludedSenderPatterns]);

  const applyRecommended = async () => {
    setShowRecommendedConfirm(false);
    await patch({ assistantAutomationPolicy: defaultAssistantAutomationPolicy });
    toast.success('Recommended assistant defaults applied');
  };

  // Ollama state
  const { data: ollamaOnline, refetch: refetchStatus } = useOllamaStatus(ollamaBaseUrl);
  const {
    data: ollamaModels,
    isLoading: modelsLoading,
    refetch: refetchModels,
  } = useOllamaModels(ollamaBaseUrl, ollamaOnline === true);
  const [pullModelName, setPullModelName] = useState('');
  const [pullProgress, setPullProgress] = useState<OllamaPullProgress | null>(null);
  const [pullPercent, setPullPercent] = useState(0);
  const handlePullProgress = useCallback((progress: OllamaPullProgress) => {
    setPullProgress(progress);
    if (progress.total && progress.completed) {
      setPullPercent(Math.round((progress.completed / progress.total) * 100));
    }
  }, []);
  const pullMutation = useOllamaPull(ollamaBaseUrl, handlePullProgress);
  const deleteMutation = useOllamaDelete(ollamaBaseUrl);
  const [baseUrlInput, setBaseUrlInput] = useState(ollamaBaseUrl);
  useEffect(() => setBaseUrlInput(ollamaBaseUrl), [ollamaBaseUrl]);

  const saveSettings = useMutation(
    trpc.settings.save.mutationOptions({
      onSuccess: () => {
        queryClient.invalidateQueries({ queryKey: trpc.settings.get.queryKey() });
      },
    }),
  );
  const handleSaveBaseUrl = useCallback(() => {
    saveSettings.mutate(
      { ...settings?.settings, ollamaBaseUrl: baseUrlInput },
      {
        onSuccess: () => toast.success('Ollama URL saved'),
        onError: (error) => toast.error(`Failed to save Ollama URL: ${error.message}`),
      },
    );
  }, [baseUrlInput, saveSettings, settings?.settings]);
  const handlePullModel = useCallback(async () => {
    if (!pullModelName.trim()) return;
    setPullProgress(null);
    setPullPercent(0);
    try {
      await pullMutation.mutateAsync(pullModelName.trim());
      toast.success(`Model "${pullModelName}" pulled successfully`);
      setPullModelName('');
      setPullProgress(null);
      setPullPercent(0);
    } catch (error) {
      toast.error(
        `Failed to pull "${pullModelName}": ${error instanceof Error ? error.message : 'Unknown error'}`,
      );
    }
  }, [pullModelName, pullMutation]);
  const handleDeleteModel = useCallback(
    async (name: string) => {
      try {
        await deleteMutation.mutateAsync(name);
        toast.success(`Model "${name}" deleted`);
      } catch (error) {
        toast.error(
          `Failed to delete "${name}": ${error instanceof Error ? error.message : 'Unknown error'}`,
        );
      }
    },
    [deleteMutation],
  );

  const hours = Array.from({ length: 24 }, (_, h) => h);
  const formatHour = (h: number) =>
    `${h.toString().padStart(2, '0')}:00 (${h === 0 ? '12 AM' : h < 12 ? `${h} AM` : h === 12 ? '12 PM' : `${h - 12} PM`})`;

  return (
    <div className="space-y-10">
      <Section
        title="Permissions"
        description="Control what the assistant can read and write on your behalf."
      >
        <RowList>
          <ToggleRow
            label="Read tasks"
            description="View existing tasks."
            checked={s?.aiCanReadTasks ?? true}
            onChange={(v) => patch({ aiCanReadTasks: v })}
          />
          <ToggleRow
            label="Create & edit tasks"
            description="Add and update tasks."
            checked={s?.aiCanWriteTasks ?? true}
            onChange={(v) => patch({ aiCanWriteTasks: v })}
          />
          <ToggleRow
            label="Read calendar"
            description="See upcoming events."
            checked={s?.aiCanReadCalendar ?? true}
            onChange={(v) => patch({ aiCanReadCalendar: v })}
          />
          <ToggleRow
            label="Create calendar events"
            description="Add new events."
            checked={s?.aiCanWriteCalendar ?? true}
            onChange={(v) => patch({ aiCanWriteCalendar: v })}
          />
          <ToggleRow
            label="Read email"
            description="Read your inbox."
            checked={s?.aiCanReadEmail ?? true}
            onChange={(v) => patch({ aiCanReadEmail: v })}
          />
          <ToggleRow
            label="Send email"
            description="Draft and send messages."
            checked={s?.aiCanSendEmail ?? true}
            onChange={(v) => patch({ aiCanSendEmail: v })}
          />
        </RowList>
      </Section>

      <Section
        title="Personalization"
        description="Give the assistant context about you and tune how it should respond."
      >
        <div className="space-y-5">
          <Field
            label="Location"
            description="City and country. Optional — gives the AI location context."
          >
            <div className="relative mt-1">
              <MapPin className="text-muted-foreground pointer-events-none absolute left-2.5 top-1/2 h-4 w-4 -translate-y-1/2" />
              <Input
                value={s?.location ?? ''}
                onChange={(e) => patch({ location: e.target.value })}
                placeholder="e.g. Oslo, Norway"
                className="h-9 pl-8"
              />
            </div>
          </Field>
          <Field label="Context about you">
            <Textarea
              value={s?.contextAboutYou ?? ''}
              onChange={(e) => patch({ contextAboutYou: e.target.value })}
              placeholder="Anything the assistant should know — your role, projects, tone, communication style…"
              className="min-h-[100px] resize-y"
            />
          </Field>
          <Field label="Custom instructions">
            <Textarea
              value={s?.customPrompt ?? ''}
              onChange={(e) => patch({ customPrompt: e.target.value })}
              placeholder="e.g. Keep replies under 3 sentences. Never use emojis."
              className="min-h-[100px] resize-y"
            />
          </Field>
        </div>
      </Section>

      <Section
        title="Mail Assistant"
        description="What Todus may prepare for you automatically."
        action={
          <Button
            variant="ghost"
            size="sm"
            className="h-7 text-xs"
            onClick={() => setShowRecommendedConfirm(true)}
          >
            Reset to recommended
          </Button>
        }
      >
        <Subheader title="Briefing" />
        <RowList>
          <ToggleRow
            label="Briefing engine"
            description="Continuously prepare open loops, prepared actions, and daily priorities."
            checked={!!policy.briefingEnabled}
            onChange={(v) => patchPolicy({ briefingEnabled: v })}
          />
          <ToggleRow
            label="Show briefing on Home"
            description="Surface Today, Needs You, Waiting On, Prepared, and Changed Since."
            checked={!!policy.showHomeBriefing}
            onChange={(v) => patchPolicy({ showHomeBriefing: v })}
          />
          <ToggleRow
            label="Auto-summarize long threads"
            description="Generate summaries for long conversations by default."
            checked={!!policy.autoSummarizeLongThreads}
            onChange={(v) => patchPolicy({ autoSummarizeLongThreads: v })}
          />
        </RowList>

        <Subheader title="Triage" />
        <RowList>
          <ToggleRow
            label="Suggest tasks from emails"
            description="Turn actionable requests into proposed tasks."
            checked={!!policy.suggestTasksFromEmail}
            onChange={(v) => patchPolicy({ suggestTasksFromEmail: v })}
          />
          <ToggleRow
            label="Suggest events from emails"
            description="Detect scheduling and surface one-tap event creation."
            checked={!!policy.suggestEventsFromEmail}
            onChange={(v) => patchPolicy({ suggestEventsFromEmail: v })}
          />
          <ToggleRow
            label="Smart reply nudges"
            description="Highlight threads that likely need a response."
            checked={!!policy.smartReplyNudges}
            onChange={(v) => patchPolicy({ smartReplyNudges: v })}
          />
          <ToggleRow
            label="Smart deadline nudges"
            description="Warn about likely deadlines or stale commitments."
            checked={!!policy.smartDeadlineNudges}
            onChange={(v) => patchPolicy({ smartDeadlineNudges: v })}
          />
          <ToggleRow
            label="Track waiting-on threads"
            description="Keep a queue for commitments blocked on someone else."
            checked={!!policy.trackWaitingOnThreads}
            onChange={(v) => patchPolicy({ trackWaitingOnThreads: v })}
          />
        </RowList>

        <Subheader title="Drafts &amp; replies" />
        <RowList>
          <ToggleRow
            label="Auto-draft replies"
            description="Prepare high-confidence reply drafts for review."
            checked={!!policy.autoDraftReplies}
            onChange={(v) => patchPolicy({ autoDraftReplies: v })}
          />
          <ToggleRow
            label="Show assistant controls in threads"
            description="Summarize, extract, create-event actions above every thread."
            checked={!!policy.assistantThreadActionsVisible}
            onChange={(v) => patchPolicy({ assistantThreadActionsVisible: v })}
          />
          <ToggleRow
            label="Batch approvals"
            description="Queue prepared actions for batch approval instead of one-by-one."
            checked={!!policy.batchApprovalEnabled}
            onChange={(v) => patchPolicy({ batchApprovalEnabled: v })}
          />
        </RowList>

        <Subheader title="Memory" />
        <RowList>
          <ToggleRow
            label="Build people memory"
            description="Remember recent communication and relationship context."
            checked={!!policy.peopleMemoryEnabled}
            onChange={(v) => patchPolicy({ peopleMemoryEnabled: v })}
          />
        </RowList>

        <Subheader title="Workday" />
        <RowList>
          <SelectRow
            label="Workday starts"
            value={String(policy.workdayStartHour ?? defaultAssistantAutomationPolicy.workdayStartHour)}
            options={hours.map((h) => ({ value: String(h), label: formatHour(h) }))}
            onChange={(v) => patchPolicy({ workdayStartHour: Number(v) })}
          />
          <SelectRow
            label="Workday ends"
            value={String(policy.workdayEndHour ?? defaultAssistantAutomationPolicy.workdayEndHour)}
            options={hours.map((h) => ({ value: String(h), label: formatHour(h) }))}
            onChange={(v) => patchPolicy({ workdayEndHour: Number(v) })}
          />
        </RowList>
        <Field
          label="Excluded senders and topics"
          description="One pattern per line. Suppress open loops and prepared actions for low-value automation."
        >
          <Textarea
            value={excludedSendersDraft}
            onChange={(e) => setExcludedSendersDraft(e.target.value)}
            onBlur={() =>
              patchPolicy({
                excludedSenderPatterns: excludedSendersDraft
                  .split('\n')
                  .map((v) => v.trim())
                  .filter(Boolean),
              })
            }
            placeholder={assistantDefaultExcludedSendersPlaceholder}
            className="min-h-[88px] resize-y"
          />
        </Field>

        <Subheader title="Auto-send (advanced)" />
        <p className="text-muted-foreground -mt-1 mb-2 text-xs">
          Off by default. Lets the assistant send narrow, low-risk replies on your behalf inside
          your workday.
        </p>
        <RowList>
          <ToggleRow
            label="Enable low-risk auto-send experiment"
            description="Only high-confidence acknowledgements and confirmations qualify."
            checked={!!policy.autoSendExperimentEnabled}
            onChange={(v) => patchPolicy({ autoSendExperimentEnabled: v })}
          />
          <SelectRow
            label="Quiet hours start"
            value={String(
              policy.autoSendQuietHours?.startHour ??
                defaultAssistantAutomationPolicy.autoSendQuietHours.startHour,
            )}
            options={hours.map((h) => ({ value: String(h), label: formatHour(h) }))}
            onChange={(v) =>
              patchPolicy({
                autoSendQuietHours: {
                  ...(policy.autoSendQuietHours ?? defaultAssistantAutomationPolicy.autoSendQuietHours),
                  startHour: Number(v),
                },
              })
            }
          />
          <SelectRow
            label="Quiet hours end"
            value={String(
              policy.autoSendQuietHours?.endHour ??
                defaultAssistantAutomationPolicy.autoSendQuietHours.endHour,
            )}
            options={hours.map((h) => ({ value: String(h), label: formatHour(h) }))}
            onChange={(v) =>
              patchPolicy({
                autoSendQuietHours: {
                  ...(policy.autoSendQuietHours ?? defaultAssistantAutomationPolicy.autoSendQuietHours),
                  endHour: Number(v),
                },
              })
            }
          />
        </RowList>
        <Field
          label="Allowed auto-send scenarios"
          description="Keep narrow. Only matters when the experiment is on."
        >
          <div className="flex flex-wrap gap-1.5">
            {assistantAutoSendScenarioOptions.map(([value, label]) => {
              const selected = (policy.autoSendAllowedScenarios ?? []).includes(value);
              return (
                <Button
                  key={value}
                  type="button"
                  variant={selected ? 'default' : 'outline'}
                  size="sm"
                  className="h-7 rounded-full text-xs"
                  onClick={() => {
                    const current: AssistantAutoSendScenario[] =
                      policy.autoSendAllowedScenarios ?? [];
                    const next = current.includes(value)
                      ? current.filter((s) => s !== value)
                      : [...current, value];
                    patchPolicy({ autoSendAllowedScenarios: next });
                  }}
                >
                  {label}
                </Button>
              );
            })}
          </div>
        </Field>
      </Section>

      <Section
        title="Model"
        description="Which model powers chat, email composition, and background tasks."
      >
        <ModelSelector variant="full" />
      </Section>

      <Section
        title="Local models (Ollama)"
        description="Run models locally for privacy, cost savings, and offline use."
        action={
          <div className="flex items-center gap-2">
            {ollamaOnline === true ? (
              <span className="flex items-center gap-1.5 text-xs text-green-600 dark:text-green-400">
                <CircleCheck className="h-3.5 w-3.5" />
                Connected
              </span>
            ) : ollamaOnline === false ? (
              <span className="text-destructive flex items-center gap-1.5 text-xs">
                <CircleAlert className="h-3.5 w-3.5" />
                Offline
              </span>
            ) : (
              <span className="text-muted-foreground text-xs">Checking…</span>
            )}
            <Button
              variant="ghost"
              size="sm"
              className="h-7 w-7 p-0"
              onClick={() => {
                refetchStatus();
                refetchModels();
              }}
            >
              <RefreshCw className="h-3.5 w-3.5" />
            </Button>
          </div>
        }
      >
        <Field label="Ollama URL" description="Default: http://localhost:11434.">
          <div className="flex gap-2">
            <Input
              value={baseUrlInput}
              onChange={(e) => setBaseUrlInput(e.target.value)}
              placeholder="http://localhost:11434"
              className="h-9 flex-1"
            />
            <Button
              variant="secondary"
              size="sm"
              onClick={handleSaveBaseUrl}
              disabled={baseUrlInput === ollamaBaseUrl}
            >
              Save
            </Button>
          </div>
        </Field>

        <div className="space-y-2">
          <div className="flex items-center justify-between">
            <h4 className="text-sm font-medium">Installed models</h4>
            {modelsLoading && (
              <Loader2 className="text-muted-foreground h-3.5 w-3.5 animate-spin" />
            )}
          </div>
          {ollamaOnline === true && ollamaModels && ollamaModels.length > 0 ? (
            <RowList>
              {ollamaModels.map((model) => (
                <div
                  key={model.name}
                  className="flex items-center justify-between gap-2 py-2"
                >
                  <div className="flex min-w-0 items-center gap-2.5">
                    <Bot className="text-muted-foreground h-4 w-4 shrink-0" />
                    <div className="min-w-0">
                      <p className="truncate text-sm">{model.name}</p>
                      <p className="text-muted-foreground text-xs">
                        {formatModelSize(model.size)}
                        {model.details?.parameter_size && ` · ${model.details.parameter_size}`}
                        {model.details?.quantization_level &&
                          ` · ${model.details.quantization_level}`}
                      </p>
                    </div>
                  </div>
                  <Button
                    variant="ghost"
                    size="sm"
                    className="text-muted-foreground hover:text-destructive h-7 w-7 p-0"
                    onClick={() => handleDeleteModel(model.name)}
                    disabled={deleteMutation.isPending}
                  >
                    <Trash2 className="h-3.5 w-3.5" />
                  </Button>
                </div>
              ))}
            </RowList>
          ) : ollamaOnline === true ? (
            <p className="text-muted-foreground text-xs">No models installed. Pull one below.</p>
          ) : (
            <p className="text-muted-foreground text-xs">
              Cannot connect to {ollamaBaseUrl}. Make sure{' '}
              <code className="bg-muted rounded px-1 font-mono text-xs">ollama serve</code> is
              running.
            </p>
          )}
        </div>

        {ollamaOnline === true && (
          <Field
            label="Pull a model"
            description={
              <>
                Browse models at{' '}
                <a
                  href="https://ollama.com/library"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="hover:text-foreground underline"
                >
                  ollama.com/library
                </a>
                .
              </>
            }
          >
            <div className="flex gap-2">
              <Input
                value={pullModelName}
                onChange={(e) => setPullModelName(e.target.value)}
                placeholder="e.g. llama3.2, mistral, gemma2"
                className="h-9 flex-1"
                onKeyDown={(e) => {
                  if (e.key === 'Enter') handlePullModel();
                }}
                disabled={pullMutation.isPending}
              />
              <Button
                variant="secondary"
                size="sm"
                onClick={handlePullModel}
                disabled={pullMutation.isPending || !pullModelName.trim()}
              >
                {pullMutation.isPending ? (
                  <Loader2 className="mr-1.5 h-3.5 w-3.5 animate-spin" />
                ) : (
                  <Download className="mr-1.5 h-3.5 w-3.5" />
                )}
                Pull
              </Button>
            </div>
            {pullMutation.isPending && pullProgress && (
              <div className="mt-2 space-y-1.5">
                <Progress value={pullPercent} className="h-2" />
                <p className="text-muted-foreground text-xs">
                  {pullProgress.status}
                  {pullPercent > 0 && ` (${pullPercent}%)`}
                </p>
              </div>
            )}
          </Field>
        )}

        {ollamaOnline === false && (
          <div className="border-border/60 bg-muted/30 rounded-md border p-3">
            <div className="flex items-start gap-2">
              <Info className="text-muted-foreground mt-0.5 h-4 w-4 shrink-0" />
              <div className="space-y-1.5">
                <p className="text-sm font-medium">Troubleshooting</p>
                <p className="text-muted-foreground text-xs">
                  If Ollama runs but the connection fails, configure CORS:
                </p>
                <pre className="bg-muted whitespace-pre-wrap rounded p-2 font-mono text-xs">
                  {OLLAMA_CORS_HELP}
                </pre>
              </div>
            </div>
          </div>
        )}
      </Section>

      <Dialog open={showRecommendedConfirm} onOpenChange={setShowRecommendedConfirm}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Replace all Mail Assistant settings?</DialogTitle>
            <DialogDescription>
              Overwrites every toggle, workday hours, quiet hours, and excluded sender patterns
              with the recommended defaults. Your custom values will be lost.
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button variant="secondary" onClick={() => setShowRecommendedConfirm(false)}>
              Cancel
            </Button>
            <Button variant="destructive" onClick={applyRecommended}>
              Apply recommended
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}

function Section({
  title,
  description,
  action,
  children,
}: {
  title: string;
  description?: string;
  action?: ReactNode;
  children: ReactNode;
}) {
  return (
    <section className="space-y-3">
      <header className="flex items-start justify-between gap-3">
        <div className="space-y-0.5">
          <h2 className="text-base font-semibold tracking-tight">{title}</h2>
          {description && (
            <p className="text-muted-foreground text-xs">{description}</p>
          )}
        </div>
        {action}
      </header>
      <div className="space-y-3">{children}</div>
    </section>
  );
}

function Subheader({ title }: { title: string }) {
  return (
    <h3 className="text-muted-foreground mt-4 text-[11px] font-medium uppercase tracking-wider first:mt-0">
      {title}
    </h3>
  );
}

function RowList({ children, className }: { children: ReactNode; className?: string }) {
  return (
    <div
      className={cn(
        'border-border/60 divide-border/60 divide-y overflow-hidden rounded-lg border',
        className,
      )}
    >
      {Array.isArray(children)
        ? children.map((child, i) => (
            <div key={i} className="px-3">
              {child}
            </div>
          ))
        : <div className="px-3">{children}</div>}
    </div>
  );
}

function ToggleRow({
  label,
  description,
  checked,
  onChange,
}: {
  label: string;
  description?: string;
  checked: boolean;
  onChange: (next: boolean) => void;
}) {
  return (
    <div className="flex items-center justify-between gap-4 py-2.5">
      <div className="min-w-0 flex-1">
        <p className="text-sm">{label}</p>
        {description && <p className="text-muted-foreground text-xs">{description}</p>}
      </div>
      <Switch checked={checked} onCheckedChange={onChange} />
    </div>
  );
}

function SelectRow({
  label,
  value,
  options,
  onChange,
  width = 180,
}: {
  label: string;
  value: string;
  options: { value: string; label: string }[];
  onChange: (next: string) => void;
  width?: number;
}) {
  return (
    <div className="flex items-center justify-between gap-4 py-2">
      <p className="text-sm">{label}</p>
      <Select value={value} onValueChange={onChange}>
        <SelectTrigger className="h-8" style={{ width }}>
          <SelectValue />
        </SelectTrigger>
        <SelectContent>
          {options.map((o) => (
            <SelectItem key={o.value} value={o.value}>
              {o.label}
            </SelectItem>
          ))}
        </SelectContent>
      </Select>
    </div>
  );
}

function Field({
  label,
  description,
  children,
}: {
  label: string;
  description?: ReactNode;
  children: ReactNode;
}) {
  return (
    <div className="space-y-2">
      <label className="text-sm font-medium">{label}</label>
      {children}
      {description && <p className="text-muted-foreground text-xs">{description}</p>}
    </div>
  );
}
