import {
  featureRouteInventory,
  resolveInventoryPath,
  routeRequiresAuth,
} from '@zero/shared';

describe('native route inventory', () => {
  it('keeps parity with active web route paths', () => {
    const expectedActivePaths = [
      '/',
      '/home',
      '/login',
      '/about',
      '/terms',
      '/pricing',
      '/privacy',
      '/contributors',
      '/hr',
      '/developer',
      '/mail',
      '/mail/:folder',
      '/mail/compose',
      '/mail/create',
      '/mail/under-construction/:path',
      '/settings',
      '/settings/appearance',
      '/settings/connections',
      '/settings/danger-zone',
      '/settings/general',
      '/settings/labels',
      '/settings/categories',
      '/settings/notifications',
      '/settings/privacy',
      '/settings/security',
      '/settings/shortcuts',
      '/settings/*',
      '/*',
    ];

    const currentPaths = featureRouteInventory.map((route) => route.webPath);
    expect(currentPaths.sort()).toEqual(expectedActivePaths.sort());
  });

  it('marks mail and settings paths as auth-protected', () => {
    expect(routeRequiresAuth('/mail/inbox')).toBe(true);
    expect(routeRequiresAuth('/settings/general')).toBe(true);
    expect(routeRequiresAuth('/pricing')).toBe(false);
  });

  it('resolves dynamic inventory paths with defaults', () => {
    expect(resolveInventoryPath('/mail/:folder')).toBe('/mail/inbox');
    expect(resolveInventoryPath('/mail/under-construction/:path')).toBe(
      '/mail/under-construction/pending',
    );
  });
});
