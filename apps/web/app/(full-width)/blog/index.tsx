import { Navigation } from '@/components/navigation';
import { PixelatedBackground } from '@/components/home/pixelated-bg';
import Footer from '@/components/home/footer';
import type { MetaFunction } from 'react-router';
import { Link } from 'react-router';

/**
 * SEO Blog Index — "/blog"
 * Content hub for organic search traffic.
 * Each post targets specific keyword clusters identified in the SEO audit.
 */

/** SEO: Meta tags for the blog index page */
export const meta: MetaFunction = () => {
  return [
    { title: 'Todus Blog — AI Email Tips, Productivity Guides & Updates' },
    {
      name: 'description',
      content:
        'Tips, guides, and insights on AI email management, productivity, and how to get more done with less inbox time. From the team at Todus.',
    },
    { property: 'og:title', content: 'Todus Blog — AI Email Tips, Productivity Guides & Updates' },
    {
      property: 'og:description',
      content:
        'Tips, guides, and insights on AI email management, productivity, and how to get more done with less inbox time.',
    },
    { tagName: 'link', rel: 'canonical', href: 'https://todus.app/blog' },
  ];
};

interface BlogPost {
  slug: string;
  title: string;
  excerpt: string;
  date: string;
  readTime: string;
  category: string;
}

/**
 * Blog posts — add new posts here to have them automatically listed.
 * Posts are sorted by date (newest first) and linked to /blog/:slug.
 */
const posts: BlogPost[] = [
  {
    slug: 'best-ai-email-apps-2026',
    title: 'The 7 Best AI Email Apps in 2026, Ranked',
    excerpt:
      'We compared every AI email client on the market — from Superhuman to Shortwave to Spark. Here\'s which ones actually save you time, and which are just hype.',
    date: '2026-03-28',
    readTime: '8 min read',
    category: 'Comparisons',
  },
  {
    slug: 'ai-email-assistant-guide',
    title: 'The Complete Guide to AI Email Assistants: What They Do & How to Choose',
    excerpt:
      'AI email assistants can draft replies, summarize threads, triage your inbox, and more. Here\'s exactly what to look for and how to pick the right one for your workflow.',
    date: '2026-03-25',
    readTime: '10 min read',
    category: 'Guides',
  },
  {
    slug: 'why-ai-email-matters',
    title: 'Why AI Email Is the Future of Productivity',
    excerpt:
      'The average professional spends 28% of their workday on email. AI email clients can cut that in half. Here\'s how the technology works and why it matters.',
    date: '2026-03-20',
    readTime: '6 min read',
    category: 'Insights',
  },
];

export default function BlogIndex() {
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

      <div className="container relative z-10 mx-auto mt-12 max-w-4xl px-4 py-16 md:mt-24">
        <div className="mb-12 text-center">
          <h1 className="mb-4 text-4xl font-medium text-white md:text-5xl">Blog</h1>
          <p className="text-lg text-[#B8B8B9]">
            AI email tips, productivity insights, and product updates from the Todus team.
          </p>
        </div>

        <div className="grid gap-8">
          {posts.map((post) => (
            <Link
              key={post.slug}
              to={`/blog/${post.slug}`}
              className="group rounded-xl border border-[#222] bg-[#141414] p-8 transition-colors hover:border-[#444]"
            >
              <div className="mb-3 flex items-center gap-3 text-sm text-gray-500">
                <span className="rounded-full bg-[#1a1a1a] px-3 py-1 text-xs font-medium text-blue-400">
                  {post.category}
                </span>
                <span>{post.date}</span>
                <span>·</span>
                <span>{post.readTime}</span>
              </div>
              <h2 className="mb-2 text-xl font-medium text-white transition-colors group-hover:text-blue-400">
                {post.title}
              </h2>
              <p className="text-sm leading-relaxed text-gray-400">{post.excerpt}</p>
            </Link>
          ))}
        </div>
      </div>

      <div className="mt-auto">
        <Footer />
      </div>
    </main>
  );
}
