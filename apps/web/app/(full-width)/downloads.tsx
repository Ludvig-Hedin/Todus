import { Apple, ArrowLeft, Globe } from 'lucide-react';
import { Navigation } from '@/components/navigation';
import { Button } from '@/components/ui/button';
import Footer from '@/components/home/footer';
import type { MetaFunction } from 'react-router';
import { Link } from 'react-router';

const AppleIcon = Apple as any;
const ArrowLeftIcon = ArrowLeft as any;
const GlobeIcon = Globe as any;

// TODO: Replace REPLACE_WITH_HASH with the actual hash from:
// `cd apps/server && npx wrangler r2 bucket dev-url get todus-releases`
const MAC_DMG_URL = 'https://pub-REPLACE_WITH_HASH.r2.dev/mac/Todus-1.0.dmg';

export const meta: MetaFunction = () => {
  return [
    { title: 'Download Todus — Mac, iPhone, and Web' },
    {
      name: 'description',
      content:
        'Download Todus for macOS and iPhone, or use the web app right in your browser.',
    },
    { property: 'og:title', content: 'Download Todus — Mac, iPhone, and Web' },
    {
      property: 'og:description',
      content:
        'Download Todus for macOS and iPhone, or use the web app right in your browser.',
    },
    { tagName: 'link', rel: 'canonical', href: 'https://todus.app/downloads' },
  ];
};

export default function DownloadsPage() {
  return (
    <div className="relative flex min-h-screen w-full flex-col overflow-auto bg-white dark:bg-[#0F0F0F]">
      <Navigation />

      <div className="relative z-10 flex grow flex-col">
        <div className="absolute right-4 top-6 md:left-8 md:right-auto md:top-8">
          <a href="/">
            <Button
              variant="ghost"
              size="sm"
              className="gap-2 text-gray-600 hover:text-gray-900 dark:text-white dark:hover:text-white/80"
            >
              <ArrowLeftIcon className="h-4 w-4" />
              Back
            </Button>
          </a>
        </div>

        <section className="mx-auto w-full max-w-6xl px-4 pt-32 pb-12 text-center">
          <h1 className="text-4xl font-semibold tracking-tight text-gray-900 md:text-6xl dark:text-white">
            Get Started Today
          </h1>
          <p className="mx-auto mt-5 max-w-2xl text-base text-gray-600 md:text-lg dark:text-white/60">
            Bring Todus everywhere you work — on your Mac, iPhone, or right in your browser.
          </p>
        </section>

        <section className="mx-auto grid w-full max-w-6xl grid-cols-1 gap-4 px-4 pb-24 md:grid-cols-3">
          <DownloadCard
            title="Desktop App"
            description="The full Todus experience on macOS 15+."
          >
            <div className="flex flex-col gap-3">
              <Button
                asChild
                variant="outline"
                className="w-full h-10 gap-2 border-gray-200 bg-white text-gray-900 hover:bg-gray-50 dark:border-white/10 dark:bg-white/5 dark:text-white dark:hover:bg-white/10"
              >
                <a href={MAC_DMG_URL} download="Todus.dmg">
                  <AppleIcon className="h-4 w-4" />
                  Download for Mac
                </a>
              </Button>
              <p className="text-xs text-gray-500 dark:text-white/40">
                First launch: right-click → Open to bypass the security warning.
              </p>
            </div>
          </DownloadCard>

          <DownloadCard
            title="Mobile App"
            description="Take Todus with you on iPhone."
          >
            <div className="flex flex-col gap-3">
              <p className="text-xs text-gray-500 dark:text-white/40">Available on the App Store:</p>
              <a
                href="https://apps.apple.com/app/todus"
                target="_blank"
                rel="noreferrer"
                className="inline-flex h-10 items-center justify-center gap-2 rounded-md bg-black px-4 text-sm font-medium text-white transition-opacity hover:opacity-90"
              >
                <AppleIcon className="h-4 w-4" />
                <span>Download on the App Store</span>
              </a>
            </div>
          </DownloadCard>

          <DownloadCard
            title="Web App"
            description="Use Todus directly from your browser — no install needed."
          >
            <Button
              asChild
              className="w-full h-10 gap-2 bg-gray-900 text-white hover:bg-gray-800 dark:bg-white dark:text-black dark:hover:bg-white/90"
            >
              <Link to="/login">
                <GlobeIcon className="h-4 w-4" />
                Open the Web App
              </Link>
            </Button>
          </DownloadCard>
        </section>

        <Footer />
      </div>
    </div>
  );
}

function DownloadCard({
  title,
  description,
  children,
}: {
  title: string;
  description: string;
  children: React.ReactNode;
}) {
  return (
    <div className="flex flex-col gap-6 rounded-2xl border border-gray-200 bg-white p-6 md:p-7 dark:border-white/10 dark:bg-white/[0.03]">
      <div className="space-y-2">
        <h2 className="text-xl font-semibold tracking-tight text-gray-900 dark:text-white">
          {title}
        </h2>
        <p className="text-sm text-gray-600 dark:text-white/60">{description}</p>
      </div>
      <div className="mt-auto">{children}</div>
    </div>
  );
}
