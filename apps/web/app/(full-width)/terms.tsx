import { ArrowLeft, Link2, Github, type LucideIcon } from 'lucide-react';
import { useCopyToClipboard } from '@/hooks/use-copy-to-clipboard';
import { Card, CardHeader, CardTitle } from '@/components/ui/card';

// Type casts for Lucide icons to resolve TS2786
const ArrowLeftIcon = ArrowLeft as LucideIcon;
const Link2Icon = Link2 as LucideIcon;
const GithubIcon = Github as LucideIcon;

import { Navigation } from '@/components/navigation';
import { Button } from '@/components/ui/button';
import Footer from '@/components/home/footer';
import { createSectionId } from '@/lib/utils';

const LAST_UPDATED = 'June 19, 2026';

export default function TermsOfService() {
  const { copiedValue: copiedSection, copyToClipboard } = useCopyToClipboard();

  const handleCopyLink = (sectionId: string) => {
    const url = `${window.location.origin}${window.location.pathname}#${sectionId}`;
    copyToClipboard(url, sectionId);
  };

  return (
    <div className="relative flex min-h-screen w-full flex-col overflow-auto bg-white dark:bg-[#111111]">
      <Navigation />
      <div className="relative z-10 flex grow flex-col">
        {/* Back Button */}
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

        <div className="container mx-auto max-w-4xl px-4 py-16">
          <Card className="overflow-hidden rounded-xl border-none bg-gray-50/80 dark:bg-transparent">
            <CardHeader className="space-y-4 px-8 py-8">
              <div className="space-y-2 text-center">
                <CardTitle className="text-3xl font-bold tracking-tight text-gray-900 md:text-4xl dark:text-white">
                  Terms of Service
                </CardTitle>
                <div className="flex items-center justify-center gap-2">
                  <p className="text-sm text-gray-500 dark:text-white/60">
                    Last updated: {LAST_UPDATED}
                  </p>
                </div>
              </div>
            </CardHeader>

            <div className="space-y-8 p-8">
              {sections.map((section) => {
                const sectionId = createSectionId(section.title);
                return (
                  <div key={section.title} id={sectionId} className="p-6">
                    <div className="mb-4 flex items-center justify-between">
                      <h2 className="text-xl font-semibold tracking-tight text-gray-900 dark:text-white">
                        {section.title}
                      </h2>
                      <button
                        onClick={() => handleCopyLink(sectionId)}
                        className="text-gray-400 hover:text-gray-700 dark:text-white/60 dark:hover:text-white/80"
                        aria-label={`Copy link to ${section.title} section`}
                      >
                        <Link2Icon
                          className={`h-4 w-4 ${copiedSection === sectionId ? 'text-green-500 dark:text-green-400' : ''}`}
                        />
                      </button>
                    </div>
                    <div className="prose prose-sm prose-a:text-blue-600 hover:prose-a:text-blue-800 dark:prose-a:text-blue-400 dark:hover:prose-a:text-blue-300 max-w-none text-gray-600 dark:text-white/80">
                      {section.content}
                    </div>
                  </div>
                );
              })}

              <div className="mt-12 flex flex-wrap items-center justify-center gap-4"></div>
            </div>
          </Card>
        </div>

        <Footer />
      </div>
    </div>
  );
}

const sections = [
  {
    title: 'Overview',
    content: (
      <p>
        Todus is a productivity service for email, calendar, tasks, docs, meetings, and AI
        assistance. These terms apply to the hosted Todus web, iOS, and macOS apps. By using Todus,
        you agree to these terms and to any policies linked from the service.
      </p>
    ),
  },
  {
    title: 'Service Description',
    content: (
      <ul className="ml-4 list-disc space-y-2">
        <li>Todus can connect to third-party accounts such as email and calendar providers.</li>
        <li>Todus can store and sync user-created workspace data across supported clients.</li>
        <li>
          Todus can use AI providers to process prompts and selected workspace data at your
          direction.
        </li>
        <li>Some features may be experimental, limited, unavailable, or changed over time.</li>
      </ul>
    ),
  },
  {
    title: 'User Responsibilities',
    content: (
      <div className="text-muted-foreground mt-4 space-y-3">
        <p>Users agree to:</p>
        <ul className="ml-4 list-disc space-y-2">
          <li>Comply with applicable laws and third-party provider terms.</li>
          <li>Keep account credentials secure and promptly report unauthorized access.</li>
          <li>
            Not use Todus for spam, abuse, unlawful content, malware, phishing, or harassment.
          </li>
          <li>Respect privacy, confidentiality, and intellectual property rights.</li>
          <li>Only connect accounts and data you are authorized to use.</li>
        </ul>
      </div>
    ),
  },
  {
    title: 'Connected Services and AI',
    content: (
      <div className="text-muted-foreground mt-4 space-y-3">
        <p>
          Todus depends on third-party providers for connected accounts, infrastructure, billing,
          analytics, diagnostics, and AI features.
        </p>
        <ul className="ml-4 list-disc space-y-2">
          <li>Third-party services may be unavailable, rate-limited, or changed without notice.</li>
          <li>AI outputs may be inaccurate and should be reviewed before relying on them.</li>
          <li>
            You are responsible for deciding what data to send to connected services and AI
            features.
          </li>
        </ul>
      </div>
    ),
  },
  {
    title: 'Billing',
    content: (
      <div className="text-muted-foreground mt-4 space-y-3">
        <p>
          Todus may offer free and paid plans depending on platform and availability. Paid iOS plan
          changes are offered only when an App Store-compliant purchase flow is available for the
          iOS app.
        </p>
        <ul className="ml-4 list-disc space-y-2">
          <li>Plan limits, pricing, and features may change over time.</li>
          <li>Refunds and cancellations may depend on the payment provider, platform, and law.</li>
          <li>
            Taxes, fees, currency conversion, and payment authorization are handled by payment
            providers.
          </li>
        </ul>
      </div>
    ),
  },
  {
    title: 'Content and Acceptable Use',
    content: (
      <ul className="ml-4 list-disc space-y-2">
        <li>
          You retain rights to your content, subject to the permissions needed to operate Todus.
        </li>
        <li>
          You must not upload, share, or generate unlawful, abusive, infringing, or harmful content.
        </li>
        <li>
          We may restrict, suspend, or remove access to protect users, Todus, providers, or legal
          compliance.
        </li>
      </ul>
    ),
  },
  {
    title: 'Disclaimers and Liability',
    content: (
      <ul className="ml-4 list-disc space-y-2">
        <li>Todus is provided as available and may contain bugs or interruptions.</li>
        <li>
          We do not guarantee that AI outputs, sync results, notifications, or imported data are
          complete or error-free.
        </li>
        <li>
          To the maximum extent permitted by law, Todus is not liable for indirect, incidental,
          special, consequential, or punitive damages.
        </li>
      </ul>
    ),
  },
  {
    title: 'Contact Information',
    content: (
      <div className="text-muted-foreground mt-4 space-y-3">
        <p>For questions about these terms:</p>
        <div className="flex flex-col space-y-2">
          <a
            href="mailto:founders@todus.app"
            className="inline-flex items-center text-blue-600 hover:text-blue-800"
          >
            founders@todus.app
          </a>
          <a
            href="https://github.com/Ludvig-Hedin/Todus"
            className="inline-flex items-center text-blue-600 hover:text-blue-800"
          >
            <GithubIcon className="mr-2 h-4 w-4" />
            Open an issue on GitHub
          </a>
        </div>
      </div>
    ),
  },
];
