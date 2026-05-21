import { redirect } from 'react-router';

export function clientLoader() {
  // Use RR-v7 `redirect` helper with a relative path so the redirect works
  // regardless of `VITE_PUBLIC_APP_URL` and doesn't break when env is missing
  // at build time.
  throw redirect('/mail/inbox');
}
