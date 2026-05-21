/**
 * Local Models settings page.
 *
 * Mirrors the macOS `MacLocalModelsView`. Lists Ollama models installed on
 * the user's machine, lets them pull new ones (with streaming progress),
 * delete them, set one as the default chat model, and pick from a small
 * grid of suggested models.
 *
 * Auth is handled by the parent `settings/layout.tsx` clientLoader.
 */

import {
  Bot,
  Cpu,
  Trash2,
  Download,
  CircleCheck,
  CircleAlert,
  RefreshCw,
  Loader2,
  Check,
} from 'lucide-react';
import {
  useOllamaModels,
  useOllamaStatus,
  useOllamaPull,
  useOllamaDelete,
} from '@/hooks/use-ollama';
import { formatModelSize } from '@/lib/ollama-utils';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { SettingsCard } from '@/components/settings/settings-card';
import type { OllamaPullProgress } from '@/lib/ollama-utils';
import { useState, useCallback } from 'react';
import { useTRPC } from '@/providers/query-provider';
import { Progress } from '@/components/ui/progress';
import { useSettings } from '@/hooks/use-settings';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Badge } from '@/components/ui/badge';
import { toast } from 'sonner';

/** Hardcoded list of popular Ollama models surfaced as quick-pull suggestions. */
const SUGGESTED_MODELS: ReadonlyArray<{ name: string; description: string }> = [
  { name: 'llama3.2:3b', description: 'Meta Llama 3.2 · small & fast' },
  { name: 'qwen2.5:7b', description: 'Qwen 2.5 · strong general model' },
  { name: 'phi3:mini', description: 'Microsoft Phi-3 Mini · compact' },
  { name: 'gemma3:4b', description: 'Google Gemma 3 · efficient' },
  { name: 'mistral:7b', description: 'Mistral 7B · classic baseline' },
  { name: 'nomic-embed-text', description: 'Nomic embeddings · for RAG' },
];

function formatModifiedDate(iso: string): string {
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return '';
  return date.toLocaleDateString(undefined, {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  });
}

