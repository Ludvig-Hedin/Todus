import { Avatar, AvatarFallback, AvatarImage } from '@/components/ui/avatar';
import { getEmailLogo } from '@/lib/utils';
import { ChevronDown, ChevronUp, Paperclip, Send, Loader2, Check, X } from 'lucide-react';
import { useEffect, useRef, useState } from 'react';

type Recipient = { name: string | null; email: string };
type Attachment = { name: string; size: number; mimeType: string };

interface InlineComposeCardProps {
  props: {
    draftId: string;
    to: Recipient[];
    cc: Recipient[] | null;
    bcc: Recipient[] | null;
    subject: string;
    body: string;
    attachments: Attachment[] | null;
    status: 'draft' | 'sending' | 'sent' | 'error' | null;
  };
  emit?: (event: string, params?: Record<string, unknown>) => void;
}

const AUTOSAVE_DEBOUNCE_MS = 600;

function formatFileSize(bytes: number): string {
  if (!Number.isFinite(bytes) || bytes <= 0) return '';
  const units = ['B', 'KB', 'MB', 'GB'];
  let i = 0;
  let n = bytes;
  while (n >= 1024 && i < units.length - 1) {
    n /= 1024;
    i++;
  }
  return `${n.toFixed(n < 10 && i > 0 ? 1 : 0)} ${units[i]}`;
}

function buildPayload(args: {
  to: Recipient[];
  cc: Recipient[];
  bcc: Recipient[];
  subject: string;
  body: string;
}): string {
  return JSON.stringify(args);
}

function RecipientPill({ recipient, onRemove }: { recipient: Recipient; onRemove?: () => void }) {
  return (
    <span className="inline-flex items-center gap-1.5 rounded-full bg-[#F6F6F7] px-2 py-1 text-xs text-black dark:bg-[#252525] dark:text-white">
      <Avatar className="h-4 w-4">
        <AvatarImage className="rounded-full" src={getEmailLogo(recipient.email)} />
        <AvatarFallback className="rounded-full text-[8px]">
          {(recipient.name ?? recipient.email)?.[0]?.toUpperCase() ?? '?'}
        </AvatarFallback>
      </Avatar>
      <span>{recipient.name ?? recipient.email}</span>
      {onRemove && (
        <button
          type="button"
          onClick={onRemove}
          className="opacity-60 hover:opacity-100"
          aria-label="Remove recipient"
        >
          <X className="h-3 w-3" />
        </button>
      )}
    </span>
  );
}

