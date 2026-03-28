import type { Config } from '@react-router/dev/config';

/**
 * React Router v7 configuration.
 *
 * SEO CRITICAL: `prerender` generates static HTML at build time for public marketing pages.
 * This ensures Google sees real content (not an empty JS shell) without enabling full SSR
 * which would require significant refactoring of the app's auth and data loading patterns.
 *
 * The app still uses `ssr: false` (client-side rendering) for authenticated routes (/mail, /settings).
 * Public pages listed in `prerender` get static HTML output that includes all meta tags,
 * structured data, and visible text content — exactly what search engines need.
 */
export default {
  ssr: false,
  buildDirectory: 'build',
  appDirectory: 'app',
  routeDiscovery: {
    mode: 'initial',
  },
  prerender: [
    '/manifest.webmanifest',
    // SEO: Pre-render all public marketing pages so Google sees real HTML content
    '/',
    '/home',
    '/about',
    '/pricing',
    '/terms',
    '/privacy',
    '/contributors',
    // SEO: Pre-render competitor comparison pages for high-intent search traffic
    '/compare/superhuman',
    '/compare/shortwave',
    '/compare/spark',
    '/compare/motion',
    // SEO: Pre-render blog pages for organic content marketing traffic
    '/blog',
    '/blog/best-ai-email-apps-2026',
    '/blog/ai-email-assistant-guide',
    '/blog/why-ai-email-matters',
  ],
  future: {
    unstable_viteEnvironmentApi: true,
  },
} satisfies Config;
