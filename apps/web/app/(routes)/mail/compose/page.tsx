import { Sheet, SheetContent } from '@/components/ui/sheet';
import { CreateEmail } from '@/components/create/create-email';
import { authProxy } from '@/lib/auth-proxy';
import { redirect, useLoaderData, useLocation, useNavigate } from 'react-router';
import type { Route } from './+types/page';

export async function clientLoader({ request }: Route.ClientLoaderArgs) {
  const session = await authProxy.api.getSession({ headers: request.headers });
  if (!session) throw redirect('/login');
  const url = new URL(request.url);
  if (url.searchParams.get('to')?.startsWith('mailto:')) {
    throw redirect(
      `/mail/compose/handle-mailto?mailto=${encodeURIComponent(url.searchParams.get('to') ?? '')}`,
    );
  }

  // CreateEmail's inner <Dialog> is gated on the `isComposeOpen` URL param —
  // without it, deep-linking to /mail/compose renders an empty Sheet. Set
  // the param via redirect so the composer actually mounts.
  if (url.searchParams.get('isComposeOpen') !== 'true') {
    const next = new URL(url);
    next.searchParams.set('isComposeOpen', 'true');
    throw redirect(`${next.pathname}${next.search}`);
  }

  return Object.fromEntries(url.searchParams.entries()) as {
    to?: string;
    subject?: string;
    body?: string;
    draftId?: string;
    cc?: string;
    bcc?: string;
  };
}

export default function ComposePage() {
  const params = useLoaderData<typeof clientLoader>();
  const location = useLocation();
  const navigate = useNavigate();
  const hasInternalReferrer = location.state?.fromApp === true;

  // Side-panel compose: leaves the rest of the mail layout (sidebar, etc.)
  // interactive while a draft is in flight. Closing the sheet pops back to
  // wherever the user came from (or the inbox if they deep-linked).
  return (
    <Sheet
      modal={false}
      open={true}
      onOpenChange={(open) => {
        if (!open) {
          if (hasInternalReferrer) {
            navigate(-1);
          } else {
            void navigate('/mail/inbox');
          }
        }
      }}
    >
      <SheetContent
        side="right"
        hideOverlay
        // Lets users keep clicking sidebar / inbox while composing.
        onPointerDownOutside={(e) => e.preventDefault()}
        onInteractOutside={(e) => e.preventDefault()}
        onEscapeKeyDown={(e) => e.preventDefault()}
        className="flex h-screen w-full max-w-[640px] flex-col border-l bg-[#FAFAFA] p-0 shadow-2xl sm:max-w-[640px] dark:bg-[#141414]"
      >
        <CreateEmail
          initialTo={params.to || ''}
          initialSubject={params.subject || ''}
          initialBody={params.body || ''}
          initialCc={params.cc || ''}
          initialBcc={params.bcc || ''}
          draftId={params.draftId || null}
        />
      </SheetContent>
    </Sheet>
  );
}
