import assert from 'node:assert/strict';
import test from 'node:test';
import { extractResponseText, nextStreamCursor } from './assistantUtils';

test('extractResponseText returns .text first when present', () => {
  assert.equal(extractResponseText({ text: 'hello', response: 'fallback' }), 'hello');
});

test('extractResponseText falls back to .response when .text missing', () => {
  assert.equal(extractResponseText({ response: 'world' }), 'world');
});

test('extractResponseText returns empty string for unknown payloads', () => {
  assert.equal(extractResponseText({}), '');
  assert.equal(extractResponseText(null), '');
});

test('nextStreamCursor advances in chunked steps and clamps to full length', () => {
  assert.equal(nextStreamCursor(0, 10, 3), 3);
  assert.equal(nextStreamCursor(8, 10, 3), 10);
  assert.equal(nextStreamCursor(5, 0, 3), 0);
});
