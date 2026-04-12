import {
  GmailSearchAssistantSystemPrompt,
  OutlookSearchAssistantSystemPrompt,
} from '../../../lib/prompts';
import { buildAIProfilePrompt } from '../../../lib/ai-profile';
import { activeDriverProcedure } from '../../trpc';
import { resolveModelFromSettings } from '../../../lib/ai-model-resolver';
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
      // Use centralized resolver with user settings — respects provider preference
      model: resolveModelFromSettings(settings?.settings, env),
      system: systemPromptWithProfile,
      prompt: input.query,
      schema: z.object({
        query: z.string(),
      }),
      output: 'object',
    });

    return result.object;
  });
