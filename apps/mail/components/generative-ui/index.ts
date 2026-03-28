/**
 * Generative UI — json-render based card rendering for AI chat.
 *
 * Entry points:
 * - ChatSpecRenderer: Renders a UI spec inline in a chat message
 * - extractUISpecFromMessage: Parses specs from message content
 * - chatCatalog: The component catalog (for system prompt generation)
 * - getChatCatalogPrompt: Generates the AI system prompt fragment
 * - registry: React component implementations
 */

export { ChatSpecRenderer, extractUISpecFromMessage, parseChatUISpec } from './ChatSpecRenderer';
export { chatCatalog, getChatCatalogPrompt, type ChatUISpec } from './catalog';
export { registry, useCardActions } from './registry';
