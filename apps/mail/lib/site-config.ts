import { APP_NAME } from '@/lib/branding';

/**
 * Central SEO configuration for the Todus web app.
 * All meta tags, Open Graph, Twitter Cards, and structured data are driven from here.
 * Update this file when changing branding, descriptions, or keyword targets.
 */

const TITLE = 'Todus — AI Email, Calendar & Tasks in One App';
const DESCRIPTION =
  'Todus is the AI-native email client that manages your inbox, calendar, and tasks so you don\'t have to. Summarize emails, auto-triage, draft replies, and get more done — backed by Y Combinator.';

const APP_URL = import.meta.env.VITE_PUBLIC_APP_URL || 'https://todus.app';

export const siteConfig = {
  title: TITLE,
  description: DESCRIPTION,
  icons: {
    icon: '/favicon.ico',
  },
  applicationName: APP_NAME,
  creator: '@nizzyabi @bruvimtired @ripgrim @needleXO @dakdevs @mrgsub',

  /** Open Graph tags for social sharing (Facebook, LinkedIn, etc.) */
  openGraph: {
    title: TITLE,
    description: DESCRIPTION,
    siteName: APP_NAME,
    images: [
      {
        url: `${APP_URL}/og.png`,
        width: 1200,
        height: 630,
        alt: 'Todus — AI Email, Calendar & Tasks',
      },
    ],
  },

  /** Twitter/X Card tags */
  twitter: {
    card: 'summary_large_image' as const,
    title: TITLE,
    description: DESCRIPTION,
    image: `${APP_URL}/og.png`,
    // site: '@todus_app', // Uncomment when Twitter/X account is set up
  },

  category: 'Email Client',

  alternates: {
    canonical: APP_URL,
  },

  /**
   * SEO keywords — targeted for AI email, calendar, and task management.
   * These are rendered as a <meta name="keywords"> tag and inform content strategy.
   */
  keywords: [
    // Primary — brand
    'Todus',
    'Todus app',
    'Todus email',
    // Primary — product category
    'AI email client',
    'AI email assistant',
    'AI email app',
    'AI inbox management',
    // Primary — multi-product value prop
    'AI calendar app',
    'AI task management',
    'AI email calendar tasks',
    'AI productivity app',
    // Secondary — competitor alternatives
    'Superhuman alternative',
    'Shortwave alternative',
    'Spark email alternative',
    'Motion app alternative',
    'Gmail alternative',
    // Secondary — features
    'email summarization',
    'AI email drafting',
    'smart email triage',
    'email AI assistant',
    // Tertiary — open source differentiator
    'open source email client',
    'open source AI email',
    // Tertiary — platform
    'email app for Mac',
    'email app for iPhone',
    'email web app',
  ],

  /**
   * JSON-LD structured data for rich search results.
   * Rendered as a <script type="application/ld+json"> in root.tsx.
   */
  structuredData: {
    organization: {
      '@context': 'https://schema.org',
      '@type': 'Organization',
      name: 'Todus',
      url: APP_URL,
      logo: `${APP_URL}/brand-logo.png`,
      description: DESCRIPTION,
      foundingDate: '2024',
      sameAs: [
        'https://github.com/todus-app',
        // 'https://twitter.com/todus_app', // Uncomment when live
        // 'https://linkedin.com/company/todus', // Uncomment when live
      ],
    },
    softwareApplication: {
      '@context': 'https://schema.org',
      '@type': 'SoftwareApplication',
      name: 'Todus',
      description: DESCRIPTION,
      url: APP_URL,
      applicationCategory: 'BusinessApplication',
      operatingSystem: 'Web, iOS, macOS',
      offers: {
        '@type': 'Offer',
        price: '0',
        priceCurrency: 'USD',
        description: 'Free plan available',
      },
    },
    faqPage: {
      '@context': 'https://schema.org',
      '@type': 'FAQPage',
      mainEntity: [
        {
          '@type': 'Question',
          name: 'What is Todus?',
          acceptedAnswer: {
            '@type': 'Answer',
            text: 'Todus is an AI-native email client that manages your inbox, calendar, and tasks. It uses AI to summarize emails, auto-triage your inbox, draft replies, and help you get more done — all in one app.',
          },
        },
        {
          '@type': 'Question',
          name: 'Is Todus free?',
          acceptedAnswer: {
            '@type': 'Answer',
            text: 'Yes, Todus offers a free plan with core features. Premium plans with advanced AI capabilities and team features are also available.',
          },
        },
        {
          '@type': 'Question',
          name: 'How is Todus different from Superhuman or Spark?',
          acceptedAnswer: {
            '@type': 'Answer',
            text: 'Todus combines email, calendar, and task management with deep AI integration in one app. Unlike Superhuman, Todus is open source and offers a free plan. Unlike Spark, Todus provides native AI that acts on your behalf — not just assists.',
          },
        },
        {
          '@type': 'Question',
          name: 'Is Todus open source?',
          acceptedAnswer: {
            '@type': 'Answer',
            text: 'Yes, Todus is fully open source. You can review the code, contribute features, or even self-host your own instance. This ensures transparency and trust with your email data.',
          },
        },
        {
          '@type': 'Question',
          name: 'What platforms does Todus support?',
          acceptedAnswer: {
            '@type': 'Answer',
            text: 'Todus is available on the web, iOS (iPhone), and macOS. You can access your AI-powered inbox from any device.',
          },
        },
        {
          '@type': 'Question',
          name: 'Does Todus work with Gmail and Outlook?',
          acceptedAnswer: {
            '@type': 'Answer',
            text: 'Yes, Todus connects to your existing Gmail and Google Workspace accounts. Outlook and Microsoft 365 support is in development.',
          },
        },
      ],
    },
  },
};
