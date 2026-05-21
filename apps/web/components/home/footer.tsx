import { TodusLogo } from '@/components/ui/todus-logo';
import { APP_NAME } from '@/lib/branding';
import { Link } from 'react-router';

const RESOURCES = [
  { label: 'Privacy Policy', href: '/privacy' },
  { label: 'Terms of Service', href: '/terms' },
];

const PRODUCT = [
  { label: 'Download', href: '/downloads' },
  { label: 'Pricing', href: '/pricing' },
  { label: 'FAQ', href: '/faq' },
  { label: 'Github', href: 'https://github.com/Ludvig-Hedin/Todus', external: true },
];

const COMPANY = [
  { label: 'About', href: '/about' },
  { label: 'Contact', href: '/contact' },
];

export default function Footer() {
  const year = new Date().getFullYear();

  return (
    <footer className="border-t border-white/10 bg-transparent">
      <div className="mx-auto flex w-full max-w-7xl flex-col gap-12 px-4 py-16">
        <div className="flex w-full flex-col gap-12 md:flex-row md:items-start md:justify-between">
          <div className="flex flex-col items-start gap-4">
            <a href="/" className="inline-flex items-center">
              <TodusLogo height={28} className="text-white" />
            </a>
            <p className="max-w-xs text-sm text-white/50">
              The AI-native email client for inbox, calendar, and tasks.
            </p>
          </div>

          <div className="grid grid-cols-2 gap-10 md:flex md:flex-1 md:justify-end md:gap-16">
            <FooterColumn title="Product" items={PRODUCT} />
            <FooterColumn title="Resources" items={RESOURCES} />
            <FooterColumn title="Company" items={COMPANY} />
          </div>
        </div>

        <div className="h-px w-full bg-white/10" />

        <div className="flex flex-col-reverse items-start justify-between gap-3 md:flex-row md:items-center">
          <div className="text-xs font-medium text-white/50 sm:text-sm">
            {`© ${year} ${APP_NAME}. All rights reserved.`}
          </div>
          <div className="flex flex-wrap items-center gap-4">
            <Link
              to="/about"
              className="text-sm text-white/60 transition-colors hover:text-white"
            >
              About
            </Link>
            <span className="h-4 w-px bg-white/15" />
            <Link
              to="/contact"
              className="text-sm text-white/60 transition-colors hover:text-white"
            >
              Contact
            </Link>
            <span className="h-4 w-px bg-white/15" />
            <Link
              to="/terms"
              className="text-sm text-white/60 transition-colors hover:text-white"
            >
              Terms
            </Link>
            <span className="h-4 w-px bg-white/15" />
            <Link
              to="/privacy"
              className="text-sm text-white/60 transition-colors hover:text-white"
            >
              Privacy
            </Link>
          </div>
        </div>
      </div>
    </footer>
  );
}

function FooterColumn({
  title,
  items,
}: {
  title: string;
  items: { label: string; href: string; external?: boolean }[];
}) {
  return (
    <div className="flex flex-col gap-5">
      <div className="text-sm font-medium text-white/40">{title}</div>
      <div className="flex flex-col gap-3.5">
        {items.map((item) =>
          item.external ? (
            <a
              key={item.label}
              href={item.href}
              target="_blank"
              rel="noreferrer"
              className="text-sm text-white/80 transition-colors hover:text-white"
            >
              {item.label}
            </a>
          ) : (
            <Link
              key={item.label}
              to={item.href}
              className="text-sm text-white/80 transition-colors hover:text-white"
            >
              {item.label}
            </Link>
          ),
        )}
      </div>
    </div>
  );
}
