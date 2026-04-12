/**
 * React hooks for interacting with a local Ollama instance.
 *
 * These hooks call the Ollama API directly from the browser. They are used
 * by the model selector and the AI settings page to list, pull, and delete
 * models. The base URL is read from user settings (default: http://localhost:11434).
 */

import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  checkOllamaConnection,
  fetchOllamaModels,
  pullOllamaModel,
  deleteOllamaModel,
  type OllamaPullProgress,
} from '@/lib/ollama-utils';

const OLLAMA_MODELS_KEY = 'ollama-models';
const OLLAMA_STATUS_KEY = 'ollama-status';

/**
 * Check whether the Ollama instance is reachable.
 * Polls every 10s when enabled.
 */
export function useOllamaStatus(baseUrl: string, enabled = true) {
  return useQuery({
    queryKey: [OLLAMA_STATUS_KEY, baseUrl],
    queryFn: () => checkOllamaConnection(baseUrl),
    enabled: enabled && !!baseUrl,
    refetchInterval: 10_000, // Re-check every 10 seconds
    retry: false,
    staleTime: 5_000,
  });
}

/**
 * Fetch installed Ollama models. Only fetches when the connection is confirmed.
 */
export function useOllamaModels(baseUrl: string, enabled = true) {
  return useQuery({
    queryKey: [OLLAMA_MODELS_KEY, baseUrl],
    queryFn: () => fetchOllamaModels(baseUrl),
    enabled: enabled && !!baseUrl,
    retry: false,
    staleTime: 30_000, // Models don't change often
  });
}

/**
 * Pull (download) a model. Returns a mutation that can be triggered on demand.
 * Accepts an onProgress callback for streaming download status.
 */
export function useOllamaPull(
  baseUrl: string,
  onProgress?: (progress: OllamaPullProgress) => void,
) {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (modelName: string) => pullOllamaModel(baseUrl, modelName, onProgress),
    onSuccess: () => {
      // Refresh the installed models list after a successful pull
      queryClient.invalidateQueries({ queryKey: [OLLAMA_MODELS_KEY, baseUrl] });
    },
  });
}

/**
 * Delete an installed model. Refreshes the model list on success.
 */
export function useOllamaDelete(baseUrl: string) {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (modelName: string) => deleteOllamaModel(baseUrl, modelName),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: [OLLAMA_MODELS_KEY, baseUrl] });
    },
  });
}
