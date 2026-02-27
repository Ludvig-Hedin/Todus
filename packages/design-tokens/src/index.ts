export type ColorMode = 'light' | 'dark';

export const typography = {
  family: {
    sans: 'Geist',
    mono: 'Geist Mono',
  },
  size: {
    xs: 12,
    sm: 14,
    md: 16,
    lg: 18,
    xl: 20,
    '2xl': 24,
  },
  lineHeight: {
    xs: 16,
    sm: 20,
    md: 24,
    lg: 28,
    xl: 30,
    '2xl': 34,
  },
} as const;

export const spacing = {
  px: 1,
  0: 0,
  1: 4,
  2: 8,
  3: 12,
  4: 16,
  5: 20,
  6: 24,
  8: 32,
  10: 40,
  12: 48,
  16: 64,
} as const;

export const radius = {
  sm: 4,
  md: 6,
  lg: 8,
  xl: 12,
} as const;

const semanticLight = {
  background: '#ffffff',
  foreground: '#09090b',
  card: '#ffffff',
  cardForeground: '#09090b',
  primary: '#18181b',
  primaryForeground: '#fafafa',
  secondary: '#f4f4f5',
  secondaryForeground: '#18181b',
  muted: '#f4f4f5',
  mutedForeground: '#71717a',
  accent: '#f4f4f5',
  accentForeground: '#18181b',
  destructive: '#e03f3f',
  destructiveForeground: '#fafafa',
  border: '#e4e4e7',
  input: '#e4e4e7',
  ring: '#09090b',
  sidebar: '#fafafa',
  sidebarForeground: '#3f3f46',
  panel: '#ffffff',
} as const;

const semanticDark = {
  background: '#121214',
  foreground: '#fafafa',
  card: '#18181b',
  cardForeground: '#fafafa',
  primary: '#fafafa',
  primaryForeground: '#18181b',
  secondary: '#27272a',
  secondaryForeground: '#fafafa',
  muted: '#27272a',
  mutedForeground: '#a1a1aa',
  accent: '#27272a',
  accentForeground: '#fafafa',
  destructive: '#7f1d1d',
  destructiveForeground: '#fafafa',
  border: '#2f2f33',
  input: '#27272a',
  ring: '#d4d4d8',
  sidebar: '#121214',
  sidebarForeground: '#f4f4f5',
  panel: '#1a1a1d',
} as const;

export const staticColors = {
  darkBackground: '#141414',
  lightBackground: '#ffffff',
  offsetDark: '#0a0a0a',
  offsetLight: '#f5f5f5',
  iconDark: '#898989',
  iconLight: '#6d6d6d',
  logout: '#d93036',
  mainBlue: '#437dfb',
  skyBlue: '#0066ff',
  shinyGray: '#a1a1a1',
} as const;

export const semanticColors = {
  light: semanticLight,
  dark: semanticDark,
} as const;

export type SemanticColorName = keyof typeof semanticLight;

export function getSemanticColor(mode: ColorMode, name: SemanticColorName): string {
  return semanticColors[mode][name];
}
