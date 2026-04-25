// USD per 1,000,000 tokens. Rates kept in sync with each provider's published pricing.
// When OpenRouter returns a model string we don't recognize, fall back to FALLBACK_RATE.
//
// Update cadence: review when adding a new model to the app or when a provider
// changes prices. Outdated rates here only mean we charge slightly off, never block.

type ModelRate = { input: number; output: number };

const RATES: Record<string, ModelRate> = {
  // Anthropic
  'anthropic/claude-opus-4-7': { input: 15, output: 75 },
  'anthropic/claude-opus-4.6': { input: 15, output: 75 },
  'anthropic/claude-opus-4': { input: 15, output: 75 },
  'anthropic/claude-sonnet-4-6': { input: 3, output: 15 },
  'anthropic/claude-sonnet-4': { input: 3, output: 15 },
  'anthropic/claude-3.5-sonnet': { input: 3, output: 15 },
  'anthropic/claude-haiku-4-5': { input: 1, output: 5 },
  'anthropic/claude-3.5-haiku': { input: 0.8, output: 4 },

  // OpenAI
  'openai/gpt-5': { input: 5, output: 15 },
  'openai/gpt-5-mini': { input: 0.5, output: 1.5 },
  'openai/gpt-5.4': { input: 5, output: 15 },
  'openai/gpt-5.4-mini': { input: 0.5, output: 1.5 },
  'openai/gpt-4.1': { input: 2, output: 8 },
  'openai/gpt-4.1-mini': { input: 0.4, output: 1.6 },
  'openai/gpt-4o': { input: 2.5, output: 10 },
  'openai/gpt-4o-mini': { input: 0.15, output: 0.6 },
  'openai/o1': { input: 15, output: 60 },
  'openai/o1-mini': { input: 3, output: 12 },

  // Google
  'google/gemini-2.5-pro': { input: 2.5, output: 10 },
  'google/gemini-2.5-flash': { input: 0.3, output: 2.5 },
  'google/gemini-2.0-flash': { input: 0.1, output: 0.4 },

  // DeepSeek (commonly used reasoning models on OpenRouter)
  'deepseek/deepseek-r1': { input: 0.55, output: 2.19 },
  'deepseek/deepseek-chat': { input: 0.27, output: 1.1 },
};

const FALLBACK_RATE: ModelRate = { input: 5, output: 15 };

const normalize = (model: string) => model.toLowerCase().trim();

const findRate = (model: string): ModelRate => {
  const key = normalize(model);
  if (RATES[key]) return RATES[key];

  // Bare model name without provider prefix — match by suffix.
  for (const [k, v] of Object.entries(RATES)) {
    if (k.endsWith(`/${key}`) || k === key) return v;
  }
  return FALLBACK_RATE;
};

/**
 * Compute USD cost for an AI call given token counts.
 * Returns dollars (e.g., 0.00342). Multiply by your credit conversion before tracking.
 */
export const calculateAICostUsd = (
  model: string,
  inputTokens: number,
  outputTokens: number,
): number => {
  const rate = findRate(model);
  const input = (Math.max(0, inputTokens) / 1_000_000) * rate.input;
  const output = (Math.max(0, outputTokens) / 1_000_000) * rate.output;
  return input + output;
};

/**
 * 1 ai_usage credit = $1 USD (matches the Autumn dashboard configuration:
 * Pro = 15 credits = $15 of model spend; Free = 7.5 credits = $7.50).
 * Returns a float — Autumn supports fractional values.
 */
export const usdToCredits = (usd: number): number => Math.max(0, usd);
