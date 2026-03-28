import { Navigation } from '@/components/navigation';
import { PixelatedBackground } from '@/components/home/pixelated-bg';
import Footer from '@/components/home/footer';
import type { MetaFunction } from 'react-router';
import { useParams, Link } from 'react-router';
import React from 'react';

/**
 * SEO Blog Post Page — "/blog/:slug"
 * Each post targets specific long-tail keyword clusters.
 * Content is rich, structured, and optimized for featured snippets.
 */

interface BlogPostData {
  slug: string;
  title: string;
  metaTitle: string;
  metaDescription: string;
  date: string;
  readTime: string;
  category: string;
  content: React.ReactNode;
}

/** Blog post content — add new posts here. Each has full SEO meta and structured content. */
const blogPosts: Record<string, BlogPostData> = {
  'best-ai-email-apps-2026': {
    slug: 'best-ai-email-apps-2026',
    title: 'The 7 Best AI Email Apps in 2026, Ranked',
    metaTitle: 'The 7 Best AI Email Apps in 2026, Ranked | Todus Blog',
    metaDescription:
      'Compare the best AI email apps of 2026: Todus, Superhuman, Shortwave, Spark, Canary Mail, and more. Detailed feature comparison, pricing, and recommendations.',
    date: '2026-03-28',
    readTime: '8 min read',
    category: 'Comparisons',
    content: (
      <article className="prose prose-invert prose-lg max-w-none">
        <p className="lead">
          AI email clients have gone from novelty to necessity. The average professional spends 28% of
          their workday on email — and the right AI tool can cut that in half. But with a dozen options
          on the market, which one actually delivers?
        </p>
        <p>
          We tested every major AI email app and ranked them based on AI depth, speed, features, pricing,
          and real-world productivity gains. Here's the definitive list for 2026.
        </p>

        <h2>1. Todus — Best Overall AI Email Client</h2>
        <p>
          <strong>Price:</strong> Free plan available | Premium from $9/mo
        </p>
        <p>
          <strong>Platforms:</strong> Web, iOS, macOS
        </p>
        <p>
          Todus is the only AI email client that combines email, calendar, and task management in a single
          app. Its AI doesn't just assist — it acts. It can triage your inbox, draft replies in your voice,
          summarize threads, and even create tasks from email conversations automatically.
        </p>
        <p>
          What sets Todus apart is the depth of AI integration. You can literally chat with your inbox — ask
          it "what did Alex say about the Q3 budget?" and get an instant answer with a link to the thread.
          The smart label system auto-categorizes emails without you lifting a finger.
        </p>
        <p>
          It's also fully open source, which means you can audit the code, contribute features, or self-host.
          Backed by Y Combinator, Todus has seen over 15,000 signups in its first 3 months.
        </p>
        <p>
          <strong>Best for:</strong> Founders, PMs, and anyone who wants AI to actually manage their inbox —
          not just highlight things.
        </p>

        <h2>2. Superhuman — Best for Speed</h2>
        <p>
          <strong>Price:</strong> $30/mo (no free plan)
        </p>
        <p>
          Superhuman is the gold standard for fast email. Keyboard-driven, minimal, and blazing quick. Their
          AI features (auto-drafts, summarization) are solid but not as deep as Todus. The biggest downside?
          No free plan, no calendar, no task management, and it's not open source.
        </p>
        <p>
          <strong>Best for:</strong> Power users who value speed above all and don't mind paying $30/month.
        </p>

        <h2>3. Shortwave — Best AI Search</h2>
        <p>
          <strong>Price:</strong> Free–$25/mo
        </p>
        <p>
          Shortwave's AI search is genuinely impressive — you can ask natural language questions about your
          email history. It also has good thread summarization. But it lacks calendar and task features,
          and there's no macOS native app.
        </p>
        <p>
          <strong>Best for:</strong> People who primarily need AI-powered search across their email archive.
        </p>

        <h2>4. Spark — Best for Teams on a Budget</h2>
        <p>
          <strong>Price:</strong> Free–$8/mo
        </p>
        <p>
          Spark has been around for years and has solid team collaboration features (shared inboxes, comments,
          assignments). The AI additions are decent but not market-leading. Good for teams, less compelling
          for individual AI power users.
        </p>
        <p>
          <strong>Best for:</strong> Teams that need shared inbox features at a low price point.
        </p>

        <h2>5. Canary Mail — Best Budget Option</h2>
        <p>
          <strong>Price:</strong> Free–$5/mo
        </p>
        <p>
          Canary gives you 80% of the AI features at 20% of the price. Thread summarization, smart
          categorization, and basic AI drafting. Privacy-focused with end-to-end encryption. Not as
          polished or deep as the top picks.
        </p>
        <p>
          <strong>Best for:</strong> Privacy-conscious users on a tight budget.
        </p>

        <h2>6. Motion — Best AI Calendar (But No Email)</h2>
        <p>
          <strong>Price:</strong> $19–34/mo
        </p>
        <p>
          Motion is excellent at AI-powered scheduling and task prioritization, but it doesn't handle
          email at all. If you need calendar and tasks but not email, Motion is great. For an all-in-one
          solution, look at Todus instead.
        </p>
        <p>
          <strong>Best for:</strong> People who need AI calendar management and don't need email.
        </p>

        <h2>7. Gmail — The Default (With AI Now Built In)</h2>
        <p>
          <strong>Price:</strong> Free
        </p>
        <p>
          Google has added "Help me write" and summary features to Gmail, but they're basic compared to
          dedicated AI email clients. If you're happy with Gmail's interface and just want light AI
          assistance, the built-in features may be enough.
        </p>
        <p>
          <strong>Best for:</strong> People who don't want to switch apps and just want basic AI help.
        </p>

        <h2>The Bottom Line</h2>
        <p>
          If you want the most capable AI email experience in 2026 — one that combines email, calendar,
          and tasks with deep AI that actually acts on your behalf — <Link to="/" className="text-blue-400 hover:text-blue-300">Todus</Link> is
          the clear winner. It's free to start, open source, and backed by Y Combinator.
        </p>
        <p>
          <Link to="/signup" className="text-blue-400 hover:text-blue-300">
            Try Todus free →
          </Link>
        </p>
      </article>
    ),
  },
  'ai-email-assistant-guide': {
    slug: 'ai-email-assistant-guide',
    title: 'The Complete Guide to AI Email Assistants: What They Do & How to Choose',
    metaTitle: 'AI Email Assistants: Complete Guide (2026) | Todus Blog',
    metaDescription:
      'What are AI email assistants? How do they work? This guide covers everything: features, use cases, how to choose, and the best options available in 2026.',
    date: '2026-03-25',
    readTime: '10 min read',
    category: 'Guides',
    content: (
      <article className="prose prose-invert prose-lg max-w-none">
        <p className="lead">
          AI email assistants are tools that use artificial intelligence to help you manage, organize,
          write, and respond to emails faster. They range from simple auto-complete features to full
          autonomous inbox managers.
        </p>

        <h2>What Can AI Email Assistants Do?</h2>
        <p>Modern AI email assistants offer these core capabilities:</p>
        <ul>
          <li><strong>Email Summarization</strong> — Get a 2-sentence summary of any thread instead of reading 30 messages</li>
          <li><strong>AI Drafting</strong> — Generate replies in your writing voice based on the thread context</li>
          <li><strong>Smart Triage</strong> — Automatically categorize and prioritize incoming emails</li>
          <li><strong>Inbox Chat</strong> — Ask questions about your email history in natural language</li>
          <li><strong>Auto-Labels</strong> — AI creates and applies labels based on content and intent</li>
          <li><strong>Task Extraction</strong> — Automatically create tasks from email action items</li>
          <li><strong>Follow-up Reminders</strong> — Get reminded when someone hasn't responded</li>
        </ul>

        <h2>How AI Email Assistants Work</h2>
        <p>
          Under the hood, AI email assistants use large language models (LLMs) like GPT-4 or Claude to
          understand the content and context of your emails. They analyze:
        </p>
        <ul>
          <li>The subject and body text of emails</li>
          <li>Thread history and conversation flow</li>
          <li>Your writing style and past responses</li>
          <li>Sender relationships and importance signals</li>
          <li>Temporal context (urgency, deadlines, scheduling)</li>
        </ul>

        <h2>How to Choose the Right AI Email Assistant</h2>
        <p>Consider these factors when picking an AI email client:</p>
        <ol>
          <li><strong>Depth of AI</strong> — Does it just assist, or does it act? The best tools take action autonomously.</li>
          <li><strong>Privacy & Security</strong> — How is your email data handled? Is the tool open source?</li>
          <li><strong>Integration Scope</strong> — Does it handle just email, or also calendar and tasks?</li>
          <li><strong>Platform Support</strong> — Web, iOS, Android, macOS, Windows?</li>
          <li><strong>Pricing</strong> — Is there a free plan? What do paid features include?</li>
        </ol>

        <h2>Our Recommendation</h2>
        <p>
          For the most complete AI email experience in 2026, we recommend <Link to="/" className="text-blue-400 hover:text-blue-300">Todus</Link>.
          It combines email, calendar, and task management with deep AI integration — and it's free to start.
        </p>
        <p>
          <Link to="/signup" className="text-blue-400 hover:text-blue-300">
            Try Todus free →
          </Link>
        </p>
      </article>
    ),
  },
  'why-ai-email-matters': {
    slug: 'why-ai-email-matters',
    title: 'Why AI Email Is the Future of Productivity',
    metaTitle: 'Why AI Email Is the Future of Productivity | Todus Blog',
    metaDescription:
      'The average professional spends 28% of their workday on email. AI email clients can cut that in half. Here\'s how the technology works and why it matters.',
    date: '2026-03-20',
    readTime: '6 min read',
    category: 'Insights',
    content: (
      <article className="prose prose-invert prose-lg max-w-none">
        <p className="lead">
          Email hasn't fundamentally changed since the 1990s. We send more of it every year, and we
          spend more time managing it. AI is about to change that — radically.
        </p>

        <h2>The Email Problem</h2>
        <p>
          According to McKinsey, the average professional spends 28% of their workday reading and
          responding to email. That's 2.6 hours per day, or 650+ hours per year. Most of that time
          is spent on low-value tasks: scanning, sorting, drafting routine replies, and context-switching.
        </p>

        <h2>How AI Changes the Equation</h2>
        <p>
          AI email clients don't just make email faster — they fundamentally change the relationship.
          Instead of you serving your inbox, your inbox serves you:
        </p>
        <ul>
          <li><strong>Read less:</strong> AI summarizes threads so you get the key points in seconds</li>
          <li><strong>Write faster:</strong> AI drafts replies in your voice based on context</li>
          <li><strong>Sort automatically:</strong> AI triages and categorizes without rules or filters</li>
          <li><strong>Never forget:</strong> AI extracts tasks, deadlines, and follow-ups automatically</li>
          <li><strong>Find anything:</strong> Natural language search across your entire email history</li>
        </ul>

        <h2>The All-in-One Shift</h2>
        <p>
          The most interesting trend in AI productivity is the convergence of email, calendar, and tasks
          into a single AI-powered workspace. Tools like <Link to="/" className="text-blue-400 hover:text-blue-300">Todus</Link> combine
          all three, so your AI assistant has full context across your entire work life — not just your inbox.
        </p>
        <p>
          When your AI knows about your calendar and tasks, it can do things like: suggest moving a meeting
          because you have a conflicting deadline, or auto-create a task when someone asks you to do something
          in an email, or draft a reply that references your availability.
        </p>

        <h2>What to Expect Next</h2>
        <p>
          By the end of 2026, we expect AI email assistants to handle 80% of routine email tasks without
          human intervention. The tools are already here — the adoption is just catching up.
        </p>
        <p>
          <Link to="/signup" className="text-blue-400 hover:text-blue-300">
            Try the future of email with Todus →
          </Link>
        </p>
      </article>
    ),
  },
};

