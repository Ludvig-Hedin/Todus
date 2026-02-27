import {
  isAllowedWebUrl,
  isLoginPath,
  isSignedInPath,
  parseAuthCallback,
  resolveWebPathFromUrl,
} from './native-auth';

describe('native auth helpers', () => {
  it('parses bearer token and expiry from callback URL', () => {
    expect(parseAuthCallback('todus://auth-callback?token=abc&expiresAt=123')).toEqual({
      token: 'abc',
      expiresAt: 123,
    });
  });

  it('returns null values when callback has no token', () => {
    expect(parseAuthCallback('https://todus.app/mail/inbox')).toEqual({
      token: null,
      expiresAt: null,
    });
  });

  it('accepts only whitelisted hosts for in-app webview', () => {
    const hosts = ['todus.app', 'api.todus.app'];

    expect(isAllowedWebUrl('https://todus.app/mail/inbox', hosts)).toBe(true);
    expect(isAllowedWebUrl('https://example.com/phishing', hosts)).toBe(false);
  });

  it('detects login and signed-in paths for auth guard transitions', () => {
    const origin = 'https://todus.app';

    expect(isLoginPath('https://todus.app/login', origin)).toBe(true);
    expect(isSignedInPath('https://todus.app/mail/inbox', origin)).toBe(true);
    expect(isSignedInPath('https://todus.app/privacy', origin)).toBe(false);
  });

  it('normalizes path from route URL', () => {
    expect(resolveWebPathFromUrl('https://todus.app/settings/general?tab=profile')).toBe(
      '/settings/general?tab=profile',
    );
  });
});
