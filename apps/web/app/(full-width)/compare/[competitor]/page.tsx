import { Navigation } from '@/components/navigation';
import { Button } from '@/components/ui/button';
import Footer from '@/components/home/footer';
import type { MetaFunction } from 'react-router';
import { useParams, Link } from 'react-router';
import { PixelatedBackground } from '@/components/home/pixelated-bg';
import { Check, X, Minus } from 'lucide-react';

/**
 * SEO Comparison Page — "/compare/:competitor"
 * These pages target high-intent "[competitor] alternative" search queries.
 * Each comparison is data-driven from the `competitors` config below.
 */

// Type casts for Lucide icons to resolve TS2786
const CheckIcon = Check as any;
const XIcon = X as any;
const MinusIcon = Minus as any;

/** Feature comparison status */
type FeatureStatus = 'yes' | 'no' | 'partial' | 'paid';

interface CompetitorData {
  name: string;
  slug: string;
  tagline: string;
  description: string;
  priceLabel: string;
  todusAdvantages: string[];
  features: {
    name: string;
    todus: FeatureStatus;
    competitor: FeatureStatus;
  }[];
  /** SEO-specific fields */
  metaTitle: string;
  metaDescription: string;
}

/**
 * SEO comparison data for each competitor.
 * Add new competitors here to auto-generate comparison pages.
 */
