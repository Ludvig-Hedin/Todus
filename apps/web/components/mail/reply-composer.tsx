import { useUndoSend } from '@/hooks/use-undo-send';
import { constructReplyBody, constructForwardBody } from '@/lib/utils';
import { useActiveConnection } from '@/hooks/use-connections';
import { useEmailAliases } from '@/hooks/use-email-aliases';
import { EmailComposer } from '../create/email-composer';
import { useHotkeysContext } from 'react-hotkeys-hook';
import { useTRPC } from '@/providers/query-provider';
import { useMutation } from '@tanstack/react-query';
import { useSettings } from '@/hooks/use-settings';
import { useThread } from '@/hooks/use-threads';
import { useSession } from '@/lib/auth-client';
import { serializeFiles } from '@/lib/schemas';
import { useDraft } from '@/hooks/use-drafts';
import { m } from '@/paraglide/messages';
import type { Sender } from '@/types';
import { useQueryState } from 'nuqs';
import { useEffect, useMemo } from 'react';
import posthog from 'posthog-js';
import { toast } from 'sonner';

interface ReplyComposeProps {
  messageId?: string;
}

export default function ReplyCompose({ messageId }: ReplyComposeProps) {
  const [mode, setMode] = useQueryState('mode');
  const { enableScope, disableScope } = useHotkeysContext();
  const { data: aliases } = useEmailAliases();

  const [draftId, setDraftId] = useQueryState('draftId');
  const [threadId] = useQueryState('threadId');
  const [, setActiveReplyId] = useQueryState('activeReplyId');
  const { data: emailData, refetch, latestDraft } = useThread(threadId);
  const { data: draft } = useDraft(draftId ?? null);
  const trpc = useTRPC();
  const { mutateAsync: sendEmail } = useMutation(trpc.mail.send.mutationOptions());
  const { data: activeConnection } = useActiveConnection();
  const { data: settings, isLoading: settingsLoading } = useSettings();
  const { data: session } = useSession();
  const { handleUndoSend } = useUndoSend();

  // Find the specific message to reply to
  const replyToMessage =
    (messageId && emailData?.messages.find((msg) => msg.id === messageId)) || emailData?.latest;

  // Derive To/Cc recipients for the active mode and feed them to EmailComposer
  // as `initialTo` / `initialCc`. Previously these were computed in a useEffect
  // that never assigned them — reply To-field arrived empty and the user had
  // to retype the recipient (or hit the zod `to.min(1)` validation wall).
  const { computedTo, computedCc } = useMemo(() => {
    if (!replyToMessage || !mode || !activeConnection?.email) {
      return { computedTo: [] as string[], computedCc: [] as string[] };
    }

    const userEmail = activeConnection.email.toLowerCase();
    const senderEmail = replyToMessage.sender.email.toLowerCase();

    if (mode === 'reply') {
      const to: string[] = [];
      if (senderEmail !== userEmail) {
        to.push(replyToMessage.sender.email);
      } else if (replyToMessage.to && replyToMessage.to.length > 0 && replyToMessage.to[0]?.email) {
        // Replying to our own sent mail — fall back to first original recipient.
        to.push(replyToMessage.to[0].email);
      }
      return { computedTo: to, computedCc: [] as string[] };
    }

    if (mode === 'replyAll') {
      const to: string[] = [];
      const cc: string[] = [];
      if (senderEmail !== userEmail) to.push(replyToMessage.sender.email);
      replyToMessage.to?.forEach((recipient) => {
        const recipientEmail = recipient.email.toLowerCase();
        if (recipientEmail !== userEmail && recipientEmail !== senderEmail) {
          to.push(recipient.email);
        }
      });
      replyToMessage.cc?.forEach((recipient) => {
        const recipientEmail = recipient.email.toLowerCase();
        if (recipientEmail !== userEmail && !to.includes(recipient.email)) {
          cc.push(recipient.email);
        }
      });
      return { computedTo: to, computedCc: cc };
    }

    // mode === 'forward' — start empty; user fills recipients themselves.
    return { computedTo: [] as string[], computedCc: [] as string[] };
  }, [mode, replyToMessage, activeConnection?.email]);

  const handleSendEmail = async (data: {
    to: string[];
    cc?: string[];
    bcc?: string[];
    subject: string;
    message: string;
    attachments: File[];
    scheduleAt?: string;
    fromEmail?: string;
  }) => {
    if (!replyToMessage || !activeConnection?.email) return;

    try {
      const userEmail = activeConnection.email.toLowerCase();
      const userName = activeConnection.name || session?.user?.name || '';

      // Honor an explicit From picked in the composer first — alias-matching is
      // only the fallback when the user didn't choose. Previously the form's
      // `data.fromEmail` was discarded and every reply sent from the
      // alias-matched address, ignoring the picker.
      let fromEmail = data.fromEmail?.trim() || userEmail;

      if (!data.fromEmail && aliases && aliases.length > 0 && replyToMessage) {
        const allRecipients = [
          ...(replyToMessage.to || []),
          ...(replyToMessage.cc || []),
          ...(replyToMessage.bcc || []),
        ];
        const matchingAlias = aliases.find((alias) =>
          allRecipients.some(
            (recipient) => recipient.email.toLowerCase() === alias.email.toLowerCase(),
          ),
        );

        if (matchingAlias) {
          fromEmail = userName.trim()
            ? `${userName.replace(/[<>]/g, '')} <${matchingAlias.email}>`
            : matchingAlias.email;
        } else {
          const primaryEmail =
            aliases.find((alias) => alias.primary)?.email || aliases[0]?.email || userEmail;
          fromEmail = userName.trim()
            ? `${userName.replace(/[<>]/g, '')} <${primaryEmail}>`
            : primaryEmail;
        }
      }

      const toRecipients: Sender[] = data.to.map((email) => ({
        email,
        name: email.split('@')[0] || 'User',
      }));

      const ccRecipients: Sender[] | undefined = data.cc
        ? data.cc.map((email) => ({
          email,
          name: email.split('@')[0] || 'User',
        }))
        : undefined;

      const bccRecipients: Sender[] | undefined = data.bcc
        ? data.bcc.map((email) => ({
          email,
          name: email.split('@')[0] || 'User',
        }))
        : undefined;

      // Field renamed `zeroSignature` → `todusSignature` on the server schema
      // (see apps/server/src/lib/schemas.ts:204). The old key returns undefined,
      // which is falsy, so the signature footer used to silently never render.
      const todusSignature = settings?.settings.todusSignature
        ? '<p style="color: #666; font-size: 12px;">Sent via <a href="https://todus.app/" style="color: #0066cc; text-decoration: none;">Todus</a></p>'
        : '';


      const emailBody =
        mode === 'forward'
          ? constructForwardBody(
            data.message + todusSignature,

            new Date(replyToMessage.receivedOn || '').toLocaleString(),
            { ...replyToMessage.sender, subject: replyToMessage.subject },
            toRecipients,
            //   replyToMessage.decodedBody,
          )
          : constructReplyBody(
            data.message + todusSignature,

            new Date(replyToMessage.receivedOn || '').toLocaleString(),
            replyToMessage.sender,
            toRecipients,
            //   replyToMessage.decodedBody,
          );

      const result = await sendEmail({
        to: toRecipients,
        cc: ccRecipients,
        bcc: bccRecipients,
        subject: data.subject,
        message: emailBody,
        attachments: await serializeFiles(data.attachments),
        fromEmail: fromEmail,
        draftId: draftId ?? undefined,
        headers: {
          'In-Reply-To': replyToMessage?.messageId ?? '',
          References: [
            ...(replyToMessage?.references ? replyToMessage.references.split(' ') : []),
            replyToMessage?.messageId,
          ]
            .filter(Boolean)
            .join(' '),
          'Thread-Id': replyToMessage?.threadId ?? '',
        },
        threadId: replyToMessage?.threadId,
        isForward: mode === 'forward',
        originalMessage: replyToMessage.decodedBody,
        scheduleAt: data.scheduleAt,
      });

      posthog.capture('Reply Email Sent');

      // Reset states
      setMode(null);
      await refetch();

      handleUndoSend(result, settings, {
        to: data.to,
        cc: data.cc,
        bcc: data.bcc,
        subject: data.subject,
        message: data.message,
        attachments: data.attachments,
        scheduleAt: data.scheduleAt,
      });
    } catch (error) {
      console.error('Error sending email:', error);
      toast.error(m['pages.createEmail.failedToSendEmail']());
    }
  };

  useEffect(() => {
    if (mode) {
      enableScope('compose');
    } else {
      disableScope('compose');
    }
    return () => {
      disableScope('compose');
    };
  }, [mode, enableScope, disableScope]);

  // Defensive coercion — drafts may arrive as `string[]`, `Sender[]` (from
  // listDrafts $raw), `string`, or null/undefined depending on whether the
  // draft was fetched via drafts.get or hydrated from a list payload.
  // Previously this only handled string|string[] and would throw
  // `email.trim is not a function` on Sender[] inputs, crashing the composer.
  const ensureEmailArray = (
    emails: string | Array<string | { name?: string; email?: string }> | undefined | null,
  ): string[] => {
    if (!emails) return [];
    const toEmailString = (entry: unknown): string => {
      if (typeof entry === 'string') return entry;
      if (entry && typeof entry === 'object') {
        const e = (entry as { email?: unknown }).email;
        if (typeof e === 'string') return e;
      }
      return '';
    };
    if (Array.isArray(emails)) {
      return emails
        .map(toEmailString)
        .map((email) => email.trim().replace(/[<>]/g, ''))
        .filter((email) => email.length > 0);
    }
    if (typeof emails === 'string') {
      return emails
        .split(',')
        .map((email) => email.trim())
        .filter((email) => email.length > 0)
        .map((email) => email.replace(/[<>]/g, ''));
    }
    return [];
  };

  if (!mode || !emailData) return null;

  return (
    <div className="w-full rounded-2xl overflow-visible border">
      <EmailComposer
        editorClassName="min-h-[50px]"
        className="w-full max-w-none! pb-1 overflow-visible"
        onSendEmail={handleSendEmail}
        onClose={async () => {
          setMode(null);
          setDraftId(null);
          setActiveReplyId(null);
        }}
        initialMessage={draft?.content ?? latestDraft?.decodedBody}
        // Draft values (resumed reply) take precedence; otherwise use the
        // recipients derived from the original message for reply / reply-all.
        initialTo={
          draft?.to ? ensureEmailArray(draft.to) : computedTo
        }
        initialCc={
          draft?.cc ? ensureEmailArray(draft.cc) : computedCc
        }
        initialBcc={ensureEmailArray(draft?.bcc)}
        initialSubject={draft?.subject}
        autofocus={true}
        settingsLoading={settingsLoading}
        replyingTo={replyToMessage?.sender.email}
      />
    </div>
  );
}
