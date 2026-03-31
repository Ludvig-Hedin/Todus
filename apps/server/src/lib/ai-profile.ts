import { getZeroDB } from './server-utils';

type AIProfileSource = {
  contextAboutYou?: string | null;
  customPrompt?: string | null;
};

const normalizeBlock = (value: string | null | undefined) => value?.trim() ?? '';

export const buildAIProfilePrompt = (source?: AIProfileSource) => {
  const sections: string[] = [];
  const contextAboutYou = normalizeBlock(source?.contextAboutYou);
  const customPrompt = normalizeBlock(source?.customPrompt);

  if (contextAboutYou) {
    sections.push(`## Context about you\n${contextAboutYou}`);
  }

  if (customPrompt) {
    sections.push(`## Custom instructions\n${customPrompt}`);
  }

  return sections.join('\n\n');
};

export async function getSharedAIProfilePromptForUser(userId: string) {
  try {
    const zeroDB = await getZeroDB(userId);
    const settings = await zeroDB.findUserSettings();
    return buildAIProfilePrompt(settings?.settings);
  } catch (error) {
    console.warn('[AIProfile] Failed to load shared AI profile prompt:', error);
    return '';
  }
}
