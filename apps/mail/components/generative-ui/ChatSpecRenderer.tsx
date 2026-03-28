/**
 * ChatSpecRenderer — Renders a json-render UI spec inline within a chat message.
 *
 * This component takes a ChatUISpec (produced by the AI) and renders it
 * using the registry of React components. It handles:
 * - Spec validation and graceful fallback for malformed specs
 * - Action dispatching (card clicks → navigation)
 * - Unknown component types (renders nothing, logs warning)
 */

import { Renderer } from '@json-render/react';
import { registry, useCardActions } from './registry';
import type { ChatUISpec } from './catalog';
import { useCallback } from 'react';

interface ChatSpecRendererProps {
  /** The JSON UI spec to render */
  spec: ChatUISpec;
  /** Optional className for the container */
  className?: string;
}

export function ChatSpecRenderer({ spec, className }: ChatSpecRendererProps) {
  const { handleCardAction } = useCardActions();

  const handleEvent = useCallback(
    (event: { type: string; payload?: Record<string, unknown> }) => {
      if (event.type === 'press' && event.payload) {
        const { action, ...params } = event.payload;
        if (typeof action === 'string') {
          handleCardAction(action, params);
        }
      }
    },
    [handleCardAction],
  );

  // Validate the spec has required fields
  if (!spec?.root || !spec?.elements) {
    console.warn('[ChatSpecRenderer] Invalid spec — missing root or elements', spec);
    return null;
  }

  // Validate root element exists
  if (!spec.elements[spec.root]) {
    console.warn('[ChatSpecRenderer] Root element not found in elements map', spec.root);
    return null;
  }

  return (
    <div className={className}>
      <Renderer spec={spec} registry={registry} onEvent={handleEvent} />
    </div>
  );
}

/**
 * Attempts to parse a JSON string into a ChatUISpec.
 * Returns null if parsing fails or the result isn't a valid spec.
 */
export function parseChatUISpec(json: string): ChatUISpec | null {
  try {
    const parsed = JSON.parse(json);
    if (parsed && typeof parsed.root === 'string' && typeof parsed.elements === 'object') {
      return parsed as ChatUISpec;
    }
    return null;
  } catch {
    return null;
  }
}

/**
 * Extracts a UI spec from a chat message's text content.
 * The AI embeds specs as ```ui-spec JSON code blocks.
 *
 * Example message content:
 * "Here are your unread emails:\n```ui-spec\n{\"root\":\"stack-1\",...}\n```"
 */
export function extractUISpecFromMessage(content: string): {
  textBefore: string;
  spec: ChatUISpec | null;
  textAfter: string;
} {
  const specPattern = /```ui-spec\n([\s\S]*?)\n```/;
  const match = content.match(specPattern);

  if (!match) {
    return { textBefore: content, spec: null, textAfter: '' };
  }

  const specJson = match[1];
  const spec = parseChatUISpec(specJson!);
  const matchIndex = match.index!;
  const textBefore = content.slice(0, matchIndex).trim();
  const textAfter = content.slice(matchIndex + match[0].length).trim();

  return { textBefore, spec, textAfter };
}
