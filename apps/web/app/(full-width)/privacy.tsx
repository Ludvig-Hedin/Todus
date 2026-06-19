import { useCopyToClipboard } from '@/hooks/use-copy-to-clipboard';
import { Card, CardHeader, CardTitle } from '@/components/ui/card';

import { ArrowLeft, Link2, Mail, Github, type LucideIcon } from 'lucide-react';

// Type casts for Lucide icons to resolve TS2786
const ArrowLeftIcon = ArrowLeft as LucideIcon;
const Link2Icon = Link2 as LucideIcon;
const MailIcon = Mail as LucideIcon;
const GithubIcon = Github as LucideIcon;

import { Navigation } from '@/components/navigation';
import { Button } from '@/components/ui/button';
import Footer from '@/components/home/footer';
import { createSectionId } from '@/lib/utils';

const LAST_UPDATED = 'June 19, 2026';

export default function PrivacyPolicy() {
  const { copiedValue: copiedSection, copyToClipboard } = useCopyToClipboard();

  const handleCopyLink = (sectionId: string) => {
    const url = `${window.location.origin}${window.location.pathname}#${sectionId}`;
    copyToClipboard(url, sectionId);
  };

  return (
    <div className="relative flex min-h-screen w-full flex-col overflow-auto bg-white dark:bg-[#111111]">
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

        <div className="container mx-auto max-w-4xl px-4 py-16">
          <Card className="overflow-hidden rounded-xl border-none bg-gray-50/80 dark:bg-transparent">
            <CardHeader className="space-y-4 px-8 py-8">
              <div className="space-y-2 text-center">
                <CardTitle className="text-3xl font-bold tracking-tight text-gray-900 md:text-4xl dark:text-white">
                  Privacy Policy
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
    title: 'Our Commitment to Privacy',
    content: (
      <div className="space-y-4">
        <p>
          Todus is a productivity service for email, calendar, tasks, docs, meetings, and AI
          assistance. We process account and workspace data to provide those features, keep your
          account secure, sync across devices, and improve reliability.
        </p>
        <p>
          This policy describes the hosted Todus web, iOS, and macOS apps. Self-hosted deployments
          are controlled by the person or organization operating that deployment.
        </p>
      </div>
    ),
  },
  {
    title: 'Data We Collect',
    content: (
      <div className="space-y-4">
        <p>Depending on the features you use, Todus may collect or process:</p>
        <ul className="ml-4 list-disc space-y-2">
          <li>
            Account information such as name, email address, profile image, and sign-in method.
          </li>
          <li>
            Authentication data such as sessions, OAuth tokens, verification codes, and
            device/session metadata.
          </li>
          <li>
            Email data you connect to Todus, including message content, headers, recipients, labels,
            attachments, drafts, and thread metadata.
          </li>
          <li>
            Calendar, reminders, task, folder, note, document, meeting, template, and sharing data
            you create or connect.
          </li>
          <li>
            AI prompts, assistant messages, tool results, generated summaries, writing-style data,
            and usage/credit counters.
          </li>
          <li>
            Billing and subscription state such as plan, status, customer identifiers, payment
            processor events, and invoices or receipts handled by payment providers.
          </li>
          <li>
            Diagnostics, logs, crash/error reports, feature usage, approximate device/app
            information, and support communications.
          </li>
        </ul>
      </div>
    ),
  },
  {
    title: 'How We Use Data',
    content: (
      <ul className="ml-4 list-disc space-y-2">
        <li>Provide, sync, secure, troubleshoot, and improve Todus features.</li>
        <li>Authenticate users and protect accounts from unauthorized access.</li>
        <li>
          Connect to email, calendar, reminder, notification, AI, and billing providers at your
          direction.
        </li>
        <li>
          Generate AI assistance, summaries, labels, search results, drafts, and task suggestions.
        </li>
        <li>
          Measure usage limits, subscription status, reliability, abuse prevention, and service
          health.
        </li>
        <li>Respond to support, legal, security, and compliance requests.</li>
      </ul>
    ),
  },
  {
    title: 'Connected Accounts and Google User Data',
    content: (
      <div className="space-y-4">
        <p>
          Todus requests access to connected accounts only after you authorize the connection. For
          Google accounts, Todus uses OAuth and requests the scopes needed for the email, calendar,
          profile, and related productivity features you enable.
        </p>
        <ul className="ml-4 list-disc space-y-2">
          <li>Google user data is used to provide and improve user-facing Todus features.</li>
          <li>We do not sell Google user data or use it for advertising.</li>
          <li>
            We do not allow humans to read Google user data except when you ask for support, when
            required for security or abuse investigation, or when required by law.
          </li>
          <li>
            You can revoke Google access through Todus settings or your Google Account settings.
          </li>
        </ul>
      </div>
    ),
  },
  {
    title: 'Limited Use Disclosure',
    content: (
      <div>
        Our use and transfer to any other app of information received from Google APIs will adhere
        to the{' '}
        <a
          href="https://developers.google.com/terms/api-services-user-data-policy"
          className="inline-flex items-center text-blue-600 hover:text-blue-800"
          target="_blank"
          rel="noopener noreferrer"
        >
          Google API Services User Data Policy
          <svg className="ml-1 h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              strokeWidth={2}
              d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14"
            />
          </svg>
        </a>
        , including the Limited Use requirements.
      </div>
    ),
  },
  {
    title: 'AI Processing',
    content: (
      <div className="space-y-4">
        <p>
          AI features may send the content you choose, or content needed to complete your request,
          to AI infrastructure and model providers. This can include emails, calendar events, tasks,
          docs, meeting notes, attachments, and assistant conversation history.
        </p>
        <ul className="ml-4 list-disc space-y-2">
          <li>
            You control whether to use AI features and whether to connect optional data sources.
          </li>
          <li>
            We use AI outputs to show responses, drafts, summaries, labels, and other requested
            results in Todus.
          </li>
          <li>AI provider availability may vary by feature and configuration.</li>
          <li>
            You should not submit sensitive information to AI features unless you want it processed
            for the requested task.
          </li>
        </ul>
      </div>
    ),
  },
  {
    title: 'Service Providers',
    content: (
      <div className="space-y-4">
        <p>
          Todus relies on service providers to operate the product. These providers process data
          only for the services they provide to Todus, subject to their agreements and policies.
        </p>
        <ul className="ml-4 list-disc space-y-2">
          <li>Cloud hosting, databases, storage, queues, workflows, and content delivery.</li>
          <li>Authentication, email delivery, OAuth providers, and connected account APIs.</li>
          <li>AI model and search providers used to answer user requests.</li>
          <li>
            Payment, subscription, analytics, diagnostics, error reporting, and support tools.
          </li>
        </ul>
      </div>
    ),
  },
  {
    title: 'Billing',
    content: (
      <ul className="ml-4 list-disc space-y-2">
        <li>Todus may offer free and paid plans depending on platform and availability.</li>
        <li>
          Payment details are processed by payment providers; Todus stores billing identifiers, plan
          status, invoices or receipts, and subscription events needed to operate the service.
        </li>
        <li>
          iOS paid plan changes are offered only when an App Store-compliant purchase flow is
          available for the iOS app.
        </li>
        <li>
          Refunds, cancellations, and subscription management may be subject to the payment
          provider, platform, and applicable law.
        </li>
      </ul>
    ),
  },
  {
    title: 'Retention and Deletion',
    content: (
      <div className="space-y-4">
        <p>
          We keep data for as long as needed to provide Todus, comply with legal obligations,
          resolve disputes, maintain security, and enforce agreements. Retention periods vary by
          data type.
        </p>
        <ul className="ml-4 list-disc space-y-2">
          <li>You can disconnect connected accounts to stop future syncing from that provider.</li>
          <li>You can delete many user-created items directly in the app.</li>
          <li>
            You can request or initiate account deletion from settings. Deletion removes or
            de-identifies account data unless retention is required for security, legal, billing, or
            compliance reasons.
          </li>
          <li>
            Backups and logs may persist for a limited time before automatic deletion according to
            operational retention schedules.
          </li>
        </ul>
      </div>
    ),
  },
  {
    title: 'Your Rights and Controls',
    content: (
      <ul className="ml-4 list-disc space-y-2">
        <li>Access, update, export, or delete account information where the app supports it.</li>
        <li>Disconnect Google or other providers at any time.</li>
        <li>
          Change device permissions such as Calendar, Reminders, Notifications, Microphone, Speech,
          Camera, and Photos in system settings.
        </li>
        <li>
          Contact us to request access, correction, deletion, portability, or restriction where
          required by applicable law.
        </li>
        <li>Lodge a complaint with your local data protection authority where applicable.</li>
      </ul>
    ),
  },
  {
    title: 'Security',
    content: (
      <ul className="ml-4 list-disc space-y-2">
        <li>We use HTTPS/TLS for data in transit.</li>
        <li>
          We use access controls and operational safeguards to limit access to production systems.
        </li>
        <li>
          No system is perfectly secure. Please contact us promptly if you believe your account or
          Todus data has been compromised.
        </li>
      </ul>
    ),
  },
  {
    title: 'Children',
    content: (
      <p>
        Todus is not intended for children under 13, and we do not knowingly collect personal data
        from children under 13. If you believe a child provided personal data to Todus, contact us
        so we can take appropriate action.
      </p>
    ),
  },
  {
    title: 'Contact',
    content: (
      <div className="space-y-3">
        <p>For privacy-related questions or concerns:</p>
        <div className="flex flex-col space-y-2">
          <a
            href="mailto:founders@todus.app"
            className="inline-flex items-center text-blue-600 hover:text-blue-800"
          >
            <MailIcon className="mr-2 h-4 w-4" />
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
  {
    title: 'Updates to This Policy',
    content: (
      <p>
        We may update this privacy policy from time to time. We will notify users of any material
        changes through our application or website.
      </p>
    ),
  },
];
