import { calculateAICostUsd } from './ai/model-pricing';

export type AIRequestType = 'chat' | 'compose' | 'title' | 'search' | 'summary';

export interface AIRequestMetrics {
  provider: string;
  model: string;
  requestType: AIRequestType;
  userId?: string;
  inputTokens: number;
  outputTokens: number;
  cacheCreationInputTokens: number;
  cacheReadInputTokens: number;
  estimatedCostUsd: number;
  timeToFirstTokenMs: number;
  totalLatencyMs: number;
  toolCallCount: number;
  error?: string;
}

/**
 * Estimate the USD cost of an AI call, accounting for Anthropic prompt cache pricing:
 * - Cache creation tokens: billed at ~1.25× standard input (approximated as standard here)
 * - Cache read tokens: billed at 10% of standard input price
 */
export function estimateLLMCost(
  model: string,
  inputTokens: number,
  outputTokens: number,
  cacheCreationTokens = 0,
  cacheReadTokens = 0,
): number {
  // Standard-priced input = total input minus the tokens served from cache
  const standardInput = Math.max(0, inputTokens - cacheReadTokens);
  const baseCost = calculateAICostUsd(model, standardInput, outputTokens);
  // Cache creation ≈ standard input rate (1.25× is Anthropic's actual; close enough for billing)
  const cacheCreationCost = calculateAICostUsd(model, cacheCreationTokens, 0);
  // Cache read = 10% of standard input rate
  const cacheReadCost = calculateAICostUsd(model, cacheReadTokens, 0) * 0.1;
  return Math.max(0, baseCost + cacheCreationCost + cacheReadCost);
}

/**
 * Creates a timing helper for measuring time-to-first-token and total latency.
 * Call markFirstToken() inside the onChunk callback on the first text chunk.
 */
export function measureStreamTiming() {
  const start = Date.now();
  let firstTokenAt: number | null = null;

  return {
    markFirstToken() {
      if (firstTokenAt === null) firstTokenAt = Date.now();
    },
    getDurations(): { ttft: number; total: number } {
      const now = Date.now();
      return {
        ttft: firstTokenAt !== null ? firstTokenAt - start : now - start,
        total: now - start,
      };
    },
  };
}

/**
 * Log AI request metrics for cost and performance visibility.
 * Writes a structured JSON line — in production, pipe stdout to your log aggregator.
 * Never logs prompt content.
 */
export function logAIUsage(metrics: AIRequestMetrics): void {
  const cacheHit = metrics.cacheReadInputTokens > 0;
  console.log(
    '[AI]',
    JSON.stringify({
      type: metrics.requestType,
      provider: metrics.provider,
      model: metrics.model,
      in: metrics.inputTokens,
      out: metrics.outputTokens,
      cacheCreate: metrics.cacheCreationInputTokens || undefined,
      cacheRead: metrics.cacheReadInputTokens || undefined,
      cacheHit,
      costUsd: Number(metrics.estimatedCostUsd.toFixed(6)),
      ttftMs: metrics.timeToFirstTokenMs,
      totalMs: metrics.totalLatencyMs,
      tools: metrics.toolCallCount || undefined,
      ...(metrics.userId ? { uid: metrics.userId } : {}),
      ...(metrics.error ? { error: metrics.error } : {}),
    }),
  );
}
