/**
 * SVG icons for auth providers and branding.
 * Used on the login screen for OAuth provider buttons.
 */
import * as React from 'react';
import Svg, { Path, SvgProps } from 'react-native-svg';

export const Google = (props: SvgProps) => (
  <Svg width="1em" height="1em" viewBox="0 0 24 24" {...props}>
    <Path
      fill="currentColor"
      d="M11.99 13.9v-3.72h9.36c.14.63.25 1.22.25 2.05c0 5.71-3.83 9.77-9.6 9.77c-5.52 0-10-4.48-10-10S6.48 2 12 2c2.7 0 4.96.99 6.69 2.61l-2.84 2.76c-.72-.68-1.98-1.48-3.85-1.48c-3.31 0-6.01 2.75-6.01 6.12s2.7 6.12 6.01 6.12c3.83 0 5.24-2.65 5.5-4.22h-5.51z"
    />
  </Svg>
);

export const Microsoft = (props: SvgProps) => (
  <Svg viewBox="0 0 448 512" {...props}>
    <Path
      d="M0 32h214.6v214.6H0V32zm233.4 0H448v214.6H233.4V32zM0 265.4h214.6V480H0V265.4zm233.4 0H448V480H233.4V265.4z"
      fill="currentColor"
    />
  </Svg>
);

export const LogoVector = (props: SvgProps) => (
  <Svg viewBox="0 0 100 100" {...props}>
    <Path
      fill="currentColor"
      d="M50 0C22.4 0 0 22.4 0 50s22.4 50 50 50 50-22.4 50-50S77.6 0 50 0zm0 88.9C28.5 88.9 11.1 71.5 11.1 50S28.5 11.1 50 11.1 88.9 28.5 88.9 50 71.5 88.9 50 88.9z"
    />
    <Path
      fill="currentColor"
      d="M50 25c-13.8 0-25 11.2-25 25s11.2 25 25 25 25-11.2 25-25-11.2-25-25-25zm0 38.9c-7.7 0-13.9-6.2-13.9-13.9S42.3 36.1 50 36.1 63.9 42.3 63.9 50 57.7 63.9 50 63.9z"
    />
  </Svg>
);

export const GoogleColored = (props: SvgProps) => (
  <Svg width="1em" height="1em" viewBox="0 0 24 24" {...props}>
    <Path
      fill="#4285F4"
      d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"
    />
    <Path
      fill="#34A853"
      d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-1 .67-2.27 1.07-3.71 1.07-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"
    />
    <Path
      fill="#FBBC05"
      d="M5.84 14.11c-.22-.66-.35-1.36-.35-2.11s.13-1.45.35-2.11V7.05H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.95l3.66-2.84z"
    />
    <Path
      fill="#EA4335"
      d="M12 5.38c1.62 0 3.06.56 4.21 1.66l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.05l3.66 2.84c.87-2.6 3.3-4.51 6.16-4.51z"
    />
  </Svg>
);
