import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from '@/components/ui/accordion';
import { ArrowLeft } from 'lucide-react';
import { Navigation } from '@/components/navigation';
import { Button } from '@/components/ui/button';
import Footer from '@/components/home/footer';
import type { MetaFunction } from 'react-router';

const ArrowLeftIcon = ArrowLeft as any;

const FAQS: { q: string; a: string }[] = [
  {
    q: 'What is Todus?',
    a: 'Todus is an AI-native email client that manages your inbox, calendar, and tasks. It uses AI to summarize emails, auto-triage your inbox, draft replies, and help you get more done — all in one app.',
  },
  {
    q: 'Is Todus free?',
    a: 'Yes, Todus offers a free plan with core features. Premium plans with advanced AI capabilities and team features are also available.',
  },
  {
    q: 'How is Todus different from Superhuman or Spark?',
    a: 'Todus combines email, calendar, and task management with deep AI integration in one app. Unlike Superhuman, Todus is open source and offers a free plan. Unlike Spark, Todus provides native AI that acts on your behalf — not just assists.',
  },
  {
    q: 'Is Todus open source?',
    a: 'Yes, Todus is fully open source. You can review the code, contribute features, or even self-host your own instance. This ensures transparency and trust with your email data.',
  },
  {
    q: 'What platforms does Todus support?',
    a: 'Todus is available on the web, iOS (iPhone), and macOS. You can access your AI-powered inbox from any device.',
  },
  {
    q: 'Does Todus work with Gmail and Outlook?',
    a: 'Yes, Todus connects to your existing Gmail and Google Workspace accounts. Outlook and Microsoft 365 support is in development.',
  },
  {
    q: 'Can I self-host Todus?',
    a: 'Yes. Todus is fully open source and includes a SELF_HOSTING.md guide at the repo root with the full setup, env, and database instructions. You can run your own instance on Cloudflare Workers.',
  },
  {
    q: 'Does Todus support custom email domains?',
    a: 'Yes. You connect your existing Google Workspace or Gmail account, so any custom domain you have already set up with Google works without further config. Native custom-domain support outside Google Workspace is on the roadmap.',
  },
  {
    q: 'When is Outlook support shipping?',
    a: 'Outlook and Microsoft 365 connectors are in active development. Track progress on the GitHub repo at github.com/Ludvig-Hedin/Todus.',
  },
  {
    q: 'How does Todus handle my data?',
    a: "Your email data syncs into your own Cloudflare Durable Object and R2 bucket scoped to your account. Todus does not sell or train on your email. See the privacy page for the full policy.",
  },
];

export const meta: MetaFunction = () => {
  return [
    { title: 'Frequently Asked Questions — Todus' },
    {
      name: 'description',
      content:
        'Answers to common questions about Todus — the AI-native email client with calendar, tasks, meetings, and docs built in.',
    },
    { property: 'og:title', content: 'Frequently Asked Questions — Todus' },
    {
      property: 'og:description',
      content:
        'Answers to common questions about Todus — the AI-native email client with calendar, tasks, meetings, and docs built in.',
    },
    { tagName: 'link', rel: 'canonical', href: 'https://todus.app/faq' },
  ];
};

export default function FAQPage() {
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

        <section className="mx-auto w-full max-w-3xl px-4 pt-32 pb-12 text-center">
          <h1 className="text-4xl font-semibold tracking-tight text-gray-900 md:text-6xl dark:text-white">
            Frequently asked
          </h1>
          <p className="mx-auto mt-5 max-w-xl text-base text-gray-600 md:text-lg dark:text-white/60">
            Answers to the questions we hear most about Todus.
          </p>
        </section>

        <section className="mx-auto w-full max-w-3xl px-4 pb-24">
          <Accordion type="single" collapsible className="w-full">
            {FAQS.map((item, i) => (
              <AccordionItem
                key={item.q}
                value={`item-${i}`}
                className="border-b border-gray-200 last:border-b-0 dark:border-white/10"
              >
                <AccordionTrigger className="text-left text-base font-medium text-gray-900 hover:no-underline dark:text-white">
                  {item.q}
                </AccordionTrigger>
                <AccordionContent className="text-gray-600 dark:text-white/70">
                  {item.a}
                </AccordionContent>
              </AccordionItem>
            ))}
          </Accordion>
        </section>

        <Footer />
      </div>
    </div>
  );
}
