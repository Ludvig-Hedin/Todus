/**
 * Centralized AI model resolution.
 *
 * Converts a (provider, modelId) pair from user settings into a Vercel AI SDK
 * LanguageModel instance. This replaces the scattered model selection logic that
 * was previously hardcoded across 10+ files.
 *
 * Key design decisions:
 * - Ollama uses the OpenAI-compatible endpoint (/v1/) so we reuse @ai-sdk/openai
 *   with a custom baseURL — no new dependency needed.
 * - When provider is 'ollama' and it's unreachable, we throw (no silent fallback).
 * - When provider is 'auto', we preserve the existing env-var cascade.
 */

import { anthropic } from '@ai-sdk/anthropic';
import { createOpenAI } from '@ai-sdk/openai';
import type { UserSettings } from './schemas';
import { google } from '@ai-sdk/google';
import type { LanguageModel } from 'ai';
import type { ZeroEnv } from '../env';
import { groq } from '@ai-sdk/groq';

// Re-export the provider enum values for consumers
export const AI_PROVIDERS = [
  'auto',
  'openai',
  'anthropic',
  'google',
  'groq',
  'openrouter',
  'ollama',
] as const;
export type AIProvider = (typeof AI_PROVIDERS)[number];

/**
 * Providers that run inference on the user's own hardware, never on a paid
 * upstream API. Requests routed to these providers must be exempt from
 * `hasAiCredits` pre-flight and from `trackAiUsage` post-stream metering —
 * billing them would charge users for compute they paid for themselves.
 *
 * Note: native iOS/macOS local-model paths bypass the backend entirely, so
 * this constant is primarily defensive for the apps/web Ollama flow.
 */
export const LOCAL_MODEL_PROVIDERS: ReadonlySet<AIProvider> = new Set(['ollama']);

/**
 * Loose model-id heuristic for the same exemption. Covers cases where the
 * client sends a known local model id without a `provider` field (older
 * apps/web builds, custom integrations). Intentionally conservative — only
 * matches strings that unambiguously identify a local-only model family.
 */
export function isLocalModelId(modelId: string | undefined): boolean {
  if (!modelId) return false;
  const m = modelId.toLowerCase();
  // mlx-community HuggingFace repos
  if (m.startsWith('mlx-community/')) return true;
  // Ollama canonical tags for the curated catalog (qwen3:1.7b, gemma3:4b, llama3.2:3b, ministral:3b ...)
  if (/^(qwen3|gemma3|llama3\.2|ministral|phi3):/i.test(modelId)) return true;
  // Apple Foundation Models
  if (m === 'apple-foundation' || m === 'apple-intelligence') return true;
  return false;
}

/**
 * One-stop check used by billing call-sites. Returns true when the request
 * targets on-device inference and must not be billed.
 */
export function isLocalInference(opts: {
  provider?: string;
  modelId?: string;
}): boolean {
  if (opts.provider && LOCAL_MODEL_PROVIDERS.has(opts.provider as AIProvider)) {
    return true;
  }
  return isLocalModelId(opts.modelId);
}

interface ResolveModelOpts {
  provider: AIProvider;
  modelId: string;
  ollamaBaseUrl: string;
  env: ZeroEnv;
}

interface ResolvedModelConfig {
  provider: AIProvider;
  modelId: string;
}

/**
 * Check whether an Ollama instance is reachable at the given base URL.
 * Uses a short timeout to avoid blocking the request for too long.
 */
export async function isOllamaReachable(baseUrl: string, timeoutMs = 2000): Promise<boolean> {
  try {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), timeoutMs);
    const res = await fetch(`${baseUrl}/api/tags`, { signal: controller.signal });
    clearTimeout(timeout);
    return res.ok;
  } catch {
    return false;
  }
}

/**
 * Resolve the "auto" provider using the existing env-var cascade:
 * OpenRouter (if key) → Google (if key) → OpenAI (if USE_OPENAI) → Anthropic
 */
function resolveAutoModel(env: ZeroEnv): LanguageModel {
  const { modelId, provider } = resolveAutoModelConfig(env);

  switch (provider) {
    case 'openrouter': {
      const openRouterProvider = createOpenAI({
        baseURL: 'https://openrouter.ai/api/v1',
        apiKey: env.OPENROUTER_API_SECRET ?? env.OPENROUTER_API_KEY,
      });
      return openRouterProvider(modelId);
    }
    case 'google':
      return google(modelId);
    case 'openai': {
      const oai = createOpenAI({});
      return oai(modelId);
    }
    default:
      return anthropic(modelId);
  }
}

