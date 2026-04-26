import { EmailCard } from './EmailCard';

type Email = {
  threadId: string;
  sender: string;
  senderEmail: string;
  subject: string;
  snippet: string;
  receivedAt: string;
  isUnread: boolean | null;
  labels: Array<{ name: string; color: string | null }> | null;
};

interface EmailListCardProps {
  props: {
    title: string | null;
    emails: Email[];
    summary: string | null;
  };
  emit?: (event: string, params?: Record<string, unknown>) => void;
}

export function EmailListCard({ props, emit }: EmailListCardProps) {
  return (
    <div className="flex flex-col gap-2">
      {props.title && (
        <p className="text-base font-semibold text-black dark:text-white">{props.title}</p>
      )}

      {props.emails.length > 0 ? (
        <div className="overflow-hidden rounded-xl border border-[#E7E7E7] dark:border-[#252525]">
          {props.emails.map((email, idx) => (
            <div
              key={email.threadId}
              className={idx > 0 ? 'border-t border-[#E7E7E7] dark:border-[#252525]' : ''}
            >
              <EmailCard props={email} emit={emit} />
            </div>
          ))}
        </div>
      ) : (
        <p className="text-muted-foreground text-sm">No emails to show.</p>
      )}

      {props.summary && (
        <div className="mt-1 flex flex-col gap-1">
          <p className="text-base font-semibold text-black dark:text-white">Summary</p>
          <p className="text-sm whitespace-pre-wrap text-black dark:text-white">{props.summary}</p>
        </div>
      )}
    </div>
  );
}
