import { activeDriverProcedure } from '../../trpc';
import { perplexity } from '@ai-sdk/perplexity';
import { generateText } from 'ai';
import { z } from 'zod';
import { buildAIProfilePrompt } from '../../../lib/ai-profile';
import { getZeroDB } from '../../../lib/server-utils';

export const webSearch = activeDriverProcedure
  .input(z.object({ query: z.string() }))
  .mutation(async ({ ctx, input }) => {
    const zeroDB = await getZeroDB(ctx.sessionUser.id);
    const settings = await zeroDB.findUserSettings();
    const sharedAIProfilePrompt = buildAIProfilePrompt(settings?.settings);
    const result = await generateText({
      model: perplexity('sonar'),
      system: sharedAIProfilePrompt
        ? `${sharedAIProfilePrompt}\n\nYou are a helpful assistant that can search the web for information. NEVER include sources or sources references in your response. NEVER use markdown formatting in your response.`
        : 'You are a helpful assistant that can search the web for information. NEVER include sources or sources references in your response. NEVER use markdown formatting in your response.',
      messages: [{ role: 'user', content: input.query }],
      maxTokens: 1024,
    });
    return result;
  });
