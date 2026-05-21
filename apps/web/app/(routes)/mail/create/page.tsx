import { authProxy } from '@/lib/auth-proxy';
import { redirect } from 'react-router';
import type { Route } from './+types/page';

export async function clientLoader({ request }: Route.ClientLoaderArgs) {
  const session = await authProxy.api.getSession({ headers: request.headers });
  if (!session) throw redirect('/login');

  const url = new URL(request.url);
  const params = Object.fromEntries(url.searchParams.entries()) as {
    to?: string;
    subject?: string;
    body?: string;
  };

  // Build the inbox redirect URL programmatically so each present param is
  // forwarded (`body` was previously dropped entirely — Web Share Target /
  // mailto handoffs with a body silently lost it) and so the To field is
  // left empty when no recipient was provided instead of being seeded with
  // a "someone@someone.com" placeholder the user might send to by accident.
  const target = new URL('/mail/inbox', url);
  target.searchParams.set('isComposeOpen', 'true');
  if (params.to) target.searchParams.set('to', params.to);
  if (params.subject) target.searchParams.set('subject', params.subject);
  if (params.body) target.searchParams.set('body', params.body);
  throw redirect(`${target.pathname}${target.search}`);
}