/** SEO: Dynamic meta tags based on the blog post slug */
export const meta: MetaFunction = ({ params }) => {
  const post = blogPosts[params.slug as string];
  if (!post) {
    return [{ title: 'Post Not Found | Todus Blog' }];
  }
  return [
    { title: post.metaTitle },
    { name: 'description', content: post.metaDescription },
    { property: 'og:title', content: post.metaTitle },
    { property: 'og:description', content: post.metaDescription },
    { property: 'og:image', content: 'https://todus.app/og.png' },
    { property: 'og:url', content: `https://todus.app/blog/${post.slug}` },
    { property: 'og:type', content: 'article' },
    { name: 'twitter:card', content: 'summary_large_image' },
    { name: 'twitter:title', content: post.metaTitle },
    { name: 'twitter:description', content: post.metaDescription },
    { tagName: 'link', rel: 'canonical', href: `https://todus.app/blog/${post.slug}` },
  ];
};

export default function BlogPostPage() {
  const { slug } = useParams();
  const post = blogPosts[slug as string];

  if (!post) {
    return (
      <div className="flex min-h-screen flex-col bg-[#0F0F0F] text-white">
        <Navigation />
        <div className="flex flex-1 items-center justify-center">
          <div className="text-center">
            <h1 className="mb-4 text-4xl font-bold">Post not found</h1>
            <Link to="/blog" className="text-blue-400 hover:text-blue-300">
              Back to blog
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

      <div className="container relative z-10 mx-auto mt-12 max-w-3xl px-4 py-16 md:mt-24">
        {/* Post header */}
        <div className="mb-12">
          <Link
            to="/blog"
            className="mb-6 inline-block text-sm text-gray-500 hover:text-gray-300"
          >
            ← Back to blog
          </Link>
          <div className="mb-4 flex items-center gap-3 text-sm text-gray-500">
            <span className="rounded-full bg-[#1a1a1a] px-3 py-1 text-xs font-medium text-blue-400">
              {post.category}
            </span>
            <span>{post.date}</span>
            <span>·</span>
            <span>{post.readTime}</span>
          </div>
          <h1 className="text-3xl font-medium leading-tight text-white md:text-4xl lg:text-5xl">
            {post.title}
          </h1>
        </div>

        {/* Post content */}
        {post.content}

        {/* Bottom CTA */}
        <div className="mt-16 rounded-xl border border-[#222] bg-[#141414] p-8 text-center">
          <h3 className="mb-2 text-xl font-medium text-white">
            Ready to try AI email?
          </h3>
          <p className="mb-6 text-gray-400">
            Start free with Todus — AI-powered email, calendar, and tasks in one app.
          </p>
          <Link to="/signup">
            <button className="rounded-lg bg-white px-6 py-3 font-medium text-black hover:bg-gray-200">
              Get Started for Free
            </button>
          </Link>
        </div>
      </div>

      <div className="mt-auto">
        <Footer />
      </div>
    </main>
  );
}
