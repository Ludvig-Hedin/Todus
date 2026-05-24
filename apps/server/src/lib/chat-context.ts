import { convertToCoreMessages, type CoreMessage, type CoreUserMessage } from 'ai';
import type { Message } from '@ai-sdk/ui-utils';

/**
 * Stable anchor injected as the first user message for Anthropic prompt caching.
 * When marked with cache_control, Anthropic caches everything before+including it:
 * system prompt + tool definitions + this anchor. Must be IDENTICAL across turns.
 */
const CACHE_ANCHOR_TEXT = '[Email AI assistant session — tools and context loaded]';

/**
 * Trim a CoreMessage[] to the last maxMessages, never starting with an
 * orphaned tool-result message (no matching tool call in the window).
 */
export function trimMessagesToBudget(
  messages: CoreMessage[],
  maxMessages = 30,
): CoreMessage[] {
  if (messages.length <= maxMessages) return messages;
  let tail = messages.slice(-maxMessages);
  // Remove leading tool-result messages that have no call in the trimmed window
  while (tail.length > 0 && tail[0]?.role === 'tool') {
    tail = tail.slice(1);
  }
  return tail;
}

/**
 * Truncate a tool-output string to prevent runaway context sizes.
 */
export function truncateToolOutput(output: string, maxChars = 8_000): string {
  if (output.length <= maxChars) return output;
  return `${output.slice(0, maxChars)}\n...[${output.length - maxChars} chars truncated]`;
}

/**
 * Build the final messages array for streamText, inserting Anthropic cache
 * breakpoints around the stable prefix (system + tools).
 *
 * Anthropic layout:
 *   [0] stable anchor (cache_control: ephemeral) — caches system+tools+anchor
 *   [1] user-profile block (volatile, not cached)
 *   [2..N] trimmed conversation history
 *
 * Other providers:
 *   [0..N] trimmed conversation history (no changes)
 */
export function buildChatMessages(opts: {
  provider: string;
  userMemory: string;
  history: CoreMessage[];
}): CoreMessage[] {
  const { provider, userMemory, history } = opts;

  const profileBlock: CoreMessage | null = userMemory.trim()
    ? { role: 'user', content: `[User context]\n${userMemory}` }
    : null;

  if (provider !== 'anthropic') {
    return [...(profileBlock ? [profileBlock] : []), ...history];
  }

  const anchorBlock: CoreUserMessage = {
    role: 'user',
    content: [
      {
        type: 'text',
        text: CACHE_ANCHOR_TEXT,
        // Marks cache breakpoint — everything before+including this block is cached
        providerOptions: {
          anthropic: { cacheControl: { type: 'ephemeral' } },
        },
      },
    ],
  };

  return [anchorBlock, ...(profileBlock ? [profileBlock] : []), ...history];
}

/**
 * Convert AI SDK UI Message[] to trimmed CoreMessage[] for streamText.
 */
export function toTrimmedCoreMessages(
  messages: Message[],
  maxMessages = 30,
): CoreMessage[] {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  return trimMessagesToBudget(convertToCoreMessages(messages as any), maxMessages);
}
