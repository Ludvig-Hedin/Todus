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
