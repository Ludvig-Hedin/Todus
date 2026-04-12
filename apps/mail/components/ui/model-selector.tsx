/**
 * Compact AI model selector for the chat header.
 *
 * Two-tier selection: provider → model. When "Ollama" is selected, the model
 * list is fetched dynamically from the local Ollama API. For cloud providers,
 * we show a curated list of common models.
 *
 * The selection is persisted to user settings via tRPC on change.
 */

import {
  Select,
  SelectContent,
  SelectGroup,
  SelectItem,
  SelectLabel,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import { useOllamaModels, useOllamaStatus } from '@/hooks/use-ollama';
import { useSettings } from '@/hooks/use-settings';
import { useTRPC } from '@/providers/query-provider';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { useState, useEffect, useCallback } from 'react';
import { cn } from '@/lib/utils';
import { Bot, Cloud, CircleAlert } from 'lucide-react';

// Curated model lists per cloud provider
const CLOUD_MODELS: Record<string, { id: string; label: string }[]> = {
  openai: [
    { id: 'gpt-4o', label: 'GPT-4o' },
    { id: 'gpt-4o-mini', label: 'GPT-4o Mini' },
    { id: 'gpt-4.1', label: 'GPT-4.1' },
    { id: 'gpt-4.1-mini', label: 'GPT-4.1 Mini' },
    { id: 'o4-mini', label: 'o4-mini' },
  ],
  anthropic: [
    { id: 'claude-sonnet-4-20250514', label: 'Claude Sonnet 4' },
    { id: 'claude-3-5-sonnet-latest', label: 'Claude 3.5 Sonnet' },
    { id: 'claude-3-5-haiku-latest', label: 'Claude 3.5 Haiku' },
  ],
  google: [
    { id: 'gemini-2.5-flash', label: 'Gemini 2.5 Flash' },
    { id: 'gemini-2.5-pro', label: 'Gemini 2.5 Pro' },
  ],
  groq: [
    { id: 'llama-3.3-70b-versatile', label: 'Llama 3.3 70B' },
    { id: 'llama-3.1-8b-instant', label: 'Llama 3.1 8B' },
    { id: 'mixtral-8x7b-32768', label: 'Mixtral 8x7B' },
  ],
};

const PROVIDER_LABELS: Record<string, string> = {
  auto: 'Auto',
  openai: 'OpenAI',
  anthropic: 'Anthropic',
  google: 'Google',
  groq: 'Groq',
  openrouter: 'OpenRouter',
  ollama: 'Ollama',
};

interface ModelSelectorProps {
  className?: string;
  /** Compact mode for the chat header (default). Full mode for settings page. */
  variant?: 'compact' | 'full';
  /** Called when provider or model changes (for parent components that need to react) */
  onModelChange?: (provider: string, modelId: string) => void;
}

export function ModelSelector({ className, variant = 'compact', onModelChange }: ModelSelectorProps) {
  const { data: settings } = useSettings();
  const trpc = useTRPC();
  const queryClient = useQueryClient();

  // Local state mirrors settings, updated optimistically.
  // Note: useSettings returns { settings: { ... } } — access via settings?.settings
  const [provider, setProvider] = useState<string>(settings?.settings?.aiProvider ?? 'auto');
  const [modelId, setModelId] = useState<string>(settings?.settings?.aiModel ?? '');
  const ollamaBaseUrl = settings?.settings?.ollamaBaseUrl ?? 'http://localhost:11434';

  // Sync from settings when they load/change
  useEffect(() => {
    if (settings?.settings?.aiProvider) setProvider(settings.settings.aiProvider);
    if (settings?.settings?.aiModel !== undefined) setModelId(settings.settings.aiModel);
  }, [settings?.settings?.aiProvider, settings?.settings?.aiModel]);

  // Ollama-specific hooks — only active when provider is 'ollama'
  const isOllamaSelected = provider === 'ollama';
  const { data: ollamaOnline } = useOllamaStatus(ollamaBaseUrl, isOllamaSelected);
  const { data: ollamaModels } = useOllamaModels(ollamaBaseUrl, isOllamaSelected && ollamaOnline === true);

  // Save settings mutation
  const saveSettings = useMutation(
    trpc.settings.save.mutationOptions({
      onSuccess: () => {
        queryClient.invalidateQueries({ queryKey: trpc.settings.get.queryKey() });
      },
    }),
  );

  const handleProviderChange = useCallback(
    (newProvider: string) => {
      setProvider(newProvider);
      // Reset model when switching providers (each provider has different models)
      const newModelId = '';
      setModelId(newModelId);
      saveSettings.mutate({ aiProvider: newProvider as any, aiModel: newModelId });
      onModelChange?.(newProvider, newModelId);
    },
    [saveSettings, onModelChange],
  );

  const handleModelChange = useCallback(
    (newModelId: string) => {
      setModelId(newModelId);
      saveSettings.mutate({ aiModel: newModelId });
      onModelChange?.(provider, newModelId);
    },
    [provider, saveSettings, onModelChange],
  );

  // Determine available models for current provider
  const availableModels =
    provider === 'ollama'
      ? (ollamaModels ?? []).map((m) => ({ id: m.name, label: m.name }))
      : CLOUD_MODELS[provider] ?? [];

  // Display label for the current selection
  const currentModelLabel =
    provider === 'auto'
      ? 'Auto'
      : modelId
        ? availableModels.find((m) => m.id === modelId)?.label ?? modelId
        : PROVIDER_LABELS[provider] ?? provider;

  if (variant === 'compact') {
    return (
      <div className={cn('flex items-center gap-1', className)}>
        {/* Combined provider + model selector as a single compact dropdown */}
        <Select
          value={provider === 'auto' ? 'auto' : `${provider}:${modelId}`}
          onValueChange={(value) => {
            if (value === 'auto') {
              handleProviderChange('auto');
              return;
            }
            const [newProvider, ...rest] = value.split(':');
            const newModel = rest.join(':'); // Model IDs can contain colons (e.g., ollama tags)
            if (newProvider !== provider) {
              setProvider(newProvider);
              setModelId(newModel);
              saveSettings.mutate({ aiProvider: newProvider as any, aiModel: newModel });
              onModelChange?.(newProvider, newModel);
            } else {
              handleModelChange(newModel);
            }
          }}
        >
          <SelectTrigger className="h-7 w-fit min-w-0 gap-1.5 border-0 bg-transparent px-2 text-xs hover:bg-muted/50">
            <div className="flex items-center gap-1.5">
              {isOllamaSelected ? (
                <>
                  <Bot className="h-3 w-3 shrink-0" />
                  {ollamaOnline === false && (
                    <CircleAlert className="h-3 w-3 shrink-0 text-destructive" />
                  )}
                </>
              ) : provider === 'auto' ? (
                <Cloud className="h-3 w-3 shrink-0" />
              ) : null}
              <span className="truncate max-w-[120px]">{currentModelLabel}</span>
            </div>
          </SelectTrigger>
          <SelectContent align="start" className="max-h-80">
            {/* Auto option */}
            <SelectItem value="auto">
              <div className="flex items-center gap-2">
                <Cloud className="h-3.5 w-3.5" />
                <span>Auto (server default)</span>
              </div>
            </SelectItem>

            {/* Cloud providers with their models */}
            {Object.entries(CLOUD_MODELS).map(([provKey, models]) => (
              <SelectGroup key={provKey}>
                <SelectLabel className="text-xs text-muted-foreground">
                  {PROVIDER_LABELS[provKey]}
                </SelectLabel>
                {models.map((m) => (
                  <SelectItem key={`${provKey}:${m.id}`} value={`${provKey}:${m.id}`}>
                    {m.label}
                  </SelectItem>
                ))}
              </SelectGroup>
            ))}

            {/* Ollama section */}
            <SelectGroup>
              <SelectLabel className="text-xs text-muted-foreground">
                <div className="flex items-center gap-1.5">
                  <Bot className="h-3 w-3" />
                  Ollama (local)
                  {ollamaOnline === true && (
                    <span className="h-1.5 w-1.5 rounded-full bg-green-500" />
                  )}
                  {ollamaOnline === false && (
                    <span className="h-1.5 w-1.5 rounded-full bg-red-500" />
                  )}
                </div>
              </SelectLabel>
              {ollamaOnline === true && ollamaModels && ollamaModels.length > 0 ? (
                ollamaModels.map((m) => (
                  <SelectItem key={`ollama:${m.name}`} value={`ollama:${m.name}`}>
                    <div className="flex items-center gap-2">
                      <Bot className="h-3 w-3 shrink-0 text-muted-foreground" />
                      {m.name}
                    </div>
                  </SelectItem>
                ))
              ) : ollamaOnline === true ? (
                <div className="px-2 py-1.5 text-xs text-muted-foreground">
                  No models installed. Go to Settings &gt; AI to pull models.
                </div>
              ) : (
                <div className="px-2 py-1.5 text-xs text-muted-foreground">
                  Ollama offline. Start with: <code className="font-mono">ollama serve</code>
                </div>
              )}
            </SelectGroup>
          </SelectContent>
        </Select>
      </div>
    );
  }

  // Full variant for settings page — two separate dropdowns
  return (
    <div className={cn('flex flex-col gap-3', className)}>
      {/* Provider selector */}
      <div className="space-y-1.5">
        <label className="text-sm font-medium">AI Provider</label>
        <Select value={provider} onValueChange={handleProviderChange}>
          <SelectTrigger className="w-full">
            <SelectValue placeholder="Select provider" />
          </SelectTrigger>
          <SelectContent>
            {Object.entries(PROVIDER_LABELS).map(([key, label]) => (
              <SelectItem key={key} value={key}>
                <div className="flex items-center gap-2">
                  {key === 'ollama' && <Bot className="h-3.5 w-3.5" />}
                  {key === 'auto' && <Cloud className="h-3.5 w-3.5" />}
                  <span>{label}</span>
                  {key === 'ollama' && ollamaOnline === true && (
                    <span className="h-1.5 w-1.5 rounded-full bg-green-500" />
                  )}
                  {key === 'ollama' && ollamaOnline === false && (
                    <span className="h-1.5 w-1.5 rounded-full bg-red-500" />
                  )}
                </div>
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>

      {/* Model selector — hidden for 'auto' */}
      {provider !== 'auto' && (
        <div className="space-y-1.5">
          <label className="text-sm font-medium">Model</label>
          <Select value={modelId} onValueChange={handleModelChange}>
            <SelectTrigger className="w-full">
              <SelectValue placeholder="Select model" />
            </SelectTrigger>
            <SelectContent>
              {provider === 'openrouter' ? (
                <div className="px-2 py-1.5 text-xs text-muted-foreground">
                  Enter model ID in the text field (e.g., openai/gpt-4o)
                </div>
              ) : availableModels.length > 0 ? (
                availableModels.map((m) => (
                  <SelectItem key={m.id} value={m.id}>
                    {m.label}
                  </SelectItem>
                ))
              ) : isOllamaSelected && ollamaOnline === false ? (
                <div className="px-2 py-1.5 text-xs text-muted-foreground">
                  Ollama is offline
                </div>
              ) : (
                <div className="px-2 py-1.5 text-xs text-muted-foreground">No models available</div>
              )}
            </SelectContent>
          </Select>
        </div>
      )}
    </div>
  );
}
