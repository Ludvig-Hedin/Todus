import assert from 'node:assert/strict';
import test from 'node:test';
import {
  buildComposePrefillParams,
  buildDraftInputFromMailto,
  extractComposePrefillParams,
  hasComposePrefillContent,
  parseMailtoUrl,
  plainTextBodyToHtml,
} from './mailtoParity';

test('parseMailtoUrl parses recipients and query values', () => {
  const parsed = parseMailtoUrl(
    'mailto:alice@example.com,bob@example.com?subject=Hello&body=Line%201&cc=carol@example.com&bcc=dave@example.com',
  );

  assert.deepEqual(parsed, {
    to: 'alice@example.com,bob@example.com',
    subject: 'Hello',
    body: 'Line 1',
    cc: 'carol@example.com',
    bcc: 'dave@example.com',
  });
});

test('parseMailtoUrl handles double-encoded query payloads', () => {
  const doubleEncoded =
    'mailto:alice%40example.com?subject=Hello%2520there&body=Line1%250ALine2&cc=carol%2540example.com';

  const parsed = parseMailtoUrl(doubleEncoded);

  assert.deepEqual(parsed, {
    to: 'alice@example.com',
    subject: 'Hello there',
    body: 'Line1\nLine2',
    cc: 'carol@example.com',
    bcc: '',
  });
});

test('parseMailtoUrl returns null for invalid payloads', () => {
  assert.equal(parseMailtoUrl('https://example.com'), null);
  assert.equal(parseMailtoUrl('mailto:'), null);
});

test('plainTextBodyToHtml preserves paragraphs and line breaks', () => {
  const html = plainTextBodyToHtml('First line\nSecond line\n\nThird line');
  assert.equal(
    html,
    '<p>First line<br />Second line</p>\n<p>Third line</p>',
  );
});

test('buildDraftInputFromMailto normalizes recipients and body', () => {
  const payload = buildDraftInputFromMailto({
    to: ' <alice@example.com>,bob@example.com ',
    subject: 'Hi',
    body: 'One\nTwo',
    cc: ' <carol@example.com> ',
    bcc: '',
  });

  assert.deepEqual(payload, {
    id: null,
    threadId: null,
    fromEmail: null,
    to: 'alice@example.com, bob@example.com',
    cc: 'carol@example.com',
    bcc: '',
    subject: 'Hi',
    message: '<p>One<br />Two</p>',
    attachments: [],
  });
});

test('extractComposePrefillParams normalizes mailto and includes draftId', () => {
  const prefill = extractComposePrefillParams({
    to: 'mailto:alice@example.com?subject=Hi&body=Body%20value',
    draftId: 'draft-1',
  });

  assert.deepEqual(prefill, {
    to: 'alice@example.com',
    subject: 'Hi',
    body: 'Body value',
    draftId: 'draft-1',
  });
});

test('buildComposePrefillParams includes only populated fields', () => {
  const params = buildComposePrefillParams({
    to: 'alice@example.com',
    subject: '',
    body: '',
    cc: '',
    bcc: '',
  });

  assert.deepEqual(params, { to: 'alice@example.com' });
});

test('hasComposePrefillContent detects meaningful prefill fields', () => {
  assert.equal(hasComposePrefillContent({}), false);
  assert.equal(hasComposePrefillContent({ draftId: 'd-1' }), false);
  assert.equal(hasComposePrefillContent({ subject: 'hello' }), true);
});
