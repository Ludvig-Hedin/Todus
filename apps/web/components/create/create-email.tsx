import { useUndoSend, type EmailData, deserializeFiles } from '@/hooks/use-undo-send';
import { useActiveConnection } from '@/hooks/use-connections';
import { Sheet, SheetClose, SheetContent } from '@/components/ui/sheet';
import { useEmailAliases } from '@/hooks/use-email-aliases';
import { cleanEmailAddresses } from '@/lib/email-utils';

import { useTRPC } from '@/providers/query-provider';
import { useMutation } from '@tanstack/react-query';
import { useSettings } from '@/hooks/use-settings';
import { EmailComposer } from './email-composer';
import { useSession } from '@/lib/auth-client';
import { serializeFiles } from '@/lib/schemas';
import { useDraft } from '@/hooks/use-drafts';
import { useEffect, useMemo, useState } from 'react';

import type { Attachment } from '@/types';
import { useQueryState } from 'nuqs';
import { X } from '../icons/icons';
import posthog from 'posthog-js';
import { toast } from 'sonner';
import './prosemirror.css';

// Define the draft type to include CC and BCC fields
type DraftType = {
  id: string;
  content?: string;
  subject?: string;
  to?: string[];
  cc?: string[];
  bcc?: string[];
  attachments?: File[];
};

