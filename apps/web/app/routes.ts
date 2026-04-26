import { type RouteConfig, index, layout, prefix, route } from '@react-router/dev/routes';

export default [
  index('page.tsx'),
  route('/home', 'home/page.tsx'),

  route('/api/mailto-handler', 'mailto-handler.ts'),

  layout('(full-width)/layout.tsx', [
    route('/about', '(full-width)/about.tsx'),
    route('/terms', '(full-width)/terms.tsx'),
    route('/pricing', '(full-width)/pricing.tsx'),
    route('/privacy', '(full-width)/privacy.tsx'),
    route('/contributors', '(full-width)/contributors.tsx'),
    route('/hr', '(full-width)/hr.tsx'),
    // SEO: Competitor comparison pages — targets "[competitor] alternative" search queries
    route('/compare/:competitor', '(full-width)/compare/[competitor]/page.tsx'),
    // SEO: Blog pages — content hub for organic search traffic
    route('/blog', '(full-width)/blog/index.tsx'),
    route('/blog/:slug', '(full-width)/blog/[slug]/page.tsx'),
    // Shared AI conversation permalink — public read-only snapshot
    route('/share/:slug', '(full-width)/share/[slug]/page.tsx'),
    // Group chat invite landing page — join via invite token
    route('/g/:token', '(full-width)/group-join/[token]/page.tsx'),
  ]),

  route('/login', '(auth)/todus/login/page.tsx'),
  route('/signup', '(auth)/todus/signup/page.tsx'),

  layout('(routes)/layout.tsx', [
    route('/developer', '(routes)/developer/page.tsx'),
    layout(
      '(routes)/mail/layout.tsx',
      prefix('/mail', [
        index('(routes)/mail/page.tsx'),
        route('/home', '(routes)/mail/home/page.tsx'),
        route('/tasks', '(routes)/mail/tasks/page.tsx'),
        route('/calendar', '(routes)/mail/calendar/page.tsx'),
        route('/search', '(routes)/mail/search/page.tsx'),
        route('/chat', '(routes)/mail/chat/page.tsx'),
        route('/create', '(routes)/mail/create/page.tsx'),
        route('/compose', '(routes)/mail/compose/page.tsx'),
        route('/under-construction/:path', '(routes)/mail/under-construction/[path]/page.tsx'),
        route('/meetings', '(routes)/mail/meetings/page.tsx'),
        route('/meetings/:meetingId', '(routes)/mail/meetings/[meetingId]/page.tsx'),
        route('/docs', '(routes)/mail/docs/page.tsx'),
        route('/docs/:docId', '(routes)/mail/docs/[docId]/page.tsx'),
        route('/:folder', '(routes)/mail/[folder]/page.tsx'),
      ]),
    ),
    layout(
      '(routes)/settings/layout.tsx',
      prefix('/settings', [
        index('(routes)/settings/page.tsx'),
        route('/appearance', '(routes)/settings/appearance/page.tsx'),
        route('/connections', '(routes)/settings/connections/page.tsx'),
        route('/danger-zone', '(routes)/settings/danger-zone/page.tsx'),
        route('/general', '(routes)/settings/general/page.tsx'),
        route('/labels', '(routes)/settings/labels/page.tsx'),
        route('/categories', '(routes)/settings/categories/page.tsx'),
        route('/signatures', '(routes)/settings/signatures/page.tsx'),
        route('/notifications', '(routes)/settings/notifications/page.tsx'),
        route('/privacy', '(routes)/settings/privacy/page.tsx'),
        route('/security', '(routes)/settings/security/page.tsx'),
        route('/shortcuts', '(routes)/settings/shortcuts/page.tsx'),
        route('/sharing', '(routes)/settings/sharing/page.tsx'),
        route('/meetings', '(routes)/settings/meetings/page.tsx'),
        route('/ai', '(routes)/settings/ai/page.tsx'),
        route('/billing', '(routes)/settings/billing/page.tsx'),
        route('/*', '(routes)/settings/[...settings]/page.tsx'),
      ]),
    ),
    route('/*', 'meta-files/not-found.ts'),
  ]),
] satisfies RouteConfig;