export default function LocalModelsPage() {
  const { data: settings } = useSettings();
  const trpc = useTRPC();
  const queryClient = useQueryClient();

  const ollamaBaseUrl = settings?.settings?.ollamaBaseUrl ?? 'http://localhost:11434';
  const currentProvider = settings?.settings?.aiProvider ?? 'auto';
  const currentModel = settings?.settings?.aiModel ?? '';

  const { data: ollamaOnline, refetch: refetchStatus } = useOllamaStatus(ollamaBaseUrl);
  const {
    data: ollamaModels,
    isLoading: modelsLoading,
    refetch: refetchModels,
  } = useOllamaModels(ollamaBaseUrl, ollamaOnline === true);

  // Pull state
  const [pullModelName, setPullModelName] = useState('');
  const [pullProgress, setPullProgress] = useState<OllamaPullProgress | null>(null);
  const [pullPercent, setPullPercent] = useState(0);
  const [pendingSuggestion, setPendingSuggestion] = useState<string | null>(null);

  const handlePullProgress = useCallback((progress: OllamaPullProgress) => {
    setPullProgress(progress);
    if (progress.total && progress.completed) {
      setPullPercent(Math.round((progress.completed / progress.total) * 100));
    }
  }, []);

  const pullMutation = useOllamaPull(ollamaBaseUrl, handlePullProgress);
  const deleteMutation = useOllamaDelete(ollamaBaseUrl);

  const saveSettings = useMutation(
    trpc.settings.save.mutationOptions({
      onSuccess: () => {
        queryClient.invalidateQueries({ queryKey: trpc.settings.get.queryKey() });
      },
    }),
  );

  const runPull = useCallback(
    async (name: string) => {
      const trimmed = name.trim();
      if (!trimmed) return;
      setPullProgress(null);
      setPullPercent(0);
      try {
        await pullMutation.mutateAsync(trimmed);
        toast.success(`Model "${trimmed}" pulled successfully`);
        if (pullModelName.trim() === trimmed) setPullModelName('');
      } catch (error) {
        toast.error(
          `Failed to pull "${trimmed}": ${error instanceof Error ? error.message : 'Unknown error'}`,
        );
      } finally {
        setPullProgress(null);
        setPullPercent(0);
        setPendingSuggestion(null);
      }
    },
    [pullMutation, pullModelName],
  );

  const handlePullModel = useCallback(() => {
    void runPull(pullModelName);
  }, [pullModelName, runPull]);

  const handleSuggestionPull = useCallback(
    (name: string) => {
      setPendingSuggestion(name);
      void runPull(name);
    },
    [runPull],
  );

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

  const handleSetDefault = useCallback(
    (name: string) => {
      if (ollamaOnline === false) {
        toast.error('Ollama is not reachable. Start it before setting as default.');
        return;
      }
      saveSettings.mutate(
        { aiProvider: 'ollama', aiModel: name },
        {
          onSuccess: () => {
            toast.success(`"${name}" set as default chat model`);
          },
          onError: (error) => {
            toast.error(`Failed to update default model: ${error.message}`);
          },
        },
      );
    },
    [saveSettings, ollamaOnline],
  );

  // Safety net: if the user previously set Ollama as default but Ollama
  // is now unreachable, surface a one-click fallback to `auto` so the AI
  // chat doesn't silently fail every request.
  const showOllamaFallback =
    currentProvider === 'ollama' && ollamaOnline === false;
  const handleFallbackToAuto = useCallback(() => {
    saveSettings.mutate(
      { aiProvider: 'auto', aiModel: '' },
      {
        onSuccess: () => {
          toast.success('Switched to auto provider while Ollama is offline');
        },
        onError: (error) => {
          toast.error(`Failed to switch provider: ${error.message}`);
        },
      },
    );
  }, [saveSettings]);

  const isInstalled = useCallback(
    (name: string) => ollamaModels?.some((m) => m.name === name) ?? false,
    [ollamaModels],
  );

  const isCurrentDefault = (name: string): boolean =>
    currentProvider === 'ollama' && currentModel === name;

  return (
    <div className="space-y-8">
      {/* Header / status */}
      <SettingsCard
        title="Local Models"
        description="Run AI models locally with Ollama. Local models never use plan credits and keep your data on-device."
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
                Not running
              </span>
            ) : (
              <span className="text-muted-foreground flex items-center gap-1.5 text-xs">
                Checking…
              </span>
            )}
            <Button
              variant="ghost"
              size="sm"
              className="h-7 w-7 p-0"
              onClick={() => {
                refetchStatus();
                refetchModels();
              }}
              aria-label="Refresh"
            >
              <RefreshCw className="h-3.5 w-3.5" />
            </Button>
          </div>
        }
      >
        <div className="border-border/60 bg-muted/30 flex items-start gap-2.5 rounded-md border p-3">
          <Cpu className="text-muted-foreground mt-0.5 h-4 w-4 shrink-0" />
          <div className="space-y-0.5">
            <p className="text-sm">Endpoint: <code className="bg-muted rounded px-1 py-0.5 font-mono text-xs">{ollamaBaseUrl}</code></p>
            <p className="text-muted-foreground text-xs">
              Configure the Ollama URL on the AI Assistant page.
            </p>
          </div>
        </div>

        {showOllamaFallback && (
          <div
            role="alert"
            className="mt-3 flex items-start gap-3 rounded-md border border-destructive/40 bg-destructive/5 p-3 text-sm"
          >
            <CircleAlert className="text-destructive mt-0.5 h-4 w-4 shrink-0" />
            <div className="min-w-0 flex-1 space-y-2">
              <div>
                <p className="text-destructive font-medium">Your default model is Ollama, but Ollama is offline.</p>
                <p className="text-muted-foreground text-xs">
                  AI chat will fail every request until you start Ollama or switch providers.
                </p>
              </div>
              <Button
                size="sm"
                variant="outline"
                onClick={handleFallbackToAuto}
                disabled={saveSettings.isPending}
              >
                Switch to auto provider
              </Button>
            </div>
          </div>
        )}

        {ollamaOnline === false && (
          <div className="border-border/60 rounded-md border border-dashed px-4 py-6 text-center">
            <CircleAlert className="text-muted-foreground/50 mx-auto h-8 w-8" />
            <p className="text-muted-foreground mt-2 text-sm">Ollama not running</p>
            <p className="text-muted-foreground mt-1 text-xs">
              Start Ollama then refresh.{' '}
              <code className="bg-muted rounded px-1 py-0.5 font-mono text-xs">ollama serve</code>
            </p>
          </div>
        )}
      </SettingsCard>

      {/* Installed Models */}
      {ollamaOnline === true && (
        <SettingsCard
          title="Installed models"
          description="Models already downloaded on this machine."
          action={
            modelsLoading ? (
              <Loader2 className="text-muted-foreground h-3.5 w-3.5 animate-spin" />
            ) : null
          }
        >
          {ollamaModels && ollamaModels.length > 0 ? (
            <div className="border-border/60 rounded-md border">
              <div className="divide-border/60 divide-y">
                {ollamaModels.map((model) => {
                  const isDefault = isCurrentDefault(model.name);
                  return (
                    <div
                      key={model.name}
                      className="flex flex-wrap items-center justify-between gap-3 px-3 py-2.5"
                    >
                      <div className="flex min-w-0 items-center gap-2.5">
                        <Bot className="text-muted-foreground h-4 w-4 shrink-0" />
                        <div className="min-w-0">
                          <div className="flex items-center gap-2">
                            <p className="truncate text-sm font-medium">{model.name}</p>
                            {isDefault && (
                              <Badge variant="secondary" className="h-5 px-1.5 text-[10px]">
                                Default
                              </Badge>
                            )}
                          </div>
                          <p className="text-muted-foreground text-xs">
                            {formatModelSize(model.size)}
                            {model.details?.parameter_size &&
                              ` · ${model.details.parameter_size}`}
                            {model.modified_at &&
                              ` · ${formatModifiedDate(model.modified_at)}`}
                          </p>
                        </div>
                      </div>
                      <div className="flex items-center gap-1.5">
                        <Button
                          variant={isDefault ? 'secondary' : 'outline'}
                          size="sm"
                          className="h-7 text-xs"
                          onClick={() => handleSetDefault(model.name)}
                          disabled={isDefault || saveSettings.isPending}
                        >
                          {isDefault ? (
                            <>
                              <Check className="mr-1 h-3.5 w-3.5" />
                              Default
                            </>
                          ) : (
                            'Set as default'
                          )}
                        </Button>
                        <Button
                          variant="ghost"
                          size="sm"
                          className="text-muted-foreground hover:text-destructive h-7 w-7 p-0"
                          onClick={() => handleDeleteModel(model.name)}
                          disabled={deleteMutation.isPending}
                          aria-label={`Delete ${model.name}`}
                        >
                          <Trash2 className="h-3.5 w-3.5" />
                        </Button>
                      </div>
                    </div>
                  );
                })}
              </div>
            </div>
          ) : (
            <div className="border-border/60 rounded-md border border-dashed px-4 py-6 text-center">
              <Bot className="text-muted-foreground/50 mx-auto h-8 w-8" />
              <p className="text-muted-foreground mt-2 text-sm">No models installed yet</p>
              <p className="text-muted-foreground text-xs">Pull one below to get started.</p>
            </div>
          )}
        </SettingsCard>
      )}

      {/* Pull a new model */}
      {ollamaOnline === true && (
        <SettingsCard
          title="Pull a new model"
          description="Download any model from the Ollama registry by name (e.g. llama3.2:3b)."
        >
          <div className="space-y-3">
            <div className="flex gap-2">
              <Input
                value={pullModelName}
                onChange={(e) => setPullModelName(e.target.value)}
                placeholder="e.g. llama3.2:3b"
                className="flex-1"
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
              <div className="space-y-1.5">
                <Progress value={pullPercent} className="h-2" />
                <p className="text-muted-foreground text-xs">
                  {pullProgress.status}
                  {pullPercent > 0 && ` (${pullPercent}%)`}
                </p>
              </div>
            )}

            <p className="text-muted-foreground text-xs">
              Browse the catalog at{' '}
              <a
                href="https://ollama.com/library"
                target="_blank"
                rel="noopener noreferrer"
                className="hover:text-foreground underline"
              >
                ollama.com/library
              </a>
            </p>
          </div>
        </SettingsCard>
      )}

      {/* Suggested models */}
      {ollamaOnline === true && (
        <SettingsCard
          title="Suggested models"
          description="Popular picks. Click pull to download one."
        >
          <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
            {SUGGESTED_MODELS.map((suggestion) => {
              const installed = isInstalled(suggestion.name);
              const pulling = pullMutation.isPending && pendingSuggestion === suggestion.name;
              return (
                <div
                  key={suggestion.name}
                  className="border-border/60 flex items-center justify-between gap-3 rounded-md border p-3"
                >
                  <div className="min-w-0">
                    <div className="flex items-center gap-2">
                      <p className="truncate text-sm font-medium">{suggestion.name}</p>
                      {installed && (
                        <Badge variant="secondary" className="h-5 px-1.5 text-[10px]">
                          Installed
                        </Badge>
                      )}
                    </div>
                    <p className="text-muted-foreground truncate text-xs">{suggestion.description}</p>
                  </div>
                  <Button
                    variant={installed ? 'ghost' : 'outline'}
                    size="sm"
                    className="h-7 shrink-0 text-xs"
                    onClick={() => handleSuggestionPull(suggestion.name)}
                    disabled={installed || pullMutation.isPending}
                  >
                    {pulling ? (
                      <Loader2 className="mr-1 h-3.5 w-3.5 animate-spin" />
                    ) : installed ? (
                      <Check className="mr-1 h-3.5 w-3.5" />
                    ) : (
                      <Download className="mr-1 h-3.5 w-3.5" />
                    )}
                    {installed ? 'Installed' : pulling ? 'Pulling…' : 'Pull'}
                  </Button>
                </div>
              );
            })}
          </div>
        </SettingsCard>
      )}
    </div>
  );
}
