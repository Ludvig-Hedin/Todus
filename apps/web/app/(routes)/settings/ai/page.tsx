/**
 * AI & Models settings page.
 *
 * Allows users to configure their AI provider, select models, manage Ollama
 * (local LLM) installation, and configure the Ollama endpoint URL.
 *
 * When Ollama is selected as the provider, this page shows:
 * - Connection status indicator
 * - Installed models with sizes and delete buttons
 * - Model pull form with streaming progress
 * - CORS troubleshooting help
 */

import {
  Bot,
  Trash2,
  Download,
  CircleCheck,
  CircleAlert,
  Info,
  RefreshCw,
  Loader2,
} from 'lucide-react';
import {
  useOllamaModels,
  useOllamaStatus,
  useOllamaPull,
  useOllamaDelete,
} from '@/hooks/use-ollama';
import { formatModelSize, OLLAMA_CORS_HELP } from '@/lib/ollama-utils';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { SettingsCard } from '@/components/settings/settings-card';
import { ModelSelector } from '@/components/ui/model-selector';
import type { OllamaPullProgress } from '@/lib/ollama-utils';
import { useState, useCallback, useEffect } from 'react';
import { useTRPC } from '@/providers/query-provider';
import { Progress } from '@/components/ui/progress';
import { useSettings } from '@/hooks/use-settings';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { toast } from 'sonner';

export default function AISettingsPage() {
  const { data: settings } = useSettings();
  const trpc = useTRPC();
  const queryClient = useQueryClient();
  const ollamaBaseUrl = settings?.settings?.ollamaBaseUrl ?? 'http://localhost:11434';

  // Ollama status and models — always fetch so we can show status even before switching
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

  const handlePullProgress = useCallback((progress: OllamaPullProgress) => {
    setPullProgress(progress);
    if (progress.total && progress.completed) {
      setPullPercent(Math.round((progress.completed / progress.total) * 100));
    }
  }, []);

  const pullMutation = useOllamaPull(ollamaBaseUrl, handlePullProgress);
  const deleteMutation = useOllamaDelete(ollamaBaseUrl);

  // Save Ollama base URL
  const saveSettings = useMutation(
    trpc.settings.save.mutationOptions({
      onSuccess: () => {
        queryClient.invalidateQueries({ queryKey: trpc.settings.get.queryKey() });
      },
    }),
  );

  const [baseUrlInput, setBaseUrlInput] = useState(ollamaBaseUrl);

  useEffect(() => {
    setBaseUrlInput(ollamaBaseUrl);
  }, [ollamaBaseUrl]);

  const handleSaveBaseUrl = useCallback(() => {
    saveSettings.mutate(
      { ollamaBaseUrl: baseUrlInput },
      {
        onSuccess: () => {
          toast.success('Ollama URL saved');
        },
        onError: (error) => {
          toast.error(`Failed to save Ollama URL: ${error.message}`);
        },
      },
    );
  }, [baseUrlInput, saveSettings]);

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

  return (
    <div className="space-y-8">
      {/* Provider & Model Selection */}
      <SettingsCard
        title="AI Provider & Model"
        description="Choose which AI provider and model to use for chat, email composition, and background tasks."
      >
        <ModelSelector variant="full" />
      </SettingsCard>

      {/* Ollama Configuration */}
      <SettingsCard
        title="Ollama (Local Models)"
        description="Run AI models locally on your machine for privacy, cost savings, and offline use."
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
              <span className="text-muted-foreground flex items-center gap-1.5 text-xs">
                Checking...
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
            >
              <RefreshCw className="h-3.5 w-3.5" />
            </Button>
          </div>
        }
      >
        {/* Base URL */}
        <div className="space-y-2">
          <label className="text-sm font-medium">Ollama URL</label>
          <div className="flex gap-2">
            <Input
              value={baseUrlInput}
              onChange={(e) => setBaseUrlInput(e.target.value)}
              placeholder="http://localhost:11434"
              className="flex-1"
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
          <p className="text-muted-foreground text-xs">
            Default: http://localhost:11434. Change this if Ollama runs on a different host or port.
          </p>
        </div>

        {/* Installed Models */}
        <div className="space-y-3">
          <div className="flex items-center justify-between">
            <h4 className="text-sm font-medium">Installed Models</h4>
            {modelsLoading && (
              <Loader2 className="text-muted-foreground h-3.5 w-3.5 animate-spin" />
            )}
          </div>

          {ollamaOnline === true && ollamaModels && ollamaModels.length > 0 ? (
            <div className="border-border/60 rounded-md border">
              <div className="divide-border/60 divide-y">
                {ollamaModels.map((model) => (
                  <div key={model.name} className="flex items-center justify-between px-3 py-2.5">
                    <div className="flex min-w-0 items-center gap-2.5">
                      <Bot className="text-muted-foreground h-4 w-4 shrink-0" />
                      <div className="min-w-0">
                        <p className="truncate text-sm font-medium">{model.name}</p>
                        <p className="text-muted-foreground text-xs">
                          {formatModelSize(model.size)}
                          {model.details?.parameter_size &&
                            ` \u00B7 ${model.details.parameter_size}`}
                          {model.details?.quantization_level &&
                            ` \u00B7 ${model.details.quantization_level}`}
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
              </div>
            </div>
          ) : ollamaOnline === true ? (
            <div className="border-border/60 rounded-md border border-dashed px-4 py-6 text-center">
              <Bot className="text-muted-foreground/50 mx-auto h-8 w-8" />
              <p className="text-muted-foreground mt-2 text-sm">No models installed yet</p>
              <p className="text-muted-foreground text-xs">Pull a model below to get started</p>
            </div>
          ) : (
            <div className="border-border/60 rounded-md border border-dashed px-4 py-6 text-center">
              <CircleAlert className="text-muted-foreground/50 mx-auto h-8 w-8" />
              <p className="text-muted-foreground mt-2 text-sm">
                Cannot connect to Ollama at {ollamaBaseUrl}
              </p>
              <p className="text-muted-foreground mt-1 text-xs">
                Make sure Ollama is running:{' '}
                <code className="bg-muted rounded px-1 py-0.5 font-mono text-xs">ollama serve</code>
              </p>
            </div>
          )}
        </div>

        {/* Pull Model */}
        {ollamaOnline === true && (
          <div className="space-y-3">
            <h4 className="text-sm font-medium">Pull a Model</h4>
            <div className="flex gap-2">
              <Input
                value={pullModelName}
                onChange={(e) => setPullModelName(e.target.value)}
                placeholder="e.g. llama3.2, mistral, gemma2"
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

            {/* Pull progress bar */}
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
              Browse available models at{' '}
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
        )}

        {/* CORS Help — shown when offline */}
        {ollamaOnline === false && (
          <div className="border-border/60 bg-muted/30 rounded-md border p-3">
            <div className="flex items-start gap-2">
              <Info className="text-muted-foreground mt-0.5 h-4 w-4 shrink-0" />
              <div className="space-y-1.5">
                <p className="text-sm font-medium">Troubleshooting</p>
                <p className="text-muted-foreground text-xs">
                  If Ollama is running but the connection fails, you may need to configure CORS:
                </p>
                <pre className="bg-muted whitespace-pre-wrap rounded p-2 font-mono text-xs">
                  {OLLAMA_CORS_HELP}
                </pre>
              </div>
            </div>
          </div>
        )}
      </SettingsCard>
    </div>
  );
}
