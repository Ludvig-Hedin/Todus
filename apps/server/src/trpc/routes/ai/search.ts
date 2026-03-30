import {
  GmailSearchAssistantSystemPrompt,
  OutlookSearchAssistantSystemPrompt,
} from '../../../lib/prompts';
import { buildAIProfilePrompt } from '../../../lib/ai-profile';
import { activeDriverProcedure } from '../../trpc';
import { openai } from '@ai-sdk/openai';
import { generateObject } from 'ai';
import { env } from '../../../env';
import { z } from 'zod';
import { getZeroDB } from '../../../lib/server-utils';

export const generateSearchQuery = activeDriverProcedure
  .input(z.object({ query: z.string() }))
  .mutation(async ({ input, ctx }) => {
    const {
      activeConnection: { providerId },
    } = ctx;
    const systemPrompt =
      providerId === 'google'
        ? GmailSearchAssistantSystemPrompt()
        : providerId === 'microsoft'
          ? OutlookSearchAssistantSystemPrompt()
          : '';

    const zeroDB = await getZeroDB(ctx.sessionUser.id);
    const settings = await zeroDB.findUserSettings();
    const sharedAIProfilePrompt = buildAIProfilePrompt(settings?.settings);
    const systemPromptWithProfile = sharedAIProfilePrompt
      ? `${sharedAIProfilePrompt}\n\n${systemPrompt}`
      : systemPrompt;

    const result = await generateObject({
      model: openai(env.OPENAI_MODEL || 'gpt-4o'),
      system: systemPromptWithProfile,
      prompt: input.query,
      schema: z.object({
        query: z.string(),
      }),
      output: 'object',
    });

    return result.object;
  });
