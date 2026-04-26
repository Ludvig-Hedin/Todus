import { authProxy } from '@/lib/auth-proxy';
import type { Route } from './+types/page';

export async function clientLoader({ request }: Route.ClientLoaderArgs) {
  const session = await authProxy.api.getSession({ headers: request.headers });
  if (!session) return Response.redirect(`${import.meta.env.VITE_PUBLIC_APP_URL}/login`);

  const url = new URL(request.url);
  const params = Object.fromEntries(url.searchParams.entries()) as {
    to?: string;
    subject?: string;
    body?: string;
  };
  const toParam = params.to || 'someone@someone.com';
  return Response.redirect(
    `${import.meta.env.VITE_PUBLIC_APP_URL}/mail/inbox?isComposeOpen=true&to=${encodeURIComponent(toParam)}${params.subject ? `&subject=${encodeURIComponent(params.subject)}` : ''}`,
  );
}
