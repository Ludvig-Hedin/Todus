type UnknownRecord = Record<string, unknown>;

export type AutumnFeature = {
  balance?: number | null;
  usage?: number | null;
  unlimited?: boolean | null;
  interval?: string | null;
  included_usage?: number | null;
  next_reset_at?: number | null;
};

export type AutumnCustomer = {
  id?: string;
  stripe_id?: string | null;
  features?: Record<string, AutumnFeature>;
  products?: unknown;
};

function getBaseUrl(backendUrl: string): string {
  return backendUrl.replace(/\/$/, '');
}

function extractErrorMessage(payload: unknown): string | null {
  if (!payload || typeof payload !== 'object') return null;
  const message = (payload as UnknownRecord).message;
  if (typeof message === 'string' && message.trim().length > 0) {
    return message;
  }
  const error = (payload as UnknownRecord).error;
  if (typeof error === 'string' && error.trim().length > 0) {
    return error;
  }
  return null;
}

function getStringAtPath(
  payload: unknown,
  path: Array<string | number>,
): string | null {
  let current: unknown = payload;
  for (const key of path) {
    if (!current || typeof current !== 'object') return null;
    current = (current as UnknownRecord)[String(key)];
  }
  return typeof current === 'string' && current.length > 0 ? current : null;
}

function extractUrl(payload: unknown): string | null {
  const candidates: Array<Array<string | number>> = [
    ['url'],
    ['checkout_url'],
    ['billing_portal_url'],
    ['billingPortalUrl'],
    ['data', 'url'],
    ['data', 'checkout_url'],
    ['data', 'billing_portal_url'],
    ['data', 'billingPortalUrl'],
  ];

  for (const path of candidates) {
    const value = getStringAtPath(payload, path);
    if (value) return value;
  }

  return null;
}

async function autumnPost<T>(
  backendUrl: string,
  token: string,
  path: string,
  body: UnknownRecord = {},
): Promise<T> {
  const response = await fetch(`${getBaseUrl(backendUrl)}/autumn/${path}`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  });

  const text = await response.text().catch(() => '');
  const payload = text ? safeJsonParse(text) : null;
  if (!response.ok) {
    const message =
      extractErrorMessage(payload) ??
      (text.trim().length > 0 ? text.trim() : `Request failed (${response.status})`);
    throw new Error(message);
  }

  return (payload ?? {}) as T;
}

function safeJsonParse(value: string): unknown {
  try {
    return JSON.parse(value);
  } catch {
    return null;
  }
}

export function hasAutumnProAccess(customer: AutumnCustomer | null | undefined): boolean {
  if (!customer) return false;
  if (typeof customer.stripe_id === 'string' && customer.stripe_id.length > 0) {
    return true;
  }

  if (Array.isArray(customer.products) && customer.products.length > 0) {
    return true;
  }

  if (customer.products && typeof customer.products === 'object') {
    return Object.keys(customer.products as UnknownRecord).length > 0;
  }

  const features = customer.features ?? {};
  return Object.values(features).some((feature) => feature?.unlimited === true);
}

export async function fetchAutumnCustomer(
  backendUrl: string,
  token: string,
): Promise<AutumnCustomer> {
  return autumnPost<AutumnCustomer>(backendUrl, token, 'customers', {});
}

export async function openAutumnBillingPortal(
  backendUrl: string,
  token: string,
): Promise<string> {
  const payload = await autumnPost<unknown>(backendUrl, token, 'openBillingPortal', {});
  const url = extractUrl(payload);
  if (!url) {
    throw new Error('Billing portal URL was missing from response.');
  }
  return url;
}

export async function startAutumnCheckout(
  backendUrl: string,
  token: string,
  payload: {
    productId: string;
    successUrl: string;
  },
): Promise<string> {
  const response = await autumnPost<unknown>(backendUrl, token, 'attach', payload);
  const checkoutUrl = extractUrl(response);
  if (!checkoutUrl) {
    throw new Error('Checkout URL was missing from response.');
  }
  return checkoutUrl;
}