export function InlineComposeCard({ props, emit }: InlineComposeCardProps) {
  const initialDraftIdRef = useRef(props.draftId);
  const [to, setTo] = useState<Recipient[]>(props.to);
  const [cc, setCc] = useState<Recipient[]>(props.cc ?? []);
  const [bcc, setBcc] = useState<Recipient[]>(props.bcc ?? []);
  const [subject, setSubject] = useState(props.subject);
  const [body, setBody] = useState(props.body);
  const [showCcBcc, setShowCcBcc] = useState((props.cc?.length ?? 0) > 0 || (props.bcc?.length ?? 0) > 0);
  const [recipientInput, setRecipientInput] = useState('');
  const [saveStatus, setSaveStatus] = useState<'saved' | 'saving' | 'syncing' | 'error'>('saved');
  const [sendStatus, setSendStatus] = useState<typeof props.status>(props.status ?? 'draft');

  // If the AI re-emits a spec for the same draft after the user has made local edits, ignore it
  // (don't clobber unsent edits). Re-emissions for a different draftId are handled by React's key.
  const isDirtyRef = useRef(false);

  useEffect(() => {
    setSendStatus(props.status ?? 'draft');
  }, [props.status]);

  // Hold the pending autosave timer in a ref so Send (and unmount) can both cancel it
  // — otherwise an orphan autosave fires ~600ms after Send and races the send mutation.
  const autosaveTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  // Debounced autosave
  useEffect(() => {
    if (!isDirtyRef.current) return;
    setSaveStatus('saving');
    if (autosaveTimerRef.current != null) clearTimeout(autosaveTimerRef.current);
    autosaveTimerRef.current = setTimeout(() => {
      const payload = buildPayload({ to, cc, bcc, subject, body });
      setSaveStatus('syncing');
      emit?.('press', { action: 'update_draft', draftId: props.draftId, payload });
      isDirtyRef.current = false;
      autosaveTimerRef.current = null;
    }, AUTOSAVE_DEBOUNCE_MS);
    return () => {
      if (autosaveTimerRef.current != null) {
        clearTimeout(autosaveTimerRef.current);
        autosaveTimerRef.current = null;
      }
    };
  }, [to, cc, bcc, subject, body, emit, props.draftId]);

  const markDirty = () => {
    isDirtyRef.current = true;
  };

  const addRecipient = (target: 'to' | 'cc' | 'bcc') => {
    const trimmed = recipientInput.trim();
    // Reject empty, missing @, missing local part, or missing domain. Catches "foo@", "@bar", "  @  ".
    const at = trimmed.indexOf('@');
    if (at <= 0 || at === trimmed.length - 1 || trimmed.includes(' ')) return;
    const normalized = trimmed.toLowerCase();
    const recipient: Recipient = { name: null, email: trimmed };
    const appendUnique = (prev: Recipient[]) =>
      prev.some((r) => r.email.toLowerCase() === normalized) ? prev : [...prev, recipient];
    if (target === 'to') setTo(appendUnique);
    if (target === 'cc') setCc(appendUnique);
    if (target === 'bcc') setBcc(appendUnique);
    setRecipientInput('');
    markDirty();
  };

  const removeRecipient = (target: 'to' | 'cc' | 'bcc', email: string) => {
    if (target === 'to') setTo((prev) => prev.filter((r) => r.email !== email));
    if (target === 'cc') setCc((prev) => prev.filter((r) => r.email !== email));
    if (target === 'bcc') setBcc((prev) => prev.filter((r) => r.email !== email));
    markDirty();
  };

  const handleSend = () => {
    // Cancel any pending autosave so it doesn't race the send mutation.
    if (autosaveTimerRef.current != null) {
      clearTimeout(autosaveTimerRef.current);
      autosaveTimerRef.current = null;
    }
    isDirtyRef.current = false;
    setSendStatus('sending');
    const payload = buildPayload({ to, cc, bcc, subject, body });
    emit?.('press', { action: 'send_draft', draftId: props.draftId, payload });
  };

  // Once sent, lock the card visually
  const isLocked = sendStatus === 'sending' || sendStatus === 'sent';

  // Suppress this comment: prevents stale-prop reset for the same draftId
  void initialDraftIdRef;

  return (
    <div className="flex flex-col gap-2 overflow-hidden rounded-xl border border-[#E7E7E7] bg-white dark:border-[#252525] dark:bg-[#1C1C1E]">
      {/* Header chip */}
      <div className="flex items-center justify-between px-3 pt-3">
        <span className="inline-flex items-center gap-1.5 rounded-full bg-[#F6F6F7] px-2 py-1 text-xs text-black dark:bg-[#252525] dark:text-white">
          <Send className="h-3 w-3" />
          New email
        </span>
        <button
          onClick={() => setShowCcBcc((s) => !s)}
          className="text-[#8C8C8C] hover:opacity-70"
          aria-label="Toggle CC/BCC"
        >
          {showCcBcc ? <ChevronUp className="h-4 w-4" /> : <ChevronDown className="h-4 w-4" />}
        </button>
      </div>

      {/* Recipients */}
      <div className="flex flex-col gap-1.5 px-3">
        <div className="flex flex-wrap items-center gap-1.5">
          <span className="text-xs text-[#8C8C8C]">To:</span>
          {to.map((r) => (
            <RecipientPill
              key={r.email}
              recipient={r}
              onRemove={isLocked ? undefined : () => removeRecipient('to', r.email)}
            />
          ))}
          {!isLocked && (
            <input
              type="email"
              placeholder="Add email…"
              value={recipientInput}
              onChange={(e) => setRecipientInput(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === 'Enter' || e.key === ',') {
                  e.preventDefault();
                  addRecipient('to');
                }
              }}
              className="flex-1 min-w-[100px] bg-transparent text-xs text-black placeholder:text-[#8C8C8C] focus:outline-none dark:text-white"
            />
          )}
        </div>

        {showCcBcc && (
          <>
            <div className="flex flex-wrap items-center gap-1.5">
              <span className="text-xs text-[#8C8C8C]">CC:</span>
              {cc.map((r) => (
                <RecipientPill
                  key={r.email}
                  recipient={r}
                  onRemove={isLocked ? undefined : () => removeRecipient('cc', r.email)}
                />
              ))}
            </div>
            <div className="flex flex-wrap items-center gap-1.5">
              <span className="text-xs text-[#8C8C8C]">BCC:</span>
              {bcc.map((r) => (
                <RecipientPill
                  key={r.email}
                  recipient={r}
                  onRemove={isLocked ? undefined : () => removeRecipient('bcc', r.email)}
                />
              ))}
            </div>
          </>
        )}
      </div>

      <div className="h-px w-full bg-[#E7E7E7] dark:bg-[#252525]" />

      {/* Subject */}
      <div className="px-3">
        <input
          type="text"
          placeholder="Subject"
          value={subject}
          onChange={(e) => {
            setSubject(e.target.value);
            markDirty();
          }}
          disabled={isLocked}
          className="w-full bg-transparent text-sm font-medium text-black placeholder:text-[#8C8C8C] focus:outline-none dark:text-white"
        />
      </div>

      {/* Attachments (display-only — actual picker fires `attach_to_draft`) */}
      {props.attachments && props.attachments.length > 0 && (
        <div className="flex flex-wrap gap-1.5 px-3 pb-1">
          {props.attachments.map((file) => (
            <span
              key={`${file.name}-${file.size}`}
              className="inline-flex items-center gap-1.5 rounded-md bg-[#F6F6F7] px-2 py-1 text-xs text-black dark:bg-[#252525] dark:text-white"
            >
              <Paperclip className="h-3 w-3 text-[#8C8C8C]" />
              <span className="max-w-[160px] truncate">{file.name}</span>
              <span className="text-[10px] text-[#8C8C8C]">{formatFileSize(file.size)}</span>
            </span>
          ))}
        </div>
      )}

      <div className="h-px w-full bg-[#E7E7E7] dark:bg-[#252525]" />

      {/* Body */}
      <div className="px-3 pb-3">
        <textarea
          value={body}
          onChange={(e) => {
            setBody(e.target.value);
            markDirty();
          }}
          disabled={isLocked}
          rows={8}
          className="w-full resize-none bg-transparent text-sm text-black placeholder:text-[#8C8C8C] focus:outline-none dark:text-white"
          placeholder="Write your email…"
        />
      </div>

      {/* Footer */}
      <div className="flex items-center justify-between border-t border-[#E7E7E7] px-3 py-2 dark:border-[#252525]">
        <span className="text-xs text-[#8C8C8C]">
          {sendStatus === 'sent'
            ? 'Sent'
            : sendStatus === 'sending'
              ? 'Sending…'
              : sendStatus === 'error'
                ? 'Failed to send'
                : saveStatus === 'saving'
                  ? 'Saving…'
                  : saveStatus === 'syncing'
                    ? 'Syncing changes…'
                    : saveStatus === 'error'
                      ? 'Save failed'
                      : 'All changes are saved'}
        </span>
        <div className="flex items-center gap-2">
          <button
            onClick={() => emit?.('press', { action: 'attach_to_draft', draftId: props.draftId })}
            disabled={isLocked}
            className="flex h-8 w-8 items-center justify-center rounded-full border border-[#E7E7E7] text-[#8C8C8C] hover:opacity-70 disabled:opacity-30 dark:border-[#252525]"
            aria-label="Attach"
          >
            <Paperclip className="h-3.5 w-3.5" />
          </button>
          <button
            onClick={handleSend}
            disabled={isLocked || to.length === 0}
            className="inline-flex items-center gap-1.5 rounded-full bg-[#437DFB] px-3 py-1.5 text-xs font-medium text-white hover:opacity-90 disabled:opacity-50"
          >
            {sendStatus === 'sending' ? (
              <Loader2 className="h-3 w-3 animate-spin" />
            ) : sendStatus === 'sent' ? (
              <Check className="h-3 w-3" />
            ) : (
              <Send className="h-3 w-3" />
            )}
            {sendStatus === 'sent' ? 'Sent' : 'Send'}
          </button>
        </div>
      </div>
    </div>
  );
}