export function resolveAutoModelConfig(env: ZeroEnv): ResolvedModelConfig {
  const openRouterApiKey = env.OPENROUTER_API_SECRET ?? env.OPENROUTER_API_KEY;

  if (openRouterApiKey) {
    return {
      provider: 'openrouter',
      modelId: (env.DEFAULT_MODEL || 'openai/gpt-4o-mini').trim(),
    };
  }

  if (env.GOOGLE_GENERATIVE_AI_API_KEY) {
    return {
      provider: 'google',
      modelId: (env.DEFAULT_MODEL || 'gemini-2.5-flash').trim(),
    };
  }

  if (env.USE_OPENAI === 'true') {
    return {
      provider: 'openai',
      modelId: (env.OPENAI_MODEL || 'gpt-4o').trim(),
    };
  }

  return {
    provider: 'anthropic',
    modelId: 'claude-3-5-sonnet-latest',
  };
}

/**
 * Create an Ollama-backed LanguageModel using the OpenAI-compatible API.
 * Ollama exposes an OpenAI-compatible endpoint at /v1/ which we leverage
 * through @ai-sdk/openai with a custom baseURL. The apiKey is required by
 * the SDK but Ollama ignores it — we pass 'ollama' as a placeholder.
 */
function createOllamaModel(baseUrl: string, modelId: string): LanguageModel {
  const ollamaProvider = createOpenAI({
    baseURL: `${baseUrl}/v1`,
    apiKey: 'ollama', // Ollama doesn't need a real API key but SDK requires non-empty
  });
  return ollamaProvider(modelId);
}

/**
 * Resolve a Vercel AI SDK LanguageModel from provider + model settings.
 *
 * This is the single source of truth for model selection across the entire backend.
 * All AI call-sites should use this instead of directly importing provider modules.
 */
export function resolveModel({
  provider,
  modelId,
  ollamaBaseUrl,
  env,
}: ResolveModelOpts): LanguageModel {
  switch (provider) {
    case 'ollama': {
      if (!modelId) {
        throw new Error(
          '[AIModel] Ollama provider selected but no model specified. Please select a model in Settings > AI.',
        );
      }
      return createOllamaModel(ollamaBaseUrl, modelId);
    }

    case 'openai': {
      const id = (modelId || env.OPENAI_MODEL || 'gpt-4o').trim();
      // Use createOpenAI to allow arbitrary model IDs (the default openai() uses strict types)
      const oai = createOpenAI({});
      return oai(id);
    }

    case 'anthropic': {
      const id = (modelId || 'claude-3-5-sonnet-latest').trim();
      return anthropic(id as any);
    }

    case 'google': {
      const id = (modelId || 'gemini-2.5-flash').trim();
      return google(id as any);
    }

    case 'groq': {
      const id = (modelId || 'llama-3.3-70b-versatile').trim();
      return groq(id as any);
    }

    case 'openrouter': {
      const apiKey = env.OPENROUTER_API_SECRET ?? env.OPENROUTER_API_KEY;
      if (!apiKey) {
        throw new Error(
          '[AIModel] OpenRouter selected but no API key configured (OPENROUTER_API_KEY).',
        );
      }
      const id = (modelId || env.DEFAULT_MODEL || 'openai/gpt-4o-mini').trim();
      const openRouterProvider = createOpenAI({
        baseURL: 'https://openrouter.ai/api/v1',
        apiKey,
      });
      return openRouterProvider(id);
    }

    case 'auto':
    default:
      return resolveAutoModel(env);
  }
}

/**
 * Resolve the concrete model identifier used for a request so downstream code
 * (billing, logging, analytics) stays aligned with the actual model selection.
 */
export function resolveModelId({
  provider,
  modelId,
  ollamaBaseUrl,
  env,
}: ResolveModelOpts): string {
  switch (provider) {
    case 'ollama': {
      if (!modelId) {
        throw new Error(
          '[AIModel] Ollama provider selected but no model specified. Please select a model in Settings > AI.',
        );
      }
      return modelId;
    }
    case 'openai':
      return (modelId || env.OPENAI_MODEL || 'gpt-4o').trim();
    case 'anthropic':
      return (modelId || 'claude-3-5-sonnet-latest').trim();
    case 'google':
      return (modelId || 'gemini-2.5-flash').trim();
    case 'groq':
      return (modelId || 'llama-3.3-70b-versatile').trim();
    case 'openrouter': {
      if (!(env.OPENROUTER_API_SECRET ?? env.OPENROUTER_API_KEY)) {
        throw new Error(
          '[AIModel] OpenRouter selected but no API key configured (OPENROUTER_API_KEY).',
        );
      }
      return (modelId || env.DEFAULT_MODEL || 'openai/gpt-4o-mini').trim();
    }
    case 'auto':
    default:
      return resolveAutoModelConfig(env).modelId;
  }
}

/**
 * Convenience: resolve a model directly from a UserSettings object.
 */
export function resolveModelFromSettings(
  settings: UserSettings | undefined,
  env: ZeroEnv,
): LanguageModel {
  const provider = (settings?.aiProvider ?? 'auto') as AIProvider;
  const modelId = settings?.aiModel ?? '';
  const ollamaBaseUrl = settings?.ollamaBaseUrl ?? 'http://localhost:11434';
  return resolveModel({ provider, modelId, ollamaBaseUrl, env });
}
