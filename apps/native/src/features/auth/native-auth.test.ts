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
    expect(parseAuthCallback('https://staging.0.email/mail/inbox')).toEqual({
      token: null,
      expiresAt: null,
    });
  });

  it('accepts only whitelisted hosts for in-app webview', () => {
    const hosts = ['staging.0.email', 'sapi.0.email'];

    expect(isAllowedWebUrl('https://staging.0.email/mail/inbox', hosts)).toBe(true);
    expect(isAllowedWebUrl('https://example.com/phishing', hosts)).toBe(false);
  });

  it('detects login and signed-in paths for auth guard transitions', () => {
    const origin = 'https://staging.0.email';

    expect(isLoginPath('https://staging.0.email/login', origin)).toBe(true);
    expect(isSignedInPath('https://staging.0.email/mail/inbox', origin)).toBe(true);
    expect(isSignedInPath('https://staging.0.email/privacy', origin)).toBe(false);
  });

  it('normalizes path from route URL', () => {
    expect(resolveWebPathFromUrl('https://staging.0.email/settings/general?tab=profile')).toBe(
      '/settings/general?tab=profile',
    );
  });
});
