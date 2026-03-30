export type ParsedMailtoData = {
  to: string;
  subject: string;
  body: string;
  cc: string;
  bcc: string;
};

export type ComposePrefillParams = {
  to?: string;
  cc?: string;
  bcc?: string;
  subject?: string;
  body?: string;
  draftId?: string;
};

const DECODE_ATTEMPTS = 2;

export function getFirstQueryValue(value: string | string[] | undefined): string | undefined {
  if (!value) return undefined;
  if (Array.isArray(value)) return value[0];
  return value;
}

function decodeMaybe(value: string): string {
  let decoded = value;
  for (let i = 0; i < DECODE_ATTEMPTS; i += 1) {
    try {
      decoded = decodeURIComponent(decoded);
    } catch {
      break;
    }
  }
  return decoded;
}

function normalizeRecipientCsv(value: string): string {
  return value
    .split(',')
    .map((entry) => entry.trim().replace(/^<|>$/g, ''))
    .filter(Boolean)
    .join(', ');
}

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

export function plainTextBodyToHtml(body: string): string {
  const normalizedBody = body.replace(/\r\n/g, '\n').replace(/\r/g, '\n');
  if (!normalizedBody.trim()) {
    return '<p></p>';
  }

  return normalizedBody
    .split(/\n\s*\n/)
    .map((paragraph) => {
      const escaped = escapeHtml(paragraph).replace(/\n/g, '<br />');
      return `<p>${escaped.replace(/\s{2,}/g, (match) => '&nbsp;'.repeat(match.length))}</p>`;
    })
    .join('\n');
}

export function parseMailtoUrl(mailtoUrl: string): ParsedMailtoData | null {
  if (!mailtoUrl.startsWith('mailto:')) {
    return null;
  }

  try {
    const mailtoContent = mailtoUrl.slice('mailto:'.length);
    const [emailPartRaw, queryPartRaw] = mailtoContent.split('?', 2);

    const to = decodeMaybe(emailPartRaw ?? '').trim();
    if (!to) {
      return null;
    }

    let subject = '';
    let body = '';
    let cc = '';
    let bcc = '';

    if (queryPartRaw) {
      const queryParams = new URLSearchParams(decodeMaybe(queryPartRaw));
      subject = decodeMaybe(queryParams.get('subject') ?? '');
      body = decodeMaybe(queryParams.get('body') ?? '');
      cc = decodeMaybe(queryParams.get('cc') ?? '');
      bcc = decodeMaybe(queryParams.get('bcc') ?? '');
    }

    return { to, subject, body, cc, bcc };
  } catch {
    return null;
  }
}

export function buildDraftInputFromMailto(mailtoData: ParsedMailtoData) {
  return {
    id: null,
    threadId: null,
    fromEmail: null,
    to: normalizeRecipientCsv(mailtoData.to),
    cc: normalizeRecipientCsv(mailtoData.cc),
    bcc: normalizeRecipientCsv(mailtoData.bcc),
    subject: mailtoData.subject,
    message: plainTextBodyToHtml(mailtoData.body),
    attachments: [],
  };
}

export function buildComposePrefillParams(
  mailtoData: ParsedMailtoData,
  draftId?: string,
): ComposePrefillParams {
  const params: ComposePrefillParams = {};
  const to = normalizeRecipientCsv(mailtoData.to);
  const cc = normalizeRecipientCsv(mailtoData.cc);
  const bcc = normalizeRecipientCsv(mailtoData.bcc);

  if (to) params.to = to;
  if (cc) params.cc = cc;
  if (bcc) params.bcc = bcc;
  if (mailtoData.subject) params.subject = mailtoData.subject;
  if (mailtoData.body) params.body = mailtoData.body;
  if (draftId) params.draftId = draftId;

  return params;
}

export function extractComposePrefillParams(params: {
  to?: string | string[];
  cc?: string | string[];
  bcc?: string | string[];
  subject?: string | string[];
  body?: string | string[];
  draftId?: string | string[];
}): ComposePrefillParams {
  const draftId = getFirstQueryValue(params.draftId);
  const toParam = getFirstQueryValue(params.to);
  const ccParam = getFirstQueryValue(params.cc);
  const bccParam = getFirstQueryValue(params.bcc);
  const subjectParam = getFirstQueryValue(params.subject);
  const bodyParam = getFirstQueryValue(params.body);

  if (toParam?.startsWith('mailto:')) {
    const parsed = parseMailtoUrl(toParam);
    if (!parsed) {
      return draftId ? { draftId } : {};
    }
    return buildComposePrefillParams(parsed, draftId);
  }

  const prefill: ComposePrefillParams = {};

  if (toParam) prefill.to = normalizeRecipientCsv(decodeMaybe(toParam));
  if (ccParam) prefill.cc = normalizeRecipientCsv(decodeMaybe(ccParam));
  if (bccParam) prefill.bcc = normalizeRecipientCsv(decodeMaybe(bccParam));
  if (subjectParam) prefill.subject = decodeMaybe(subjectParam);
  if (bodyParam) prefill.body = decodeMaybe(bodyParam);
  if (draftId) prefill.draftId = draftId;

  return prefill;
}

export function hasComposePrefillContent(prefill: ComposePrefillParams): boolean {
  return Boolean(
    prefill.to || prefill.cc || prefill.bcc || prefill.subject || prefill.body,
  );
}