const competitors: Record<string, CompetitorData> = {
  superhuman: {
    name: 'Superhuman',
    slug: 'superhuman',
    tagline: 'Looking for a Superhuman alternative?',
    description:
      'Superhuman charges $30/month for a fast email client. Todus gives you the same speed, plus AI that actually manages your inbox, calendar, and tasks — with a free plan.',
    priceLabel: '$30/mo',
    todusAdvantages: [
      'Free plan available — Superhuman is $30/month with no free tier',
      'AI that acts on your behalf, not just assists',
      'Built-in calendar and task management',
      'Open source — fully transparent and auditable',
      'Available on Web, iOS, and macOS',
    ],
    features: [
      { name: 'AI Email Drafting', todus: 'yes', competitor: 'yes' },
      { name: 'AI Email Summarization', todus: 'yes', competitor: 'yes' },
      { name: 'Smart Inbox Triage', todus: 'yes', competitor: 'partial' },
      { name: 'Calendar Integration', todus: 'yes', competitor: 'partial' },
      { name: 'Task Management', todus: 'yes', competitor: 'no' },
      { name: 'AI Chat with Inbox', todus: 'yes', competitor: 'no' },
      { name: 'Keyboard Shortcuts', todus: 'yes', competitor: 'yes' },
      { name: 'Smart Labels & Categories', todus: 'yes', competitor: 'partial' },
      { name: 'Free Plan', todus: 'yes', competitor: 'no' },
      { name: 'Open Source', todus: 'yes', competitor: 'no' },
      { name: 'Self-Hostable', todus: 'yes', competitor: 'no' },
      { name: 'iOS App', todus: 'yes', competitor: 'yes' },
      { name: 'macOS App', todus: 'yes', competitor: 'yes' },
      { name: 'Web App', todus: 'yes', competitor: 'no' },
    ],
    metaTitle: 'Todus vs Superhuman — Free AI Email Alternative (2026)',
    metaDescription:
      'Compare Todus and Superhuman side by side. Todus offers AI email management, calendar, and tasks for free — plus it\'s open source. See the full feature comparison.',
  },
  shortwave: {
    name: 'Shortwave',
    slug: 'shortwave',
    tagline: 'Looking for a Shortwave alternative?',
    description:
      'Shortwave is a solid AI email client, but it\'s email-only. Todus combines AI email with calendar and task management in one app — so you stop juggling tools.',
    priceLabel: '$7-25/mo',
    todusAdvantages: [
      'All-in-one: email, calendar, and tasks in a single app',
      'AI acts on your behalf — not just summarizes',
      'Open source and transparent',
      'Native iOS and macOS apps',
      'More comprehensive free plan',
    ],
    features: [
      { name: 'AI Email Drafting', todus: 'yes', competitor: 'yes' },
      { name: 'AI Email Summarization', todus: 'yes', competitor: 'yes' },
      { name: 'Smart Inbox Triage', todus: 'yes', competitor: 'yes' },
      { name: 'Calendar Integration', todus: 'yes', competitor: 'no' },
      { name: 'Task Management', todus: 'yes', competitor: 'no' },
      { name: 'AI Chat with Inbox', todus: 'yes', competitor: 'yes' },
      { name: 'Smart Labels & Categories', todus: 'yes', competitor: 'partial' },
      { name: 'Free Plan', todus: 'yes', competitor: 'partial' },
      { name: 'Open Source', todus: 'yes', competitor: 'no' },
      { name: 'Self-Hostable', todus: 'yes', competitor: 'no' },
      { name: 'iOS App', todus: 'yes', competitor: 'yes' },
      { name: 'macOS App', todus: 'yes', competitor: 'no' },
      { name: 'Web App', todus: 'yes', competitor: 'yes' },
    ],
    metaTitle: 'Todus vs Shortwave — AI Email + Calendar + Tasks (2026)',
    metaDescription:
      'Shortwave does email well, but Todus does email, calendar, and tasks with AI — all in one app. Open source, free plan, iOS & macOS native. See the comparison.',
  },
  spark: {
    name: 'Spark',
    slug: 'spark',
    tagline: 'Looking for a Spark alternative?',
    description:
      'Spark is a popular email client with team features. Todus goes further with AI that manages your entire workflow — email, calendar, and tasks — not just organizes your inbox.',
    priceLabel: '$0-8/mo',
    todusAdvantages: [
      'Deeper AI integration — AI acts on your behalf',
      'Built-in task management, not just email',
      'Calendar management included',
      'Open source — review every line of code',
      'Backed by Y Combinator',
    ],
    features: [
      { name: 'AI Email Drafting', todus: 'yes', competitor: 'yes' },
      { name: 'AI Email Summarization', todus: 'yes', competitor: 'yes' },
      { name: 'Smart Inbox Triage', todus: 'yes', competitor: 'yes' },
      { name: 'Calendar Integration', todus: 'yes', competitor: 'partial' },
      { name: 'Task Management', todus: 'yes', competitor: 'no' },
      { name: 'AI Chat with Inbox', todus: 'yes', competitor: 'no' },
      { name: 'Team Collaboration', todus: 'partial', competitor: 'yes' },
      { name: 'Smart Labels & Categories', todus: 'yes', competitor: 'yes' },
      { name: 'Free Plan', todus: 'yes', competitor: 'yes' },
      { name: 'Open Source', todus: 'yes', competitor: 'no' },
      { name: 'Self-Hostable', todus: 'yes', competitor: 'no' },
      { name: 'iOS App', todus: 'yes', competitor: 'yes' },
      { name: 'macOS App', todus: 'yes', competitor: 'yes' },
      { name: 'Web App', todus: 'yes', competitor: 'yes' },
    ],
    metaTitle: 'Todus vs Spark — AI Email Client with Calendar & Tasks (2026)',
    metaDescription:
      'Compare Todus and Spark email. Todus offers deeper AI, built-in calendar and tasks, and is fully open source. See the full feature comparison.',
  },
  motion: {
    name: 'Motion',
    slug: 'motion',
    tagline: 'Looking for a Motion alternative?',
    description:
      'Motion is a great AI calendar and task tool, but it doesn\'t do email. Todus brings AI to email, calendar, AND tasks in one unified app — so your entire workflow lives in one place.',
    priceLabel: '$19-34/mo',
    todusAdvantages: [
      'Full AI email management — Motion has no email',
      'All-in-one: email + calendar + tasks',
      'Free plan available — Motion starts at $19/month',
      'Open source and self-hostable',
      'AI chat with your inbox',
    ],
    features: [
      { name: 'AI Email Management', todus: 'yes', competitor: 'no' },
      { name: 'AI Email Drafting', todus: 'yes', competitor: 'no' },
      { name: 'AI Calendar Scheduling', todus: 'yes', competitor: 'yes' },
      { name: 'Task Management', todus: 'yes', competitor: 'yes' },
      { name: 'AI Task Prioritization', todus: 'yes', competitor: 'yes' },
      { name: 'AI Chat with Inbox', todus: 'yes', competitor: 'no' },
      { name: 'Smart Labels & Categories', todus: 'yes', competitor: 'no' },
      { name: 'Free Plan', todus: 'yes', competitor: 'no' },
      { name: 'Open Source', todus: 'yes', competitor: 'no' },
      { name: 'Self-Hostable', todus: 'yes', competitor: 'no' },
      { name: 'iOS App', todus: 'yes', competitor: 'yes' },
      { name: 'macOS App', todus: 'yes', competitor: 'yes' },
      { name: 'Web App', todus: 'yes', competitor: 'yes' },
    ],
    metaTitle: 'Todus vs Motion — AI Email, Calendar & Tasks in One App (2026)',
    metaDescription:
      'Motion does calendar and tasks but not email. Todus brings AI to email, calendar, AND tasks in one app. Free plan, open source. See the full comparison.',
  },
};

