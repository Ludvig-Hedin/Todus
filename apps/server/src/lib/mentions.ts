import { mentionKinds, type MentionRef } from '@zero/shared';
import { z } from 'zod';

export const mentionKindSchema = z.enum(mentionKinds);

export const mentionRefSchema = z.object({
  id: z.string(),
  kind: mentionKindSchema,
  title: z.string(),
  subtitle: z.string().nullable().optional(),
  displayText: z.string(),
  accessibilityLabel: z.string(),
});

export const mentionSearchGroupSchema = z.object({
  kind: mentionKindSchema,
  label: z.string(),
  items: z.array(mentionRefSchema),
});

export const mentionSearchResultSchema = z.object({
  groups: z.array(mentionSearchGroupSchema),
});

type RoleContentMessage = {
  role: string;
  content: string;
};

const escapeLine = (value: string | null | undefined) => (value ?? '').replace(/\s+/g, ' ').trim();

export const formatMentionContext = (mentions: MentionRef[]) => {
  const lines = mentions.map((mention) => {
    const subtitle = escapeLine(mention.subtitle);
    const meta = subtitle ? ` — ${subtitle}` : '';

    return `- ${mention.kind}#${mention.id}: ${mention.title}${meta}`;
  });

  if (lines.length === 0) {
    return '';
  }

  return ['Resolved mentions for the current user message:', ...lines].join('\n');
};

export const injectMentionContextIntoMessages = <T extends RoleContentMessage>(
  messages: T[],
  mentions: MentionRef[] | undefined,
) => {
  if (!mentions?.length) {
    return messages;
  }

  const mentionContext = formatMentionContext(mentions);
  if (!mentionContext) {
    return messages;
  }

  const nextMessages = [...messages];

  for (let index = nextMessages.length - 1; index >= 0; index -= 1) {
    if (nextMessages[index]?.role !== 'user') {
      continue;
    }

    nextMessages[index] = {
      ...nextMessages[index],
      content: `${nextMessages[index].content}\n\n<resolved_mentions>\n${mentionContext}\n</resolved_mentions>`,
    };

    return nextMessages;
  }

  return nextMessages;
};
