import { ContactCard } from './ContactCard';

type Contact = {
  name: string;
  email: string;
  avatarUrl: string | null;
};

interface ContactListCardProps {
  props: {
    title: string | null;
    contacts: Contact[];
  };
}

export function ContactListCard({ props }: ContactListCardProps) {
  return (
    <div className="flex flex-col gap-2">
      {props.title && (
        <p className="text-base font-semibold text-black dark:text-white">{props.title}</p>
      )}

      <div className="overflow-hidden rounded-xl border border-[#E7E7E7] dark:border-[#252525]">
        {props.contacts.map((contact, idx) => (
          <div
            key={`${contact.email}-${idx}`}
            className={idx > 0 ? 'border-t border-[#E7E7E7] dark:border-[#252525]' : ''}
          >
            <ContactCard props={contact} />
          </div>
        ))}
      </div>
    </div>
  );
}
