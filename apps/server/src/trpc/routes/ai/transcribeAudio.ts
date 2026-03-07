import { activeDriverProcedure } from '../../trpc';
import { env } from '../../../env';
import { toByteArray } from 'base64-js';
import { z } from 'zod';

const DEFAULT_MIME_TYPE = 'audio/mp4';
const MAX_AUDIO_BASE64_LENGTH = 8_000_000;

export const transcribeAudio = activeDriverProcedure
  .input(
    z.object({
      audioBase64: z.string().min(1),
      mimeType: z.string().optional(),
      language: z.string().optional(),
    }),
  )
  .mutation(async ({ input }) => {
    if (!env.OPENAI_API_KEY) {
      throw new Error('OpenAI API key not configured.');
    }

    if (input.audioBase64.length > MAX_AUDIO_BASE64_LENGTH) {
      throw new Error('Audio payload too large.');
    }

    const payload = input.audioBase64.includes(',')
      ? input.audioBase64.split(',').at(-1) ?? ''
      : input.audioBase64;

    let bytes: Uint8Array;
    try {
      bytes = toByteArray(payload);
    } catch {
      throw new Error('Invalid audio payload.');
    }

    const mimeType = input.mimeType || DEFAULT_MIME_TYPE;
    const formData = new FormData();
    formData.append('file', new Blob([bytes], { type: mimeType }), 'assistant-input.m4a');
    formData.append('model', 'gpt-4o-mini-transcribe');
    if (input.language) {
      formData.append('language', input.language);
    }

    const response = await fetch('https://api.openai.com/v1/audio/transcriptions', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${env.OPENAI_API_KEY}`,
      },
      body: formData,
    });

    if (!response.ok) {
      const message = await response.text();
      throw new Error(`Transcription failed (${response.status}): ${message}`);
    }

    const result = (await response.json()) as { text?: string };
    return {
      text: result.text?.trim() ?? '',
    };
  });
