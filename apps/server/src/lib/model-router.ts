import { resolveModel, isLocalInference, type AIProvider } from './ai-model-resolver';
import type { ZeroEnv } from '../env';
import type { LanguageModel } from 'ai';

export type TaskType = 'chat' | 'compose' | 'title' | 'summary' | 'search';

/**
 * Default fast (cheap) model per provider for low-complexity tasks.
 * Overridable via env vars: FAST_MODEL_ANTHROPIC, FAST_MODEL_OPENAI, FAST_MODEL_GOOGLE.
 */
const DEFAULT_FAST_MODELS: Partial<Record<string, string>> = {
  anthropic: 'claude-haiku-3-5-20241022',
  openai: 'gpt-4o-mini',
  google: 'gemini-2.0-flash-lite',
  groq: 'llama-3.1-8b-instant',
};

const FAST_TASK_SET = new Set<TaskType>(['compose', 'title', 'summary']);

/**
 * Route a task to the appropriate LanguageModel.
 *
 * Fast tasks (compose, title, summary) use the provider's configured fast model.
 * Chat and other tasks use the user's configured default model.
 * Local inference (Ollama, Apple) always passes through unchanged.
 */
export function routeModel(
  taskType: TaskType,
  provider: AIProvider,
  modelId: string,
  ollamaBaseUrl: string,
  env: ZeroEnv,
): LanguageModel {
  if (isLocalInference({ provider, modelId })) {
    return resolveModel({ provider, modelId, ollamaBaseUrl, env });
  }

  if (FAST_TASK_SET.has(taskType)) {
    const fastId = getFastModelId(provider, env);
    if (fastId) {
      return resolveModel({ provider, modelId: fastId, ollamaBaseUrl, env });
    }
  }

  return resolveModel({ provider, modelId, ollamaBaseUrl, env });
}

function getFastModelId(provider: string, env: ZeroEnv): string | null {
  switch (provider) {
    case 'anthropic':
      return env.FAST_MODEL_ANTHROPIC || DEFAULT_FAST_MODELS.anthropic || null;
    case 'openai':
      return env.FAST_MODEL_OPENAI || DEFAULT_FAST_MODELS.openai || null;
    case 'google':
      return env.FAST_MODEL_GOOGLE || DEFAULT_FAST_MODELS.google || null;
    case 'groq':
      return DEFAULT_FAST_MODELS.groq || null;
    default:
      return null;
  }
}
