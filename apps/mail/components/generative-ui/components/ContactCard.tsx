import { Avatar, AvatarFallback, AvatarImage } from '@/components/ui/avatar';
import { getEmailLogo } from '@/lib/utils';

interface ContactCardProps {
  props: {
    name: string;
    email: string;
    avatarUrl: string | null;
  };
}

export function ContactCard({ props }: ContactCardProps) {
  return (
    <div className="flex items-center gap-3 rounded-lg p-2">
      <Avatar className="h-8 w-8">
        <AvatarImage
          className="rounded-full"
          src={props.avatarUrl ?? getEmailLogo(props.email)}
        />
        <AvatarFallback className="rounded-full bg-[#FFFFFF] font-bold text-[#9F9F9F] dark:bg-[#373737]">
          {props.name?.[0]?.toUpperCase() ?? '?'}
        </AvatarFallback>
      </Avatar>
      <div className="flex flex-col">
        <p className="text-sm font-medium text-black dark:text-white">{props.name}</p>
        <p className="text-xs text-[#8C8C8C]">{props.email}</p>
      </div>
    </div>
  );
}
