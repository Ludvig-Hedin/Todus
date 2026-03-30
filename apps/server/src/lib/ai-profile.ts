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

