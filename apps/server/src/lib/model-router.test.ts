import { describe, expect, it, vi } from 'vitest';

vi.mock('cloudflare:workers', () => ({ env: {} }));

// Mock all AI SDK providers
vi.mock('@ai-sdk/anthropic', () => ({
  anthropic: (id: string) => ({ _provider: 'anthropic', _id: id }),
}));
vi.mock('@ai-sdk/openai', () => ({
  createOpenAI: () => (id: string) => ({ _provider: 'openai', _id: id }),
}));
vi.mock('@ai-sdk/google', () => ({
  google: (id: string) => ({ _provider: 'google', _id: id }),
}));
vi.mock('@ai-sdk/groq', () => ({
  groq: (id: string) => ({ _provider: 'groq', _id: id }),
}));

import { routeModel } from './model-router';
import type { ZeroEnv } from '../env';

const baseEnv = {} as unknown as ZeroEnv;

describe('routeModel', () => {
  it('returns fast model for compose task on anthropic', () => {
    const model = routeModel('compose', 'anthropic', 'claude-sonnet-4-6', '', baseEnv) as any;
    expect(model._id).toBe('claude-haiku-3-5-20241022');
  });

  it('returns fast model for title task on anthropic', () => {
    const model = routeModel('title', 'anthropic', 'claude-sonnet-4-6', '', baseEnv) as any;
    expect(model._id).toBe('claude-haiku-3-5-20241022');
  });

  it('returns fast model for summary task on anthropic', () => {
    const model = routeModel('summary', 'anthropic', 'claude-sonnet-4-6', '', baseEnv) as any;
    expect(model._id).toBe('claude-haiku-3-5-20241022');
  });

  it('returns user model for chat task on anthropic', () => {
    const model = routeModel('chat', 'anthropic', 'claude-opus-4-7', '', baseEnv) as any;
    expect(model._id).toBe('claude-opus-4-7');
  });

  it('returns user model for search task on anthropic', () => {
    const model = routeModel('search', 'anthropic', 'claude-sonnet-4-6', '', baseEnv) as any;
    expect(model._id).toBe('claude-sonnet-4-6');
  });

  it('env override FAST_MODEL_ANTHROPIC takes precedence over default', () => {
    const envWithOverride = { FAST_MODEL_ANTHROPIC: 'claude-custom-fast' } as unknown as ZeroEnv;
    const model = routeModel('compose', 'anthropic', 'claude-opus-4-7', '', envWithOverride) as any;
    expect(model._id).toBe('claude-custom-fast');
  });
});
