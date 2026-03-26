const PREVIEW_PREFIX =
  'Auth bypass preview mode is enabled, so this response is generated on-device.';

export function buildAuthBypassAssistantReply(prompt: string): string {
  const trimmed = prompt.trim();
  if (!trimmed) {
    return `${PREVIEW_PREFIX}\n\nAsk a question and I will draft a useful starting point.`;
  }

  const normalized = trimmed.toLowerCase();

  if (
    normalized.includes('summarize') ||
    normalized.includes('summary') ||
    normalized.includes('prioritize') ||
    normalized.includes('priority') ||
    normalized.includes('inbox')
  ) {
    return `${PREVIEW_PREFIX}

Quick inbox priority framework:
1. Handle anything blocking someone else first.
2. Reply to time-sensitive items next.
3. Archive or snooze low-value threads.
4. Convert multi-step asks into a short task list.

If you share one thread, I can draft the exact reply text.`;
  }

  if (
    normalized.includes('follow-up') ||
    normalized.includes('follow up') ||
    normalized.includes('nudge') ||
    normalized.includes('delayed reply')
  ) {
    return `${PREVIEW_PREFIX}

Suggested follow-up draft:
"Hi <Name>, just following up on my note from earlier. When you have a moment, could you share an update on <topic>? Thanks so much."

Optional closer: "If easier, I can send over a quick summary of what we need."`;
  }

  if (
    normalized.includes('decline') ||
    normalized.includes('cannot attend') ||
    normalized.includes("can't attend") ||
    normalized.includes('reject meeting')
  ) {
    return `${PREVIEW_PREFIX}

Suggested decline draft:
"Thanks for the invite. I won't be able to join this one, but I appreciate you including me. Please share notes afterward, and I can follow up async."`;
  }

  return `${PREVIEW_PREFIX}

I can still help with structure while offline from mailbox APIs:
- draft a reply
- shorten or rewrite text
- propose subject lines
- turn notes into action items

Prompt received: "${trimmed}"`;
}

export function authBypassVoiceUnavailableMessage(): string {
  return 'Voice dictation is unavailable in auth bypass mode because transcription requires an authenticated mailbox session.';
}
