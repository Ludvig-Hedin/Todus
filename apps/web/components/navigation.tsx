import { Book, Shield, FileText, Briefcase } from 'lucide-react';
import { Navbar1 } from '@/components/navbar1';
import { signIn, useSession } from '@/lib/auth-client';
import { APP_NAME } from '@/lib/branding';
import { useNavigate } from 'react-router';
import { toast } from 'sonner';

export function Navigation() {
  const { data: session } = useSession();
  const navigate = useNavigate();

  function handleGetStarted() {
    if (session) {
      navigate('/mail/inbox');
    } else {
      toast.promise(
        signIn.social({
          provider: 'google',
          callbackURL: `${window.location.origin}/mail/inbox`,
        }),
        { error: 'Login redirect failed' },
      );
    }
  }

  return (
    <NavigationWrapper onGetStarted={handleGetStarted} sessionExists={!!session} />
  );
}

function NavigationWrapper({
  onGetStarted,
  sessionExists,
}: {
  onGetStarted: () => void;
  sessionExists: boolean;
}) {
  return (
    <div className="fixed top-0 left-0 right-0 z-50 w-full bg-[#0F0F0F]">
      <Navbar1
        logo={{
          url: '/',
          src: '/brand-logo.png',
          alt: APP_NAME,
          title: APP_NAME,
        }}
        menu={[
          { title: 'Pricing', url: '/pricing' },
          { title: 'Download', url: '/downloads' },
          {
            title: 'Company',
            url: '#',
            items: [
              {
                title: 'About',
                description: `Learn more about ${APP_NAME} and our mission.`,
                icon: <Briefcase className="size-5 shrink-0" />,
                url: '/about',
              },
              {
                title: 'Blog',
                description: 'Product updates, tips, and email productivity guides.',
                icon: <Book className="size-5 shrink-0" />,
                url: '/blog',
              },
              {
                title: 'Privacy',
                description: 'How we handle and protect your data.',
                icon: <Shield className="size-5 shrink-0" />,
                url: '/privacy',
              },
              {
                title: 'Terms of Service',
                description: `Our terms and conditions for using ${APP_NAME}.`,
                icon: <FileText className="size-5 shrink-0" />,
                url: '/terms',
              },
            ],
          },
        ]}
        onGetStarted={onGetStarted}
        sessionExists={sessionExists}
      />
    </div>
  );
}