export function CreateEmail({
  initialTo = '',
  initialSubject = '',
  initialBody = '',
  initialCc = '',
  initialBcc = '',
  draftId: propDraftId,
}: {
  initialTo?: string;
  initialSubject?: string;
  initialBody?: string;
  initialCc?: string;
  initialBcc?: string;
  draftId?: string | null;
}) {
  const { data: session } = useSession();

  const { data: aliases } = useEmailAliases();
  const [draftId, setDraftId] = useQueryState('draftId');
  // Read mailto / Web-Share-Target fields from the URL so deep links like
  // /mail/inbox?isComposeOpen=true&to=…&subject=…&body=… prefill the
  // composer instead of silently dropping the payload. CreateEmail is the
  // only consumer of these flags app-wide (mounted by app-sidebar).
  const [queryTo] = useQueryState('to');
  const [querySubject] = useQueryState('subject');
  const [queryBody] = useQueryState('body');
  const [queryCc] = useQueryState('cc');
  const [queryBcc] = useQueryState('bcc');
  const resolvedTo = queryTo ?? initialTo;
  const resolvedSubject = querySubject ?? initialSubject;
  const resolvedBody = queryBody ?? initialBody;
  const resolvedCc = queryCc ?? initialCc;
  const resolvedBcc = queryBcc ?? initialBcc;
  const {
    data: draft,
    isLoading: isDraftLoading,
    error: draftError,
  } = useDraft(draftId ?? propDraftId ?? null);

  const [, setIsDraftFailed] = useState(false);
  const trpc = useTRPC();
  const { mutateAsync: sendEmail } = useMutation(trpc.mail.send.mutationOptions());
  const [isComposeOpen, setIsComposeOpen] = useQueryState('isComposeOpen');
  const [, setThreadId] = useQueryState('threadId');
  const [, setActiveReplyId] = useQueryState('activeReplyId');
  const { data: activeConnection } = useActiveConnection();
  const { data: settings, isLoading: settingsLoading } = useSettings();
  const { handleUndoSend } = useUndoSend();
  // If there was an error loading the draft, set the failed state
  useEffect(() => {
    if (draftError) {
      console.error('Error loading draft:', draftError);
      setIsDraftFailed(true);
      toast.error('Failed to load draft');
    }
  }, [draftError]);

  const { data: activeAccount } = useActiveConnection();

  const userEmail = activeAccount?.email || activeConnection?.email || session?.user?.email || '';
  const userName = activeAccount?.name || activeConnection?.name || session?.user?.name || '';

  const handleSendEmail = async (data: {
    to: string[];
    cc?: string[];
    bcc?: string[];
    subject: string;
    message: string;
    attachments: File[];
    fromEmail?: string;
    scheduleAt?: string;
    includeSignature?: boolean;
  }) => {
    const fromEmail = data.fromEmail || aliases?.[0]?.email || userEmail;

    const shouldIncludeSignature = data.includeSignature ?? settings?.settings.todusSignature ?? true;
    const todusSignature = shouldIncludeSignature
      ? '<p style="color: #666; font-size: 12px;">Sent via <a href="https://todus.app/" style="color: #0066cc; text-decoration: none;">Todus</a></p>'
      : '';


    const result = await sendEmail({
      to: data.to.map((email) => ({ email, name: email.split('@')[0] || email })),
      cc: data.cc?.map((email) => ({ email, name: email.split('@')[0] || email })),
      bcc: data.bcc?.map((email) => ({ email, name: email.split('@')[0] || email })),
      subject: data.subject,
      message: data.message + todusSignature,

      attachments: await serializeFiles(data.attachments),
      fromEmail: userName.trim() ? `${userName.replace(/[<>]/g, '')} <${fromEmail}>` : fromEmail,
      draftId: draftId ?? undefined,
      scheduleAt: data.scheduleAt,
    });

    setDraftId(null);
    clearUndoData();

    // Track different email sending scenarios
    if (data.cc && data.cc.length > 0 && data.bcc && data.bcc.length > 0) {
      posthog.capture('Create Email Sent with CC and BCC');
    } else if (data.cc && data.cc.length > 0) {
      posthog.capture('Create Email Sent with CC');
    } else if (data.bcc && data.bcc.length > 0) {
      posthog.capture('Create Email Sent with BCC');
    } else {
      posthog.capture('Create Email Sent');
    }

    handleUndoSend(result, settings, {
      to: data.to,
      cc: data.cc,
      bcc: data.bcc,
      subject: data.subject,
      message: data.message,
      attachments: data.attachments,
      fromEmail: data.fromEmail,
      scheduleAt: data.scheduleAt,
    });
  };

  useEffect(() => {
    if (propDraftId && !draftId) {
      setDraftId(propDraftId);
    }
  }, [propDraftId, draftId, setDraftId]);

  // Process initial email addresses
  const processInitialEmails = (emailStr: string) => {
    if (!emailStr) return [];
    const cleanedAddresses = cleanEmailAddresses(emailStr);
    return cleanedAddresses || [];
  };

  const clearUndoData = () => {
    if (typeof window !== 'undefined') {
      localStorage.removeItem('undoEmailData');
    }
  };

  const undoEmailData = useMemo((): EmailData | null => {
    if (isComposeOpen !== 'true') return null;
    if (typeof window === 'undefined') return null;

    const storedData = localStorage.getItem('undoEmailData');
    if (!storedData) return null;

    try {
      const parsedData = JSON.parse(storedData);

      if (parsedData.attachments && Array.isArray(parsedData.attachments)) {
        parsedData.attachments = deserializeFiles(parsedData.attachments);
      }

      return parsedData;
    } catch (error) {
      console.error('Failed to parse undo email data:', error);
      return null;
    }
  }, [isComposeOpen]);

  // Cast draft to our extended type that includes CC and BCC
  const typedDraft = draft as unknown as DraftType;

  const handleDialogClose = (open: boolean) => {
    setIsComposeOpen(open ? 'true' : null);
    if (!open) {
      setDraftId(null);
      clearUndoData();
    }
  };

  const base64ToFile = (base64: string, filename: string, mimeType: string): File | null => {
    try {
      const byteString = atob(base64);
      const byteArray = new Uint8Array(byteString.length);
      for (let i = 0; i < byteString.length; i++) {
        byteArray[i] = byteString.charCodeAt(i);
      }
      return new File([byteArray], filename, { type: mimeType });
    } catch (error) {
      console.error('Failed to convert base64 to file', error);
      return null;
    }
  };

  // convert the attachments into File[]
  const files: File[] = ((typedDraft?.attachments as Attachment[] | undefined) || [])
    .map((att: Attachment) => base64ToFile(att.body, att.filename, att.mimeType))
    .filter((file): file is File => file !== null);

  return (
    <>
      {/* Inline (non-modal) compose pane — slides in on the right and lets
          the user keep clicking inbox / sidebar while composing. Mirrors
          macOS MacEmailComposeView which never blocks the rest of the app. */}
      <Sheet open={!!isComposeOpen} onOpenChange={handleDialogClose} modal={false}>
        <SheetContent
          side="right"
          hideOverlay
          // Prevent close-on-outside-click so the user can keep interacting
          // with the inbox/sidebar without dismissing their draft. Escape is
          // intentionally NOT blocked here — the EmailComposer registers its
          // own capture-phase Esc handler that shows a leave-confirmation when
          // there's typed content, and falls through to close the Sheet when
          // the composer is empty (matching the "esc" label on the close
          // button).
          onPointerDownOutside={(e) => e.preventDefault()}
          onInteractOutside={(e) => e.preventDefault()}
          className="flex h-screen w-full max-w-[760px] flex-col border-l bg-[#FAFAFA] p-0 shadow-2xl sm:max-w-[760px] dark:bg-[#141414]"
        >
        <div className="flex h-full min-h-0 flex-col gap-1 p-4">
          <div className="flex w-full justify-start">
            <SheetClose asChild className="flex">
              <button className="dark:bg-panelDark flex items-center gap-1 rounded-lg bg-[#F0F0F0] px-2 py-1 hover:bg-gray-100 dark:hover:bg-[#404040] transition-colors cursor-pointer">
                <X className="fill-muted-foreground mt-0.5 h-3.5 w-3.5 dark:fill-[#929292]" />
                <span className="text-muted-foreground text-sm font-medium dark:text-white">
                  esc
                </span>
              </button>
            </SheetClose>
          </div>
          {isDraftLoading ? (
            <div className="flex h-[600px] w-full items-center justify-center rounded-2xl border">
              <div className="text-center">
                <div className="mx-auto mb-4 h-6 w-6 animate-spin rounded-full border-2 border-gray-300 border-t-blue-600"></div>
                <p>Loading draft...</p>
              </div>
            </div>
          ) : (
            <EmailComposer
              key={typedDraft?.id || undoEmailData?.to?.join(',') || resolvedTo || 'composer'}
              className="h-full max-w-none rounded-2xl border"
              onSendEmail={handleSendEmail}
              initialMessage={
                undoEmailData?.message ||
                typedDraft?.content ||
                resolvedBody
              }
              initialTo={
                undoEmailData?.to ||
                typedDraft?.to?.map((e: string) => e.replace(/[<>]/g, '')) ||
                processInitialEmails(resolvedTo)
              }
              initialCc={
                undoEmailData?.cc ||
                typedDraft?.cc?.map((e: string) => e.replace(/[<>]/g, '')) ||
                processInitialEmails(resolvedCc)
              }
              initialBcc={
                undoEmailData?.bcc ||
                typedDraft?.bcc?.map((e: string) => e.replace(/[<>]/g, '')) ||
                processInitialEmails(resolvedBcc)
              }
              onClose={() => {
                setThreadId(null);
                setActiveReplyId(null);
                setIsComposeOpen(null);
                setDraftId(null);
                clearUndoData();
              }}
              initialAttachments={undoEmailData?.attachments || files}
              initialSubject={
                undoEmailData?.subject ||
                typedDraft?.subject ||
                resolvedSubject
              }
              autofocus={false}
              settingsLoading={settingsLoading}
            />
          )}
        </div>
        </SheetContent>
      </Sheet>
    </>
  );
}
