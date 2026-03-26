import assert from 'node:assert/strict';
import test from 'node:test';
import {
  authBypassVoiceUnavailableMessage,
  buildAuthBypassAssistantReply,
} from './authBypassAssistant';

test('buildAuthBypassAssistantReply returns inbox guidance for summarize prompts', () => {
  const reply = buildAuthBypassAssistantReply('Summarize my inbox priorities');
  assert.match(reply, /priority framework/i);
  assert.match(reply, /on-device/i);
});

test('buildAuthBypassAssistantReply returns follow-up template for follow-up prompts', () => {
  const reply = buildAuthBypassAssistantReply('Draft a follow-up for delayed reply');
  assert.match(reply, /following up/i);
});

test('buildAuthBypassAssistantReply returns decline template for decline prompts', () => {
  const reply = buildAuthBypassAssistantReply('Help me decline this meeting');
  assert.match(reply, /won't be able to join/i);
});

test('buildAuthBypassAssistantReply includes user prompt for generic requests', () => {
  const reply = buildAuthBypassAssistantReply('Rewrite this draft politely');
  assert.match(reply, /Prompt received/i);
});

test('authBypassVoiceUnavailableMessage explains voice restriction', () => {
  assert.match(authBypassVoiceUnavailableMessage(), /unavailable in auth bypass mode/i);
});
