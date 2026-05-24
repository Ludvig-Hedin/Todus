import { describe, expect, it } from 'vitest';
import { trimMessagesToBudget, truncateToolOutput, buildChatMessages } from './chat-context';
import type { CoreMessage } from 'ai';

function userMsg(text: string): CoreMessage {
  return { role: 'user', content: text };
}
function assistantMsg(text: string): CoreMessage {
  return { role: 'assistant', content: text };
}
function toolResultMsg(): CoreMessage {
  return { role: 'tool', content: [{ type: 'tool-result', toolCallId: 't1', toolName: 'x', result: 'y' }] };
}

describe('trimMessagesToBudget', () => {
  it('returns array unchanged when under limit', () => {
    const msgs = [userMsg('a'), assistantMsg('b')];
    expect(trimMessagesToBudget(msgs, 10)).toBe(msgs);
  });

  it('keeps last N messages when over limit', () => {
    const msgs = Array.from({ length: 40 }, (_, i) => userMsg(`msg${i}`));
    const result = trimMessagesToBudget(msgs, 30);
    expect(result).toHaveLength(30);
    expect((result[0].content as string)).toBe('msg10');
    expect((result[29].content as string)).toBe('msg39');
  });

  it('removes orphaned tool-result at head of trimmed window', () => {
    // Trimmed window starts with a tool result that has no matching call
    const msgs: CoreMessage[] = [
      ...Array.from({ length: 28 }, (_, i) => userMsg(`old${i}`)),
      toolResultMsg(),
      userMsg('last'),
    ];
    const result = trimMessagesToBudget(msgs, 5);
    // First msg after trim is the tool result — should be stripped
    expect(result[0].role).not.toBe('tool');
  });

  it('does NOT remove tool-result that follows a tool call in window', () => {
    // All in-window — no orphan to strip
    const msgs: CoreMessage[] = [userMsg('a'), assistantMsg('b')];
    expect(trimMessagesToBudget(msgs, 5)).toHaveLength(2);
  });
});

describe('truncateToolOutput', () => {
  it('returns short strings unchanged', () => {
    const s = 'hello world';
    expect(truncateToolOutput(s, 8000)).toBe(s);
  });

  it('truncates long strings and appends truncation note', () => {
    const s = 'x'.repeat(10_000);
    const result = truncateToolOutput(s, 8_000);
    expect(result.length).toBeLessThan(10_000);
    expect(result).toContain('[2000 chars truncated]');
  });
});

describe('buildChatMessages', () => {
  const history: CoreMessage[] = [userMsg('hi'), assistantMsg('hello')];

  it('non-anthropic: no cache anchor, profile prepended if present', () => {
    const result = buildChatMessages({ provider: 'openai', userMemory: 'Alice', history });
    expect(result[0].role).toBe('user');
    expect(result[0].content).toContain('Alice');
    expect(result).toHaveLength(3);
    // No cache_control anywhere
    expect(JSON.stringify(result)).not.toContain('cacheControl');
  });

  it('non-anthropic: no profile block when userMemory is empty', () => {
    const result = buildChatMessages({ provider: 'openai', userMemory: '', history });
    expect(result).toEqual(history);
  });

  it('anthropic: injects cache anchor as first message', () => {
    const result = buildChatMessages({ provider: 'anthropic', userMemory: 'Alice', history });
    const anchor = result[0] as any;
    expect(anchor.role).toBe('user');
    expect(anchor.content[0].providerOptions?.anthropic?.cacheControl?.type).toBe('ephemeral');
  });

  it('anthropic: profile placed after anchor, before history', () => {
    const result = buildChatMessages({ provider: 'anthropic', userMemory: 'Alice', history });
    expect(result[1].role).toBe('user');
    expect(result[1].content).toContain('Alice');
    expect(result[2]).toEqual(history[0]);
  });

  it('anthropic: no profile block when userMemory is empty', () => {
    const result = buildChatMessages({ provider: 'anthropic', userMemory: '', history });
    // anchor + 2 history msgs = 3
    expect(result).toHaveLength(3);
    expect((result[1] as any).content).toBe('hi');
  });
});