/** SEO: Dynamic meta tags based on the competitor slug */
export const meta: MetaFunction = ({ params }) => {
  const competitor = competitors[params.competitor as string];
  if (!competitor) {
    return [{ title: 'Todus — Compare AI Email Clients' }];
  }
  return [
    { title: competitor.metaTitle },
    { name: 'description', content: competitor.metaDescription },
    { property: 'og:title', content: competitor.metaTitle },
    { property: 'og:description', content: competitor.metaDescription },
    { property: 'og:image', content: 'https://todus.app/og.png' },
    { property: 'og:url', content: `https://todus.app/compare/${competitor.slug}` },
    { name: 'twitter:card', content: 'summary_large_image' },
    { name: 'twitter:title', content: competitor.metaTitle },
    { name: 'twitter:description', content: competitor.metaDescription },
    { tagName: 'link', rel: 'canonical', href: `https://todus.app/compare/${competitor.slug}` },
  ];
};

/** Renders a feature status icon — exhaustive switch with compile-time safety */
function StatusIcon({ status }: { status: FeatureStatus }) {
  switch (status) {
    case 'yes':
      return <CheckIcon className="h-5 w-5 text-emerald-400" />;
    case 'no':
      return <XIcon className="h-5 w-5 text-red-400" />;
    case 'partial':
      return <MinusIcon className="h-5 w-5 text-yellow-400" />;
    case 'paid':
      return <span className="text-xs text-yellow-400">Paid</span>;
    default: {
      // Exhaustiveness check — if FeatureStatus is extended, TypeScript will error here
      const _exhaustive: never = status;
      return <MinusIcon className="h-5 w-5 text-gray-500" />;
    }
  }
}

