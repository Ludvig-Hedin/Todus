import { describe, expect, it, vi, afterEach } from 'vitest';
import { estimateLLMCost, measureStreamTiming, logAIUsage } from './ai-observability';

describe('estimateLLMCost', () => {
  it('returns 0 for all-zero inputs', () => {
    expect(estimateLLMCost('anthropic/claude-sonnet-4-6', 0, 0)).toBe(0);
  });

  it('prices cache read tokens at 10% of standard input rate', () => {
    // claude-sonnet-4-6: input=$3/M, output=$15/M
    // 1M cache read tokens = 0.1 * $3 = $0.30
    const withoutCache = estimateLLMCost('anthropic/claude-sonnet-4-6', 1_000_000, 0);
    const withCacheRead = estimateLLMCost('anthropic/claude-sonnet-4-6', 1_000_000, 0, 0, 1_000_000);
    // Cache read should be ~10% of standard input cost
    expect(withCacheRead).toBeCloseTo(withoutCache * 0.1, 5);
  });

  it('reduces standard input cost for tokens served from cache', () => {
    // 100k input, 50k from cache read → only 50k billed at standard rate
    const full = estimateLLMCost('anthropic/claude-sonnet-4-6', 100_000, 0);
    const halfCached = estimateLLMCost('anthropic/claude-sonnet-4-6', 100_000, 0, 0, 50_000);
    expect(halfCached).toBeLessThan(full);
  });

  it('falls back to FALLBACK_RATE for unknown models', () => {
    // Should not throw
    const cost = estimateLLMCost('unknown/model-xyz', 1000, 500);
    expect(cost).toBeGreaterThan(0);
  });
});

describe('measureStreamTiming', () => {
  it('returns ttft = total when markFirstToken not called', async () => {
    const t = measureStreamTiming();
    await new Promise((r) => setTimeout(r, 5));
    const { ttft, total } = t.getDurations();
    expect(ttft).toBeGreaterThanOrEqual(0);
    expect(total).toBeGreaterThanOrEqual(0);
    // When no first token, ttft === total (both = now - start)
    expect(Math.abs(ttft - total)).toBeLessThan(5);
  });

  it('records ttft < total after markFirstToken then getDurations later', async () => {
    const t = measureStreamTiming();
    await new Promise((r) => setTimeout(r, 5));
    t.markFirstToken();
    await new Promise((r) => setTimeout(r, 5));
    const { ttft, total } = t.getDurations();
    expect(ttft).toBeLessThan(total);
  });

  it('markFirstToken only records once', async () => {
    const t = measureStreamTiming();
    t.markFirstToken();
    const { ttft: first } = t.getDurations();
    await new Promise((r) => setTimeout(r, 10));
    t.markFirstToken(); // should be a no-op
    const { ttft: second } = t.getDurations();
    expect(second).toBeCloseTo(first, -1); // within 10ms
  });
});

describe('logAIUsage', () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('writes structured JSON to console.log', () => {
    const spy = vi.spyOn(console, 'log').mockImplementation(() => {});
    logAIUsage({
      provider: 'anthropic',
      model: 'claude-sonnet-4-6',
      requestType: 'chat',
      userId: 'u1',
      inputTokens: 1000,
      outputTokens: 200,
      cacheCreationInputTokens: 800,
      cacheReadInputTokens: 0,
      estimatedCostUsd: 0.003,
      timeToFirstTokenMs: 120,
      totalLatencyMs: 2500,
      toolCallCount: 2,
    });
    expect(spy).toHaveBeenCalledOnce();
    const [prefix, jsonStr] = spy.mock.calls[0]!;
    expect(prefix).toBe('[AI]');
    const parsed = JSON.parse(jsonStr as string);
    expect(parsed.provider).toBe('anthropic');
    expect(parsed.in).toBe(1000);
    expect(parsed.cacheHit).toBe(false);
    expect(parsed.uid).toBe('u1');
  });

  it('marks cacheHit true when cacheReadInputTokens > 0', () => {
    const spy = vi.spyOn(console, 'log').mockImplementation(() => {});
    logAIUsage({
      provider: 'anthropic',
      model: 'claude-sonnet-4-6',
      requestType: 'chat',
      inputTokens: 500,
      outputTokens: 100,
      cacheCreationInputTokens: 0,
      cacheReadInputTokens: 400,
      estimatedCostUsd: 0.001,
      timeToFirstTokenMs: 80,
      totalLatencyMs: 1000,
      toolCallCount: 0,
    });
    const parsed = JSON.parse(spy.mock.calls[0]![1] as string);
    expect(parsed.cacheHit).toBe(true);
  });
});