export default function ComparisonPage() {
  const { competitor: slug } = useParams();
  const competitor = competitors[slug as string];

  if (!competitor) {
    return (
      <div className="flex min-h-screen flex-col bg-[#0F0F0F] text-white">
        <Navigation />
        <div className="flex flex-1 items-center justify-center">
          <div className="text-center">
            <h1 className="mb-4 text-4xl font-bold">Comparison not found</h1>
            <Link to="/" className="text-blue-400 hover:text-blue-300">
              Go back home
            </Link>
          </div>
        </div>
        <Footer />
      </div>
    );
  }

  return (
    <main className="relative flex min-h-screen flex-1 flex-col overflow-x-hidden bg-[#0F0F0F]">
      <PixelatedBackground
        className="z-1 absolute left-1/2 top-[-40px] h-auto w-screen min-w-[1920px] -translate-x-1/2 object-cover"
        style={{
          mixBlendMode: 'screen',
          maskImage: 'linear-gradient(to bottom, black, transparent)',
        }}
      />
      <Navigation />

      {/* Hero Section */}
      <div className="container relative z-10 mx-auto mt-12 max-w-4xl px-4 py-16 md:mt-24">
        <div className="mb-12 text-center">
          <p className="mb-4 text-sm font-medium uppercase tracking-widest text-blue-400">
            Comparison
          </p>
          <h1 className="mb-4 text-4xl font-medium leading-tight text-white md:text-5xl lg:text-6xl">
            Todus vs {competitor.name}
          </h1>
          <p className="mx-auto max-w-2xl text-lg text-[#B8B8B9]">{competitor.description}</p>
        </div>

        {/* CTA */}
        <div className="mb-16 flex justify-center gap-4">
          <Link to="/signup">
            <Button className="bg-white px-8 py-3 text-black hover:bg-gray-200">
              Try Todus Free
            </Button>
          </Link>
          <Link to="/pricing">
            <Button variant="outline" className="border-[#333] px-8 py-3 text-white hover:bg-[#1a1a1a]">
              See Pricing
            </Button>
          </Link>
        </div>

        {/* Why Todus wins */}
        <section className="mb-16">
          <h2 className="mb-8 text-center text-2xl font-medium text-white">
            Why teams switch from {competitor.name} to Todus
          </h2>
          <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
            {competitor.todusAdvantages.map((advantage, i) => (
              <div
                key={i}
                className="rounded-xl border border-[#222] bg-[#141414] p-6"
              >
                <CheckIcon className="mb-3 h-5 w-5 text-emerald-400" />
                <p className="text-sm text-gray-300">{advantage}</p>
              </div>
            ))}
          </div>
        </section>

        {/* Feature comparison table */}
        <section className="mb-16">
          <h2 className="mb-8 text-center text-2xl font-medium text-white">
            Feature-by-Feature Comparison
          </h2>
          <div className="overflow-hidden rounded-xl border border-[#222]">
            {/* Table header */}
            <div className="grid grid-cols-3 border-b border-[#222] bg-[#141414] px-6 py-4 text-sm font-medium">
              <div className="text-gray-400">Feature</div>
              <div className="text-center text-white">Todus</div>
              <div className="text-center text-gray-400">
                {competitor.name} ({competitor.priceLabel})
              </div>
            </div>
            {/* Table rows */}
            {competitor.features.map((feature, i) => (
              <div
                key={feature.name}
                className={`grid grid-cols-3 px-6 py-3 text-sm ${
                  i % 2 === 0 ? 'bg-[#0F0F0F]' : 'bg-[#141414]'
                }`}
              >
                <div className="text-gray-300">{feature.name}</div>
                <div className="flex justify-center">
                  <StatusIcon status={feature.todus} />
                </div>
                <div className="flex justify-center">
                  <StatusIcon status={feature.competitor} />
                </div>
              </div>
            ))}
          </div>
        </section>

        {/* Bottom CTA */}
        <section className="mb-16 text-center">
          <h2 className="mb-4 text-3xl font-medium text-white">
            Ready to switch from {competitor.name}?
          </h2>
          <p className="mb-8 text-[#B8B8B9]">
            Start for free. No credit card required. Import your Gmail in 30 seconds.
          </p>
          <Link to="/signup">
            <Button className="bg-white px-8 py-3 text-black hover:bg-gray-200">
              Get Started for Free
            </Button>
          </Link>
        </section>

        {/* Other comparisons — internal linking for SEO */}
        <section className="mb-16">
          <h2 className="mb-6 text-center text-xl font-medium text-gray-400">
            Other comparisons
          </h2>
          <div className="flex flex-wrap justify-center gap-3">
            {Object.values(competitors)
              .filter((c) => c.slug !== slug)
              .map((c) => (
                <Link
                  key={c.slug}
                  to={`/compare/${c.slug}`}
                  className="rounded-full border border-[#333] px-4 py-2 text-sm text-gray-400 transition-colors hover:border-white hover:text-white"
                >
                  Todus vs {c.name}
                </Link>
              ))}
          </div>
        </section>
      </div>

      <div className="mt-auto">
        <Footer />
      </div>
    </main>
  );
}
